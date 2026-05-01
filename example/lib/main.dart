import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[flutter-error] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint('${details.stack}');
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[platform-error] $error');
    debugPrint('$stack');
    return false;
  };

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniAudio Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PlayerShell(),
    );
  }
}

enum EqScreenMode {
  multibandEq('Enable Multiband EQ'),
  mixEq('Enable Mix EQ');

  const EqScreenMode(this.label);
  final String label;
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final IsolateAudioPlayer _player = IsolateAudioPlayer();
  final TextEditingController _singleUrlController = TextEditingController();
  final TextEditingController _multiUrlController = TextEditingController();
  final ValueNotifier<PlayerStatus> _status = ValueNotifier(
    const PlayerStatus(
      positionSeconds: 0,
      durationSeconds: 0,
      isPlaying: false,
      currentIndex: -1,
      playlistCount: 0,
      shuffleEnabled: false,
      loopMode: LoopMode.off,
    ),
  );

  final List<AudioSource> _playlist = <AudioSource>[];
  final List<String> _logs = <String>[];
  int _tabIndex = 0;
  int _lazyLoadSession = 0;
  bool _nativeNetworkStreamingSupported = false;
  bool _allowInvalidTlsForDownloads = false;
  final bool _systemMediaControlsEnabled = false;
  int _lastPublishedNowPlayingIndex = -1;

  bool _eqEnabled = false;
  final bool _crossfeedEnabled = false;
  final int _crossfeedPreset = 1;

  bool _reverbEnabled = false;
  bool _lowpassEnabled = false;
  bool _highpassEnabled = false;
  bool _bandpassEnabled = false;
  bool _peakEqEnabled = false;
  bool _notchEnabled = false;
  bool _lowshelfEnabled = false;
  bool _highshelfEnabled = false;
  bool _delayEnabled = false;

  // Advanced Audio State
  EqScreenMode _eqMode = EqScreenMode.multibandEq;
  bool _multibandEqEnabled = false;
  bool _mixEqEnabled = false;
  final List<double> _eqBandGains = List.filled(10, 0.0);
  final List<double> _eqFrequencies = const [
    31.25,
    62.5,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000
  ];
  late final List<EqBandConfig> _mixedEqBands = _buildMixedEqBands();
  AudioFormat _outputFormat = AudioFormat.f32;
  int _outputSampleRate = 0; // 0=Native
  int _outputChannels = 2; // Stereo
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 250;

  double _low = 1.0;
  double _mid = 1.0;
  double _high = 1.0;
  double _gain = 1.0;
  double _pan = 0.0;
  double _pitch = 1.0;

  bool _spatEnabled = false;
  double _spatX = 0.0;
  double _spatY = 0.0;
  double _spatZ = 0.0;

  double _lpCutoff = 12000;
  double _hpCutoff = 80;
  double _bpCutoff = 1000;
  double _bpQ = 0.707;
  double _peakFreq = 1000;
  double _peakQ = 1.0;
  double _peakGainDb = 0.0;
  double _notchFreq = 1000;
  double _notchQ = 1.0;
  double _lowshelfFreq = 200;
  double _lowshelfSlope = 1.0;
  double _lowshelfGainDb = 0.0;
  double _highshelfFreq = 4000;
  double _highshelfSlope = 1.0;
  double _highshelfGainDb = 0.0;
  double _rvMix = 0.15;
  double _rvFeedback = 0.65;
  double _rvDelay = 95;
  double _dlMix = 0.2;
  double _dlFeedback = 0.35;
  double _dlDelay = 240;

  bool _stereoWidenEnabled = false;
  bool _crossfeedEnabled = false;
  int _crossfeedPreset = 0;
  double _stereoWidenWidth = 1.5;
  double _stereoWidenDelayMs = 15.0;

  bool _customLpf1Enabled = false;
  double _customLpf1Cutoff = 1000.0;
  bool _customHpf1Enabled = false;
  double _customHpf1Cutoff = 80.0;

  bool _customBiquadEnabled = false;
  double _bqB0 = 1.0;
  double _bqB1 = 0.0;
  double _bqB2 = 0.0;
  final double _bqA0 = 1.0;
  double _bqA1 = 0.0;
  double _bqA2 = 0.0;

  int _resampleAlgIndex = 0;
  int _ditherModeIndex = 0;

  // Limiter & Clipping Detection
  bool _limiterEnabled = false;
  double _limiterThreshold = 0.95;
  double _limiterAttackMs = 2.0;
  double _limiterReleaseMs = 50.0;
  bool _clipDetectionEnabled = false;
  int _clippedSamples = 0;
  Timer? _clipPollTimer;

  bool _analyzerEnabled = false;
  int _analyzerFrameSize = 512;
  StreamSubscription<Float32List>? _analyzerSub;
  List<double> _analyzerValues = List<double>.filled(96, 0.0);

  @override
  void initState() {
    super.initState();
    // Initialize the engine with defaults
    _player.init(enableSystemAudio: true);

    // Initialize the multiband EQ (safe to call even if unnecessary, but good practice)
    _player.initMultibandEq(_eqFrequencies);
    _nativeNetworkStreamingSupported = _player.isNetworkStreamingSupported();
    _logs.insert(
      0,
      _nativeNetworkStreamingSupported
          ? '[init] Native URL byte-streaming: enabled'
          : '[init] Native URL byte-streaming: disabled (download fallback for URLs)',
    );
    final initErr = _player.getLastError();
    if (initErr.isNotEmpty) {
      _logs.insert(0, '[init] $initErr');
    }
    _player.statusStream.listen((s) {
      _status.value = s;
      _publishNowPlayingFromStatus(s);
      // Removed setState to prevent full rebuilds on every status update
    });
    _player.logStream.listen((line) {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $line');
      if (_logs.length > 200) {
        _logs.removeRange(200, _logs.length);
      }
      if (mounted && _tabIndex == 2) {
        setState(() {}); // Only rebuild if Logs tab is active
      }
    });

    _player.configureAnalyzer(frameSize: _analyzerFrameSize);
    _analyzerSub = _player.analyzerStream.listen((frame) {
      if (frame.isEmpty) return;
      const targetBins = 96;
      final bins = List<double>.filled(targetBins, 0.0);
      final srcLen = frame.length;
      for (var i = 0; i < targetBins; i++) {
        final from = (i * srcLen / targetBins).floor();
        final to = ((i + 1) * srcLen / targetBins).ceil();
        var sum = 0.0;
        var count = 0;
        for (var j = from; j < to && j < srcLen; j++) {
          sum += frame[j].abs();
          count++;
        }
        bins[i] = count > 0 ? sum / count : 0.0;
      }
      if (!mounted) return;
      setState(() {
        _analyzerValues = bins;
      });
    });

    if (Platform.isAndroid) {
      unawaited(_ensureNotificationPermission());
    }
  }

