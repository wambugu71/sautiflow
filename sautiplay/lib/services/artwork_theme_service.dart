import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';

/// High-performance, non-blocking Isolate-driven artwork color extraction service
/// powered by Google's official Material 3 (material_color_utilities) Quantizer & Scoring engine.
class ArtworkThemeService {
  ArtworkThemeService._();
  static final ArtworkThemeService instance = ArtworkThemeService._();

  static const int _maxCacheSize = 50;
  final Map<String, ColorScheme> _lruCache = {};

  final StreamController<ColorScheme> _schemeController =
      StreamController<ColorScheme>.broadcast();

  Stream<ColorScheme> get onColorSchemeChanged => _schemeController.stream;

  ColorScheme? _currentScheme;
  ColorScheme? get currentScheme => _currentScheme;

  /// Extract dominant theme color scheme asynchronously in a background isolate using Google Material 3 algorithms.
  Future<ColorScheme> extractAndEmit({
    required String trackKey,
    required Uint8List? artBytes,
    bool isDark = true,
  }) async {
    if (artBytes == null || artBytes.isEmpty || trackKey.isEmpty) {
      final fallback = fallbackScheme(isDark);
      _updateCurrent(fallback);
      return fallback;
    }

    if (_lruCache.containsKey(trackKey)) {
      final cached = _lruCache[trackKey]!;
      _updateCurrent(cached);
      return cached;
    }

    try {
      final int argbInt = await compute(_isolateExtractDominantColor, artBytes);
      final dominantColor = Color(argbInt);

      final scheme = ColorScheme.fromSeed(
        seedColor: dominantColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      );

      _evictIfNecessary();
      _lruCache[trackKey] = scheme;

      _updateCurrent(scheme);
      return scheme;
    } catch (e) {
      debugPrint('[ArtworkThemeService] Isolate extraction failed: $e');
      final fallback = fallbackScheme(isDark);
      _updateCurrent(fallback);
      return fallback;
    }
  }

  void _updateCurrent(ColorScheme scheme) {
    _currentScheme = scheme;
    _schemeController.add(scheme);
  }

  void _evictIfNecessary() {
    if (_lruCache.length >= _maxCacheSize) {
      _lruCache.remove(_lruCache.keys.first);
    }
  }

  static ColorScheme fallbackScheme(bool isDark) {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF38BDF8),
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  void clearCache() => _lruCache.clear();
}

/// ── Background Worker Isolate ────────────────────────────────────────────────
/// Executed off the main UI loop: Uses Google's official Material 3 (QuantizerCelebi + Score)
/// algorithms to extract the exact seed color from raw artwork pixel data.
Future<int> _isolateExtractDominantColor(Uint8List bytes) async {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0xFF38BDF8;

    // Resample down to 64x64 for optimal Google Material 3 quantization balance
    final resized = img.copyResize(decoded, width: 64, height: 64);
    final pixels = Int32List(resized.width * resized.height);

    int idx = 0;
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        final a = pixel.a.toInt();
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        pixels[idx++] = (a << 24) | (r << 16) | (g << 8) | b;
      }
    }

    // 🚀 Google Material 3 Quantizer (Celebi) + Score Ranking
    final quantizerResult = await QuantizerCelebi().quantize(pixels, 128);
    final rankedColors = Score.score(quantizerResult.colorToCount);

    if (rankedColors.isNotEmpty) {
      return rankedColors.first;
    }

    return 0xFF38BDF8;
  } catch (e) {
    return 0xFF38BDF8;
  }
}

