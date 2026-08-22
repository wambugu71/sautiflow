import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_profile.dart';
import '../eq_screen.dart';
import '../isolate_player.dart';
import 'package:sautiflow/sautiflow.dart';
import 'app_state_service.dart';

/// Service for managing audio profiles, saving user custom profiles,
/// exporting/importing profile files, and applying profiles to the engine.
class AudioProfileService {
  AudioProfileService._();
  static final AudioProfileService instance = AudioProfileService._();

  static const String _kUserProfilesKey = 'sp_user_audio_profiles';
  static const String _kActiveProfileIdKey = 'sp_active_profile_id';

  final StreamController<AudioProfile?> _activeProfileController =
      StreamController<AudioProfile?>.broadcast();
  Stream<AudioProfile?> get activeProfileStream =>
      _activeProfileController.stream;

  /// Retrieves all available profiles (Built-in + Custom User Profiles).
  Future<List<AudioProfile>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_kUserProfilesKey) ?? [];

    final customProfiles = rawList
        .map((s) {
          try {
            return AudioProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error parsing user profile: $e');
            return null;
          }
        })
        .whereType<AudioProfile>()
        .toList();

    return [..._getBuiltInProfiles(), ...customProfiles];
  }

  /// Gets the currently active profile (if any).
  Future<AudioProfile?> getActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_kActiveProfileIdKey);
    if (activeId == null || activeId.isEmpty) return null;

    final profiles = await getProfiles();
    return profiles.firstWhere((p) => p.id == activeId,
        orElse: () => profiles.first);
  }

  /// Saves or updates a user profile.
  Future<void> saveProfile(AudioProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_kUserProfilesKey) ?? [];

    final customProfiles = rawList
        .map((s) {
          try {
            return AudioProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<AudioProfile>()
        .toList();

    final existingIndex = customProfiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex >= 0) {
      customProfiles[existingIndex] =
          profile.copyWith(updatedAt: DateTime.now());
    } else {
      customProfiles.add(profile);
    }

    final encoded = customProfiles.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_kUserProfilesKey, encoded);
  }

  /// Deletes a custom profile by ID.
  Future<void> deleteProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_kUserProfilesKey) ?? [];

    final updated = rawList
        .map((s) {
          try {
            return AudioProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<AudioProfile>()
        .where((p) => p.id != id && !p.isBuiltIn)
        .map((p) => jsonEncode(p.toJson()))
        .toList();

    await prefs.setStringList(_kUserProfilesKey, updated);

    final activeId = prefs.getString(_kActiveProfileIdKey);
    if (activeId == id) {
      await prefs.remove(_kActiveProfileIdKey);
      _activeProfileController.add(null);
    }
  }

  /// Resets all built-in DSP effects and Sauti DSP Suite to baseline disabled defaults.
  Future<void> resetAllEffects(IsolateAudioPlayer player) async {
    // 1. Send all disable commands to the isolate audio engine ATOMICALLY (0ms latency)
    player.setReverbEnabled(false);
    player.setDelay(enabled: false, mix: 0.3, feedback: 0.4, delayMs: 250.0);
    player.setDynamicBass(enabled: false, preset: 18, gain: 15.0);
    player.setCrystalizer(enabled: false);
    player.setStereoEnhancement(enabled: false, mix: 0.5);
    player.setEqEnabled(false);
    player.setEq(low: 0.0, mid: 0.0, high: 0.0);
    player.setSpatializationEnabled(false);
    player.setCustomLpf1(enabled: false, cutoffHz: 500.0);
    player.setCustomHpf1(enabled: false, cutoffHz: 120.0);
    player.setLimiterEnabled(false);

    // Reset & disable all Sauti DSP Suite modules directly in engine
    player.resetDsp();
    player.setClarity(enabled: false);
    player.setHarmonicBass(enabled: false);
    player.setDynamicSystem(enabled: false);
    player.setAnalogWarmth(enabled: false);
    player.setConvolverEnabled(false);
    player.setMasterLimiter(enabled: false);
    await AppStateService.instance
        .saveSautiDspState({'dspMasterEnabled': false});
    await EqScreen.applySavedStateToEngine(player);

    // 2. Persist baseline disabled state to storage in parallel
    await Future.wait([
      AppStateService.instance.saveSpatialAudio(
          enabled: false, reverbMix: 0.25, roomSize: 0.3, echo: 0.15),
      AppStateService.instance
          .saveDelay(enabled: false, mix: 0.3, feedback: 0.4, time: 0.25),
      AppStateService.instance
          .saveDynamicBass(enabled: false, preset: 18, gain: 15.0),
      AppStateService.instance.saveCrystalizer(
          enabled: false,
          intensity: 0.5,
          highShelfEnabled: true,
          highShelfGainDb: 2.0),
      AppStateService.instance.saveCrossfeed(enabled: false, preset: 1),
      AppStateService.instance
          .saveStereoWiden(enabled: false, width: 1.5, delayMs: 15.0),
      AppStateService.instance.saveStereoEnhancement(enabled: false, mix: 0.5),
      AppStateService.instance
          .saveAudioTuning(enabled: false, low: 0.0, mid: 0.0, high: 0.0),
      AppStateService.instance
          .saveTrue3d(enabled: false, x: 0.0, y: 0.0, z: 0.0),
      AppStateService.instance.saveCustomLpf(enabled: false, cutoff: 500.0),
      AppStateService.instance.saveCustomHpf(enabled: false, cutoff: 120.0),
      AppStateService.instance.saveLimiter(
          enabled: false, threshold: 0.95, attackMs: 2.0, releaseMs: 50.0),
    ]);
  }

  /// Applies a full AudioProfile to the audio engine and updates AppStateService.
  Future<void> applyProfile(
      IsolateAudioPlayer player, AudioProfile profile) async {
    // Step 0: Clean baseline reset of all DSP effects to prevent leftover effects
    await resetAllEffects(player);

    // 1. Apply Graphic & Parametric EQ
    final eq = profile.eqState;
    if (eq.isNotEmpty) {
      final bool enabled = eq['enabled'] ?? true;
      final String presetName = profile.name;
      final List<double> gains =
          (eq['gains'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
              [];
      final List<double> freqs =
          (eq['freqs'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
              [];
      final double preampDb = (eq['preampDb'] as num?)?.toDouble() ?? 0.0;

      player.setMultibandEqEnabled(enabled);
      if (freqs.isNotEmpty) {
        player.initMultibandEq(freqs);
        for (int i = 0; i < gains.length; i++) {
          player.setMultibandEqBandGain(i, gains[i]);
        }
      }

      final gainLinear = math.pow(10, preampDb / 20.0).toDouble();
      player.setGain(gainLinear);

      await AppStateService.instance.saveEqBands(
        enabled: enabled,
        preset: presetName,
        gains: gains,
        preampDb: preampDb,
        bandCount: freqs.isNotEmpty ? freqs.length : 10,
      );
    }

    // 2. Apply Built-in DSP Effects
    final dsp = profile.dspEffectsState;
    if (dsp.isNotEmpty) {
      if (dsp.containsKey('spatial')) {
        final s = dsp['spatial'] as Map;
        final enabled = s['enabled'] ?? false;
        final reverbMix = (s['reverbMix'] as num?)?.toDouble() ?? 0.25;
        final roomSize = (s['roomSize'] as num?)?.toDouble() ?? 0.3;
        final echo = (s['echo'] as num?)?.toDouble() ?? 0.15;
        player.setReverbEnabled(enabled);
        await AppStateService.instance.saveSpatialAudio(
          enabled: enabled,
          reverbMix: reverbMix,
          roomSize: roomSize,
          echo: echo,
        );
      }

      if (dsp.containsKey('delay')) {
        final d = dsp['delay'] as Map;
        final enabled = d['enabled'] ?? false;
        final mix = (d['mix'] as num?)?.toDouble() ?? 0.3;
        final feedback = (d['feedback'] as num?)?.toDouble() ?? 0.4;
        final time = (d['time'] as num?)?.toDouble() ?? 0.25;
        player.setDelay(
            enabled: enabled,
            mix: mix,
            feedback: feedback,
            delayMs: time * 1000.0);
        await AppStateService.instance.saveDelay(
          enabled: enabled,
          mix: mix,
          feedback: feedback,
          time: time,
        );
      }

      if (dsp.containsKey('dynamicBass')) {
        final db = dsp['dynamicBass'] as Map;
        final enabled = db['enabled'] ?? false;
        final preset = (db['preset'] as num?)?.toInt() ?? 18;
        final gain = (db['gain'] as num?)?.toDouble() ?? 15.0;
        player.setDynamicBass(enabled: enabled, preset: preset, gain: gain);
        await AppStateService.instance.saveDynamicBass(
          enabled: enabled,
          preset: preset,
          gain: gain,
        );
      }

      if (dsp.containsKey('crystalizer')) {
        final c = dsp['crystalizer'] as Map;
        final enabled = c['enabled'] ?? false;
        final intensity = (c['intensity'] as num?)?.toDouble() ?? 0.5;
        final highShelf = c['highShelfEnabled'] ?? true;
        final shelfGain = (c['highShelfGainDb'] as num?)?.toDouble() ?? 2.0;
        player.setCrystalizer(enabled: enabled);
        await AppStateService.instance.saveCrystalizer(
          enabled: enabled,
          intensity: intensity,
          highShelfEnabled: highShelf,
          highShelfGainDb: shelfGain,
        );
      }

      if (dsp.containsKey('crossfeed')) {
        final cf = dsp['crossfeed'] as Map;
        final enabled = cf['enabled'] ?? false;
        final preset = (cf['preset'] as num?)?.toInt() ?? 1;
        player.setCrossfeed(enabled: enabled, preset: preset);
        await AppStateService.instance
            .saveCrossfeed(enabled: enabled, preset: preset);
      }

      if (dsp.containsKey('stereoWiden')) {
        final sw = dsp['stereoWiden'] as Map;
        final enabled = sw['enabled'] ?? false;
        final width = (sw['width'] as num?)?.toDouble() ?? 1.5;
        final delayMs = (sw['delayMs'] as num?)?.toDouble() ?? 15.0;
        await AppStateService.instance.saveStereoWiden(
          enabled: enabled,
          width: width,
          delayMs: delayMs,
        );
      }

      if (dsp.containsKey('stereoEnhancement')) {
        final se = dsp['stereoEnhancement'] as Map;
        final enabled = se['enabled'] ?? false;
        final mix = (se['mix'] as num?)?.toDouble() ?? 0.5;
        player.setStereoEnhancement(enabled: enabled, mix: mix);
        await AppStateService.instance
            .saveStereoEnhancement(enabled: enabled, mix: mix);
      }

      if (dsp.containsKey('audioTuning')) {
        final at = dsp['audioTuning'] as Map;
        final enabled = at['enabled'] ?? false;
        final low = (at['low'] as num?)?.toDouble() ?? 0.0;
        final mid = (at['mid'] as num?)?.toDouble() ?? 0.0;
        final high = (at['high'] as num?)?.toDouble() ?? 0.0;
        player.setEqEnabled(enabled);
        player.setEq(low: low, mid: mid, high: high);
        await AppStateService.instance.saveAudioTuning(
          enabled: enabled,
          low: low,
          mid: mid,
          high: high,
        );
      }

      if (dsp.containsKey('true3d')) {
        final t3d = dsp['true3d'] as Map;
        final enabled = t3d['enabled'] ?? false;
        final x = (t3d['x'] as num?)?.toDouble() ?? 0.0;
        final y = (t3d['y'] as num?)?.toDouble() ?? 0.0;
        final z = (t3d['z'] as num?)?.toDouble() ?? 0.0;
        player.setSpatializationEnabled(enabled);
        await AppStateService.instance
            .saveTrue3d(enabled: enabled, x: x, y: y, z: z);
      }

      if (dsp.containsKey('limiter')) {
        final l = dsp['limiter'] as Map;
        final enabled = l['enabled'] ?? false;
        final threshold = (l['threshold'] as num?)?.toDouble() ?? 0.95;
        final attack = (l['attackMs'] as num?)?.toDouble() ?? 2.0;
        final release = (l['releaseMs'] as num?)?.toDouble() ?? 50.0;
        player.setLimiterEnabled(enabled);
        await AppStateService.instance.saveLimiter(
          enabled: enabled,
          threshold: threshold,
          attackMs: attack,
          releaseMs: release,
        );
      }
    }

    // 3. Apply Sauti DSP Suite State
    final cleanDspState = <String, dynamic>{
      'dspMasterEnabled': profile.sautiDspState['dspMasterEnabled'] ?? false,
      'clarityEnabled': false,
      'bassEnabled': false,
      'dynamicSystemEnabled': false,
      'analogWarmthEnabled': false,
      'convolverEnabled': false,
      'limiterEnabled': false,
      ...profile.sautiDspState,
    };
    await AppStateService.instance.saveSautiDspState(cleanDspState);
    await EqScreen.applySavedStateToEngine(player);

    // 4. Save active profile ID & notify listeners
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveProfileIdKey, profile.id);
    _activeProfileController.add(profile);
    AppStateService.instance.eqSettingsChanged.add(null);
  }

  /// Exports an AudioProfile to a file on disk.
  Future<void> exportProfile(AudioProfile profile, String targetPath) async {
    final file = File(targetPath);
    await file.writeAsString(jsonEncode(profile.toJson()));
  }

  /// Imports an AudioProfile from a JSON file.
  Future<AudioProfile> importProfile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final Map<String, dynamic> json =
        jsonDecode(content) as Map<String, dynamic>;
    final imported = AudioProfile.fromJson(json);

    final newProfile = imported.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      isBuiltIn: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await saveProfile(newProfile);
    return newProfile;
  }

  /// Built-in factory audio profiles.
  List<AudioProfile> _getBuiltInProfiles() {
    final defaultFrequencies = [
      32.0,
      60.0,
      125.0,
      250.0,
      500.0,
      1000.0,
      2000.0,
      4000.0,
      8000.0,
      16000.0
    ];

    return [
      AudioProfile(
        id: 'builtin_flat',
        name: 'Flat / Reference',
        category: 'Reference',
        description: 'Neutral frequency response with zero processing.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': true,
          'preampDb': 0.0,
          'freqs': defaultFrequencies,
          'gains': List<double>.filled(10, 0.0),
        },
        dspEffectsState: {},
        sautiDspState: {'dspMasterEnabled': false},
      ),
      AudioProfile(
        id: 'builtin_basshead',
        name: 'Bass Boost Extreme',
        category: 'Headphones',
        description: 'Deep sub-bass amplification and dynamic bass processing.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': false,
          'preampDb': -3.0,
          'freqs': defaultFrequencies,
          'gains': [6.0, 5.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        },
        dspEffectsState: {
          'dynamicBass': {'enabled': false, 'preset': 18, 'gain': 18.0}
        },
        sautiDspState: {
          'dspMasterEnabled': true,
          'bassEnabled': true,
          'bassProfile': HarmonicBassProfile.pureBass.value,
          'bassCutoffHz': 60.0,
          'bassBoost': 0.85,
          'dynamicSystemEnabled': false,
          'dynamicSystemProfile': TransducerProfile.extremeSubwoofer.value,
          'dynamicSystemStrength': 0.75,
        },
      ),
      AudioProfile(
        id: 'builtin_vocal',
        name: 'Vocal & Podcast',
        category: 'Genre',
        description: 'Enhanced mid-range clarity and speech intelligibility.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': true,
          'preampDb': -1.0,
          'freqs': defaultFrequencies,
          'gains': [-2.0, -2.0, -2.0, 1.0, 3.0, 4.0, 3.0, 1.0, -1.0, -1.0],
        },
        dspEffectsState: {
          'crystalizer': {
            'enabled': true,
            'intensity': 0.4,
            'highShelfEnabled': true,
            'highShelfGainDb': 1.5
          }
        },
        sautiDspState: {
          'dspMasterEnabled': true,
          'clarityEnabled': true,
          'clarityProfile': AudioClarityProfile.presenceExciter.value,
          'clarityIntensity': 0.6,
        },
      ),
      AudioProfile(
        id: 'builtin_rock',
        name: 'Rock & Dynamics',
        category: 'Genre',
        description:
            'V-shaped frequency response for impactful drums and guitars.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': true,
          'preampDb': -2.5,
          'freqs': defaultFrequencies,
          'gains': [5.0, 4.0, 2.0, -1.0, -2.0, -1.0, 1.0, 3.0, 4.0, 5.0],
        },
        dspEffectsState: {},
        sautiDspState: {
          'dspMasterEnabled': true,
          'analogWarmthEnabled': true,
          'analogWarmthProfile': AnalogWarmthProfile.triode12AX7.value,
          'analogWarmthDrive': 0.45,
        },
      ),
      AudioProfile(
        id: 'builtin_audiophile',
        name: 'Audiophile Acoustic',
        category: 'Headphones',
        description: 'crosstalk cancellation and transparent tone controls.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': true,
          'preampDb': 0.0,
          'freqs': defaultFrequencies,
          'gains': List<double>.filled(10, 0.0),
        },
        dspEffectsState: {
          'crossfeed': {'enabled': true, 'preset': 4},
          'stereoEnhancement': {'enabled': true, 'mix': 0.35},
        },
        sautiDspState: {
          'dspMasterEnabled': true,
          'analogWarmthEnabled': true,
          'analogWarmthProfile': AnalogWarmthProfile.vintagePreamp.value,
          'analogWarmthDrive': 0.35,
          'clarityEnabled': true,
          'clarityProfile': AudioClarityProfile.airShelf.value,
          'clarityIntensity': 0.4,
        },
      ),
      AudioProfile(
        id: 'builtin_cinema_3d',
        name: 'surround',
        category: 'Speakers',
        description: 'Good for long listening.',
        isBuiltIn: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        eqState: {
          'enabled': true,
          'preampDb': 0.0,
          'freqs': defaultFrequencies,
          'gains': [2.0, 1.0, 0.0, 0.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0],
        },
        dspEffectsState: {},
        sautiDspState: {
          'dspMasterEnabled': true,
          'dynamicSystemEnabled': true,
          'dynamicSystemProfile': TransducerProfile.highEndReference.value,
          'dynamicSystemStrength': 0.6,
          'clarityEnabled': true,
          'clarityProfile': AudioClarityProfile.harmonicBrilliance.value,
          'clarityIntensity': 0.5,
        },
      ),
    ];
  }
}
