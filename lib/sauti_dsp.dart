import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'audio_engine_ffi.dart';

/// Audio Clarity DSP profiles.
enum AudioClarityProfile {
  transientCrisp(0),
  airShelf(1),
  presenceExciter(2),
  harmonicBrilliance(3);

  final int value;
  const AudioClarityProfile(this.value);
}

/// Dynamic Bass & Subwoofer DSP profiles.
enum HarmonicBassProfile {
  naturalBass(0),
  pureBass(1),
  subwoofer(2),
  harmonicExciter(3),
  pultecDeep(4),
  dynamicMultiPole(5);

  // Backward-compatible aliases
  static const HarmonicBassProfile subBassResonant = naturalBass;
  static const HarmonicBassProfile punchyBass = pureBass;

  final int value;
  const HarmonicBassProfile(this.value);
}

/// 19 Pre-tuned hardware & acoustic Dynamic Bass presets.
enum DynamicBassPreset {
  smoothNaturalSub(0, 'Smooth Natural Sub'),
  punchyInEar(1, 'Punchy In-Ear'),
  warmOverEar(2, 'Warm Over-Ear'),
  deepAcoustic(3, 'Deep Acoustic'),
  wideDynamic(4, 'Wide Dynamic'),
  subBassBoom(5, 'Sub-Bass Boom'),
  tightSub(6, 'Tight Sub'),
  solidImpact(7, 'Solid Impact'),
  cleanKick(8, 'Clean Kick'),
  richLowEnd(9, 'Rich Low-End'),
  clubPaPunch(10, 'Club PA Punch'),
  bassheadHeavy(11, 'Basshead Heavy'),
  resonantRumble(12, 'Resonant Rumble'),
  cinemaSub(13, 'Cinema Sub'),
  carAudioSlam(14, 'Car Audio Slam'),
  audiophileReference(15, 'Audiophile Reference'),
  studioMonitorLows(16, 'Studio Monitor Lows'),
  deepSubExtension(17, 'Deep Sub Extension'),
  ultimateSubwoofer(18, 'Ultimate Subwoofer');

  final int value;
  final String label;
  const DynamicBassPreset(this.value, this.label);
}

/// Dynamic Transducer profiles.
enum TransducerProfile {
  earphone(0, 'Earbuds'), // friendly naming
  headphone(1, 'Headphones'),
  highEndReference(2, 'Reference'),
  speakerMonitor(3, 'Speakers'),
  extremeSubwoofer(4, 'Subwoofer'),
  pureDynamic(5, 'Pure'),
  audiophileReference(6, 'Audiophile'),
  studioMonitorLows(7, 'Monitors'),
  cinemaSubSlam(8, 'Cinema'),
  carAudioBass(9, 'Car'),
  deepAcousticWarmth(10, 'Acoustic'),
  cleanKickDrum(11, 'Kick'),
  resonantRumble(12, 'Resonant'),
  subBassBoom(13, 'Sub-Bass'),
  solidImpact(14, 'Solid'),
  richLowEnd(15, 'Rich'),
  clubPAPunch(16, 'Club'),
  deepSubExtension(17, 'Deep'),
  ultimateSubwoofer(18, 'Ultimate');

  final int value;
  final String label;
  const TransducerProfile(this.value, [this.label = '']);
}

/// Analog Warmth profiles.
enum AnalogWarmthProfile {
  triode12AX7(0),
  magneticTape(1),
  vintagePreamp(2);

  final int value;
  const AnalogWarmthProfile(this.value);
}

/// Dialogue Booster & Enhancer profiles (reconstructed from Dolby DAP).
enum DialogEnhancerProfile {
  cinema(0, 'Cinema'),
  music(1, 'Music'),
  voice(2, 'Voice'),
  night(3, 'Night'),
  custom(4, 'Custom');

  final int value;
  final String label;
  const DialogEnhancerProfile(this.value, [this.label = '']);
}

/// De-Esser operating modes.
enum DeEsserMode {
  splitBand(0),
  wideBand(1);

  final int value;
  const DeEsserMode(this.value);
}

/// De-Esser presets.
enum DeEsserPreset {
  gentleVocal(0),
  aggressiveSibilance(1),
  vintageWideband(2),
  podcastSpeech(3),
  custom(4);

  final int value;
  const DeEsserPreset(this.value);
}

/// Downward Expander & Noise Floor Reducer presets.
enum DownwardExpanderPreset {
  vinylClean(0),
  tapeHiss(1),
  gentleExpansion(2),
  dynamicGate(3),
  custom(4);

  final int value;
  const DownwardExpanderPreset(this.value);
}

/// Spatial Surround suite modes.
enum SurroundMode {
  off(0),
  matrixSurround(1), // Cinema Matrix 5.1 (Pro Logic II cleanroom)
  binauralVirtualizer(2), // Reconstructed from Dolby analysis_dlby2
  acousticStage(3); // Reconstructed from AM3D Zirene re_workspace

  final int value;
  const SurroundMode(this.value);

  // Backward-compatibility aliases
  static const SurroundMode matrix51Hrtf = SurroundMode.matrixSurround;
  static const SurroundMode fieldExpander = SurroundMode.acousticStage;
  static const SurroundMode differentialHaas = SurroundMode.acousticStage;
  static const SurroundMode viperHeadphone = SurroundMode.binauralVirtualizer;
}

/// Dynamic Equalizer filter types.
enum DynamicEqFilterType {
  peak(0),
  lowShelf(1),
  highShelf(2);

  final int value;
  const DynamicEqFilterType(this.value);
}

/// Dynamic Equalizer operating modes.
enum DynamicEqMode {
  staticMode(0),
  compress(1),
  expand(2);

  final int value;
  const DynamicEqMode(this.value);
}

/// Vintage Tape Wow, Flutter & Drift presets.
enum TapeDriftPreset {
  subtleHiFi(0),
  vintageReelToReel(1),
  warpedVinyl(2),
  cassetteLoFi(3),
  custom(4);

  final int value;
  const TapeDriftPreset(this.value);
}

// Native FFI Typedefs
typedef _DspSetEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetSurroundModeNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetSurroundModeDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetClarityParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetClarityParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetBassParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float);
typedef _DspSetBassParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double);

typedef _DspSetDynamicBassParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetDynamicBassParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDynamicSystemParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetDynamicSystemParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDynamicSystemCustomParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetDynamicSystemCustomParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    double,
    double,
    double,
    double,
    double,
    double,
    double);

typedef _DspSetAnalogWarmthParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetAnalogWarmthParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDialogEnhancerParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetDialogEnhancerParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double, double, double);

typedef _DspGetDialogEnhancerGainReductionDbNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetDialogEnhancerGainReductionDbDart = double Function(
    ffi.Pointer<ffi.Void>);

typedef _DspSetDeEsserPresetNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetDeEsserPresetDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetDeEsserParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetDeEsserParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDeEsserParamsExNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetDeEsserParamsExDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double, double, double, double, double);

typedef _DspGetDeEsserGainReductionDbNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetDeEsserGainReductionDbDart = double Function(
    ffi.Pointer<ffi.Void>);

