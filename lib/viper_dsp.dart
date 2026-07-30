import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';
import 'audio_engine_ffi.dart';

// FFI Typedefs for ViPER DSP Integration

typedef _ViperSetEnabledNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ViperSetEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ViperSetSamplingRateNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ViperSetSamplingRateDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ViperResetNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ViperResetDart = void Function(ffi.Pointer<ffi.Void>);

typedef _ViperMasterLimiterNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _ViperMasterLimiterDart = void Function(ffi.Pointer<ffi.Void>, double, double, double);

typedef _ViperPlaybackGainNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Float);
typedef _ViperPlaybackGainDart = void Function(ffi.Pointer<ffi.Void>, int, double, double, double);

typedef _ViperLufsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32);
typedef _ViperLufsDart = void Function(ffi.Pointer<ffi.Void>, int, double, double, int);

typedef _ViperFetCompressorNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Float, ffi.Int32,
    ffi.Float, ffi.Int32, ffi.Float, ffi.Int32, ffi.Float, ffi.Int32, ffi.Float,
    ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Int32);
typedef _ViperFetCompressorDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double, double, int,
    double, int, double, int, double, int, double,
    double, double, double, double, int);

typedef _ViperBassNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Float, ffi.Int32);
typedef _ViperBassDart = void Function(ffi.Pointer<ffi.Void>, int, int, int, double, int);

typedef _ViperBassMonoNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Float, ffi.Int32);
typedef _ViperBassMonoDart = void Function(ffi.Pointer<ffi.Void>, int, int, int, double, int);

typedef _ViperPsychoacousticBassNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _ViperPsychoacousticBassDart = void Function(ffi.Pointer<ffi.Void>, int, int, int, int, int);

typedef _ViperSpectrumExtensionNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Float);
typedef _ViperSpectrumExtensionDart = void Function(ffi.Pointer<ffi.Void>, int, int, double);

typedef _ViperEqualizerNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Float>);
typedef _ViperEqualizerDart = void Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Float>);

typedef _ViperConvolverNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _ViperConvolverDart = void Function(ffi.Pointer<ffi.Void>, int, double);

typedef _ViperLoadConvolverKernelNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _ViperLoadConvolverKernelDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, int, int, int);

typedef _ViperUnloadConvolverKernelNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ViperUnloadConvolverKernelDart = void Function(ffi.Pointer<ffi.Void>);

typedef _ViperDdcNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ViperDdcDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ViperLoadDdcCoefficientsNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _ViperLoadDdcCoefficientsDart = void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, int);

typedef _ViperFieldSurroundNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32);
typedef _ViperFieldSurroundDart = void Function(ffi.Pointer<ffi.Void>, int, double, double, int);

typedef _ViperDiffSurroundNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Int32, ffi.Float, ffi.Float);
typedef _ViperDiffSurroundDart = void Function(ffi.Pointer<ffi.Void>, int, double, int, double, double);

typedef _ViperStereoImagerNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _ViperStereoImagerDart = void Function(ffi.Pointer<ffi.Void>, int, double, double, double, double, double);

typedef _ViperHeadphoneSurroundNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _ViperHeadphoneSurroundDart = void Function(ffi.Pointer<ffi.Void>, int, int);

typedef _ViperReverbNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _ViperReverbDart = void Function(ffi.Pointer<ffi.Void>, int, double, double, double, double, double);

typedef _ViperDynamicSystemNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Float);
typedef _ViperDynamicSystemDart = void Function(ffi.Pointer<ffi.Void>, int, int, int, int, int, double, double, double);

typedef _ViperClarityNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Float);
typedef _ViperClarityDart = void Function(ffi.Pointer<ffi.Void>, int, int, double);

typedef _ViperCureNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _ViperCureDart = void Function(ffi.Pointer<ffi.Void>, int, int);

