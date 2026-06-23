import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'isolate_player.dart';
import 'services/app_state_service.dart';

// Tailwind Colors Ported
const primaryColor = Color(0xFF137fec);
const bgLightColor = Color(0xFFf6f7f8);
const bgDarkColor = Color(0xFF101922);
const surfaceDarkColor = Color(0xFF1C252E);
const surfaceDarkerColor = Color(0xFF111a22);

class EqScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool analyzerEnabled;
  final String analyzerType;

  const EqScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.analyzerType,
  });

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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

  // Stereo Widen
  bool _stereoWidenEnabled = false;
  double _stereoWidenWidth = 1.5;
  double _stereoWidenDelayMs = 0.15; // Maps to 15ms

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

  // Custom Filters
  bool _customLpfEnabled = false;
  double _customLpfCutoff = 500.0;

  bool _customHpfEnabled = false;
  double _customHpfCutoff = 120.0;

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

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initEq();
    _eqSettingsSub =
        AppStateService.instance.eqSettingsChanged.stream.listen((_) {
      if (mounted) _loadPreferences();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final hideBanner = prefs.getBool('hide_eq_warning') ?? false;

    // Load all persisted EQ state
    final eqBands = await AppStateService.instance.loadEqBands();
    final spatial = await AppStateService.instance.loadSpatialAudio();
    final delay = await AppStateService.instance.loadDelay();
    final dynamicBass = await AppStateService.instance.loadDynamicBass();
    final crystalizer = await AppStateService.instance.loadCrystalizer();
    final stereoWiden = await AppStateService.instance.loadStereoWiden();
    final crossfeed = await AppStateService.instance.loadCrossfeed();
    final tuning = await AppStateService.instance.loadAudioTuning();
    final true3d = await AppStateService.instance.loadTrue3d();
    final lpf = await AppStateService.instance.loadCustomLpf();
    final hpf = await AppStateService.instance.loadCustomHpf();
    final limiter = await AppStateService.instance.loadLimiter();

    setState(() {
      _showWarningBanner = !hideBanner;

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

      // Stereo Widen
      _stereoWidenEnabled = stereoWiden.enabled;
      _stereoWidenWidth = stereoWiden.width;
      _stereoWidenDelayMs = stereoWiden.delayMs;

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
    );
    AppStateService.instance.saveStereoWiden(
      enabled: _stereoWidenEnabled,
      width: _stereoWidenWidth,
      delayMs: _stereoWidenDelayMs,
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
    _eqSettingsSub?.cancel();
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgDarkColor,
        title: const Text('Audio Pipeline State',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Input File Format',
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold)),
              Text(
                  'Sample Rate: ${state.inputSampleRate} Hz\nChannels: ${state.inputChannels}\nFormat: ${state.inputFormatString}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text('DSP Processing Format',
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold)),
              Text(
                  'Sample Rate: ${state.processingSampleRate} Hz\nChannels: ${state.processingChannels}\nFormat: ${state.processingFormatString}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text('Hardware Output Format',
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold)),
              Text(
                  'Sample Rate: ${state.outputSampleRate} Hz\nChannels: ${state.outputChannels}\nFormat: ${state.outputFormatString}\nEst. Device Latency: ${latencyMs.toStringAsFixed(2)} ms',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text('Active DSP Nodes',
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold)),
              Text(
                  'EQ: ${state.eqEnabled}\nReverb: ${state.reverbEnabled}\nLimiter: ${state.limiterEnabled}\nDelay: ${state.delayEnabled}\nStereo Widen: ${state.stereoWidenEnabled}\nSpatialization: ${state.spatializationEnabled}',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _resetAll() {
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

      // Limiter
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: bgDarkColor,
      appBar: null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          return Align(
            alignment: isDesktop ? Alignment.topCenter : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000.0),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    isDesktop ? 48.0 : 0, 0, isDesktop ? 48.0 : 0, 120),
                physics: const BouncingScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 16.0, bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info_outline, color: Colors.white54),
                              onPressed: _showPipelineInfo,
                            ),
                            const SizedBox(width: 8),
                            const Text('Master EQ', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.white),
                              tooltip: 'Reset All',
                              onPressed: _resetAll,
                            ),
                            Switch(
                              value: _masterEqEnabled,
                              onChanged: (val) {
                                setState(() => _masterEqEnabled = val);
                                widget.player.setMultibandEqEnabled(val);
                                _saveEqState();
                              },
                              activeThumbColor: Colors.white,
                              activeTrackColor: primaryColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Warning Banner
                  if (_showWarningBanner)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red[400], size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Advanced Controls',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Improper equalizer, limiter, or biquad settings can cause severe audio distortion, clipping, or a completely degraded listening experience. Proceed with caution.',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      height: 1.4),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _dismissWarningBanner,
                            icon: const Icon(Icons.close,
                                color: Colors.white54, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 20,
                          ),
                        ],
                      ),
                    ),

                  // Graphic Equalizer Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildGraphicEqSection(),
                  ),
                  const SizedBox(height: 16),

                  // Audio Tuning Section (3-Band)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, bottom: 40),
                    child: _buildAudioTuningSection(),
                  ),

                  // Parametric EQ Section
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, bottom: 40),
                    child: _buildParametricEqSection(),
                  ),

                  // Delay (Echo) Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildDelaySection(),
                  ),
                  const SizedBox(height: 16),

                  // Dynamic Bass
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildDynamicBassSection(),
                  ),
                  const SizedBox(height: 16),

                  // Crystalizer
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildCrystalizerSection(),
                  ),
                  const SizedBox(height: 16),

                  // Audiophile Crossfeed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildCrossfeedSection(),
                  ),
                  const SizedBox(height: 16),

                  // Stereo Widen Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildStereoWidenSection(),
                  ),
                  const SizedBox(height: 16),

                  // Spatial Audio (Reverb combo)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSpatialAudioSection(),
                  ),
                  const SizedBox(height: 32),

                  // True 3D Spatial Audio
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildTrue3dSection(),
                  ),

                  // Custom Filters Section
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, bottom: 32),
                    child: _buildCustomFiltersSection(),
                  ),

                  // Soft Limiter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildLimiterSection(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetChip(String label) {
    final isSelected = _activePreset == label;
    return GestureDetector(
      onTap: () => _applyPreset(label),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : surfaceDarkColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isSelected ? primaryColor : Colors.white.withOpacity(0.1)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
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
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: surfaceDarkColor,
          title: Text('Enter $title',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Value ($min to $max)',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: primaryColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final val = double.tryParse(controller.text);
                if (val != null) {
                  onChanged(val.clamp(min, max));
                }
                Navigator.pop(context);
              },
              child: const Text('OK', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGraphicEqSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.equalizer, color: primaryColor, size: 20),
      ),
      title: '${_eqFrequencies.length}-Band Equalizer',
      subtitle: 'Enable ${_eqFrequencies.length}-band EQ',
      isEnabled: _masterEqEnabled,
      onToggle: (v) {
        setState(() => _masterEqEnabled = v);
        widget.player.setMultibandEqEnabled(v);
        _saveEqState();
      },
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 0),
            children: [
              _buildPresetChip('Flat'),
              const SizedBox(width: 12),
              _buildPresetChip('Bass Boost'),
              const SizedBox(width: 12),
              _buildPresetChip('Vocal'),
              const SizedBox(width: 12),
              _buildPresetChip('Treble'),
              const SizedBox(width: 12),
              _buildPresetChip('Rock'),
              const SizedBox(width: 12),
              _buildPresetChip('Jazz'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 16),
          child: _buildGraphicEqSliders(),
        ),
      ],
    );
  }

  Widget _buildGraphicEqSliders() {
    // Preamp Slider (Independent of Graphic EQ toggle)
    final Widget preampSlider = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: Colors.deepOrangeAccent,
                  inactiveTrackColor: Colors.white.withOpacity(0.1),
                  thumbColor: Colors.deepOrangeAccent,
                ),
                child: Slider(
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
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('PREAMP',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );

    // Graphic Sliders (Dynamic based on band count)
    final List<Widget> bandSliders = List.generate(_eqFrequencies.length, (i) {
      final freq = _eqFrequencies[i];
      String label = freq >= 1000
          ? '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k'
          : '${freq.toInt()}';

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor:
                        _masterEqEnabled ? primaryColor : Colors.white24,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor:
                        _masterEqEnabled ? Colors.white : Colors.white24,
                  ),
                  child: Slider(
                    value: _eqGains[i],
                    min: -12.0,
                    max: 12.0,
                    onChanged: _masterEqEnabled
                        ? (v) {
                            setState(() {
                              _eqGains[i] = v;
                              _activePreset = 'Custom';
                              widget.player.setMultibandEqBandGain(i, v);
                            });
                            _saveEqState();
                          }
                        : null,
                  ),
                ),
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
                            widget.player.setMultibandEqBandGain(i, v);
                          });
                          _saveEqState();
                        },
                      )
                  : null,
              child: Text(
                '${_eqGains[i] > 0 ? '+' : ''}${_eqGains[i].toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: _masterEqEnabled ? primaryColor : Colors.white24,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    });

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preampSlider,
        Container(
          width: 1,
          height: 190,
          color: Colors.white.withOpacity(0.1),
          margin: const EdgeInsets.only(right: 4),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: bandSliders,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpatialAudioSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.spatial_audio_off_outlined,
            color: primaryColor, size: 20),
      ),
      title: 'Spatial Audio',
      subtitle: 'Immersive soundstage',
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
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.waves, color: primaryColor, size: 20),
      ),
      title: 'Dynamic Bass',
      subtitle: 'Powerful bass enhancement',
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
                Text('PRESET',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: surfaceDarkColor,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButton<int>(
                    value: _dynamicBassPreset,
                    dropdownColor: surfaceDarkerColor,
                    underline: const SizedBox(),
                    icon:
                        const Icon(Icons.arrow_drop_down, color: primaryColor),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: List.generate(19, (index) {
                      // 0=60, 1=65, ... 18=180 mappings.
                      int f = 60 + (index * 5); // Rough mapping for display
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
    const crystalColor = Color(0xFF00C9B1); // teal-cyan accent
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0x2600C9B1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.auto_fix_high, color: crystalColor, size: 20),
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
        // Knobs row
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
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: _crystalizerHighShelf,
              activeThumbColor: crystalColor,
              onChanged: (v) {
                setState(() => _crystalizerHighShelf = v);
                if (_crystalizerEnabled) _updateCrystalizer();
                _saveEqState();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Info chip
        Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x1A00C9B1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x4000C9B1)),
            ),
            child: Text(
              'Recovers transient detail & "air" lost in MP3/AAC compression',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
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
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.headphones, color: primaryColor, size: 20),
      ),
      title: 'Crossfeed',
      subtitle: 'Simulate speaker listening',
      isEnabled: _crossfeedEnabled,
      onToggle: (v) {
        setState(() => _crossfeedEnabled = v);
        if (v) {
          _updateCrossfeed();
        } else {
          widget.player.setCrossfeed(enabled: false, preset: _crossfeedPreset);
        }
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Algorithm Preset',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: surfaceDarkColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: DropdownButton<int>(
                value: _crossfeedPreset,
                dropdownColor: surfaceDarkerColor,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: primaryColor),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('BS2B Weak')),
                  DropdownMenuItem(value: 2, child: Text('BS2B Strong')),
                  DropdownMenuItem(value: 3, child: Text('Joe0bloggs 3D')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _crossfeedPreset = val);
                    _updateCrossfeed();
                    _saveEqState();
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStereoWidenSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.compare_arrows, color: primaryColor, size: 20),
      ),
      title: 'Stereo Stage',
      subtitle: 'M/S & Haas width',
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
              label: 'HAAS',
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

  Widget _buildDelaySection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.blur_on, color: primaryColor, size: 20),
      ),
      title: 'Delay / Echo',
      subtitle: 'Repeats & rhythms',
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
              label: 'FDBK',
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
    widget.player.setCrossfeed(
      enabled: _crossfeedEnabled,
      preset: _crossfeedPreset,
    );
  }

  void _updateStereoWiden() {
    // mapped _stereoWidenDelayMs mapping 0.0-1.0 to 0-100ms
    double delayMsMapping = _stereoWidenDelayMs * 100.0;
    widget.player.setStereoWiden(
      enabled: _stereoWidenEnabled,
      width: _stereoWidenWidth,
      delayMs: delayMsMapping,
    );
  }

  void _updateSpatialAudio() {
    // DelayMs mapping: 20ms to 350ms
    double delayMs = 20.0 + (_roomSize * 330.0);
    // Feedback mapping: 0 to 0.98 based on Echo
    double feedback = _echo * 0.98;

    widget.player
        .setReverb(mix: _reverbMix, feedback: feedback, delayMs: delayMs);
  }

  Widget _buildTrue3dSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child:
            const Icon(Icons.spatial_tracking, color: primaryColor, size: 20),
      ),
      title: 'True 3D Spatial Audio',
      subtitle: 'X/Y/Z Source Placement',
      isEnabled: _true3dEnabled,
      onToggle: (v) {
        setState(() => _true3dEnabled = v);
        widget.player.setSpatializationEnabled(v);
        if (v) _updateTrue3dPositions();
        _saveEqState();
      },
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'X (PAN)',
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
              label: 'Y (UP)',
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
              label: 'Z (FWD)',
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
      ],
    );
  }

  void _updateTrue3dPositions() {
    widget.player.setPosition(x: _spatX, y: _spatY, z: _spatZ);
  }

  Widget _buildAudioTuningSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.tune, color: primaryColor, size: 20),
      ),
      title: 'Audio Tuning',
      subtitle: '3-band EQ',
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
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.tune, color: primaryColor, size: 20),
      ),
      title: 'Parametric EQ',
      subtitle: 'Advanced mixed FX chain',
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add_circle_outline, color: primaryColor),
              label:
                  const Text('Add Band', style: TextStyle(color: primaryColor)),
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
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
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
      width: 220,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Band ${index + 1}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('${band.frequencyHz.toInt()}Hz',
                      style: const TextStyle(
                          color: primaryColor, fontFamily: 'monospace')),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _parametricBands.removeAt(index);
                        _applyParametricBands();
                      });
                    },
                    child: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Type Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: surfaceDarkerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<EqBandType>(
                value: band.type,
                isExpanded: true,
                dropdownColor: surfaceDarkerColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: EqBandType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
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
          ),
          //  const SizedBox(height: 16),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Frequency Knob
              ModernAudioKnob(
                label: 'FREQ',
                value: band.frequencyHz.clamp(20.0, 20000.0),
                min: 20.0,
                max: 20000.0,
                flatValue: 1000.0,
                activeColor: _parametricEqEnabled ? primaryColor : Colors.white,
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
                activeColor: _parametricEqEnabled ? primaryColor : Colors.white,
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

              // Gain Knob
              ModernAudioKnob(
                label: 'GAIN',
                value: band.gainDb,
                min: -24.0,
                max: 24.0,
                flatValue: 0.0,
                activeColor: _parametricEqEnabled ? primaryColor : Colors.white,
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
    );
  }

  Widget _buildCustomFiltersSection() {
    return _CollapsibleSection(
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.filter_list, color: primaryColor, size: 20),
      ),
      title: 'Custom Filters',
      subtitle: 'Real-Time LPF, HPF, Biquad',
      hasSwitch: false,
      children: [
        // LPF Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Low-Pass Filter',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Switch(
                  value: _customLpfEnabled,
                  onChanged: (v) {
                    setState(() {
                      _customLpfEnabled = v;
                      widget.player.setCustomLpf1(
                          enabled: v, cutoffHz: _customLpfCutoff);
                    });
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: primaryColor,
                ),
              ],
            ),
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
        const SizedBox(height: 24),

        // HPF Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('High-Pass Filter',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Switch(
                  value: _customHpfEnabled,
                  onChanged: (v) {
                    setState(() {
                      _customHpfEnabled = v;
                      widget.player.setCustomHpf1(
                          enabled: v, cutoffHz: _customHpfCutoff);
                    });
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: primaryColor,
                ),
              ],
            ),
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
        const SizedBox(height: 24),

        // Biquad Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Custom Biquad',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            Switch(
              value: _customBiquadEnabled,
              onChanged: (v) {
                setState(() {
                  _customBiquadEnabled = v;
                  _updateBiquad();
                });
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
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
        )
      ],
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
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.compress, color: primaryColor, size: 20),
      ),
      title: 'Soft Limiter',
      subtitle: 'Prevent clipping & distortion',
      isEnabled: _limiterEnabled,
      onToggle: (v) {
        setState(() => _limiterEnabled = v);
        _applyLimiter();
        _saveEqState();
      },
      children: [
        // ── Three knobs ──────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'THRESH',
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
  final Color activeColor;
  final bool isPercentage;
  final double displayMultiplier;

  const ModernAudioKnob({
    super.key,
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 3.0,
    this.flatValue = 1.0,
    required this.onChanged,
    this.valueFormatter,
    this.activeColor = primaryColor,
    this.isPercentage = false,
    this.displayMultiplier = 1.0,
  });

  @override
  State<ModernAudioKnob> createState() => _ModernAudioKnobState();
}

