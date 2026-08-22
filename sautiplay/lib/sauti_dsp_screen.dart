import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';

/// Screen for controlling the clean-room Sauti DSP Suite.
class SautiDspScreen extends StatefulWidget {
  final IsolateAudioPlayer player;

  const SautiDspScreen({super.key, required this.player});

  static Future<void> applySavedStateToEngine(IsolateAudioPlayer player) async {
    final map = await AppStateService.instance.loadSautiDspState();
    if (map.isEmpty) return;

    final bool masterEnabled = map['dspMasterEnabled'] ?? true;
    if (!masterEnabled) {
      player.setClarity(enabled: false);
      player.setHarmonicBass(enabled: false);
      player.setDynamicSystem(enabled: false);
      player.setAnalogWarmth(enabled: false);
      player.setConvolverEnabled(false);
      player.setMasterLimiter(enabled: false);
      return;
    }

    // 1. Audio Clarity
    player.setClarity(
      enabled: map['clarityEnabled'] ?? false,
      profile: AudioClarityProfile.values.firstWhere(
        (e) => e.value == (map['clarityProfile'] ?? 0),
        orElse: () => AudioClarityProfile.transientCrisp,
      ),
      intensity: (map['clarityIntensity'] as num?)?.toDouble() ?? 0.5,
    );

    // 2. Harmonic Bass
    player.setHarmonicBass(
      enabled: map['bassEnabled'] ?? false,
      profile: HarmonicBassProfile.values.firstWhere(
        (e) => e.value == (map['bassProfile'] ?? 0),
        orElse: () => HarmonicBassProfile.subBassResonant,
      ),
      cutoffHz: (map['bassCutoffHz'] as num?)?.toDouble() ?? 60.0,
      boost: (map['bassBoost'] as num?)?.toDouble() ?? 0.5,
    );

    // 3. Dynamic Transducer System
    player.setDynamicSystem(
      enabled: map['dynamicSystemEnabled'] ?? false,
      profile: TransducerProfile.values.firstWhere(
        (e) => e.value == (map['dynamicSystemProfile'] ?? 0),
        orElse: () => TransducerProfile.earphone,
      ),
      strength: (map['dynamicSystemStrength'] as num?)?.toDouble() ?? 0.5,
    );

    // 4. Analog Warmth
    player.setAnalogWarmth(
      enabled: map['analogWarmthEnabled'] ?? false,
      profile: AnalogWarmthProfile.values.firstWhere(
        (e) => e.value == (map['analogWarmthProfile'] ?? 0),
        orElse: () => AnalogWarmthProfile.triode12AX7,
      ),
      drive: (map['analogWarmthDrive'] as num?)?.toDouble() ?? 0.5,
    );

    // 5. FFT Convolver
    final bool convolverEnabled = map['convolverEnabled'] ?? false;
    player.setConvolverEnabled(convolverEnabled);
    player.setConvolverMix(
      wet: (map['convolverWet'] as num?)?.toDouble() ?? 1.0,
      dry: (map['convolverDry'] as num?)?.toDouble() ?? 0.0,
    );
    final String? irPath = map['convolverIrPath'] as String?;
    if (convolverEnabled && irPath != null && irPath.isNotEmpty && File(irPath).existsSync()) {
      player.loadConvolverIr(irPath);
    }

    // 6. Master Peak Limiter
    player.setMasterLimiter(
      enabled: map['limiterEnabled'] ?? false,
      ceilingDb: (map['limiterCeilingDb'] as num?)?.toDouble() ?? -0.1,
      outputGainDb: (map['limiterOutputGainDb'] as num?)?.toDouble() ?? 0.0,
      releaseMs: (map['limiterReleaseMs'] as num?)?.toDouble() ?? 60.0,
    );
  }

  @override
  State<SautiDspScreen> createState() => _SautiDspScreenState();
}