typedef _ViperTubeSimulatorNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ViperTubeSimulatorDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ViperAnalogXNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _ViperAnalogXDart = void Function(ffi.Pointer<ffi.Void>, int, int);

typedef _ViperSpeakerCorrectionNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ViperSpeakerCorrectionDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ViperMultibandCompressorNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);
typedef _ViperMultibandCompressorDart = void Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);

typedef _ViperDynamicEqNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Float>);
typedef _ViperDynamicEqDart = void Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Float>);

typedef _ViperAdaptiveLoudnessNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32, ffi.Float, ffi.Float);
typedef _ViperAdaptiveLoudnessDart = void Function(ffi.Pointer<ffi.Void>, int, int, double, double);

// Memory allocation typedefs (from C standard library)
typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

/// Enums and Configuration Classes

enum ViperBassMode { natural, pure, subwoofer }
enum ViperClarityMode { mild, natural, aggressive }
enum ViperAnalogXMode { mild, moderate, aggressive }
enum ViperCureCrossfeedPreset { off, weakChuMoy, strongJmeier }
enum ViperLufsSpeed { fast, medium, slow, verySlow }
enum ViperAlcMode { natural, mild, punchy }

class ViperMultibandCompressorBand {
  bool enable;
  double threshold;
  double ratio;
  double knee;
  bool kneeAuto;
  double gain;
  bool gainAuto;
  double attack;
  bool attackAuto;
  double release;
  bool releaseAuto;
  double kneeMulti;
  double maxAttack;
  double maxRelease;
  double crest;
  double adapt;
  bool noClip;

  ViperMultibandCompressorBand({
    this.enable = false,
    this.threshold = 0.0,
    this.ratio = 0.0,
    this.knee = 0.0,
    this.kneeAuto = false,
    this.gain = 0.0,
    this.gainAuto = false,
    this.attack = 0.0,
    this.attackAuto = false,
    this.release = 0.0,
    this.releaseAuto = false,
    this.kneeMulti = 0.0,
    this.maxAttack = 0.0,
    this.maxRelease = 0.0,
    this.crest = 0.0,
    this.adapt = 0.0,
    this.noClip = false,
  });

  /// The C struct layout is 17 floats. 
  ///  [0]enable [1]threshold [2]ratio [3]knee [4]knee_auto [5]gain [6]gain_auto
  ///  [7]attack [8]attack_auto [9]release [10]release_auto [11]knee_multi
  ///  [12]max_attack [13]max_release [14]crest [15]adapt [16]no_clip
  void writeToArray(Float32List arr, int offset) {
    arr[offset + 0] = enable ? 1.0 : 0.0;
    arr[offset + 1] = (threshold / -60.0).clamp(0.0, 1.0); // dB to 0..1
    arr[offset + 2] = ratio; // Native code negates it: ratio_ = -value
    arr[offset + 3] = (knee / 60.0).clamp(0.0, 1.0); // Assuming knee is dB width
    arr[offset + 4] = kneeAuto ? 1.0 : 0.0;
    arr[offset + 5] = (gain / 60.0).clamp(-1.0, 1.0); // dB to normalized
    arr[offset + 6] = gainAuto ? 1.0 : 0.0;
    arr[offset + 7] = _normalizeAttack(attack);
    arr[offset + 8] = attackAuto ? 1.0 : 0.0;
    arr[offset + 9] = _normalizeRelease(release);
    arr[offset + 10] = releaseAuto ? 1.0 : 0.0;
    arr[offset + 11] = kneeMulti;
    arr[offset + 12] = _normalizeAttack(maxAttack > 0 ? maxAttack : 100.0);
    arr[offset + 13] = _normalizeRelease(maxRelease > 0 ? maxRelease : 1000.0);
    arr[offset + 14] = _normalizeRelease(crest > 0 ? crest : 100.0); // crest uses same scale as release
    arr[offset + 15] = adapt > 0 ? (math.log(adapt) / 1.386294) : 0.660964; // adapt is in sec, 0.66 default
    arr[offset + 16] = noClip ? 1.0 : 0.0;
  }

