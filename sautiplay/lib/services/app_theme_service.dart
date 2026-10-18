import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/navigation_bar/styles/m3e_navigation_bar_theme.dart';
import '../database/preferences_store.dart';
import 'm3e_typography_service.dart';

import 'artwork_theme_service.dart';

// ─── Theme IDs ───────────────────────────────────────────────────────────────
enum AppThemeId {
  darkBlue,
  dark,
  light,
  orange,
  purple,
  amoledBlack,
  dynamicAlbumArt,
}

// ─── Per-theme palette ────────────────────────────────────────────────────────
class AppThemeData {
  final AppThemeId id;
  final String displayName;
  final Color bgDark;   // scaffold background
  final Color cardDark; // card / surface
  final Color primary;  // accent / primary
  final Color textDark; // muted text
  final IconData icon;

  const AppThemeData({
    required this.id,
    required this.displayName,
    required this.bgDark,
    required this.cardDark,
    required this.primary,
    required this.textDark,
    required this.icon,
  });

  /// High-refresh-rate 60Hz/120Hz frame-by-frame color interpolator
  static AppThemeData lerp(AppThemeData a, AppThemeData b, double t) {
    if (identical(a, b)) return a;
    return AppThemeData(
      id: t < 0.5 ? a.id : b.id,
      displayName: t < 0.5 ? a.displayName : b.displayName,
      bgDark: Color.lerp(a.bgDark, b.bgDark, t) ?? b.bgDark,
      cardDark: Color.lerp(a.cardDark, b.cardDark, t) ?? b.cardDark,
      primary: Color.lerp(a.primary, b.primary, t) ?? b.primary,
      textDark: Color.lerp(a.textDark, b.textDark, t) ?? b.textDark,
      icon: t < 0.5 ? a.icon : b.icon,
    );
  }

