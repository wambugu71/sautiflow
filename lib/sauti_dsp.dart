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
  pultecDeep(4);

  // Backward-compatible aliases
  static const HarmonicBassProfile subBassResonant = naturalBass;
  static const HarmonicBassProfile punchyBass = pureBass;

  final int value;
  const HarmonicBassProfile(this.value);
}

/// Dynamic Transducer profiles.
enum TransducerProfile {
  earphone(0),
  headphone(1),
  highEndReference(2),
  speakerMonitor(3),
  extremeSubwoofer(4),
  pureDynamic(5);

  final int value;
  const TransducerProfile(this.value);
}

/// Analog Warmth profiles.
enum AnalogWarmthProfile {
  triode12AX7(0),
  magneticTape(1),
  vintagePreamp(2);

  final int value;
  const AnalogWarmthProfile(this.value);
}

/// De-Esser operating modes.
enum DeEsserMode {
  splitBand(0),
  wideBand(1);

  final int value;
  const DeEsserMode(this.value);
}

/// Spatial Surround suite modes (see surround.md).
enum SurroundMode {
  off(0),
  fieldExpander(1),
  differentialHaas(2),
  viperHeadphone(3),
  matrix51Hrtf(4);

  final int value;
  const SurroundMode(this.value);
}

// Native FFI Typedefs
typedef _DspSetEnabledNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetSurroundModeNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _DspSetSurroundModeDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _DspSetClarityParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetClarityParamsDart = void Function(ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetBassParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float);
typedef _DspSetBassParamsDart = void Function(ffi.Pointer<ffi.Void>, int, double, double);

typedef _DspSetDynamicSystemParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetDynamicSystemParamsDart = void Function(ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetAnalogWarmthParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetAnalogWarmthParamsDart = void Function(ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDeEsserParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _DspSetDeEsserParamsDart = void Function(ffi.Pointer<ffi.Void>, int, double);

typedef _DspSetDeEsserParamsExNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float,
    ffi.Float
);
typedef _DspSetDeEsserParamsExDart = void Function(
    ffi.Pointer<ffi.Void>,
    int,
    double,
    double,
    double,
    double,
    double,
    double
);

typedef _DspGetDeEsserGainReductionDbNative = ffi.Float Function(ffi.Pointer<ffi.Void>);
typedef _DspGetDeEsserGainReductionDbDart = double Function(ffi.Pointer<ffi.Void>);

typedef _DspLoadConvolverIrNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32);
typedef _DspLoadConvolverIrDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, int, int);

typedef _DspClearConvolverIrNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DspClearConvolverIrDart = void Function(ffi.Pointer<ffi.Void>);

typedef _DspSetConvolverMixNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float);
typedef _DspSetConvolverMixDart = void Function(ffi.Pointer<ffi.Void>, double, double);

typedef _DspSetMasterLimiterParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetMasterLimiterParamsDart = void Function(ffi.Pointer<ffi.Void>, double, double, double);

typedef _DspResetNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DspResetDart = void Function(ffi.Pointer<ffi.Void>);

typedef _DspHasConvolverIrNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _DspHasConvolverIrDart = int Function(ffi.Pointer<ffi.Void>);

typedef _DspGetConvolverKernelLengthNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _DspGetConvolverKernelLengthDart = int Function(ffi.Pointer<ffi.Void>);

typedef _DspGetLimiterGainReductionDbNative = ffi.Float Function(ffi.Pointer<ffi.Void>);
typedef _DspGetLimiterGainReductionDbDart = double Function(ffi.Pointer<ffi.Void>);

typedef _DspSetSurroundParamsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _DspSetSurroundParamsDart = void Function(ffi.Pointer<ffi.Void>, double, double, double, double);

typedef _DspSetSurroundParamsExNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Float, ffi.Float, ffi.Float, ffi.Float, // field: width, crossover, diffuser, bass anchor
    ffi.Float, ffi.Float, ffi.Float,           // haas: delay, depth, damping
    ffi.Int32, ffi.Float, ffi.Float,           // vhs: preset, reflection gain, damping
    ffi.Float, ffi.Float, ffi.Float, ffi.Float // matrix: center focus, boost, rear delay, head radius
);
typedef _DspSetSurroundParamsExDart = void Function(
    ffi.Pointer<ffi.Void>,
    double, double, double, double,
    double, double, double,
    int, double, double,
    double, double, double, double
);

