import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/app_state_service.dart';
import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';

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

class _EqScreenState extends State<EqScreen> {
  // Preferences
  bool _showWarningBanner = true;

  // Master EQ
  bool _masterEqEnabled = true;

  // 10-Band Graphic EQ Frequencies
  final List<double> _eqFrequencies = [
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
  final List<double> _eqGains = List.filled(10, 0.0);
  String _activePreset = 'Flat';

  // Parametric EQ bands state
  final List<EqBandConfig> _parametricBands = [];
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

  // Audio Tuning (3-band EQ)
  bool _audioTuningEnabled = false;
  double _tuneLow = 1.0;
  double _tuneMid = 1.0;
  double _tuneHigh = 1.0;

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

  // Realtime Analyzer
  List<double> _analyzerValues = List<double>.filled(64, 0.0);
  StreamSubscription<Float32List>? _analyzerSub;

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
    _analyzerSub = widget.player.analyzerStream.listen((frame) {
      if (frame.isEmpty || !widget.analyzerEnabled) return;
      const targetBins = 64;
      final bins = List<double>.filled(targetBins, 0.0);
      final srcLen = frame.length;
      for (var i = 0; i < targetBins; i++) {
        final from = (i * srcLen / targetBins).floor();
        final to = ((i + 1) * srcLen / targetBins).ceil();
        var sum = 0.0;
        var count = 0;
        for (var j = from; j < to && j < srcLen; j++) {
          sum += frame[j].abs();
          count++;
        }
        bins[i] = count > 0 ? sum / count : 0.0;
      }
      if (mounted) setState(() => _analyzerValues = bins);
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final hideBanner = prefs.getBool('hide_eq_warning') ?? false;

    // Load all persisted EQ state
    final eqBands = await AppStateService.instance.loadEqBands();
    final spatial = await AppStateService.instance.loadSpatialAudio();
    final delay = await AppStateService.instance.loadDelay();
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
    _analyzerSub?.cancel();
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
      switch (preset) {
        case 'Flat':
          _eqGains.fillRange(0, _eqGains.length, 0.0);
          break;
        case 'Bass Boost':
          _eqGains[0] = 6.0;
          _eqGains[1] = 5.0;
          _eqGains[2] = 3.0;
          _eqGains.fillRange(3, 10, 0.0);
          break;
        case 'Vocal':
          _eqGains.fillRange(0, 3, -2.0);
          _eqGains[3] = 1.0;
          _eqGains[4] = 3.0;
          _eqGains[5] = 4.0;
          _eqGains[6] = 3.0;
          _eqGains[7] = 1.0;
          _eqGains.fillRange(8, 10, -1.0);
          break;
        case 'Treble':
          _eqGains.fillRange(0, 6, 0.0);
          _eqGains[6] = 2.0;
          _eqGains[7] = 4.0;
          _eqGains[8] = 5.0;
          _eqGains[9] = 6.0;
          break;
        case 'Rock':
          _eqGains[0] = 5.0;
          _eqGains[1] = 4.0;
          _eqGains[2] = 2.0;
          _eqGains[3] = -1.0;
          _eqGains[4] = -2.0;
          _eqGains[5] = -1.0;
          _eqGains[6] = 1.0;
          _eqGains[7] = 3.0;
          _eqGains[8] = 4.0;
          _eqGains[9] = 5.0;
          break;
        case 'Jazz':
          _eqGains[0] = 4.0;
          _eqGains[1] = 3.0;
          _eqGains[2] = 1.0;
          _eqGains[3] = 2.0;
          _eqGains[4] = -2.0;
          _eqGains[5] = -2.0;
          _eqGains[6] = 0.0;
          _eqGains[7] = 1.0;
          _eqGains[8] = 3.0;
          _eqGains[9] = 4.0;
          break;
      }
      _applyEqGains();
    });
    // Persist the new preset
    _saveEqState();
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

      _audioTuningEnabled = false;
      widget.player.setEqEnabled(false);
      _tuneLow = 1.0;
      _tuneMid = 1.0;
      _tuneHigh = 1.0;
      widget.player.setEq(low: 1.0, mid: 1.0, high: 1.0);

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
    return Scaffold(
      backgroundColor: bgDarkColor,
      appBar: AppBar(
        backgroundColor: surfaceDarkerColor.withOpacity(0.95),
        elevation: 0,
        title: const Text('Audio Effects',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => _resetAll(),
            child: const Text('Reset',
                style: TextStyle(
                    color: primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        physics: const BouncingScrollPhysics(),
        children: [
          // Warning Banner
          if (_showWarningBanner)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              color: Colors.white70, fontSize: 12, height: 1.4),
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

          // Realtime Audio Analyzer (replaces old EQ chart)
          if (widget.analyzerEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _buildAnalyzerSection(),
            ),

          // Master Equalizer Switch
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('10-Band Equalizer',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('Enable 10-band EQ',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12)),
                  ],
                ),
                Switch(
                  value: _masterEqEnabled,
                  onChanged: (v) {
                    setState(() => _masterEqEnabled = v);
                    widget.player.setMultibandEqEnabled(v);
                    _saveEqState();
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: primaryColor,
                ),
              ],
            ),
          ),

          // Presets Horizontal Scroller
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
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

          // 10-Band Sliders
          Padding(
            padding:
                const EdgeInsets.only(top: 32, left: 20, right: 20, bottom: 40),
            child: _buildGraphicEqSliders(),
          ),

          // Audio Tuning Section (3-Band)
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
            child: _buildAudioTuningSection(),
          ),

          // Parametric EQ Section
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
            child: _buildParametricEqSection(),
          ),