  /// Builds a full M3EThemeData from this palette for Material 3 Expressive components.
  M3EThemeData toM3EThemeData({
    String? fontFamily,
    double? rond,
    double? bodyRond,
    bool? useM3ETypography,
  }) {
    final activeFont = fontFamily ?? AppThemeService.instance.fontFamily;
    final activeRond = rond ?? AppThemeService.instance.fontRond;
    final activeBodyRond = bodyRond ?? AppThemeService.instance.bodyFontRond;
    final activeUseM3E =
        useM3ETypography ?? AppThemeService.instance.useM3ETypography;

    final isDark = bgDark.computeLuminance() < 0.15;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textMuted = isDark ? textDark : const Color(0xFF64748B);
    final borderAlpha = isDark ? 0.12 : 0.08;

    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final resolvedTextTheme = M3ETypographyService.resolveTextTheme(
      baseTextTheme,
      fontFamily: activeFont,
      useM3E: activeUseM3E,
      rond: activeRond,
      bodyRond: activeBodyRond,
    );

    final m3eScheme = M3EColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: isDark ? Colors.black : Colors.white,
      primaryContainer: primary.withValues(alpha: isDark ? 0.3 : 0.2),
      onPrimaryContainer: isDark ? Colors.white : primary,
      secondary: primary,
      onSecondary: isDark ? Colors.black : Colors.white,
      secondaryContainer: primary.withValues(alpha: isDark ? 0.25 : 0.15),
      onSecondaryContainer: isDark ? Colors.white : primary,
      tertiary: primary,
      onTertiary: isDark ? Colors.black : Colors.white,
      tertiaryContainer: primary.withValues(alpha: 0.2),
      onTertiaryContainer: isDark ? Colors.white : primary,
      error: const Color(0xFFCF6679),
      onError: Colors.black,
      errorContainer: const Color(0xFFB00020).withValues(alpha: 0.2),
      onErrorContainer: const Color(0xFFCF6679),
      surface: cardDark,
      onSurface: textPrimary,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: bgDark,
      surfaceContainerLow: bgDark,
      surfaceContainer: cardDark,
      surfaceContainerHigh: cardDark,
      surfaceContainerHighest: cardDark,
      surfaceDim: bgDark,
      surfaceBright: cardDark,
      inverseSurface: textPrimary,
      onInverseSurface: bgDark,
      inversePrimary: primary,
      outline: textPrimary.withValues(alpha: 0.2),
      outlineVariant: textPrimary.withValues(alpha: borderAlpha),
      shadow: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
      scrim: Colors.black.withValues(alpha: 0.6),
      surfaceTint: primary,
      emphasis: primary,
      onEmphasis: isDark ? Colors.black : Colors.white,
      info: primary,
      success: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      warning: isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00),
      danger: const Color(0xFFCF6679),
      surfaceStrong: cardDark,
      onSurfaceStrong: textPrimary,
      outlineStrong: textPrimary.withValues(alpha: 0.3),
    );

    return M3EThemeData(
      colorScheme: m3eScheme,
      typeScale: M3ETypeScale.fromTextTheme(resolvedTextTheme),
      cardTheme: const M3ECardTheme(),
      listTheme: const M3EListTheme(),
      dialogTheme: const M3EDialogTheme(),
      bottomSheetTheme: const M3EBottomSheetTheme(),
      navigationBarTheme: const M3ENavigationBarTheme(
        heightMedium: 72,
        heightSmall: 60,
        iconSize: 24,
      ),
    );
  }

  /// Builds a full MaterialApp ThemeData from this palette with responsive
  /// Material 3 Expressive typography and custom selectable fonts.
  ThemeData toThemeData({
    String? fontFamily,
    double? rond,
    double? bodyRond,
    bool? useM3ETypography,
  }) {
    final activeFont = fontFamily ?? AppThemeService.instance.fontFamily;
    final activeRond = rond ?? AppThemeService.instance.fontRond;
    final activeBodyRond = bodyRond ?? AppThemeService.instance.bodyFontRond;
    final activeUseM3E =
        useM3ETypography ?? AppThemeService.instance.useM3ETypography;

    final isDark = bgDark.computeLuminance() < 0.15;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textMuted = isDark ? textDark : const Color(0xFF64748B);
    final borderAlpha = isDark ? 0.12 : 0.08;

    final resolvedTextTheme = M3ETypographyService.resolveTextTheme(
      base.textTheme,
      fontFamily: activeFont,
      useM3E: activeUseM3E,
      rond: activeRond,
      bodyRond: activeBodyRond,
    );

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: primary,
            onPrimary: Colors.black,
            surface: cardDark,
            onSurface: textPrimary,
            surfaceContainerLowest: bgDark,
            surfaceContainerLow: bgDark,
            surfaceContainer: cardDark,
            surfaceContainerHigh: cardDark,
            surfaceContainerHighest: cardDark,
            surfaceDim: bgDark,
            surfaceBright: cardDark,
            onSurfaceVariant: textMuted,
            outline: textPrimary.withValues(alpha: 0.2),
            outlineVariant: textPrimary.withValues(alpha: borderAlpha),
          )
        : ColorScheme.light(
            primary: primary,
            onPrimary: Colors.white,
            surface: cardDark,
            onSurface: textPrimary,
            surfaceContainerLowest: bgDark,
            surfaceContainerLow: bgDark,
            surfaceContainer: cardDark,
            surfaceContainerHigh: cardDark,
            surfaceContainerHighest: cardDark,
            surfaceDim: bgDark,
            surfaceBright: cardDark,
            onSurfaceVariant: textMuted,
            outline: textPrimary.withValues(alpha: 0.2),
            outlineVariant: textPrimary.withValues(alpha: borderAlpha),
          );

    return base.copyWith(
      textTheme: resolvedTextTheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bgDark,
      colorScheme: colorScheme,
      cardColor: cardDark,
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardDark,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: textPrimary.withValues(alpha: borderAlpha)),
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: textMuted,
          fontSize: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardDark,
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: textPrimary.withValues(alpha: borderAlpha)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgDark,
        indicatorColor: primary.withValues(alpha: 0.3),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: primary, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return TextStyle(
              color: textMuted.withValues(alpha: isDark ? 0.7 : 0.8),
              fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return IconThemeData(
              color: textMuted.withValues(alpha: isDark ? 0.7 : 0.8));
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: textPrimary.withValues(alpha: borderAlpha),
        thickness: 1,
      ),
      dividerColor: textPrimary.withValues(alpha: borderAlpha),
      iconTheme: IconThemeData(color: textPrimary),
    );
  }
}

