import 'dart:ffi' as ffi;
import '../audio_engine_ffi.dart';

enum ResampleAlgorithm { linear, custom }

enum DitherMode { none, rectangle, triangle }

// Native function typedefs
typedef _CreateLpf1Native = ffi.Pointer<ffi.Void> Function(ffi.Int32 format,
    ffi.Int32 channels, ffi.Int32 sampleRate, ffi.Double cutoffHz);
typedef _CreateLpf1Dart = ffi.Pointer<ffi.Void> Function(
    int format, int channels, int sampleRate, double cutoffHz);
typedef _VoidFilterOpNative = ffi.Void Function(ffi.Pointer<ffi.Void> filter);
typedef _VoidFilterOpDart = void Function(ffi.Pointer<ffi.Void> filter);
typedef _ProcessFilterNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> filter,
    ffi.Pointer<ffi.Void> outFrames,
    ffi.Pointer<ffi.Void> inFrames,
    ffi.Uint64 frameCount);
typedef _ProcessFilterDart = int Function(
    ffi.Pointer<ffi.Void> filter,
    ffi.Pointer<ffi.Void> outFrames,
    ffi.Pointer<ffi.Void> inFrames,
    int frameCount);

typedef _CreateLpf2Native = ffi.Pointer<ffi.Void> Function(
    ffi.Int32 format,
    ffi.Int32 channels,
    ffi.Int32 sampleRate,
    ffi.Double cutoffHz,
    ffi.Double q);
typedef _CreateLpf2Dart = ffi.Pointer<ffi.Void> Function(
    int format, int channels, int sampleRate, double cutoffHz, double q);

typedef _CreateLpfNative = ffi.Pointer<ffi.Void> Function(
    ffi.Int32 format,
    ffi.Int32 channels,
    ffi.Int32 sampleRate,
    ffi.Double cutoffHz,
    ffi.Int32 order);
typedef _CreateLpfDart = ffi.Pointer<ffi.Void> Function(
    int format, int channels, int sampleRate, double cutoffHz, int order);

typedef _CreateBiquadNative = ffi.Pointer<ffi.Void> Function(
    ffi.Int32 format,
    ffi.Int32 channels,
    ffi.Double b0,
    ffi.Double b1,
    ffi.Double b2,
    ffi.Double a0,
    ffi.Double a1,
    ffi.Double a2);
typedef _CreateBiquadDart = ffi.Pointer<ffi.Void> Function(
    int format,
    int channels,
    double b0,
    double b1,
    double b2,
    double a0,
    double a1,
    double a2);

typedef _CreateResamplerNative = ffi.Pointer<ffi.Void> Function(
    ffi.Int32 format,
    ffi.Int32 channels,
    ffi.Int32 sampleRateIn,
    ffi.Int32 sampleRateOut,
    ffi.Int32 algorithm,
    ffi.Int32 ditherMode);
typedef _CreateResamplerDart = ffi.Pointer<ffi.Void> Function(
    int format,
    int channels,
    int sampleRateIn,
    int sampleRateOut,
    int algorithm,
    int ditherMode);

typedef _ProcessResamplerNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> resampler,
    ffi.Pointer<ffi.Void> inFrames,
    ffi.Pointer<ffi.Uint64> inFrameCount,
    ffi.Pointer<ffi.Void> outFrames,
    ffi.Pointer<ffi.Uint64> outFrameCount);
typedef _ProcessResamplerDart = int Function(
    ffi.Pointer<ffi.Void> resampler,
    ffi.Pointer<ffi.Void> inFrames,
    ffi.Pointer<ffi.Uint64> inFrameCount,
    ffi.Pointer<ffi.Void> outFrames,
    ffi.Pointer<ffi.Uint64> outFrameCount);

typedef _SetResamplerRateNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> resampler,
    ffi.Int32 sampleRateIn,
    ffi.Int32 sampleRateOut);
typedef _SetResamplerRateDart = void Function(
    ffi.Pointer<ffi.Void> resampler, int sampleRateIn, int sampleRateOut);

typedef _SetResamplerRateRatioNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> resampler, ffi.Float ratioInOut);
typedef _SetResamplerRateRatioDart = void Function(
    ffi.Pointer<ffi.Void> resampler, double ratioInOut);

typedef _GetResamplerFramesNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> resampler, ffi.Uint64 inOrOutFrameCount);
typedef _GetResamplerFramesDart = int Function(
    ffi.Pointer<ffi.Void> resampler, int inOrOutFrameCount);

typedef _GetResamplerLatencyNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> resampler);
typedef _GetResamplerLatencyDart = int Function(
    ffi.Pointer<ffi.Void> resampler);