          // Delay (Echo) Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildDelaySection(),
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
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 32),
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

  Widget _buildGraphicEqSliders() {
    final List<Widget> sliders = [];

    // Preamp Slider
    sliders.add(
      Column(
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
                      _masterEqEnabled ? primaryColor : Colors.white,
                  inactiveTrackColor: Colors.white.withOpacity(0.1),
                  thumbColor: Colors.white,
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
          const SizedBox(height: 12),
          Text('PREAMP',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );

    // 10-Band Sliders
    sliders.addAll(
      List.generate(10, (i) {
        final freq = _eqFrequencies[i];
        String label =
            freq >= 1000 ? '${(freq / 1000).toInt()}k' : '${freq.toInt()}';

        return Column(
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
                        _masterEqEnabled ? primaryColor : Colors.white,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _eqGains[i],
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
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        );
      }),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: sliders,
    );
  }

  Widget _buildSpatialAudioSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.spatial_audio_off_outlined,
                      color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spatial Audio',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('Immersive soundstage',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            Switch(
              value: _spatialAudioEnabled,
              onChanged: (v) {
                setState(() => _spatialAudioEnabled = v);
                widget.player.setReverbEnabled(v);
                if (v) _updateSpatialAudio();
                _saveEqState();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
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

  Widget _buildDelaySection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle),
                  child:
                      const Icon(Icons.blur_on, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Delay / Echo',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('Repeats & rhythms',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            Switch(
              value: _delayEnabled,
              onChanged: (v) {
                setState(() => _delayEnabled = v);
                widget.player.setDelay(enabled: v);
                if (v) _updateDelay();
                _saveEqState();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
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

  void _updateSpatialAudio() {
    // DelayMs mapping: 20ms to 350ms
    double delayMs = 20.0 + (_roomSize * 330.0);
    // Feedback mapping: 0 to 0.98 based on Echo
    double feedback = _echo * 0.98;

    widget.player
        .setReverb(mix: _reverbMix, feedback: feedback, delayMs: delayMs);
  }

  Widget _buildTrue3dSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.spatial_tracking,
                      color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('True 3D Spatial Audio',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('X/Y/Z Source Placement',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            Switch(
              value: _true3dEnabled,
              onChanged: (v) {
                setState(() => _true3dEnabled = v);
                widget.player.setSpatializationEnabled(v);
                if (v) _updateTrue3dPositions();
                _saveEqState();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
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
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.tune, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Audio Tuning',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('3-band EQ',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            Switch(
              value: _audioTuningEnabled,
              onChanged: (v) {
                setState(() => _audioTuningEnabled = v);
                widget.player.setEqEnabled(v);
                if (v) {
                  widget.player
                      .setEq(low: _tuneLow, mid: _tuneMid, high: _tuneHigh);
                }
                _saveEqState();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ModernAudioKnob(
              label: 'BASS',
              value: _tuneLow,
              min: 0.01,
              max: 4.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
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
              min: 0.01,
              max: 4.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
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
              min: 0.01,
              max: 4.0,
              activeColor: _audioTuningEnabled ? primaryColor : Colors.white,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Parametric EQ',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('Advanced mixed FX chain',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
            Row(
              children: [
                if (true) // Keep Add button visible to allow configuring while off
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: primaryColor),
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
                Switch(
                  value: _parametricEqEnabled,
                  onChanged: (v) {
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
                        widget.player.initMultibandFx(_parametricBands);
                      }
                      widget.player.setMultibandFxEnabled(v);
                    });
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: primaryColor,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
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

  // ── Realtime Analyzer ──────────────────────────────────────────────
  Widget _buildAnalyzerSection() {
    if (!widget.analyzerEnabled) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: _buildAnalyzerChart(),
    );
  }

  Widget _buildAnalyzerChart() {
    final len = _analyzerValues.length;

    if (widget.analyzerType == 'bar') {
      // ── Bar Chart ──
      final groups = <BarChartGroupData>[];
      for (var i = 0; i < len; i++) {
        final normalized = (_analyzerValues[i] * 6.0).clamp(0.0, 1.0);
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: normalized,
                width: math.max(
                    1, (MediaQuery.of(context).size.width - 100) / len),
                color: primaryColor.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 1.0,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ],
          ),
        );
      }

      return BarChart(
        BarChartData(
          maxY: 1,
          minY: 0,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: groups,
          barTouchData: BarTouchData(enabled: false),
        ),
      );
    }

    // ── Area (Line) Chart ──
    final spots = <FlSpot>[];
    for (var i = 0; i < len; i++) {
      final normalized = (_analyzerValues[i] * 6.0).clamp(0.0, 1.0);
      spots.add(FlSpot(i.toDouble(), normalized));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(1, len - 1).toDouble(),
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: primaryColor,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  primaryColor.withValues(alpha: 0.4),
                  primaryColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }

  Widget _buildCustomFiltersSection() {
    return Column(
      children: [
        // Title
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle),
              child:
                  const Icon(Icons.filter_list, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Custom Filters',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('Real-Time LPF, HPF, Biquad',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle),
                  child:
                      const Icon(Icons.compress, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Soft Limiter',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('Prevent clipping & distortion',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
            Switch(
              value: _limiterEnabled,
              onChanged: (v) {
                setState(() => _limiterEnabled = v);
                _applyLimiter();
                _saveEqState();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
        const SizedBox(height: 24),
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
    if (widget.valueFormatter != null) {
      displayValue = widget.valueFormatter!(widget.value);
    } else {
      double db =
          20 * math.log(widget.value == 0 ? 0.0001 : widget.value) / math.ln10;
      db = db.clamp(-24.0, 24.0);
      displayValue = '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
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
        Text(displayValue,
            style: TextStyle(
                color: widget.activeColor,
                fontSize: 10,
                fontFamily: 'monospace')),
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