// ─── Service singleton ────────────────────────────────────────────────────────
class AppThemeService {
  AppThemeService._() {
    ArtworkThemeService.instance.onColorSchemeChanged.listen((_) {
      if (_current == AppThemeId.dynamicAlbumArt) {
        themeChanged.add(_current);
      }
    });
  }
  static final AppThemeService instance = AppThemeService._();

  static const _kAppThemeKey = 'sp_app_theme_id';
  static const _kAlbumArtShapeKey = 'sp_album_art_shape';

  /// All available themes, ordered for display.
  static const List<AppThemeData> themes = [
    AppThemeData(
      id: AppThemeId.darkBlue,
      displayName: 'Dark Blue',
      bgDark: Color(0xFF0F172A),
      cardDark: Color(0xFF1E293B),
      primary: Color(0xFF38BDF8),
      textDark: Color(0xFF94A3B8),
      icon: Icons.dark_mode_outlined,
    ),
    AppThemeData(
      id: AppThemeId.dark,
      displayName: 'Dark',
      bgDark: Color(0xFF0D0D0D),
      cardDark: Color(0xFF1A1A1A),
      primary: Color(0xFFAAAAAA),
      textDark: Color(0xFF8A8A8A),
      icon: Icons.nights_stay_outlined,
    ),
    AppThemeData(
      id: AppThemeId.light,
      displayName: 'Light',
      bgDark: Color(0xFFE8EAED),
      cardDark: Color(0xFFFFFFFF),
      primary: Color(0xFF0284C7),
      textDark: Color(0xFF64748B),
      icon: Icons.wb_sunny_outlined,
    ),
    AppThemeData(
      id: AppThemeId.orange,
      displayName: 'Sunset',
      bgDark: Color(0xFF1A0F00),
      cardDark: Color(0xFF2A1A08),
      primary: Color(0xFFFF7A00),
      textDark: Color(0xFFBB8A52),
      icon: Icons.local_fire_department_outlined,
    ),
    AppThemeData(
      id: AppThemeId.purple,
      displayName: 'Violet',
      bgDark: Color(0xFF100B1F),
      cardDark: Color(0xFF1B1330),
      primary: Color(0xFF9B59F5),
      textDark: Color(0xFF9D8EC0),
      icon: Icons.auto_awesome_outlined,
    ),
    AppThemeData(
      id: AppThemeId.amoledBlack,
      displayName: 'AMOLED',
      bgDark: Color(0xFF000000),
      cardDark: Color(0xFF0A0A0A),
      primary: Color(0xFF00E5FF),
      textDark: Color(0xFF607D8B),
      icon: Icons.phonelink_outlined,
    ),
    AppThemeData(
      id: AppThemeId.dynamicAlbumArt,
      displayName: 'Dynamic Cover',
      bgDark: Color(0xFF0F172A),
      cardDark: Color(0xFF1E293B),
      primary: Color(0xFF38BDF8),
      textDark: Color(0xFF94A3B8),
      icon: Icons.palette_outlined,
    ),
  ];

  static const _kUseM3EAlbumArtShapeKey = 'sp_use_m3e_album_art_shape';
  static const _kFontFamilyKey = 'sp_font_family';
  static const _kUseM3ETypographyKey = 'sp_use_m3e_typography';
  static const _kFontRondKey = 'sp_font_rond';
  static const _kBodyFontRondKey = 'sp_body_font_rond';

  /// Broadcast stream – emits the new [AppThemeId] whenever the theme changes.
  final StreamController<AppThemeId> themeChanged =
      StreamController<AppThemeId>.broadcast();

  /// Broadcast stream – emits the new [Shapes] whenever the album art shape changes.
  final StreamController<Shapes> albumArtShapeChanged =
      StreamController<Shapes>.broadcast();

  /// Broadcast stream – emits whether M3E shape containers are enabled for album art.
  final StreamController<bool> useM3EAlbumArtShapeChanged =
      StreamController<bool>.broadcast();

  /// Broadcast stream – emits the selected font family name.
  final StreamController<String> fontFamilyChanged =
      StreamController<String>.broadcast();

  /// Broadcast stream – emits whether Material 3 Expressive typography scale is active.
  final StreamController<bool> useM3ETypographyChanged =
      StreamController<bool>.broadcast();

