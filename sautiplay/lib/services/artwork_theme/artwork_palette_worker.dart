import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'adaptive_theme_generator.dart';
import 'artwork_palette_models.dart';
import 'palette_personality_analyzer.dart';
import 'perceptual_color_analyzer.dart';

/// Result returned by [ArtworkPaletteWorker] containing the serialized-safe
/// perceptual analysis and performance metrics.
class WorkerExtractionResult {
  final ArtworkPaletteAnalysis analysis;
  final ArtworkExtractionMetrics metrics;

  const WorkerExtractionResult({
    required this.analysis,
    required this.metrics,
  });
}

/// Persistent background isolate worker for decoding, sampling, CIELAB K-Means++
/// clustering, personality analysis, and semantic theme generation.
///
/// Strictly isolated from SautiFlow's realtime audio engine and enforces bounded
/// concurrency (1 active job, 1 latest-wins foreground slot, up to 2 prefetch
/// slots).
class ArtworkPaletteWorker {
  bool useNativeCodec;

  ArtworkPaletteWorker({this.useNativeCodec = true});

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _receivePort;
  Completer<void>? _startingCompleter;

  int _nextJobId = 0;
  _PendingWorkerJob? _activeJob;
  _PendingWorkerJob? _pendingForeground;
  final List<_PendingWorkerJob> _prefetchQueue = <_PendingWorkerJob>[];
  bool _disposed = false;

  /// Whether the persistent worker isolate is currently spawned and ready.
  bool get isRunning => _isolate != null && _workerSendPort != null;

  /// Number of queued (not yet active) prefetch jobs.
  int get queuedPrefetchCount => _prefetchQueue.length;

  /// Submits a high-priority foreground extraction job. Any previously queued
  /// (not yet started) foreground job is immediately superseded (`null`).
  Future<WorkerExtractionResult?> extractForeground({
    required String artworkHash,
    required Uint8List artBytes,
    PaletteExtractionConfig config = const PaletteExtractionConfig(),
  }) {
    if (artBytes.isEmpty) return Future<WorkerExtractionResult?>.value(null);
    _disposed = false;

    // Remove duplicate prefetch if one was queued for the same artwork.
    _prefetchQueue.removeWhere((p) {
      if (p.artworkHash == artworkHash) {
        p.cancelled = true;
        if (!p.completer.isCompleted) p.completer.complete(null);
        return true;
      }
      return false;
    });

    if (_pendingForeground != null) {
      _pendingForeground!.cancelled = true;
      if (!_pendingForeground!.completer.isCompleted) {
        _pendingForeground!.completer.complete(null);
      }
      _pendingForeground = null;
    }

    final job = _PendingWorkerJob(
      jobId: ++_nextJobId,
      artworkHash: artworkHash,
      artBytes: artBytes,
      config: config,
      isForeground: true,
    );
    _pendingForeground = job;
    _schedulePump();
    return job.completer.future;
  }

  /// Enqueues a low-priority prefetch job (capped at 2 queued entries).
  Future<WorkerExtractionResult?> enqueuePrefetch({
    required String artworkHash,
    required Uint8List artBytes,
    PaletteExtractionConfig config = const PaletteExtractionConfig(),
  }) {
    if (artBytes.isEmpty || _disposed) {
      return Future<WorkerExtractionResult?>.value(null);
    }

    if (_activeJob?.artworkHash == artworkHash ||
        _pendingForeground?.artworkHash == artworkHash) {
      return Future<WorkerExtractionResult?>.value(null);
    }
    for (final existing in _prefetchQueue) {
      if (existing.artworkHash == artworkHash) {
        return existing.completer.future;
      }
    }

    while (_prefetchQueue.length >= 2) {
      final dropped = _prefetchQueue.removeAt(0);
      dropped.cancelled = true;
      if (!dropped.completer.isCompleted) {
        dropped.completer.complete(null);
      }
    }

    final job = _PendingWorkerJob(
      jobId: ++_nextJobId,
      artworkHash: artworkHash,
      artBytes: artBytes,
      config: config,
      isForeground: false,
    );
    _prefetchQueue.add(job);
    _schedulePump();
    return job.completer.future;
  }

