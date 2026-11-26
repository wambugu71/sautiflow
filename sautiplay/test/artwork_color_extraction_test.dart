import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sautiplay/services/artwork_theme/artwork_palette_models.dart';
import 'package:sautiplay/services/artwork_theme/perceptual_color_analyzer.dart';

Uint8List _makePng(
  int width,
  int height,
  int Function(int x, int y) colorAt,
) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final argb = colorAt(x, y);
      final a = (argb >> 24) & 0xFF;
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      final b = argb & 0xFF;
      image.setPixelRgba(x, y, r, g, b, a);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('PerceptualColorAnalyzer Extraction & Ranking', () {
    test('1. Mostly black artwork with small 3% vivid red accent selects red',
        () {
      // 160x160 = 25,600 px; 28x28 = 784 px (~3.06%) vivid crimson red.
      final png = _makePng(160, 160, (x, y) {
        if (x >= 66 && x < 94 && y >= 66 && y < 94) {
          return 0xFFE11D48;
        }
        return 0xFF080808;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      final topAccent = result!.rankedAccents.first.cluster;

      final r = (topAccent.argb >> 16) & 0xFF;
      final g = (topAccent.argb >> 8) & 0xFF;
      final b = topAccent.argb & 0xFF;
      expect(r, greaterThan(170));
      expect(r, greaterThan(g * 2));
      expect(r, greaterThan(b));
      expect(topAccent.chroma, greaterThan(45.0));
      expect(topAccent.categories, contains(ColorCategory.accentCandidate));
      expect(topAccent.categories, contains(ColorCategory.vibrant));
    });

    test('2. Mostly white artwork with 5% cobalt blue accent selects blue', () {
      // 160x160 = 25,600 px; 36x36 = 1,296 px (~5.06%) cobalt blue.
      final png = _makePng(160, 160, (x, y) {
        if (x >= 62 && x < 98 && y >= 62 && y < 98) {
          return 0xFF2563EB;
        }
        return 0xFFF8F8F8;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      final topAccent = result!.rankedAccents.first.cluster;

      final r = (topAccent.argb >> 16) & 0xFF;
      final g = (topAccent.argb >> 8) & 0xFF;
      final b = topAccent.argb & 0xFF;
      expect(b, greaterThan(180));
      expect(b, greaterThan(r * 2));
      expect(b, greaterThan(g));
      expect(topAccent.lightness, lessThan(75.0));
    });

    test('3. Highly saturated electronic cover extracts vivid distinct accents',
        () {
      final png = _makePng(160, 160, (x, y) {
        if (y < 54) return 0xFF00E5FF; // Electric cyan
        if (y < 108) return 0xFFFF007F; // Hot magenta
        if (x < 80) return 0xFF6A00FF; // Neon violet
        return 0xFF140B29; // Deep dark ground
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      expect(result!.rankedAccents.length, greaterThanOrEqualTo(3));
      expect(result.rankedAccents.first.cluster.chroma, greaterThan(55.0));
    });

    test('4. Monochromatic grayscale cover yields neutral clusters', () {
      final png = _makePng(160, 160, (x, y) {
        if (y < 40) return 0xFF181818;
        if (y < 80) return 0xFF505050;
        if (y < 120) return 0xFF909090;
        return 0xFFD0D0D0;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      expect(result!.clusters, isNotEmpty);
      for (final c in result.clusters) {
        expect(c.chroma, lessThan(5.0));
        expect(c.categories, contains(ColorCategory.neutral));
      }
    });

    test('5. Warm vintage artwork selects warm accent cleanly', () {
      final png = _makePng(160, 160, (x, y) {
        if (x < 70 && y < 110) return 0xFF6E503B; // Sepia
        if (x >= 70 && y < 110) return 0xFFA3573E; // Terracotta
        if (y >= 110 && x < 100) return 0xFFB88B4A; // Muted gold
        return 0xFFD8C7A8; // Aged cream
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      final top = result!.rankedAccents.first.cluster;
      final r = (top.argb >> 16) & 0xFF;
      final b = top.argb & 0xFF;
      expect(r, greaterThan(b));
      expect(top.chroma, greaterThan(18.0));
    });

    test('6. Low-contrast muted artwork extracts coherent clusters', () {
      final png = _makePng(160, 160, (x, y) {
        if (y < 60) return 0xFF3B4654;
        if (y < 120) return 0xFF4B5868;
        return 0xFF647D94;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      expect(result!.clusters, isNotEmpty);
      expect(result.rankedAccents, isNotEmpty);
    });

    test(
        '7. Multiple competing accents produce perceptually distinct deterministic ranks',
        () {
      final png = _makePng(160, 160, (x, y) {
        if (y < 64) return 0xFF1E1E24; // 40% slate dark
        if (x < 54) return 0xFFDC2626; // 20% crimson
        if (x < 107) return 0xFF0D9488; // 20% teal
        return 0xFFD97706; // 20% amber
      });

      final first = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      final second = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.rankedAccents.length, greaterThanOrEqualTo(3));

      // Perceptual separation between ranked candidates.
      for (int i = 0; i < first.rankedAccents.length; i++) {
        for (int j = i + 1; j < first.rankedAccents.length; j++) {
          final d = first.rankedAccents[i].cluster.lab
              .deltaE(first.rankedAccents[j].cluster.lab);
          expect(d, greaterThanOrEqualTo(18.0));
        }
      }

      // Strict determinism across repeated runs.
      expect(
        first.clusters.map((c) => c.argb).toList(),
        equals(second!.clusters.map((c) => c.argb).toList()),
      );
      expect(
        first.rankedAccents.map((r) => r.cluster.argb).toList(),
        equals(second.rankedAccents.map((r) => r.cluster.argb).toList()),
      );
      expect(
        first.rankedAccents.map((r) => r.score).toList(),
        equals(second.rankedAccents.map((r) => r.score).toList()),
      );
    });

    test('8. Tiny 0.8% distinctive emerald accent on charcoal is preserved', () {
      // 200x200 = 40,000 px; 18x18 = 324 px = 0.81% emerald.
      final png = _makePng(200, 200, (x, y) {
        if (x >= 91 && x < 109 && y >= 91 && y < 109) {
          return 0xFF10B981;
        }
        return 0xFF111318;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(png);
      expect(result, isNotNull);
      final top = result!.rankedAccents.first.cluster;
      final r = (top.argb >> 16) & 0xFF;
      final g = (top.argb >> 8) & 0xFF;
      final b = top.argb & 0xFF;
      expect(g, greaterThan(r));
      expect(g, greaterThan(b));
      expect(top.chroma, greaterThan(35.0));
    });

    test('9. Empty, corrupt, or fully transparent inputs fail safely', () {
      expect(
        PerceptualColorAnalyzer.analyzeEncodedBytes(Uint8List(0)),
        isNull,
      );
      expect(
        PerceptualColorAnalyzer.analyzeEncodedBytes(
          Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x9A]),
        ),
        isNull,
      );
      final transparentRgba = Uint8List(40 * 40 * 4); // All alpha = 0
      expect(
        PerceptualColorAnalyzer.analyzeRgbaPixels(transparentRgba, 40, 40),
        isNull,
      );
    });

    test('10. Aspect ratio preserved and near-duplicate clusters merged', () {
      final widePng = _makePng(400, 200, (x, y) {
        // Two very close shades of blue (deltaE < 6) and a coral accent.
        if (x < 180) return 0xFF3060C0;
        if (x < 360) return 0xFF3464C4;
        return 0xFFF43F5E;
      });

      final result = PerceptualColorAnalyzer.analyzeEncodedBytes(widePng);
      expect(result, isNotNull);
      expect(result!.workingWidth, equals(160));
      expect(result.workingHeight, equals(80));

      for (int i = 0; i < result.clusters.length; i++) {
        for (int j = i + 1; j < result.clusters.length; j++) {
          final deltaE =
              result.clusters[i].lab.deltaE(result.clusters[j].lab);
          expect(deltaE, greaterThanOrEqualTo(10.0));
        }
      }
    });
  });
}
