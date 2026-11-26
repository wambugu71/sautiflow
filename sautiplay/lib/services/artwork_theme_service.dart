import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../database/app_database.dart';
import 'artwork_theme/adaptive_theme_generator.dart';
import 'artwork_theme/artwork_palette_models.dart';
import 'artwork_theme/artwork_palette_worker.dart';

/// Intelligent album-art color extraction, two-tier versioned caching, and
/// stale-result-protected adaptive theme engine.
///
/// Heavy image analysis runs in a persistent background Dart worker isolate
/// ([ArtworkPaletteWorker]), completely isolated from SautiFlow's realtime
/// audio engine and the Flutter UI isolate.
class ArtworkThemeService {
  ArtworkThemeService._();
  static final ArtworkThemeService instance = ArtworkThemeService._();

  static const int _maxL1CacheSize = 128;
  static const int _maxTrackKeyIndexSize = 256;

  final LinkedHashMap<String, ArtworkPaletteAnalysis> _l1Cache =
      LinkedHashMap<String, ArtworkPaletteAnalysis>();
  final LinkedHashMap<String, String> _trackKeyToHash =
      LinkedHashMap<String, String>();

  final ArtworkPaletteWorker _worker = ArtworkPaletteWorker();
  PaletteExtractionConfig _config = const PaletteExtractionConfig();
  AppDatabase? _database;
  Future<void>? _pendingPersist;

  final StreamController<ColorScheme> _schemeController =
      StreamController<ColorScheme>.broadcast();
  final StreamController<AdaptiveSemanticPalette> _semanticPaletteController =
      StreamController<AdaptiveSemanticPalette>.broadcast();

  Stream<ColorScheme> get onColorSchemeChanged => _schemeController.stream;
  Stream<AdaptiveSemanticPalette> get onSemanticPaletteChanged =>
      _semanticPaletteController.stream;

  ColorScheme? _currentScheme;
  ColorScheme? get currentScheme => _currentScheme;

  AdaptiveSemanticPalette? _currentSemanticPalette;
  AdaptiveSemanticPalette? get currentSemanticPalette =>
      _currentSemanticPalette;

  ArtworkPaletteAnalysis? _currentAnalysis;
  ArtworkPaletteAnalysis? get currentAnalysis => _currentAnalysis;

  ArtworkExtractionMetrics? _lastMetrics;
  ArtworkExtractionMetrics? get lastMetrics => _lastMetrics;

  bool _adaptiveModeActive = true;
  bool get isAdaptiveModeActive => _adaptiveModeActive;

  int _activeRequestId = 0;

  // Fast reference identity memo to avoid re-hashing identical byte buffers.
  Uint8List? _lastHashedBytesRef;
  String? _lastHashedDigest;

  int _l1Hits = 0;
  int _l2Hits = 0;
  int _cacheMisses = 0;

  int get l1Hits => _l1Hits;
  int get l2Hits => _l2Hits;
  int get cacheMisses => _cacheMisses;

  double get cacheHitRate {
    final total = _l1Hits + _l2Hits + _cacheMisses;
    if (total == 0) return 0.0;
    return (_l1Hits + _l2Hits) / total;
  }

  /// Attaches the persistent Drift database for L2 versioned palette caching.
  void attachDatabase(AppDatabase? database) {
    _database = database;
  }

  /// Synchronizes adaptive mode state. Switching away cancels queued work and
  /// invalidates any in-flight emissions.
  void setAdaptiveModeActive(bool active) {
    if (_adaptiveModeActive == active) return;
    _adaptiveModeActive = active;
    if (!active) {
      _activeRequestId++;
      _worker.cancelPending(includePrefetch: true);
    }
  }

  /// Invalidates in-flight results and cancels queued background extraction jobs.
  void cancelPending({bool includePrefetch = true}) {
    _activeRequestId++;
    _worker.cancelPending(includePrefetch: includePrefetch);
  }