  /// Cancels any queued (not yet running) work without killing the warm isolate.
  void cancelPending({bool includePrefetch = true}) {
    if (_pendingForeground != null) {
      _pendingForeground!.cancelled = true;
      if (!_pendingForeground!.completer.isCompleted) {
        _pendingForeground!.completer.complete(null);
      }
      _pendingForeground = null;
    }
    if (includePrefetch && _prefetchQueue.isNotEmpty) {
      for (final job in _prefetchQueue) {
        job.cancelled = true;
        if (!job.completer.isCompleted) {
          job.completer.complete(null);
        }
      }
      _prefetchQueue.clear();
    }
  }

  /// Permanently terminates the worker isolate and clears all pending jobs.
  Future<void> dispose() async {
    _disposed = true;
    cancelPending(includePrefetch: true);
    if (_activeJob != null) {
      _activeJob!.cancelled = true;
      if (!_activeJob!.completer.isCompleted) {
        _activeJob!.completer.complete(null);
      }
      _activeJob = null;
    }

    final sendPort = _workerSendPort;
    _workerSendPort = null;
    if (sendPort != null) {
      try {
        sendPort.send(const <String, Object?>{'type': 'shutdown'});
      } catch (_) {}
    }

    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    if (_startingCompleter != null && !_startingCompleter!.isCompleted) {
      _startingCompleter!.complete();
    }
    _startingCompleter = null;
  }

  void _schedulePump() {
    if (_activeJob != null || _disposed) return;
    unawaited(_pumpNext());
  }

  Future<void> _pumpNext() async {
    if (_activeJob != null || _disposed) return;

    final _PendingWorkerJob? nextJob;
    if (_pendingForeground != null) {
      nextJob = _pendingForeground;
      _pendingForeground = null;
    } else if (_prefetchQueue.isNotEmpty) {
      nextJob = _prefetchQueue.removeAt(0);
    } else {
      return;
    }

    if (nextJob == null || nextJob.cancelled) {
      _schedulePump();
      return;
    }

    _activeJob = nextJob;
    final totalSw = Stopwatch()..start();

    try {
      await _ensureStarted();
      if (_disposed || nextJob.cancelled || _workerSendPort == null) {
        if (!nextJob.completer.isCompleted) {
          nextJob.completer.complete(null);
        }
        return;
      }

      int nativeDecodeMs = 0;
      _DecodedRgbaBuffer? rgbaBuffer;
      if (useNativeCodec) {
        final decodeSw = Stopwatch()..start();
        rgbaBuffer = await _tryNativeCodecDecode(
          nextJob.artBytes,
          maxDimension: nextJob.config.targetDimension,
        );
        decodeSw.stop();
        nativeDecodeMs = decodeSw.elapsedMilliseconds;
      }

      if (_disposed || nextJob.cancelled || _workerSendPort == null) {
        if (!nextJob.completer.isCompleted) {
          nextJob.completer.complete(null);
        }
        return;
      }

      final Map<String, Object?> payload;
      final int workingBufferBytes;
      if (rgbaBuffer != null) {
        workingBufferBytes = rgbaBuffer.rgba.length;
        payload = <String, Object?>{
          'type': 'analyzeRgba',
          'jobId': nextJob.jobId,
          'artworkHash': nextJob.artworkHash,
          'width': rgbaBuffer.width,
          'height': rgbaBuffer.height,
          'nativeDecodeMs': nativeDecodeMs,
          'rgba': TransferableTypedData.fromList(<Uint8List>[rgbaBuffer.rgba]),
          'config': nextJob.config.toJson(),
        };
      } else {
        workingBufferBytes = nextJob.artBytes.length;
        payload = <String, Object?>{
          'type': 'analyzeEncoded',
          'jobId': nextJob.jobId,
          'artworkHash': nextJob.artworkHash,
          'bytes':
              TransferableTypedData.fromList(<Uint8List>[nextJob.artBytes]),
          'config': nextJob.config.toJson(),
        };
      }

      nextJob.workingBufferBytes = workingBufferBytes;
      nextJob.totalStopwatch = totalSw;
      _workerSendPort!.send(payload);
    } catch (_) {
      if (!nextJob.completer.isCompleted) {
        nextJob.completer.complete(null);
      }
      if (identical(_activeJob, nextJob)) {
        _activeJob = null;
      }
      _schedulePump();
    }
  }