class _SautiDspScreenState extends State<SautiDspScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loaded = false;

  // Master switch
  bool _dspMasterEnabled = true;

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

  // 6. Master Peak Limiter
  bool _limiterEnabled = false;
  double _limiterCeilingDb = -0.1;
  double _limiterOutputGainDb = 0.0;
  double _limiterReleaseMs = 60.0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final map = await AppStateService.instance.loadSautiDspState();
    if (mounted) {
      setState(() {
        _dspMasterEnabled = map['dspMasterEnabled'] ?? true;

        // Clarity
        _clarityEnabled = map['clarityEnabled'] ?? false;
        _clarityProfile = AudioClarityProfile.values.firstWhere(
          (e) => e.value == (map['clarityProfile'] ?? 0),
          orElse: () => AudioClarityProfile.transientCrisp,
        );
        _clarityIntensity = (map['clarityIntensity'] as num?)?.toDouble() ?? 0.5;

        // Bass
        _bassEnabled = map['bassEnabled'] ?? false;
        _bassProfile = HarmonicBassProfile.values.firstWhere(
          (e) => e.value == (map['bassProfile'] ?? 0),
          orElse: () => HarmonicBassProfile.subBassResonant,
        );
        _bassCutoffHz = (map['bassCutoffHz'] as num?)?.toDouble() ?? 60.0;
        _bassBoost = (map['bassBoost'] as num?)?.toDouble() ?? 0.5;

        // Dynamic System
        _dynamicSystemEnabled = map['dynamicSystemEnabled'] ?? false;
        _dynamicSystemProfile = TransducerProfile.values.firstWhere(
          (e) => e.value == (map['dynamicSystemProfile'] ?? 0),
          orElse: () => TransducerProfile.earphone,
        );
        _dynamicSystemStrength = (map['dynamicSystemStrength'] as num?)?.toDouble() ?? 0.5;

        // Analog Warmth
        _analogWarmthEnabled = map['analogWarmthEnabled'] ?? false;
        _analogWarmthProfile = AnalogWarmthProfile.values.firstWhere(
          (e) => e.value == (map['analogWarmthProfile'] ?? 0),
          orElse: () => AnalogWarmthProfile.triode12AX7,
        );
        _analogWarmthDrive = (map['analogWarmthDrive'] as num?)?.toDouble() ?? 0.5;

        // Convolver
        _convolverEnabled = map['convolverEnabled'] ?? false;
        _convolverIrPath = map['convolverIrPath'] as String?;
        if (_convolverIrPath != null && _convolverIrPath!.isNotEmpty) {
          _convolverIrFileName = p.basename(_convolverIrPath!);
        }
        _convolverWet = (map['convolverWet'] as num?)?.toDouble() ?? 1.0;
        _convolverDry = (map['convolverDry'] as num?)?.toDouble() ?? 0.0;

        // Master Limiter
        _limiterEnabled = map['limiterEnabled'] ?? false;
        _limiterCeilingDb = (map['limiterCeilingDb'] as num?)?.toDouble() ?? -0.1;
        _limiterOutputGainDb = (map['limiterOutputGainDb'] as num?)?.toDouble() ?? 0.0;
        _limiterReleaseMs = (map['limiterReleaseMs'] as num?)?.toDouble() ?? 60.0;

        _loaded = true;
      });
    }
  }

  Map<String, dynamic> _toMap() {
    return {
      'dspMasterEnabled': _dspMasterEnabled,
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
      'limiterEnabled': _limiterEnabled,
      'limiterCeilingDb': _limiterCeilingDb,
      'limiterOutputGainDb': _limiterOutputGainDb,
      'limiterReleaseMs': _limiterReleaseMs,
    };
  }

  void _saveAndApply() {
    final state = _toMap();
    AppStateService.instance.saveSautiDspState(state);
    if (!_dspMasterEnabled) {
      widget.player.setClarity(enabled: false);
      widget.player.setHarmonicBass(enabled: false);
      widget.player.setDynamicSystem(enabled: false);
      widget.player.setAnalogWarmth(enabled: false);
      widget.player.setConvolverEnabled(false);
      widget.player.setMasterLimiter(enabled: false);
      return;
    }

    widget.player.setClarity(
      enabled: _clarityEnabled,
      profile: _clarityProfile,
      intensity: _clarityIntensity,
    );

    widget.player.setHarmonicBass(
      enabled: _bassEnabled,
      profile: _bassProfile,
      cutoffHz: _bassCutoffHz,
      boost: _bassBoost,
    );

    widget.player.setDynamicSystem(
      enabled: _dynamicSystemEnabled,
      profile: _dynamicSystemProfile,
      strength: _dynamicSystemStrength,
    );

    widget.player.setAnalogWarmth(
      enabled: _analogWarmthEnabled,
      profile: _analogWarmthProfile,
      drive: _analogWarmthDrive,
    );

    widget.player.setConvolverEnabled(_convolverEnabled);
    widget.player.setConvolverMix(wet: _convolverWet, dry: _convolverDry);
    if (_convolverEnabled && _convolverIrPath != null && _convolverIrPath!.isNotEmpty) {
      widget.player.loadConvolverIr(_convolverIrPath!);
    }

    widget.player.setMasterLimiter(
      enabled: _limiterEnabled,
      ceilingDb: _limiterCeilingDb,
      outputGainDb: _limiterOutputGainDb,
      releaseMs: _limiterReleaseMs,
    );
  }

  Future<void> _pickImpulseResponse() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _convolverIrPath = path;
          _convolverIrFileName = p.basename(path);
          _convolverEnabled = true;
        });
        _saveAndApply();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load acoustic file: $e')),
        );
      }
    }
  }

  void _resetDsp() {
    widget.player.resetDsp();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All sound effects have been reset.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final primaryColor = context.primaryColor;
    final surfaceColor = context.cardDark;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header: Master Switch & Reset ─────────────────────────────────
          _buildMasterHeader(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 1. Audio Clarity Engine ───────────────────────────────────────
          _buildClarityCard(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 2. Harmonic Bass Engine ───────────────────────────────────────
          _buildHarmonicBassCard(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 3. Dynamic Transducer Correction ──────────────────────────────
          _buildDynamicSystemCard(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 4. Analog Warmth (Tube & Tape) ────────────────────────────────
          _buildAnalogWarmthCard(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 5. Partitioned FFT Convolver ──────────────────────────────────
          _buildConvolverCard(primaryColor, surfaceColor),
          const SizedBox(height: 16),

          // ─── 6. Master Peak Limiter ────────────────────────────────────────
          _buildMasterLimiterCard(primaryColor, surfaceColor),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Master Header ─────────────────────────────────────────────────────────
  Widget _buildMasterHeader(Color primaryColor, Color surfaceColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _dspMasterEnabled ? primaryColor.withValues(alpha: 0.5) : Colors.white10,
          width: 1.2,
        ),
        boxShadow: _dspMasterEnabled
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _dspMasterEnabled
                      ? primaryColor.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: _dspMasterEnabled ? primaryColor : Colors.white54,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sauti Studio Audio FX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    _dspMasterEnabled ? 'Studio Enhancements Active' : 'All Sound Effects Off',
                    style: TextStyle(
                      color: _dspMasterEnabled ? primaryColor : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: 'Reset All Effects',
                onPressed: _resetDsp,
              ),
              M3ESwitch(
                value: _dspMasterEnabled,
                onChanged: (val) {
                  setState(() => _dspMasterEnabled = val);
                  _saveAndApply();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 1. Clarity & Vocals Card ───────────────────────────────────────────────
  Widget _buildClarityCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Clarity & Vocal Enhancer',
      subtitle: 'Brings out crisp details, vocal presence & high-end sparkle',
      icon: Icons.graphic_eq_rounded,
      enabled: _clarityEnabled,
      onToggle: (v) {
        setState(() => _clarityEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSelector<AudioClarityProfile>(
            label: 'Clarity Style',
            selectedValue: _clarityProfile,
            items: const [
              (AudioClarityProfile.transientCrisp, 'Crisp & Detailed (Fast Transients)'),
              (AudioClarityProfile.airShelf, 'Air & Sparkle (Top-End Sheen)'),
              (AudioClarityProfile.presenceExciter, 'Vocal Presence (Forward & Intelligible)'),
              (AudioClarityProfile.harmonicBrilliance, 'Studio Brilliance (Bright & Open)'),
            ],
            onChanged: (p) {
              if (p == null) return;
              setState(() => _clarityProfile = p);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: 'Clarity Amount',
            value: _clarityIntensity,
            displayValue: '${(_clarityIntensity * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _clarityIntensity = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── 2. Deep Bass & Subwoofer Card ─────────────────────────────────────────
  Widget _buildHarmonicBassCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Deep Bass & Subwoofer',
      subtitle: 'Clean mono bass injection, kick punch & subwoofer power',
      icon: Icons.speaker_group_rounded,
      enabled: _bassEnabled,
      onToggle: (v) {
        setState(() => _bassEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSelector<HarmonicBassProfile>(
            label: 'Bass Character',
            selectedValue: _bassProfile,
            items: const [
              (HarmonicBassProfile.naturalBass, 'Natural Bass (Smooth & Clean)'),
              (HarmonicBassProfile.pureBass, 'Punchy Kick (Tight Drums & Beats)'),
              (HarmonicBassProfile.subwoofer, 'Subwoofer Rumble (Deep Low-End)'),
              (HarmonicBassProfile.harmonicExciter, 'Earbud / Small Speaker Bass (Harmonic)'),
              (HarmonicBassProfile.pultecDeep, 'Deep Sub & Anti-Mud (Pultec Studio)'),
            ],
            onChanged: (p) {
              if (p == null) return;
              setState(() => _bassProfile = p);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: 'Bass Focus Frequency',
            value: _bassCutoffHz,
            displayValue: '${_bassCutoffHz.toInt()} Hz',
            min: 30.0,
            max: 160.0,
            onChanged: (v) {
              setState(() => _bassCutoffHz = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 10),
          _buildSliderRow(
            label: 'Bass Power',
            value: _bassBoost,
            displayValue: '${(_bassBoost * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _bassBoost = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── 3. Headphone & Speaker Optimizer Card ─────────────────────────────────
  Widget _buildDynamicSystemCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Device & Headphone Optimizer',
      subtitle: 'Tailors sound dynamics and crossover to your listening gear',
      icon: Icons.headphones_rounded,
      enabled: _dynamicSystemEnabled,
      onToggle: (v) {
        setState(() => _dynamicSystemEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSelector<TransducerProfile>(
            label: 'Your Listening Device',
            selectedValue: _dynamicSystemProfile,
            items: const [
              (TransducerProfile.earphone, 'In-Ear Earbuds (Punchy & Open Sound)'),
              (TransducerProfile.headphone, 'Over-Ear Headphones (Warm & Spacious)'),
              (TransducerProfile.highEndReference, 'Studio / Audiophile (Accurate & Flat)'),
              (TransducerProfile.speakerMonitor, 'Desktop & Portable Speakers (Excursion Safe)'),
              (TransducerProfile.extremeSubwoofer, 'Club & Basshead Subwoofer (Massive Impact)'),
              (TransducerProfile.pureDynamic, 'Punchy Dynamic (Energetic & Lively)'),
            ],
            onChanged: (p) {
              if (p == null) return;
              setState(() => _dynamicSystemProfile = p);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: 'Optimization Strength',
            value: _dynamicSystemStrength,
            displayValue: '${(_dynamicSystemStrength * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _dynamicSystemStrength = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── 4. Warmth & Vintage Sound Card ────────────────────────────────────────
  Widget _buildAnalogWarmthCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Analog Warmth & Color',
      subtitle: 'Adds rich analog harmonics, velvety depth & vintage character',
      icon: Icons.album_rounded,
      enabled: _analogWarmthEnabled,
      onToggle: (v) {
        setState(() => _analogWarmthEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSelector<AnalogWarmthProfile>(
            label: 'Warmth Flavor',
            selectedValue: _analogWarmthProfile,
            items: const [
              (AnalogWarmthProfile.triode12AX7, 'Vacuum Tube Amp (12AX7 Smooth Warmth)'),
              (AnalogWarmthProfile.magneticTape, 'Vintage Reel-to-Reel Tape (Soft & Silky)'),
              (AnalogWarmthProfile.vintagePreamp, 'Studio Console Preamp (Punchy Body)'),
            ],
            onChanged: (p) {
              if (p == null) return;
              setState(() => _analogWarmthProfile = p);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: 'Warmth Amount',
            value: _analogWarmthDrive,
            displayValue: '${(_analogWarmthDrive * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _analogWarmthDrive = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── 5. Room & Acoustic Space Convolver Card ───────────────────────────────
  Widget _buildConvolverCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Acoustic Space & Convolver',
      subtitle: 'Simulate playing inside real concert halls, rooms, or custom acoustics',
      icon: Icons.waves_rounded,
      enabled: _convolverEnabled,
      onToggle: (v) {
        setState(() => _convolverEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File Picker / Status Area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _convolverIrFileName ?? 'No Acoustic File Loaded',
                        style: TextStyle(
                          color: _convolverIrFileName != null ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _convolverIrPath != null ? 'Active Acoustic Simulation' : 'Select a .wav room impulse response file',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_convolverIrPath != null)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Clear File',
                    onPressed: () {
                      setState(() {
                        _convolverIrPath = null;
                        _convolverIrFileName = null;
                        _convolverEnabled = false;
                      });
                      widget.player.clearConvolverIr();
                      _saveAndApply();
                    },
                  ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Browse'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor.withValues(alpha: 0.25),
                    foregroundColor: primaryColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: _pickImpulseResponse,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: 'Room Acoustic Mix',
            value: _convolverWet,
            displayValue: '${(_convolverWet * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _convolverWet = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 10),
          _buildSliderRow(
            label: 'Original Audio Mix',
            value: _convolverDry,
            displayValue: '${(_convolverDry * 100).toInt()}%',
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _convolverDry = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── 6. Volume & Distortion Shield ─────────────────────────────────────────
  Widget _buildMasterLimiterCard(Color primaryColor, Color surfaceColor) {
    return _buildSectionCard(
      title: 'Volume & Distortion Shield',
      subtitle: 'Prevents clipping distortion and boosts loudness safely',
      icon: Icons.shield_rounded,
      enabled: _limiterEnabled,
      onToggle: (v) {
        setState(() => _limiterEnabled = v);
        _saveAndApply();
      },
      primaryColor: primaryColor,
      surfaceColor: surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSliderRow(
            label: 'Max Volume Ceiling',
            value: _limiterCeilingDb,
            displayValue: '${_limiterCeilingDb.toStringAsFixed(1)} dBFS',
            min: -12.0,
            max: 0.0,
            onChanged: (v) {
              setState(() => _limiterCeilingDb = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 10),
          _buildSliderRow(
            label: 'Loudness Boost',
            value: _limiterOutputGainDb,
            displayValue: '${_limiterOutputGainDb > 0 ? '+' : ''}${_limiterOutputGainDb.toStringAsFixed(1)} dB',
            min: -24.0,
            max: 12.0,
            onChanged: (v) {
              setState(() => _limiterOutputGainDb = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
          const SizedBox(height: 10),
          _buildSliderRow(
            label: 'Smooth Recovery Speed',
            value: _limiterReleaseMs,
            displayValue: '${_limiterReleaseMs.toInt()} ms',
            min: 5.0,
            max: 500.0,
            onChanged: (v) {
              setState(() => _limiterReleaseMs = v);
              _saveAndApply();
            },
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  // ─── Helper Builders ───────────────────────────────────────────────────────
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Color primaryColor,
    required Color surfaceColor,
    required Widget child,
  }) {
    final effectiveEnabled = _dspMasterEnabled && enabled;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: effectiveEnabled ? primaryColor.withValues(alpha: 0.4) : Colors.white10,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: effectiveEnabled ? primaryColor : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: effectiveEnabled ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                M3ESwitch(
                  value: enabled,
                  onChanged: _dspMasterEnabled ? onToggle : null,
                ),
              ],
            ),
          ),
          if (enabled && _dspMasterEnabled) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSelector<T>({
    required String label,
    required T selectedValue,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
    required Color primaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: selectedValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E2230),
              icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item.$1,
                      child: Text(
                        item.$2,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required String displayValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color primaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              displayValue,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        M3ESlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
