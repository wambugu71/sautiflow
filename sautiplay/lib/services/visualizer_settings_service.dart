import 'dart:async';
import 'package:projectm_visualizer/projectm_visualizer.dart';
import '../database/preferences_store.dart';
import '../widgets/fluid_area_visualizer.dart';
import '../widgets/physics_dots_visualizer.dart';

/// Centralized management service for all audio visualizers across Sautiplay.
///
/// Features:
/// - Controls visibility on the Sound Effects / EQ Screen.
/// - Controls global target frame rate (30 Hz, 60 Hz, 120 Hz).
/// - Controls preset auto-cycling / shuffle timer (5s - 20s M3E slider).
/// - Controls rendering quality profiles (eco 360p, balanced 540p, high 720p, native).
/// - Controls preset transition duration (soft cut / crossfade).
/// - Controls battery saver frame throttling.
class VisualizerSettingsService {
  VisualizerSettingsService._();
  static final VisualizerSettingsService instance = VisualizerSettingsService._();

  static const String kEffectsVisualizerEnabled = 'sp_effects_visualizer_enabled';
  static const String kTargetFps = 'sp_visualizer_target_fps';
  static const String kAutoChangeEnabled = 'sp_visualizer_auto_change_enabled';
  static const String kAutoChangeSeconds = 'sp_visualizer_auto_change_seconds';
  static const String kQuality = 'sp_visualizer_quality';
  static const String kSoftCutDuration = 'sp_visualizer_soft_cut_seconds';
  static const String kBatterySaver = 'sp_visualizer_battery_saver';
  static const String kMeshDensity = 'sp_visualizer_mesh_density';
  static const String kShowTelemetry = 'sp_visualizer_show_telemetry';

  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  Stream<void> get onSettingsChanged => _changeController.stream;

  // ─── Instant Getters (Zero-latency memory lookup) ──────────────────────────

  /// Whether the visualizer widget canvas is rendered on the Effects screen.
  bool get effectsVisualizerEnabled =>
      PreferencesStore.instance.getBool(kEffectsVisualizerEnabled, defaultValue: true) ?? true;

  /// Target refresh rate for all visualizers (30, 60, or 120 Hz).
  int get targetFps {
    final val = PreferencesStore.instance.getInt(kTargetFps, defaultValue: 60) ?? 60;
    if (val != 30 && val != 60 && val != 120) return 60;
    return val;
  }

  /// Whether presets/themes automatically cycle on a timer during playback.
  bool get autoChangeEnabled =>
      PreferencesStore.instance.getBool(kAutoChangeEnabled, defaultValue: false) ?? false;

  /// Time in seconds between preset changes (clamped 5 - 20 seconds).
  int get autoChangeIntervalSeconds {
    final val = PreferencesStore.instance.getInt(kAutoChangeSeconds, defaultValue: 10) ?? 10;
    return val.clamp(5, 20);
  }

  /// Visualizer resolution and performance profile.
  VisualizerQuality get quality {
    final raw = PreferencesStore.instance.getString(kQuality, defaultValue: 'balanced') ?? 'balanced';
    switch (raw.toLowerCase()) {
      case 'eco':
        return VisualizerQuality.eco;
      case 'high':
        return VisualizerQuality.high;
      case 'native':
        return VisualizerQuality.native;
      case 'balanced':
      default:
        return VisualizerQuality.balanced;
    }
  }

  /// Crossfade blend duration between presets in seconds (0.5s - 3.0s).
  double get softCutDuration {
    final raw = PreferencesStore.instance.getDouble(kSoftCutDuration) ?? 1.5;
    return raw.clamp(0.5, 3.0);
  }

  /// Whether rendering throttles down to 15 FPS when silent or paused to conserve power.
  bool get batterySaverEnabled =>
      PreferencesStore.instance.getBool(kBatterySaver, defaultValue: true) ?? true;