  double _normalizeAttack(double ms) {
    if (ms <= 0.1) return 0.0;
    return ((math.log(ms / 1000.0) + 9.21034) / 7.600903).clamp(0.0, 1.0);
  }

  double _normalizeRelease(double ms) {
    if (ms <= 5.0) return 0.0;
    return ((math.log(ms / 1000.0) + 5.298317) / 5.991465).clamp(0.0, 1.0);
  }
}

class ViperDynamicEqBand {
  double frequencyHz;
  double q;
  double gainDb;
  double thresholdDb;
  double attackMs;
  double releaseMs;
  int filterType;

  ViperDynamicEqBand({
    this.frequencyHz = 1000.0,
    this.q = 1.0,
    this.gainDb = 0.0,
    this.thresholdDb = 0.0,
    this.attackMs = 20.0,
    this.releaseMs = 100.0,
    this.filterType = 0,
  });

  /// The C struct layout is 7 floats.
  ///  [0]frequency_hz [1]q [2]gain_db [3]threshold_db [4]attack_ms
  ///  [5]release_ms   [6]filter_type
  void writeToArray(Float32List arr, int offset) {
    arr[offset + 0] = frequencyHz;
    arr[offset + 1] = q;
    arr[offset + 2] = gainDb;
    arr[offset + 3] = thresholdDb;
    arr[offset + 4] = attackMs;
    arr[offset + 5] = releaseMs;
    arr[offset + 6] = filterType.toDouble();
  }
}

/// The main ViPER DSP integration class.
class ViperDsp {
  final AudioEngineFFI _audioEngine;
  late final ffi.DynamicLibrary _lib;
  late final ffi.Pointer<ffi.Void> _enginePtr;

  late final _ViperSetEnabledDart _setEnabled;
  late final _ViperSetSamplingRateDart _setSamplingRate;
  late final _ViperResetDart _reset;
  late final _ViperMasterLimiterDart _masterLimiter;
  late final _ViperPlaybackGainDart _playbackGain;
  late final _ViperLufsDart _lufs;
  late final _ViperFetCompressorDart _fetCompressor;
  late final _ViperBassDart _bass;
  late final _ViperBassMonoDart _bassMono;
  late final _ViperPsychoacousticBassDart _psychoacousticBass;
  late final _ViperSpectrumExtensionDart _spectrumExtension;
  late final _ViperEqualizerDart _equalizer;
  late final _ViperConvolverDart _convolver;
  late final _ViperLoadConvolverKernelDart _loadConvolverKernel;
  late final _ViperUnloadConvolverKernelDart _unloadConvolverKernel;
  late final _ViperDdcDart _ddc;
  late final _ViperLoadDdcCoefficientsDart _loadDdcCoefficients;
  late final _ViperFieldSurroundDart _fieldSurround;
  late final _ViperDiffSurroundDart _diffSurround;
  late final _ViperStereoImagerDart _stereoImager;
  late final _ViperHeadphoneSurroundDart _headphoneSurround;
  late final _ViperReverbDart _reverb;
  late final _ViperDynamicSystemDart _dynamicSystem;
  late final _ViperClarityDart _clarity;
  late final _ViperCureDart _cure;
  late final _ViperTubeSimulatorDart _tubeSimulator;
  late final _ViperAnalogXDart _analogX;
  late final _ViperSpeakerCorrectionDart _speakerCorrection;
  late final _ViperMultibandCompressorDart _multibandCompressor;
  late final _ViperDynamicEqDart _dynamicEq;
  late final _ViperAdaptiveLoudnessDart _adaptiveLoudness;

  late final _MallocDart _malloc;
  late final _FreeDart _free;