  List<EqBandConfig> _buildMixedEqBands() {
    const types = <EqBandType>[
      EqBandType.lowshelf,
      EqBandType.peak,
      EqBandType.notch,
      EqBandType.bandpass,
      EqBandType.peak,
      EqBandType.peak,
      EqBandType.notch,
      EqBandType.bandpass,
      EqBandType.peak,
      EqBandType.highshelf,
    ];
    return List<EqBandConfig>.generate(_eqFrequencies.length, (i) {
      return EqBandConfig(
        type: types[i],
        frequencyHz: _eqFrequencies[i],
        gainDb: _eqBandGains[i],
        q: 1.0,
        slope: 1.0,
        enabled: true,
      );
    });
  }

  void _applyMixEq() {
    _player.setMultibandEqEnabled(false);
    _player.initMultibandFx(_mixedEqBands, enabled: _mixEqEnabled);
  }

  void _updateMixEqBand(int index,
      {EqBandType? type, double? q, double? gain}) {
    final current = _mixedEqBands[index];
    _mixedEqBands[index] = EqBandConfig(
      type: type ?? current.type,
      frequencyHz: current.frequencyHz,
      q: q ?? current.q,
      gainDb: gain ?? current.gainDb,
      slope: current.slope,
      enabled: current.enabled,
    );
    _applyMixEq();
  }

  void _applyLimiter() {
    _player.setLimiterEnabled(_limiterEnabled);
    if (_limiterEnabled) {
      _player.setLimiterParams(
        threshold: _limiterThreshold,
        attackMs: _limiterAttackMs,
        releaseMs: _limiterReleaseMs,
      );
    }
  }

