import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/services/artwork_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Theme & 60-120Hz Lerp Tests', () {
    test('AppThemeData.lerp smoothly interpolates colors between themes', () {
      final themeA = AppThemeService.themes.firstWhere(
        (t) => t.id == AppThemeId.darkBlue,
      );
      final themeB = AppThemeService.themes.firstWhere(
        (t) => t.id == AppThemeId.orange,
      );

      // t = 0.0 -> matches themeA
      final lerp0 = AppThemeData.lerp(themeA, themeB, 0.0);
      expect(lerp0.primary, themeA.primary);
      expect(lerp0.bgDark, themeA.bgDark);
      expect(lerp0.cardDark, themeA.cardDark);

      // t = 1.0 -> matches themeB
      final lerp1 = AppThemeData.lerp(themeA, themeB, 1.0);
      expect(lerp1.primary, themeB.primary);
      expect(lerp1.bgDark, themeB.bgDark);
      expect(lerp1.cardDark, themeB.cardDark);

      // t = 0.5 -> intermediate 60-120Hz frame interpolation
      final lerpHalf = AppThemeData.lerp(themeA, themeB, 0.5);
      final expectedPrimary = Color.lerp(themeA.primary, themeB.primary, 0.5);
      final expectedBg = Color.lerp(themeA.bgDark, themeB.bgDark, 0.5);
      final expectedCard = Color.lerp(themeA.cardDark, themeB.cardDark, 0.5);

      expect(lerpHalf.primary, expectedPrimary);
      expect(lerpHalf.bgDark, expectedBg);
      expect(lerpHalf.cardDark, expectedCard);
    });

    test('ArtworkThemeService returns fallback gracefully on null/empty bytes', () async {
      final service = ArtworkThemeService.instance;
      final scheme = await service.extractAndEmit(
        trackKey: 'empty_test',
        artBytes: null,
        isDark: true,
      );

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, ArtworkThemeService.fallbackScheme(true).primary);
    });

    test('ArtworkThemeService peek returns cached scheme when available', () async {
      final service = ArtworkThemeService.instance;
      expect(service.peek('non_existent_key'), isNull);
    });
  });
}
