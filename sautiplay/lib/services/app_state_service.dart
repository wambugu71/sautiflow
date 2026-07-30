import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service for persisting and restoring all app state across
/// restarts: playback queue, EQ settings, and user preferences/settings.

enum ReplayGainMode {
  none,
  track,
  album
}
class AppStateService {
  AppStateService._();
  static final AppStateService instance = AppStateService._();

  // Stream to notify listeners of EQ changes
  final StreamController<void> eqSettingsChanged =
      StreamController<void>.broadcast();

  // Stream to notify listeners of ReplayGain changes
  final StreamController<void> replayGainChanged =
      StreamController<void>.broadcast();

  // ─── Playback ───────────────────────────────────────────────────────────────
  static const _kQueueJson = 'sp_queue_json';
  static const _kQueueIndex = 'sp_queue_index';
  static const _kQueuePositionMs = 'sp_queue_position_ms';

  Future<void> saveQueue({
    required List<Map<String, dynamic>> tracks,
    required int index,
    required int positionMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = tracks.map((t) => jsonEncode(t)).toList();
    await prefs.setStringList(_kQueueJson, encoded);
    await prefs.setInt(_kQueueIndex, index);
    await prefs.setInt(_kQueuePositionMs, positionMs);
  }

  Future<({List<Map<String, dynamic>> tracks, int index, int positionMs})>
      loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQueueJson) ?? [];
    final tracks = raw
        .map<Map<String, dynamic>>((s) {
          try {
            return Map<String, dynamic>.from(jsonDecode(s) as Map);
          } catch (_) {
            return {};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
    final index = prefs.getInt(_kQueueIndex) ?? 0;
    final positionMs = prefs.getInt(_kQueuePositionMs) ?? 0;
    return (tracks: tracks, index: index, positionMs: positionMs);
  }

  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueueJson);
    await prefs.remove(_kQueueIndex);
    await prefs.remove(_kQueuePositionMs);
  }

  // ─── EQ – Graphic EQ + Preamp ─────────────────────────────────────────────────
  static const _kEqEnabled = 'sp_eq_enabled';
  static const _kEqPreset = 'sp_eq_preset';
  static const _kEqGains = 'sp_eq_gains';
  static const _kPreampDb = 'sp_preamp_db';
  static const _kEqBandCount = 'sp_eq_band_count';

  Future<void> saveEqBands({
    required bool enabled,
    required String preset,
    required List<double> gains,
    required double preampDb,
    required int bandCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prevBandCount = prefs.getInt(_kEqBandCount);

    await prefs.setBool(_kEqEnabled, enabled);
    await prefs.setString(_kEqPreset, preset);
    await prefs.setStringList(
        _kEqGains, gains.map((g) => g.toString()).toList());
    await prefs.setDouble(_kPreampDb, preampDb);
    await prefs.setInt(_kEqBandCount, bandCount);

    if (prevBandCount != null && prevBandCount != bandCount) {
      eqSettingsChanged.add(null);
    }
  }

  Future<
      ({
        bool enabled,
        String preset,
        List<double> gains,
        double preampDb,
        int bandCount
      })> loadEqBands() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEqEnabled) ?? true;
    final preset = prefs.getString(_kEqPreset) ?? 'Flat';
    final bandCount = prefs.getInt(_kEqBandCount) ?? 10;

    final rawGains = prefs.getStringList(_kEqGains);
    final gains = rawGains != null
        ? rawGains.map((s) => double.tryParse(s) ?? 0.0).toList()
        : List<double>.filled(bandCount, 0.0);

    final preampDb = prefs.getDouble(_kPreampDb) ?? 0.0;

