import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'isolate_player.dart';
import 'services/app_state_service.dart';
import 'widgets/app_showcase.dart';
import 'widgets/parametric_eq_graph.dart';
import 'widgets/playback_speed_modal.dart';
import 'widgets/race_visualizer.dart';

import 'services/app_theme_service.dart';

class EqScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool analyzerEnabled;
  final String analyzerType;
  final GlobalKey? effectsKnobKey;

  const EqScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.analyzerType,
    this.effectsKnobKey,
  });

  /// Applies persisted Sauti DSP suite settings directly to the audio engine.
  static Future<void> applySavedStateToEngine(IsolateAudioPlayer player) async {
    final state = await AppStateService.instance.loadSautiDspState();
    if (state.isEmpty) return;

    final masterEnabled = state['dspMasterEnabled'] ?? true;
    final clarityEnabled = masterEnabled && (state['clarityEnabled'] ?? false);
    final clarityProfile = AudioClarityProfile.values.firstWhere(
      (e) => e.value == (state['clarityProfile'] ?? 0),
      orElse: () => AudioClarityProfile.transientCrisp,
    );
    final clarityIntensity =
        (state['clarityIntensity'] as num?)?.toDouble() ?? 0.5;

    final bassEnabled = masterEnabled && (state['bassEnabled'] ?? false);
    final bassProfile = HarmonicBassProfile.values.firstWhere(
      (e) => e.value == (state['bassProfile'] ?? 0),
      orElse: () => HarmonicBassProfile.naturalBass,
    );
    final bassCutoffHz = (state['bassCutoffHz'] as num?)?.toDouble() ?? 60.0;
    final bassBoost = (state['bassBoost'] as num?)?.toDouble() ?? 0.5;

    final dynamicSystemEnabled =
        masterEnabled && (state['dynamicSystemEnabled'] ?? false);
    final dynamicSystemProfile = TransducerProfile.values.firstWhere(
      (e) => e.value == (state['dynamicSystemProfile'] ?? 0),
      orElse: () => TransducerProfile.earphone,
    );
    final dynamicSystemStrength =
        (state['dynamicSystemStrength'] as num?)?.toDouble() ?? 0.5;

    final analogWarmthEnabled =
        masterEnabled && (state['analogWarmthEnabled'] ?? false);
    final analogWarmthProfile = AnalogWarmthProfile.values.firstWhere(
      (e) => e.value == (state['analogWarmthProfile'] ?? 0),
      orElse: () => AnalogWarmthProfile.triode12AX7,
    );
    final analogWarmthDrive =
        (state['analogWarmthDrive'] as num?)?.toDouble() ?? 0.5;

    final convolverEnabled =
        masterEnabled && (state['convolverEnabled'] ?? false);
    final convolverIrPath = state['convolverIrPath'] as String?;
    final convolverWet = (state['convolverWet'] as num?)?.toDouble() ?? 1.0;
    final convolverDry = (state['convolverDry'] as num?)?.toDouble() ?? 0.0;

    final limiterEnabled = masterEnabled && (state['limiterEnabled'] ?? false);
    final limiterCeilingDb =
        (state['limiterCeilingDb'] as num?)?.toDouble() ?? -0.1;
    final limiterOutputGainDb =
        (state['limiterOutputGainDb'] as num?)?.toDouble() ?? 0.0;
    final limiterReleaseMs =
        (state['limiterReleaseMs'] as num?)?.toDouble() ?? 60.0;

    player.setClarity(
      enabled: clarityEnabled,
      profile: clarityProfile,
      intensity: clarityIntensity,
    );

    player.setHarmonicBass(
      enabled: bassEnabled,
      profile: bassProfile,
      cutoffHz: bassCutoffHz,
      boost: bassBoost,
    );

    player.setDynamicSystem(
      enabled: dynamicSystemEnabled,
      profile: dynamicSystemProfile,
      strength: dynamicSystemStrength,
    );

    player.setAnalogWarmth(
      enabled: analogWarmthEnabled,
      profile: analogWarmthProfile,
      drive: analogWarmthDrive,
    );

    player.setConvolverEnabled(convolverEnabled);
    player.setConvolverMix(wet: convolverWet, dry: convolverDry);
    if (convolverEnabled &&
        convolverIrPath != null &&
        convolverIrPath.isNotEmpty) {
      player.loadConvolverIr(convolverIrPath);
    }

    final surroundEnabled = masterEnabled && (state['surroundEnabled'] ?? false);
    final surroundMode = SurroundMode.values.firstWhere(
      (e) => e.value == (state['surroundMode'] ?? 0),
      orElse: () => SurroundMode.off,
    );
    player.setSurround(
      enabled: surroundEnabled,
      mode: surroundMode,
      fieldWidth:
          (state['surroundFieldWidth'] as num?)?.toDouble() ?? 1.4,
      vhsRoomPreset: (state['surroundRoomPreset'] as num?)?.toInt() ?? 2,
      haasDelayMs:
          (state['surroundHaasDelayMs'] as num?)?.toDouble() ?? 5.5,
      centerFocus:
          (state['surroundCenterFocus'] as num?)?.toDouble() ?? 0.6,
    );

    player.setMasterLimiter(
      enabled: limiterEnabled,
      ceilingDb: limiterCeilingDb,
      outputGainDb: limiterOutputGainDb,
      releaseMs: limiterReleaseMs,
    );
  }

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Reactive theme colors from BuildContext
  Color get primaryColor => context.primaryColor;
  Color get bgDarkColor => context.bgDark;
  Color get surfaceDarkColor => context.cardDark;
  Color get surfaceDarkerColor => context.cardDark.withValues(alpha: 0.8);

  // Preferences
  bool _showWarningBanner = true;

  // Master EQ
  bool _masterEqEnabled = true;

  // Graphic EQ Frequencies
  List<double> _eqFrequencies = [
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
  List<double> _eqGains = List.filled(10, 0.0);

  void _setupFrequencies(int bands) {
    if (bands == 10) {
      _eqFrequencies = [
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
    } else if (bands == 16) {
      _eqFrequencies = [
        25.0,
        40.0,
        63.0,
        100.0,
        160.0,
        250.0,
        400.0,
        630.0,
        1000.0,
        1600.0,
        2500.0,
        4000.0,
        6300.0,
        10000.0,
        16000.0,
        20000.0
      ];
    } else if (bands == 32) {
      _eqFrequencies = [
        16.0,
        20.0,
        25.0,
        31.5,
        40.0,
        50.0,
        63.0,
        80.0,
        100.0,
        125.0,
        160.0,
        200.0,
        250.0,
        315.0,
        400.0,
        500.0,
        630.0,
        800.0,
        1000.0,
        1250.0,
        1600.0,
        2000.0,
        2500.0,
        3150.0,
        4000.0,
        5000.0,
        6300.0,
        8000.0,
        10000.0,
        12500.0,
        16000.0,
        20000.0
      ];
    } else {
      _eqFrequencies = [];
      for (int i = 0; i < bands; i++) {
        _eqFrequencies
            .add((20.0 * math.pow(1000.0, i / (bands - 1))).roundToDouble());
      }
    }
    if (_eqGains.length != bands) {
      _eqGains = List.filled(bands, 0.0);
    }
  }

  String _activePreset = 'Flat';

  // Parametric EQ bands state
  final List<EqBandConfig> _parametricBands = [
    const EqBandConfig(
        type: EqBandType.lowshelf, frequencyHz: 120, gainDb: 0.0, slope: 1.0),
    const EqBandConfig(
        type: EqBandType.peak, frequencyHz: 1000, gainDb: 0.0, q: 1.2),
    const EqBandConfig(
        type: EqBandType.highshelf, frequencyHz: 9000, gainDb: 0.0, slope: 1.0),
  ];
  bool _parametricEqEnabled = false;

  // Crystalizer
  bool _crystalizerEnabled = false;
  double _crystalizerIntensity = 0.5;
  bool _crystalizerHighShelf = true;
  double _crystalizerShelfGain = 2.0;

  // Audiophile Crossfeed
  int _crossfeedPreset = 1;
  int _crossfeedAlgorithmIndex =
      2; // 1=Simple, 2=BS2B, 3=Meier, 4=Natural, 5=RACE
  bool _crossfeedEnabled = false;
  double _crossfeedMix = 0.5;
  double _crossfeedDelayMs = 0.40;
  double _crossfeedCutoffHz = 700.0;
  bool _crossfeedCompensation = true;
  double _raceDelayMs = 0.166;
  double _raceAlpha = 0.55;
  double _raceLpfHz = 2500.0;

  // Stereo Widen
  bool _stereoWidenEnabled = false;
  double _stereoWidenWidth = 1.5;
  double _stereoWidenDelayMs = 0.15; // Maps to 15ms

  // DSP Stereo Enhancer
  bool _stereoEnhancementEnabled = false;
  double _stereoEnhancementMix = 0.5;

  // Reverb (Freeverb FDN)
  bool _reverbEnabled = false;
  double _reverbMix = 0.25;
  double _reverbRoomSize = 0.6;
  double _reverbDamping = 0.4;
  double _reverbPreDelayMs = 20.0;
  double _reverbWidth = 1.0;

  // Audio Tuning (3-band EQ)
  bool _audioTuningEnabled = false;
  double _tuneLow = 0.0;
  double _tuneMid = 0.0;
  double _tuneHigh = 0.0;

  // Preamp
  double _preampDb = 0.0; // Simulated gain offset
  // Subscriptions
  StreamSubscription<void>? _eqSettingsSub;

  // Soft Limiter
  bool _limiterEnabled = false;
  double _limiterThreshold = 0.95; // 0.1 – 1.0
  double _limiterAttackMs = 2.0; // 0.1 – 100 ms
  double _limiterReleaseMs = 50.0; // 10 – 1000 ms

  // ── Sauti DSP Suite States ──
  // 1. Audio Clarity
  bool _clarityEnabled = false;
  AudioClarityProfile _clarityProfile = AudioClarityProfile.transientCrisp;
  double _clarityIntensity = 0.5;

  // 2. Harmonic Bass
  bool _bassEnabled = false;
  HarmonicBassProfile _bassProfile = HarmonicBassProfile.subBassResonant;
  double _bassCutoffHz = 60.0;
  double _bassBoost = 0.5;

  // 3. Dynamic Transducer System
  bool _dynamicSystemEnabled = false;
  TransducerProfile _dynamicSystemProfile = TransducerProfile.earphone;
  double _dynamicSystemStrength = 0.5;

  // 4. Analog Warmth
  bool _analogWarmthEnabled = false;
  AnalogWarmthProfile _analogWarmthProfile = AnalogWarmthProfile.triode12AX7;
  double _analogWarmthDrive = 0.5;

  // 5. FFT Convolver
  bool _convolverEnabled = false;
  String? _convolverIrPath;
  String? _convolverIrFileName;
  double _convolverWet = 1.0;
  double _convolverDry = 0.0;

  // 5b. Spatial Surround Suite
  bool _surroundEnabled = false;
  SurroundMode _surroundMode = SurroundMode.off;
  double _surroundFieldWidth = 1.4;
  int _surroundRoomPreset = 2;
  double _surroundHaasDelayMs = 5.5;
  double _surroundCenterFocus = 0.6;

  // 6. Master Peak Limiter
  bool _masterLimiterEnabled = false;
  double _masterLimiterCeilingDb = -0.1;
  double _masterLimiterOutputGainDb = 0.0;
  double _masterLimiterReleaseMs = 60.0;

  // Playback Speed & Status
  double _playbackPitch = 1.0;
  bool _isPlaying = false;
  StreamSubscription<PlayerStatus>? _statusSub;

  StateSetter? _subScreenSetState;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _subScreenSetState?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initEq();
    widget.player.setAnalyzerEnabled(true);
    widget.player.configureAnalyzer(frameSize: 512);

    _statusSub = widget.player.statusStream.listen((status) {
      if (mounted && _isPlaying != status.isPlaying) {
        setState(() {
          _isPlaying = status.isPlaying;
        });
      }
    });

    _eqSettingsSub =
        AppStateService.instance.eqSettingsChanged.stream.listen((_) {
      if (mounted) _loadPreferences();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final hideBanner = prefs.getBool('hide_eq_warning') ?? false;

    // Load all persisted EQ state
    final speed = await AppStateService.instance.loadPlaybackSpeed();
    final eqBands = await AppStateService.instance.loadEqBands();
    final crystalizer = await AppStateService.instance.loadCrystalizer();
    final stereoWiden = await AppStateService.instance.loadStereoWiden();
    final stereoEnhancement =
        await AppStateService.instance.loadStereoEnhancement();
    final reverb = await AppStateService.instance.loadReverb();
    final crossfeed = await AppStateService.instance.loadCrossfeed();
    final raceParams = await AppStateService.instance.loadRaceParams();
    final tuning = await AppStateService.instance.loadAudioTuning();
    final limiter = await AppStateService.instance.loadLimiter();

    setState(() {
      _showWarningBanner = !hideBanner;
      _playbackPitch = speed;

      // EQ bands
      _masterEqEnabled = eqBands.enabled;
      _activePreset = eqBands.preset;
      _setupFrequencies(eqBands.bandCount);
      if (eqBands.gains.length == _eqGains.length) {
        for (int i = 0; i < _eqGains.length; i++) {
          _eqGains[i] = eqBands.gains[i];
        }
      }
      _preampDb = eqBands.preampDb;

      // Crystalizer
      _crystalizerEnabled = crystalizer.enabled;
      _crystalizerIntensity = crystalizer.intensity;
      _crystalizerHighShelf = crystalizer.highShelfEnabled;
      _crystalizerShelfGain = crystalizer.highShelfGainDb;

      // Crossfeed
      _crossfeedEnabled = crossfeed.enabled;
      _crossfeedPreset = crossfeed.preset > 0 ? crossfeed.preset : 1;
      _crossfeedAlgorithmIndex = crossfeed.algoIndex;
      _crossfeedMix = crossfeed.mix;
      _crossfeedDelayMs = crossfeed.delayMs;
      _crossfeedCutoffHz = crossfeed.cutoffHz;
      _crossfeedCompensation = crossfeed.outputCompensation;
      _raceDelayMs = raceParams.delayMs;
      _raceAlpha = raceParams.alpha;
      _raceLpfHz = raceParams.lpfHz;

      // Stereo Widen
      _stereoWidenEnabled = stereoWiden.enabled;
      _stereoWidenWidth = stereoWiden.width;
      _stereoWidenDelayMs = stereoWiden.delayMs;

      // DSP Stereo Enhancer
      _stereoEnhancementEnabled = stereoEnhancement.enabled;
      _stereoEnhancementMix = stereoEnhancement.mix;

      // Reverb (Freeverb FDN)
      _reverbEnabled = reverb.enabled;
      _reverbMix = reverb.mix;
      _reverbRoomSize = reverb.roomSize;
      _reverbDamping = reverb.damping;
      _reverbPreDelayMs = reverb.preDelayMs;
      _reverbWidth = reverb.width;

      // Audio Tuning
      _audioTuningEnabled = tuning.enabled;
      _tuneLow = tuning.low;
      _tuneMid = tuning.mid;
      _tuneHigh = tuning.high;

      // Limiter
      _limiterEnabled = limiter.enabled;
      _limiterThreshold = limiter.threshold;
      _limiterAttackMs = limiter.attackMs;
      _limiterReleaseMs = limiter.releaseMs;
    });

    // Load Sauti DSP Suite state
    final dspMap = await AppStateService.instance.loadSautiDspState();
    if (dspMap.isNotEmpty && mounted) {
      setState(() {
        _clarityEnabled = dspMap['clarityEnabled'] ?? false;
        _clarityProfile = AudioClarityProfile.values.firstWhere(
          (e) => e.value == (dspMap['clarityProfile'] ?? 0),
          orElse: () => AudioClarityProfile.transientCrisp,
        );
        _clarityIntensity =
            (dspMap['clarityIntensity'] as num?)?.toDouble() ?? 0.5;

        _bassEnabled = dspMap['bassEnabled'] ?? false;
        _bassProfile = HarmonicBassProfile.values.firstWhere(
          (e) => e.value == (dspMap['bassProfile'] ?? 0),
          orElse: () => HarmonicBassProfile.subBassResonant,
        );
        _bassCutoffHz = (dspMap['bassCutoffHz'] as num?)?.toDouble() ?? 60.0;
        _bassBoost = (dspMap['bassBoost'] as num?)?.toDouble() ?? 0.5;

        _dynamicSystemEnabled = dspMap['dynamicSystemEnabled'] ?? false;
        _dynamicSystemProfile = TransducerProfile.values.firstWhere(
          (e) => e.value == (dspMap['dynamicSystemProfile'] ?? 0),
          orElse: () => TransducerProfile.earphone,
        );
        _dynamicSystemStrength =
            (dspMap['dynamicSystemStrength'] as num?)?.toDouble() ?? 0.5;

        _analogWarmthEnabled = dspMap['analogWarmthEnabled'] ?? false;
        _analogWarmthProfile = AnalogWarmthProfile.values.firstWhere(
          (e) => e.value == (dspMap['analogWarmthProfile'] ?? 0),
          orElse: () => AnalogWarmthProfile.triode12AX7,
        );
        _analogWarmthDrive =
            (dspMap['analogWarmthDrive'] as num?)?.toDouble() ?? 0.5;

        _convolverEnabled = dspMap['convolverEnabled'] ?? false;
        _convolverIrPath = dspMap['convolverIrPath'] as String?;
        if (_convolverIrPath != null && _convolverIrPath!.isNotEmpty) {
          _convolverIrFileName = p.basename(_convolverIrPath!);
        }
        _convolverWet = (dspMap['convolverWet'] as num?)?.toDouble() ?? 1.0;
        _convolverDry = (dspMap['convolverDry'] as num?)?.toDouble() ?? 0.0;

        _surroundEnabled = dspMap['surroundEnabled'] ?? false;
        _surroundMode = SurroundMode.values.firstWhere(
          (e) => e.value == (dspMap['surroundMode'] ?? 0),
          orElse: () => SurroundMode.off,
        );
        _surroundFieldWidth =
            (dspMap['surroundFieldWidth'] as num?)?.toDouble() ?? 1.4;
        _surroundRoomPreset =
            (dspMap['surroundRoomPreset'] as num?)?.toInt() ?? 2;
        _surroundHaasDelayMs =
            (dspMap['surroundHaasDelayMs'] as num?)?.toDouble() ?? 5.5;
        _surroundCenterFocus =
            (dspMap['surroundCenterFocus'] as num?)?.toDouble() ?? 0.6;

        _masterLimiterEnabled = dspMap['limiterEnabled'] ?? false;
        _masterLimiterCeilingDb =
            (dspMap['limiterCeilingDb'] as num?)?.toDouble() ?? -0.1;
        _masterLimiterOutputGainDb =
            (dspMap['limiterOutputGainDb'] as num?)?.toDouble() ?? 0.0;
        _masterLimiterReleaseMs =
            (dspMap['limiterReleaseMs'] as num?)?.toDouble() ?? 60.0;
      });
    }

    // Apply loaded state to the audio engine
    widget.player.setMultibandEqEnabled(_masterEqEnabled);
    widget.player.initMultibandEq(_eqFrequencies);
    _applyEqGains();
    _applyStoredPreamp();

    if (_crystalizerEnabled) {
      _updateCrystalizer();
    }
    if (_crossfeedEnabled) {
      _updateCrossfeed();
    }
    if (_stereoWidenEnabled) {
      _updateStereoWiden();
    }
    if (_stereoEnhancementEnabled) {
      _updateStereoEnhancement();
    }
    if (_reverbEnabled) {
      _updateReverb();
    }
    if (_audioTuningEnabled) {
      widget.player.setEqEnabled(true);
      widget.player.setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
    }
    if (_limiterEnabled) {
      _applyLimiter();
    }

    // Apply Sauti DSP suite
    _updateClarity();
    _updateHarmonicBass();
    _updateDynamicSystem();
    _updateAnalogWarmth();
    _updateConvolver();
    _updateSurround();
    _updateMasterLimiter();
  }

  void _updateClarity() {
    widget.player.setClarity(
      enabled: _clarityEnabled,
      profile: _clarityProfile,
      intensity: _clarityIntensity,
    );
  }

  void _updateHarmonicBass() {
    widget.player.setHarmonicBass(
      enabled: _bassEnabled,
      profile: _bassProfile,
      cutoffHz: _bassCutoffHz,
      boost: _bassBoost,
    );
  }

  void _updateDynamicSystem() {
    widget.player.setDynamicSystem(
      enabled: _dynamicSystemEnabled,
      profile: _dynamicSystemProfile,
      strength: _dynamicSystemStrength,
    );
  }

  void _updateAnalogWarmth() {
    widget.player.setAnalogWarmth(
      enabled: _analogWarmthEnabled,
      profile: _analogWarmthProfile,
      drive: _analogWarmthDrive,
    );
  }

  void _updateConvolver() {
    widget.player.setConvolverEnabled(_convolverEnabled);
    widget.player.setConvolverMix(wet: _convolverWet, dry: _convolverDry);
    if (_convolverEnabled &&
        _convolverIrPath != null &&
        _convolverIrPath!.isNotEmpty) {
      widget.player.loadConvolverIr(_convolverIrPath!);
    }
  }

  void _updateSurround() {
    widget.player.setSurround(
      enabled: _surroundEnabled,
      mode: _surroundMode,
      fieldWidth: _surroundFieldWidth,
      vhsRoomPreset: _surroundRoomPreset,
      haasDelayMs: _surroundHaasDelayMs,
      centerFocus: _surroundCenterFocus,
    );
  }

  void _updateMasterLimiter() {
    widget.player.setMasterLimiter(
      enabled: _masterLimiterEnabled,
      ceilingDb: _masterLimiterCeilingDb,
      outputGainDb: _masterLimiterOutputGainDb,
      releaseMs: _masterLimiterReleaseMs,
    );
  }

  Future<void> _pickImpulseResponse() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'irs'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _convolverIrPath = path;
          _convolverIrFileName = p.basename(path);
          _convolverEnabled = true;
        });
        _updateConvolver();
        _saveEqState();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load acoustic file: $e')),
        );
      }
    }
  }

  void _updateStereoEnhancement() {
    widget.player.setStereoEnhancement(
      enabled: _stereoEnhancementEnabled,
      mix: _stereoEnhancementMix,
    );
  }

  void _updateReverb() {
    widget.player.setReverbEx(
      enabled: _reverbEnabled,
      mix: _reverbMix,
      roomSize: _reverbRoomSize,
      damping: _reverbDamping,
      preDelayMs: _reverbPreDelayMs,
      width: _reverbWidth,
    );
  }

  /// Applies the loaded preamp value to the audio engine.
  void _applyStoredPreamp() {
    final gain = math.pow(10, _preampDb / 20).toDouble();
    widget.player.setGain(gain);
  }

  /// Saves all current EQ and Sauti DSP state to persistent storage.
  void _saveEqState() {
    AppStateService.instance.saveEqBands(
      enabled: _masterEqEnabled,
      preset: _activePreset,
      gains: List<double>.from(_eqGains),
      preampDb: _preampDb,
      bandCount: _eqFrequencies.length,
    );
    AppStateService.instance.saveCrystalizer(
      enabled: _crystalizerEnabled,
      intensity: _crystalizerIntensity,
      highShelfEnabled: _crystalizerHighShelf,
      highShelfGainDb: _crystalizerShelfGain,
    );
    AppStateService.instance.saveCrossfeed(
      enabled: _crossfeedEnabled,
      preset: _crossfeedPreset,
      algoIndex: _crossfeedAlgorithmIndex,
      mix: _crossfeedMix,
      delayMs: _crossfeedDelayMs,
      cutoffHz: _crossfeedCutoffHz,
      outputCompensation: _crossfeedCompensation,
    );
    AppStateService.instance.saveRaceParams(
      delayMs: _raceDelayMs,
      alpha: _raceAlpha,
      lpfHz: _raceLpfHz,
    );
    AppStateService.instance.saveStereoWiden(
      enabled: _stereoWidenEnabled,
      width: _stereoWidenWidth,
      delayMs: _stereoWidenDelayMs,
    );
    AppStateService.instance.saveStereoEnhancement(
      enabled: _stereoEnhancementEnabled,
      mix: _stereoEnhancementMix,
    );
    AppStateService.instance.saveReverb(
      enabled: _reverbEnabled,
      mix: _reverbMix,
      roomSize: _reverbRoomSize,
      damping: _reverbDamping,
      preDelayMs: _reverbPreDelayMs,
      width: _reverbWidth,
    );
    AppStateService.instance.saveAudioTuning(
      enabled: _audioTuningEnabled,
      low: _tuneLow,
      mid: _tuneMid,
      high: _tuneHigh,
    );
    AppStateService.instance.saveLimiter(
      enabled: _limiterEnabled,
      threshold: _limiterThreshold,
      attackMs: _limiterAttackMs,
      releaseMs: _limiterReleaseMs,
    );

    // Save Sauti DSP Suite state
    AppStateService.instance.saveSautiDspState({
      'dspMasterEnabled': _masterEqEnabled,
      'clarityEnabled': _clarityEnabled,
      'clarityProfile': _clarityProfile.value,
      'clarityIntensity': _clarityIntensity,
      'bassEnabled': _bassEnabled,
      'bassProfile': _bassProfile.value,
      'bassCutoffHz': _bassCutoffHz,
      'bassBoost': _bassBoost,
      'dynamicSystemEnabled': _dynamicSystemEnabled,
      'dynamicSystemProfile': _dynamicSystemProfile.value,
      'dynamicSystemStrength': _dynamicSystemStrength,
      'analogWarmthEnabled': _analogWarmthEnabled,
      'analogWarmthProfile': _analogWarmthProfile.value,
      'analogWarmthDrive': _analogWarmthDrive,
      'convolverEnabled': _convolverEnabled,
      'convolverIrPath': _convolverIrPath,
      'convolverWet': _convolverWet,
      'convolverDry': _convolverDry,
      'surroundEnabled': _surroundEnabled,
      'surroundMode': _surroundMode.value,
      'surroundFieldWidth': _surroundFieldWidth,
      'surroundRoomPreset': _surroundRoomPreset,
      'surroundHaasDelayMs': _surroundHaasDelayMs,
      'surroundCenterFocus': _surroundCenterFocus,
      'limiterEnabled': _masterLimiterEnabled,
      'limiterCeilingDb': _masterLimiterCeilingDb,
      'limiterOutputGainDb': _masterLimiterOutputGainDb,
      'limiterReleaseMs': _masterLimiterReleaseMs,
    });
  }

  void _dismissWarningBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_eq_warning', true);
    setState(() {
      _showWarningBanner = false;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _eqSettingsSub?.cancel();
    widget.player.setAnalyzerEnabled(false);
    super.dispose();
  }

  void _initEq() {
    widget.player.setMultibandEqEnabled(_masterEqEnabled);
    widget.player.initMultibandEq(_eqFrequencies);
    _applyPreset('Flat');
  }

  void _applyEqGains() {
    for (int i = 0; i < _eqGains.length; i++) {
      widget.player.setMultibandEqBandGain(i, _eqGains[i]);
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      _activePreset = preset;
      if (preset == 'Flat') {
        _eqGains.fillRange(0, _eqGains.length, 0.0);
      } else {
        List<double> baseGains = List.filled(10, 0.0);
        switch (preset) {
          case 'Bass Boost':
            baseGains = [6.0, 5.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
            break;
          case 'Vocal':
            baseGains = [-2.0, -2.0, -2.0, 1.0, 3.0, 4.0, 3.0, 1.0, -1.0, -1.0];
            break;
          case 'Treble':
            baseGains = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 4.0, 5.0, 6.0];
            break;
          case 'Rock':
            baseGains = [5.0, 4.0, 2.0, -1.0, -2.0, -1.0, 1.0, 3.0, 4.0, 5.0];
            break;
          case 'Jazz':
            baseGains = [4.0, 3.0, 1.0, 2.0, -2.0, -2.0, 0.0, 1.0, 3.0, 4.0];
            break;
        }

        for (int i = 0; i < _eqGains.length; i++) {
          double position = i / (_eqGains.length - 1);
          double index10 = position * 9.0;
          int lower = index10.floor();
          int upper = index10.ceil();
          double fraction = index10 - lower;
          if (upper > 9) upper = 9;
          _eqGains[i] =
              baseGains[lower] * (1.0 - fraction) + baseGains[upper] * fraction;
        }
      }
      _applyEqGains();
    });
    // Persist the new preset
    _saveEqState();
  }

  void _showPipelineInfo() async {
    final state = await widget.player.getPipelineState();
    final latencyMs = await widget.player.getDeviceLatencyMs();

    if (!mounted) return;

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Audio Pipeline State',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Input File Format',
                    style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'Sample Rate: ${state.inputSampleRate} Hz\nChannels: ${state.inputChannels}\nFormat: ${state.inputFormatString}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text('DSP Processing Format',
                    style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'Sample Rate: ${state.processingSampleRate} Hz\nChannels: ${state.processingChannels}\nFormat: ${state.processingFormatString}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text('Hardware Output Format',
                    style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'Sample Rate: ${state.outputSampleRate} Hz\nChannels: ${state.outputChannels}\nFormat: ${state.outputFormatString}\nEst. Device Latency: ${latencyMs.toStringAsFixed(2)} ms',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text('Active DSP Nodes',
                    style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'EQ: ${state.eqEnabled}\nReverb: ${state.reverbEnabled}\nLimiter: ${state.limiterEnabled}\nDelay: ${state.delayEnabled}\nStereo Widen: ${state.stereoWidenEnabled}\nSpatialization: ${state.spatializationEnabled}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _resetAll() {
    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Reset All Effects?',
        content: const Material(
          color: Colors.transparent,
          child: Text(
            'This will reset the Equalizer and all audio DSP effects to defaults.',
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
        ),
        topDivider: true,
        bottomDivider: true,
        actions: [
          M3EButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () {
              Navigator.pop(context);
              _performResetAll();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _performResetAll() {
    _applyPreset('Flat');
    setState(() {
      _masterEqEnabled = true;
      widget.player.setMultibandEqEnabled(true);

      _crystalizerEnabled = false;
      _crystalizerIntensity = 0.5;
      _crystalizerHighShelf = true;
      _crystalizerShelfGain = 2.0;
      widget.player.setCrystalizer(enabled: false);

      _crossfeedEnabled = false;
      _crossfeedPreset = 1;
      _crossfeedAlgorithmIndex = 2;
      widget.player.setCrossfeed(enabled: false, preset: 0);
      widget.player.setCrossfeedAlgorithm(CrossfeedAlgorithm.off);

      _stereoWidenEnabled = false;
      _stereoWidenWidth = 1.5;
      widget.player.setStereoWiden(enabled: false, width: 1.5, delayMs: 15.0);

      _stereoEnhancementEnabled = false;
      _stereoEnhancementMix = 0.5;
      widget.player.setStereoEnhancement(enabled: false, mix: 0.5);

      _reverbEnabled = false;
      _reverbMix = 0.25;
      _reverbRoomSize = 0.6;
      _reverbDamping = 0.4;
      _reverbPreDelayMs = 20.0;
      _reverbWidth = 1.0;
      widget.player.setReverbEx(
        enabled: false,
        mix: _reverbMix,
        roomSize: _reverbRoomSize,
        damping: _reverbDamping,
        preDelayMs: _reverbPreDelayMs,
        width: _reverbWidth,
      );

      _audioTuningEnabled = false;
      widget.player.setEqEnabled(false);
      _tuneLow = 0.0;
      _tuneMid = 0.0;
      _tuneHigh = 0.0;
      widget.player.setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);

      _preampDb = 0.0;
      widget.player.setGain(1.0); // 1.0 is 0dB
      widget.player.setPitch(1.0);

      _parametricEqEnabled = false;
      _parametricBands.clear();
      widget.player.setMultibandFxEnabled(false);
      widget.player.clearMultibandFx();

      _limiterEnabled = false;
      _limiterThreshold = 0.95;
      _limiterAttackMs = 2.0;
      _limiterReleaseMs = 50.0;
      widget.player.setLimiterEnabled(false);
      widget.player.setClippingDetectionEnabled(false);

      // Sauti DSP Suite Resets
      _clarityEnabled = false;
      _clarityProfile = AudioClarityProfile.transientCrisp;
      _clarityIntensity = 0.5;
      widget.player.setClarity(enabled: false);

      _bassEnabled = false;
      _bassProfile = HarmonicBassProfile.subBassResonant;
      _bassCutoffHz = 60.0;
      _bassBoost = 0.5;
      widget.player.setHarmonicBass(enabled: false);

      _dynamicSystemEnabled = false;
      _dynamicSystemProfile = TransducerProfile.earphone;
      _dynamicSystemStrength = 0.5;
      widget.player.setDynamicSystem(enabled: false);

      _analogWarmthEnabled = false;
      _analogWarmthProfile = AnalogWarmthProfile.triode12AX7;
      _analogWarmthDrive = 0.5;
      widget.player.setAnalogWarmth(enabled: false);

      _convolverEnabled = false;
      _convolverIrPath = null;
      _convolverIrFileName = null;
      _convolverWet = 1.0;
      _convolverDry = 0.0;
      widget.player.setConvolverEnabled(false);
      widget.player.clearConvolverIr();

      _surroundEnabled = false;
      _surroundMode = SurroundMode.off;
      _surroundFieldWidth = 1.4;
      _surroundRoomPreset = 2;
      _surroundHaasDelayMs = 5.5;
      _surroundCenterFocus = 0.6;
      widget.player.setSurround(enabled: false, mode: SurroundMode.off);

      _masterLimiterEnabled = false;
      _masterLimiterCeilingDb = -0.1;
      _masterLimiterOutputGainDb = 0.0;
      _masterLimiterReleaseMs = 60.0;
      widget.player.setMasterLimiter(enabled: false);
    });
    // Persist the reset state
    _saveEqState();
  }

  Widget _buildSectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: primaryColor, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: primaryColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: primaryColor.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectTileCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    Shapes shape = Shapes.c4SidedCookie,
    ValueChanged<bool>? onToggle,
    required VoidCallback onTapDetail,
  }) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      leading: /*M3EContainer(
        shape,
        width: 44,
        height: 44,
        color: isEnabled
            ? primaryColor.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        border: BorderSide(
          color: isEnabled
              ? primaryColor.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.2,
        ),
        child: */
          Center(
        child: Icon(
          icon,
          color: isEnabled ? primaryColor : Colors.white60,
          size: 22,
        ),
        //  ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggle != null) ...[
            M3ESwitch(
              selectedIcon: Icon(Icons.check, color: primaryColor),
              value: isEnabled,
              onChanged: onToggle,
            ),
            const SizedBox(width: 6),
          ],
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white38,
            size: 22,
          ),
        ],
      ),
      onTap: onTapDetail,
    );
  }

  void _openDetailScreen(
      String title, IconData icon, WidgetBuilder contentBuilder,
      {Shapes shape = Shapes.c4SidedCookie}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(
            builder: (context, setSubState) {
              _subScreenSetState = setSubState;
              return Scaffold(
                backgroundColor: bgDarkColor,
                appBar: AppBar(
                  backgroundColor: surfaceDarkerColor,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: M3EIconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 20),
                    variant: M3EIconButtonVariant.standard,
                    onPressed: () {
                      _subScreenSetState = null;
                      Navigator.pop(context);
                    },
                  ),
                  title: Row(
                    children: [
                      /* M3EContainer(
                        shape,
                        width: 32,
                        height: 32,
                        color: primaryColor.withValues(alpha: 0.18),
                        border: BorderSide(
                          color: primaryColor.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                        child: */
                      Center(
                        child: Icon(icon, color: primaryColor, size: 16),
                      ),
                      // ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                body: RepaintBoundary(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    physics: const BouncingScrollPhysics(),
                    child: contentBuilder(context),
                  ),
                ),
              );
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curveAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final slideAnimation = Tween<Offset>(
            begin: const Offset(0.06, 0.0),
            end: Offset.zero,
          ).animate(curveAnimation);

          final fadeAnimation = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(curveAnimation);

          return SlideTransition(
            position: slideAnimation,
            child: FadeTransition(
              opacity: fadeAnimation,
              child: child,
            ),
          );
        },
      ),
    ).then((_) {
      _subScreenSetState = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000.0),
        child: CustomScrollView(
          key: const PageStorageKey<String>('eq_screen_scroll'),
          slivers: [
            // Top Master Control Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 16.0, right: 16.0, top: 12.0, bottom: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: surfaceDarkColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _masterEqEnabled
                          ? primaryColor.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Center(
                            child: Icon(
                              Icons.equalizer_rounded,
                              color: _masterEqEnabled
                                  ? primaryColor
                                  : Colors.white60,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Master EQ & DSP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Text(
                                _masterEqEnabled
                                    ? 'Audio engine active'
                                    : 'DSP bypassed',
                                style: TextStyle(
                                  color: _masterEqEnabled
                                      ? primaryColor.withValues(alpha: 0.9)
                                      : Colors.white38,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 4),
                          const SizedBox(width: 4),
                          M3EIconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 19),
                            variant: M3EIconButtonVariant.tonal,
                            tooltip: 'Reset All',
                            onPressed: _resetAll,
                          ),
                          const SizedBox(width: 6),
                          M3ESwitch(
                            selectedIcon:
                                Icon(Icons.check, color: primaryColor),
                            value: _masterEqEnabled,
                            onChanged: (val) {
                              setState(() => _masterEqEnabled = val);
                              widget.player.setMultibandEqEnabled(val);
                              _saveEqState();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Warning Banner (Dismissible)
            if (_showWarningBanner)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: M3ECard(
                    variant: M3ECardVariant.filled,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          M3EContainer(
                            Shapes.triangle,
                            width: 32,
                            height: 32,
                            color: Colors.amber.withValues(alpha: 0.15),
                            border: BorderSide(
                              color: Colors.amber.withValues(alpha: 0.35),
                              width: 1.0,
                            ),
                            child: const Center(
                              child: Icon(Icons.warning_amber_rounded,
                                  color: Colors.amberAccent, size: 18),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Extreme equalizer or filter boosts can cause clipping. Use limiter or preamp reduction if needed.',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  height: 1.3),
                            ),
                          ),
                          M3EIconButton(
                            onPressed: _dismissWarningBanner,
                            icon: const Icon(Icons.close_rounded, size: 16),
                            variant: M3EIconButtonVariant.standard,
                            tooltip: 'Dismiss',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Section 1: Equalization & Tuning
            SliverToBoxAdapter(
              child: _buildSectionHeader('Equalization & Tuning',
                  icon: Icons.equalizer_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 4,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          '${_eqFrequencies.length}-Band Graphic EQ',
                          Icons.equalizer_rounded,
                          (_) => _buildGraphicEqSection(),
                          shape: Shapes.c4SidedCookie,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Playback Speed & Pitch',
                          Icons.speed_rounded,
                          (_) => _buildPlaybackSpeedSection(),
                          shape: Shapes.sunny,
                        );
                        break;
                      case 2:
                        _openDetailScreen(
                          '3-Band Audio Tuning',
                          Icons.tune_rounded,
                          (_) => _buildAudioTuningSection(),
                          shape: Shapes.pill,
                        );
                        break;
                      case 3:
                        _openDetailScreen(
                          'Parametric EQ',
                          Icons.show_chart_rounded,
                          (_) => _buildParametricEqSection(),
                          shape: Shapes.gem,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return AppShowcase(
                        showcaseKey: widget.effectsKnobKey ?? GlobalKey(),
                        title: 'Knob Controls',
                        description:
                            'Drag knobs to adjust EQ. Tip: Long-press any knob to edit values directly with your keyboard!',
                        currentStep: 3,
                        totalSteps: 4,
                        child: _buildEffectTileCard(
                          icon: Icons.equalizer_rounded,
                          shape: Shapes.c4SidedCookie,
                          title: '${_eqFrequencies.length}-Band Graphic EQ',
                          subtitle: _masterEqEnabled
                              ? '${_eqFrequencies.length}-Band ($_activePreset)'
                              : 'Disabled',
                          isEnabled: _masterEqEnabled,
                          onToggle: (v) {
                            setState(() => _masterEqEnabled = v);
                            widget.player.setMultibandEqEnabled(v);
                            _saveEqState();
                          },
                          onTapDetail: () => _openDetailScreen(
                            '${_eqFrequencies.length}-Band Graphic EQ',
                            Icons.equalizer_rounded,
                            (_) => _buildGraphicEqSection(),
                            shape: Shapes.c4SidedCookie,
                          ),
                        ),
                      );
                    }
                    if (index == 1) {
                      return _buildEffectTileCard(
                        icon: Icons.speed_rounded,
                        shape: Shapes.sunny,
                        title: 'Playback Speed & Pitch',
                        subtitle: (_playbackPitch - 1.0).abs() >= 0.01
                            ? '${_playbackPitch.toStringAsFixed(2)}x Speed'
                            : 'Normal Speed (1.0x)',
                        isEnabled: (_playbackPitch - 1.0).abs() >= 0.01,
                        onToggle: (v) {
                          final newPitch = v ? 1.25 : 1.0;
                          setState(() => _playbackPitch = newPitch);
                          widget.player.setPitch(newPitch);
                          AppStateService.instance.savePlaybackSpeed(newPitch);
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Playback Speed & Pitch',
                          Icons.speed_rounded,
                          (_) => _buildPlaybackSpeedSection(),
                          shape: Shapes.sunny,
                        ),
                      );
                    }
                    if (index == 2) {
                      return _buildEffectTileCard(
                        icon: Icons.tune_rounded,
                        shape: Shapes.pill,
                        title: '3-Band Audio Tuning',
                        subtitle: _audioTuningEnabled
                            ? 'Low: ${_tuneLow.toInt()}dB | Mid: ${_tuneMid.toInt()}dB | High: ${_tuneHigh.toInt()}dB'
                            : 'Disabled',
                        isEnabled: _audioTuningEnabled,
                        onToggle: (v) {
                          setState(() => _audioTuningEnabled = v);
                          widget.player.setEqEnabled(v);
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          '3-Band Audio Tuning',
                          Icons.tune_rounded,
                          (_) => _buildAudioTuningSection(),
                          shape: Shapes.pill,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.show_chart_rounded,
                      shape: Shapes.gem,
                      title: 'Parametric EQ',
                      subtitle: _parametricEqEnabled
                          ? '${_parametricBands.length} Active Bands'
                          : 'Disabled',
                      isEnabled: _parametricEqEnabled,
                      onToggle: (v) {
                        setState(() => _parametricEqEnabled = v);
                        widget.player.setMultibandFxEnabled(v);
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Parametric EQ',
                        Icons.show_chart_rounded,
                        (_) => _buildParametricEqSection(),
                        shape: Shapes.gem,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 2: Bass & Subwoofer Engine
            SliverToBoxAdapter(
              child: _buildSectionHeader('Bass Engine',
                  icon: Icons.speaker_group_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Dynamic Bass',
                          Icons.speaker_group_rounded,
                          (_) => _buildHarmonicBassSection(),
                          shape: Shapes.boom,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Psychoacoustics Bass',
                          Icons.headphones_rounded,
                          (_) => _buildDynamicSystemSection(),
                          shape: Shapes.burst,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.speaker_group_rounded,
                        shape: Shapes.boom,
                        title: 'Dynamic Bass',
                        subtitle: _bassEnabled
                            ? '${_getHarmonicBassProfileName(_bassProfile)} | ${_bassCutoffHz.toInt()}Hz (${(_bassBoost * 100).toInt()}%)'
                            : 'Disabled',
                        isEnabled: _bassEnabled,
                        onToggle: (v) {
                          setState(() => _bassEnabled = v);
                          _updateHarmonicBass();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Dynamic Bass',
                          Icons.speaker_group_rounded,
                          (_) => _buildHarmonicBassSection(),
                          shape: Shapes.boom,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.headphones_rounded,
                      shape: Shapes.burst,
                      title: 'Psychoacoustics Bass',
                      subtitle: _dynamicSystemEnabled
                          ? '${_getTransducerProfileName(_dynamicSystemProfile)} (${(_dynamicSystemStrength * 100).toInt()}%)'
                          : 'Disabled',
                      isEnabled: _dynamicSystemEnabled,
                      onToggle: (v) {
                        setState(() => _dynamicSystemEnabled = v);
                        _updateDynamicSystem();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Psychoacoustics Bass',
                        Icons.headphones_rounded,
                        (_) => _buildDynamicSystemSection(),
                        shape: Shapes.burst,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 3: Clarity & Dynamics
            SliverToBoxAdapter(
              child: _buildSectionHeader('Clarity & Dynamics',
                  icon: Icons.auto_awesome),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Audio Clarity',
                          Icons.graphic_eq_rounded,
                          (_) => _buildClaritySection(),
                          shape: Shapes.gem,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Crystalizer',
                          Icons.auto_fix_high_rounded,
                          (_) => _buildCrystalizerSection(),
                          shape: Shapes.burst,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.graphic_eq_rounded,
                        shape: Shapes.gem,
                        title: 'Audio Clarity',
                        subtitle: _clarityEnabled
                            ? '${_getClarityProfileName(_clarityProfile)} (${(_clarityIntensity * 100).toInt()}%)'
                            : 'Disabled',
                        isEnabled: _clarityEnabled,
                        onToggle: (v) {
                          setState(() => _clarityEnabled = v);
                          _updateClarity();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Audio Clarity',
                          Icons.graphic_eq_rounded,
                          (_) => _buildClaritySection(),
                          shape: Shapes.gem,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.auto_fix_high_rounded,
                      shape: Shapes.burst,
                      title: 'Crystalizer',
                      subtitle: _crystalizerEnabled
                          ? 'Intensity: ${(_crystalizerIntensity * 100).toInt()}%'
                          : 'Disabled',
                      isEnabled: _crystalizerEnabled,
                      onToggle: (v) {
                        setState(() => _crystalizerEnabled = v);
                        _updateCrystalizer();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Crystalizer',
                        Icons.auto_fix_high_rounded,
                        (_) => _buildCrystalizerSection(),
                        shape: Shapes.burst,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 4: Spatial & Analog Warmth
            SliverToBoxAdapter(
              child: _buildSectionHeader('Spatial & Analog Warmth',
                  icon: Icons.headphones_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 4,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Crossfeed',
                          Icons.headphones_rounded,
                          (_) => _buildCrossfeedSection(),
                          shape: Shapes.arch,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Stereo Widener',
                          Icons.swap_horiz_rounded,
                          (_) => _buildStereoWidenSection(),
                          shape: Shapes.slanted,
                        );
                        break;
                      case 2:
                        _openDetailScreen(
                          'Stereo Enhancer',
                          Icons.surround_sound_rounded,
                          (_) => _buildStereoEnhancementSection(),
                          shape: Shapes.puffyDiamond,
                        );
                        break;
                      case 3:
                        _openDetailScreen(
                          'Analog Warmth',
                          Icons.album_rounded,
                          (_) => _buildAnalogWarmthSection(),
                          shape: Shapes.sunny,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.headphones_rounded,
                        shape: Shapes.arch,
                        title: 'Crossfeed',
                        subtitle: _crossfeedEnabled
                            ? (_crossfeedAlgorithmIndex == 1
                                ? 'Simple Reference'
                                : _crossfeedAlgorithmIndex == 2
                                    ? 'Bauer BS2B'
                                    : _crossfeedAlgorithmIndex == 3
                                        ? 'Jan Meier'
                                        : _crossfeedAlgorithmIndex == 4
                                            ? 'Custom Natural'
                                            : 'Ambiophonics (RACE)')
                            : 'Disabled',
                        isEnabled: _crossfeedEnabled,
                        onToggle: (v) {
                          setState(() => _crossfeedEnabled = v);
                          if (v) {
                            _updateCrossfeed();
                          } else {
                            widget.player.setCrossfeed(
                                enabled: false, preset: _crossfeedPreset);
                          }
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Crossfeed',
                          Icons.headphones_rounded,
                          (_) => _buildCrossfeedSection(),
                          shape: Shapes.arch,
                        ),
                      );
                    }
                    if (index == 1) {
                      return _buildEffectTileCard(
                        icon: Icons.swap_horiz_rounded,
                        shape: Shapes.slanted,
                        title: 'Stereo Widener',
                        subtitle: _stereoWidenEnabled
                            ? 'Width: ${_stereoWidenWidth.toStringAsFixed(1)}x'
                            : 'Disabled',
                        isEnabled: _stereoWidenEnabled,
                        onToggle: (v) {
                          setState(() => _stereoWidenEnabled = v);
                          if (v) {
                            _updateStereoWiden();
                          } else {
                            widget.player.setStereoWiden(
                                enabled: false,
                                width: _stereoWidenWidth,
                                delayMs: _stereoWidenDelayMs * 100.0);
                          }
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Stereo Widener',
                          Icons.swap_horiz_rounded,
                          (_) => _buildStereoWidenSection(),
                          shape: Shapes.slanted,
                        ),
                      );
                    }
                    if (index == 2) {
                      return _buildEffectTileCard(
                        icon: Icons.surround_sound_rounded,
                        shape: Shapes.puffyDiamond,
                        title: 'Stereo Enhancer',
                        subtitle: _stereoEnhancementEnabled
                            ? 'Mix: ${(_stereoEnhancementMix * 100).toInt()}%'
                            : 'Disabled',
                        isEnabled: _stereoEnhancementEnabled,
                        onToggle: (v) {
                          setState(() => _stereoEnhancementEnabled = v);
                          _updateStereoEnhancement();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Stereo Enhancer',
                          Icons.surround_sound_rounded,
                          (_) => _buildStereoEnhancementSection(),
                          shape: Shapes.puffyDiamond,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.album_rounded,
                      shape: Shapes.sunny,
                      title: 'Analog Warmth',
                      subtitle: _analogWarmthEnabled
                          ? '${_getAnalogWarmthProfileName(_analogWarmthProfile)} (${(_analogWarmthDrive * 100).toInt()}%)'
                          : 'Disabled',
                      isEnabled: _analogWarmthEnabled,
                      onToggle: (v) {
                        setState(() => _analogWarmthEnabled = v);
                        _updateAnalogWarmth();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Analog Warmth',
                        Icons.album_rounded,
                        (_) => _buildAnalogWarmthSection(),
                        shape: Shapes.sunny,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 5: Acoustic Space, Convolver & Surround
            SliverToBoxAdapter(
              child: _buildSectionHeader('Convolver & Surround',
                  icon: Icons.waves_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Convolver',
                          Icons.waves_rounded,
                          (_) => _buildConvolverSection(),
                          shape: Shapes.c4SidedCookie,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Spatial Surround',
                          Icons.surround_sound_rounded,
                          (_) => _buildSurroundSection(),
                          shape: Shapes.puffyDiamond,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.waves_rounded,
                        shape: Shapes.c4SidedCookie,
                        title: 'Convolver',
                        subtitle: _convolverEnabled
                            ? (_convolverIrFileName ?? 'Acoustic IR Active')
                            : 'Disabled',
                        isEnabled: _convolverEnabled,
                        onToggle: (v) {
                          setState(() => _convolverEnabled = v);
                          _updateConvolver();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Convolver',
                          Icons.waves_rounded,
                          (_) => _buildConvolverSection(),
                          shape: Shapes.c4SidedCookie,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.surround_sound_rounded,
                      shape: Shapes.puffyDiamond,
                      title: 'Spatial Surround',
                      subtitle: _surroundEnabled
                          ? _getSurroundModeSubtitle()
                          : 'Disabled',
                      isEnabled: _surroundEnabled,
                      onToggle: (v) {
                        setState(() {
                          _surroundEnabled = v;
                          if (v && _surroundMode == SurroundMode.off) {
                            _surroundMode = SurroundMode.fieldExpander;
                          }
                        });
                        _updateSurround();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Spatial Surround',
                        Icons.surround_sound_rounded,
                        (_) => _buildSurroundSection(),
                        shape: Shapes.puffyDiamond,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 6: Reverb
            SliverToBoxAdapter(
              child:
                  _buildSectionHeader('Reverb', icon: Icons.wb_twilight_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 1,
                  onTap: (index) {
                    _openDetailScreen(
                      'Reverb',
                      Icons.wb_twilight_rounded,
                      (_) => _buildReverbSection(),
                      shape: Shapes.flower,
                    );
                  },
                  itemBuilder: (context, index) {
                    return _buildEffectTileCard(
                      icon: Icons.wb_twilight_rounded,
                      shape: Shapes.flower,
                      title: 'Reverb',
                      subtitle: _reverbEnabled
                          ? 'Mix ${(_reverbMix * 100).toInt()}% | Room ${(_reverbRoomSize * 100).toInt()}%'
                          : 'Disabled',
                      isEnabled: _reverbEnabled,
                      onToggle: (v) {
                        setState(() => _reverbEnabled = v);
                        _updateReverb();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Reverb',
                        Icons.wb_twilight_rounded,
                        (_) => _buildReverbSection(),
                        shape: Shapes.flower,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 7: Master Dynamics & Protection
            SliverToBoxAdapter(
              child: _buildSectionHeader('Master Dynamics & Protection',
                  icon: Icons.shield_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Master Peak Limiter',
                          Icons.shield_rounded,
                          (_) => _buildMasterLimiterSection(),
                          shape: Shapes.square,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Soft Anti-Clipping Limiter',
                          Icons.compress_rounded,
                          (_) => _buildLimiterSection(),
                          shape: Shapes.diamond,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.shield_rounded,
                        shape: Shapes.square,
                        title: 'Master Peak Limiter',
                        subtitle: _masterLimiterEnabled
                            ? 'Ceiling: ${_masterLimiterCeilingDb.toStringAsFixed(1)} dBFS'
                            : 'Disabled',
                        isEnabled: _masterLimiterEnabled,
                        onToggle: (v) {
                          setState(() => _masterLimiterEnabled = v);
                          _updateMasterLimiter();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Master Peak Limiter',
                          Icons.shield_rounded,
                          (_) => _buildMasterLimiterSection(),
                          shape: Shapes.square,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.compress_rounded,
                      shape: Shapes.diamond,
                      title: 'Soft Anti-Clipping Limiter',
                      subtitle: _limiterEnabled
                          ? 'Threshold: ${_limiterThreshold.toInt()}dB'
                          : 'Disabled',
                      isEnabled: _limiterEnabled,
                      onToggle: (v) {
                        setState(() => _limiterEnabled = v);
                        if (v) {
                          _applyLimiter();
                        } else {
                          widget.player.setLimiterEnabled(false);
                        }
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'Soft Anti-Clipping Limiter',
                        Icons.compress_rounded,
                        (_) => _buildLimiterSection(),
                        shape: Shapes.diamond,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Bottom Spacing for floating player / nav
            const SliverToBoxAdapter(
              child: SizedBox(height: 120),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label) {
    final isSelected = _activePreset == label;
    return M3EChip(
      label: label,
      type: M3EChipType.filter,
      selected: isSelected,
      onPressed: () => _applyPreset(label),
    );
  }

  Future<void> _promptForValue({
    required String title,
    required double currentValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) async {
    final controller =
        TextEditingController(text: currentValue.toStringAsFixed(2));
    await M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Enter $title',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allowed range: $min to $max',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                M3ETextField(
                  controller: controller,
                  label: 'Value',
                ),
              ],
            ),
          ),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                onChanged(val.clamp(min, max));
              }
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSpeedSection() {
    final isNormal = (_playbackPitch - 1.0).abs() < 0.01;
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.sunny,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.speed_rounded, color: primaryColor, size: 20),
      ),
      // ),
      title: 'Speed & Pitch',
      subtitle: '${_playbackPitch.toStringAsFixed(2)}x Speed',
      isEnabled: !isNormal,
      onToggle: (v) {
        final newPitch = v ? 1.25 : 1.0;
        setState(() => _playbackPitch = newPitch);
        widget.player.setPitch(newPitch);
        AppStateService.instance.savePlaybackSpeed(newPitch);
      },
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Speed: ${_playbackPitch.toStringAsFixed(2)}x',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold),
              ),
              M3EButton.icon(
                icon: Icon(Icons.tune_rounded, size: 16, color: primaryColor),
                label:
                    Text('Adjust Speed', style: TextStyle(color: primaryColor)),
                onPressed: () async {
                  final res = await showPlaybackSpeedModal(
                    context,
                    widget.player,
                    currentPitch: _playbackPitch,
                  );
                  if (res != null) {
                    setState(() => _playbackPitch = res);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGraphicEqSection() {
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.clampShell,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.equalizer_rounded, color: primaryColor, size: 20),
        //  ),
      ),
      title: 'Graphic Equalizer',
      subtitle: '${_eqFrequencies.length}-Band Frequency Shaping',
      isEnabled: _masterEqEnabled,
      onToggle: (v) {
        setState(() => _masterEqEnabled = v);
        widget.player.setMultibandEqEnabled(v);
        _saveEqState();
      },
      children: [
        // Band Count Segmented Selector
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: M3ESegmentedButton<int>(
            segments: const [
              M3ESegment(value: 10, label: '10 Bands'),
              M3ESegment(value: 16, label: '16 Bands'),
              M3ESegment(value: 32, label: '32 Bands'),
            ],
            selected: {
              _eqFrequencies.length == 10 ||
                      _eqFrequencies.length == 16 ||
                      _eqFrequencies.length == 32
                  ? _eqFrequencies.length
                  : 10
            },
            onSelectionChanged: (Set<int> val) {
              if (val.isNotEmpty) {
                final bands = val.first;
                setState(() {
                  _setupFrequencies(bands);
                  widget.player.initMultibandEq(_eqFrequencies);
                  _applyPreset(_activePreset);
                });
                _saveEqState();
              }
            },
          ),
        ),
        // Preset Chips Row
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              for (final preset in [
                'Flat',
                'Bass Boost',
                'Vocal',
                'Treble',
                'Rock',
                'Jazz',
              ]) ...[
                _buildPresetChip(preset),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: _buildGraphicEqSliders(),
        ),
      ],
    );
  }

  Widget _buildGraphicEqSliders() {
    return RepaintBoundary(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preamp Slider (Independent of Graphic EQ toggle)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                SizedBox(
                  height: 160,
                  width: 44,
                  child: M3ESlider.vertical(
                    value: _preampDb,
                    min: -12.0,
                    max: 12.0,
                    onChanged: (v) {
                      setState(() {
                        _preampDb = v;
                        double gain = math.pow(10, v / 20).toDouble();
                        widget.player.setGain(gain);
                      });
                    },
                    onChangeEnd: (_) => _saveEqState(),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onLongPress: () => _promptForValue(
                    title: 'PREAMP',
                    currentValue: _preampDb,
                    min: -12.0,
                    max: 12.0,
                    onChanged: (v) {
                      setState(() {
                        _preampDb = v;
                        double gain = math.pow(10, v / 20).toDouble();
                        widget.player.setGain(gain);
                      });
                      _saveEqState();
                    },
                  ),
                  child: Text(
                    '${_preampDb > 0 ? '+' : ''}${_preampDb.toStringAsFixed(1)} dB',
                    style: const TextStyle(
                      color: Colors.deepOrangeAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('PREAMP',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 190,
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.only(right: 6),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: List.generate(_eqFrequencies.length, (i) {
                  final freq = _eqFrequencies[i];
                  String label = freq >= 1000
                      ? '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k'
                      : '${freq.toInt()}';

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 160,
                          width: 44,
                          child: M3ESlider.vertical(
                            value: _eqGains[i],
                            min: -12.0,
                            max: 12.0,
                            onChanged: _masterEqEnabled
                                ? (v) {
                                    setState(() {
                                      _eqGains[i] = v;
                                      _activePreset = 'Custom';
                                      widget.player
                                          .setMultibandEqBandGain(i, v);
                                    });
                                  }
                                : null,
                            onChangeEnd:
                                _masterEqEnabled ? (_) => _saveEqState() : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onLongPress: _masterEqEnabled
                              ? () => _promptForValue(
                                    title: 'Band Gain ($label)',
                                    currentValue: _eqGains[i],
                                    min: -12.0,
                                    max: 12.0,
                                    onChanged: (v) {
                                      setState(() {
                                        _eqGains[i] = v;
                                        _activePreset = 'Custom';
                                        widget.player
                                            .setMultibandEqBandGain(i, v);
                                      });
                                      _saveEqState();
                                    },
                                  )
                              : null,
                          child: Text(
                            '${_eqGains[i] > 0 ? '+' : ''}${_eqGains[i].toStringAsFixed(1)} dB',
                            style: TextStyle(
                              color: _masterEqEnabled
                                  ? primaryColor
                                  : Colors.white24,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrystalizerSection() {
    const crystalColor = Color(0xFF00C9B1);
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.burst,
        width: 40,
        height: 40,
        color: const Color(0x2600C9B1),
        border: const BorderSide(
          color: Color(0x6600C9B1),
          width: 1.0,
        ),
        child: */
          const Center(
        child: Icon(Icons.auto_fix_high_rounded, color: crystalColor, size: 20),
        // ),
      ),
      title: 'Crystalizer',
      subtitle: 'Audiophile transient reconstruction',
      isEnabled: _crystalizerEnabled,
      onToggle: (v) {
        setState(() => _crystalizerEnabled = v);
        _updateCrystalizer();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'INTENSITY',
              value: _crystalizerIntensity,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _crystalizerEnabled ? crystalColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _crystalizerIntensity = v);
                if (_crystalizerEnabled) _updateCrystalizer();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'AIR SHELF',
              value: _crystalizerShelfGain,
              min: 0.0,
              max: 6.0,
              flatValue: 2.0,
              activeColor: _crystalizerHighShelf && _crystalizerEnabled
                  ? crystalColor
                  : Colors.white38,
              valueFormatter: (v) =>
                  '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                if (!_crystalizerHighShelf) return;
                setState(() => _crystalizerShelfGain = v);
                if (_crystalizerEnabled) _updateCrystalizer();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // High-shelf toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'High-shelf "Air" boost',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            M3ESwitch(
              selectedIcon: Icon(Icons.check, color: primaryColor),
              value: _crystalizerHighShelf,
              onChanged: (v) {
                setState(() => _crystalizerHighShelf = v);
                if (_crystalizerEnabled) _updateCrystalizer();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x1A00C9B1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x4000C9B1)),
            ),
            child: Text(
              'Recovers transient detail & "air" lost in compressed audio',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCrossfeedSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.arch,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child:*/
          Center(
        child: Icon(Icons.headphones_rounded, color: primaryColor, size: 20),
        //  ),
      ),
      title: 'Crossfeed',
      subtitle: 'Simulate natural acoustic speaker listening',
      isEnabled: _crossfeedEnabled,
      onToggle: (v) {
        setState(() => _crossfeedEnabled = v);
        _updateCrossfeed();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Algorithm',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            /* M3EContainer(
              Shapes.pill,
              color: surfaceDarkColor,
              border: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
              child:*/
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _crossfeedAlgorithmIndex,
                  dropdownColor: surfaceDarkerColor,
                  icon:
                      Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Simple Reference')),
                    DropdownMenuItem(value: 2, child: Text('Bauer BS2B')),
                    DropdownMenuItem(value: 3, child: Text('Jan Meier')),
                    DropdownMenuItem(value: 4, child: Text('Custom Natural')),
                    DropdownMenuItem(
                        value: 5, child: Text('Ambiophonics (RACE)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _crossfeedAlgorithmIndex = val;
                        _crossfeedEnabled = true;
                      });
                      _updateCrossfeed();
                      _saveEqState();
                    }
                  },
                  // ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_crossfeedAlgorithmIndex >= 1 && _crossfeedAlgorithmIndex <= 4) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'CROSSFEED MIX',
                value: _crossfeedMix,
                min: 0.0,
                max: 1.0,
                flatValue: 0.5,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                isPercentage: true,
                valueFormatter: (v) => '${(v * 100).toInt()}%',
                onChanged: (v) {
                  setState(() => _crossfeedMix = v);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
              ModernAudioKnob(
                label: 'ITD DELAY',
                value: (_crossfeedDelayMs - 0.05) / 1.95,
                min: 0.0,
                max: 1.0,
                flatValue: (0.40 - 0.05) / 1.95,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                valueFormatter: (_) =>
                    '${(_crossfeedDelayMs * 1000).round()}µs',
                onChanged: (v) {
                  setState(() => _crossfeedDelayMs = 0.05 + v * 1.95);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
              ModernAudioKnob(
                label: 'CUTOFF FREQ',
                value: (_crossfeedCutoffHz - 200.0) / 2800.0,
                min: 0.0,
                max: 1.0,
                flatValue: (700.0 - 200.0) / 2800.0,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                valueFormatter: (_) => '${_crossfeedCutoffHz.toInt()}Hz',
                onChanged: (v) {
                  setState(() => _crossfeedCutoffHz = 200.0 + v * 2800.0);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () {
              setState(() => _crossfeedCompensation = !_crossfeedCompensation);
              if (_crossfeedEnabled) _updateCrossfeed();
              _saveEqState();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: surfaceDarkColor.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _crossfeedCompensation
                      ? primaryColor.withValues(alpha: 0.4)
                      : Colors.white10,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.equalizer_rounded,
                        size: 18,
                        color: _crossfeedCompensation
                            ? primaryColor
                            : Colors.white54,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Output Loudness Compensation',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                  M3ESwitch(
                    selectedIcon: Icon(Icons.check, color: primaryColor),
                    value: _crossfeedCompensation,
                    onChanged: (v) {
                      setState(() => _crossfeedCompensation = v);
                      if (_crossfeedEnabled) _updateCrossfeed();
                      _saveEqState();
                    },
                  ),
                ],
              ),
            ),
          ),
        ] else if (_crossfeedAlgorithmIndex == 5) ...[
          RepaintBoundary(
            child: RaceSoundstageVisualizer(
              delayMs: _raceDelayMs,
              alpha: _raceAlpha,
              lpfHz: _raceLpfHz,
              isEnabled: _crossfeedEnabled,
              primaryColor: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'ITD DELAY',
                value: (_raceDelayMs - 0.05) / 0.35,
                min: 0.0,
                max: 1.0,
                flatValue: (0.166 - 0.05) / 0.35,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                valueFormatter: (_) => '${(_raceDelayMs * 1000).round()}µs',
                onChanged: (v) {
                  setState(() => _raceDelayMs = 0.05 + v * 0.35);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
              ModernAudioKnob(
                label: 'ATTENUATION',
                value: (_raceAlpha - 0.10) / 0.80,
                min: 0.0,
                max: 1.0,
                flatValue: (0.55 - 0.10) / 0.80,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                isPercentage: true,
                valueFormatter: (_) => '${(_raceAlpha * 100).toInt()}%',
                onChanged: (v) {
                  setState(() => _raceAlpha = 0.10 + v * 0.80);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
              ModernAudioKnob(
                label: 'HEAD LPF',
                value: (_raceLpfHz - 500.0) / 7500.0,
                min: 0.0,
                max: 1.0,
                flatValue: (2500.0 - 500.0) / 7500.0,
                activeColor: _crossfeedEnabled ? primaryColor : Colors.white,
                valueFormatter: (_) => '${_raceLpfHz.toInt()}Hz',
                onChanged: (v) {
                  setState(() => _raceLpfHz = 500.0 + v * 7500.0);
                  if (_crossfeedEnabled) _updateCrossfeed();
                  _saveEqState();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStereoWidenSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.slanted,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.swap_horiz_rounded, color: primaryColor, size: 20),
        // ),
      ),
      title: 'Stereo Widener',
      subtitle: 'Mid/Side matrix & Haas effect width expansion',
      isEnabled: _stereoWidenEnabled,
      onToggle: (v) {
        setState(() => _stereoWidenEnabled = v);
        if (v) {
          _updateStereoWiden();
        } else {
          widget.player.setStereoWiden(
              enabled: false,
              width: _stereoWidenWidth,
              delayMs: _stereoWidenDelayMs * 100.0);
        }
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'WIDTH',
              value: (_stereoWidenWidth / 5.0).clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              flatValue: 0.2, // Maps to 1.0
              activeColor: _stereoWidenEnabled ? primaryColor : Colors.white,
              displayMultiplier: 5.0,
              valueFormatter: (v) => '${(v * 5.0).toStringAsFixed(1)}x',
              onChanged: (v) {
                setState(() => _stereoWidenWidth = v * 5.0);
                if (_stereoWidenEnabled) _updateStereoWiden();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'HAAS DELAY',
              value: _stereoWidenDelayMs,
              min: 0.0,
              max: 1.0,
              flatValue: 0.15,
              activeColor: _stereoWidenEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}ms',
              onChanged: (v) {
                setState(() => _stereoWidenDelayMs = v);
                if (_stereoWidenEnabled) _updateStereoWiden();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStereoEnhancementSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.puffyDiamond,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child:*/
          Center(
        child:
            Icon(Icons.surround_sound_rounded, color: primaryColor, size: 20),
        //),
      ),
      title: 'Stereo Enhancer',
      subtitle: 'Warped PFB M/S Widening',
      isEnabled: _stereoEnhancementEnabled,
      onToggle: (v) {
        setState(() => _stereoEnhancementEnabled = v);
        _updateStereoEnhancement();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'STEREO MIX',
              value: _stereoEnhancementMix,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor:
                  _stereoEnhancementEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _stereoEnhancementMix = v);
                if (_stereoEnhancementEnabled) _updateStereoEnhancement();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              _stereoEnhancementMix == 0.5
                  ? 'Pass-through (Original Stereo)'
                  : (_stereoEnhancementMix > 0.5
                      ? 'Stereo Widening (Center Subtraction)'
                      : 'Mono Center Extraction'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  void _updateCrystalizer() {
    widget.player.setCrystalizer(
      enabled: _crystalizerEnabled,
      intensity: _crystalizerIntensity,
      highShelfEnabled: _crystalizerHighShelf,
      highShelfGainDb: _crystalizerShelfGain,
    );
  }

  void _updateCrossfeed() {
    if (!_crossfeedEnabled) {
      widget.player.setCrossfeed(enabled: false, preset: 0);
      widget.player.setCrossfeedAlgorithm(CrossfeedAlgorithm.off);
      return;
    }

    if (_crossfeedAlgorithmIndex == 5) {
      // Legacy RACE / Ambiophonics path
      widget.player.setCrossfeed(enabled: true, preset: 4);
      widget.player.setRaceParams(
        delayMs: _raceDelayMs,
        alpha: _raceAlpha,
        lpfHz: _raceLpfHz,
      );
    } else {
      CrossfeedAlgorithm algo = CrossfeedAlgorithm.off;
      if (_crossfeedAlgorithmIndex == 1) {
        algo = CrossfeedAlgorithm.simple;
      } else if (_crossfeedAlgorithmIndex == 2) {
        algo = CrossfeedAlgorithm.bs2b;
      } else if (_crossfeedAlgorithmIndex == 3) {
        algo = CrossfeedAlgorithm.meier;
      } else if (_crossfeedAlgorithmIndex == 4) {
        algo = CrossfeedAlgorithm.natural;
      }
      widget.player.setCrossfeedAlgorithm(algo);
      widget.player.setCrossfeedParams(
        mix: _crossfeedMix,
        delayMs: _crossfeedDelayMs,
        cutoffHz: _crossfeedCutoffHz,
        outputCompensation: _crossfeedCompensation,
      );
    }
  }

  void _updateStereoWiden() {
    double delayMsMapping = _stereoWidenDelayMs * 100.0;
    widget.player.setStereoWiden(
      enabled: _stereoWidenEnabled,
      width: _stereoWidenWidth,
      delayMs: delayMsMapping,
    );
  }

  Widget _buildAudioTuningSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.pill,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.tune_rounded, color: primaryColor, size: 20),
      ),
      //),
      title: '3-Band Audio Tuning',
      subtitle: 'Bass, midrange & treble shelving tone control',
      isEnabled: _audioTuningEnabled,
      onToggle: (v) {
        setState(() => _audioTuningEnabled = v);
        widget.player.setEqEnabled(v);
        if (v) {
          widget.player.setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
        }
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'BASS',
              value: _tuneLow,
              min: -24.0,
              max: 12.0,
              flatValue: 0.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() => _tuneLow = v);
                if (_audioTuningEnabled) {
                  widget.player
                      .setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
                }
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'MID',
              value: _tuneMid,
              min: -24.0,
              max: 12.0,
              flatValue: 0.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() => _tuneMid = v);
                if (_audioTuningEnabled) {
                  widget.player
                      .setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
                }
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'TREBLE',
              value: _tuneHigh,
              min: -24.0,
              max: 12.0,
              flatValue: 0.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() => _tuneHigh = v);
                if (_audioTuningEnabled) {
                  widget.player
                      .setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
                }
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _applyParametricBands() {
    widget.player.setMultibandFxBands(_parametricBands);
  }

  Widget _buildParametricEqSection() {
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.gem,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child:*/
          Center(
        child: Icon(Icons.show_chart_rounded, color: primaryColor, size: 20),
        //),
      ),
      title: 'Parametric Equalizer',
      subtitle: 'Dynamic cascade filter nodes & visual response curve',
      isEnabled: _parametricEqEnabled,
      onToggle: (v) {
        setState(() {
          _parametricEqEnabled = v;
          if (v && _parametricBands.isEmpty) {
            _parametricBands.addAll([
              const EqBandConfig(
                  type: EqBandType.lowshelf,
                  frequencyHz: 120,
                  gainDb: 0.0,
                  slope: 1.0),
              const EqBandConfig(
                  type: EqBandType.peak,
                  frequencyHz: 1000,
                  gainDb: 0.0,
                  q: 1.2),
              const EqBandConfig(
                  type: EqBandType.highshelf,
                  frequencyHz: 9000,
                  gainDb: 0.0,
                  slope: 1.0),
            ]);
          }
          if (v) {
            widget.player.initMultibandFx(_parametricBands);
          }
          widget.player.setMultibandFxEnabled(v);
        });
      },
      children: [
        RepaintBoundary(
          child: ParametricEqGraph(
            bands: _parametricBands,
            isEnabled: _parametricEqEnabled,
            height: 110.0,
            primaryColor: primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            M3EButton.icon(
              icon: Icon(Icons.add_rounded, color: primaryColor, size: 18),
              label: Text('Add Band', style: TextStyle(color: primaryColor)),
              onPressed: () {
                setState(() {
                  _parametricBands.add(const EqBandConfig(
                    type: EqBandType.peak,
                    frequencyHz: 1000,
                    gainDb: 0.0,
                    q: 1.2,
                    slope: 1.0,
                  ));
                  _applyParametricBands();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _parametricBands.length,
            itemBuilder: (context, index) {
              final band = _parametricBands[index];
              return _buildParametricBandCard(index, band);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParametricBandCard(int index, EqBandConfig band) {
    return Container(
      width: 255,
      margin: const EdgeInsets.only(right: 14),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Band ${index + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5)),
                  Row(
                    children: [
                      Text('${band.frequencyHz.toInt()}Hz',
                          style: TextStyle(
                              color: primaryColor,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      M3EIconButton(
                        onPressed: () {
                          setState(() {
                            _parametricBands.removeAt(index);
                            _applyParametricBands();
                          });
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        variant: M3EIconButtonVariant.standard,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Type Selector
              /* M3EContainer(
                Shapes.pill,
                color: surfaceDarkerColor,
                border: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: */
              DropdownButtonHideUnderline(
                child: DropdownButton<EqBandType>(
                  value: band.type,
                  isExpanded: true,
                  dropdownColor: surfaceDarkerColor,
                  icon: const Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white54),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  items: EqBandType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(switch (t) {
                              EqBandType.peak => 'Peak EQ',
                              EqBandType.bandpass => 'Band-Pass',
                              EqBandType.notch => 'Notch',
                              EqBandType.lowshelf => 'Low Shelf',
                              EqBandType.highshelf => 'High Shelf',
                              EqBandType.lowpass => 'Low-Pass',
                              EqBandType.highpass => 'High-Pass',
                            }),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _parametricBands[index] = EqBandConfig(
                          type: v,
                          frequencyHz: band.frequencyHz,
                          enabled: band.enabled,
                          q: band.q,
                          gainDb: band.gainDb,
                          slope: band.slope,
                        );
                        _applyParametricBands();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Frequency Knob
                  ModernAudioKnob(
                    size: 52,
                    label: 'FREQ',
                    value: band.frequencyHz.clamp(20.0, 20000.0),
                    min: 20.0,
                    max: 20000.0,
                    flatValue: 1000.0,
                    activeColor:
                        _parametricEqEnabled ? primaryColor : Colors.white,
                    valueFormatter: (v) => '${v.toInt()}Hz',
                    onChanged: (v) {
                      setState(() {
                        _parametricBands[index] = EqBandConfig(
                          type: band.type,
                          frequencyHz: v,
                          enabled: band.enabled,
                          q: band.q,
                          gainDb: band.gainDb,
                          slope: band.slope,
                        );
                        _applyParametricBands();
                      });
                    },
                  ),

                  // Q Factor / Slope Knob
                  ModernAudioKnob(
                    size: 52,
                    label: band.type == EqBandType.lowshelf ||
                            band.type == EqBandType.highshelf
                        ? 'SLOPE'
                        : 'Q',
                    value: band.type == EqBandType.lowshelf ||
                            band.type == EqBandType.highshelf
                        ? band.slope
                        : band.q,
                    min: 0.1,
                    max: 18.0,
                    flatValue: 1.0,
                    activeColor:
                        _parametricEqEnabled ? primaryColor : Colors.white,
                    valueFormatter: (v) => v.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() {
                        if (band.type == EqBandType.lowshelf ||
                            band.type == EqBandType.highshelf) {
                          _parametricBands[index] = EqBandConfig(
                            type: band.type,
                            frequencyHz: band.frequencyHz,
                            enabled: band.enabled,
                            q: band.q,
                            gainDb: band.gainDb,
                            slope: v,
                          );
                        } else {
                          _parametricBands[index] = EqBandConfig(
                            type: band.type,
                            frequencyHz: band.frequencyHz,
                            enabled: band.enabled,
                            q: v,
                            gainDb: band.gainDb,
                            slope: band.slope,
                          );
                        }
                        _applyParametricBands();
                      });
                    },
                  ),

                  // Gain Knob (for Peak, Low Shelf, High Shelf)
                  if (band.type == EqBandType.peak ||
                      band.type == EqBandType.lowshelf ||
                      band.type == EqBandType.highshelf)
                    ModernAudioKnob(
                      size: 52,
                      label: 'GAIN',
                      value: band.gainDb,
                      min: -24.0,
                      max: 24.0,
                      flatValue: 0.0,
                      activeColor:
                          _parametricEqEnabled ? primaryColor : Colors.white,
                      valueFormatter: (v) =>
                          '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                      onChanged: (v) {
                        setState(() {
                          _parametricBands[index] = EqBandConfig(
                            type: band.type,
                            frequencyHz: band.frequencyHz,
                            enabled: band.enabled,
                            q: band.q,
                            gainDb: v,
                            slope: band.slope,
                          );
                          _applyParametricBands();
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHarmonicBassProfileName(HarmonicBassProfile profile) {
    return switch (profile) {
      HarmonicBassProfile.naturalBass => 'Natural Bass',
      HarmonicBassProfile.pureBass => 'Punchy Kick',
      HarmonicBassProfile.subwoofer => 'Subwoofer Rumble',
      HarmonicBassProfile.harmonicExciter => 'Harmonic Exciter',
      HarmonicBassProfile.pultecDeep => 'Pultec Deep Sub',
    };
  }

  String _getTransducerProfileName(TransducerProfile profile) {
    return switch (profile) {
      TransducerProfile.earphone => 'In-Ear Earbuds',
      TransducerProfile.headphone => 'Over-Ear Headphones',
      TransducerProfile.highEndReference => 'Studio Reference',
      TransducerProfile.speakerMonitor => 'Desktop Speakers',
      TransducerProfile.extremeSubwoofer => 'Extreme Subwoofer',
      TransducerProfile.pureDynamic => 'Pure Dynamic',
    };
  }

  String _getClarityProfileName(AudioClarityProfile profile) {
    return switch (profile) {
      AudioClarityProfile.transientCrisp => 'Crisp & Detailed',
      AudioClarityProfile.airShelf => 'Air & Sparkle',
      AudioClarityProfile.presenceExciter => 'Vocal Presence',
      AudioClarityProfile.harmonicBrilliance => 'Studio Brilliance',
    };
  }

  String _getAnalogWarmthProfileName(AnalogWarmthProfile profile) {
    return switch (profile) {
      AnalogWarmthProfile.triode12AX7 => 'Vacuum Tube (12AX7)',
      AnalogWarmthProfile.magneticTape => 'Reel-to-Reel Tape',
      AnalogWarmthProfile.vintagePreamp => 'Console Preamp',
    };
  }

  Widget _buildHarmonicBassSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.speaker_group_rounded, color: primaryColor, size: 20),
      ),
      title: 'Dynamic Bass',
      subtitle: 'Powerful chest pumping bass & subwoofer rumble',
      isEnabled: _bassEnabled,
      onToggle: (v) {
        setState(() => _bassEnabled = v);
        _updateHarmonicBass();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bass Character',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<HarmonicBassProfile>(
                value: _bassProfile,
                dropdownColor: surfaceDarkerColor,
                icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                    value: HarmonicBassProfile.naturalBass,
                    child: Text('Natural Bass'),
                  ),
                  DropdownMenuItem(
                    value: HarmonicBassProfile.pureBass,
                    child: Text('Pure Bass'),
                  ),
                  DropdownMenuItem(
                    value: HarmonicBassProfile.subwoofer,
                    child: Text('Aggressive Bass'),
                  ),
                  DropdownMenuItem(
                    value: HarmonicBassProfile.harmonicExciter,
                    child: Text('Harmonic Exciter'),
                  ),
                  DropdownMenuItem(
                    value: HarmonicBassProfile.pultecDeep,
                    child: Text('Pultec Deep'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _bassProfile = val);
                    if (_bassEnabled) _updateHarmonicBass();
                    _saveEqState();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'FOCUS FREQ',
              value: _bassCutoffHz,
              min: 30.0,
              max: 160.0,
              flatValue: 60.0,
              activeColor: _bassEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() => _bassCutoffHz = v);
                if (_bassEnabled) _updateHarmonicBass();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'BASS POWER',
              value: _bassBoost,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _bassEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _bassBoost = v);
                if (_bassEnabled) _updateHarmonicBass();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDynamicSystemSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.headphones_rounded, color: primaryColor, size: 20),
      ),
      title: 'Psychoacoustics Bass',
      subtitle: 'Dynamic Crossover & Spatialization for your Listening Gear',
      isEnabled: _dynamicSystemEnabled,
      onToggle: (v) {
        setState(() => _dynamicSystemEnabled = v);
        _updateDynamicSystem();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Listening Gear',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<TransducerProfile>(
                value: _dynamicSystemProfile,
                dropdownColor: surfaceDarkerColor,
                icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                    value: TransducerProfile.earphone,
                    child: Text('In-Ear Earbuds'),
                  ),
                  DropdownMenuItem(
                    value: TransducerProfile.headphone,
                    child: Text('Over-Ear Headphones'),
                  ),
                  DropdownMenuItem(
                    value: TransducerProfile.highEndReference,
                    child: Text('Reference'),
                  ),
                  DropdownMenuItem(
                    value: TransducerProfile.speakerMonitor,
                    child: Text('Desktop Speakers'),
                  ),
                  DropdownMenuItem(
                    value: TransducerProfile.extremeSubwoofer,
                    child: Text('Club Subwoofer'),
                  ),
                  DropdownMenuItem(
                    value: TransducerProfile.pureDynamic,
                    child: Text('Pure Dynamic'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _dynamicSystemProfile = val);
                    if (_dynamicSystemEnabled) _updateDynamicSystem();
                    _saveEqState();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'OPTIMIZE',
              value: _dynamicSystemStrength,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _dynamicSystemEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _dynamicSystemStrength = v);
                if (_dynamicSystemEnabled) _updateDynamicSystem();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClaritySection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.graphic_eq_rounded, color: primaryColor, size: 20),
      ),
      title: 'Audio Clarity',
      subtitle: 'Brings out crisp details, vocal presence & high-end sheen',
      isEnabled: _clarityEnabled,
      onToggle: (v) {
        setState(() => _clarityEnabled = v);
        _updateClarity();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Clarity Style',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<AudioClarityProfile>(
                value: _clarityProfile,
                dropdownColor: surfaceDarkerColor,
                icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                    value: AudioClarityProfile.transientCrisp,
                    child: Text('Crisp'),
                  ),
                  DropdownMenuItem(
                    value: AudioClarityProfile.airShelf,
                    child: Text('Air'),
                  ),
                  DropdownMenuItem(
                    value: AudioClarityProfile.presenceExciter,
                    child: Text('Vocal'),
                  ),
                  DropdownMenuItem(
                    value: AudioClarityProfile.harmonicBrilliance,
                    child: Text('Harmonic Brilliance'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _clarityProfile = val);
                    if (_clarityEnabled) _updateClarity();
                    _saveEqState();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'CLARITY',
              value: _clarityIntensity,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _clarityEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _clarityIntensity = v);
                if (_clarityEnabled) _updateClarity();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalogWarmthSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.album_rounded, color: primaryColor, size: 20),
      ),
      title: 'Analog Warmth',
      subtitle: 'Adds rich analog harmonics, velvety depth & vintage character',
      isEnabled: _analogWarmthEnabled,
      onToggle: (v) {
        setState(() => _analogWarmthEnabled = v);
        _updateAnalogWarmth();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Warmth Flavor',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<AnalogWarmthProfile>(
                value: _analogWarmthProfile,
                dropdownColor: surfaceDarkerColor,
                icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                    value: AnalogWarmthProfile.triode12AX7,
                    child: Text('Vacuum Tube'),
                  ),
                  DropdownMenuItem(
                    value: AnalogWarmthProfile.magneticTape,
                    child: Text('Vintage Tape'),
                  ),
                  DropdownMenuItem(
                    value: AnalogWarmthProfile.vintagePreamp,
                    child: Text('Console Preamp'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _analogWarmthProfile = val);
                    if (_analogWarmthEnabled) _updateAnalogWarmth();
                    _saveEqState();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'WARMTH DRIVE',
              value: _analogWarmthDrive,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _analogWarmthEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _analogWarmthDrive = v);
                if (_analogWarmthEnabled) _updateAnalogWarmth();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConvolverSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.waves_rounded, color: primaryColor, size: 20),
      ),
      title: 'Acoustic Space & Convolver',
      subtitle:
          'Simulate playing inside real halls, spaces & acoustic impulses',
      isEnabled: _convolverEnabled,
      onToggle: (v) {
        setState(() => _convolverEnabled = v);
        _updateConvolver();
        _saveEqState();
      },
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceDarkerColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _convolverIrFileName ?? 'No Impulse Response Loaded',
                      style: TextStyle(
                        color: _convolverIrFileName != null
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _convolverIrPath != null
                          ? 'Active Acoustic Room Simulation'
                          : 'Load a .wav room impulse response file',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_convolverIrPath != null)
                IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: Colors.white54, size: 20),
                  tooltip: 'Clear File',
                  onPressed: () {
                    setState(() {
                      _convolverIrPath = null;
                      _convolverIrFileName = null;
                      _convolverEnabled = false;
                    });
                    widget.player.clearConvolverIr();
                    _updateConvolver();
                    _saveEqState();
                  },
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Browse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor.withValues(alpha: 0.25),
                  foregroundColor: primaryColor,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _pickImpulseResponse,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'ROOM WET',
              value: _convolverWet,
              min: 0.0,
              max: 1.0,
              flatValue: 1.0,
              activeColor: _convolverEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _convolverWet = v);
                if (_convolverEnabled) _updateConvolver();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'AUDIO DRY',
              value: _convolverDry,
              min: 0.0,
              max: 1.0,
              flatValue: 0.0,
              activeColor: _convolverEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _convolverDry = v);
                if (_convolverEnabled) _updateConvolver();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  String _getSurroundModeName(SurroundMode mode) {
    switch (mode) {
      case SurroundMode.off:
        return 'Off';
      case SurroundMode.fieldExpander:
        return 'Field Expander';
      case SurroundMode.differentialHaas:
        return 'Haas Spatializer';
      case SurroundMode.viperHeadphone:
        return 'Headphone Surround+';
      case SurroundMode.matrix51Hrtf:
        return 'Matrix 5.1 HRTF';
    }
  }

  String _getSurroundModeSubtitle() {
    switch (_surroundMode) {
      case SurroundMode.off:
        return 'Enabled';
      case SurroundMode.fieldExpander:
        return 'Field Expander | ${_surroundFieldWidth.toStringAsFixed(1)}x Width';
      case SurroundMode.differentialHaas:
        return 'Haas Spatializer | ${_surroundHaasDelayMs.toStringAsFixed(1)}ms';
      case SurroundMode.viperHeadphone:
        return 'Headphone Surround+ | Room $_surroundRoomPreset';
      case SurroundMode.matrix51Hrtf:
        return 'Matrix 5.1 HRTF | Focus ${(_surroundCenterFocus * 100).toInt()}%';
    }
  }

  String _getSurroundModeDescription(SurroundMode mode) {
    switch (mode) {
      case SurroundMode.off:
        return 'Select a surround algorithm';
      case SurroundMode.fieldExpander:
        return 'M/S soundstage expander with Schroeder diffuser. Keeps bass punch while widening the field. 100% mono compatible.';
      case SurroundMode.differentialHaas:
        return 'Haas precedence-effect spatializer. Cross-injected delayed audio creates vast concert-hall depth.';
      case SurroundMode.viperHeadphone:
        return 'Simulates studio monitors in an acoustically treated room via crossfeed & early reflections. Relieves listening fatigue.';
      case SurroundMode.matrix51Hrtf:
        return 'Pro Logic II dematrixing into 5 virtual speakers rendered through a parametric spherical-head HRTF. Zero latency.';
    }
  }

  Widget _buildSurroundSection() {
    const surroundColor = Color(0xFF7C6BFF);
    return _CollapsibleSection(
      icon: Center(
        child:
            Icon(Icons.surround_sound_rounded, color: surroundColor, size: 20),
      ),
      title: 'Spatial Surround',
      subtitle: _getSurroundModeSubtitle(),
      isEnabled: _surroundEnabled,
      onToggle: (v) {
        setState(() {
          _surroundEnabled = v;
          if (v && _surroundMode == SurroundMode.off) {
            _surroundMode = SurroundMode.fieldExpander;
          }
        });
        _updateSurround();
        _saveEqState();
      },
      children: [
        // Algorithm selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: surfaceDarkerColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SurroundMode>(
              value: _surroundMode == SurroundMode.off
                  ? SurroundMode.fieldExpander
                  : _surroundMode,
              dropdownColor: surfaceDarkerColor,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600),
              items: [
                for (final mode in [
                  SurroundMode.fieldExpander,
                  SurroundMode.differentialHaas,
                  SurroundMode.viperHeadphone,
                  SurroundMode.matrix51Hrtf,
                ])
                  DropdownMenuItem(
                    value: mode,
                    child: Text(_getSurroundModeName(mode)),
                  ),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() {
                  _surroundMode = mode;
                  _surroundEnabled = true;
                });
                _updateSurround();
                _saveEqState();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _getSurroundModeDescription(_surroundMode),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Mode-specific knobs
        if (_surroundMode == SurroundMode.fieldExpander)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'FIELD WIDTH',
                value: (_surroundFieldWidth - 0.5) / 2.0,
                min: 0.0,
                max: 1.0,
                flatValue: (1.4 - 0.5) / 2.0,
                activeColor: _surroundEnabled ? surroundColor : Colors.white,
                displayMultiplier: 2.0,
                valueFormatter: (v) => '${(v * 2.0 + 0.5).toStringAsFixed(1)}x',
                onChanged: (v) {
                  setState(() => _surroundFieldWidth = 0.5 + v * 2.0);
                  if (_surroundEnabled) _updateSurround();
                  _saveEqState();
                },
              ),
              ModernAudioKnob(
                label: 'BASS ANCHOR',
                value: 0.9,
                min: 0.0,
                max: 1.0,
                flatValue: 0.9,
                activeColor: _surroundEnabled ? surroundColor : Colors.white,
                isPercentage: true,
                valueFormatter: (_) => 'Locked',
                onChanged: (_) {},
              ),
            ],
          )
        else if (_surroundMode == SurroundMode.differentialHaas)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'HAAS DELAY',
                value: (_surroundHaasDelayMs - 1.0) / 24.0,
                min: 0.0,
                max: 1.0,
                flatValue: (5.5 - 1.0) / 24.0,
                activeColor: _surroundEnabled ? surroundColor : Colors.white,
                displayMultiplier: 24.0,
                valueFormatter: (v) =>
                    '${(1.0 + v * 24.0).toStringAsFixed(1)}ms',
                onChanged: (v) {
                  setState(() => _surroundHaasDelayMs = 1.0 + v * 24.0);
                  if (_surroundEnabled) _updateSurround();
                  _saveEqState();
                },
              ),
            ],
          )
        else if (_surroundMode == SurroundMode.viperHeadphone)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'ROOM SIZE',
                value: (_surroundRoomPreset - 1) / 4.0,
                min: 0.0,
                max: 1.0,
                flatValue: (2 - 1) / 4.0,
                activeColor: _surroundEnabled ? surroundColor : Colors.white,
                valueFormatter: (_) => 'Level $_surroundRoomPreset',
                onChanged: (v) {
                  setState(() {
                    _surroundRoomPreset = 1 + ((v * 4).round()).clamp(0, 4);
                  });
                  if (_surroundEnabled) _updateSurround();
                  _saveEqState();
                },
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ModernAudioKnob(
                label: 'CENTER FOCUS',
                value: _surroundCenterFocus,
                min: 0.0,
                max: 1.0,
                flatValue: 0.6,
                activeColor: _surroundEnabled ? surroundColor : Colors.white,
                isPercentage: true,
                valueFormatter: (v) => '${(v * 100).toInt()}%',
                onChanged: (v) {
                  setState(() => _surroundCenterFocus = v);
                  if (_surroundEnabled) _updateSurround();
                  _saveEqState();
                },
              ),
            ],
          ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: surroundColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: surroundColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Zero-latency binaural/surround processing | Stereo (headphone) output',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReverbSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.wb_twilight_rounded, color: primaryColor, size: 20),
      ),
      title: 'Reverb',
      subtitle: 'Freeverb room simulation with pre-delay & damping control',
      isEnabled: _reverbEnabled,
      onToggle: (v) {
        setState(() => _reverbEnabled = v);
        _updateReverb();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'MIX',
              value: _reverbMix,
              min: 0.0,
              max: 1.0,
              flatValue: 0.25,
              activeColor: _reverbEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _reverbMix = v);
                if (_reverbEnabled) _updateReverb();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'ROOM SIZE',
              value: _reverbRoomSize,
              min: 0.0,
              max: 1.0,
              flatValue: 0.6,
              activeColor: _reverbEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _reverbRoomSize = v);
                if (_reverbEnabled) _updateReverb();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'DAMPING',
              value: _reverbDamping,
              min: 0.0,
              max: 1.0,
              flatValue: 0.4,
              activeColor: _reverbEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _reverbDamping = v);
                if (_reverbEnabled) _updateReverb();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'PRE-DELAY',
              value: _reverbPreDelayMs,
              min: 0.0,
              max: 250.0,
              flatValue: 20.0,
              activeColor: _reverbEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} ms',
              onChanged: (v) {
                setState(() => _reverbPreDelayMs = v);
                if (_reverbEnabled) _updateReverb();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'WIDTH',
              value: _reverbWidth,
              min: 0.0,
              max: 1.0,
              flatValue: 1.0,
              activeColor: _reverbEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _reverbWidth = v);
                if (_reverbEnabled) _updateReverb();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            'Tip: higher room size & lower damping give long, bright halls; '
            'pre-delay keeps vocals clear of the tail.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterLimiterSection() {
    return _CollapsibleSection(
      icon: Center(
        child: Icon(Icons.shield_rounded, color: primaryColor, size: 20),
      ),
      title: 'Master Peak Limiter',
      subtitle: 'Lookahead true-peak brickwall limiting & loudness booster',
      isEnabled: _masterLimiterEnabled,
      onToggle: (v) {
        setState(() => _masterLimiterEnabled = v);
        _updateMasterLimiter();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'CEILING',
              value: _masterLimiterCeilingDb,
              min: -12.0,
              max: 0.0,
              flatValue: -0.1,
              activeColor: _masterLimiterEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() => _masterLimiterCeilingDb = v);
                if (_masterLimiterEnabled) _updateMasterLimiter();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'GAIN BOOST',
              value: _masterLimiterOutputGainDb,
              min: -6.0,
              max: 12.0,
              flatValue: 0.0,
              activeColor: _masterLimiterEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() => _masterLimiterOutputGainDb = v);
                if (_masterLimiterEnabled) _updateMasterLimiter();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'RELEASE',
              value: _masterLimiterReleaseMs,
              min: 10.0,
              max: 500.0,
              flatValue: 60.0,
              activeColor: _masterLimiterEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} ms',
              onChanged: (v) {
                setState(() => _masterLimiterReleaseMs = v);
                if (_masterLimiterEnabled) _updateMasterLimiter();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _applyLimiter() {
    widget.player.setLimiterEnabled(_limiterEnabled);
    if (_limiterEnabled) {
      widget.player.setLimiterParams(
        threshold: _limiterThreshold,
        attackMs: _limiterAttackMs,
        releaseMs: _limiterReleaseMs,
      );
    }
  }

  Widget _buildLimiterSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.square,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child:*/
          Center(
        child: Icon(Icons.compress_rounded, color: primaryColor, size: 20),
        //),
      ),
      title: 'Soft Limiter',
      subtitle: 'True-peak limiting & anti-clipping dynamics processor',
      isEnabled: _limiterEnabled,
      onToggle: (v) {
        setState(() => _limiterEnabled = v);
        _applyLimiter();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'THRESHOLD',
              value: _limiterThreshold,
              min: 0.1,
              max: 1.0,
              flatValue: 0.95,
              activeColor: _limiterEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: _limiterEnabled
                  ? (v) {
                      setState(() => _limiterThreshold = v);
                      _applyLimiter();
                    }
                  : (_) {},
            ),
            ModernAudioKnob(
              label: 'ATTACK',
              value: _limiterAttackMs,
              min: 0.1,
              max: 100.0,
              flatValue: 2.0,
              activeColor: _limiterEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}ms',
              onChanged: _limiterEnabled
                  ? (v) {
                      setState(() => _limiterAttackMs = v);
                      _applyLimiter();
                    }
                  : (_) {},
            ),
            ModernAudioKnob(
              label: 'RELEASE',
              value: _limiterReleaseMs,
              min: 10.0,
              max: 1000.0,
              flatValue: 50.0,
              activeColor: _limiterEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(0)}ms',
              onChanged: _limiterEnabled
                  ? (v) {
                      setState(() => _limiterReleaseMs = v);
                      _applyLimiter();
                    }
                  : (_) {},
            ),
          ],
        ),
      ],
    );
  }
}

class ModernAudioKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double flatValue;
  final ValueChanged<double> onChanged;
  final String Function(double)? valueFormatter;
  final Color? activeColor;
  final bool isPercentage;
  final double displayMultiplier;
  final double size;

  const ModernAudioKnob({
    super.key,
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 3.0,
    this.flatValue = 1.0,
    required this.onChanged,
    this.valueFormatter,
    this.activeColor,
    this.isPercentage = false,
    this.displayMultiplier = 1.0,
    this.size = 60.0,
  });

  @override
  State<ModernAudioKnob> createState() => _ModernAudioKnobState();
}

class _ModernAudioKnobState extends State<ModernAudioKnob> {
  Color get primaryColor => context.primaryColor;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // dragging up (negative dy) increases value
    double sensitivity = (widget.max - widget.min) / 150.0;
    double newValue = widget.value - (details.delta.dy * sensitivity);
    newValue = newValue.clamp(widget.min, widget.max);
    if ((newValue - widget.value).abs() > 0.001) {
      widget.onChanged(newValue);
    }
  }

  void _showValueDialog(BuildContext context, double dbValue) {
    String initialText = widget.value.toStringAsFixed(2);
    double effectiveMultiplier =
        widget.isPercentage ? 100.0 : widget.displayMultiplier;
    int decimals = widget.isPercentage ? 0 : 1;

    if (widget.isPercentage || widget.displayMultiplier != 1.0) {
      initialText =
          (widget.value * effectiveMultiplier).toStringAsFixed(decimals);
    } else if (widget.valueFormatter == null) {
      initialText = dbValue.toStringAsFixed(2);
    }

    final controller = TextEditingController(text: initialText);

    double displayMin = widget.min;
    double displayMax = widget.max;
    if (widget.isPercentage || widget.displayMultiplier != 1.0) {
      displayMin = widget.min * effectiveMultiplier;
      displayMax = widget.max * effectiveMultiplier;
    } else if (widget.valueFormatter == null) {
      displayMin = -24.0;
      displayMax = 24.0;
    }

    String displayMinStr = displayMin.toStringAsFixed(decimals);
    String displayMaxStr = displayMax.toStringAsFixed(decimals);
    if (widget.valueFormatter == null &&
        !widget.isPercentage &&
        widget.displayMultiplier == 1.0) {
      displayMinStr = displayMin.toStringAsFixed(1);
      displayMaxStr = displayMax.toStringAsFixed(1);
    }

    final accentColor = widget.activeColor ?? primaryColor;

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Adjust ${widget.label}',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Center(
                    child:
                        Icon(Icons.tune_rounded, size: 16, color: accentColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Allowed range: $displayMinStr to $displayMaxStr',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              M3ETextField(
                controller: controller,
                label: 'Target Value',
              ),
            ],
          ),
        ),
        actions: [
          M3EButton(
            onPressed: () {
              widget.onChanged(widget.flatValue);
              Navigator.pop(context);
            },
            child: const Text('Reset Flat'),
          ),
          M3EButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                if (widget.isPercentage || widget.displayMultiplier != 1.0) {
                  widget.onChanged((val / effectiveMultiplier)
                      .clamp(widget.min, widget.max));
                } else if (widget.valueFormatter == null) {
                  double linear = math.pow(10, val / 20).toDouble();
                  widget.onChanged(linear.clamp(widget.min, widget.max));
                } else {
                  widget.onChanged(val.clamp(widget.min, widget.max));
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double normalizedValue =
        (widget.value - widget.min) / (widget.max - widget.min);

    String displayValue;
    double dbValue = 0.0;
    if (widget.valueFormatter != null) {
      displayValue = widget.valueFormatter!(widget.value);
    } else {
      dbValue =
          20 * math.log(widget.value == 0 ? 0.0001 : widget.value) / math.ln10;
      dbValue = dbValue.clamp(-24.0, 24.0);
      displayValue =
          '${dbValue > 0 ? '+' : ''}${dbValue.toStringAsFixed(1)} dB';
    }

    final accentColor = widget.activeColor ?? primaryColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: GestureDetector(
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onDoubleTap: () => widget.onChanged(widget.flatValue),
            onLongPress: () => _showValueDialog(context, dbValue),
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _KnobPainter(
                normalizedValue: normalizedValue,
                activeColor: accentColor,
                inactiveColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showValueDialog(context, dbValue),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.size < 60 ? 5 : 8,
            ),
            child: Center(
              child: Text(
                displayValue,
                style: TextStyle(
                  color: accentColor,
                  fontSize: widget.size < 60 ? 9.5 : 10.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // ),
        ),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double normalizedValue;
  final Color activeColor;
  final Color inactiveColor;

  _KnobPainter({
    required this.normalizedValue,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final trackPaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final startAngle = math.pi * 0.75;
    final sweepAngle = math.pi * 1.5;

    // Draw background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw active arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      startAngle,
      sweepAngle * normalizedValue,
      false,
      activePaint,
    );

    // Draw knob circle
    final basePaint = Paint()
      ..color = const Color(0xFF1E1E2C)
      ..style = PaintingStyle.fill;

    // Darker rim
    final rimPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, radius - 8, basePaint);
    canvas.drawCircle(center, radius - 8, rimPaint);

    // Draw tick
    final tickPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final currentAngle = startAngle + (sweepAngle * normalizedValue);
    final tickRadius = radius - 14;
    final tickX = center.dx + tickRadius * math.cos(currentAngle);
    final tickY = center.dy + tickRadius * math.sin(currentAngle);

    canvas.drawCircle(Offset(tickX, tickY), 3, tickPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue;
  }
}

class _CollapsibleSection extends StatefulWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final bool isEnabled;
  final ValueChanged<bool>? onToggle;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isEnabled = false,
    this.onToggle,
    required this.children,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  Color get primaryColor => context.primaryColor;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isEnabled;
  }

  @override
  void didUpdateWidget(_CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled != oldWidget.isEnabled && widget.isEnabled) {
      _isExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return M3EExpandableList.builder(
      key: ValueKey('${widget.title}_${_isExpanded}_${widget.isEnabled}'),
      itemCount: 1,
      initiallyExpanded: _isExpanded ? const {0} : const <int>{},
      allowMultipleExpanded: true,
      onExpansionChanged: (index, {required isExpanded}) {
        setState(() {
          _isExpanded = isExpanded;
        });
      },
      style: const M3EExpandableStyle(
        outerRadius: 16,
        innerRadius: 16,
        headerPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        bodyPadding: EdgeInsets.fromLTRB(14, 0, 14, 14),
        titleSubtitleGap: 4,
        expandIcon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white54,
          size: 22,
        ),
        collapseIcon: Icon(
          Icons.keyboard_arrow_up_rounded,
          color: Colors.white54,
          size: 22,
        ),
      ),
      headerBuilder: (context, index, progress) {
        return Row(
          children: [
            widget.icon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: widget.isEnabled
                          ? primaryColor.withValues(alpha: 0.9)
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onToggle != null) ...[
              const SizedBox(width: 8),
              M3ESwitch(
                selectedIcon: Icon(Icons.check, color: primaryColor),
                value: widget.isEnabled,
                onChanged: widget.onToggle,
              ),
              const SizedBox(width: 4),
            ],
          ],
        );
      },
      bodyBuilder: (context, index, progress) {
        if (progress <= 0.0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: progress.clamp(0.0, 1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 16),
                ...widget.children,
              ],
            ),
          ),
        );
      },
    );
  }
}