typedef _DspSetExpanderPresetNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetExpanderPresetDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetExpanderParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetExpanderParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double, double);

typedef _DspSetExpanderParamsExNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetExpanderParamsExDart = void Function(ffi.Pointer<ffi.Void>,
    double, double, double, double, double, double, double);

typedef _DspGetExpanderGainReductionDbNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetExpanderGainReductionDbDart = double Function(
    ffi.Pointer<ffi.Void>);

typedef _DspLoadConvolverIrNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32);
typedef _DspLoadConvolverIrDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, int, int);

typedef _DspClearConvolverIrNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DspClearConvolverIrDart = void Function(ffi.Pointer<ffi.Void>);

typedef _DspSetConvolverMixNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float);
typedef _DspSetConvolverMixDart = void Function(
    ffi.Pointer<ffi.Void>, double, double);

typedef _DspSetMasterLimiterParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetMasterLimiterParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double);

typedef _DspResetNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DspResetDart = void Function(ffi.Pointer<ffi.Void>);

typedef _DspHasConvolverIrNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _DspHasConvolverIrDart = int Function(ffi.Pointer<ffi.Void>);

typedef _DspGetConvolverKernelLengthNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetConvolverKernelLengthDart = int Function(ffi.Pointer<ffi.Void>);

typedef _DspGetLimiterGainReductionDbNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetLimiterGainReductionDbDart = double Function(
    ffi.Pointer<ffi.Void>);

typedef _DspSetSurroundParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetSurroundParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double);

typedef _DspSetSurroundMatrixParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetSurroundMatrixParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double);

typedef _DspSetSurroundBinauralParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Float,
    ffi.Int32,
    ffi.Float,
    ffi.Int32,
    ffi.Float);
typedef _DspSetSurroundBinauralParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, int, double, int, double);

typedef _DspSetSurroundStageParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Int32,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetSurroundStageParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, int, double, double, double, double, double);

typedef _DspSetSurroundParamsExNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float, // field: width, crossover, diffuser, bass anchor
    ffi.Float,
    ffi.Float,
    ffi.Float, // haas: delay, depth, damping
    ffi.Int32,
    ffi.Float,
    ffi.Float, // vhs: preset, reflection gain, damping
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float // matrix: center focus, boost, rear delay, head radius
    );
typedef _DspSetSurroundParamsExDart = void Function(
    ffi.Pointer<ffi.Void>,
    double,
    double,
    double,
    double,
    double,
    double,
    double,
    int,
    double,
    double,
    double,
    double,
    double,
    double);

typedef _DspSetDynamicLoudnessParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetDynamicLoudnessParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double, double);

typedef _DspGetDynamicLoudnessParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);
typedef _DspGetDynamicLoudnessParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);

typedef _DspGetDynamicLoudnessCurrentBoostNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);
typedef _DspGetDynamicLoudnessCurrentBoostDart = void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);

typedef _DspSetNoiseGateParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetNoiseGateParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double, double, double);

typedef _DspGetNoiseGateParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);
typedef _DspGetNoiseGateParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);

typedef _DspSetLevellerParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetLevellerParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double, double, double);

typedef _DspGetLevellerParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);
typedef _DspGetLevellerParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);

typedef _DspSetDynamicEqBandNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Int32);
typedef _DspSetDynamicEqBandDart = void Function(
    ffi.Pointer<ffi.Void>,
    int,
    int,
    int,
    double,
    double,
    double,
    double,
    double,
    double,
    double,
    double,
    int);

typedef _DspGetDynamicEqBandNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Int32>);
typedef _DspGetDynamicEqBandDart = void Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Int32>);

typedef _DspGetDynamicEqBandGainOffsetDbNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspGetDynamicEqBandGainOffsetDbDart = double Function(
    ffi.Pointer<ffi.Void>, int);

typedef _DspSetTapeDriftParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float);
typedef _DspSetTapeDriftParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    double,
    double,
    double,
    double,
    double,
    double,
    double);

typedef _DspGetTapeDriftParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);
typedef _DspGetTapeDriftParamsDart = void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>);

typedef _DspSetTapeDriftPresetNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetTapeDriftPresetDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspGetTapeDriftPresetNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>);
typedef _DspGetTapeDriftPresetDart = int Function(ffi.Pointer<ffi.Void>);

/// Clean-room high-fidelity DSP suite for SautiFlow.
class SautiDsp {
  final ffi.DynamicLibrary _lib;
  final ffi.Pointer<ffi.Void> _enginePtr;

  late final _DspResetDart _reset;

  late final _DspSetEnabledDart _setClarityEnabled;
  late final _DspSetClarityParamsDart _setClarityParams;

  late final _DspSetEnabledDart _setBassEnabled;
  late final _DspSetBassParamsDart _setBassParams;

  late final _DspSetEnabledDart _setDynamicBassEnabled;
  late final _DspSetDynamicBassParamsDart _setDynamicBassParams;

  late final _DspSetEnabledDart _setDynamicSystemEnabled;
  late final _DspSetDynamicSystemParamsDart _setDynamicSystemParams;
  late final _DspSetDynamicSystemCustomParamsDart _setDynamicSystemCustomParams;

  late final _DspSetEnabledDart _setAnalogWarmthEnabled;
  late final _DspSetAnalogWarmthParamsDart _setAnalogWarmthParams;

  late final _DspSetEnabledDart _setDialogEnhancerEnabled;
  late final _DspSetDialogEnhancerParamsDart _setDialogEnhancerParams;
  late final _DspGetDialogEnhancerGainReductionDbDart
      _getDialogEnhancerGainReductionDb;

  late final _DspSetEnabledDart _setDeEsserEnabled;
  late final _DspSetDeEsserPresetDart _setDeEsserPreset;
  late final _DspSetDeEsserParamsDart _setDeEsserParams;
  late final _DspSetDeEsserParamsExDart _setDeEsserParamsEx;
  late final _DspGetDeEsserGainReductionDbDart _getDeEsserGainReductionDb;

  late final _DspSetEnabledDart _setExpanderEnabled;
  late final _DspSetExpanderPresetDart _setExpanderPreset;
  late final _DspSetExpanderParamsDart _setExpanderParams;
  late final _DspSetExpanderParamsExDart _setExpanderParamsEx;
  late final _DspGetExpanderGainReductionDbDart _getExpanderGainReductionDb;

  late final _DspSetEnabledDart _setConvolverEnabled;
  late final _DspLoadConvolverIrDart _loadConvolverIr;
  late final _DspClearConvolverIrDart _clearConvolverIr;
  late final _DspSetConvolverMixDart _setConvolverMix;
  late final _DspHasConvolverIrDart _hasConvolverIr;
  late final _DspGetConvolverKernelLengthDart _getConvolverKernelLength;

  late final _DspSetEnabledDart _setMasterLimiterEnabled;
  late final _DspSetMasterLimiterParamsDart _setMasterLimiterParams;
  late final _DspGetLimiterGainReductionDbDart _getLimiterGainReductionDb;