  /// Broadcast stream – emits the global corner roundness (ROND axis).
  final StreamController<double> fontRondChanged =
      StreamController<double>.broadcast();

  /// Broadcast stream – emits the body corner roundness (bodyRond axis).
  final StreamController<double> bodyFontRondChanged =
      StreamController<double>.broadcast();

  AppThemeId _current = AppThemeId.darkBlue;
  AppThemeId get current => _current;

  Shapes _albumArtShape = Shapes.slanted;
  Shapes get albumArtShape => _albumArtShape;

  bool _useM3EAlbumArtShape = false;
  bool get useM3EAlbumArtShape => _useM3EAlbumArtShape;

  String _fontFamily = 'System';
  String get fontFamily => _fontFamily;

  bool _useM3ETypography = true;
  bool get useM3ETypography => _useM3ETypography;

  double _fontRond = 0.0;
  double get fontRond => _fontRond;

  double _bodyFontRond = 0.0;
  double get bodyFontRond => _bodyFontRond;

  AppThemeData get currentData {
    final base = themes.firstWhere((t) => t.id == _current);
    if (_current == AppThemeId.dynamicAlbumArt) {
      final scheme = ArtworkThemeService.instance.currentScheme;
      if (scheme != null) {
        return AppThemeData(
          id: AppThemeId.dynamicAlbumArt,
          displayName: 'Dynamic Cover',
          bgDark: scheme.surface,
          cardDark: scheme.surfaceContainerHigh,
          primary: scheme.primary,
          textDark: scheme.onSurface.withValues(alpha: 0.7),
          icon: Icons.palette_outlined,
        );
      }
    }
    return base;
  }

  Future<void> loadTheme() async {
    final prefs = PreferencesStore.instance;
    final saved = prefs.getString(_kAppThemeKey);
    if (saved != null) {
      final match = AppThemeId.values.where((e) => e.name == saved);
      if (match.isNotEmpty) _current = match.first;
    }
    final savedShape = prefs.getString(_kAlbumArtShapeKey);
    if (savedShape != null) {
      final match = Shapes.values.where((e) => e.name == savedShape);
      if (match.isNotEmpty) _albumArtShape = match.first;
    }
    final savedUseM3EShape = prefs.getBool(_kUseM3EAlbumArtShapeKey);
    if (savedUseM3EShape != null) {
      _useM3EAlbumArtShape = savedUseM3EShape;
    }
    final savedFont = prefs.getString(_kFontFamilyKey);
    if (savedFont != null && savedFont.isNotEmpty) {
      _fontFamily = savedFont;
    }
    final savedM3E = prefs.getBool(_kUseM3ETypographyKey);
    if (savedM3E != null) {
      _useM3ETypography = savedM3E;
    }
    final savedRond = prefs.getDouble(_kFontRondKey);
    if (savedRond != null) {
      _fontRond = savedRond;
    }
    final savedBodyRond = prefs.getDouble(_kBodyFontRondKey);
    if (savedBodyRond != null) {
      _bodyFontRond = savedBodyRond;
    }
  }

  Future<void> saveTheme(AppThemeId id) async {
    _current = id;
    await PreferencesStore.instance.setString(_kAppThemeKey, id.name);
    themeChanged.add(id);
  }

  Future<void> saveAlbumArtShape(Shapes shape) async {
    _albumArtShape = shape;
    await PreferencesStore.instance.setString(_kAlbumArtShapeKey, shape.name);
    albumArtShapeChanged.add(shape);
  }

  Future<void> saveUseM3EAlbumArtShape(bool enabled) async {
    _useM3EAlbumArtShape = enabled;
    await PreferencesStore.instance.setBool(_kUseM3EAlbumArtShapeKey, enabled);
    useM3EAlbumArtShapeChanged.add(enabled);
  }

  Future<void> saveFontFamily(String family) async {
    _fontFamily = family;
    await PreferencesStore.instance.setString(_kFontFamilyKey, family);
    fontFamilyChanged.add(family);
  }

  Future<void> saveUseM3ETypography(bool enabled) async {
    _useM3ETypography = enabled;
    await PreferencesStore.instance.setBool(_kUseM3ETypographyKey, enabled);
    useM3ETypographyChanged.add(enabled);
  }