  ViperDsp(this._audioEngine) {
    _lib = _audioEngine.library;
    _enginePtr = _audioEngine.enginePointer;

    final allocLib = AudioEngineFFI.openAllocatorLibrary();
    _malloc = allocLib.lookupFunction<_MallocNative, _MallocDart>('malloc');
    _free = allocLib.lookupFunction<_FreeNative, _FreeDart>('free');

    _setEnabled = _lib.lookupFunction<_ViperSetEnabledNative, _ViperSetEnabledDart>('ae_viper_set_enabled');
    _setSamplingRate = _lib.lookupFunction<_ViperSetSamplingRateNative, _ViperSetSamplingRateDart>('ae_viper_set_sampling_rate');
    _reset = _lib.lookupFunction<_ViperResetNative, _ViperResetDart>('ae_viper_reset');
    _masterLimiter = _lib.lookupFunction<_ViperMasterLimiterNative, _ViperMasterLimiterDart>('ae_viper_master_limiter');
    _playbackGain = _lib.lookupFunction<_ViperPlaybackGainNative, _ViperPlaybackGainDart>('ae_viper_playback_gain');
    _lufs = _lib.lookupFunction<_ViperLufsNative, _ViperLufsDart>('ae_viper_lufs');
    _fetCompressor = _lib.lookupFunction<_ViperFetCompressorNative, _ViperFetCompressorDart>('ae_viper_fet_compressor');
    _bass = _lib.lookupFunction<_ViperBassNative, _ViperBassDart>('ae_viper_bass');
    _bassMono = _lib.lookupFunction<_ViperBassMonoNative, _ViperBassMonoDart>('ae_viper_bass_mono');
    _psychoacousticBass = _lib.lookupFunction<_ViperPsychoacousticBassNative, _ViperPsychoacousticBassDart>('ae_viper_psychoacoustic_bass');
    _spectrumExtension = _lib.lookupFunction<_ViperSpectrumExtensionNative, _ViperSpectrumExtensionDart>('ae_viper_spectrum_extension');
    _equalizer = _lib.lookupFunction<_ViperEqualizerNative, _ViperEqualizerDart>('ae_viper_equalizer');
    _convolver = _lib.lookupFunction<_ViperConvolverNative, _ViperConvolverDart>('ae_viper_convolver');
    _loadConvolverKernel = _lib.lookupFunction<_ViperLoadConvolverKernelNative, _ViperLoadConvolverKernelDart>('ae_viper_load_convolver_kernel');
    _unloadConvolverKernel = _lib.lookupFunction<_ViperUnloadConvolverKernelNative, _ViperUnloadConvolverKernelDart>('ae_viper_unload_convolver_kernel');
    _ddc = _lib.lookupFunction<_ViperDdcNative, _ViperDdcDart>('ae_viper_ddc');
    _loadDdcCoefficients = _lib.lookupFunction<_ViperLoadDdcCoefficientsNative, _ViperLoadDdcCoefficientsDart>('ae_viper_load_ddc_coefficients');
    _fieldSurround = _lib.lookupFunction<_ViperFieldSurroundNative, _ViperFieldSurroundDart>('ae_viper_field_surround');
    _diffSurround = _lib.lookupFunction<_ViperDiffSurroundNative, _ViperDiffSurroundDart>('ae_viper_diff_surround');
    _stereoImager = _lib.lookupFunction<_ViperStereoImagerNative, _ViperStereoImagerDart>('ae_viper_stereo_imager');
    _headphoneSurround = _lib.lookupFunction<_ViperHeadphoneSurroundNative, _ViperHeadphoneSurroundDart>('ae_viper_headphone_surround');
    _reverb = _lib.lookupFunction<_ViperReverbNative, _ViperReverbDart>('ae_viper_reverb');
    _dynamicSystem = _lib.lookupFunction<_ViperDynamicSystemNative, _ViperDynamicSystemDart>('ae_viper_dynamic_system');
    _clarity = _lib.lookupFunction<_ViperClarityNative, _ViperClarityDart>('ae_viper_clarity');
    _cure = _lib.lookupFunction<_ViperCureNative, _ViperCureDart>('ae_viper_cure');
    _tubeSimulator = _lib.lookupFunction<_ViperTubeSimulatorNative, _ViperTubeSimulatorDart>('ae_viper_tube_simulator');
    _analogX = _lib.lookupFunction<_ViperAnalogXNative, _ViperAnalogXDart>('ae_viper_analog_x');
    _speakerCorrection = _lib.lookupFunction<_ViperSpeakerCorrectionNative, _ViperSpeakerCorrectionDart>('ae_viper_speaker_correction');
    _multibandCompressor = _lib.lookupFunction<_ViperMultibandCompressorNative, _ViperMultibandCompressorDart>('ae_viper_multiband_compressor');
    _dynamicEq = _lib.lookupFunction<_ViperDynamicEqNative, _ViperDynamicEqDart>('ae_viper_dynamic_eq');
    _adaptiveLoudness = _lib.lookupFunction<_ViperAdaptiveLoudnessNative, _ViperAdaptiveLoudnessDart>('ae_viper_adaptive_loudness');
  }