  /// Whether realtime FPS and DSP metrics are overlaid on the visualizer canvas.
  bool get showTelemetry =>
      PreferencesStore.instance.getBool(kShowTelemetry, defaultValue: false) ?? false;

  /// Mesh vertex density ('compact', 'standard', 'dense').
  String get meshDensity =>
      PreferencesStore.instance.getString(kMeshDensity, defaultValue: 'standard') ?? 'standard';

  // ─── Setters (Synchronous memory + async WAL SQLite) ─────────────────────

  Future<void> setEffectsVisualizerEnabled(bool enabled) async {
    await PreferencesStore.instance.setBool(kEffectsVisualizerEnabled, enabled);
    _changeController.add(null);
  }

  Future<void> setTargetFps(int fps) async {
    final validFps = (fps == 30 || fps == 120) ? fps : 60;
    await PreferencesStore.instance.setInt(kTargetFps, validFps);
    _changeController.add(null);
  }

  Future<void> setAutoChangeEnabled(bool enabled) async {
    await PreferencesStore.instance.setBool(kAutoChangeEnabled, enabled);
    _changeController.add(null);
  }

  Future<void> setAutoChangeIntervalSeconds(int seconds) async {
    final clamped = seconds.clamp(5, 20);
    await PreferencesStore.instance.setInt(kAutoChangeSeconds, clamped);
    _changeController.add(null);
  }

  Future<void> setQuality(VisualizerQuality q) async {
    String str = 'balanced';
    if (q == VisualizerQuality.eco) str = 'eco';
    if (q == VisualizerQuality.high) str = 'high';
    if (q == VisualizerQuality.native) str = 'native';
    await PreferencesStore.instance.setString(kQuality, str);
    _changeController.add(null);
  }

  Future<void> setSoftCutDuration(double seconds) async {
    await PreferencesStore.instance.setDouble(kSoftCutDuration, seconds.clamp(0.5, 3.0));
    _changeController.add(null);
  }

  Future<void> setBatterySaverEnabled(bool enabled) async {
    await PreferencesStore.instance.setBool(kBatterySaver, enabled);
    _changeController.add(null);
  }

  Future<void> setShowTelemetry(bool show) async {
    await PreferencesStore.instance.setBool(kShowTelemetry, show);
    _changeController.add(null);
  }

  Future<void> setMeshDensity(String density) async {
    await PreferencesStore.instance.setString(kMeshDensity, density);
    _changeController.add(null);
  }

  /// Calculates the next preset / theme ID for seamless auto-cycling.
  String getNextPresetId({
    required String currentAnalyzerType,
    required String currentSpectrumStyle,
  }) {
    if (currentAnalyzerType == 'projectm') {
      final presets = ProjectMPresetLibrary.allWithCustom;
      if (presets.isEmpty) return ProjectMPresetLibrary.defaultPreset.id;
      final idx = presets.indexWhere((p) => p.id == currentSpectrumStyle);
      final nextIdx = (idx >= 0 && idx + 1 < presets.length) ? idx + 1 : 0;
      return presets[nextIdx].id;
    } else if (currentAnalyzerType == 'area' || currentAnalyzerType == 'Waves') {
      final themes = FluidAreaTheme.values;
      final idx = themes.indexWhere((t) => t.name == currentSpectrumStyle);
      final nextIdx = (idx >= 0 && idx + 1 < themes.length) ? idx + 1 : 0;
      return themes[nextIdx].name;
    } else if (currentAnalyzerType == 'bar' ||
        currentAnalyzerType == 'dots' ||
        currentAnalyzerType == 'Dots') {
      final themes = PhysicsDotsTheme.values;
      final idx = themes.indexWhere((t) => t.name == currentSpectrumStyle);
      final nextIdx = (idx >= 0 && idx + 1 < themes.length) ? idx + 1 : 0;
      return themes[nextIdx].name;
    }
    return currentSpectrumStyle;
  }
}