  late final _DspSetEnabledDart _setSurroundEnabled;
  late final _DspSetSurroundModeDart _setSurroundMode;
  late final _DspSetSurroundParamsDart _setSurroundParams;
  late final _DspSetSurroundMatrixParamsDart _setSurroundMatrixParams;
  late final _DspSetSurroundBinauralParamsDart _setSurroundBinauralParams;
  late final _DspSetSurroundStageParamsDart _setSurroundStageParams;
  late final _DspSetSurroundParamsExDart _setSurroundParamsEx;
  late final _DspSetEnabledDart _setSubsonicFilterEnabled;
  late final _DspHasConvolverIrDart _getSubsonicFilterEnabled;
  late final _DspSetEnabledDart _setDynamicLoudnessEnabled;
  late final _DspHasConvolverIrDart _getDynamicLoudnessEnabled;
  late final _DspSetDynamicLoudnessParamsDart _setDynamicLoudnessParams;
  late final _DspGetDynamicLoudnessParamsDart _getDynamicLoudnessParams;
  late final _DspGetDynamicLoudnessCurrentBoostDart _getDynamicLoudnessCurrentBoost;

  late final _DspSetEnabledDart _setNoiseGateEnabled;
  late final _DspHasConvolverIrDart _getNoiseGateEnabled;
  late final _DspSetNoiseGateParamsDart _setNoiseGateParams;
  late final _DspGetNoiseGateParamsDart _getNoiseGateParams;
  late final _DspGetDialogEnhancerGainReductionDbDart _getNoiseGateGainReductionDb;

  late final _DspSetEnabledDart _setLevellerEnabled;
  late final _DspHasConvolverIrDart _getLevellerEnabled;
  late final _DspSetLevellerParamsDart _setLevellerParams;
  late final _DspGetLevellerParamsDart _getLevellerParams;
  late final _DspGetDialogEnhancerGainReductionDbDart _getLevellerCurrentGainDb;

  late final _DspSetEnabledDart _setDynamicEqEnabled;
  late final _DspHasConvolverIrDart _getDynamicEqEnabled;
  late final _DspSetDynamicEqBandDart _setDynamicEqBand;
  late final _DspGetDynamicEqBandDart _getDynamicEqBand;
  late final _DspGetDynamicEqBandGainOffsetDbDart _getDynamicEqBandGainOffsetDb;

  late final _DspSetEnabledDart _setTapeDriftEnabled;
  late final _DspHasConvolverIrDart _getTapeDriftEnabled;
  late final _DspSetTapeDriftParamsDart _setTapeDriftParams;
  late final _DspGetTapeDriftParamsDart _getTapeDriftParams;
  late final _DspSetTapeDriftPresetDart _setTapeDriftPreset;
  late final _DspGetTapeDriftPresetDart _getTapeDriftPreset;

  SautiDsp(this._lib, this._enginePtr) {
    _initFunctions();
  }

  SautiDsp.fromEngine(AudioEngineFFI engine)
      : _lib = engine.library,
        _enginePtr = engine.enginePointer {
    _initFunctions();
  }

