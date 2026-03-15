import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service for persisting and restoring all app state across
/// restarts: playback queue, EQ settings, and user preferences/settings.
class AppStateService {
  AppStateService._();
  static final AppStateService instance = AppStateService._();

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
    final tracks = raw.map<Map<String, dynamic>>((s) {
      try {
        return Map<String, dynamic>.from(jsonDecode(s) as Map);
      } catch (_) {
        return {};
      }
    }).where((m) => m.isNotEmpty).toList();
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

  // ─── EQ – 10-band + Preamp ─────────────────────────────────────────────────
  static const _kEqEnabled = 'sp_eq_enabled';
  static const _kEqPreset = 'sp_eq_preset';
  static const _kEqGains = 'sp_eq_gains';
  static const _kPreampDb = 'sp_preamp_db';

  Future<void> saveEqBands({
    required bool enabled,
    required String preset,
    required List<double> gains,
    required double preampDb,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEqEnabled, enabled);
    await prefs.setString(_kEqPreset, preset);
    await prefs.setStringList(
        _kEqGains, gains.map((g) => g.toString()).toList());
    await prefs.setDouble(_kPreampDb, preampDb);
  }

  Future<({bool enabled, String preset, List<double> gains, double preampDb})>
      loadEqBands() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEqEnabled) ?? true;
    final preset = prefs.getString(_kEqPreset) ?? 'Flat';
    final rawGains = prefs.getStringList(_kEqGains);
    final gains = rawGains != null
        ? rawGains.map((s) => double.tryParse(s) ?? 0.0).toList()
        : List<double>.filled(10, 0.0);
    final preampDb = prefs.getDouble(_kPreampDb) ?? 0.0;
    return (
      enabled: enabled,
      preset: preset,
      gains: gains,
      preampDb: preampDb
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

  Future<
          ({
            bool enabled,
            double reverbMix,
            double roomSize,
            double echo
          })>
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

  Future<
          ({
            bool enabled,
            double threshold,
            double attackMs,
            double releaseMs
          })>
      loadLimiter() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      enabled: prefs.getBool(_kLimiterEnabled) ?? false,
      threshold: prefs.getDouble(_kLimiterThreshold) ?? 0.95,
      attackMs: prefs.getDouble(_kLimiterAttack) ?? 2.0,
      releaseMs: prefs.getDouble(_kLimiterRelease) ?? 50.0,
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
            bool allowInvalidTls
          })>
      loadEngineSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      outputFormatIndex: prefs.getInt(_kOutputFormat) ?? 0, // 0 = f32
      sampleRate: prefs.getInt(_kSampleRate) ?? 0,
      channels: prefs.getInt(_kChannels) ?? 2,
      crossfadeEnabled: prefs.getBool(_kCrossfadeEnabled) ?? false,
      crossfadeMs: prefs.getInt(_kCrossfadeMs) ?? 250,
      analyzerEnabled: prefs.getBool(_kAnalyzerEnabled) ?? false,
      analyzerType: prefs.getString(_kAnalyzerType) ?? 'area',
      analyzerSampleSize: prefs.getInt(_kAnalyzerSampleSize) ?? 1024,
      allowInvalidTls: prefs.getBool(_kAllowInvalidTls) ?? false,
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
            int ditherMode
          })>
      loadUiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      streamingQuality:
          prefs.getString(_kStreamingQuality) ?? 'High Fidelity',
      gaplessPlayback: prefs.getBool(_kGaplessPlayback) ?? true,
      normalizeVolume: prefs.getBool(_kNormalizeVolume) ?? false,
      streamOverWifi: prefs.getBool(_kStreamOverWifi) ?? true,
      resampleAlgorithm: prefs.getInt(_kResampleAlgorithm) ?? 0,
      ditherMode: prefs.getInt(_kDitherMode) ?? 0,
    );
  }
}