  Future<void> _ensureStarted() async {
    if (_workerSendPort != null) return;
    if (_startingCompleter != null) {
      return _startingCompleter!.future;
    }

    final starting = Completer<void>();
    _startingCompleter = starting;
    final port = ReceivePort();
    _receivePort = port;

    port.listen((dynamic message) {
      if (message is SendPort) {
        _workerSendPort = message;
        if (!starting.isCompleted) starting.complete();
        return;
      }

      if (message is Map) {
        _handleWorkerReply(Map<String, Object?>.from(message));
      }
    });

    try {
      _isolate = await Isolate.spawn<SendPort>(
        _workerIsolateEntry,
        port.sendPort,
        debugName: 'SautiPlayArtworkPaletteWorker',
      );
      await starting.future;
    } catch (_) {
      if (!starting.isCompleted) starting.complete();
      _startingCompleter = null;
      rethrow;
    }
    _startingCompleter = null;
  }

  void _handleWorkerReply(Map<String, Object?> message) {
    final jobId = (message['jobId'] as num?)?.toInt();
    final active = _activeJob;
    if (active == null || active.jobId != jobId) {
      return;
    }
    _activeJob = null;

    try {
      active.totalStopwatch?.stop();
      if (active.cancelled || _disposed || message['ok'] != true) {
        if (!active.completer.isCompleted) {
          active.completer.complete(null);
        }
      } else {
        final analysisJson = Map<String, Object?>.from(
          message['analysis'] as Map,
        );
        final analysis = ArtworkPaletteAnalysis.fromJson(analysisJson);
        final metrics = ArtworkExtractionMetrics(
          artworkHash: active.artworkHash,
          cacheTier: 'miss',
          decodeMs: (message['decodeMs'] as num?)?.toInt() ?? 0,
          analysisMs: (message['analysisMs'] as num?)?.toInt() ?? 0,
          themeGenMs: (message['themeGenMs'] as num?)?.toInt() ?? 0,
          totalMs: active.totalStopwatch?.elapsedMilliseconds ?? 0,
          sampledPixelCount:
              (message['sampledPixelCount'] as num?)?.toInt() ?? 0,
          workingBufferBytes: active.workingBufferBytes,
        );
        if (!active.completer.isCompleted) {
          active.completer.complete(
            WorkerExtractionResult(analysis: analysis, metrics: metrics),
          );
        }
      }
    } catch (_) {
      if (!active.completer.isCompleted) {
        active.completer.complete(null);
      }
    } finally {
      _schedulePump();
    }
  }

