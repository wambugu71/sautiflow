import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:sautiflow/sautiflow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../isolate_player.dart';
import '../models/autoeq_profile.dart';
import 'app_state_service.dart';
import 'autoeq_parser.dart';

class AutoEqService {
  AutoEqService._();
  static final AutoEqService instance = AutoEqService._();

  static const String _kCustomProfilesKey = 'sp_custom_autoeq_profiles_v2';
  static const String _kActiveProfileIdKey = 'sp_active_autoeq_profile_id_v2';

  final List<AutoEqProfileModel> _builtInProfiles = [];
  final List<AutoEqProfileModel> _customProfiles = [];
  AutoEqProfileModel? _activeProfile;
  bool _isInitialized = false;

  final StreamController<AutoEqProfileModel?> activeProfileChanged =
      StreamController<AutoEqProfileModel?>.broadcast();

  Stream<AutoEqProfileModel?> get onActiveProfileChanged =>
      activeProfileChanged.stream;

  List<AutoEqProfileModel> get builtInProfiles => List.unmodifiable(_builtInProfiles);
  List<AutoEqProfileModel> get customProfiles => List.unmodifiable(_customProfiles);
  List<AutoEqProfileModel> get allProfiles =>
      List.unmodifiable([..._builtInProfiles, ..._customProfiles]);
  AutoEqProfileModel? get activeProfile => _activeProfile;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadBuiltInManifest();
    await _loadCustomProfiles();
    await _loadActiveProfile();
  }

  Future<void> _loadBuiltInManifest() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/autoeq/manifest.json');
      final List rawList = jsonDecode(jsonStr) as List;

      _builtInProfiles.clear();
      for (final item in rawList) {
        if (item is Map) {
          final id = item['id'] as String;
          final name = item['name'] as String;
          final modelName = item['modelName'] as String;
          final brand = item['brand'] as String;
          final category = item['category'] as String? ?? 'Headphones';
          final target = item['target'] as String? ?? 'Harman Target';
          final typeStr = item['type'] as String;
          final isGraphic = typeStr == 'graphic';
          final type = isGraphic ? AutoEqType.graphic : AutoEqType.parametric;
          final preampDb = (item['preampDb'] as num?)?.toDouble() ?? 0.0;
          final assetPath = item['assetPath'] as String;

          String rawContent = '';
          try {
            rawContent = await rootBundle.loadString(assetPath);
          } catch (_) {}

          AutoEqResult? parsed;
          if (rawContent.isNotEmpty) {
            parsed = AutoEqParser.parseContent(rawContent, profileName: name);
          }

          _builtInProfiles.add(AutoEqProfileModel(
            id: id,
            name: name,
            modelName: modelName,
            brand: brand,
            category: category,
            target: target,
            type: type,
            preampDb: parsed?.preampGainDb ?? preampDb,
            assetPath: assetPath,
            rawContent: rawContent,
            isBuiltIn: true,
            parametricBands: parsed?.parametricBands ?? const [],
            graphicGains31: parsed?.bandGainDbs31 ?? const [],
            rawGraphicPairs: parsed?.rawGraphicPairs ?? const {},
          ));
        }
      }
    } catch (e) {
      // Manifest load fallback
    }
  }

  Future<void> _loadCustomProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_kCustomProfilesKey) ?? [];
      _customProfiles.clear();
      for (final jsonStr in rawList) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          _customProfiles.add(AutoEqProfileModel.fromJson(map));
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _loadActiveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeId = prefs.getString(_kActiveProfileIdKey);
      if (activeId != null && activeId.isNotEmpty) {
        _activeProfile = allProfiles.cast<AutoEqProfileModel?>().firstWhere(
              (p) => p?.id == activeId,
              orElse: () => null,
            );
      }
    } catch (_) {}
  }

  Future<void> _saveCustomProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _customProfiles.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_kCustomProfilesKey, list);
  }

  /// Imports an AutoEQ profile from raw string content (EqualizerAPO or GraphicEQ).
  Future<AutoEqProfileModel> importFromString({
    required String content,
    required String name,
    String brand = 'Custom',
  }) async {
    final parsed = AutoEqParser.parseContent(content, profileName: name);
    final isGraphic = parsed.isGraphicEq;
    final type = isGraphic ? AutoEqType.graphic : AutoEqType.parametric;

    final profile = AutoEqProfileModel(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      modelName: name,
      brand: brand,
      category: 'Imported',
      target: 'User Profile',
      type: type,
      preampDb: parsed.preampGainDb,
      rawContent: content,
      isBuiltIn: false,
      parametricBands: parsed.parametricBands,
      graphicGains31: parsed.bandGainDbs31,
      rawGraphicPairs: parsed.rawGraphicPairs,
    );

    _customProfiles.removeWhere((p) => p.name.toLowerCase() == name.toLowerCase());
    _customProfiles.insert(0, profile);
    await _saveCustomProfiles();
    return profile;
  }

  /// Imports an AutoEQ profile from a file (.txt or .csv).
  Future<AutoEqProfileModel> importFromFile(File file, {String? customName}) async {
    final content = await file.readAsString();
    final defaultName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : file.uri.pathSegments.last.replaceAll(RegExp(r'\.(txt|csv)$', caseSensitive: false), '');
    return importFromString(content: content, name: defaultName);
  }

  /// Deletes a user-imported custom profile.
  Future<void> deleteCustomProfile(String id) async {
    _customProfiles.removeWhere((p) => p.id == id);
    await _saveCustomProfiles();
    if (_activeProfile?.id == id) {
      _activeProfile = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActiveProfileIdKey);
      activeProfileChanged.add(null);
    }
  }

  /// Clears the active AutoEQ profile.
  Future<void> clearActiveProfile(IsolateAudioPlayer player) async {
    _activeProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveProfileIdKey);
    activeProfileChanged.add(null);
  }

  /// Applies the AutoEQ profile to the engine, routing to Parametric EQ or Graphic EQ.
  Future<void> applyProfile({
    required IsolateAudioPlayer player,
    required AutoEqProfileModel profile,
    int targetGraphicBands = 32,
    List<double>? customGraphicFrequencies,
  }) async {
    _activeProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveProfileIdKey, profile.id);

    // 1. Preamp Adjustment
    if (profile.preampDb != 0.0) {
      final linearGain = math.pow(10, profile.preampDb / 20.0).toDouble();
      player.setGain(linearGain);
    }

    // 2. Differentiate and Route where it belongs
    if (profile.isParametric) {
      // ─── Route to Parametric EQ Engine ───
      List<EqBandConfig> bands = profile.parametricBands;
      if (bands.isEmpty && profile.rawContent != null) {
        final parsed = AutoEqParser.parseContent(profile.rawContent!, profileName: profile.name);
        bands = parsed.parametricBands;
      }

      if (bands.isNotEmpty) {
        player.initMultibandFx(bands, enabled: true);
        player.setMultibandFxEnabled(true);

        final bandMaps = bands.map((b) => {
          'type': b.type.index,
          'frequency': b.frequencyHz,
          'gainDb': b.gainDb,
          'q': b.q,
          'slope': b.slope,
          'enabled': b.enabled,
        }).toList();

        await AppStateService.instance.saveParametricEq(
          enabled: true,
          bands: bandMaps,
        );
        await prefs.setString('sp_active_parametric_preset', profile.name);
      }
    } else {
      // ─── Route to Graphic EQ Engine ───
      List<double> freqs = customGraphicFrequencies ?? _getStandardFrequencies(targetGraphicBands);
      List<double> gains = [];

      if (profile.rawGraphicPairs.isNotEmpty) {
        gains = freqs
            .map((f) => AutoEqParser.interpolateGain(profile.rawGraphicPairs, f))
            .toList();
      } else if (profile.graphicGains31.isNotEmpty) {
        final map31 = <double, double>{};
        for (int i = 0; i < AutoEqParser.iso31CenterFreqs.length; i++) {
          if (i < profile.graphicGains31.length) {
            map31[AutoEqParser.iso31CenterFreqs[i]] = profile.graphicGains31[i];
          }
        }
        gains = freqs.map((f) => AutoEqParser.interpolateGain(map31, f)).toList();
      } else {
        gains = List.filled(freqs.length, 0.0);
      }

      player.initMultibandEq(freqs);
      for (int i = 0; i < gains.length; i++) {
        player.setMultibandEqBandGain(i, gains[i]);
      }
      player.setMultibandEqEnabled(true);

      await AppStateService.instance.saveEqBands(
        enabled: true,
        preset: profile.name,
        gains: gains,
        preampDb: profile.preampDb,
        bandCount: freqs.length,
      );
    }

    activeProfileChanged.add(profile);
  }

  static List<double> _getStandardFrequencies(int bands) {
    if (bands == 10) {
      return [32.0, 60.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
    } else if (bands == 16) {
      return [
        25.0, 40.0, 63.0, 100.0, 160.0, 250.0, 400.0, 630.0, 1000.0, 1600.0, 2500.0,
        4000.0, 6300.0, 10000.0, 16000.0, 20000.0
      ];
    } else {
      // 32 bands
      return [
        16.0, 20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0,
        250.0, 315.0, 400.0, 500.0, 630.0, 800.0, 1000.0, 1250.0, 1600.0, 2000.0,
        2500.0, 3150.0, 4000.0, 5000.0, 6300.0, 8000.0, 10000.0, 12500.0, 16000.0, 20000.0
      ];
    }
  }
}