  void _initFunctions() {
    _reset =
        _lib.lookupFunction<_DspResetNative, _DspResetDart>('ae_dsp_reset');

    _setClarityEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_clarity_enabled');
    _setClarityParams = _lib.lookupFunction<_DspSetClarityParamsNative,
        _DspSetClarityParamsDart>('ae_dsp_set_clarity_params');

    _setBassEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_bass_enabled');
    _setBassParams =
        _lib.lookupFunction<_DspSetBassParamsNative, _DspSetBassParamsDart>(
            'ae_dsp_set_bass_params');

    _setDynamicBassEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_set_dynamic_bass_enabled');
    _setDynamicBassParams = _lib.lookupFunction<_DspSetDynamicBassParamsNative,
        _DspSetDynamicBassParamsDart>('ae_set_dynamic_bass_params');

    _setDynamicSystemEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_dynamic_system_enabled');
    _setDynamicSystemParams = _lib.lookupFunction<
        _DspSetDynamicSystemParamsNative,
        _DspSetDynamicSystemParamsDart>('ae_dsp_set_dynamic_system_params');
    _setDynamicSystemCustomParams = _lib.lookupFunction<
            _DspSetDynamicSystemCustomParamsNative,
            _DspSetDynamicSystemCustomParamsDart>(
        'ae_dsp_set_dynamic_system_custom_params');

    _setAnalogWarmthEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_analog_warmth_enabled');
    _setAnalogWarmthParams = _lib.lookupFunction<
        _DspSetAnalogWarmthParamsNative,
        _DspSetAnalogWarmthParamsDart>('ae_dsp_set_analog_warmth_params');

    _setDialogEnhancerEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_dialog_enhancer_enabled');
    _setDialogEnhancerParams = _lib.lookupFunction<
        _DspSetDialogEnhancerParamsNative,
        _DspSetDialogEnhancerParamsDart>('ae_dsp_set_dialog_enhancer_params');
    _getDialogEnhancerGainReductionDb = _lib.lookupFunction<
            _DspGetDialogEnhancerGainReductionDbNative,
            _DspGetDialogEnhancerGainReductionDbDart>(
        'ae_dsp_get_dialog_enhancer_gain_reduction_db');

    _setDeEsserEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_de_esser_enabled');
    _setDeEsserPreset = _lib.lookupFunction<_DspSetDeEsserPresetNative,
        _DspSetDeEsserPresetDart>('ae_dsp_set_de_esser_preset');
    _setDeEsserParams = _lib.lookupFunction<_DspSetDeEsserParamsNative,
        _DspSetDeEsserParamsDart>('ae_dsp_set_de_esser_params');
    _setDeEsserParamsEx = _lib.lookupFunction<_DspSetDeEsserParamsExNative,
        _DspSetDeEsserParamsExDart>('ae_dsp_set_de_esser_params_ex');
    _getDeEsserGainReductionDb = _lib.lookupFunction<
            _DspGetDeEsserGainReductionDbNative,
            _DspGetDeEsserGainReductionDbDart>(
        'ae_dsp_get_de_esser_gain_reduction_db');

    _setExpanderEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_expander_enabled');
    _setExpanderPreset = _lib.lookupFunction<_DspSetExpanderPresetNative,
        _DspSetExpanderPresetDart>('ae_dsp_set_expander_preset');
    _setExpanderParams = _lib.lookupFunction<_DspSetExpanderParamsNative,
        _DspSetExpanderParamsDart>('ae_dsp_set_expander_params');
    _setExpanderParamsEx = _lib.lookupFunction<_DspSetExpanderParamsExNative,
        _DspSetExpanderParamsExDart>('ae_dsp_set_expander_params_ex');
    _getExpanderGainReductionDb = _lib.lookupFunction<
            _DspGetExpanderGainReductionDbNative,
            _DspGetExpanderGainReductionDbDart>(
        'ae_dsp_get_expander_gain_reduction_db');

    _setConvolverEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_convolver_enabled');
    _loadConvolverIr =
        _lib.lookupFunction<_DspLoadConvolverIrNative, _DspLoadConvolverIrDart>(
            'ae_dsp_load_convolver_ir');
    _clearConvolverIr = _lib.lookupFunction<_DspClearConvolverIrNative,
        _DspClearConvolverIrDart>('ae_dsp_clear_convolver_ir');
    _setConvolverMix =
        _lib.lookupFunction<_DspSetConvolverMixNative, _DspSetConvolverMixDart>(
            'ae_dsp_set_convolver_mix');
    _hasConvolverIr =
        _lib.lookupFunction<_DspHasConvolverIrNative, _DspHasConvolverIrDart>(
            'ae_dsp_has_convolver_ir');
    _getConvolverKernelLength = _lib.lookupFunction<
        _DspGetConvolverKernelLengthNative,
        _DspGetConvolverKernelLengthDart>('ae_dsp_get_convolver_kernel_length');

    _setMasterLimiterEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_master_limiter_enabled');
    _setMasterLimiterParams = _lib.lookupFunction<
        _DspSetMasterLimiterParamsNative,
        _DspSetMasterLimiterParamsDart>('ae_dsp_set_master_limiter_params');
    _getLimiterGainReductionDb = _lib.lookupFunction<
            _DspGetLimiterGainReductionDbNative,
            _DspGetLimiterGainReductionDbDart>(
        'ae_dsp_get_limiter_gain_reduction_db');

    _setSurroundEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_surround_enabled');
    _setSurroundMode =
        _lib.lookupFunction<_DspSetSurroundModeNative, _DspSetSurroundModeDart>(
            'ae_dsp_set_surround_mode');
    _setSurroundParams = _lib.lookupFunction<_DspSetSurroundParamsNative,
        _DspSetSurroundParamsDart>('ae_dsp_set_surround_params');
    _setSurroundMatrixParams = _lib.lookupFunction<
        _DspSetSurroundMatrixParamsNative,
        _DspSetSurroundMatrixParamsDart>('ae_dsp_set_surround_matrix_params');
    _setSurroundBinauralParams = _lib.lookupFunction<
            _DspSetSurroundBinauralParamsNative,
            _DspSetSurroundBinauralParamsDart>(
        'ae_dsp_set_surround_binaural_params');
    _setSurroundStageParams = _lib.lookupFunction<
        _DspSetSurroundStageParamsNative,
        _DspSetSurroundStageParamsDart>('ae_dsp_set_surround_stage_params');
    _setSurroundParamsEx = _lib.lookupFunction<_DspSetSurroundParamsExNative,
        _DspSetSurroundParamsExDart>('ae_dsp_set_surround_params_ex');
    _setSubsonicFilterEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_subsonic_filter_enabled');
    _getSubsonicFilterEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_subsonic_filter_enabled');
    _setDynamicLoudnessEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_dynamic_loudness_enabled');
    _getDynamicLoudnessEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_dynamic_loudness_enabled');
    _setDynamicLoudnessParams = _lib.lookupFunction<
        _DspSetDynamicLoudnessParamsNative,
        _DspSetDynamicLoudnessParamsDart>('ae_dsp_set_dynamic_loudness_params');
    _getDynamicLoudnessParams = _lib.lookupFunction<
        _DspGetDynamicLoudnessParamsNative,
        _DspGetDynamicLoudnessParamsDart>('ae_dsp_get_dynamic_loudness_params');
    _getDynamicLoudnessCurrentBoost = _lib.lookupFunction<
        _DspGetDynamicLoudnessCurrentBoostNative,
        _DspGetDynamicLoudnessCurrentBoostDart>('ae_dsp_get_dynamic_loudness_current_boost');

    _setNoiseGateEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_noise_gate_enabled');
    _getNoiseGateEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_noise_gate_enabled');
    _setNoiseGateParams = _lib.lookupFunction<
        _DspSetNoiseGateParamsNative,
        _DspSetNoiseGateParamsDart>('ae_dsp_set_noise_gate_params');
    _getNoiseGateParams = _lib.lookupFunction<
        _DspGetNoiseGateParamsNative,
        _DspGetNoiseGateParamsDart>('ae_dsp_get_noise_gate_params');
    _getNoiseGateGainReductionDb = _lib.lookupFunction<
        _DspGetDialogEnhancerGainReductionDbNative,
        _DspGetDialogEnhancerGainReductionDbDart>('ae_dsp_get_noise_gate_gain_reduction_db');

    _setLevellerEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_leveller_enabled');
    _getLevellerEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_leveller_enabled');
    _setLevellerParams = _lib.lookupFunction<
        _DspSetLevellerParamsNative,
        _DspSetLevellerParamsDart>('ae_dsp_set_leveller_params');
    _getLevellerParams = _lib.lookupFunction<
        _DspGetLevellerParamsNative,
        _DspGetLevellerParamsDart>('ae_dsp_get_leveller_params');
    _getLevellerCurrentGainDb = _lib.lookupFunction<
        _DspGetDialogEnhancerGainReductionDbNative,
        _DspGetDialogEnhancerGainReductionDbDart>('ae_dsp_get_leveller_current_gain_db');

    _setDynamicEqEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_dynamic_eq_enabled');
    _getDynamicEqEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_dynamic_eq_enabled');
    _setDynamicEqBand = _lib.lookupFunction<
        _DspSetDynamicEqBandNative,
        _DspSetDynamicEqBandDart>('ae_dsp_set_dynamic_eq_band');
    _getDynamicEqBand = _lib.lookupFunction<
        _DspGetDynamicEqBandNative,
        _DspGetDynamicEqBandDart>('ae_dsp_get_dynamic_eq_band');
    _getDynamicEqBandGainOffsetDb = _lib.lookupFunction<
        _DspGetDynamicEqBandGainOffsetDbNative,
        _DspGetDynamicEqBandGainOffsetDbDart>('ae_dsp_get_dynamic_eq_band_gain_offset_db');

    _setTapeDriftEnabled =
        _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>(
            'ae_dsp_set_tape_drift_enabled');
    _getTapeDriftEnabled = _lib.lookupFunction<_DspHasConvolverIrNative,
        _DspHasConvolverIrDart>('ae_dsp_get_tape_drift_enabled');
    _setTapeDriftParams = _lib.lookupFunction<
        _DspSetTapeDriftParamsNative,
        _DspSetTapeDriftParamsDart>('ae_dsp_set_tape_drift_params');
    _getTapeDriftParams = _lib.lookupFunction<
        _DspGetTapeDriftParamsNative,
        _DspGetTapeDriftParamsDart>('ae_dsp_get_tape_drift_params');
    _setTapeDriftPreset = _lib.lookupFunction<
        _DspSetTapeDriftPresetNative,
        _DspSetTapeDriftPresetDart>('ae_dsp_set_tape_drift_preset');
    _getTapeDriftPreset = _lib.lookupFunction<
        _DspGetTapeDriftPresetNative,
        _DspGetTapeDriftPresetDart>('ae_dsp_get_tape_drift_preset');
  }

  /// Reset all internal DSP buffers and history states.
  void reset() {
    if (_enginePtr == ffi.nullptr) return;
    _reset(_enginePtr);
  }