/// Clean-room high-fidelity DSP suite for SautiFlow.
class SautiDsp {
  final ffi.DynamicLibrary _lib;
  final ffi.Pointer<ffi.Void> _enginePtr;

  late final _DspResetDart _reset;

  late final _DspSetEnabledDart _setClarityEnabled;
  late final _DspSetClarityParamsDart _setClarityParams;

  late final _DspSetEnabledDart _setBassEnabled;
  late final _DspSetBassParamsDart _setBassParams;

  late final _DspSetEnabledDart _setDynamicSystemEnabled;
  late final _DspSetDynamicSystemParamsDart _setDynamicSystemParams;

  late final _DspSetEnabledDart _setAnalogWarmthEnabled;
  late final _DspSetAnalogWarmthParamsDart _setAnalogWarmthParams;

  late final _DspSetEnabledDart _setDeEsserEnabled;
  late final _DspSetDeEsserParamsDart _setDeEsserParams;
  late final _DspSetDeEsserParamsExDart _setDeEsserParamsEx;
  late final _DspGetDeEsserGainReductionDbDart _getDeEsserGainReductionDb;

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
  late final _DspSetSurroundParamsExDart _setSurroundParamsEx;

  SautiDsp(this._lib, this._enginePtr) {
    _initFunctions();
  }

  SautiDsp.fromEngine(AudioEngineFFI engine)
      : _lib = engine.library,
        _enginePtr = engine.enginePointer {
    _initFunctions();
  }

  void _initFunctions() {
    _reset = _lib.lookupFunction<_DspResetNative, _DspResetDart>('ae_dsp_reset');

    _setClarityEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_clarity_enabled');
    _setClarityParams = _lib.lookupFunction<_DspSetClarityParamsNative, _DspSetClarityParamsDart>('ae_dsp_set_clarity_params');

    _setBassEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_bass_enabled');
    _setBassParams = _lib.lookupFunction<_DspSetBassParamsNative, _DspSetBassParamsDart>('ae_dsp_set_bass_params');

    _setDynamicSystemEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_dynamic_system_enabled');
    _setDynamicSystemParams = _lib.lookupFunction<_DspSetDynamicSystemParamsNative, _DspSetDynamicSystemParamsDart>('ae_dsp_set_dynamic_system_params');

    _setAnalogWarmthEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_analog_warmth_enabled');
    _setAnalogWarmthParams = _lib.lookupFunction<_DspSetAnalogWarmthParamsNative, _DspSetAnalogWarmthParamsDart>('ae_dsp_set_analog_warmth_params');

    _setDeEsserEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_de_esser_enabled');
    _setDeEsserParams = _lib.lookupFunction<_DspSetDeEsserParamsNative, _DspSetDeEsserParamsDart>('ae_dsp_set_de_esser_params');
    _setDeEsserParamsEx = _lib.lookupFunction<_DspSetDeEsserParamsExNative, _DspSetDeEsserParamsExDart>('ae_dsp_set_de_esser_params_ex');
    _getDeEsserGainReductionDb = _lib.lookupFunction<_DspGetDeEsserGainReductionDbNative, _DspGetDeEsserGainReductionDbDart>('ae_dsp_get_de_esser_gain_reduction_db');

    _setConvolverEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_convolver_enabled');
    _loadConvolverIr = _lib.lookupFunction<_DspLoadConvolverIrNative, _DspLoadConvolverIrDart>('ae_dsp_load_convolver_ir');
    _clearConvolverIr = _lib.lookupFunction<_DspClearConvolverIrNative, _DspClearConvolverIrDart>('ae_dsp_clear_convolver_ir');
    _setConvolverMix = _lib.lookupFunction<_DspSetConvolverMixNative, _DspSetConvolverMixDart>('ae_dsp_set_convolver_mix');
    _hasConvolverIr = _lib.lookupFunction<_DspHasConvolverIrNative, _DspHasConvolverIrDart>('ae_dsp_has_convolver_ir');
    _getConvolverKernelLength = _lib.lookupFunction<_DspGetConvolverKernelLengthNative, _DspGetConvolverKernelLengthDart>('ae_dsp_get_convolver_kernel_length');

    _setMasterLimiterEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_master_limiter_enabled');
    _setMasterLimiterParams = _lib.lookupFunction<_DspSetMasterLimiterParamsNative, _DspSetMasterLimiterParamsDart>('ae_dsp_set_master_limiter_params');
    _getLimiterGainReductionDb = _lib.lookupFunction<_DspGetLimiterGainReductionDbNative, _DspGetLimiterGainReductionDbDart>('ae_dsp_get_limiter_gain_reduction_db');

    _setSurroundEnabled = _lib.lookupFunction<_DspSetEnabledNative, _DspSetEnabledDart>('ae_dsp_set_surround_enabled');
    _setSurroundMode = _lib.lookupFunction<_DspSetSurroundModeNative, _DspSetSurroundModeDart>('ae_dsp_set_surround_mode');
    _setSurroundParams = _lib.lookupFunction<_DspSetSurroundParamsNative, _DspSetSurroundParamsDart>('ae_dsp_set_surround_params');
    _setSurroundParamsEx = _lib.lookupFunction<_DspSetSurroundParamsExNative, _DspSetSurroundParamsExDart>('ae_dsp_set_surround_params_ex');
  }