  /// Computes a collision-resistant SHA-256 content hash for [bytes].
  static String computeArtworkHash(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  String _hashBytes(Uint8List bytes) {
    if (identical(_lastHashedBytesRef, bytes) && _lastHashedDigest != null) {
      return _lastHashedDigest!;
    }
    final digest = computeArtworkHash(bytes);
    _lastHashedBytesRef = bytes;
    _lastHashedDigest = digest;
    return digest;
  }

  /// Synchronously peeks into the L1 cache by [trackKey] or artwork hash.
  ColorScheme? peek(String trackKey) {
    final analysis = peekAnalysis(trackKey);
    if (analysis == null) return null;
    return _toColorScheme(analysis.semanticPalette, isDark: true);
  }

  /// Synchronously peeks into the L1 cache for full analysis data.
  ArtworkPaletteAnalysis? peekAnalysis(String trackKey) {
    if (trackKey.isEmpty) return null;
    final direct = _l1Cache[trackKey];
    if (direct != null) return direct;
    final mappedHash = _trackKeyToHash[trackKey];
    if (mappedHash == null) return null;
    return _l1Cache[mappedHash];
  }

  /// Extracts (or retrieves from cache) an intelligent semantic palette and
  /// emits updates if the request is still current and adaptive mode is active.
  Future<AdaptiveSemanticPalette> extractAdaptiveTheme({
    required String trackKey,
    required Uint8List? artBytes,
    bool isDark = true,
    bool isArtworkPending = false,
    bool respectModeGate = false,
  }) async {
    if (respectModeGate && !_adaptiveModeActive) {
      return _currentSemanticPalette ??
          AdaptiveThemeGenerator.fallbackPalette();
    }

    final requestId = ++_activeRequestId;
    final totalSw = Stopwatch()..start();

    if (artBytes == null || artBytes.isEmpty) {
      if (isArtworkPending && _currentSemanticPalette != null) {
        return _currentSemanticPalette!;
      }
      final fallback = AdaptiveThemeGenerator.fallbackPalette();
      totalSw.stop();
      _lastMetrics = ArtworkExtractionMetrics(
        artworkHash: trackKey,
        cacheTier: 'fallback',
        decodeMs: 0,
        analysisMs: 0,
        themeGenMs: 0,
        totalMs: totalSw.elapsedMilliseconds,
        sampledPixelCount: 0,
        workingBufferBytes: 0,
      );
      if (requestId == _activeRequestId &&
          (!respectModeGate || _adaptiveModeActive)) {
        _emitPalette(fallback, analysis: null, isDark: isDark);
      }
      return fallback;
    }

    final artworkHash = _hashBytes(artBytes);
    _linkTrackKey(trackKey, artworkHash);

    // 1. L1 true LRU in-memory cache check.
    final l1Hit = _getFromL1(artworkHash);
    if (l1Hit != null) {
      _l1Hits++;
      totalSw.stop();
      _lastMetrics = ArtworkExtractionMetrics(
        artworkHash: artworkHash,
        cacheTier: 'l1',
        decodeMs: 0,
        analysisMs: 0,
        themeGenMs: 0,
        totalMs: totalSw.elapsedMilliseconds,
        sampledPixelCount: 0,
        workingBufferBytes: 0,
      );
      if (requestId == _activeRequestId &&
          (!respectModeGate || _adaptiveModeActive)) {
        _emitPalette(l1Hit.semanticPalette, analysis: l1Hit, isDark: isDark);
      }
      return l1Hit.semanticPalette;
    }

    // 2. L2 persistent Drift versioned cache check.
    final l2Hit = await _readFromL2(artworkHash);
    if (l2Hit != null) {
      _putInL1(artworkHash, l2Hit);
      _l2Hits++;
      totalSw.stop();
      _lastMetrics = ArtworkExtractionMetrics(
        artworkHash: artworkHash,
        cacheTier: 'l2',
        decodeMs: 0,
        analysisMs: 0,
        themeGenMs: 0,
        totalMs: totalSw.elapsedMilliseconds,
        sampledPixelCount: 0,
        workingBufferBytes: 0,
      );
      if (requestId == _activeRequestId &&
          (!respectModeGate || _adaptiveModeActive)) {
        _emitPalette(l2Hit.semanticPalette, analysis: l2Hit, isDark: isDark);
      }
      return l2Hit.semanticPalette;
    }

    // Abort before waking worker if superseded while awaiting L2 I/O.
    if (requestId != _activeRequestId ||
        (respectModeGate && !_adaptiveModeActive)) {
      return _currentSemanticPalette ??
          AdaptiveThemeGenerator.fallbackPalette();
    }

    // 3. Cache miss -> run extraction on the persistent background worker.
    // Visual continuity: preserve the currently valid theme while processing.
    _cacheMisses++;
    try {
      final result = await _worker.extractForeground(
        artworkHash: artworkHash,
        artBytes: artBytes,
        config: _config,
      );

      if (result == null) {
        if (requestId != _activeRequestId ||
            (respectModeGate && !_adaptiveModeActive)) {
          return _currentSemanticPalette ??
              AdaptiveThemeGenerator.fallbackPalette();
        }
        // Preserve existing valid theme on failure; fall back only if none set.
        if (_currentSemanticPalette != null) {
          return _currentSemanticPalette!;
        }
        final fallback = AdaptiveThemeGenerator.fallbackPalette();
        _emitPalette(fallback, analysis: null, isDark: isDark);
        return fallback;
      }

      // Always cache valid results even if the user skipped mid-extraction.
      _putInL1(artworkHash, result.analysis);
      unawaited(_persistToL2(artworkHash, result.analysis));

      totalSw.stop();
      _lastMetrics = ArtworkExtractionMetrics(
        artworkHash: artworkHash,
        cacheTier: 'miss',
        decodeMs: result.metrics.decodeMs,
        analysisMs: result.metrics.analysisMs,
        themeGenMs: result.metrics.themeGenMs,
        totalMs: totalSw.elapsedMilliseconds,
        sampledPixelCount: result.metrics.sampledPixelCount,
        workingBufferBytes: result.metrics.workingBufferBytes,
      );

      if (requestId == _activeRequestId &&
          (!respectModeGate || _adaptiveModeActive)) {
        _emitPalette(
          result.analysis.semanticPalette,
          analysis: result.analysis,
          isDark: isDark,
        );
      }
      return result.analysis.semanticPalette;
    } catch (e) {
      debugPrint('[ArtworkThemeService] Extraction error: $e');
      if (_currentSemanticPalette != null) {
        return _currentSemanticPalette!;
      }
      final fallback = AdaptiveThemeGenerator.fallbackPalette();
      if (requestId == _activeRequestId &&
          (!respectModeGate || _adaptiveModeActive)) {
        _emitPalette(fallback, analysis: null, isDark: isDark);
      }
      return fallback;
    }
  }

  /// Backwards-compatible entrypoint returning a Flutter [ColorScheme].
  Future<ColorScheme> extractAndEmit({
    required String trackKey,
    required Uint8List? artBytes,
    bool isDark = true,
    bool isArtworkPending = false,
    bool respectModeGate = false,
  }) async {
    final palette = await extractAdaptiveTheme(
      trackKey: trackKey,
      artBytes: artBytes,
      isDark: isDark,
      isArtworkPending: isArtworkPending,
      respectModeGate: respectModeGate,
    );
    return _toColorScheme(palette, isDark: isDark);
  }

  /// Silently pre-extracts and caches an upcoming track's palette in the
  /// background without emitting to UI streams.
  Future<void> prefetch({
    required String trackKey,
    required Uint8List? artBytes,
    bool isDark = true,
  }) async {
    if (!_adaptiveModeActive) return;
    if (artBytes == null || artBytes.isEmpty || trackKey.isEmpty) return;

    final artworkHash = _hashBytes(artBytes);
    _linkTrackKey(trackKey, artworkHash);

    if (_l1Cache.containsKey(artworkHash)) return;

    final l2Hit = await _readFromL2(artworkHash);
    if (l2Hit != null) {
      _putInL1(artworkHash, l2Hit);
      return;
    }

    if (!_adaptiveModeActive) return;

    try {
      final result = await _worker.enqueuePrefetch(
        artworkHash: artworkHash,
        artBytes: artBytes,
        config: _config,
      );
      if (result != null) {
        _putInL1(artworkHash, result.analysis);
        unawaited(_persistToL2(artworkHash, result.analysis));
      }
    } catch (_) {}
  }

  void _emitPalette(
    AdaptiveSemanticPalette palette, {
    required ArtworkPaletteAnalysis? analysis,
    required bool isDark,
  }) {
    _currentSemanticPalette = palette;
    _currentAnalysis = analysis;
    final scheme = _toColorScheme(palette, isDark: isDark);
    _currentScheme = scheme;
    _semanticPaletteController.add(palette);
    _schemeController.add(scheme);
  }

  ArtworkPaletteAnalysis? _getFromL1(String hash) {
    final existing = _l1Cache.remove(hash);
    if (existing != null) {
      _l1Cache[hash] = existing;
    }
    return existing;
  }

  void _putInL1(String hash, ArtworkPaletteAnalysis analysis) {
    _l1Cache.remove(hash);
    if (_l1Cache.length >= _maxL1CacheSize) {
      _l1Cache.remove(_l1Cache.keys.first);
    }
    _l1Cache[hash] = analysis;
  }

  void _linkTrackKey(String trackKey, String hash) {
    if (trackKey.isEmpty) return;
    _trackKeyToHash.remove(trackKey);
    if (_trackKeyToHash.length >= _maxTrackKeyIndexSize) {
      _trackKeyToHash.remove(_trackKeyToHash.keys.first);
    }
    _trackKeyToHash[trackKey] = hash;
  }

  Future<ArtworkPaletteAnalysis?> _readFromL2(String artworkHash) async {
    final db = _database;
    if (db == null) return null;
    try {
      final row = await db.getArtworkPalette(
        artworkHash,
        expectedVersion: AdaptiveThemeGenerator.kAlgorithmVersion,
      );
      if (row == null) return null;
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) {
        await db.deleteArtworkPalette(artworkHash);
        return null;
      }
      final analysis = ArtworkPaletteAnalysis.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (analysis.algorithmVersion !=
          AdaptiveThemeGenerator.kAlgorithmVersion) {
        await db.deleteArtworkPalette(artworkHash);
        return null;
      }
      return analysis;
    } catch (e) {
      debugPrint(
        '[ArtworkThemeService] Corrupt L2 palette cache entry purged: $e',
      );
      try {
        await db.deleteArtworkPalette(artworkHash);
      } catch (_) {}
      return null;
    }
  }