class MiniaudioFiltersFFI {
  MiniaudioFiltersFFI({String? libraryPath})
      : _lib = AudioEngineFFI.openLibrary(libraryPath) {
    _createLpf1 = _lib
        .lookupFunction<_CreateLpf1Native, _CreateLpf1Dart>('ae_lpf1_create');
    _destroyLpf1 = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_lpf1_destroy');
    _reinitLpf1 = _lib.lookupFunction<_CreateLpf1Native, _CreateLpf1Dart>(
        'ae_lpf1_reinit'); // Signature is same for args
    _processLpf1 =
        _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
            'ae_lpf1_process');

    _createLpf2 = _lib
        .lookupFunction<_CreateLpf2Native, _CreateLpf2Dart>('ae_lpf2_create');
    _destroyLpf2 = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_lpf2_destroy');
    _reinitLpf2 = _lib
        .lookupFunction<_CreateLpf2Native, _CreateLpf2Dart>('ae_lpf2_reinit');
    _processLpf2 =
        _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
            'ae_lpf2_process');

    _createLpf =
        _lib.lookupFunction<_CreateLpfNative, _CreateLpfDart>('ae_lpf_create');
    _destroyLpf = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_lpf_destroy');
    _reinitLpf =
        _lib.lookupFunction<_CreateLpfNative, _CreateLpfDart>('ae_lpf_reinit');
    _processLpf = _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
        'ae_lpf_process');

    _createHpf1 = _lib
        .lookupFunction<_CreateLpf1Native, _CreateLpf1Dart>('ae_hpf1_create');
    _destroyHpf1 = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_hpf1_destroy');
    _reinitHpf1 = _lib
        .lookupFunction<_CreateLpf1Native, _CreateLpf1Dart>('ae_hpf1_reinit');
    _processHpf1 =
        _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
            'ae_hpf1_process');

    _createHpf2 = _lib
        .lookupFunction<_CreateLpf2Native, _CreateLpf2Dart>('ae_hpf2_create');
    _destroyHpf2 = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_hpf2_destroy');
    _reinitHpf2 = _lib
        .lookupFunction<_CreateLpf2Native, _CreateLpf2Dart>('ae_hpf2_reinit');
    _processHpf2 =
        _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
            'ae_hpf2_process');

    _createHpf =
        _lib.lookupFunction<_CreateLpfNative, _CreateLpfDart>('ae_hpf_create');
    _destroyHpf = _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
        'ae_hpf_destroy');
    _reinitHpf =
        _lib.lookupFunction<_CreateLpfNative, _CreateLpfDart>('ae_hpf_reinit');
    _processHpf = _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
        'ae_hpf_process');

    _createBiquad = _lib.lookupFunction<_CreateBiquadNative, _CreateBiquadDart>(
        'ae_biquad_create');
    _destroyBiquad =
        _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
            'ae_biquad_destroy');
    _reinitBiquad = _lib.lookupFunction<_CreateBiquadNative, _CreateBiquadDart>(
        'ae_biquad_reinit');
    _processBiquad =
        _lib.lookupFunction<_ProcessFilterNative, _ProcessFilterDart>(
            'ae_biquad_process');

    _createResampler =
        _lib.lookupFunction<_CreateResamplerNative, _CreateResamplerDart>(
            'ae_resampler_create');
    _destroyResampler =
        _lib.lookupFunction<_VoidFilterOpNative, _VoidFilterOpDart>(
            'ae_resampler_destroy');
    _processResampler =
        _lib.lookupFunction<_ProcessResamplerNative, _ProcessResamplerDart>(
            'ae_resampler_process');
    _setResamplerRate =
        _lib.lookupFunction<_SetResamplerRateNative, _SetResamplerRateDart>(
            'ae_resampler_set_rate');
    _setResamplerRateRatio = _lib.lookupFunction<_SetResamplerRateRatioNative,
        _SetResamplerRateRatioDart>('ae_resampler_set_rate_ratio');
    _getResamplerRequiredInput =
        _lib.lookupFunction<_GetResamplerFramesNative, _GetResamplerFramesDart>(
            'ae_resampler_get_required_input_frame_count');
    _getResamplerExpectedOutput =
        _lib.lookupFunction<_GetResamplerFramesNative, _GetResamplerFramesDart>(
            'ae_resampler_get_expected_output_frame_count');
    _getResamplerInputLatency = _lib.lookupFunction<_GetResamplerLatencyNative,
        _GetResamplerLatencyDart>('ae_resampler_get_input_latency');
    _getResamplerOutputLatency = _lib.lookupFunction<_GetResamplerLatencyNative,
        _GetResamplerLatencyDart>('ae_resampler_get_output_latency');
  }

  final ffi.DynamicLibrary _lib;

  late final _CreateLpf1Dart _createLpf1;
  late final _VoidFilterOpDart _destroyLpf1;
  late final _CreateLpf1Dart _reinitLpf1;
  late final _ProcessFilterDart _processLpf1;

  late final _CreateLpf2Dart _createLpf2;
  late final _VoidFilterOpDart _destroyLpf2;
  late final _CreateLpf2Dart _reinitLpf2;
  late final _ProcessFilterDart _processLpf2;

  late final _CreateLpfDart _createLpf;
  late final _VoidFilterOpDart _destroyLpf;
  late final _CreateLpfDart _reinitLpf;
  late final _ProcessFilterDart _processLpf;

  late final _CreateLpf1Dart _createHpf1;
  late final _VoidFilterOpDart _destroyHpf1;
  late final _CreateLpf1Dart _reinitHpf1;
  late final _ProcessFilterDart _processHpf1;

  late final _CreateLpf2Dart _createHpf2;
  late final _VoidFilterOpDart _destroyHpf2;
  late final _CreateLpf2Dart _reinitHpf2;
  late final _ProcessFilterDart _processHpf2;

  late final _CreateLpfDart _createHpf;
  late final _VoidFilterOpDart _destroyHpf;
  late final _CreateLpfDart _reinitHpf;
  late final _ProcessFilterDart _processHpf;

  late final _CreateBiquadDart _createBiquad;
  late final _VoidFilterOpDart _destroyBiquad;
  late final _CreateBiquadDart _reinitBiquad;
  late final _ProcessFilterDart _processBiquad;

  late final _CreateResamplerDart _createResampler;
  late final _VoidFilterOpDart _destroyResampler;
  late final _ProcessResamplerDart _processResampler;
  late final _SetResamplerRateDart _setResamplerRate;
  late final _SetResamplerRateRatioDart _setResamplerRateRatio;
  late final _GetResamplerFramesDart _getResamplerRequiredInput;
  late final _GetResamplerFramesDart _getResamplerExpectedOutput;
  late final _GetResamplerLatencyDart _getResamplerInputLatency;
  late final _GetResamplerLatencyDart _getResamplerOutputLatency;

  // Dart Wrappers for Friendly Usage

  ffi.Pointer<ffi.Void> createLpf1(
      AudioFormat format, int channels, int sampleRate, double cutoffHz) {
    return _createLpf1(format.index, channels, sampleRate, cutoffHz);
  }

  void reinitLpf1(ffi.Pointer<ffi.Void> filter, AudioFormat format,
      int channels, int sampleRate, double cutoffHz) {
    _reinitLpf1(format.index, channels, sampleRate, cutoffHz);
  }

  bool processLpf1(
      ffi.Pointer<ffi.Void> filter,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    return _processLpf1(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyLpf1(ffi.Pointer<ffi.Void> filter) => _destroyLpf1(filter);

  ffi.Pointer<ffi.Void> createLpf2(AudioFormat format, int channels,
      int sampleRate, double cutoffHz, double q) {
    return _createLpf2(format.index, channels, sampleRate, cutoffHz, q);
  }

  void reinitLpf2(ffi.Pointer<ffi.Void> filter, AudioFormat format,
      int channels, int sampleRate, double cutoffHz, double q) {
    _reinitLpf2(format.index, channels, sampleRate, cutoffHz, q);
  }

  bool processLpf2(
      ffi.Pointer<ffi.Void> filter,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    return _processLpf2(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyLpf2(ffi.Pointer<ffi.Void> filter) => _destroyLpf2(filter);

  ffi.Pointer<ffi.Void> createLpf(AudioFormat format, int channels,
      int sampleRate, double cutoffHz, int order) {
    return _createLpf(format.index, channels, sampleRate, cutoffHz, order);
  }

  void reinitLpf(ffi.Pointer<ffi.Void> filter, AudioFormat format, int channels,
      int sampleRate, double cutoffHz, int order) {
    _reinitLpf(format.index, channels, sampleRate, cutoffHz, order);
  }

  bool processLpf(ffi.Pointer<ffi.Void> filter, ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames, int frameCount) {
    return _processLpf(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyLpf(ffi.Pointer<ffi.Void> filter) => _destroyLpf(filter);

  ffi.Pointer<ffi.Void> createHpf1(
      AudioFormat format, int channels, int sampleRate, double cutoffHz) {
    return _createHpf1(format.index, channels, sampleRate, cutoffHz);
  }

  void reinitHpf1(ffi.Pointer<ffi.Void> filter, AudioFormat format,
      int channels, int sampleRate, double cutoffHz) {
    _reinitHpf1(format.index, channels, sampleRate, cutoffHz);
  }

  bool processHpf1(
      ffi.Pointer<ffi.Void> filter,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    return _processHpf1(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyHpf1(ffi.Pointer<ffi.Void> filter) => _destroyHpf1(filter);

  ffi.Pointer<ffi.Void> createHpf2(AudioFormat format, int channels,
      int sampleRate, double cutoffHz, double q) {
    return _createHpf2(format.index, channels, sampleRate, cutoffHz, q);
  }

  void reinitHpf2(ffi.Pointer<ffi.Void> filter, AudioFormat format,
      int channels, int sampleRate, double cutoffHz, double q) {
    _reinitHpf2(format.index, channels, sampleRate, cutoffHz, q);
  }

  bool processHpf2(
      ffi.Pointer<ffi.Void> filter,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    return _processHpf2(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyHpf2(ffi.Pointer<ffi.Void> filter) => _destroyHpf2(filter);

  ffi.Pointer<ffi.Void> createHpf(AudioFormat format, int channels,
      int sampleRate, double cutoffHz, int order) {
    return _createHpf(format.index, channels, sampleRate, cutoffHz, order);
  }

  void reinitHpf(ffi.Pointer<ffi.Void> filter, AudioFormat format, int channels,
      int sampleRate, double cutoffHz, int order) {
    _reinitHpf(format.index, channels, sampleRate, cutoffHz, order);
  }

  bool processHpf(ffi.Pointer<ffi.Void> filter, ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames, int frameCount) {
    return _processHpf(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyHpf(ffi.Pointer<ffi.Void> filter) => _destroyHpf(filter);

  ffi.Pointer<ffi.Void> createBiquad(AudioFormat format, int channels,
      double b0, double b1, double b2, double a0, double a1, double a2) {
    return _createBiquad(format.index, channels, b0, b1, b2, a0, a1, a2);
  }

  void reinitBiquad(
      ffi.Pointer<ffi.Void> filter,
      AudioFormat format,
      int channels,
      double b0,
      double b1,
      double b2,
      double a0,
      double a1,
      double a2) {
    _reinitBiquad(format.index, channels, b0, b1, b2, a0, a1, a2);
  }

  bool processBiquad(
      ffi.Pointer<ffi.Void> filter,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    return _processBiquad(filter, outFrames, inFrames, frameCount) != 0;
  }

  void destroyBiquad(ffi.Pointer<ffi.Void> filter) => _destroyBiquad(filter);

  ffi.Pointer<ffi.Void> createResampler(
      AudioFormat format,
      int channels,
      int sampleRateIn,
      int sampleRateOut,
      ResampleAlgorithm algorithm,
      DitherMode ditherMode) {
    return _createResampler(format.index, channels, sampleRateIn, sampleRateOut,
        algorithm.index, ditherMode.index);
  }

  bool processResampler(
      ffi.Pointer<ffi.Void> resampler,
      ffi.Pointer<ffi.Void> inFrames,
      ffi.Pointer<ffi.Uint64> inFrameCount,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Uint64> outFrameCount) {
    return _processResampler(
            resampler, inFrames, inFrameCount, outFrames, outFrameCount) !=
        0;
  }

  void setResamplerRate(
      ffi.Pointer<ffi.Void> resampler, int sampleRateIn, int sampleRateOut) {
    _setResamplerRate(resampler, sampleRateIn, sampleRateOut);
  }

  void setResamplerRateRatio(
      ffi.Pointer<ffi.Void> resampler, double ratioInOut) {
    _setResamplerRateRatio(resampler, ratioInOut);
  }

  int getResamplerRequiredInput(
      ffi.Pointer<ffi.Void> resampler, int outFrameCount) {
    return _getResamplerRequiredInput(resampler, outFrameCount);
  }

  int getResamplerExpectedOutput(
      ffi.Pointer<ffi.Void> resampler, int inFrameCount) {
    return _getResamplerExpectedOutput(resampler, inFrameCount);
  }

  int getResamplerInputLatency(ffi.Pointer<ffi.Void> resampler) {
    return _getResamplerInputLatency(resampler);
  }

  int getResamplerOutputLatency(ffi.Pointer<ffi.Void> resampler) {
    return _getResamplerOutputLatency(resampler);
  }

  void destroyResampler(ffi.Pointer<ffi.Void> resampler) =>
      _destroyResampler(resampler);
}