  /// Reset all internal DSP buffers and history states.
  void reset() {
    if (_enginePtr == ffi.nullptr) return;
    _reset(_enginePtr);
  }

  /// Audio Clarity Engine.
  void setClarity({required bool enabled, AudioClarityProfile profile = AudioClarityProfile.transientCrisp, double intensity = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setClarityEnabled(_enginePtr, enabled ? 1 : 0);
    _setClarityParams(_enginePtr, profile.value, intensity);
  }

  /// Harmonic Bass Engine.
  void setHarmonicBass({required bool enabled, HarmonicBassProfile profile = HarmonicBassProfile.subBassResonant, double cutoffHz = 60.0, double boost = 1.0}) {
    if (_enginePtr == ffi.nullptr) return;
    _setBassEnabled(_enginePtr, enabled ? 1 : 0);
    _setBassParams(_enginePtr, profile.value, cutoffHz, boost);
  }

  /// Dynamic Transducer Correction.
  void setDynamicSystem({required bool enabled, TransducerProfile profile = TransducerProfile.earphone, double strength = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setDynamicSystemEnabled(_enginePtr, enabled ? 1 : 0);
    _setDynamicSystemParams(_enginePtr, profile.value, strength);
  }

  /// Analog Warmth (Triode Tube & Magnetic Tape saturation).
  void setAnalogWarmth({required bool enabled, AnalogWarmthProfile profile = AnalogWarmthProfile.triode12AX7, double drive = 0.5}) {
    if (_enginePtr == ffi.nullptr) return;
    _setAnalogWarmthEnabled(_enginePtr, enabled ? 1 : 0);
    _setAnalogWarmthParams(_enginePtr, profile.value, drive);
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
  void setMasterLimiter({required bool enabled, double ceilingDb = -0.1, double outputGainDb = 0.0, double releaseMs = 60.0}) {
    if (_enginePtr == ffi.nullptr) return;
    _setMasterLimiterEnabled(_enginePtr, enabled ? 1 : 0);
    _setMasterLimiterParams(_enginePtr, ceilingDb, outputGainDb, releaseMs);
  }

  /// Get current limiter gain reduction in dB (for real-time meter display).
  double get limiterGainReductionDb {
    if (_enginePtr == ffi.nullptr) return 0.0;
    return _getLimiterGainReductionDb(_enginePtr);
  }

  /// Spatial Surround Suite.
  ///
  /// [mode] selects the algorithm. The compact parameters map to:
  ///  - [fieldWidth]: stereo field expansion ratio (0.0-2.5, default 1.4)
  ///  - [roomLevel]: VHS+ room preset 1-5 (default 2)
  ///  - [delayMs]: Haas precedence delay in ms, 1-25 (default 5.5)
  ///  - [centerFocus]: Matrix 5.1 vocal centering 0.0-1.0 (default 0.6)
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
    _setSurroundParams(_enginePtr, fieldWidth, roomLevel.toDouble(), delayMs, centerFocus);
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
      fieldWidth, fieldCrossoverHz, fieldDiffuserMix, bassAnchor,
      haasDelayMs, haasDepth, haasDampingHz,
      vhsRoomPreset.clamp(1, 5), vhsReflectionGain, vhsDamping,
      centerFocus, surroundBoost, surroundDelayMs, headRadiusCm,
    );
  }
}