  static Future<_DecodedRgbaBuffer?> _tryNativeCodecDecode(
    Uint8List bytes, {
    required int maxDimension,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) return null;

      final clampedMax = maxDimension.clamp(32, 512);
      int? targetW;
      int? targetH;
      if (w > clampedMax || h > clampedMax) {
        if (w >= h) {
          targetW = clampedMax;
          targetH = math.max(1, (h * clampedMax / w).round());
        } else {
          targetH = clampedMax;
          targetW = math.max(1, (w * clampedMax / h).round());
        }
      }

      codec = await descriptor.instantiateCodec(
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final rgba = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      return _DecodedRgbaBuffer(
        rgba: rgba,
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class _DecodedRgbaBuffer {
  final Uint8List rgba;
  final int width;
  final int height;

  const _DecodedRgbaBuffer({
    required this.rgba,
    required this.width,
    required this.height,
  });
}

class _PendingWorkerJob {
  final int jobId;
  final String artworkHash;
  final Uint8List artBytes;
  final PaletteExtractionConfig config;
  final bool isForeground;
  final Completer<WorkerExtractionResult?> completer =
      Completer<WorkerExtractionResult?>();

  bool cancelled = false;
  int workingBufferBytes = 0;
  Stopwatch? totalStopwatch;

  _PendingWorkerJob({
    required this.jobId,
    required this.artworkHash,
    required this.artBytes,
    required this.config,
    required this.isForeground,
  });
}

@pragma('vm:entry-point')
void _workerIsolateEntry(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  commandPort.listen((dynamic rawMessage) {
    if (rawMessage is! Map) return;
    final msg = Map<String, Object?>.from(rawMessage);
    final type = msg['type']?.toString();

    if (type == 'shutdown') {
      commandPort.close();
      return;
    }

    final jobId = (msg['jobId'] as num?)?.toInt() ?? 0;
    final artworkHash = msg['artworkHash']?.toString() ?? '';

    try {
      final configRaw = msg['config'];
      final config = configRaw is Map
          ? PaletteExtractionConfig.fromJson(
              Map<String, Object?>.from(configRaw),
            )
          : const PaletteExtractionConfig();

      List<AnalyzedColorCluster> clusters = const [];
      List<RankedAccentCandidate> rankedAccents = const [];
      int sampledPixelCount = 0;
      int decodeMs = 0;
      int analysisMs = 0;

      if (type == 'analyzeRgba') {
        final transferable = msg['rgba'] as TransferableTypedData;
        final rgba = transferable.materialize().asUint8List();
        final width = (msg['width'] as num).toInt();
        final height = (msg['height'] as num).toInt();
        decodeMs = (msg['nativeDecodeMs'] as num?)?.toInt() ?? 0;

        final analyzed = PerceptualColorAnalyzer.analyzeRgbaPixels(
          rgba,
          width,
          height,
          config: config,
        );
        if (analyzed == null) {
          mainSendPort.send(<String, Object?>{'jobId': jobId, 'ok': false});
          return;
        }
        clusters = analyzed.clusters;
        rankedAccents = analyzed.rankedAccents;
        sampledPixelCount = analyzed.sampledPixelCount;
        analysisMs = analyzed.analysisMs;
      } else if (type == 'analyzeEncoded') {
        final transferable = msg['bytes'] as TransferableTypedData;
        final bytes = transferable.materialize().asUint8List();

        final analyzed = PerceptualColorAnalyzer.analyzeEncodedBytes(
          bytes,
          config: config,
        );
        if (analyzed == null) {
          mainSendPort.send(<String, Object?>{'jobId': jobId, 'ok': false});
          return;
        }
        clusters = analyzed.clusters;
        rankedAccents = analyzed.rankedAccents;
        sampledPixelCount = analyzed.sampledPixelCount;
        decodeMs = analyzed.decodeMs;
        analysisMs = analyzed.analysisMs;
      } else {
        mainSendPort.send(<String, Object?>{'jobId': jobId, 'ok': false});
        return;
      }

      final themeSw = Stopwatch()..start();
      final personality = PalettePersonalityAnalyzer.analyze(clusters);
      final semanticPalette = AdaptiveThemeGenerator.generate(
        clusters: clusters,
        rankedAccents: rankedAccents,
        personality: personality,
      );
      themeSw.stop();

      final analysis = ArtworkPaletteAnalysis(
        artworkHash: artworkHash,
        algorithmVersion: AdaptiveThemeGenerator.kAlgorithmVersion,
        clusters: clusters,
        rankedAccents: rankedAccents,
        personality: personality,
        semanticPalette: semanticPalette,
      );

      mainSendPort.send(<String, Object?>{
        'jobId': jobId,
        'ok': true,
        'decodeMs': decodeMs,
        'analysisMs': analysisMs,
        'themeGenMs': themeSw.elapsedMilliseconds,
        'sampledPixelCount': sampledPixelCount,
        'analysis': analysis.toJson(),
      });
    } catch (_) {
      mainSendPort.send(<String, Object?>{'jobId': jobId, 'ok': false});
    }
  });
}
