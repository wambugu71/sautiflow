import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  system(null, 'System Default', 'Mfumo Chaguomsingi', 'የስርዓቱ መደበኛ'),
  english(Locale('en'), 'English', 'Kiingereza', 'እንግሊዝኛ'),
  swahili(Locale('sw'), 'Kiswahili', 'Kiswahili', 'ስዋሂሊኛ'),
  amharic(Locale('am'), 'አማርኛ', 'Kiamhari', 'አማርኛ');

  final Locale? locale;
  final String nativeName;
  final String swahiliName;
  final String amharicName;

  const AppLanguage(
    this.locale,
    this.nativeName,
    this.swahiliName,
    this.amharicName,
  );

  static AppLanguage fromLocale(Locale? locale) {
    if (locale == null) return AppLanguage.system;
    return AppLanguage.values.firstWhere(
      (lang) => lang.locale?.languageCode == locale.languageCode,
      orElse: () => AppLanguage.system,
    );
  }
}

class AppLocaleService {
  AppLocaleService._();
  static final AppLocaleService instance = AppLocaleService._();

  static const _kLocaleKey = 'sp_app_language_code';
  Locale? _currentLocale;

  /// Broadcast stream emitting the active [Locale] (or null for system default).
  final StreamController<Locale?> localeChanged =
      StreamController<Locale?>.broadcast();

  Locale? get currentLocale => _currentLocale;

  AppLanguage get currentLanguage => AppLanguage.fromLocale(_currentLocale);

  /// Loads the persisted language selection from SharedPreferences.
  Future<void> loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kLocaleKey);
      if (code == null || code.isEmpty || code == 'system') {
        _currentLocale = null;
      } else {
        _currentLocale = Locale(code);
      }
    } catch (_) {
      _currentLocale = null;
    }
    localeChanged.add(_currentLocale);
  }

  /// Sets and persists a new language. Pass `null` for system default.
  Future<void> setLocale(Locale? locale) async {
    _currentLocale = locale;
    localeChanged.add(_currentLocale);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_kLocaleKey);
      } else {
        await prefs.setString(_kLocaleKey, locale.languageCode);
      }
    } catch (_) {
      // Ignored
    }
  }
}