    return (
      enabled: enabled,
      preset: preset,
      gains: gains,
      preampDb: preampDb,
      bandCount: bandCount
    );
  }

  // ─── EQ – Spatial Audio / Reverb ──────────────────────────────────────────
  static const _kSpatialEnabled = 'sp_spatial_enabled';
  static const _kReverbMix = 'sp_reverb_mix';
  static const _kRoomSize = 'sp_room_size';
  static const _kEcho = 'sp_echo';

  Future<void> saveSpatialAudio({
    required bool enabled,
    required double reverbMix,
    required double roomSize,
    required double echo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpatialEnabled, enabled);
    await prefs.setDouble(_kReverbMix, reverbMix);
    await prefs.setDouble(_kRoomSize, roomSize);
    await prefs.setDouble(_kEcho, echo);
  }

  Future<({bool enabled, double reverbMix, double roomSize, double echo})>
      loadSpatialAudio() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kSpatialEnabled) ?? false,
      reverbMix: prefs.getDouble(_kReverbMix) ?? 0.25,
      roomSize: prefs.getDouble(_kRoomSize) ?? 0.3,
      echo: prefs.getDouble(_kEcho) ?? 0.15,
    );
  }

  // ─── EQ – Delay / Echo ────────────────────────────────────────────────────
  static const _kDelayEnabled = 'sp_delay_enabled';
  static const _kDelayMix = 'sp_delay_mix';
  static const _kDelayFeedback = 'sp_delay_feedback';
  static const _kDelayTime = 'sp_delay_time';

  // ─── EQ – Stereo Widen ────────────────────────────────────────────────────
  static const _kStereoWidenEnabled = 'sp_stereo_widen_enabled';
  static const _kStereoWidenWidth = 'sp_stereo_widen_width';
  static const _kStereoWidenDelayMs = 'sp_stereo_widen_delay_ms';

  static const _kCrossfeedEnabled = 'sp_crossfeed_enabled';
  static const _kCrossfeedPreset = 'sp_crossfeed_preset';

  static const _kDynamicBassEnabled = 'sp_dynamic_bass_enabled';
  static const _kDynamicBassPreset = 'sp_dynamic_bass_preset';
  static const _kDynamicBassGain = 'sp_dynamic_bass_gain';

  Future<void> saveDelay({
    required bool enabled,
    required double mix,
    required double feedback,
    required double time,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDelayEnabled, enabled);
    await prefs.setDouble(_kDelayMix, mix);
    await prefs.setDouble(_kDelayFeedback, feedback);
    await prefs.setDouble(_kDelayTime, time);
  }

  Future<({bool enabled, double mix, double feedback, double time})>
      loadDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kDelayEnabled) ?? false,
      mix: prefs.getDouble(_kDelayMix) ?? 0.3,
      feedback: prefs.getDouble(_kDelayFeedback) ?? 0.4,
      time: prefs.getDouble(_kDelayTime) ?? 0.25,
    );
  }

  Future<void> saveStereoWiden({
    required bool enabled,
    required double width,
    required double delayMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStereoWidenEnabled, enabled);
    await prefs.setDouble(_kStereoWidenWidth, width);
    await prefs.setDouble(_kStereoWidenDelayMs, delayMs);
  }

  Future<({bool enabled, double width, double delayMs})>
      loadStereoWiden() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kStereoWidenEnabled) ?? false,
      width: prefs.getDouble(_kStereoWidenWidth) ?? 1.5,
      delayMs: prefs.getDouble(_kStereoWidenDelayMs) ?? 15.0,
    );
  }

  Future<void> saveCrossfeed({
    required bool enabled,
    required int preset,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCrossfeedEnabled, enabled);
    await prefs.setInt(_kCrossfeedPreset, preset);
  }

  Future<({bool enabled, int preset})> loadCrossfeed() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kCrossfeedEnabled) ?? false,
      preset: prefs.getInt(_kCrossfeedPreset) ?? 0,
    );
  }

  Future<void> saveDynamicBass({
    required bool enabled,
    required int preset,
    required double gain,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamicBassEnabled, enabled);
    await prefs.setInt(_kDynamicBassPreset, preset);
    await prefs.setDouble(_kDynamicBassGain, gain);
  }

  Future<({bool enabled, int preset, double gain})> loadDynamicBass() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kDynamicBassEnabled) ?? false,
      preset: prefs.getInt(_kDynamicBassPreset) ?? 18,
      gain: prefs.getDouble(_kDynamicBassGain) ?? 15.0,
    );
  }

  // ─── EQ – Crystalizer ─────────────────────────────────────────────────────
  static const _kCrystalizerEnabled = 'sp_crystalizer_enabled';
  static const _kCrystalizerIntensity = 'sp_crystalizer_intensity';
  static const _kCrystalizerHighShelf = 'sp_crystalizer_high_shelf';
  static const _kCrystalizerShelfGain = 'sp_crystalizer_shelf_gain';

  Future<void> saveCrystalizer({
    required bool enabled,
    required double intensity,
    required bool highShelfEnabled,
    required double highShelfGainDb,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCrystalizerEnabled, enabled);
    await prefs.setDouble(_kCrystalizerIntensity, intensity);
    await prefs.setBool(_kCrystalizerHighShelf, highShelfEnabled);
    await prefs.setDouble(_kCrystalizerShelfGain, highShelfGainDb);
  }

  Future<
      ({
        bool enabled,
        double intensity,
        bool highShelfEnabled,
        double highShelfGainDb
      })> loadCrystalizer() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kCrystalizerEnabled) ?? false,
      intensity: prefs.getDouble(_kCrystalizerIntensity) ?? 0.5,
      highShelfEnabled: prefs.getBool(_kCrystalizerHighShelf) ?? true,
      highShelfGainDb: prefs.getDouble(_kCrystalizerShelfGain) ?? 2.0,
    );
  }

  // ─── EQ – Audio Tuning (3-band) ───────────────────────────────────────────
  static const _kAudioTuningEnabled = 'sp_audio_tuning_enabled';
  static const _kTuneLow = 'sp_tune_low';
  static const _kTuneMid = 'sp_tune_mid';
  static const _kTuneHigh = 'sp_tune_high';

  Future<void> saveAudioTuning({
    required bool enabled,
    required double low,
    required double mid,
    required double high,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAudioTuningEnabled, enabled);
    await prefs.setDouble(_kTuneLow, low);
    await prefs.setDouble(_kTuneMid, mid);
    await prefs.setDouble(_kTuneHigh, high);
  }

  Future<({bool enabled, double low, double mid, double high})>
      loadAudioTuning() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kAudioTuningEnabled) ?? false,
      low: prefs.getDouble(_kTuneLow) ?? 1.0,
      mid: prefs.getDouble(_kTuneMid) ?? 1.0,
      high: prefs.getDouble(_kTuneHigh) ?? 1.0,
    );
  }

  // ─── EQ – True 3D Spatialization ──────────────────────────────────────────
  static const _kTrue3dEnabled = 'sp_true3d_enabled';
  static const _kSpatX = 'sp_spat_x';
  static const _kSpatY = 'sp_spat_y';
  static const _kSpatZ = 'sp_spat_z';

  Future<void> saveTrue3d({
    required bool enabled,
    required double x,
    required double y,
    required double z,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTrue3dEnabled, enabled);
    await prefs.setDouble(_kSpatX, x);
    await prefs.setDouble(_kSpatY, y);
    await prefs.setDouble(_kSpatZ, z);
  }

  Future<({bool enabled, double x, double y, double z})> loadTrue3d() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kTrue3dEnabled) ?? false,
      x: prefs.getDouble(_kSpatX) ?? 0.0,
      y: prefs.getDouble(_kSpatY) ?? 0.0,
      z: prefs.getDouble(_kSpatZ) ?? 0.0,
    );
  }

  // ─── EQ – Custom LPF ──────────────────────────────────────────────────────
  static const _kLpfEnabled = 'sp_custom_lpf_enabled';
  static const _kLpfCutoff = 'sp_custom_lpf_cutoff';

  Future<void> saveCustomLpf({
    required bool enabled,
    required double cutoff,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLpfEnabled, enabled);
    await prefs.setDouble(_kLpfCutoff, cutoff);
  }

  Future<({bool enabled, double cutoff})> loadCustomLpf() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kLpfEnabled) ?? false,
      cutoff: prefs.getDouble(_kLpfCutoff) ?? 500.0,
    );
  }

  // ─── EQ – Custom HPF ──────────────────────────────────────────────────────
  static const _kHpfEnabled = 'sp_custom_hpf_enabled';
  static const _kHpfCutoff = 'sp_custom_hpf_cutoff';

  Future<void> saveCustomHpf({
    required bool enabled,
    required double cutoff,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHpfEnabled, enabled);
    await prefs.setDouble(_kHpfCutoff, cutoff);
  }

  Future<({bool enabled, double cutoff})> loadCustomHpf() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kHpfEnabled) ?? false,
      cutoff: prefs.getDouble(_kHpfCutoff) ?? 120.0,
    );
  }

  // ─── EQ – Limiter ─────────────────────────────────────────────────────────
  static const _kLimiterEnabled = 'sp_limiter_enabled';
  static const _kLimiterThreshold = 'sp_limiter_threshold';
  static const _kLimiterAttack = 'sp_limiter_attack_ms';
  static const _kLimiterRelease = 'sp_limiter_release_ms';

  Future<void> saveLimiter({
    required bool enabled,
    required double threshold,
    required double attackMs,
    required double releaseMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLimiterEnabled, enabled);
    await prefs.setDouble(_kLimiterThreshold, threshold);
    await prefs.setDouble(_kLimiterAttack, attackMs);
    await prefs.setDouble(_kLimiterRelease, releaseMs);
  }

  Future<({bool enabled, double threshold, double attackMs, double releaseMs})>
      loadLimiter() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kLimiterEnabled) ?? false,
      threshold: prefs.getDouble(_kLimiterThreshold) ?? 0.95,
      attackMs: prefs.getDouble(_kLimiterAttack) ?? 2.0,
      releaseMs: prefs.getDouble(_kLimiterRelease) ?? 50.0,
    );
  }

  // ─── EQ – Parametric EQ ───────────────────────────────────────────────────
  static const _kParametricEqEnabled = 'sp_parametric_eq_enabled';
  static const _kParametricEqBands = 'sp_parametric_eq_bands'; // JSON list

  /// Each band is stored as a JSON object:
  /// {type, frequency, q, gainDb, slope, enabled}
  Future<void> saveParametricEq({
    required bool enabled,
    required List<Map<String, dynamic>> bands,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kParametricEqEnabled, enabled);
    await prefs.setStringList(
      _kParametricEqBands,
      bands.map(jsonEncode).toList(),
    );
  }

  Future<({bool enabled, List<Map<String, dynamic>> bands})>
      loadParametricEq() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kParametricEqEnabled) ?? false;
    final raw = prefs.getStringList(_kParametricEqBands);
    final bands = raw != null
        ? raw
            .map<Map<String, dynamic>>((s) {
              try {
                return Map<String, dynamic>.from(jsonDecode(s) as Map);
              } catch (_) {
                return {};
              }
            })
            .where((m) => m.isNotEmpty)
            .toList()
        : <Map<String, dynamic>>[];
    return (enabled: enabled, bands: bands);
  }

  // ─── EQ – Custom Biquad ───────────────────────────────────────────────────
  static const _kBiquadEnabled = 'sp_biquad_enabled';
  static const _kBiquadB0 = 'sp_biquad_b0';
  static const _kBiquadB1 = 'sp_biquad_b1';
  static const _kBiquadB2 = 'sp_biquad_b2';
  static const _kBiquadA0 = 'sp_biquad_a0';
  static const _kBiquadA1 = 'sp_biquad_a1';
  static const _kBiquadA2 = 'sp_biquad_a2';

  Future<void> saveCustomBiquad({
    required bool enabled,
    required double b0,
    required double b1,
    required double b2,
    required double a0,
    required double a1,
    required double a2,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiquadEnabled, enabled);
    await prefs.setDouble(_kBiquadB0, b0);
    await prefs.setDouble(_kBiquadB1, b1);
    await prefs.setDouble(_kBiquadB2, b2);
    await prefs.setDouble(_kBiquadA0, a0);
    await prefs.setDouble(_kBiquadA1, a1);
    await prefs.setDouble(_kBiquadA2, a2);
  }

  Future<
      ({
        bool enabled,
        double b0,
        double b1,
        double b2,
        double a0,
        double a1,
        double a2
      })> loadCustomBiquad() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kBiquadEnabled) ?? false,
      b0: prefs.getDouble(_kBiquadB0) ?? 1.0,
      b1: prefs.getDouble(_kBiquadB1) ?? 0.0,
      b2: prefs.getDouble(_kBiquadB2) ?? 0.0,
      a0: prefs.getDouble(_kBiquadA0) ?? 1.0,
      a1: prefs.getDouble(_kBiquadA1) ?? 0.0,
      a2: prefs.getDouble(_kBiquadA2) ?? 0.0,
    );
  }

  // ─── Settings – Output / Engine ──────────────────────────────────────────
  static const _kOutputFormat = 'sp_output_format';
  static const _kSampleRate = 'sp_sample_rate';
  static const _kChannels = 'sp_channels';
  static const _kCrossfadeEnabled = 'sp_crossfade_enabled';
  static const _kCrossfadeMs = 'sp_crossfade_ms';
  static const _kAnalyzerEnabled = 'sp_analyzer_enabled';
  static const _kAnalyzerType = 'sp_analyzer_type';
  static const _kAnalyzerSampleSize = 'sp_analyzer_sample_size';
  static const _kAllowInvalidTls = 'sp_allow_invalid_tls';
  static const _kExclusiveMode = 'sp_exclusive_mode';
  static const _kAnalyzerAutoFit = 'sp_analyzer_auto_fit';
  static const _kAnalyzerShowGrids = 'sp_analyzer_show_grids';
  static const _kAnalyzerLogScale = 'sp_analyzer_log_scale';
  static const _kSpectrumStyle = 'sp_spectrum_style';

  Future<void> saveEngineSettings({
    required int outputFormatIndex,
    required int sampleRate,
    required int channels,
    required bool crossfadeEnabled,
    required int crossfadeMs,
    required bool analyzerEnabled,
    required String analyzerType,
    required int analyzerSampleSize,
    required bool allowInvalidTls,
    required bool exclusiveMode,
    required bool analyzerAutoFit,
    required bool analyzerShowGrids,
    required bool analyzerLogScale,
    required String spectrumStyle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOutputFormat, outputFormatIndex);
    await prefs.setInt(_kSampleRate, sampleRate);
    await prefs.setInt(_kChannels, channels);
    await prefs.setBool(_kCrossfadeEnabled, crossfadeEnabled);
    await prefs.setInt(_kCrossfadeMs, crossfadeMs);
    await prefs.setBool(_kAnalyzerEnabled, analyzerEnabled);
    await prefs.setString(_kAnalyzerType, analyzerType);
    await prefs.setInt(_kAnalyzerSampleSize, analyzerSampleSize);
    await prefs.setBool(_kAllowInvalidTls, allowInvalidTls);
    await prefs.setBool(_kExclusiveMode, exclusiveMode);
    await prefs.setBool(_kAnalyzerAutoFit, analyzerAutoFit);
    await prefs.setBool(_kAnalyzerShowGrids, analyzerShowGrids);
    await prefs.setBool(_kAnalyzerLogScale, analyzerLogScale);
    await prefs.setString(_kSpectrumStyle, spectrumStyle);
  }

  Future<
      ({
        int outputFormatIndex,
        int sampleRate,
        int channels,
        bool crossfadeEnabled,
        int crossfadeMs,
        bool analyzerEnabled,
        String analyzerType,
        int analyzerSampleSize,
        bool allowInvalidTls,
        bool exclusiveMode,
        bool analyzerAutoFit,
        bool analyzerShowGrids,
        bool analyzerLogScale,
        String spectrumStyle
      })> loadEngineSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      outputFormatIndex: prefs.getInt(_kOutputFormat) ?? 0, // 0 = f32
      sampleRate: prefs.getInt(_kSampleRate) ?? 0,
      channels: prefs.getInt(_kChannels) ?? 2,
      crossfadeEnabled: prefs.getBool(_kCrossfadeEnabled) ?? false,
      crossfadeMs: prefs.getInt(_kCrossfadeMs) ?? 250,
      analyzerEnabled: prefs.getBool(_kAnalyzerEnabled) ?? true,
      analyzerType: prefs.getString(_kAnalyzerType) ?? 'area',
      analyzerSampleSize: prefs.getInt(_kAnalyzerSampleSize) ?? 1024,
      allowInvalidTls: prefs.getBool(_kAllowInvalidTls) ?? false,
      exclusiveMode: prefs.getBool(_kExclusiveMode) ?? false,
      analyzerAutoFit: prefs.getBool(_kAnalyzerAutoFit) ?? true,
      analyzerShowGrids: prefs.getBool(_kAnalyzerShowGrids) ?? true,
      analyzerLogScale: prefs.getBool(_kAnalyzerLogScale) ?? true,
      spectrumStyle: prefs.getString(_kSpectrumStyle) ?? 'neon',
    );
  }

  // ─── Settings – UI / Streaming preferences ───────────────────────────────
  static const _kStreamingQuality = 'sp_streaming_quality';
  static const _kGaplessPlayback = 'sp_gapless_playback';
  static const _kNormalizeVolume = 'sp_normalize_volume';
  static const _kStreamOverWifi = 'sp_stream_over_wifi';
  static const _kResampleAlgorithm = 'sp_resample_algorithm';
  static const _kDitherMode = 'sp_dither_mode';

  Future<void> saveUiSettings({
    required String streamingQuality,
    required bool gaplessPlayback,
    required bool normalizeVolume,
    required bool streamOverWifi,
    required int resampleAlgorithm,
    required int ditherMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStreamingQuality, streamingQuality);
    await prefs.setBool(_kGaplessPlayback, gaplessPlayback);
    await prefs.setBool(_kNormalizeVolume, normalizeVolume);
    await prefs.setBool(_kStreamOverWifi, streamOverWifi);
    await prefs.setInt(_kResampleAlgorithm, resampleAlgorithm);
    await prefs.setInt(_kDitherMode, ditherMode);
  }

  Future<
      ({
        String streamingQuality,
        bool gaplessPlayback,
        bool normalizeVolume,
        bool streamOverWifi,
        int resampleAlgorithm,
        int ditherMode,
      })> loadUiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      streamingQuality: prefs.getString(_kStreamingQuality) ?? 'High Fidelity',
      gaplessPlayback: prefs.getBool(_kGaplessPlayback) ?? true,
      normalizeVolume: prefs.getBool(_kNormalizeVolume) ?? false,
      streamOverWifi: prefs.getBool(_kStreamOverWifi) ?? true,
      resampleAlgorithm: prefs.getInt(_kResampleAlgorithm) ?? 0,
      ditherMode: prefs.getInt(_kDitherMode) ?? 0,
    );
  }

  // ─── ViPER DSP Settings ───────────────────────────────────────────────────
  static const _kViperFxState = 'sp_viper_fx_state';

  Future<void> saveViperFxState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kViperFxState, jsonEncode(state));
  }

  Future<Map<String, dynamic>> loadViperFxState() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kViperFxState);
    if (str != null && str.isNotEmpty) {
      try {
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  // ─── DSP Oversampling Settings ───────────────────────────────────────────
  static const _kDspOversampling = 'sp_dsp_oversampling';

  Future<void> saveDspOversampling(int factor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDspOversampling, factor);
  }

  Future<int> loadDspOversampling() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kDspOversampling) ?? 1;
  }

  // ─── ReplayGain Settings ──────────────────────────────────────────────────
  static const _kReplayGainMode = 'sp_replay_gain_mode';
  static const _kReplayGainPreamp = 'sp_replay_gain_preamp';

  Future<void> saveReplayGainSettings({
    required ReplayGainMode mode,
    required double preamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReplayGainMode, mode.index);
    await prefs.setDouble(_kReplayGainPreamp, preamp);
    replayGainChanged.add(null);
  }

  Future<({ReplayGainMode mode, double preamp})> loadReplayGainSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_kReplayGainMode) ?? 0;
    final mode = ReplayGainMode.values.elementAtOrNull(modeIndex) ?? ReplayGainMode.none;
    final preamp = prefs.getDouble(_kReplayGainPreamp) ?? 0.0;
    return (mode: mode, preamp: preamp);
  }

  // ─── Playback Speed & Pitch Settings ──────────────────────────────────────
  static const _kPlaybackPitch = 'sp_playback_pitch';

  Future<void> savePlaybackSpeed(double pitch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlaybackPitch, pitch);
  }

  Future<double> loadPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kPlaybackPitch) ?? 1.0;
  }

  // ─── Speaker & Hardware Protection Settings ──────────────────────────────
  static const _kSpeakerProtectionEnabled = 'sp_speaker_protection_enabled';
  static const _kSubsonicCutoff = 'sp_subsonic_cutoff_hz';
  static const _kUltrasonicCutoff = 'sp_ultrasonic_cutoff_hz';
  static const _kSpeakerLimiterThreshold = 'sp_speaker_limiter_threshold';
  static const _kSafetyAttenuation = 'sp_speaker_safety_attenuation_db';

  Future<void> saveSpeakerProtection({
    required bool enabled,
    required double subsonicCutoffHz,
    required double ultrasonicCutoffHz,
    required double limiterThreshold,
    required double safetyAttenuationDb,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpeakerProtectionEnabled, enabled);
    await prefs.setDouble(_kSubsonicCutoff, subsonicCutoffHz);
    await prefs.setDouble(_kUltrasonicCutoff, ultrasonicCutoffHz);
    await prefs.setDouble(_kSpeakerLimiterThreshold, limiterThreshold);
    await prefs.setDouble(_kSafetyAttenuation, safetyAttenuationDb);
  }

  Future<({
    bool enabled,
    double subsonicCutoffHz,
    double ultrasonicCutoffHz,
    double limiterThreshold,
    double safetyAttenuationDb,
  })> loadSpeakerProtection() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kSpeakerProtectionEnabled) ?? true,
      subsonicCutoffHz: prefs.getDouble(_kSubsonicCutoff) ?? 25.0,
      ultrasonicCutoffHz: prefs.getDouble(_kUltrasonicCutoff) ?? 20000.0,
      limiterThreshold: prefs.getDouble(_kSpeakerLimiterThreshold) ?? 0.95,
      safetyAttenuationDb: prefs.getDouble(_kSafetyAttenuation) ?? -1.0,
    );
  }

  // ─── Phase Inversion Settings ─────────────────────────────────────────────
  static const _kPhaseInvertLeft = 'sp_phase_invert_left';
  static const _kPhaseInvertRight = 'sp_phase_invert_right';

  Future<void> savePhaseInversion({
    required bool invertLeft,
    required bool invertRight,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPhaseInvertLeft, invertLeft);
    await prefs.setBool(_kPhaseInvertRight, invertRight);
  }

  Future<({bool invertLeft, bool invertRight})> loadPhaseInversion() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      invertLeft: prefs.getBool(_kPhaseInvertLeft) ?? false,
      invertRight: prefs.getBool(_kPhaseInvertRight) ?? false,
    );
  }
}
// Force Flutter compiler sync



