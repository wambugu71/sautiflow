import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'isolate_player.dart';
import 'services/app_state_service.dart';
import 'widgets/app_showcase.dart';
import 'widgets/custom_filters_graph.dart';
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

  // Spatial Audio
  bool _spatialAudioEnabled = false;
  double _reverbMix = 0.25;
  double _roomSize = 0.3; // Using delay/feedback to simulate
  double _echo = 0.15;

  // Delay (Echo)
  bool _delayEnabled = false;
  double _delayMix = 0.3;
  double _delayFeedback = 0.4;
  double _delayTime = 0.25;

  // Dynamic Bass
  bool _dynamicBassEnabled = false;
  int _dynamicBassPreset = 12;
  double _dynamicBassGain = 15.0;

  // Crystalizer
  bool _crystalizerEnabled = false;
  double _crystalizerIntensity = 0.5;
  bool _crystalizerHighShelf = true;
  double _crystalizerShelfGain = 2.0;

  // Audiophile Crossfeed
  bool _crossfeedEnabled = false;
  int _crossfeedPreset = 1;
  int _crossfeedAlgorithmIndex =
      2; // 1=Simple, 2=BS2B, 3=Meier, 4=Natural, 5=RACE
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

  // DSP Stereo Enhancement
  bool _stereoEnhancementEnabled = false;
  double _stereoEnhancementMix = 0.5;

  // Audio Tuning (3-band EQ)
  bool _audioTuningEnabled = false;
  double _tuneLow = 0.0;
  double _tuneMid = 0.0;
  double _tuneHigh = 0.0;

  // Preamp
  double _preampDb = 0.0; // Simulated gain offset

  // True 3D Spatialization
  bool _true3dEnabled = false;
  double _spatX = 0.0;
  double _spatY = 0.0;
  double _spatZ = 0.0;
  int _spatAttenuationModel = 1;
  double _spatRolloff = 1.0;
  double _spatMinDistance = 1.0;
  double _spatMaxDistance = 100.0;
  double _spatDopplerFactor = 1.0;
  double _soundConeInnerRad = 3.14;
  double _soundConeOuterRad = 6.28;
  double _soundConeOuterGain = 0.5;
  double _listenerX = 0.0;
  double _listenerY = 0.0;
  double _listenerZ = 0.0;
  final double _listenerDirZ = 1.0;

  // Custom Filters & Standalone Miniaudio Bindings
  bool _customLpfEnabled = false;
  double _customLpfCutoff = 500.0;

  bool _customHpfEnabled = false;
  double _customHpfCutoff = 120.0;

  bool _customBpfEnabled = false;
  double _customBpfCutoff = 1000.0;
  double _customBpfQ = 0.707;

  bool _customNotchEnabled = false;
  double _customNotchCutoff = 60.0;
  double _customNotchQ = 10.0;

  bool _customPeakEnabled = false;
  double _customPeakCutoff = 1000.0;
  double _customPeakGainDb = 0.0;
  double _customPeakQ = 1.0;

  bool _customLoshelfEnabled = false;
  double _customLoshelfCutoff = 250.0;
  double _customLoshelfGainDb = 0.0;
  double _customLoshelfSlope = 1.0;

  bool _customHishelfEnabled = false;
  double _customHishelfCutoff = 8000.0;
  double _customHishelfGainDb = 0.0;
  double _customHishelfSlope = 1.0;

  bool _customBiquadEnabled = false;
  double _biquadB0 = 1.0;
  double _biquadB1 = 0.0;
  double _biquadB2 = 0.0;
  double _biquadA0 = 1.0;
  double _biquadA1 = 0.0;
  double _biquadA2 = 0.0;
  // Subscriptions
  StreamSubscription<void>? _eqSettingsSub;

  // Soft Limiter
  bool _limiterEnabled = false;
  double _limiterThreshold = 0.95; // 0.1 – 1.0
  double _limiterAttackMs = 2.0; // 0.1 – 100 ms
  double _limiterReleaseMs = 50.0; // 10 – 1000 ms

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
    final spatial = await AppStateService.instance.loadSpatialAudio();
    final delay = await AppStateService.instance.loadDelay();
    final dynamicBass = await AppStateService.instance.loadDynamicBass();
    final crystalizer = await AppStateService.instance.loadCrystalizer();
    final stereoWiden = await AppStateService.instance.loadStereoWiden();
    final stereoEnhancement =
        await AppStateService.instance.loadStereoEnhancement();
    final crossfeed = await AppStateService.instance.loadCrossfeed();
    final raceParams = await AppStateService.instance.loadRaceParams();
    final tuning = await AppStateService.instance.loadAudioTuning();
    final true3d = await AppStateService.instance.loadTrue3d();
    final lpf = await AppStateService.instance.loadCustomLpf();
    final hpf = await AppStateService.instance.loadCustomHpf();
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

      // Spatial
      _spatialAudioEnabled = spatial.enabled;
      _reverbMix = spatial.reverbMix;
      _roomSize = spatial.roomSize;
      _echo = spatial.echo;

      // Delay
      _delayEnabled = delay.enabled;
      _delayMix = delay.mix;
      _delayFeedback = delay.feedback;
      _delayTime = delay.time;

      // Dynamic Bass
      _dynamicBassEnabled = dynamicBass.enabled;
      _dynamicBassPreset = dynamicBass.preset;
      _dynamicBassGain = dynamicBass.gain;

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

      // DSP Stereo Enhancement
      _stereoEnhancementEnabled = stereoEnhancement.enabled;
      _stereoEnhancementMix = stereoEnhancement.mix;

      // Audio Tuning
      _audioTuningEnabled = tuning.enabled;
      _tuneLow = tuning.low;
      _tuneMid = tuning.mid;
      _tuneHigh = tuning.high;

      // True 3D
      _true3dEnabled = true3d.enabled;
      _spatX = true3d.x;
      _spatY = true3d.y;
      _spatZ = true3d.z;

      // Custom filters
      _customLpfEnabled = lpf.enabled;
      _customLpfCutoff = lpf.cutoff;
      _customHpfEnabled = hpf.enabled;
      _customHpfCutoff = hpf.cutoff;

      // Limiter
      _limiterEnabled = limiter.enabled;
      _limiterThreshold = limiter.threshold;
      _limiterAttackMs = limiter.attackMs;
      _limiterReleaseMs = limiter.releaseMs;
    });

    // Apply loaded state to the audio engine
    widget.player.setMultibandEqEnabled(_masterEqEnabled);
    widget.player.initMultibandEq(_eqFrequencies);
    _applyEqGains();
    _applyStoredPreamp();

    if (_spatialAudioEnabled) {
      widget.player.setReverbEnabled(true);
      _updateSpatialAudio();
    }
    if (_delayEnabled) {
      widget.player.setDelay(enabled: true);
      _updateDelay();
    }
    if (_dynamicBassEnabled) {
      _updateDynamicBass();
    }
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
    if (_audioTuningEnabled) {
      widget.player.setEqEnabled(true);
      widget.player.setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
    }
    if (_true3dEnabled) {
      widget.player.setSpatializationEnabled(true);
      _updateTrue3dPositions();
    }
    if (_customLpfEnabled) {
      widget.player.setCustomLpf1(enabled: true, cutoffHz: _customLpfCutoff);
    }
    if (_customHpfEnabled) {
      widget.player.setCustomHpf1(enabled: true, cutoffHz: _customHpfCutoff);
    }
    if (_limiterEnabled) {
      _applyLimiter();
    }
  }

  void _updateStereoEnhancement() {
    widget.player.setStereoEnhancement(
      enabled: _stereoEnhancementEnabled,
      mix: _stereoEnhancementMix,
    );
  }

  /// Applies the loaded preamp value to the audio engine.
  void _applyStoredPreamp() {
    final gain = math.pow(10, _preampDb / 20).toDouble();
    widget.player.setGain(gain);
  }

  /// Saves all current EQ state to persistent storage.
  void _saveEqState() {
    AppStateService.instance.saveEqBands(
      enabled: _masterEqEnabled,
      preset: _activePreset,
      gains: List<double>.from(_eqGains),
      preampDb: _preampDb,
      bandCount: _eqFrequencies.length,
    );
    AppStateService.instance.saveSpatialAudio(
      enabled: _spatialAudioEnabled,
      reverbMix: _reverbMix,
      roomSize: _roomSize,
      echo: _echo,
    );
    AppStateService.instance.saveDelay(
      enabled: _delayEnabled,
      mix: _delayMix,
      feedback: _delayFeedback,
      time: _delayTime,
    );
    AppStateService.instance.saveDynamicBass(
      enabled: _dynamicBassEnabled,
      preset: _dynamicBassPreset,
      gain: _dynamicBassGain,
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
    AppStateService.instance.saveAudioTuning(
      enabled: _audioTuningEnabled,
      low: _tuneLow,
      mid: _tuneMid,
      high: _tuneHigh,
    );
    AppStateService.instance.saveTrue3d(
      enabled: _true3dEnabled,
      x: _spatX,
      y: _spatY,
      z: _spatZ,
    );
    AppStateService.instance.saveCustomLpf(
      enabled: _customLpfEnabled,
      cutoff: _customLpfCutoff,
    );
    AppStateService.instance.saveCustomHpf(
      enabled: _customHpfEnabled,
      cutoff: _customHpfCutoff,
    );
    AppStateService.instance.saveLimiter(
      enabled: _limiterEnabled,
      threshold: _limiterThreshold,
      attackMs: _limiterAttackMs,
      releaseMs: _limiterReleaseMs,
    );
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

      _spatialAudioEnabled = false;
      widget.player.setReverbEnabled(false);

      _delayEnabled = false;
      widget.player.setDelay(enabled: false);

      _dynamicBassEnabled = false;
      _dynamicBassPreset = 12;
      _dynamicBassGain = 15.0;
      widget.player.setDynamicBass(
        enabled: false,
        preset: _dynamicBassPreset,
        gain: _dynamicBassGain,
      );

      _crystalizerEnabled = false;
      _crystalizerIntensity = 0.5;
      _crystalizerHighShelf = true;
      _crystalizerShelfGain = 2.0;
      widget.player.setCrystalizer(enabled: false);

      _stereoEnhancementEnabled = false;
      _stereoEnhancementMix = 0.5;
      widget.player.setStereoEnhancement(enabled: false, mix: 0.5);

      _audioTuningEnabled = false;
      widget.player.setEqEnabled(false);
      _tuneLow = 0.0;
      _tuneMid = 0.0;
      _tuneHigh = 0.0;
      widget.player.setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);

      _preampDb = 0.0;
      widget.player.setGain(1.0); // 1.0 is 0dB
      widget.player.setPitch(1.0);

      _true3dEnabled = false;
      widget.player.setSpatializationEnabled(false);
      _spatX = 0.0;
      _spatY = 0.0;
      _spatZ = 0.0;

      _parametricEqEnabled = false;
      _parametricBands.clear();
      widget.player.setMultibandFxEnabled(false);
      widget.player.clearMultibandFx();

      _customLpfEnabled = false;
      _customLpfCutoff = 500.0;
      widget.player.setCustomLpf1(enabled: false, cutoffHz: _customLpfCutoff);

      _customHpfEnabled = false;
      _customHpfCutoff = 120.0;
      widget.player.setCustomHpf1(enabled: false, cutoffHz: _customHpfCutoff);

      _customBpfEnabled = false;
      _customBpfCutoff = 1000.0;
      _customBpfQ = 0.707;
      widget.player.setBandpass(
          enabled: false, cutoffHz: _customBpfCutoff, q: _customBpfQ);

      _customNotchEnabled = false;
      _customNotchCutoff = 60.0;
      _customNotchQ = 10.0;
      widget.player.setNotch(
          enabled: false, frequencyHz: _customNotchCutoff, q: _customNotchQ);

      _customPeakEnabled = false;
      _customPeakCutoff = 1000.0;
      _customPeakGainDb = 0.0;
      _customPeakQ = 1.0;
      widget.player.setPeakEq(
          enabled: false,
          frequencyHz: _customPeakCutoff,
          gainDb: _customPeakGainDb,
          q: _customPeakQ);

      _customLoshelfEnabled = false;
      _customLoshelfCutoff = 250.0;
      _customLoshelfGainDb = 0.0;
      _customLoshelfSlope = 1.0;
      widget.player.setLowshelf(
          enabled: false,
          frequencyHz: _customLoshelfCutoff,
          gainDb: _customLoshelfGainDb,
          slope: _customLoshelfSlope);

      _customHishelfEnabled = false;
      _customHishelfCutoff = 8000.0;
      _customHishelfGainDb = 0.0;
      _customHishelfSlope = 1.0;
      widget.player.setHighshelf(
          enabled: false,
          frequencyHz: _customHishelfCutoff,
          gainDb: _customHishelfGainDb,
          slope: _customHishelfSlope);

      _customBiquadEnabled = false;
      widget.player.setCustomBiquad(
        enabled: false,
        b0: _biquadB0,
        b1: _biquadB1,
        b2: _biquadB2,
        a0: _biquadA0,
        a1: _biquadA1,
        a2: _biquadA2,
      );

      _limiterEnabled = false;
      _limiterThreshold = 0.95;
      _limiterAttackMs = 2.0;
      _limiterReleaseMs = 50.0;
      widget.player.setLimiterEnabled(false);
      widget.player.setClippingDetectionEnabled(false);
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
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
                        showcaseKey:
                            widget.effectsKnobKey ?? GlobalKey(),
                        title: 'Knob Controls',
                        description:
                            'Drag knobs to adjust EQ. Tip: Long-press any knob to edit values directly with your keyboard!',
                        currentStep: 3,
                        totalSteps: 4,
                        child: _buildEffectTileCard(
                          icon: Icons.equalizer_rounded,
                          shape: Shapes.c4SidedCookie,
                          title:
                              '${_eqFrequencies.length}-Band Graphic EQ',
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
                        isEnabled:
                            (_playbackPitch - 1.0).abs() >= 0.01,
                        onToggle: (v) {
                          final newPitch = v ? 1.25 : 1.0;
                          setState(() => _playbackPitch = newPitch);
                          widget.player.setPitch(newPitch);
                          AppStateService.instance
                              .savePlaybackSpeed(newPitch);
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

            // Section 2: Dynamics & Bass
            SliverToBoxAdapter(
              child: _buildSectionHeader('Dynamics & Bass',
                  icon: Icons.waves_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 3,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Dynamic Bass',
                          Icons.waves_rounded,
                          (_) => _buildDynamicBassSection(),
                          shape: Shapes.boom,
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
                      case 2:
                        _openDetailScreen(
                          'Soft Limiter',
                          Icons.compress_rounded,
                          (_) => _buildLimiterSection(),
                          shape: Shapes.square,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.waves_rounded,
                        shape: Shapes.boom,
                        title: 'Dynamic Bass',
                        subtitle: _dynamicBassEnabled
                            ? 'Gain: ${_dynamicBassGain.toInt()}%'
                            : 'Disabled',
                        isEnabled: _dynamicBassEnabled,
                        onToggle: (v) {
                          setState(() => _dynamicBassEnabled = v);
                          if (v) {
                            _updateDynamicBass();
                          } else {
                            widget.player.setDynamicBass(
                                enabled: false,
                                preset: _dynamicBassPreset,
                                gain: _dynamicBassGain);
                          }
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Dynamic Bass',
                          Icons.waves_rounded,
                          (_) => _buildDynamicBassSection(),
                          shape: Shapes.boom,
                        ),
                      );
                    }
                    if (index == 1) {
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
                    }
                    return _buildEffectTileCard(
                      icon: Icons.compress_rounded,
                      shape: Shapes.square,
                      title: 'Soft Limiter',
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
                        'Soft Limiter',
                        Icons.compress_rounded,
                        (_) => _buildLimiterSection(),
                        shape: Shapes.square,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 3: Spatial & Headphones
            SliverToBoxAdapter(
              child: _buildSectionHeader('Spatial & Headphones',
                  icon: Icons.headphones_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 5,
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
                          'Stereo Enhancement',
                          Icons.surround_sound_rounded,
                          (_) => _buildStereoEnhancementSection(),
                          shape: Shapes.puffyDiamond,
                        );
                        break;
                      case 3:
                        _openDetailScreen(
                          '3D Audio',
                          Icons.spatial_audio_off_outlined,
                          (_) => _buildSpatialAudioSection(),
                          shape: Shapes.softBoom,
                        );
                        break;
                      case 4:
                        _openDetailScreen(
                          'True 3D Spatial Audio',
                          Icons.threed_rotation_rounded,
                          (_) => _buildTrue3dSection(),
                          shape: Shapes.circle,
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
                            ? (_crossfeedPreset == 1
                                ? 'BS2B Weak'
                                : _crossfeedPreset == 2
                                    ? 'BS2B Strong'
                                    : _crossfeedPreset == 3
                                        ? 'Joe0bloggs'
                                        : 'Ambiophonics')
                            : 'Disabled',
                        isEnabled: _crossfeedEnabled,
                        onToggle: (v) {
                          setState(() => _crossfeedEnabled = v);
                          if (v) {
                            _updateCrossfeed();
                          } else {
                            widget.player.setCrossfeed(
                                enabled: false,
                                preset: _crossfeedPreset);
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
                        title: 'Stereo Enhancement',
                        subtitle: _stereoEnhancementEnabled
                            ? 'Mix: ${(_stereoEnhancementMix * 100).toInt()}%'
                            : 'Disabled',
                        isEnabled: _stereoEnhancementEnabled,
                        onToggle: (v) {
                          setState(
                              () => _stereoEnhancementEnabled = v);
                          _updateStereoEnhancement();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Stereo Enhancement',
                          Icons.surround_sound_rounded,
                          (_) => _buildStereoEnhancementSection(),
                          shape: Shapes.puffyDiamond,
                        ),
                      );
                    }
                    if (index == 3) {
                      return _buildEffectTileCard(
                        icon: Icons.spatial_audio_off_outlined,
                        shape: Shapes.softBoom,
                        title: '3D Audio',
                        subtitle: _spatialAudioEnabled
                            ? 'Reverb: ${(_reverbMix * 100).toInt()}% | Room: ${(_roomSize * 100).toInt()}%'
                            : 'Disabled',
                        isEnabled: _spatialAudioEnabled,
                        onToggle: (v) {
                          setState(() => _spatialAudioEnabled = v);
                          widget.player.setReverbEnabled(v);
                          if (v) _updateSpatialAudio();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          '3D Audio',
                          Icons.spatial_audio_off_outlined,
                          (_) => _buildSpatialAudioSection(),
                          shape: Shapes.softBoom,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.threed_rotation_rounded,
                      shape: Shapes.circle,
                      title: 'True 3D Spatial Audio',
                      subtitle: _true3dEnabled
                          ? 'XYZ Vector Coordinates Active'
                          : 'Disabled',
                      isEnabled: _true3dEnabled,
                      onToggle: (v) {
                        setState(() => _true3dEnabled = v);
                        widget.player.setSpatializationEnabled(v);
                        if (v) _updateTrue3dPositions();
                        _saveEqState();
                      },
                      onTapDetail: () => _openDetailScreen(
                        'True 3D Spatial Audio',
                        Icons.threed_rotation_rounded,
                        (_) => _buildTrue3dSection(),
                        shape: Shapes.circle,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Section 4: Advanced Audio Filters
            SliverToBoxAdapter(
              child: _buildSectionHeader('Advanced Audio Filters',
                  icon: Icons.filter_alt_rounded),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                          'Delay / Echo',
                          Icons.repeat_rounded,
                          (_) => _buildDelaySection(),
                          shape: Shapes.l4LeafClover,
                        );
                        break;
                      case 1:
                        _openDetailScreen(
                          'Advanced Filters',
                          Icons.filter_alt_outlined,
                          (_) => _buildCustomFiltersSection(),
                          shape: Shapes.diamond,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        icon: Icons.repeat_rounded,
                        shape: Shapes.l4LeafClover,
                        title: 'Delay / Echo',
                        subtitle: _delayEnabled
                            ? 'Time: ${(_delayTime * 1000).toInt()}ms | Mix: ${(_delayMix * 100).toInt()}%'
                            : 'Disabled',
                        isEnabled: _delayEnabled,
                        onToggle: (v) {
                          setState(() => _delayEnabled = v);
                          widget.player.setDelay(enabled: v);
                          if (v) _updateDelay();
                          _saveEqState();
                        },
                        onTapDetail: () => _openDetailScreen(
                          'Delay / Echo',
                          Icons.repeat_rounded,
                          (_) => _buildDelaySection(),
                          shape: Shapes.l4LeafClover,
                        ),
                      );
                    }
                    return _buildEffectTileCard(
                      icon: Icons.filter_alt_outlined,
                      shape: Shapes.diamond,
                      title: 'Advanced Filters',
                      subtitle: (_customLpfEnabled ||
                              _customHpfEnabled ||
                              _customBpfEnabled ||
                              _customNotchEnabled ||
                              _customPeakEnabled ||
                              _customLoshelfEnabled ||
                              _customHishelfEnabled ||
                              _customBiquadEnabled)
                          ? 'Active Filters Configured'
                          : 'Disabled',
                      isEnabled: _customLpfEnabled ||
                          _customHpfEnabled ||
                          _customBpfEnabled ||
                          _customNotchEnabled ||
                          _customPeakEnabled ||
                          _customLoshelfEnabled ||
                          _customHishelfEnabled ||
                          _customBiquadEnabled,
                      onTapDetail: () => _openDetailScreen(
                        'Advanced Filters',
                        Icons.filter_alt_outlined,
                        (_) => _buildCustomFiltersSection(),
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
                      _saveEqState();
                    },
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
                                    _saveEqState();
                                  }
                                : null,
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

  Widget _buildSpatialAudioSection() {
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.softBoom,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child:*/
          Center(
        child: Icon(Icons.spatial_audio_off_outlined,
            color: primaryColor, size: 20),
        //),
      ),
      title: '3D Spatial Audio',
      subtitle: 'Immersive virtual soundstage & reverb',
      isEnabled: _spatialAudioEnabled,
      onToggle: (v) {
        setState(() => _spatialAudioEnabled = v);
        widget.player.setReverbEnabled(v);
        if (v) _updateSpatialAudio();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'SIZE',
              value: _roomSize,
              min: 0.0,
              max: 1.0,
              flatValue: 0.3,
              activeColor: _spatialAudioEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _roomSize = v);
                if (_spatialAudioEnabled) _updateSpatialAudio();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'ECHO',
              value: _echo,
              min: 0.0,
              max: 1.0,
              flatValue: 0.15,
              activeColor: _spatialAudioEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _echo = v);
                if (_spatialAudioEnabled) _updateSpatialAudio();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'REVERB',
              value: _reverbMix,
              min: 0.0,
              max: 1.0,
              flatValue: 0.25,
              activeColor: _spatialAudioEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _reverbMix = v);
                if (_spatialAudioEnabled) _updateSpatialAudio();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDynamicBassSection() {
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.boom,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.waves_rounded, color: primaryColor, size: 20),
        // ),
      ),
      title: 'Dynamic Bass',
      subtitle: 'Harmonic bass boost & sub-frequency enhancement',
      isEnabled: _dynamicBassEnabled,
      onToggle: (v) {
        setState(() => _dynamicBassEnabled = v);
        if (v) {
          _updateDynamicBass();
        } else {
          widget.player.setDynamicBass(
              enabled: false,
              preset: _dynamicBassPreset,
              gain: _dynamicBassGain);
        }
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'GAIN',
              value: _dynamicBassGain / 100.0,
              min: 0.0,
              max: 1.0,
              flatValue: 1.0,
              activeColor: _dynamicBassEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _dynamicBassGain = v * 100.0);
                if (_dynamicBassEnabled) _updateDynamicBass();
              },
            ),
            Column(
              children: [
                Text(
                  'PRESET FREQ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                /*M3EContainer(
                  Shapes.pill,
                  color: surfaceDarkColor,
                  border:
                      BorderSide(color: primaryColor.withValues(alpha: 0.35)),
                  child: */
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _dynamicBassPreset,
                      dropdownColor: surfaceDarkerColor,
                      icon: Icon(Icons.arrow_drop_down_rounded,
                          color: primaryColor),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      items: List.generate(19, (index) {
                        int f = 60 + (index * 5);
                        if (index > 14) f = 130 + ((index - 14) * 10);
                        if (index == 18) f = 180;
                        return DropdownMenuItem(
                            value: index, child: Text('$f Hz'));
                      }),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _dynamicBassPreset = val);
                          if (_dynamicBassEnabled) _updateDynamicBass();
                          _saveEqState();
                        }
                      },
                      //  ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
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
                      setState(() => _crossfeedAlgorithmIndex = val);
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
      title: 'Stereo Enhancement',
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

  Widget _buildDelaySection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.l4LeafClover,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.repeat_rounded, color: primaryColor, size: 20),
        // ),
      ),
      title: 'Delay / Echo',
      subtitle: 'Feedback, time delay & rhythmic repeats',
      isEnabled: _delayEnabled,
      onToggle: (v) {
        setState(() => _delayEnabled = v);
        widget.player.setDelay(enabled: v);
        if (v) _updateDelay();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'TIME',
              value: _delayTime,
              min: 0.0,
              max: 1.0,
              flatValue: 0.25,
              activeColor: _delayEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _delayTime = v);
                if (_delayEnabled) _updateDelay();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'FEEDBACK',
              value: _delayFeedback,
              min: 0.0,
              max: 1.0,
              flatValue: 0.4,
              activeColor: _delayEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _delayFeedback = v);
                if (_delayEnabled) _updateDelay();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'MIX',
              value: _delayMix,
              min: 0.0,
              max: 1.0,
              flatValue: 0.3,
              activeColor: _delayEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _delayMix = v);
                if (_delayEnabled) _updateDelay();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _updateDelay() {
    // delayTime: 0.0 -> 1.0 mapped to 10ms -> 1000ms
    double delayMs = 10.0 + (_delayTime * 990.0);
    widget.player.setDelay(
      enabled: _delayEnabled,
      mix: _delayMix,
      feedback: _delayFeedback,
      delayMs: delayMs,
    );
  }

  void _updateDynamicBass() {
    widget.player.setDynamicBass(
      enabled: _dynamicBassEnabled,
      preset: _dynamicBassPreset,
      gain: _dynamicBassGain,
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

  void _updateSpatialAudio() {
    double delayMs = 20.0 + (_roomSize * 330.0);
    double feedback = _echo * 0.98;

    widget.player
        .setReverb(mix: _reverbMix, feedback: feedback, delayMs: delayMs);
  }

  Widget _buildSectionSubHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: primaryColor.withValues(alpha: 0.9),
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildTrue3dSection() {
    return _CollapsibleSection(
      icon: /* M3EContainer(
        Shapes.circle,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child:
            Icon(Icons.threed_rotation_rounded, color: primaryColor, size: 20),
        //  ),
      ),
      title: 'True 3D Spatial Audio',
      subtitle: '3D Positioning, Sound Cones & Distance Attenuation',
      isEnabled: _true3dEnabled,
      onToggle: (v) {
        setState(() => _true3dEnabled = v);
        widget.player.setSpatializationEnabled(v);
        if (v) _updateTrue3dPositions();
        _saveEqState();
      },
      children: [
        _buildSectionSubHeader('Sound Source Position'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'SRC X',
              value: _spatX,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _spatX = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'SRC Y',
              value: _spatY,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _spatY = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'SRC Z',
              value: _spatZ,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _spatZ = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionSubHeader('Distance Attenuation & Doppler'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Attenuation Model',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            /*M3EContainer(
              Shapes.pill,
              color: surfaceDarkColor,
              border: BorderSide(color: primaryColor.withValues(alpha: 0.35)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child:*/
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _spatAttenuationModel,
                dropdownColor: surfaceDarkerColor,
                icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('None')),
                  DropdownMenuItem(value: 1, child: Text('Inverse')),
                  DropdownMenuItem(value: 2, child: Text('Linear')),
                  DropdownMenuItem(value: 3, child: Text('Exponential')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _spatAttenuationModel = val);
                    if (_true3dEnabled) _updateTrue3dPositions();
                    _saveEqState();
                  }
                },
              ),
            ),
            // ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'ROLLOFF',
              value: _spatRolloff,
              min: 0.0,
              max: 5.0,
              flatValue: 1.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}x',
              onChanged: (v) {
                setState(() => _spatRolloff = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'MIN DIST',
              value: _spatMinDistance,
              min: 0.1,
              max: 20.0,
              flatValue: 1.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}m',
              onChanged: (v) {
                setState(() => _spatMinDistance = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'MAX DIST',
              value: _spatMaxDistance,
              min: 1.0,
              max: 500.0,
              flatValue: 100.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()}m',
              onChanged: (v) {
                setState(() => _spatMaxDistance = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'DOPPLER',
              value: _spatDopplerFactor,
              min: 0.0,
              max: 5.0,
              flatValue: 1.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}x',
              onChanged: (v) {
                setState(() => _spatDopplerFactor = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionSubHeader('Sound Cone & Directivity'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'INNER CONE',
              value: _soundConeInnerRad,
              min: 0.0,
              max: 6.28,
              flatValue: 3.14,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${(v * 180 / 3.14159).round()}°',
              onChanged: (v) {
                setState(() => _soundConeInnerRad = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'OUTER CONE',
              value: _soundConeOuterRad,
              min: 0.0,
              max: 6.28,
              flatValue: 6.28,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${(v * 180 / 3.14159).round()}°',
              onChanged: (v) {
                setState(() => _soundConeOuterRad = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'OUTER GAIN',
              value: _soundConeOuterGain,
              min: 0.0,
              max: 1.0,
              flatValue: 0.5,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              isPercentage: true,
              valueFormatter: (v) => '${(v * 100).toInt()}%',
              onChanged: (v) {
                setState(() => _soundConeOuterGain = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionSubHeader('Listener Position & Orientation'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'LISTENER X',
              value: _listenerX,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _listenerX = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'LISTENER Y',
              value: _listenerY,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _listenerY = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
            ModernAudioKnob(
              label: 'LISTENER Z',
              value: _listenerZ,
              min: -5.0,
              max: 5.0,
              flatValue: 0.0,
              activeColor: _true3dEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _listenerZ = v);
                if (_true3dEnabled) _updateTrue3dPositions();
                _saveEqState();
              },
            ),
          ],
        ),
      ],
    );
  }

  void _updateTrue3dPositions() {
    widget.player.setSpatializationEnabled(_true3dEnabled);
    widget.player.setPosition(x: _spatX, y: _spatY, z: _spatZ);
    widget.player.setAttenuationModel(_spatAttenuationModel);
    widget.player.setRolloff(_spatRolloff);
    widget.player.setMinDistance(_spatMinDistance);
    widget.player.setMaxDistance(_spatMaxDistance);
    widget.player.setDopplerFactor(_spatDopplerFactor);
    widget.player.setSoundCone(
      innerAngleRad: _soundConeInnerRad,
      outerAngleRad: _soundConeOuterRad,
      outerGain: _soundConeOuterGain,
    );
    widget.player
        .setListenerPosition(x: _listenerX, y: _listenerY, z: _listenerZ);
    widget.player.setListenerDirection(x: 0.0, y: 0.0, z: _listenerDirZ);
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

  Widget _buildCustomFiltersSection() {
    return _CollapsibleSection(
      icon: /*M3EContainer(
        Shapes.diamond,
        width: 40,
        height: 40,
        color: primaryColor.withValues(alpha: 0.18),
        border: BorderSide(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        child: */
          Center(
        child: Icon(Icons.filter_alt_rounded, color: primaryColor, size: 20),
        // ),
      ),
      title: 'Advanced Audio Filters',
      subtitle: 'Real-Time LPF, HPF, BPF, Notch, Peak, Low/High Shelf & Biquad',
      hasSwitch: false,
      children: [
        // Real-Time Combined Frequency Response Graph
        RepaintBoundary(
          child: CustomFiltersGraph(
            config: CustomFilterGraphConfig(
              lpfEnabled: _customLpfEnabled,
              lpfCutoff: _customLpfCutoff,
              hpfEnabled: _customHpfEnabled,
              hpfCutoff: _customHpfCutoff,
              bpfEnabled: _customBpfEnabled,
              bpfCutoff: _customBpfCutoff,
              bpfQ: _customBpfQ,
              notchEnabled: _customNotchEnabled,
              notchCutoff: _customNotchCutoff,
              notchQ: _customNotchQ,
              peakEnabled: _customPeakEnabled,
              peakCutoff: _customPeakCutoff,
              peakGainDb: _customPeakGainDb,
              peakQ: _customPeakQ,
              loshelfEnabled: _customLoshelfEnabled,
              loshelfCutoff: _customLoshelfCutoff,
              loshelfGainDb: _customLoshelfGainDb,
              loshelfSlope: _customLoshelfSlope,
              hishelfEnabled: _customHishelfEnabled,
              hishelfCutoff: _customHishelfCutoff,
              hishelfGainDb: _customHishelfGainDb,
              hishelfSlope: _customHishelfSlope,
              biquadEnabled: _customBiquadEnabled,
              biquadB0: _biquadB0,
              biquadB1: _biquadB1,
              biquadB2: _biquadB2,
              biquadA0: _biquadA0,
              biquadA1: _biquadA1,
              biquadA2: _biquadA2,
            ),
            primaryColor: primaryColor,
            height: 125.0,
          ),
        ),
        const SizedBox(height: 16),

        // LPF Section
        _buildFilterRow(
          title: 'Low-Pass Filter (LPF)',
          isEnabled: _customLpfEnabled,
          onToggle: (v) {
            setState(() {
              _customLpfEnabled = v;
              widget.player
                  .setCustomLpf1(enabled: v, cutoffHz: _customLpfCutoff);
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'CUTOFF',
              value: _customLpfCutoff,
              min: 20.0,
              max: 20000.0,
              flatValue: 500.0,
              activeColor: _customLpfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customLpfCutoff = v;
                  if (_customLpfEnabled) {
                    widget.player.setCustomLpf1(enabled: true, cutoffHz: v);
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // HPF Section
        _buildFilterRow(
          title: 'High-Pass Filter (HPF)',
          isEnabled: _customHpfEnabled,
          onToggle: (v) {
            setState(() {
              _customHpfEnabled = v;
              widget.player
                  .setCustomHpf1(enabled: v, cutoffHz: _customHpfCutoff);
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'CUTOFF',
              value: _customHpfCutoff,
              min: 20.0,
              max: 20000.0,
              flatValue: 120.0,
              activeColor: _customHpfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customHpfCutoff = v;
                  if (_customHpfEnabled) {
                    widget.player.setCustomHpf1(enabled: true, cutoffHz: v);
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Band-Pass Filter (BPF) Section
        _buildFilterRow(
          title: 'Band-Pass Filter (BPF)',
          isEnabled: _customBpfEnabled,
          onToggle: (v) {
            setState(() {
              _customBpfEnabled = v;
              _updateBpf();
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'CUTOFF',
              value: _customBpfCutoff,
              min: 20.0,
              max: 20000.0,
              flatValue: 1000.0,
              activeColor: _customBpfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customBpfCutoff = v;
                  _updateBpf();
                });
              },
            ),
            ModernAudioKnob(
              label: 'Q',
              value: _customBpfQ,
              min: 0.1,
              max: 10.0,
              flatValue: 0.707,
              activeColor: _customBpfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(2),
              onChanged: (v) {
                setState(() {
                  _customBpfQ = v;
                  _updateBpf();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Notch Filter Section
        _buildFilterRow(
          title: 'Notch Filter',
          isEnabled: _customNotchEnabled,
          onToggle: (v) {
            setState(() {
              _customNotchEnabled = v;
              _updateNotch();
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'FREQ',
              value: _customNotchCutoff,
              min: 20.0,
              max: 20000.0,
              flatValue: 60.0,
              activeColor: _customNotchEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customNotchCutoff = v;
                  _updateNotch();
                });
              },
            ),
            ModernAudioKnob(
              label: 'Q',
              value: _customNotchQ,
              min: 0.5,
              max: 30.0,
              flatValue: 10.0,
              activeColor: _customNotchEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(1),
              onChanged: (v) {
                setState(() {
                  _customNotchQ = v;
                  _updateNotch();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Peaking EQ Filter Section
        _buildFilterRow(
          title: 'Peaking EQ Filter',
          isEnabled: _customPeakEnabled,
          onToggle: (v) {
            setState(() {
              _customPeakEnabled = v;
              _updatePeak();
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'FREQ',
              value: _customPeakCutoff,
              min: 20.0,
              max: 20000.0,
              flatValue: 1000.0,
              activeColor: _customPeakEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customPeakCutoff = v;
                  _updatePeak();
                });
              },
            ),
            ModernAudioKnob(
              label: 'GAIN',
              value: _customPeakGainDb,
              min: -24.0,
              max: 24.0,
              flatValue: 0.0,
              activeColor: _customPeakEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() {
                  _customPeakGainDb = v;
                  _updatePeak();
                });
              },
            ),
            ModernAudioKnob(
              label: 'Q',
              value: _customPeakQ,
              min: 0.1,
              max: 10.0,
              flatValue: 1.0,
              activeColor: _customPeakEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(2),
              onChanged: (v) {
                setState(() {
                  _customPeakQ = v;
                  _updatePeak();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Low Shelf Filter Section
        _buildFilterRow(
          title: 'Low Shelf Filter',
          isEnabled: _customLoshelfEnabled,
          onToggle: (v) {
            setState(() {
              _customLoshelfEnabled = v;
              _updateLoshelf();
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'CUTOFF',
              value: _customLoshelfCutoff,
              min: 20.0,
              max: 5000.0,
              flatValue: 250.0,
              activeColor: _customLoshelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customLoshelfCutoff = v;
                  _updateLoshelf();
                });
              },
            ),
            ModernAudioKnob(
              label: 'GAIN',
              value: _customLoshelfGainDb,
              min: -24.0,
              max: 24.0,
              flatValue: 0.0,
              activeColor: _customLoshelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() {
                  _customLoshelfGainDb = v;
                  _updateLoshelf();
                });
              },
            ),
            ModernAudioKnob(
              label: 'SLOPE',
              value: _customLoshelfSlope,
              min: 0.1,
              max: 2.0,
              flatValue: 1.0,
              activeColor: _customLoshelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(2),
              onChanged: (v) {
                setState(() {
                  _customLoshelfSlope = v;
                  _updateLoshelf();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // High Shelf Filter Section
        _buildFilterRow(
          title: 'High Shelf Filter',
          isEnabled: _customHishelfEnabled,
          onToggle: (v) {
            setState(() {
              _customHishelfEnabled = v;
              _updateHishelf();
            });
          },
          controls: [
            ModernAudioKnob(
              label: 'CUTOFF',
              value: _customHishelfCutoff,
              min: 1000.0,
              max: 20000.0,
              flatValue: 8000.0,
              activeColor: _customHishelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => '${v.toInt()} Hz',
              onChanged: (v) {
                setState(() {
                  _customHishelfCutoff = v;
                  _updateHishelf();
                });
              },
            ),
            ModernAudioKnob(
              label: 'GAIN',
              value: _customHishelfGainDb,
              min: -24.0,
              max: 24.0,
              flatValue: 0.0,
              activeColor: _customHishelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) =>
                  '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: (v) {
                setState(() {
                  _customHishelfGainDb = v;
                  _updateHishelf();
                });
              },
            ),
            ModernAudioKnob(
              label: 'SLOPE',
              value: _customHishelfSlope,
              min: 0.1,
              max: 2.0,
              flatValue: 1.0,
              activeColor: _customHishelfEnabled ? primaryColor : Colors.white,
              valueFormatter: (v) => v.toStringAsFixed(2),
              onChanged: (v) {
                setState(() {
                  _customHishelfSlope = v;
                  _updateHishelf();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Biquad Section
        M3ECard(
          variant: M3ECardVariant.filled,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Direct Form II Biquad Coeffs',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold)),
                    M3ESwitch(
                      selectedIcon: Icon(Icons.check, color: primaryColor),
                      value: _customBiquadEnabled,
                      onChanged: (v) {
                        setState(() {
                          _customBiquadEnabled = v;
                          _updateBiquad();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildBiquadKnob(
                        'B0',
                        _biquadB0,
                        (v) => setState(() {
                              _biquadB0 = v;
                              _updateBiquad();
                            })),
                    _buildBiquadKnob(
                        'B1',
                        _biquadB1,
                        (v) => setState(() {
                              _biquadB1 = v;
                              _updateBiquad();
                            })),
                    _buildBiquadKnob(
                        'B2',
                        _biquadB2,
                        (v) => setState(() {
                              _biquadB2 = v;
                              _updateBiquad();
                            })),
                    _buildBiquadKnob(
                        'A0',
                        _biquadA0,
                        (v) => setState(() {
                              _biquadA0 = v;
                              _updateBiquad();
                            })),
                    _buildBiquadKnob(
                        'A1',
                        _biquadA1,
                        (v) => setState(() {
                              _biquadA1 = v;
                              _updateBiquad();
                            })),
                    _buildBiquadKnob(
                        'A2',
                        _biquadA2,
                        (v) => setState(() {
                              _biquadA2 = v;
                              _updateBiquad();
                            })),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow({
    required String title,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required List<Widget> controls,
  }) {
    return M3ECard(
      variant: M3ECardVariant.filled,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: isEnabled,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: controls,
            ),
          ],
        ),
      ),
    );
  }

  void _updateBpf() {
    widget.player.setBandpass(
      enabled: _customBpfEnabled,
      cutoffHz: _customBpfCutoff,
      q: _customBpfQ,
    );
  }

  void _updateNotch() {
    widget.player.setNotch(
      enabled: _customNotchEnabled,
      frequencyHz: _customNotchCutoff,
      q: _customNotchQ,
    );
  }

  void _updatePeak() {
    widget.player.setPeakEq(
      enabled: _customPeakEnabled,
      frequencyHz: _customPeakCutoff,
      gainDb: _customPeakGainDb,
      q: _customPeakQ,
    );
  }

  void _updateLoshelf() {
    widget.player.setLowshelf(
      enabled: _customLoshelfEnabled,
      frequencyHz: _customLoshelfCutoff,
      gainDb: _customLoshelfGainDb,
      slope: _customLoshelfSlope,
    );
  }

  void _updateHishelf() {
    widget.player.setHighshelf(
      enabled: _customHishelfEnabled,
      frequencyHz: _customHishelfCutoff,
      gainDb: _customHishelfGainDb,
      slope: _customHishelfSlope,
    );
  }

  void _updateBiquad() {
    widget.player.setCustomBiquad(
      enabled: _customBiquadEnabled,
      b0: _biquadB0,
      b1: _biquadB1,
      b2: _biquadB2,
      a0: _biquadA0,
      a1: _biquadA1,
      a2: _biquadA2,
    );
  }

  Widget _buildBiquadKnob(
      String label, double value, ValueChanged<double> onChanged) {
    return ModernAudioKnob(
      label: label,
      value: value,
      min: -2.0,
      max: 2.0,
      flatValue: (label == 'B0' || label == 'A0') ? 1.0 : 0.0,
      activeColor: _customBiquadEnabled ? primaryColor : Colors.white,
      valueFormatter: (v) => v.toStringAsFixed(2),
      onChanged: onChanged,
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
  final bool hasSwitch;
  final ValueChanged<bool>? onToggle;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isEnabled = false,
    this.hasSwitch = true,
    this.onToggle,
    required this.children,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  Color get primaryColor => context.primaryColor;

  @override
  Widget build(BuildContext context) {
    return M3EExpandableList.builder(
      key: ValueKey('${widget.title}_${widget.isEnabled}'),
      itemCount: 1,
      initiallyExpanded: widget.isEnabled ? const {0} : const <int>{},
      allowMultipleExpanded: true,
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
            if (widget.hasSwitch) ...[
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