  Future<void> saveFontRond(double rond) async {
    _fontRond = rond;
    await PreferencesStore.instance.setDouble(_kFontRondKey, rond);
    fontRondChanged.add(rond);
  }

  Future<void> saveBodyFontRond(double bodyRond) async {
    _bodyFontRond = bodyRond;
    await PreferencesStore.instance.setDouble(_kBodyFontRondKey, bodyRond);
    bodyFontRondChanged.add(bodyRond);
  }

  static AppThemeData dataFor(AppThemeId id) =>
      themes.firstWhere((t) => t.id == id);
}

// ─── InheritedWidget so any descendant can reactively read the current theme ──
class AppThemeProvider extends InheritedWidget {
  final AppThemeData themeData;
  final Shapes albumArtShape;
  final bool useM3EAlbumArtShape;
  final String fontFamily;
  final bool useM3ETypography;
  final double fontRond;
  final double bodyFontRond;

  const AppThemeProvider({
    super.key,
    required this.themeData,
    this.albumArtShape = Shapes.slanted,
    this.useM3EAlbumArtShape = false,
    this.fontFamily = 'System',
    this.useM3ETypography = true,
    this.fontRond = 0.0,
    this.bodyFontRond = 0.0,
    required super.child,
  });

  static AppThemeData of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.themeData ?? AppThemeService.instance.currentData;
  }

  static Shapes ofShape(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.albumArtShape ?? AppThemeService.instance.albumArtShape;
  }

  static bool ofUseM3EShape(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.useM3EAlbumArtShape ??
        AppThemeService.instance.useM3EAlbumArtShape;
  }

  static String ofFontFamily(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.fontFamily ?? AppThemeService.instance.fontFamily;
  }

  static bool ofUseM3ETypography(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.useM3ETypography ??
        AppThemeService.instance.useM3ETypography;
  }

  static double ofFontRond(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.fontRond ?? AppThemeService.instance.fontRond;
  }

  static double ofBodyFontRond(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    return provider?.bodyFontRond ?? AppThemeService.instance.bodyFontRond;
  }

  @override
  bool updateShouldNotify(AppThemeProvider oldWidget) =>
      themeData.id != oldWidget.themeData.id ||
      themeData.primary != oldWidget.themeData.primary ||
      themeData.bgDark != oldWidget.themeData.bgDark ||
      themeData.cardDark != oldWidget.themeData.cardDark ||
      albumArtShape != oldWidget.albumArtShape ||
      useM3EAlbumArtShape != oldWidget.useM3EAlbumArtShape ||
      fontFamily != oldWidget.fontFamily ||
      useM3ETypography != oldWidget.useM3ETypography ||
      fontRond != oldWidget.fontRond ||
      bodyFontRond != oldWidget.bodyFontRond;
}

// ─── BuildContext Extension for Reactive Theme Tokens ─────────────────────────
extension AppThemeContextExtension on BuildContext {
  AppThemeData get appTheme => AppThemeProvider.of(this);
  Shapes get albumArtShape => AppThemeProvider.ofShape(this);
  bool get useM3EAlbumArtShape => AppThemeProvider.ofUseM3EShape(this);
  String get fontFamily => AppThemeProvider.ofFontFamily(this);
  bool get useM3ETypography => AppThemeProvider.ofUseM3ETypography(this);
  double get fontRond => AppThemeProvider.ofFontRond(this);
  double get bodyFontRond => AppThemeProvider.ofBodyFontRond(this);
  TextTheme get emphasizedTextTheme => Theme.of(this).textTheme.emphasized;
  Color get bgDark => appTheme.bgDark;
  Color get cardDark => appTheme.cardDark;
  Color get surfaceDarkerColor => appTheme.cardDark.withValues(alpha: 0.8);
  Color get primaryColor => appTheme.primary;
  Color get textMuted => appTheme.textDark;
  Color get textDark => appTheme.textDark;
  bool get isDark => bgDark.computeLuminance() < 0.15;
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF1A1A2E);
  Color get outlineColor => (isDark ? Colors.white : const Color(0xFF1A1A2E)).withValues(alpha: 0.12);
}