class _ModernAudioKnobState extends State<ModernAudioKnob> {
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // dragging up (negative dy) increases value
    double sensitivity = (widget.max - widget.min) / 150.0;
    double newValue = widget.value - (details.delta.dy * sensitivity);
    newValue = newValue.clamp(widget.min, widget.max);
    widget.onChanged(newValue);
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
      // It's a dB value internally mapped via math.pow for gain elsewhere, or direct dB.
      dbValue =
          20 * math.log(widget.value == 0 ? 0.0001 : widget.value) / math.ln10;
      dbValue = dbValue.clamp(-24.0, 24.0);
      displayValue =
          '${dbValue > 0 ? '+' : ''}${dbValue.toStringAsFixed(1)} dB';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onDoubleTap: () => widget.onChanged(widget.flatValue),
          child: CustomPaint(
            size: const Size(60, 60),
            painter: _KnobPainter(
              normalizedValue: normalizedValue,
              activeColor: widget.activeColor,
              inactiveColor: Colors.white.withOpacity(0.1),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(widget.label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        GestureDetector(
          onLongPress: () {
            // Determine default text based on whether it's plain value or dB
            String initialText = widget.value.toStringAsFixed(2);
            double effectiveMultiplier =
                widget.isPercentage ? 100.0 : widget.displayMultiplier;
            int decimals = widget.isPercentage ? 0 : 1;

            if (widget.isPercentage || widget.displayMultiplier != 1.0) {
              initialText = (widget.value * effectiveMultiplier)
                  .toStringAsFixed(decimals);
            } else if (widget.valueFormatter == null) {
              initialText = dbValue.toStringAsFixed(2);
            }

            final controller = TextEditingController(text: initialText);

            // Determine input bounds for display
            double displayMin = widget.min;
            double displayMax = widget.max;
            if (widget.isPercentage || widget.displayMultiplier != 1.0) {
              displayMin = widget.min * effectiveMultiplier;
              displayMax = widget.max * effectiveMultiplier;
            } else if (widget.valueFormatter == null) {
              displayMin = -24.0;
              displayMax = 24.0;
            }

            // Also format the range correctly
            String displayMinStr = displayMin.toStringAsFixed(decimals);
            String displayMaxStr = displayMax.toStringAsFixed(decimals);
            if (widget.valueFormatter == null &&
                !widget.isPercentage &&
                widget.displayMultiplier == 1.0) {
              // dB case
              displayMinStr = displayMin.toStringAsFixed(1);
              displayMaxStr = displayMax.toStringAsFixed(1);
            }

            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: surfaceDarkColor,
                  title: Text('Enter ${widget.label}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  content: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Value ($displayMinStr to $displayMaxStr)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: primaryColor)),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    TextButton(
                      onPressed: () {
                        final val = double.tryParse(controller.text);
                        if (val != null) {
                          if (widget.isPercentage ||
                              widget.displayMultiplier != 1.0) {
                            widget.onChanged((val / effectiveMultiplier)
                                .clamp(widget.min, widget.max));
                          } else if (widget.valueFormatter == null) {
                            // User entered dB, convert back to linear
                            double linear = math.pow(10, val / 20).toDouble();
                            widget.onChanged(
                                linear.clamp(widget.min, widget.max));
                          } else {
                            // For audio tuning, the value itself is dB and formatter is now provided
                            widget.onChanged(val.clamp(widget.min, widget.max));
                          }
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('OK',
                          style: TextStyle(color: primaryColor)),
                    ),
                  ],
                );
              },
            );
          },
          child: Text(displayValue,
              style: TextStyle(
                  color: widget.activeColor,
                  fontSize: 10,
                  fontFamily: 'monospace')),
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
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isEnabled;
  }

  @override
  void didUpdateWidget(covariant _CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled && !oldWidget.isEnabled) {
      _isExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    widget.icon,
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text(widget.subtitle,
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (widget.hasSwitch)
                      Switch(
                        value: widget.isEnabled,
                        onChanged: widget.onToggle,
                        activeThumbColor: Colors.white,
                        activeTrackColor: primaryColor,
                      ),
                    if (widget.hasSwitch) const SizedBox(width: 8),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 16),
          ...widget.children,
        ],
      ],
    );
  }
}