  void _freePtr(ffi.Pointer<ffi.Void> ptr) {
    if (ptr != ffi.nullptr) {
      _free(ptr);
    }
  }

  /// Enable or disable the entire ViPER DSP chain.
  void setEnabled(bool enabled) {
    if (_enginePtr == ffi.nullptr) return;
    _setEnabled(_enginePtr, enabled ? 1 : 0);
  }

  /// Update the sample rate ViPER uses internally.
  /// Call whenever the engine sample rate changes.
  void setSamplingRate(int sampleRate) {
    if (_enginePtr == ffi.nullptr) return;
    _setSamplingRate(_enginePtr, sampleRate);
  }

  /// Request a full reset of all ViPER effects and internal buffers.
  void reset() {
    if (_enginePtr == ffi.nullptr) return;
    _reset(_enginePtr);
  }

  /// Master output limiter / volume / pan.
  ///   [threshold]    [0..1]  - soft-limiter gate level  (default 1.0)
  ///   [outputVolume] [0..1]  - master output scale       (default 1.0)
  ///   [channelPan]   [-1..1] - stereo pan                (default 0.0)
  void setMasterLimiter({
    double threshold = 1.0,
    double outputVolume = 1.0,
    double channelPan = 0.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _masterLimiter(_enginePtr, threshold, outputVolume, channelPan);
  }

  /// Automatic playback gain control (AGC).
  void setPlaybackGain({
    required bool enable,
    double strength = 0.5,
    double maxGain = 0.5,
    double outputThreshold = 0.9,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _playbackGain(_enginePtr, enable ? 1 : 0, strength, maxGain, outputThreshold);
  }

  /// LUFS-based loudness normalisation.
  ///   [target]   - LUFS target level  (e.g. -14.0)
  ///   [maxGainDb] - maximum boost in dB
  ///   [speed]    - convergence speed
  void setLufs({
    required bool enable,
    double target = -14.0,
    double maxGainDb = 6.0,
    ViperLufsSpeed speed = ViperLufsSpeed.medium,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _lufs(_enginePtr, enable ? 1 : 0, target, maxGainDb, speed.index);
  }

  /// FET-style dynamics compressor.
  void setFetCompressor({
    required bool enable,
    double threshold = 0.0,
    double ratio = 0.0,
    double knee = 0.0,
    bool kneeAuto = false,
    double gain = 0.0,
    bool gainAuto = false,
    double attack = 0.0,
    bool attackAuto = false,
    double release = 0.0,
    bool releaseAuto = false,
    double kneeMulti = 0.0,
    double maxAttack = 0.0,
    double maxRelease = 0.0,
    double crest = 0.0,
    double adapt = 0.0,
    bool noClip = false,
  }) {
    double nThreshold = (threshold / -60.0).clamp(0.0, 1.0);
    double nGain = (gain / 60.0).clamp(-1.0, 1.0);
    double nKnee = (knee / 60.0).clamp(0.0, 1.0);
    double nAttack = attack <= 0.1 ? 0.0 : ((math.log(attack / 1000.0) + 9.21034) / 7.600903).clamp(0.0, 1.0);
    double nRelease = release <= 5.0 ? 0.0 : ((math.log(release / 1000.0) + 5.298317) / 5.991465).clamp(0.0, 1.0);
    double nMaxAttack = maxAttack <= 0.1 ? 0.879450 : ((math.log(maxAttack / 1000.0) + 9.21034) / 7.600903).clamp(0.0, 1.0);
    double nMaxRelease = maxRelease <= 5.0 ? 0.884311 : ((math.log(maxRelease / 1000.0) + 5.298317) / 5.991465).clamp(0.0, 1.0);
    double nCrest = crest <= 5.0 ? 0.615689 : ((math.log(crest / 1000.0) + 5.298317) / 5.991465).clamp(0.0, 1.0);
    double nAdapt = adapt <= 0.0 ? 0.660964 : (math.log(adapt) / 1.386294).clamp(0.0, 1.0);

    _fetCompressor(
      _enginePtr, enable ? 1 : 0, nThreshold, ratio, nKnee, kneeAuto ? 1 : 0,
      nGain, gainAuto ? 1 : 0, nAttack, attackAuto ? 1 : 0, nRelease, releaseAuto ? 1 : 0,
      kneeMulti, nMaxAttack, nMaxRelease, nCrest, nAdapt, noClip ? 1 : 0,
    );
  }

  /// ViPER Bass (stereo bass boost).
  void setBass({
    required bool enable,
    ViperBassMode mode = ViperBassMode.natural,
    int frequencyHz = 80,
    double gain = 0.5,
    bool antiPop = false,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _bass(_enginePtr, enable ? 1 : 0, mode.index, frequencyHz, gain, antiPop ? 1 : 0);
  }

  /// ViPER Bass in mono (sub-bass reinforcement).
  void setBassMono({
    required bool enable,
    ViperBassMode mode = ViperBassMode.natural,
    int frequencyHz = 80,
    double gain = 0.5,
    bool antiPop = false,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _bassMono(_enginePtr, enable ? 1 : 0, mode.index, frequencyHz, gain, antiPop ? 1 : 0);
  }

  /// Psychoacoustic bass (harmonic synthesis).
  void setPsychoacousticBass({
    required bool enable,
    int cutoffHz = 80,
    int intensity = 50,
    int harmonicOrder = 2,
    int originalLevel = 100,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _psychoacousticBass(_enginePtr, enable ? 1 : 0, cutoffHz, intensity, harmonicOrder, originalLevel);
  }

  /// Spectrum extension (high-frequency air / exciter).
  void setSpectrumExtension({
    required bool enable,
    int strength = 50,
    double exciter = 0.5,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _spectrumExtension(_enginePtr, enable ? 1 : 0, strength, exciter);
  }

  /// 31-band graphic equaliser.
  /// [bandLevels] should contain values [0..1] where 0.5 = flat. Max 31 elements.
  void setEqualizer({
    required bool enable,
    required List<double> bandLevels,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    
    int count = bandLevels.length;
    if (count > 31) count = 31;

    final ptr = _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    try {
      final list = ptr.asTypedList(count);
      for (int i = 0; i < count; i++) {
        list[i] = bandLevels[i];
      }
      _equalizer(_enginePtr, enable ? 1 : 0, count, ptr);
    } finally {
      _freePtr(ptr.cast<ffi.Void>());
    }
  }

  /// Impulse-response convolver.
  void setConvolver({
    required bool enable,
    double crossChannel = 0.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _convolver(_enginePtr, enable ? 1 : 0, crossChannel);
  }

  /// Load an impulse-response kernel into the convolver.
  /// Returns the assigned kernel ID on success, 0 on failure.
  int loadConvolverKernel(Float32List samples, int channels, int kernelId) {
    if (_enginePtr == ffi.nullptr) return 0;
    
    int frameCount = samples.length ~/ channels;
    final ptr = _malloc(samples.length * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    
    try {
      final list = ptr.asTypedList(samples.length);
      list.setAll(0, samples);
      return _loadConvolverKernel(_enginePtr, ptr, frameCount, channels, kernelId);
    } finally {
      _freePtr(ptr.cast<ffi.Void>());
    }
  }

  /// Unload the currently loaded convolver kernel.
  void unloadConvolverKernel() {
    if (_enginePtr == ffi.nullptr) return;
    _unloadConvolverKernel(_enginePtr);
  }

  /// DDC (Device-Dependent Correction) filter.
  void setDdc(bool enable) {
    if (_enginePtr == ffi.nullptr) return;
    _ddc(_enginePtr, enable ? 1 : 0);
  }

  /// Load DDC biquad-section coefficients.
  /// Each section is 5 floats: [b0, b1, b2, a1, a2].
  /// [sections44100] and [sections48000] should each have length = sectionCount * 5.
  void loadDdcCoefficients({
    required List<double> sections44100,
    required List<double> sections48000,
    required int sectionCount,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    
    int expectedLength = sectionCount * 5;
    if (sections44100.length < expectedLength || sections48000.length < expectedLength) return;

    final ptr44100 = _malloc(expectedLength * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final ptr48000 = _malloc(expectedLength * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    
    try {
      final list44100 = ptr44100.asTypedList(expectedLength);
      list44100.setAll(0, sections44100.take(expectedLength));
      
      final list48000 = ptr48000.asTypedList(expectedLength);
      list48000.setAll(0, sections48000.take(expectedLength));

      _loadDdcCoefficients(_enginePtr, ptr44100, ptr48000, sectionCount);
    } finally {
      _freePtr(ptr44100.cast<ffi.Void>());
      _freePtr(ptr48000.cast<ffi.Void>());
    }
  }

  /// Field Surround (ColorfulMusic).
  void setFieldSurround({
    required bool enable,
    double widening = 0.5,
    double midImage = 0.5,
    int depth = 2,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _fieldSurround(_enginePtr, enable ? 1 : 0, widening, midImage, depth);
  }

  /// Differential Surround.
  void setDiffSurround({
    required bool enable,
    double delay = 0.5,
    bool reverse = false,
    double wetDryMix = 0.5,
    double lpCutoffHz = 8000.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _diffSurround(_enginePtr, enable ? 1 : 0, delay, reverse ? 1 : 0, wetDryMix, lpCutoffHz);
  }

  /// Multiband stereo imager.
  /// Width percentages [0..200] (100 = unchanged).
  void setStereoImager({
    required bool enable,
    double lowWidth = 100.0,
    double midWidth = 100.0,
    double highWidth = 100.0,
    double lowCrossoverHz = 300.0,
    double highCrossoverHz = 3000.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _stereoImager(_enginePtr, enable ? 1 : 0, lowWidth, midWidth, highWidth, lowCrossoverHz, highCrossoverHz);
  }

  /// Headphone surround (ViPER Headphone Engine / VHE).
  void setHeadphoneSurround({
    required bool enable,
    int quality = 2,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _headphoneSurround(_enginePtr, enable ? 1 : 0, quality);
  }

  /// ViPER Reverberation.
  void setReverb({
    required bool enable,
    double roomSize = 0.5,
    double width = 0.5,
    double damp = 0.5,
    double wet = 0.5,
    double dry = 0.5,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _reverb(_enginePtr, enable ? 1 : 0, roomSize, width, damp, wet, dry);
  }

  /// Dynamic System (psychoacoustic mid/bass enhancement).
  void setDynamicSystem({
    required bool enable,
    int xCoeffLow = 0,
    int xCoeffHigh = 0,
    int yCoeffLow = 0,
    int yCoeffHigh = 0,
    double sideGainLow = 0.0,
    double sideGainHigh = 0.0,
    double strength = 0.5,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _dynamicSystem(_enginePtr, enable ? 1 : 0, xCoeffLow, xCoeffHigh, yCoeffLow, yCoeffHigh, sideGainLow, sideGainHigh, strength);
  }

  /// Clarity (detail / resolution enhancement).
  void setClarity({
    required bool enable,
    ViperClarityMode mode = ViperClarityMode.natural,
    double gain = 0.5,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _clarity(_enginePtr, enable ? 1 : 0, mode.index, gain);
  }

  /// Cure (BS2B-style crossfeed for headphones).
  void setCure({
    required bool enable,
    ViperCureCrossfeedPreset preset = ViperCureCrossfeedPreset.off,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _cure(_enginePtr, enable ? 1 : 0, preset.index);
  }

  /// Tube Simulator (soft harmonic saturation).
  void setTubeSimulator(bool enable) {
    if (_enginePtr == ffi.nullptr) return;
    _tubeSimulator(_enginePtr, enable ? 1 : 0);
  }

  /// AnalogX (analog warmth simulation).
  void setAnalogX({
    required bool enable,
    ViperAnalogXMode mode = ViperAnalogXMode.moderate,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _analogX(_enginePtr, enable ? 1 : 0, mode.index);
  }

  /// Speaker Correction (impulse-based room/speaker correction).
  void setSpeakerCorrection(bool enable) {
    if (_enginePtr == ffi.nullptr) return;
    _speakerCorrection(_enginePtr, enable ? 1 : 0);
  }

  /// Multiband Compressor (up to 5 bands).
  void setMultibandCompressor({
    required bool enable,
    required List<double> crossoverFreqs,
    required List<ViperMultibandCompressorBand> bands,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    
    int count = bands.length;
    if (count > 5) count = 5;

    final crossPtr = _malloc(4 * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final paramsPtr = _malloc(count * 17 * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    
    try {
      final crossList = crossPtr.asTypedList(4);
      for (int i = 0; i < 4 && i < crossoverFreqs.length; i++) {
        crossList[i] = crossoverFreqs[i];
      }

      final paramsList = paramsPtr.asTypedList(count * 17);
      for (int i = 0; i < count; i++) {
        bands[i].writeToArray(paramsList, i * 17);
      }

      _multibandCompressor(_enginePtr, enable ? 1 : 0, count, crossPtr, paramsPtr);
    } finally {
      _freePtr(crossPtr.cast<ffi.Void>());
      _freePtr(paramsPtr.cast<ffi.Void>());
    }
  }

  /// Dynamic EQ (up to 8 bands).
  void setDynamicEq({
    required bool enable,
    required List<ViperDynamicEqBand> bands,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    
    int count = bands.length;
    if (count > 8) count = 8;

    final ptr = _malloc(count * 7 * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    
    try {
      final list = ptr.asTypedList(count * 7);
      for (int i = 0; i < count; i++) {
        bands[i].writeToArray(list, i * 7);
      }

      _dynamicEq(_enginePtr, enable ? 1 : 0, count, ptr);
    } finally {
      _freePtr(ptr.cast<ffi.Void>());
    }
  }

  /// Adaptive Loudness Compensation (ALC).
  /// Dynamically adjusts low-shelf and high-shelf EQ based on volume attenuation.
  void setAdaptiveLoudness({
    required bool enable,
    ViperAlcMode mode = ViperAlcMode.natural,
    double strength = 1.0,
    double attenuationDb = 0.0,
  }) {
    if (_enginePtr == ffi.nullptr) return;
    _adaptiveLoudness(_enginePtr, enable ? 1 : 0, mode.index, strength, attenuationDb);
  }
}