  Future<void> _persistToL2(
    String artworkHash,
    ArtworkPaletteAnalysis analysis,
  ) {
    final db = _database;
    if (db == null) return Future<void>.value();
    final future = () async {
      try {
        await db.upsertArtworkPalette(
          artworkHash: artworkHash,
          algorithmVersion: analysis.algorithmVersion,
          payloadJson: jsonEncode(analysis.toJson()),
        );
      } catch (e) {
        debugPrint('[ArtworkThemeService] L2 palette persist skipped: $e');
      }
    }();
    _pendingPersist = future;
    return future;
  }

  /// Converts an [AdaptiveSemanticPalette] into a Flutter [ColorScheme].
  static ColorScheme toColorScheme(
    AdaptiveSemanticPalette palette, {
    bool isDark = true,
  }) =>
      _toColorScheme(palette, isDark: isDark);

  static ColorScheme _toColorScheme(
    AdaptiveSemanticPalette p, {
    bool isDark = true,
  }) {
    if (!isDark) {
      return ColorScheme.fromSeed(
        seedColor: Color(p.primaryAccent),
        brightness: Brightness.light,
      );
    }
    return ColorScheme.dark(
      primary: Color(p.primaryAccent),
      onPrimary: Color(p.onPrimary),
      secondary: Color(p.secondaryAccent),
      onSecondary: Color(p.onSecondary),
      tertiary: Color(p.secondaryAccent),
      onTertiary: Color(p.onSecondary),
      surface: Color(p.background),
      onSurface: Color(p.primaryText),
      onSurfaceVariant: Color(p.secondaryText),
      surfaceContainerLowest: Color(p.background),
      surfaceContainerLow: Color(p.background),
      surfaceContainer: Color(p.surface),
      surfaceContainerHigh: Color(p.elevatedSurface),
      surfaceContainerHighest: Color(p.elevatedSurface),
      surfaceTint: Color(p.surfaceTint),
    );
  }

