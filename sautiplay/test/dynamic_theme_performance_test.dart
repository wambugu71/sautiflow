import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/services/artwork_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ArtworkThemeService.instance.configureForTesting(useNativeCodec: false);
  });

  tearDown(() async {
    await ArtworkThemeService.instance.resetForTesting();
  });

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

    test('AppThemeData.lerp interpolates all semantic adaptive roles', () {
      const a = AppThemeData(
        id: AppThemeId.dynamicAlbumArt,
        displayName: 'Dynamic Cover',
        bgDark: Color(0xFF0A0C10),
        cardDark: Color(0xFF141820),
        primary: Color(0xFFEF4444),
        textDark: Color(0xFF9CA3AF),
        icon: Icons.palette_outlined,
        elevatedSurfaceColor: Color(0xFF1E2430),
        secondaryAccentColor: Color(0xFFF59E0B),
        onPrimaryColor: Color(0xFF090B0E),
        onSecondaryColor: Color(0xFF090B0E),
        textPrimaryColor: Color(0xFFF8FAFC),
        progressIndicatorColor: Color(0xFFF87171),
        progressTrackColor: Color(0xFF2B3240),
        activeNavigationColor: Color(0xFFEF4444),
        playbackControlColor: Color(0xFFF87171),
        surfaceTintColor: Color(0x14EF4444),
      );
      const b = AppThemeData(
        id: AppThemeId.dynamicAlbumArt,
        displayName: 'Dynamic Cover',
        bgDark: Color(0xFF081014),
        cardDark: Color(0xFF101C22),
        primary: Color(0xFF06B6D4),
        textDark: Color(0xFF94A3B8),
        icon: Icons.palette_outlined,
        elevatedSurfaceColor: Color(0xFF182A33),
        secondaryAccentColor: Color(0xFF8B5CF6),
        onPrimaryColor: Color(0xFF061014),
        onSecondaryColor: Color(0xFFF8FAFC),
        textPrimaryColor: Color(0xFFFFFFFF),
        progressIndicatorColor: Color(0xFF22D3EE),
        progressTrackColor: Color(0xFF20343E),
        activeNavigationColor: Color(0xFF22D3EE),
        playbackControlColor: Color(0xFF06B6D4),
        surfaceTintColor: Color(0x1406B6D4),
      );

      expect(a.hasSameColors(b), isFalse);
      expect(a.hasSameColors(a), isTrue);

      final mid = AppThemeData.lerp(a, b, 0.5);
      expect(
        mid.elevatedSurface,
        Color.lerp(a.elevatedSurface, b.elevatedSurface, 0.5),
      );
      expect(
        mid.secondaryAccent,
        Color.lerp(a.secondaryAccent, b.secondaryAccent, 0.5),
      );
      expect(
        mid.progressIndicator,
        Color.lerp(a.progressIndicator, b.progressIndicator, 0.5),
      );
      expect(
        mid.progressTrack,
        Color.lerp(a.progressTrack, b.progressTrack, 0.5),
      );
      expect(
        mid.activeNavigation,
        Color.lerp(a.activeNavigation, b.activeNavigation, 0.5),
      );
      expect(
        mid.playbackControl,
        Color.lerp(a.playbackControl, b.playbackControl, 0.5),
      );
      expect(mid.surfaceTint, Color.lerp(a.surfaceTint, b.surfaceTint, 0.5));
    });

    test('ArtworkThemeService returns fallback gracefully on null/empty bytes',
        () async {
      final service = ArtworkThemeService.instance;
      final scheme = await service.extractAndEmit(
        trackKey: 'empty_test',
        artBytes: null,
        isDark: true,
      );

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, ArtworkThemeService.fallbackScheme(true).primary);
    });

    test('ArtworkThemeService peek returns null when key is absent', () async {
      final service = ArtworkThemeService.instance;
      expect(service.peek('non_existent_key'), isNull);
    });
  });
}