  /// Audio Clarity Engine.
  void setClarity(
      {required bool enabled,
      AudioClarityProfile profile = AudioClarityProfile.transientCrisp,
      double intensity = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setClarityEnabled(_enginePtr, enabled ? 1 : 0);
    _setClarityParams(_enginePtr, profile.value, intensity);
  }

  /// Harmonic Bass Engine.
  void setHarmonicBass(
      {required bool enabled,
      HarmonicBassProfile profile = HarmonicBassProfile.subBassResonant,
      double cutoffHz = 60.0,
      double boost = 1.0}) {
    if (_enginePtr == ffi.nullptr) return;
    _setBassEnabled(_enginePtr, enabled ? 1 : 0);
    _setBassParams(_enginePtr, profile.value, cutoffHz, boost);
  }

  /// Dynamic Multi-Pole Resonant Bass with 19 pre-tuned hardware & acoustic presets.
  void setDynamicBass({
    required bool enabled,
    DynamicBassPreset preset = DynamicBassPreset.ultimateSubwoofer,
    double gainDb = 15.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicBassEnabled(_enginePtr, enabled ? 1 : 0);
    _setDynamicBassParams(_enginePtr, preset.value, gainDb);
  }

  /// Dynamic Transducer Correction.
  void setDynamicSystem(
      {required bool enabled,
      TransducerProfile profile = TransducerProfile.earphone,
      double strength = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicSystemEnabled(_enginePtr, enabled ? 1 : 0);
    _setDynamicSystemParams(_enginePtr, profile.value, strength);
  }

  /// Dynamic Transducer Custom Multi-Band Parameters.
  void setDynamicSystemCustom({
    required bool enabled,
    required double xLow,
    required double xHigh,
    required double yLow,
    required double yHigh,
    required double sideGainLow,
    required double sideGainHigh,
    required double bassGain,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicSystemEnabled(_enginePtr, enabled ? 1 : 0);
    _setDynamicSystemCustomParams(
      _enginePtr,
      xLow,
      xHigh,
      yLow,
      yHigh,
      sideGainLow,
      sideGainHigh,
      bassGain,
    );
  }

  /// Analog Warmth (Triode Tube & Magnetic Tape saturation).
  void setAnalogWarmth(
      {required bool enabled,
      AnalogWarmthProfile profile = AnalogWarmthProfile.triode12AX7,
      double drive = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setAnalogWarmthEnabled(_enginePtr, enabled ? 1 : 0);
    _setAnalogWarmthParams(_enginePtr, profile.value, drive);
  }

  /// Dialogue Booster & Background Noise Ducking Engine (reconstructed from Dolby DAP).
  void setDialogEnhancer({
    required bool enabled,
    DialogEnhancerProfile profile = DialogEnhancerProfile.cinema,
    double amount = 0.65,
    double ducking = 0.55,
    double clarity = 0.60,
    double centerFocus = 0.70,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDialogEnhancerEnabled(_enginePtr, enabled ? 1 : 0);
    _setDialogEnhancerParams(
        _enginePtr, profile.value, amount, ducking, clarity, centerFocus);
  }

  /// Returns current dynamic background ducking attenuation in dB (negative value or 0.0).
  double getDialogEnhancerGainReductionDb() {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getDialogEnhancerGainReductionDb(_enginePtr);
  }

  /// Split-Band / Wideband De-Esser.
  void setDeEsser({
    required bool enabled,
    DeEsserMode mode = DeEsserMode.splitBand,
    double intensity = 0.5,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDeEsserEnabled(_enginePtr, enabled ? 1 : 0);
    _setDeEsserParams(_enginePtr, mode.value, intensity);
  }

  /// Sets De-Esser preset.
  void setDeEsserPreset(DeEsserPreset preset) {
    if (_enginePtr == ffi.nullptr) return;
    _setDeEsserPreset(_enginePtr, preset.value);
  }

  /// Full manual parameter tuning for De-Esser.
  void setDeEsserEx({
    required bool enabled,
    DeEsserMode mode = DeEsserMode.splitBand,
    double frequencyHz = 5500.0,
    double thresholdDb = -22.0,
    double ratio = 4.0,
    double maxReductionDb = 12.0,
    double attackMs = 1.0,
    double releaseMs = 35.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDeEsserEnabled(_enginePtr, enabled ? 1 : 0);
    _setDeEsserParamsEx(
      _enginePtr,
      mode.value,
      frequencyHz,
      thresholdDb,
      ratio,
      maxReductionDb,
      attackMs,
      releaseMs,
    );
  }

  /// Current real-time gain reduction of De-Esser in dB.
  double get deEsserGainReductionDb {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getDeEsserGainReductionDb(_enginePtr);
  }

  /// Downward Expander & Adaptive Noise Floor Reducer (ideal for vinyl/tape rips).
  void setDownwardExpander({
    required bool enabled,
    DownwardExpanderPreset preset = DownwardExpanderPreset.vinylClean,
    double? thresholdDb,
    double? ratio,
    double? rangeDb,
    double? attackMs,
    double? releaseMs,
    double? kneeDb,
    double? sidechainHpfHz,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setExpanderEnabled(_enginePtr, enabled ? 1 : 0);
    _setExpanderPreset(_enginePtr, preset.value);
    if (preset == DownwardExpanderPreset.custom ||
        thresholdDb != null ||
        ratio != null ||
        rangeDb != null ||
        attackMs != null ||
        releaseMs != null ||
        kneeDb != null ||
        sidechainHpfHz != null) {
      _setExpanderParamsEx(
        _enginePtr,
        thresholdDb ?? -52.0,
        ratio ?? 1.8,
        rangeDb ?? -16.0,
        attackMs ?? 12.0,
        releaseMs ?? 280.0,
        kneeDb ?? 6.0,
        sidechainHpfHz ?? 50.0,
      );
    }
  }

  /// Full manual parameter tuning for Downward Expander.
  void setDownwardExpanderEx({
    required bool enabled,
    double thresholdDb = -52.0,
    double ratio = 1.8,
    double rangeDb = -16.0,
    double attackMs = 12.0,
    double releaseMs = 280.0,
    double kneeDb = 6.0,
    double sidechainHpfHz = 50.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setExpanderEnabled(_enginePtr, enabled ? 1 : 0);
    _setExpanderParamsEx(
      _enginePtr,
      thresholdDb,
      ratio,
      rangeDb,
      attackMs,
      releaseMs,
      kneeDb,
      sidechainHpfHz,
    );
  }

  /// Compact parameter setter for Downward Expander.
  void setDownwardExpanderParams({
    required bool enabled,
    double thresholdDb = -52.0,
    double ratio = 1.8,
    double rangeDb = -16.0,
    double attackMs = 12.0,
    double releaseMs = 280.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setExpanderEnabled(_enginePtr, enabled ? 1 : 0);
    _setExpanderParams(
        _enginePtr, thresholdDb, ratio, rangeDb, attackMs, releaseMs);
  }

  /// Current real-time gain reduction of Downward Expander in dB.
  double get downwardExpanderGainReductionDb {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getExpanderGainReductionDb(_enginePtr);
  }

  /// Partitioned FFT Impulse Response Convolver.
  bool loadImpulseResponse(Float32List samples, int channels) {
    if (_enginePtr == ffi.nullptr || samples.isEmpty) return false;
    final frameCount = samples.length ~/ channels;
    final ptr = calloc<ffi.Float>(samples.length);
    final typedList = ptr.asTypedList(samples.length);
    typedList.setAll(0, samples);
    try {
      final res = _loadConvolverIr(_enginePtr, ptr, frameCount, channels);
      return res == 1;
    } finally {
      calloc.free(ptr);
    }
  }

  void setConvolverEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setConvolverEnabled(_enginePtr, enabled ? 1 : 0);
  }

  void clearImpulseResponse() {
    if (_enginePtr == ffi.nullptr) return;
    _clearConvolverIr(_enginePtr);
  }

  void setConvolverMix({double wet = 1.0, double dry = 0.0}) {
    if (_enginePtr == ffi.nullptr) return;
    _setConvolverMix(_enginePtr, wet, dry);
  }

  bool get hasImpulseResponse {
    if (_enginePtr == ffi.nullptr) return false;
    return _hasConvolverIr(_enginePtr) == 1;
  }

  int get convolverKernelLength {
    if (_enginePtr == ffi.nullptr) return 0;
    return _getConvolverKernelLength(_enginePtr);
  }

  /// Master Peak Limiter.
  void setMasterLimiter(
      {required bool enabled,
      double ceilingDb = -0.1,
      double outputGainDb = 0.0,
      double releaseMs = 60.0}) {
    if (_enginePtr == ffi.nullptr) return;
    _setMasterLimiterEnabled(_enginePtr, enabled ? 1 : 0);
    _setMasterLimiterParams(_enginePtr, ceilingDb, outputGainDb, releaseMs);
  }

  /// Sets master headroom trim in dB applied before the DSP processing chain.
  /// A negative value (e.g. -3.0 dB to -6.0 dB) provides clean headroom to prevent
  /// harmonic saturation or clipping when multiple DSP modules are active.
  void setMasterHeadroomTrimDb(double trimDb) {
    if (_enginePtr == ffi.nullptr) return;
    setMasterLimiter(enabled: true, ceilingDb: -0.1, outputGainDb: trimDb);
  }

  /// Get current limiter gain reduction in dB (for real-time meter display).
  double get limiterGainReductionDb {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getLimiterGainReductionDb(_enginePtr);
  }

  /// Spatial Surround Suite.
  ///
  /// [mode] selects the algorithm:
  ///  - [SurroundMode.matrixSurround]: Cinema Matrix 5.1 (Pro Logic II cleanroom)
  ///  - [SurroundMode.binauralVirtualizer]: Dolby Headphone HRTF & Speaker Virtualizer
  ///  - [SurroundMode.acousticStage]: AM3D Zirene 3D Virtual Surround & M/S Expander
  void setSurround({
    required bool enabled,
    SurroundMode mode = SurroundMode.off,
    double fieldWidth = 1.4,
    int roomLevel = 2,
    double delayMs = 5.5,
    double centerFocus = 0.6,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setSurroundEnabled(_enginePtr, enabled ? 1 : 0);
    _setSurroundMode(_enginePtr, mode.value);
    _setSurroundParams(
        _enginePtr, fieldWidth, roomLevel.toDouble(), delayMs, centerFocus);
  }

  /// Cinema Matrix 5.1 (Cleanroom Pro Logic II Dematrix -> Spherical HRTF).
  void setSurroundMatrix({
    required bool enabled,
    double centerFocus = 0.6,
    double surroundBoost = 1.2,
    double surroundDelayMs = 15.0,
    double headRadiusCm = 8.75,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setSurroundEnabled(_enginePtr, enabled ? 1 : 0);
    _setSurroundMode(_enginePtr, SurroundMode.matrixSurround.value);
    _setSurroundMatrixParams(
      _enginePtr,
      centerFocus,
      surroundBoost,
      surroundDelayMs,
      headRadiusCm,
    );
  }

  /// Binaural HRTF Virtualizer (Reconstructed from Dolby analysis_dlby2).
  ///
  /// [mode]: 0 for Headphone HRTF, 1 for Speaker Field.
  /// [roomPreset]: 1 for Studio, 2 for Cinema, 3 for Concert Hall.
  /// [speakerAngle]: 0 for Narrow (10 deg), 1 for Standard (30 deg), 2 for Wide (45 deg).
  void setSurroundBinaural({
    required bool enabled,
    int mode = 0,
    double boost = 0.65,
    int roomPreset = 2,
    double roomMix = 0.35,
    int speakerAngle = 1,
    double shadowCutoffHz = 3500.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setSurroundEnabled(_enginePtr, enabled ? 1 : 0);
    _setSurroundMode(_enginePtr, SurroundMode.binauralVirtualizer.value);
    _setSurroundBinauralParams(
      _enginePtr,
      mode,
      boost,
      roomPreset,
      roomMix,
      speakerAngle,
      shadowCutoffHz,
    );
  }

  /// 3D Acoustic Stage (Reconstructed from AM3D Zirene re_workspace).
  ///
  /// [profile]: 0 for Headset, 1 for Speaker.
  /// [mode]: 0 for Studio (Normal), 1 for Panoramic (Wide).
  void setSurroundStage({
    required bool enabled,
    int profile = 0,
    int mode = 0,
    double width = 1.2,
    double depth = 0.5,
    double cancellation = 0.60,
    double airPresence = 0.40,
    double bassAnchorHz = 60.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setSurroundEnabled(_enginePtr, enabled ? 1 : 0);
    _setSurroundMode(_enginePtr, SurroundMode.acousticStage.value);
    _setSurroundStageParams(
      _enginePtr,
      profile,
      mode,
      width,
      depth,
      cancellation,
      airPresence,
      bassAnchorHz,
    );
  }

  /// Full per-algorithm surround tuning.
  void setSurroundEx({
    required bool enabled,
    required SurroundMode mode,
    double fieldWidth = 1.4,
    double fieldCrossoverHz = 160.0,
    double fieldDiffuserMix = 0.5,
    double bassAnchor = 0.9,
    double haasDelayMs = 5.5,
    double haasDepth = 0.4,
    double haasDampingHz = 5000.0,
    int vhsRoomPreset = 2,
    double vhsReflectionGain = 0.45,
    double vhsDamping = 0.25,
    double centerFocus = 0.6,
    double surroundBoost = 1.2,
    double surroundDelayMs = 15.0,
    double headRadiusCm = 8.75,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setSurroundEnabled(_enginePtr, enabled ? 1 : 0);
    _setSurroundMode(_enginePtr, mode.value);
    _setSurroundParamsEx(
      _enginePtr,
      fieldWidth,
      fieldCrossoverHz,
      fieldDiffuserMix,
      bassAnchor,
      haasDelayMs,
      haasDepth,
      haasDampingHz,
      vhsRoomPreset.clamp(1, 5),
      vhsReflectionGain,
      vhsDamping,
      centerFocus,
      surroundBoost,
      surroundDelayMs,
      headRadiusCm,
    );
  }

  /// Subsonic DC / Infrasonic Rumble Clean-Room Filter (18 Hz Butterworth HPF).
  void setSubsonicFilterEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setSubsonicFilterEnabled(_enginePtr, enabled ? 1 : 0);
  }

  /// Check if the Subsonic Filter is currently active.
  bool isSubsonicFilterEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getSubsonicFilterEnabled(_enginePtr) != 0;
  }

  /// Dynamic Loudness (ISO 226:2003 Equal-Loudness Contour Compensation).
  void setDynamicLoudnessEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicLoudnessEnabled(_enginePtr, enabled ? 1 : 0);
  }

  bool isDynamicLoudnessEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getDynamicLoudnessEnabled(_enginePtr) != 0;
  }

  void setDynamicLoudnessParams({
    double refLevelDb = 0.0,
    double maxBassBoostDb = 9.0,
    double maxTrebleBoostDb = 4.5,
    double bassFreqHz = 90.0,
    double trebleFreqHz = 9000.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicLoudnessParams(
      _enginePtr,
      refLevelDb,
      maxBassBoostDb,
      maxTrebleBoostDb,
      bassFreqHz,
      trebleFreqHz,
    );
  }

  ({double refLevelDb, double maxBassBoostDb, double maxTrebleBoostDb, double bassFreqHz, double trebleFreqHz}) getDynamicLoudnessParams() {
    if (_enginePtr == ffi.nullptr) {
      return (refLevelDb: 0.0, maxBassBoostDb: 9.0, maxTrebleBoostDb: 4.5, bassFreqHz: 90.0, trebleFreqHz: 9000.0);
    }
    final pRef = calloc<ffi.Float>();
    final pBass = calloc<ffi.Float>();
    final pTreble = calloc<ffi.Float>();
    final pBassF = calloc<ffi.Float>();
    final pTrebleF = calloc<ffi.Float>();
    try {
      _getDynamicLoudnessParams(_enginePtr, pRef, pBass, pTreble, pBassF, pTrebleF);
      return (
        refLevelDb: pRef.value,
        maxBassBoostDb: pBass.value,
        maxTrebleBoostDb: pTreble.value,
        bassFreqHz: pBassF.value,
        trebleFreqHz: pTrebleF.value,
      );
    } finally {
      calloc.free(pRef);
      calloc.free(pBass);
      calloc.free(pTreble);
      calloc.free(pBassF);
      calloc.free(pTrebleF);
    }
  }

  ({double bassBoostDb, double trebleBoostDb}) getDynamicLoudnessCurrentBoost() {
    if (_enginePtr == ffi.nullptr) {
      return (bassBoostDb: 0.0, trebleBoostDb: 0.0);
    }
    final pBass = calloc<ffi.Float>();
    final pTreble = calloc<ffi.Float>();
    try {
      _getDynamicLoudnessCurrentBoost(_enginePtr, pBass, pTreble);
      return (
        bassBoostDb: pBass.value,
        trebleBoostDb: pTreble.value,
      );
    } finally {
      calloc.free(pBass);
      calloc.free(pTreble);
    }
  }

  /// Studio Noise Gate with Dual-Threshold Hysteresis & Hold Time.
  void setNoiseGateEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setNoiseGateEnabled(_enginePtr, enabled ? 1 : 0);
  }

  bool isNoiseGateEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getNoiseGateEnabled(_enginePtr) != 0;
  }

  void setNoiseGateParams({
    double openThreshDb = -42.0,
    double closeThreshDb = -48.0,
    double holdMs = 80.0,
    double attackMs = 1.0,
    double releaseMs = 120.0,
    double sidechainHpfHz = 80.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setNoiseGateParams(
      _enginePtr,
      openThreshDb,
      closeThreshDb,
      holdMs,
      attackMs,
      releaseMs,
      sidechainHpfHz,
    );
  }

  ({double openThreshDb, double closeThreshDb, double holdMs, double attackMs, double releaseMs, double sidechainHpfHz}) getNoiseGateParams() {
    if (_enginePtr == ffi.nullptr) {
      return (openThreshDb: -42.0, closeThreshDb: -48.0, holdMs: 80.0, attackMs: 1.0, releaseMs: 120.0, sidechainHpfHz: 80.0);
    }
    final pOpen = calloc<ffi.Float>();
    final pClose = calloc<ffi.Float>();
    final pHold = calloc<ffi.Float>();
    final pAttack = calloc<ffi.Float>();
    final pRelease = calloc<ffi.Float>();
    final pHpf = calloc<ffi.Float>();
    try {
      _getNoiseGateParams(_enginePtr, pOpen, pClose, pHold, pAttack, pRelease, pHpf);
      return (
        openThreshDb: pOpen.value,
        closeThreshDb: pClose.value,
        holdMs: pHold.value,
        attackMs: pAttack.value,
        releaseMs: pRelease.value,
        sidechainHpfHz: pHpf.value,
      );
    } finally {
      calloc.free(pOpen);
      calloc.free(pClose);
      calloc.free(pHold);
      calloc.free(pAttack);
      calloc.free(pRelease);
      calloc.free(pHpf);
    }
  }

  double getNoiseGateGainReductionDb() {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getNoiseGateGainReductionDb(_enginePtr);
  }

  /// Broadcast Leveller (Real-Time EBU R128 / BS.1770 Slow-Window AGC).
  void setLevellerEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setLevellerEnabled(_enginePtr, enabled ? 1 : 0);
  }

  bool isLevellerEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getLevellerEnabled(_enginePtr) != 0;
  }

  void setLevellerParams({
    double targetLufs = -16.0,
    double maxRiseDbSec = 0.75,
    double maxFallDbSec = 1.5,
    double maxBoostDb = 9.0,
    double maxAttenuationDb = 12.0,
    double silenceGateLufs = -45.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setLevellerParams(
      _enginePtr,
      targetLufs,
      maxRiseDbSec,
      maxFallDbSec,
      maxBoostDb,
      maxAttenuationDb,
      silenceGateLufs,
    );
  }

  ({double targetLufs, double maxRiseDbSec, double maxFallDbSec, double maxBoostDb, double maxAttenuationDb, double silenceGateLufs}) getLevellerParams() {
    if (_enginePtr == ffi.nullptr) {
      return (targetLufs: -16.0, maxRiseDbSec: 0.75, maxFallDbSec: 1.5, maxBoostDb: 9.0, maxAttenuationDb: 12.0, silenceGateLufs: -45.0);
    }
    final pTarget = calloc<ffi.Float>();
    final pRise = calloc<ffi.Float>();
    final pFall = calloc<ffi.Float>();
    final pBoost = calloc<ffi.Float>();
    final pAtten = calloc<ffi.Float>();
    final pGate = calloc<ffi.Float>();
    try {
      _getLevellerParams(_enginePtr, pTarget, pRise, pFall, pBoost, pAtten, pGate);
      return (
        targetLufs: pTarget.value,
        maxRiseDbSec: pRise.value,
        maxFallDbSec: pFall.value,
        maxBoostDb: pBoost.value,
        maxAttenuationDb: pAtten.value,
        silenceGateLufs: pGate.value,
      );
    } finally {
      calloc.free(pTarget);
      calloc.free(pRise);
      calloc.free(pFall);
      calloc.free(pBoost);
      calloc.free(pAtten);
      calloc.free(pGate);
    }
  }

  double getLevellerCurrentGainDb() {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getLevellerCurrentGainDb(_enginePtr);
  }

  /// 6-Band Dynamic Equalizer (DynamicEqDSP).
  void setDynamicEqEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicEqEnabled(_enginePtr, enabled ? 1 : 0);
  }

  bool isDynamicEqEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getDynamicEqEnabled(_enginePtr) != 0;
  }

  void setDynamicEqBand({
    required int bandIndex,
    required DynamicEqFilterType filterType,
    required DynamicEqMode mode,
    required double freqHz,
    double q = 1.0,
    double baseGainDb = 0.0,
    double thresholdDb = -24.0,
    double rangeDb = 6.0,
    double ratio = 3.0,
    double attackMs = 2.0,
    double releaseMs = 60.0,
    bool enabled = true,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicEqBand(
      _enginePtr,
      bandIndex,
      filterType.value,
      mode.value,
      freqHz,
      q,
      baseGainDb,
      thresholdDb,
      rangeDb,
      ratio,
      attackMs,
      releaseMs,
      enabled ? 1 : 0,
    );
  }

  ({
    DynamicEqFilterType filterType,
    DynamicEqMode mode,
    double freqHz,
    double q,
    double baseGainDb,
    double thresholdDb,
    double rangeDb,
    double ratio,
    double attackMs,
    double releaseMs,
    bool enabled,
  }) getDynamicEqBand(int bandIndex) {
    if (_enginePtr == ffi.nullptr) {
      return (
        filterType: DynamicEqFilterType.peak,
        mode: DynamicEqMode.compress,
        freqHz: 1000.0,
        q: 1.0,
        baseGainDb: 0.0,
        thresholdDb: -24.0,
        rangeDb: 6.0,
        ratio: 3.0,
        attackMs: 2.0,
        releaseMs: 60.0,
        enabled: false,
      );
    }
    final pType = calloc<ffi.Int32>();
    final pMode = calloc<ffi.Int32>();
    final pFreq = calloc<ffi.Float>();
    final pQ = calloc<ffi.Float>();
    final pBaseGain = calloc<ffi.Float>();
    final pThresh = calloc<ffi.Float>();
    final pRange = calloc<ffi.Float>();
    final pRatio = calloc<ffi.Float>();
    final pAttack = calloc<ffi.Float>();
    final pRelease = calloc<ffi.Float>();
    final pEnabled = calloc<ffi.Int32>();
    try {
      _getDynamicEqBand(
        _enginePtr,
        bandIndex,
        pType,
        pMode,
        pFreq,
        pQ,
        pBaseGain,
        pThresh,
        pRange,
        pRatio,
        pAttack,
        pRelease,
        pEnabled,
      );
      final fType = (pType.value >= 0 && pType.value < DynamicEqFilterType.values.length)
          ? DynamicEqFilterType.values[pType.value]
          : DynamicEqFilterType.peak;
      final mMode = (pMode.value >= 0 && pMode.value < DynamicEqMode.values.length)
          ? DynamicEqMode.values[pMode.value]
          : DynamicEqMode.compress;
      return (
        filterType: fType,
        mode: mMode,
        freqHz: pFreq.value,
        q: pQ.value,
        baseGainDb: pBaseGain.value,
        thresholdDb: pThresh.value,
        rangeDb: pRange.value,
        ratio: pRatio.value,
        attackMs: pAttack.value,
        releaseMs: pRelease.value,
        enabled: pEnabled.value != 0,
      );
    } finally {
      calloc.free(pType);
      calloc.free(pMode);
      calloc.free(pFreq);
      calloc.free(pQ);
      calloc.free(pBaseGain);
      calloc.free(pThresh);
      calloc.free(pRange);
      calloc.free(pRatio);
      calloc.free(pAttack);
      calloc.free(pRelease);
      calloc.free(pEnabled);
    }
  }

  double getDynamicEqBandGainOffsetDb(int bandIndex) {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getDynamicEqBandGainOffsetDb(_enginePtr, bandIndex);
  }

  /// Vintage Tape Wow & Flutter / Mechanical Pitch Drift (TapeDriftDSP).
  void setTapeDriftEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setTapeDriftEnabled(_enginePtr, enabled ? 1 : 0);
  }

  bool isTapeDriftEnabled() {
    if (_enginePtr == ffi.nullptr) return false;
    return _getTapeDriftEnabled(_enginePtr) != 0;
  }

  void setTapeDriftParams({
    double wowRateHz = 0.8,
    double wowDepthMs = 0.35,
    double flutterRateHz = 12.0,
    double flutterDepthMs = 0.08,
    double driftDepthMs = 0.10,
    double stereoPhaseDeg = 45.0,
    double hfDampingHz = 18000.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _setTapeDriftParams(
      _enginePtr,
      wowRateHz,
      wowDepthMs,
      flutterRateHz,
      flutterDepthMs,
      driftDepthMs,
      stereoPhaseDeg,
      hfDampingHz,
    );
  }

  ({
    double wowRateHz,
    double wowDepthMs,
    double flutterRateHz,
    double flutterDepthMs,
    double driftDepthMs,
    double stereoPhaseDeg,
    double hfDampingHz,
  }) getTapeDriftParams() {
    if (_enginePtr == ffi.nullptr) {
      return (
        wowRateHz: 0.8,
        wowDepthMs: 0.35,
        flutterRateHz: 12.0,
        flutterDepthMs: 0.08,
        driftDepthMs: 0.10,
        stereoPhaseDeg: 45.0,
        hfDampingHz: 18000.0,
      );
    }
    final pWowRate = calloc<ffi.Float>();
    final pWowDepth = calloc<ffi.Float>();
    final pFlutterRate = calloc<ffi.Float>();
    final pFlutterDepth = calloc<ffi.Float>();
    final pDrift = calloc<ffi.Float>();
    final pPhase = calloc<ffi.Float>();
    final pDamping = calloc<ffi.Float>();
    try {
      _getTapeDriftParams(
        _enginePtr,
        pWowRate,
        pWowDepth,
        pFlutterRate,
        pFlutterDepth,
        pDrift,
        pPhase,
        pDamping,
      );
      return (
        wowRateHz: pWowRate.value,
        wowDepthMs: pWowDepth.value,
        flutterRateHz: pFlutterRate.value,
        flutterDepthMs: pFlutterDepth.value,
        driftDepthMs: pDrift.value,
        stereoPhaseDeg: pPhase.value,
        hfDampingHz: pDamping.value,
      );
    } finally {
      calloc.free(pWowRate);
      calloc.free(pWowDepth);
      calloc.free(pFlutterRate);
      calloc.free(pFlutterDepth);
      calloc.free(pDrift);
      calloc.free(pPhase);
      calloc.free(pDamping);
    }
  }

  void setTapeDriftPreset(TapeDriftPreset preset) {
    if (_enginePtr == ffi.nullptr) return;
    _setTapeDriftPreset(_enginePtr, preset.value);
  }

  TapeDriftPreset getTapeDriftPreset() {
    if (_enginePtr == ffi.nullptr) return TapeDriftPreset.subtleHiFi;
    final val = _getTapeDriftPreset(_enginePtr);
    if (val >= 0 && val < TapeDriftPreset.values.length) {
      return TapeDriftPreset.values[val];
    }
    return TapeDriftPreset.custom;
  }
}
