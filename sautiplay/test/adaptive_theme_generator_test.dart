import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:sautiplay/services/artwork_theme/adaptive_theme_generator.dart';
import 'package:sautiplay/services/artwork_theme/artwork_palette_models.dart';
import 'package:sautiplay/services/artwork_theme/palette_personality_analyzer.dart';
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
      image.setPixelRgba(
        x,
        y,
        (argb >> 16) & 0xFF,
        (argb >> 8) & 0xFF,
        argb & 0xFF,
        (argb >> 24) & 0xFF,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void _expectValidWcagAndNeutralFoundation(AdaptiveSemanticPalette p) {
  final bgLum = PerceptualColorAnalyzer.relativeLuminance(p.background);
  final surfLum = PerceptualColorAnalyzer.relativeLuminance(p.surface);
  final elevLum = PerceptualColorAnalyzer.relativeLuminance(p.elevatedSurface);

  // Neutral dark foundation stability and subtle stepped elevation.
  expect(bgLum, lessThan(0.03));
  expect(surfLum, greaterThan(bgLum));
  expect(elevLum, greaterThan(surfLum));

  final surfaces = [p.background, p.surface, p.elevatedSurface];
  for (final bg in surfaces) {
    expect(
      PerceptualColorAnalyzer.wcagContrastRatio(p.primaryText, bg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      PerceptualColorAnalyzer.wcagContrastRatio(p.secondaryText, bg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      PerceptualColorAnalyzer.wcagContrastRatio(p.primaryAccent, bg),
      greaterThanOrEqualTo(3.0),
    );
    expect(
      PerceptualColorAnalyzer.wcagContrastRatio(p.secondaryAccent, bg),
      greaterThanOrEqualTo(3.0),
    );
    expect(
      PerceptualColorAnalyzer.wcagContrastRatio(p.playbackControl, bg),
      greaterThanOrEqualTo(3.0),
    );
  }

  expect(
    PerceptualColorAnalyzer.wcagContrastRatio(p.onPrimary, p.primaryAccent),
    greaterThanOrEqualTo(4.5),
  );
  expect(
    PerceptualColorAnalyzer.wcagContrastRatio(p.onSecondary, p.secondaryAccent),
    greaterThanOrEqualTo(4.5),
  );
  expect(
    PerceptualColorAnalyzer.wcagContrastRatio(
      p.activeNavigation,
      p.background,
    ),
    greaterThanOrEqualTo(4.5),
  );
  expect(
    PerceptualColorAnalyzer.wcagContrastRatio(
      p.progressIndicator,
      p.progressTrack,
    ),
    greaterThanOrEqualTo(3.0),
  );

  // Surface tint remains restrained (alpha <= ~0.10).
  final tintAlpha = (p.surfaceTint >> 24) & 0xFF;
  expect(tintAlpha, inInclusiveRange(8, 28));
}

void main() {
  group('PalettePersonalityAnalyzer & AdaptiveThemeGenerator', () {
    test('classifies all 6 palette personalities and modulates theme intensity',
        () {
      final electronicPng = _makePng(120, 120, (x, y) {
        if (y < 40) return 0xFF00E5FF;
        if (y < 80) return 0xFFFF007F;
        return 0xFF6A00FF;
      });
      final monoPng = _makePng(120, 120, (x, y) {
        if (y < 40) return 0xFF181818;
        if (y < 80) return 0xFF606060;
        return 0xFFC8C8C8;
      });
      final cinematicPng = _makePng(120, 120, (x, y) {
        if (y < 92) return 0xFF090B0E;
        if (x < 75) return 0xFFF1F5F9;
        return 0xFFE11D48;
      });
      final vintagePng = _makePng(120, 120, (x, y) {
        if (y < 45) return 0xFF6E503B;
        if (y < 85) return 0xFFA3573E;
        return 0xFFB88B4A;
      });
      final naturalPng = _makePng(120, 120, (x, y) {
        if (y < 45) return 0xFF4E6E35; // olive leaf green
        if (y < 85) return 0xFF6D7F3F; // moss green
        return 0xFF7D633A; // warm bark
      });
      final ambientPng = _makePng(120, 120, (x, y) {
        if (y < 45) return 0xFF345075; // muted dusk slate blue
        if (y < 85) return 0xFF3E707A; // muted misty teal
        return 0xFF655685; // muted dusk lavender
      });

      final cases = <PalettePersonality, Uint8List>{
        PalettePersonality.electronic: electronicPng,
        PalettePersonality.monochromatic: monoPng,
        PalettePersonality.cinematic: cinematicPng,
        PalettePersonality.vintage: vintagePng,
        PalettePersonality.natural: naturalPng,
        PalettePersonality.ambient: ambientPng,
      };

      final palettes = <PalettePersonality, AdaptiveSemanticPalette>{};
      for (final entry in cases.entries) {
        final extracted =
            PerceptualColorAnalyzer.analyzeEncodedBytes(entry.value)!;
        final personality =
            PalettePersonalityAnalyzer.analyze(extracted.clusters);
        expect(
          personality.personality,
          entry.key,
          reason: 'Expected ${entry.key} for test artwork',
        );
        final palette = AdaptiveThemeGenerator.generate(
          clusters: extracted.clusters,
          rankedAccents: extracted.rankedAccents,
          personality: personality,
        );
        expect(palette.isFallback, isFalse);
        _expectValidWcagAndNeutralFoundation(palette);
        palettes[entry.key] = palette;
      }

      final elecChroma =
          Hct.fromInt(palettes[PalettePersonality.electronic]!.primaryAccent)
              .chroma;
      final ambientChroma =
          Hct.fromInt(palettes[PalettePersonality.ambient]!.primaryAccent)
              .chroma;
      final monoChroma =
          Hct.fromInt(palettes[PalettePersonality.monochromatic]!.primaryAccent)
              .chroma;

      expect(elecChroma, greaterThan(ambientChroma));
      expect(monoChroma, lessThanOrEqualTo(22.0));
    });

    test('WCAG 2.1 contrast invariants hold across full 0..360 degree hue sweep',
        () {
      for (int hue = 0; hue < 360; hue += 15) {
        for (final chroma in const [18.0, 52.0, 84.0]) {
          final seedArgb = Hct.from(hue.toDouble(), chroma, 54.0).toInt();
          final png = _makePng(100, 100, (x, y) {
            if (x < 60 && y < 60) return 0xFF14161A;
            return seedArgb;
          });
          final extracted = PerceptualColorAnalyzer.analyzeEncodedBytes(png)!;
          final personality =
              PalettePersonalityAnalyzer.analyze(extracted.clusters);
          final palette = AdaptiveThemeGenerator.generate(
            clusters: extracted.clusters,
            rankedAccents: extracted.rankedAccents,
            personality: personality,
          );
          _expectValidWcagAndNeutralFoundation(palette);
        }
      }
    });

    test('fallbackPalette meets all contrast and dark neutral requirements', () {
      final fallback = AdaptiveThemeGenerator.fallbackPalette();
      expect(fallback.isFallback, isTrue);
      _expectValidWcagAndNeutralFoundation(fallback);
    });
  });
}