  void _setClipDetection(bool enabled) {
    _player.setClippingDetectionEnabled(enabled);
    if (enabled) {
      _clipPollTimer?.cancel();
      _clipPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        final count = _player.getClippedSamplesCount();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _clippedSamples = count);
        });
      });
    } else {
      _clipPollTimer?.cancel();
      _clipPollTimer = null;
    }
  }

  @override
  void dispose() {
    _singleUrlController.dispose();
    _multiUrlController.dispose();
    _analyzerSub?.cancel();
    _clipPollTimer?.cancel();
    _status.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureNotificationPermission() async {
    final notif = await Permission.notification.status;
    if (notif.isGranted) return;

    final req = await Permission.notification.request();
    if (!req.isGranted) {
      _logs.insert(
        0,
        '[permission] Notification permission denied. Media notification may not appear.',
      );
      if (req.isPermanentlyDenied) {
        _logs.insert(
          0,
          '[permission] Notification permission permanently denied. Open app settings.',
        );
      }
    }
  }

  void _publishNowPlayingFromStatus(PlayerStatus status) {
    final idx = status.currentIndex;
    if (idx < 0 || idx >= _playlist.length) return;
    if (idx == _lastPublishedNowPlayingIndex) return;

    final source = _playlist[idx];
    final title = _nameFromSource(source);
    final subtitle = _subtitleFromSource(source);
    _lastPublishedNowPlayingIndex = idx;

    unawaited(
      _player.updateNowPlaying(
        id: 'track_$idx',
        title: title,
        artist: subtitle,
        duration:
            Duration(milliseconds: (status.durationSeconds * 1000).round()),
      ),
    );
  }

  Uri? _parseInputToUri(String raw) {
    final text = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('<', '')
        .replaceAll('>', '');
    if (text.isEmpty) return null;

    final isWindowsDrivePath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(text);
    final isUncPath = text.startsWith('\\\\');
    if (isWindowsDrivePath || isUncPath) {
      return File(text).absolute.uri;
    }

    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (!uri.hasAuthority || uri.host.trim().isEmpty) return null;
      final host = uri.host.toLowerCase().trim();
      if (host == 'link' || host == 'your-link' || host == 'placeholder') {
        return null;
      }
      return uri;
    }

    if (uri.scheme == 'file') {
      return uri;
    }

    if (!uri.hasScheme) {
      return File(text).absolute.uri;
    }

    return null;
  }

  List<Uri> _parseInputUris(String rawList) {
    final seen = <String>{};
    final out = <Uri>[];
    final parts = rawList
        .split(RegExp(r'[\r\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final part in parts) {
      final uri = _parseInputToUri(part);
      if (uri == null) continue;
      final key = uri.toString();
      if (seen.add(key)) out.add(uri);
    }
    return out;
  }

  String? _safeFilePathFromUri(Uri uri) {
    if (uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  Future<AudioSource?> _sourceFromPickedFile(PlatformFile f) async {
    if (f.path != null && f.path!.isNotEmpty) {
      final file = File(f.path!);
      if (file.existsSync()) {
        return AudioSource.uri(file.uri);
      }
    }

    final cacheDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}miniaudiodart_pick_cache',
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = (() {
      final fromExt = f.extension?.trim();
      if (fromExt != null && fromExt.isNotEmpty) {
        return '.${fromExt.toLowerCase()}';
      }
      final fromName = f.name;
      final dot = fromName.lastIndexOf('.');
      if (dot > 0 && dot < fromName.length - 1) {
        return '.${fromName.substring(dot + 1).toLowerCase()}';
      }
      return '.bin';
    })();

    final out = File(
      '${cacheDir.path}${Platform.pathSeparator}pick_${DateTime.now().microsecondsSinceEpoch}_${f.name.hashCode}$ext',
    );

    if (f.readStream != null) {
      final sink = out.openWrite();
      try {
        await sink.addStream(f.readStream!);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (out.existsSync() && out.lengthSync() > 0) {
        return AudioSource.uri(out.uri);
      }
    }

    if (f.bytes != null && f.bytes!.isNotEmpty) {
      await out.writeAsBytes(f.bytes!, flush: true);
      if (out.existsSync() && out.lengthSync() > 0) {
        return AudioSource.uri(out.uri);
      }
    }

    _logs.insert(
      0,
      '[pick] Could not materialize: ${f.name} (no usable path/stream/bytes)',
    );
    return null;
  }

  Future<AudioSource?> _materializeSource(Uri uri) async {
    if (uri.scheme == 'file') {
      final filePath = _safeFilePathFromUri(uri);
      if (filePath == null || filePath.isEmpty) {
        _logs.insert(0, '[source] Invalid file URI: $uri');
        return null;
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        _logs.insert(0, '[source] Local file not found: ${file.path}');
        return null;
      }
      return AudioSource.uri(uri);
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      _logs.insert(0, '[source] Unsupported URI scheme: ${uri.scheme}');
      return null;
    }

    final supportsNativeNetwork = _player.isNetworkStreamingSupported();
    if (supportsNativeNetwork) {
      _logs.insert(0, '[source] Using native network source in playlist: $uri');
      return AudioSource.network(uri.toString());
    }

    _logs.insert(
        0, '[source] Downloading URL for playlist compatibility: $uri');

    final cacheDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}miniaudiodart_stream_cache',
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = () {
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp3')) return '.mp3';
      if (path.endsWith('.aac')) return '.aac';
      if (path.endsWith('.m4a')) return '.m4a';
      if (path.endsWith('.wav')) return '.wav';
      if (path.endsWith('.ogg')) return '.ogg';
      if (path.endsWith('.flac')) return '.flac';
      return '.mp3';
    }();

    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}stream_${DateTime.now().microsecondsSinceEpoch}$ext',
    );

    final client = HttpClient();
    if (_allowInvalidTlsForDownloads && uri.scheme == 'https') {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'MiniAudioDart/1.0 (Flutter)');
      req.headers.set('Accept', '*/*');

      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _logs.insert(0, '[source] HTTP ${res.statusCode}: $uri');
        return null;
      }

      final sink = file.openWrite();
      await sink.addStream(res);
      await sink.flush();
      await sink.close();

      return AudioSource.uri(file.uri);
    } on HandshakeException catch (e) {
      final message = e.toString();
      if (message.contains('CERTIFICATE_VERIFY_FAILED') &&
          message.contains('not yet valid')) {
        _logs.insert(
          0,
          '[source] TLS certificate date check failed. Verify device/system clock and timezone, then retry.',
        );
        if (!_allowInvalidTlsForDownloads) {
          _logs.insert(
            0,
            '[source] Tip: enable "Allow invalid TLS certs" in Logs tab for testing only.',
          );
        }
      }
      _logs.insert(0, '[source] Download failed: $e');
      return null;
    } catch (e) {
      _logs.insert(0, '[source] Download failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _playSingleUrl() async {
    final uri = _parseInputToUri(_singleUrlController.text);
    if (uri == null) {
      _logs.insert(
        0,
        '[source] Invalid input. Use a local path, file:// URI, or http(s) URL.',
      );
      setState(() {});
      return;
    }

    late final AudioSource src;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final supportsNativeNetwork = _player.isNetworkStreamingSupported();
      if (supportsNativeNetwork) {
        _logs.insert(0,
            '[source] URL input detected. Using native network source: $uri');
        src = AudioSource.network(uri.toString());
      } else {
        _logs.insert(
          0,
          '[source] URL input detected. Native URL byte-streaming is unavailable; using isolate pushStream fallback.',
        );
        src = AudioSource.network(uri.toString());
      }
    } else {
      final localSrc = await _materializeSource(uri);
      if (localSrc == null) {
        setState(() {});
        return;
      }
      src = localSrc;
    }

    setState(() {
      _playlist
        ..clear()
        ..add(src);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );
    _player.play();

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[url-play] $msg');
      setState(() {});
    }
  }

  Future<void> _setMultiUrlPlaylist() async {
    final uris = _parseInputUris(_multiUrlController.text);
    if (uris.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found. Use one per line.');
      setState(() {});
      return;
    }

    final resolved = await Future.wait(uris.map(_materializeSource));
    final sources = <AudioSource>[];
    for (final resolvedSrc in resolved) {
      if (resolvedSrc == null) continue;
      sources.add(resolvedSrc);
    }

    if (sources.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found after resolution.');
      setState(() {});
      return;
    }

    setState(() {
      _playlist
        ..clear()
        ..addAll(sources);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[sources-set] $msg');
      setState(() {});
    }
  }

  Future<void> _addMultiUrls() async {
    final uris = _parseInputUris(_multiUrlController.text);
    if (uris.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found to add.');
      setState(() {});
      return;
    }

    final resolved = await Future.wait(uris.map(_materializeSource));
    for (final src in resolved.whereType<AudioSource>()) {
      _playlist.add(src);
      _player.addAudioSource(src);
      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '[sources-add] $msg');
      }
    }
    setState(() {});
  }

  Future<void> _appendPickedFilesLazily(
    List<PlatformFile> files, {
    required int sessionTag,
    int? skipIndex,
    String logPrefix = '[lazy]',
  }) async {
    var added = 0;
    for (var i = 0; i < files.length; i++) {
      if (skipIndex != null && i == skipIndex) continue;
      if (!mounted || sessionTag != _lazyLoadSession) return;

      final src = await _sourceFromPickedFile(files[i]);
      if (src == null) continue;
      if (!mounted || sessionTag != _lazyLoadSession) return;

      _playlist.add(src);
      _player.addAudioSource(src);
      added++;

      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '$logPrefix $msg');
      }

      if (added % 5 == 0) {
        setState(() {});
      }
    }

    if (!mounted || sessionTag != _lazyLoadSession) return;
    _logs.insert(0, '$logPrefix Added $added tracks in background');
    setState(() {});
  }

  Future<void> _pickSongsAndSetPlaylist() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      withReadStream: true,
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    final sessionTag = ++_lazyLoadSession;
    AudioSource? firstSource;
    var firstIndex = -1;
    for (var i = 0; i < result.files.length; i++) {
      final src = await _sourceFromPickedFile(result.files[i]);
      if (src != null) {
        firstSource = src;
        firstIndex = i;
        break;
      }
    }

    if (firstSource == null) {
      _logs.insert(0, '[playlist] No playable picked files.');
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _playlist
        ..clear()
        ..add(firstSource!);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[playlist] $msg');
      setState(() {});
    }

    _logs.insert(
      0,
      '[lazy] Playlist ready instantly with 1 track. Loading remaining tracks in background...',
    );
    setState(() {});

    unawaited(
      _appendPickedFilesLazily(
        result.files,
        sessionTag: sessionTag,
        skipIndex: firstIndex,
        logPrefix: '[playlist-lazy]',
      ),
    );
  }

  Future<void> _pickFolderAndSetPlaylist() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final String? selectedDirectory =
        await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    final dir = Directory(selectedDirectory);
    if (!dir.existsSync()) return;

    final List<File> audioFiles = [];
    final extensions = ['.mp3', '.ogg', '.wav', '.flac', '.m4a', '.aac'];

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final lowerPath = entity.path.toLowerCase();
          if (extensions.any((ext) => lowerPath.endsWith(ext))) {
            audioFiles.add(entity);
          }
        }
      }
    } catch (e) {
      _logs.insert(0, '[folder] Error listing files: $e');
    }

    if (audioFiles.isEmpty) {
      _logs.insert(0, '[playlist] No playable files found in folder.');
      if (mounted) setState(() {});
      return;
    }

    // Convert to PlatformFiles to reuse _appendPickedFilesLazily logic or handle directly
    // Since we have Files, we can create AudioSources directly.

    final sources = audioFiles.map((f) => AudioSource.uri(f.uri)).toList();

    setState(() {
      _playlist
        ..clear()
        ..addAll(sources);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );
    _logs.insert(
      0,
      '[folder] Playlist ready with ${sources.length} tracks from ${dir.path}',
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[playlist] $msg');
      setState(() {});
    }
  }

  Future<void> _addSongs() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      withReadStream: true,
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    final sessionTag = ++_lazyLoadSession;
    _logs.insert(
      0,
      '[add-lazy] Adding ${result.files.length} picked songs in background...',
    );
    setState(() {});

    unawaited(
      _appendPickedFilesLazily(
        result.files,
        sessionTag: sessionTag,
        logPrefix: '[add-lazy]',
      ),
    );
  }

  String _nameFromSource(AudioSource source) {
    final uri = source.uri;
    if (uri.scheme == 'file') {
      final p = _safeFilePathFromUri(uri);
      if (p == null || p.isEmpty) {
        return uri.toString();
      }
      final sep = Platform.pathSeparator;
      final i = p.lastIndexOf(sep);
      return i >= 0 ? p.substring(i + 1) : p;
    }
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    return uri.toString();
  }

  String _subtitleFromSource(AudioSource source) {
    final uri = source.uri;
    if (uri.scheme == 'file') {
      final p = _safeFilePathFromUri(uri);
      return (p == null || p.isEmpty) ? uri.toString() : p;
    }
    return uri.toString();
  }

  Widget _buildPlayerScreen() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildInputSection(),
                const SizedBox(height: 8),
                ValueListenableBuilder<PlayerStatus>(
                  valueListenable: _status,
                  builder: (context, st, _) => _buildPlayerControls(st),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        Expanded(
          flex: 2,
          child: ValueListenableBuilder<PlayerStatus>(
            valueListenable: _status,
            builder: (context, st, _) => _buildPlaylist(st),
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickSongsAndSetPlaylist,
                      icon: const Icon(Icons.library_music),
                      label: const Text('Pick Files'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickFolderAndSetPlaylist,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pick Folder'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addSongs,
                      icon: const Icon(Icons.queue_music),
                      label: const Text('Add Songs'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              TextField(
                controller: _singleUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText:
                      'Single source (local path, file://, or http/https)',
                  hintText:
                      r'C:\Music\song.mp3  or  https://example.com/live.mp3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _playSingleUrl,
                      icon: const Icon(Icons.link),
                      label: const Text('Play URL'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      child: const Text('Stream'),
                      onPressed: () async {
                        final uri = _parseInputToUri(_singleUrlController.text);
                        if (uri == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid URL/path')),
                          );
                          return;
                        }

                        if (uri.scheme == 'http' || uri.scheme == 'https') {
                          _logs.insert(
                            0,
                            '[stream] Direct push streaming disabled in demo for stability. Falling back to cached URL playback.',
                          );
                          if (mounted) setState(() {});
                        }

                        await _playSingleUrl();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _multiUrlController,
                keyboardType: TextInputType.multiline,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Multiple sources (one per line)',
                  hintText: 'C:\\Music\\a.mp3\nhttps://example.com/b.mp3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _setMultiUrlPlaylist,
                      icon: const Icon(
                        Icons.playlist_add_check_circle_outlined,
                      ),
                      label: const Text('Set URL Playlist'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addMultiUrls,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add URLs'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerControls(PlayerStatus st) {
    final duration = Duration(
      milliseconds: (st.durationSeconds * 1000).round(),
    );
    final position = Duration(
      milliseconds: (st.positionSeconds * 1000).round(),
    );
    final maxMs =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds <= 0 ? 0 : duration.inMilliseconds)
        .toDouble();
    final currentIndex = st.currentIndex;
    final currentTitle = (currentIndex >= 0 && currentIndex < _playlist.length)
        ? _nameFromSource(_playlist[currentIndex])
        : 'No track selected';
    final currentSubtitle =
        (currentIndex >= 0 && currentIndex < _playlist.length)
            ? _subtitleFromSource(_playlist[currentIndex])
            : 'Pick songs or set URL playlist';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            child: ListTile(
              leading: Icon(
                st.isPlaying ? Icons.graphic_eq : Icons.music_note_outlined,
              ),
              title: Text(
                currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                currentSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _systemMediaControlsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Slider(
                value: posMs,
                max: maxMs,
                onChanged: (v) {
                  _player.seekTo(Duration(milliseconds: v.toInt()));
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(_fmt(position)), Text(_fmt(duration))],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _player.seekToPrevious,
                iconSize: 32,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                onPressed: st.isPlaying ? _player.pause : _player.play,
                iconSize: 42,
                icon: Icon(
                  st.isPlaying ? Icons.pause_circle : Icons.play_circle,
                ),
              ),
              IconButton(
                onPressed: _player.seekToNext,
                iconSize: 32,
                icon: const Icon(Icons.skip_next),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () {
                  final enabled = !st.shuffleEnabled;
                  _player.setShuffleModeEnabled(enabled);
                },
                icon: Icon(
                  st.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                ),
              ),
              PopupMenuButton<LoopMode>(
                initialValue: st.loopMode,
                icon: Icon(_loopIcon(st.loopMode)),
                onSelected: _player.setLoopMode,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: LoopMode.off, child: Text('Loop Off')),
                  PopupMenuItem(value: LoopMode.all, child: Text('Loop All')),
                  PopupMenuItem(value: LoopMode.one, child: Text('Loop One')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylist(PlayerStatus st) {
    return ReorderableListView.builder(
      itemCount: _playlist.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final item = _playlist.removeAt(oldIndex);
        _playlist.insert(newIndex, item);
        _player.moveAudioSource(oldIndex, newIndex);
        setState(() {});
      },
      itemBuilder: (context, index) {
        final isCurrent = st.currentIndex == index;
        return ListTile(
          key: ValueKey('song_$index'),
          leading: Icon(isCurrent ? Icons.graphic_eq : Icons.music_note),
          title: Text(_nameFromSource(_playlist[index])),
          subtitle: Text(_subtitleFromSource(_playlist[index])),
          onTap: () => _player.seekTo(Duration.zero, index: index),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _player.removeAudioSourceAt(index);
              _playlist.removeAt(index);
              setState(() {});
            },
          ),
        );
      },
    );
  }

  Widget _buildAdvancedSettings() {
    return ExpansionTile(
      title: const Text('Advanced Audio Settings'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Output Format
              DropdownButtonFormField<AudioFormat>(
                initialValue: _outputFormat,
                decoration: const InputDecoration(labelText: 'Audio Format'),
                items: AudioFormat.values.map((f) {
                  return DropdownMenuItem(value: f, child: Text(f.name));
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _outputFormat = v);
                  _player.setOutputFormat(v);
                },
              ),
              const SizedBox(height: 8),
              // Sample Rate
              DropdownButtonFormField<int>(
                initialValue: _outputSampleRate,
                decoration: const InputDecoration(labelText: 'Sample Rate'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Native')),
                  DropdownMenuItem(value: 44100, child: Text('44100 Hz')),
                  DropdownMenuItem(value: 48000, child: Text('48000 Hz')),
                  DropdownMenuItem(value: 96000, child: Text('96000 Hz')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _outputSampleRate = v);
                  _player.setOutputSampleRate(v);
                },
              ),
              // Mono/Stereo
              SwitchListTile(
                title: const Text('Stereo Output'),
                subtitle: Text(
                    _outputChannels == 2 ? '2 Channels' : '1 Channel (Mono)'),
                value: _outputChannels == 2,
                onChanged: (v) {
                  setState(() => _outputChannels = v ? 2 : 1);
                  _player.setOutputChannels(_outputChannels);
                },
              ),
              const Divider(height: 16),
              SwitchListTile(
                title: const Text('Enable Crossfade'),
                subtitle: Text(
                    'Transition fade between tracks ($_crossfadeDurationMs ms)'),
                value: _crossfadeEnabled,
                onChanged: (v) {
                  setState(() => _crossfadeEnabled = v);
                  _player.setCrossfadeEnabled(v);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Crossfade Duration: $_crossfadeDurationMs ms'),
                subtitle: Slider(
                  value: _crossfadeDurationMs.toDouble(),
                  min: 0,
                  max: 10000,
                  divisions: 100,
                  onChanged: (v) {
                    final next = v.round();
                    setState(() => _crossfadeDurationMs = next);
                    _player.setCrossfadeDurationMs(next);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEqScreen() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildAdvancedSettings(),
        const Divider(),
        DropdownButtonFormField<EqScreenMode>(
          initialValue: _eqMode,
          decoration: const InputDecoration(
            labelText: 'EQ mode',
            border: OutlineInputBorder(),
          ),
          items: EqScreenMode.values
              .map(
                (mode) => DropdownMenuItem<EqScreenMode>(
                  value: mode,
                  child: Text(mode.label),
                ),
              )
              .toList(),
          onChanged: (mode) {
            if (mode == null) return;
            setState(() {
              _eqMode = mode;
              if (mode == EqScreenMode.multibandEq) {
                _mixEqEnabled = false;
                _player.setMultibandFxEnabled(false);
              } else {
                _multibandEqEnabled = false;
                _player.setMultibandEqEnabled(false);
              }
            });
          },
        ),
        const SizedBox(height: 8),
        if (_eqMode == EqScreenMode.multibandEq) ...[
          SwitchListTile(
            title: const Text('Enable 10-Band EQ'),
            value: _multibandEqEnabled,
            onChanged: (v) {
              setState(() => _multibandEqEnabled = v);
              if (v) {
                _mixEqEnabled = false;
                _player.setMultibandFxEnabled(false);
              }
              _player.setMultibandEqEnabled(v);
              if (v) {
                _player.initMultibandEq(_eqFrequencies);
                for (int i = 0; i < _eqFrequencies.length; ++i) {
                  _player.setMultibandEqBandGain(i, _eqBandGains[i]);
                }
              }
            },
          ),
          if (_multibandEqEnabled)
            SizedBox(
              height: 300,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _eqFrequencies.length,
                itemBuilder: (context, index) {
                  final freq = _eqFrequencies[index];
                  final label = freq >= 1000
                      ? '${(freq / 1000).toStringAsFixed(1)}k'
                      : '${freq.toInt()}';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: _eqBandGains[index],
                            min: -12.0,
                            max: 12.0,
                            onChanged: (v) {
                              setState(() => _eqBandGains[index] = v);
                              _player.setMultibandEqBandGain(index, v);
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${_eqBandGains[index].toStringAsFixed(1)} dB',
                        style: const TextStyle(fontSize: 10),
                      ),
                      Text(label, style: const TextStyle(fontSize: 10)),
                    ],
                  );
                },
              ),
            ),
        ] else ...[
          SwitchListTile(
            title: const Text('Enable Mix EQ'),
            value: _mixEqEnabled,
            onChanged: (v) {
              setState(() {
                _mixEqEnabled = v;
                if (v) {
                  _multibandEqEnabled = false;
                  _player.setMultibandEqEnabled(false);
                }
              });
              _applyMixEq();
            },
          ),
          if (_mixEqEnabled)
            ListView.builder(
              itemCount: _mixedEqBands.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final band = _mixedEqBands[index];
                final freq = band.frequencyHz;
                final label = freq >= 1000
                    ? '${(freq / 1000).toStringAsFixed(1)}k'
                    : freq.toStringAsFixed(2);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Band ${index + 1} • $label Hz'),
                        DropdownButton<EqBandType>(
                          value: band.type,
                          items: EqBandType.values
                              .map(
                                (t) => DropdownMenuItem<EqBandType>(
                                  value: t,
                                  child: Text(t.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(
                                () => _updateMixEqBand(index, type: value));
                          },
                        ),
                        Text('Q: ${band.q.toStringAsFixed(2)}'),
                        Slider(
                          value: band.q,
                          min: 0.1,
                          max: 18.0,
                          divisions: 179,
                          onChanged: (v) {
                            setState(() => _updateMixEqBand(index, q: v));
                          },
                        ),
                        Text('Gain: ${band.gainDb.toStringAsFixed(1)} dB'),
                        Slider(
                          value: band.gainDb,
                          min: -12.0,
                          max: 12.0,
                          divisions: 48,
                          onChanged: (v) {
                            setState(() {
                              _eqBandGains[index] = v;
                              _updateMixEqBand(index, gain: v);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Realtime Analyzer'),
          subtitle: const Text('Raw frame values for chart visualization'),
          value: _analyzerEnabled,
          onChanged: (v) {
            setState(() => _analyzerEnabled = v);
            _player.setAnalyzerEnabled(v);
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: _analyzerFrameSize,
          decoration: const InputDecoration(
            labelText: 'Analyzer frame size',
            border: OutlineInputBorder(),
          ),
          items: const [256, 512, 1024, 2048]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v samples')))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _analyzerFrameSize = v);
            _player.configureAnalyzer(frameSize: v);
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildAnalyzerChart(),
            ),
          ),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable 3-Band EQ'),
          value: _eqEnabled,
          onChanged: (v) {
            setState(() => _eqEnabled = v);
            _player.setEqEnabled(v);
          },
        ),
        _slider('Low', _low, 0, 4, (v) {
          setState(() => _low = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        _slider('Mid', _mid, 0, 4, (v) {
          setState(() => _mid = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        _slider('High', _high, 0, 4, (v) {
          setState(() => _high = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        const Divider(),
        _slider('Gain', _gain, 0, 4, (v) {
          setState(() => _gain = v);
          _player.setGain(v);
        }),
        _slider('Pan', _pan, -1, 1, (v) {
          setState(() => _pan = v);
          _player.setPan(v);
        }),
        _slider('Pitch', _pitch, 0.1, 4.0, (v) {
          setState(() => _pitch = v);
          _player.setPitch(v);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Spatialization (3D Audio)'),
          value: _spatEnabled,
          onChanged: (v) {
            setState(() => _spatEnabled = v);
            _player.setSpatializationEnabled(v);
          },
        ),
        if (_spatEnabled) ...[
          _slider('Source X (Left/Right)', _spatX, -5, 5, (v) {
            setState(() => _spatX = v);
            _player.setPosition(x: _spatX, y: _spatY, z: _spatZ);
          }),
          _slider('Source Y (Up/Down)', _spatY, -5, 5, (v) {
            setState(() => _spatY = v);
            _player.setPosition(x: _spatX, y: _spatY, z: _spatZ);
          }),
          _slider('Source Z (Forward/Back)', _spatZ, -5, 5, (v) {
            setState(() => _spatZ = v);
            _player.setPosition(x: _spatX, y: _spatY, z: _spatZ);
          }),
        ],
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Reverb'),
          value: _reverbEnabled,
          onChanged: (v) {
            setState(() => _reverbEnabled = v);
            _player.setReverbEnabled(v);
          },
        ),
        _slider('Reverb Mix', _rvMix, 0, 1, (v) {
          setState(() => _rvMix = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        _slider('Reverb Feedback', _rvFeedback, 0, 0.98, (v) {
          setState(() => _rvFeedback = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        _slider('Reverb Delay ms', _rvDelay, 20, 350, (v) {
          setState(() => _rvDelay = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Low-pass'),
          value: _lowpassEnabled,
          onChanged: (v) {
            setState(() => _lowpassEnabled = v);
            _player.setLowpass(enabled: v, cutoffHz: _lpCutoff);
          },
        ),
        _slider('Low-pass cutoff (Hz)', _lpCutoff, 20, 18000, (v) {
          setState(() => _lpCutoff = v);
          _player.setLowpass(enabled: _lowpassEnabled, cutoffHz: _lpCutoff);
        }),
        SwitchListTile(
          title: const Text('Enable High-pass'),
          value: _highpassEnabled,
          onChanged: (v) {
            setState(() => _highpassEnabled = v);
            _player.setHighpass(enabled: v, cutoffHz: _hpCutoff);
          },
        ),
        _slider('High-pass cutoff (Hz)', _hpCutoff, 10, 5000, (v) {
          setState(() => _hpCutoff = v);
          _player.setHighpass(enabled: _highpassEnabled, cutoffHz: _hpCutoff);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Band-pass'),
          value: _bandpassEnabled,
          onChanged: (v) {
            setState(() => _bandpassEnabled = v);
            _player.setBandpass(enabled: v, cutoffHz: _bpCutoff, q: _bpQ);
          },
        ),
        _slider('Band-pass cutoff (Hz)', _bpCutoff, 20, 18000, (v) {
          setState(() => _bpCutoff = v);
          _player.setBandpass(
            enabled: _bandpassEnabled,
            cutoffHz: _bpCutoff,
            q: _bpQ,
          );
        }),
        _slider('Band-pass Q', _bpQ, 0.1, 10.0, (v) {
          setState(() => _bpQ = v);
          _player.setBandpass(
            enabled: _bandpassEnabled,
            cutoffHz: _bpCutoff,
            q: _bpQ,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Peak EQ'),
          value: _peakEqEnabled,
          onChanged: (v) {
            setState(() => _peakEqEnabled = v);
            _player.setPeakEq(
              enabled: v,
              gainDb: _peakGainDb,
              q: _peakQ,
              frequencyHz: _peakFreq,
            );
          },
        ),
        _slider('Peak EQ Frequency (Hz)', _peakFreq, 20, 18000, (v) {
          setState(() => _peakFreq = v);
          _player.setPeakEq(
            enabled: _peakEqEnabled,
            gainDb: _peakGainDb,
            q: _peakQ,
            frequencyHz: _peakFreq,
          );
        }),
        _slider('Peak EQ Gain (dB)', _peakGainDb, -24, 24, (v) {
          setState(() => _peakGainDb = v);
          _player.setPeakEq(
            enabled: _peakEqEnabled,
            gainDb: _peakGainDb,
            q: _peakQ,
            frequencyHz: _peakFreq,
          );
        }),
        _slider('Peak EQ Q', _peakQ, 0.1, 10.0, (v) {
          setState(() => _peakQ = v);
          _player.setPeakEq(
            enabled: _peakEqEnabled,
            gainDb: _peakGainDb,
            q: _peakQ,
            frequencyHz: _peakFreq,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Notch'),
          value: _notchEnabled,
          onChanged: (v) {
            setState(() => _notchEnabled = v);
            _player.setNotch(enabled: v, q: _notchQ, frequencyHz: _notchFreq);
          },
        ),
        _slider('Notch Frequency (Hz)', _notchFreq, 20, 18000, (v) {
          setState(() => _notchFreq = v);
          _player.setNotch(
            enabled: _notchEnabled,
            q: _notchQ,
            frequencyHz: _notchFreq,
          );
        }),
        _slider('Notch Q', _notchQ, 0.1, 10.0, (v) {
          setState(() => _notchQ = v);
          _player.setNotch(
            enabled: _notchEnabled,
            q: _notchQ,
            frequencyHz: _notchFreq,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Low Shelf'),
          value: _lowshelfEnabled,
          onChanged: (v) {
            setState(() => _lowshelfEnabled = v);
            _player.setLowshelf(
              enabled: v,
              gainDb: _lowshelfGainDb,
              slope: _lowshelfSlope,
              frequencyHz: _lowshelfFreq,
            );
          },
        ),
        _slider('Low Shelf Frequency (Hz)', _lowshelfFreq, 20, 2000, (v) {
          setState(() => _lowshelfFreq = v);
          _player.setLowshelf(
            enabled: _lowshelfEnabled,
            gainDb: _lowshelfGainDb,
            slope: _lowshelfSlope,
            frequencyHz: _lowshelfFreq,
          );
        }),
        _slider('Low Shelf Gain (dB)', _lowshelfGainDb, -24, 24, (v) {
          setState(() => _lowshelfGainDb = v);
          _player.setLowshelf(
            enabled: _lowshelfEnabled,
            gainDb: _lowshelfGainDb,
            slope: _lowshelfSlope,
            frequencyHz: _lowshelfFreq,
          );
        }),
        _slider('Low Shelf Slope', _lowshelfSlope, 0.1, 2.0, (v) {
          setState(() => _lowshelfSlope = v);
          _player.setLowshelf(
            enabled: _lowshelfEnabled,
            gainDb: _lowshelfGainDb,
            slope: _lowshelfSlope,
            frequencyHz: _lowshelfFreq,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable High Shelf'),
          value: _highshelfEnabled,
          onChanged: (v) {
            setState(() => _highshelfEnabled = v);
            _player.setHighshelf(
              enabled: v,
              gainDb: _highshelfGainDb,
              slope: _highshelfSlope,
              frequencyHz: _highshelfFreq,
            );
          },
        ),
        _slider('High Shelf Frequency (Hz)', _highshelfFreq, 1000, 18000, (v) {
          setState(() => _highshelfFreq = v);
          _player.setHighshelf(
            enabled: _highshelfEnabled,
            gainDb: _highshelfGainDb,
            slope: _highshelfSlope,
            frequencyHz: _highshelfFreq,
          );
        }),
        _slider('High Shelf Gain (dB)', _highshelfGainDb, -24, 24, (v) {
          setState(() => _highshelfGainDb = v);
          _player.setHighshelf(
            enabled: _highshelfEnabled,
            gainDb: _highshelfGainDb,
            slope: _highshelfSlope,
            frequencyHz: _highshelfFreq,
          );
        }),
        _slider('High Shelf Slope', _highshelfSlope, 0.1, 2.0, (v) {
          setState(() => _highshelfSlope = v);
          _player.setHighshelf(
            enabled: _highshelfEnabled,
            gainDb: _highshelfGainDb,
            slope: _highshelfSlope,
            frequencyHz: _highshelfFreq,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Delay'),
          value: _delayEnabled,
          onChanged: (v) {
            setState(() => _delayEnabled = v);
            _player.setDelay(
              enabled: v,
              mix: _dlMix,
              feedback: _dlFeedback,
              delayMs: _dlDelay,
            );
          },
        ),
        _slider('Delay Mix', _dlMix, 0, 1, (v) {
          setState(() => _dlMix = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        _slider('Delay Feedback', _dlFeedback, 0, 0.98, (v) {
          setState(() => _dlFeedback = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        _slider('Delay Time ms', _dlDelay, 10, 1200, (v) {
          setState(() => _dlDelay = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Stereo Widen (M/S + Haas)'),
          value: _stereoWidenEnabled,
          onChanged: (v) {
            setState(() => _stereoWidenEnabled = v);
            _player.setStereoWiden(
              enabled: v,
              width: _stereoWidenWidth,
              delayMs: _stereoWidenDelayMs,
            );
          },
        ),
        _slider('Stereo Width', _stereoWidenWidth, 0.0, 5.0, (v) {
          setState(() => _stereoWidenWidth = v);
          _player.setStereoWiden(
            enabled: _stereoWidenEnabled,
            width: _stereoWidenWidth,
            delayMs: _stereoWidenDelayMs,
          );
        }),
        _slider('Haas Delay (ms)', _stereoWidenDelayMs, 0.0, 100.0, (v) {
          setState(() => _stereoWidenDelayMs = v);
          _player.setStereoWiden(
            enabled: _stereoWidenEnabled,
            width: _stereoWidenWidth,
            delayMs: _stereoWidenDelayMs,
          );
        }),

        const Divider(),
        SwitchListTile(
          title: const Text('Enable Crossfeed (Headphone Surround)'),
          value: _crossfeedEnabled,
          onChanged: (v) {
            setState(() => _crossfeedEnabled = v);
            _player.setCrossfeed(
              enabled: v,
              preset: _crossfeedPreset,
            );
          },
        ),
        _slider('Crossfeed Preset\n0=Joe0bloggs, 1=BS2B-Weak, 2=BS2B-Strong',
            _crossfeedPreset.toDouble(), 0, 2, (v) {
          int preset = v.round();
          setState(() => _crossfeedPreset = preset);
          _player.setCrossfeed(
            enabled: _crossfeedEnabled,
            preset: _crossfeedPreset,
          );
        }),

        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Standalone Continuous Filters',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Custom LPF1'),
          value: _customLpf1Enabled,
          onChanged: (v) {
            setState(() => _customLpf1Enabled = v);
            _player.setCustomLpf1(enabled: v, cutoffHz: _customLpf1Cutoff);
          },
        ),
        _slider('LPF1 Cutoff (Hz)', _customLpf1Cutoff, 20, 22000, (v) {
          setState(() => _customLpf1Cutoff = v);
          _player.setCustomLpf1(enabled: _customLpf1Enabled, cutoffHz: v);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Custom HPF1'),
          value: _customHpf1Enabled,
          onChanged: (v) {
            setState(() => _customHpf1Enabled = v);
            _player.setCustomHpf1(enabled: v, cutoffHz: _customHpf1Cutoff);
          },
        ),
        _slider('HPF1 Cutoff (Hz)', _customHpf1Cutoff, 10, 22000, (v) {
          setState(() => _customHpf1Cutoff = v);
          _player.setCustomHpf1(enabled: _customHpf1Enabled, cutoffHz: v);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Custom Biquad (Raw)'),
          value: _customBiquadEnabled,
          onChanged: (v) {
            setState(() => _customBiquadEnabled = v);
            _player.setCustomBiquad(
                enabled: v,
                b0: _bqB0,
                b1: _bqB1,
                b2: _bqB2,
                a0: _bqA0,
                a1: _bqA1,
                a2: _bqA2);
          },
        ),
        _slider('B0', _bqB0, -2.0, 2.0, (v) {
          setState(() => _bqB0 = v);
          _player.setCustomBiquad(
              enabled: _customBiquadEnabled,
              b0: v,
              b1: _bqB1,
              b2: _bqB2,
              a0: _bqA0,
              a1: _bqA1,
              a2: _bqA2);
        }),
        _slider('B1', _bqB1, -2.0, 2.0, (v) {
          setState(() => _bqB1 = v);
          _player.setCustomBiquad(
              enabled: _customBiquadEnabled,
              b0: _bqB0,
              b1: v,
              b2: _bqB2,
              a0: _bqA0,
              a1: _bqA1,
              a2: _bqA2);
        }),
        _slider('B2', _bqB2, -2.0, 2.0, (v) {
          setState(() => _bqB2 = v);
          _player.setCustomBiquad(
              enabled: _customBiquadEnabled,
              b0: _bqB0,
              b1: _bqB1,
              b2: v,
              a0: _bqA0,
              a1: _bqA1,
              a2: _bqA2);
        }),
        _slider('A1', _bqA1, -2.0, 2.0, (v) {
          setState(() => _bqA1 = v);
          _player.setCustomBiquad(
              enabled: _customBiquadEnabled,
              b0: _bqB0,
              b1: _bqB1,
              b2: _bqB2,
              a0: _bqA0,
              a1: v,
              a2: _bqA2);
        }),
        _slider('A2', _bqA2, -2.0, 2.0, (v) {
          setState(() => _bqA2 = v);
          _player.setCustomBiquad(
              enabled: _customBiquadEnabled,
              b0: _bqB0,
              b1: _bqB1,
              b2: _bqB2,
              a0: _bqA0,
              a1: _bqA1,
              a2: v);
        }),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Engine Resampling & Dither',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          title: const Text('Resampling Algorithm'),
          trailing: DropdownButton<int>(
            value: _resampleAlgIndex,
            items: const [
              DropdownMenuItem(value: 0, child: Text('miniaudio Linear')),
              DropdownMenuItem(value: 1, child: Text('srcSincBestQuality')),
              DropdownMenuItem(value: 2, child: Text('srcSincMediumQuality')),
              DropdownMenuItem(value: 3, child: Text('srcSincFastest')),
              DropdownMenuItem(value: 4, child: Text('srcZeroOrderHold')),
              DropdownMenuItem(value: 5, child: Text('srcLinear')),
              DropdownMenuItem(value: 6, child: Text('Custom')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _resampleAlgIndex = v);
                _player.setEngineResampleAlgorithm(v);
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Dither Mode'),
          trailing: DropdownButton<int>(
            value: _ditherModeIndex,
            items: const [
              DropdownMenuItem(value: 0, child: Text('None')),
              DropdownMenuItem(value: 1, child: Text('Rectangle')),
              DropdownMenuItem(value: 2, child: Text('Triangle')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _ditherModeIndex = v);
                _player.setEngineDitherMode(v);
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildAdvancedSettings(),
        const Divider(),
        // ── Soft Limiter ────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Soft Limiter',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Limiter'),
          secondary: const Icon(Icons.compress),
          value: _limiterEnabled,
          onChanged: (v) {
            setState(() => _limiterEnabled = v);
            _applyLimiter();
          },
        ),
        ListTile(
          title: const Text('Threshold'),
          subtitle: Slider(
            value: _limiterThreshold.clamp(0.1, 1.0),
            min: 0.1,
            max: 1.0,
            divisions: 90,
            label: _limiterThreshold.toStringAsFixed(2),
            onChanged: _limiterEnabled
                ? (v) {
                    setState(() => _limiterThreshold = v);
                    _applyLimiter();
                  }
                : null,
          ),
          trailing: Text(_limiterThreshold.toStringAsFixed(2)),
        ),
        ListTile(
          title: const Text('Attack (ms)'),
          subtitle: Slider(
            value: _limiterAttackMs.clamp(0.1, 100.0),
            min: 0.1,
            max: 100.0,
            divisions: 100,
            label: _limiterAttackMs.toStringAsFixed(1),
            onChanged: _limiterEnabled
                ? (v) {
                    setState(() => _limiterAttackMs = v);
                    _applyLimiter();
                  }
                : null,
          ),
          trailing: Text('${_limiterAttackMs.toStringAsFixed(1)} ms'),
        ),
        ListTile(
          title: const Text('Release (ms)'),
          subtitle: Slider(
            value: _limiterReleaseMs.clamp(10.0, 1000.0),
            min: 10.0,
            max: 1000.0,
            divisions: 99,
            label: _limiterReleaseMs.toStringAsFixed(0),
            onChanged: _limiterEnabled
                ? (v) {
                    setState(() => _limiterReleaseMs = v);
                    _applyLimiter();
                  }
                : null,
          ),
          trailing: Text('${_limiterReleaseMs.toStringAsFixed(0)} ms'),
        ),
        const Divider(),
        // ── Clipping Detection ───────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Clipping Detection',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Clipping Detection'),
          secondary: Icon(
            Icons.warning_amber_rounded,
            color: _clippedSamples > 0 ? Colors.red : null,
          ),
          subtitle: _clipDetectionEnabled
              ? Text(
                  'Clipped samples: $_clippedSamples',
                  style: TextStyle(
                    color: _clippedSamples > 0 ? Colors.red : null,
                    fontWeight: _clippedSamples > 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                )
              : null,
          value: _clipDetectionEnabled,
          onChanged: (v) {
            setState(() {
              _clipDetectionEnabled = v;
              if (!v) _clippedSamples = 0;
            });
            _setClipDetection(v);
          },
        ),
        if (_clipDetectionEnabled)
          ListTile(
            title: const Text('Reset Clip Counter'),
            trailing: FilledButton.tonal(
              onPressed: () {
                _player.resetClippedSamplesCount();
                setState(() => _clippedSamples = 0);
              },
              child: const Text('Reset'),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAnalyzerChart() {
    if (!_analyzerEnabled) {
      return const Center(
        child: Text('Enable Realtime Analyzer to view audio frame values.'),
      );
    }

    final spots = <FlSpot>[];
    final len = _analyzerValues.length;
    for (var i = 0; i < len; i++) {
      final normalized = (_analyzerValues[i] * 6.0).clamp(0.0, 1.0);
      spots.add(FlSpot(i.toDouble(), normalized));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, len - 1).toDouble(),
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.deepPurple,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.deepPurple.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  final msg = _player.getLastError();
                  _logs.insert(0, '[poll] ${msg.isEmpty ? "(no error)" : msg}');
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Poll Error'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _player.clearLastError();
                  _logs.insert(0, '[action] Cleared native error state');
                  setState(() {});
                },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Clear Native Error'),
              ),
              FilterChip(
                selected: _allowInvalidTlsForDownloads,
                label: const Text('Allow invalid TLS certs (test only)'),
                onSelected: (selected) {
                  setState(() => _allowInvalidTlsForDownloads = selected);
                  _logs.insert(
                    0,
                    selected
                        ? '[security] Invalid TLS cert acceptance enabled for fallback downloads.'
                        : '[security] Invalid TLS cert acceptance disabled.',
                  );
                },
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (_logs.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No logs to copy')),
                    );
                    return;
                  }

                  final text = _logs.reversed.join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${_logs.length} log lines')),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy Logs'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _logs.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear Log View'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _logs.isEmpty
              ? const Center(child: Text('No logs yet'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(_logs[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title: ${value.toStringAsFixed(2)}'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  IconData _loopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.all:
        return Icons.repeat_on;
      case LoopMode.one:
        return Icons.repeat_one_on;
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  Future<bool> _ensureMediaPermission() async {
    if (!Platform.isAndroid) return true;

    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;

    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;

    if (audio.isPermanentlyDenied || storage.isPermanentlyDenied) {
      _logs.insert(0, '[permission] Permanently denied. Open app settings.');
      await openAppSettings();
    }

    return false;
  }

  void _showPipelineInfo() {
    final state = player.pipelineState;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audio Pipeline State'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Input Source',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Format: ${state.inputFormatString}'),
              Text('Sample Rate: ${state.inputSampleRate} Hz'),
              Text('Channels: ${state.inputChannels}'),
              const SizedBox(height: 12),
              const Text('DSP Processing',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Format: ${state.processingFormatString}'),
              Text('Sample Rate: ${state.processingSampleRate} Hz'),
              Text('Channels: ${state.processingChannels}'),
              const SizedBox(height: 12),
              const Text('Hardware Output',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Format: ${state.outputFormatString}'),
              Text('Sample Rate: ${state.outputSampleRate} Hz'),
              Text('Channels: ${state.outputChannels}'),
              const SizedBox(height: 12),
              const Text('Active DSP Features',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('EQ: ${state.eqEnabled ? 'ON' : 'OFF'}'),
              Text('Reverb: ${state.reverbEnabled ? 'ON' : 'OFF'}'),
              Text('Limiter: ${state.limiterEnabled ? 'ON' : 'OFF'}'),
              Text('Stereo Widen: ${state.stereoWidenEnabled ? 'ON' : 'OFF'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MiniAudio Playlist Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showPipelineInfo,
            tooltip: 'Pipeline State',
          )
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [_buildPlayerScreen(), _buildEqScreen(), _buildLogsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.playlist_play),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.equalizer),
            label: 'Equalizer',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}
