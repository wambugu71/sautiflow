import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Builds a full MaterialApp ThemeData from this palette.
  ThemeData toThemeData() {
    final isDark = bgDark.computeLuminance() < 0.15;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textMuted = isDark ? textDark : const Color(0xFF64748B);

    return base.copyWith(
      scaffoldBackgroundColor: bgDark,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: primary,
              surface: cardDark,
              onSurface: textPrimary,
            )
          : ColorScheme.light(
              primary: primary,
              surface: cardDark,
              onSurface: textPrimary,
            ),
      cardColor: cardDark,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardDark,
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: textPrimary.withValues(alpha: 0.1)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
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
      dividerColor: textPrimary.withValues(alpha: 0.08),
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

  /// Broadcast stream – emits the new [AppThemeId] whenever the theme changes.
  final StreamController<AppThemeId> themeChanged =
      StreamController<AppThemeId>.broadcast();

  AppThemeId _current = AppThemeId.darkBlue;
  AppThemeId get current => _current;

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
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kAppThemeKey);
    if (saved != null) {
      final match = AppThemeId.values.where((e) => e.name == saved);
      if (match.isNotEmpty) _current = match.first;
    }
  }

  Future<void> saveTheme(AppThemeId id) async {
    _current = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppThemeKey, id.name);
    themeChanged.add(id);
  }

  static AppThemeData dataFor(AppThemeId id) =>
      themes.firstWhere((t) => t.id == id);
}