  /// Fallback [ColorScheme] matching SautiPlay's default dark-blue palette.
  static ColorScheme fallbackScheme(bool isDark) {
    return _toColorScheme(
      AdaptiveThemeGenerator.fallbackPalette(),
      isDark: isDark,
    );
  }

  /// Clears in-memory L1 caches without disturbing the persistent Drift cache.
  void clearCache() {
    _l1Cache.clear();
    _trackKeyToHash.clear();
    _lastHashedBytesRef = null;
    _lastHashedDigest = null;
  }

  /// Test-only configuration hook for injecting an in-memory Drift DB or
  /// disabling native codec decoding in headless test environments.
  @visibleForTesting
  void configureForTesting({
    AppDatabase? database,
    bool? useNativeCodec,
    PaletteExtractionConfig? config,
    bool? adaptiveModeActive,
  }) {
    if (database != null) {
      _database = database;
    }
    if (useNativeCodec != null) {
      _worker.useNativeCodec = useNativeCodec;
    }
    if (config != null) {
      _config = config;
    }
    if (adaptiveModeActive != null) {
      _adaptiveModeActive = adaptiveModeActive;
    }
  }

  /// Test-only cleanup that clears all caches/counters and terminates the
  /// persistent background isolate cleanly.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _pendingPersist;
    _pendingPersist = null;
    clearCache();
    _database = null;
    _currentScheme = null;
    _currentSemanticPalette = null;
    _currentAnalysis = null;
    _lastMetrics = null;
    _l1Hits = 0;
    _l2Hits = 0;
    _cacheMisses = 0;
    _activeRequestId = 0;
    _adaptiveModeActive = true;
    _config = const PaletteExtractionConfig();
    _worker.useNativeCodec = true;
    await _worker.dispose();
  }
}
