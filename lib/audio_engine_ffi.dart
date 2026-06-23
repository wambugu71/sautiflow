import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

enum LoopMode { off, all, one }

enum AudioFormat { f32, s16, u8, s24, s32 }

enum EqBandType { peak, bandpass, notch, lowshelf, highshelf }

class EqBandConfig {
  const EqBandConfig({
    required this.type,
    required this.frequencyHz,
    this.enabled = true,
    this.q = 1.0,
    this.gainDb = 0.0,
    this.slope = 1.0,
  });

  final EqBandType type;
  final double frequencyHz;
  final bool enabled;
  final double q;
  final double gainDb;
  final double slope;
}

class AudioSource {
  final Uri uri;
  const AudioSource.uri(this.uri);

  factory AudioSource.file(String path) => AudioSource.uri(Uri.file(path));
  factory AudioSource.network(String url) => AudioSource.uri(Uri.parse(url));

  bool get isNetwork => uri.scheme == 'http' || uri.scheme == 'https';
}

typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

final class PlayerStatusNative extends ffi.Struct {
  @ffi.Double()
  external double position_seconds;

  @ffi.Double()
  external double duration_seconds;

  @ffi.Int32()
  external int is_playing;

  @ffi.Int32()
  external int current_index;

  @ffi.Int32()
  external int playlist_count;

  @ffi.Int32()
  external int shuffle_enabled;

  @ffi.Int32()
  external int loop_mode;
}

final class PipelineStateNative extends ffi.Struct {
  @ffi.Int32()
  external int input_format;
  @ffi.Int32()
  external int input_sample_rate;
  @ffi.Int32()
  external int input_channels;

  @ffi.Int32()
  external int processing_format;
  @ffi.Int32()
  external int processing_sample_rate;
  @ffi.Int32()
  external int processing_channels;

  @ffi.Int32()
  external int output_format;
  @ffi.Int32()
  external int output_sample_rate;
  @ffi.Int32()
  external int output_channels;

  @ffi.Int32()
  external int eq_enabled;
  @ffi.Int32()
  external int reverb_enabled;
  @ffi.Int32()
  external int limiter_enabled;
  @ffi.Int32()
  external int stereo_widen_enabled;
  @ffi.Int32()
  external int spatialization_enabled;
  @ffi.Int32()
  external int delay_enabled;

  @ffi.Float()
  external double gain;
  @ffi.Float()
  external double pan;
  @ffi.Float()
  external double pitch;
}

typedef _CreateEngineNative = ffi.Pointer<ffi.Void> Function(
    ffi.Int32, ffi.Int32);
typedef _CreateEngineDart = ffi.Pointer<ffi.Void> Function(int, int);

typedef _DestroyEngineNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DestroyEngineDart = void Function(ffi.Pointer<ffi.Void>);

typedef _SetPlaylistNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Char>>,
  ffi.Int32,
);
typedef _SetPlaylistDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Char>>,
  int,
);

typedef _AddToPlaylistNative = ffi.Uint8 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>);
typedef _AddToPlaylistDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>);

typedef _InsertToPlaylistNative = ffi.Uint8 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Pointer<ffi.Char>);
typedef _InsertToPlaylistDart = int Function(
    ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Char>);

typedef _RemoveFromPlaylistNative = ffi.Uint8 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _RemoveFromPlaylistDart = int Function(ffi.Pointer<ffi.Void>, int);

typedef _MovePlaylistItemNative = ffi.Uint8 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _MovePlaylistItemDart = int Function(ffi.Pointer<ffi.Void>, int, int);

typedef _ClearPlaylistNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ClearPlaylistDart = void Function(ffi.Pointer<ffi.Void>);

typedef _BoolOpNative = ffi.Uint8 Function(ffi.Pointer<ffi.Void>);
typedef _BoolOpDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SeekNative = ffi.Uint8 Function(ffi.Pointer<ffi.Void>, ffi.Double);
typedef _SeekDart = int Function(ffi.Pointer<ffi.Void>, double);

typedef _JumpNative = ffi.Uint8 Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _JumpDart = int Function(ffi.Pointer<ffi.Void>, int);

typedef _JumpWithPositionNative = ffi.Uint8 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Double);
typedef _JumpWithPositionDart = int Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _SetIntNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetIntDart = void Function(ffi.Pointer<ffi.Void>, int);
typedef _GetIntNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetIntDart = int Function(ffi.Pointer<ffi.Void>);

typedef _GetDeviceLatencyMsNative = ffi.Float Function(ffi.Pointer<ffi.Void>);
typedef _GetDeviceLatencyMsDart = double Function(ffi.Pointer<ffi.Void>);

typedef _GetStatusNative = PlayerStatusNative Function(ffi.Pointer<ffi.Void>);
typedef _GetStatusDart = PlayerStatusNative Function(ffi.Pointer<ffi.Void>);

typedef _GetPipelineStateNative = PipelineStateNative Function(
    ffi.Pointer<ffi.Void>);
typedef _GetPipelineStateDart = PipelineStateNative Function(
    ffi.Pointer<ffi.Void>);

typedef _GetLastErrorNative = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Void>,
);
typedef _GetLastErrorDart = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Void>,
);

typedef _ClearLastErrorNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ClearLastErrorDart = void Function(ffi.Pointer<ffi.Void>);

typedef _SetFxEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetFxEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SetReverbParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _SetReverbParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double);

typedef _SetEqGainsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _SetEqGainsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double);

// Custom Filter Typedefs
typedef _SetCustomLpf1ParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Double);
typedef _SetCustomLpf1ParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _SetCustomBiquadParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int32,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double);
typedef _SetCustomBiquadParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double, double, double, double, double);

typedef _SetSingleFloatNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float);
typedef _SetSingleFloatDart = void Function(ffi.Pointer<ffi.Void>, double);
typedef _SetTwoFloatsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float);
typedef _SetTwoFloatsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double);

// Spatialization Typedefs
// ae_set_spatialization_enabled(AudioEngineHandle *engine, int enabled)
typedef _SetSpatializationEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetSpatializationEnabledDart = void Function(
    ffi.Pointer<ffi.Void>, int);

// ae_set_position, ae_set_direction, ae_set_velocity (engine, x, y, z)
typedef _SetSpatializationVec3Native = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _SetSpatializationVec3Dart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double);

typedef _SetSingleIntNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetSingleIntDart = void Function(ffi.Pointer<ffi.Void>, int);

// Fading & Scheduling
typedef _SetFadeInMillisecondsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Int32);
typedef _SetFadeInMillisecondsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, int);

typedef _SetStereoWidenNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float, ffi.Float);
typedef _SetStereoWidenDart = void Function(
    ffi.Pointer<ffi.Void>, int, double, double);

typedef _SetDynamicBassParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _SetDynamicBassParamsDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

// Crystalizer typedefs
typedef _SetCrystalizerEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetCrystalizerEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SetCrystalizerParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Int32, ffi.Float);
typedef _SetCrystalizerParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, int, double);

typedef _GetCrystalizerIntensityNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>);
typedef _GetCrystalizerIntensityDart = double Function(ffi.Pointer<ffi.Void>);

typedef _SetTimeInPcmFramesNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Uint64);
typedef _SetTimeInPcmFramesDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetEngineTimeInPcmFramesNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void>);
typedef _GetEngineTimeInPcmFramesDart = int Function(ffi.Pointer<ffi.Void>);

// End Callback
typedef _EndCallbackNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef _SetEndCallbackNative = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.NativeFunction<_EndCallbackNative>>, ffi.Pointer<ffi.Void>);
typedef _SetEndCallbackDart = void Function(ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.NativeFunction<_EndCallbackNative>>, ffi.Pointer<ffi.Void>);

typedef _SetExclusiveModeNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetExclusiveModeDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetExclusiveModeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetExclusiveModeDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetOutputFormatNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetOutputFormatDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetOutputFormatNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetOutputFormatDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetOutputRateNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetOutputRateDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetOutputRateNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetOutputRateDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetOutputChannelsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetOutputChannelsDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetOutputChannelsNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetOutputChannelsDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetEngineResampleAlgorithmNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetEngineResampleAlgorithmDart = void Function(
    ffi.Pointer<ffi.Void>, int);

typedef _GetEngineResampleAlgorithmNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>);
typedef _GetEngineResampleAlgorithmDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SetEngineDitherModeNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetEngineDitherModeDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetEngineDitherModeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetEngineDitherModeDart = int Function(ffi.Pointer<ffi.Void>);

// Limiter & Clipping Detection
typedef _SetLimiterEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetLimiterEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SetLimiterParamsNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float, ffi.Float);
typedef _SetLimiterParamsDart = void Function(
    ffi.Pointer<ffi.Void>, double, double, double);

typedef _SetClippingDetectionEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetClippingDetectionEnabledDart = void Function(
    ffi.Pointer<ffi.Void>, int);

typedef _GetClippedSamplesCountNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void>);
typedef _GetClippedSamplesCountDart = int Function(ffi.Pointer<ffi.Void>);

typedef _ResetClippedSamplesCountNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>);
typedef _ResetClippedSamplesCountDart = void Function(ffi.Pointer<ffi.Void>);

typedef _InitMultibandEqNative = ffi.Void Function(ffi.Pointer<ffi.Void>,
    ffi.Int32, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);
typedef _InitMultibandEqDart = void Function(
    ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);

typedef _SetMultibandEqEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetMultibandEqEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SetMultibandEqGainNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Float);
typedef _SetMultibandEqGainDart = void Function(
    ffi.Pointer<ffi.Void>, int, double);

typedef _GetMultibandEqGainNative = ffi.Float Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _GetMultibandEqGainDart = double Function(ffi.Pointer<ffi.Void>, int);

typedef _SetMultibandFxEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetMultibandFxEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _SetMultibandFxBandsNative = ffi.Void Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Int32>,
);
typedef _SetMultibandFxBandsDart = void Function(
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Int32>,
);

typedef _ClearMultibandFxNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ClearMultibandFxDart = void Function(ffi.Pointer<ffi.Void>);

typedef _InitPushStreamNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _InitPushStreamDart = void Function(ffi.Pointer<ffi.Void>);

typedef _PushStreamChunkNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _PushStreamChunkDart = void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);

typedef _EndPushStreamNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _EndPushStreamDart = void Function(ffi.Pointer<ffi.Void>);

typedef _GetPushStreamBufferedBytesNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>);
typedef _GetPushStreamBufferedBytesDart = int Function(ffi.Pointer<ffi.Void>);

typedef _GetNetworkStreamingSupportNative = ffi.Int32 Function();
typedef _GetNetworkStreamingSupportDart = int Function();

typedef _SetAnalyzerEnabledNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SetAnalyzerEnabledDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _ConfigureAnalyzerNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _ConfigureAnalyzerDart = void Function(ffi.Pointer<ffi.Void>, int);

typedef _GetAnalyzerFrameSizeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _GetAnalyzerFrameSizeDart = int Function(ffi.Pointer<ffi.Void>);

typedef _PollAnalyzerFrameNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef _PollAnalyzerFrameDart = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>, int);

typedef _GetAnalyzerDroppedFramesNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void>);
typedef _GetAnalyzerDroppedFramesDart = int Function(ffi.Pointer<ffi.Void>);

class PlayerStatus {
  final double positionSeconds;
  final double durationSeconds;
  final bool isPlaying;
  final int currentIndex;
  final int playlistCount;
  final bool shuffleEnabled;
  final LoopMode loopMode;

  const PlayerStatus({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.isPlaying,
    required this.currentIndex,
    required this.playlistCount,
    required this.shuffleEnabled,
    required this.loopMode,
  });
}

class PipelineAudioState {
  final int inputFormat;
  final int inputSampleRate;
  final int inputChannels;
  final int processingFormat;
  final int processingSampleRate;
  final int processingChannels;
  final int outputFormat;
  final int outputSampleRate;
  final int outputChannels;

  final bool eqEnabled;
  final bool reverbEnabled;
  final bool limiterEnabled;
  final bool stereoWidenEnabled;
  final bool spatializationEnabled;
  final bool delayEnabled;

  final double gain;
  final double pan;
  final double pitch;

  const PipelineAudioState({
    required this.inputFormat,
    required this.inputSampleRate,
    required this.inputChannels,
    required this.processingFormat,
    required this.processingSampleRate,
    required this.processingChannels,
    required this.outputFormat,
    required this.outputSampleRate,
    required this.outputChannels,
    required this.eqEnabled,
    required this.reverbEnabled,
    required this.limiterEnabled,
    required this.stereoWidenEnabled,
    required this.spatializationEnabled,
    required this.delayEnabled,
    required this.gain,
    required this.pan,
    required this.pitch,
  });

  factory PipelineAudioState.fromNative(PipelineStateNative native) {
    return PipelineAudioState(
      inputFormat: native.input_format,
      inputSampleRate: native.input_sample_rate,
      inputChannels: native.input_channels,
      processingFormat: native.processing_format,
      processingSampleRate: native.processing_sample_rate,
      processingChannels: native.processing_channels,
      outputFormat: native.output_format,
      outputSampleRate: native.output_sample_rate,
      outputChannels: native.output_channels,
      eqEnabled: native.eq_enabled != 0,
      reverbEnabled: native.reverb_enabled != 0,
      limiterEnabled: native.limiter_enabled != 0,
      stereoWidenEnabled: native.stereo_widen_enabled != 0,
      spatializationEnabled: native.spatialization_enabled != 0,
      delayEnabled: native.delay_enabled != 0,
      gain: native.gain,
      pan: native.pan,
      pitch: native.pitch,
    );
  }

  factory PipelineAudioState.empty() {
    return const PipelineAudioState(
      inputFormat: 0,
      inputSampleRate: 0,
      inputChannels: 0,
      processingFormat: 0,
      processingSampleRate: 0,
      processingChannels: 0,
      outputFormat: 0,
      outputSampleRate: 0,
      outputChannels: 0,
      eqEnabled: false,
      reverbEnabled: false,
      limiterEnabled: false,
      stereoWidenEnabled: false,
      spatializationEnabled: false,
      delayEnabled: false,
      gain: 0.0,
      pan: 0.0,
      pitch: 0.0,
    );
  }

  String formatToString(int format) {
    switch (format) {
      case 1:
        return '8-bit Unsigned';
      case 2:
        return '16-bit Signed';
      case 3:
        return '24-bit Signed';
      case 4:
        return '32-bit Signed';
      case 5:
        return '32-bit Float';
      default:
        return 'Unknown ($format)';
    }
  }

  String get inputFormatString => formatToString(inputFormat);
  String get processingFormatString => formatToString(processingFormat);
  String get outputFormatString => formatToString(outputFormat);
}

class AudioEngineFFI {
  AudioEngineFFI({String? libraryPath})
      : _lib = openLibrary(libraryPath),
        _engine = ffi.nullptr {
    final allocLib = openAllocatorLibrary();
    _malloc = allocLib.lookupFunction<_MallocNative, _MallocDart>('malloc');
    _free = allocLib.lookupFunction<_FreeNative, _FreeDart>('free');

    _createEngine = _lib.lookupFunction<_CreateEngineNative, _CreateEngineDart>(
      'ae_create_engine',
    );
    _destroyEngine =
        _lib.lookupFunction<_DestroyEngineNative, _DestroyEngineDart>(
      'ae_destroy_engine',
    );
    _setPlaylist = _lib.lookupFunction<_SetPlaylistNative, _SetPlaylistDart>(
      'ae_set_playlist',
    );
    _addToPlaylist =
        _lib.lookupFunction<_AddToPlaylistNative, _AddToPlaylistDart>(
      'ae_add_to_playlist',
    );
    _insertToPlaylist =
        _lib.lookupFunction<_InsertToPlaylistNative, _InsertToPlaylistDart>(
      'ae_insert_to_playlist',
    );
    _removeFromPlaylist =
        _lib.lookupFunction<_RemoveFromPlaylistNative, _RemoveFromPlaylistDart>(
      'ae_remove_from_playlist',
    );
    _movePlaylistItem =
        _lib.lookupFunction<_MovePlaylistItemNative, _MovePlaylistItemDart>(
      'ae_move_playlist_item',
    );
    _clearPlaylist =
        _lib.lookupFunction<_ClearPlaylistNative, _ClearPlaylistDart>(
      'ae_clear_playlist',
    );

    _play = _lib.lookupFunction<_BoolOpNative, _BoolOpDart>('ae_play');
    _pause = _lib.lookupFunction<_BoolOpNative, _BoolOpDart>('ae_pause');
    _stop = _lib.lookupFunction<_BoolOpNative, _BoolOpDart>('ae_stop');
    _next = _lib.lookupFunction<_BoolOpNative, _BoolOpDart>('ae_next');
    _prev = _lib.lookupFunction<_BoolOpNative, _BoolOpDart>('ae_prev');

    _seek = _lib.lookupFunction<_SeekNative, _SeekDart>('ae_seek');
    _jumpTo = _lib.lookupFunction<_JumpNative, _JumpDart>('ae_jump_to');
    _jumpToWithPosition =
        _lib.lookupFunction<_JumpWithPositionNative, _JumpWithPositionDart>(
      'ae_jump_to_with_position',
    );
    _getDeviceLatencyMs = _lib.lookupFunction<_GetDeviceLatencyMsNative,
        _GetDeviceLatencyMsDart>('ae_get_device_latency_ms');
    _getStatus = _lib.lookupFunction<_GetStatusNative, _GetStatusDart>(
      'ae_get_status',
    );
    _getPipelineState =
        _lib.lookupFunction<_GetPipelineStateNative, _GetPipelineStateDart>(
      'ae_get_pipeline_state',
    );
    _getLastError = _lib.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
      'ae_get_last_error',
    );
    _clearLastError =
        _lib.lookupFunction<_ClearLastErrorNative, _ClearLastErrorDart>(
      'ae_clear_last_error',
    );

    _setLoopMode = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
      'ae_set_loop_mode',
    );
    _setShuffleEnabled = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
      'ae_set_shuffle_enabled',
    );
    _reshuffle = _lib.lookupFunction<_ClearPlaylistNative, _ClearPlaylistDart>(
      'ae_reshuffle',
    );
    _setCrossfadeEnabled = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
      'ae_set_crossfade_enabled',
    );
    _getCrossfadeEnabled = _lib.lookupFunction<_GetIntNative, _GetIntDart>(
      'ae_get_crossfade_enabled',
    );
    _setCrossfadeDurationMs = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
      'ae_set_crossfade_duration_ms',
    );
    _getCrossfadeDurationMs = _lib.lookupFunction<_GetIntNative, _GetIntDart>(
      'ae_get_crossfade_duration_ms',
    );

    _setReverbEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_reverb_enabled',
    );
    _setReverbParams =
        _lib.lookupFunction<_SetReverbParamsNative, _SetReverbParamsDart>(
      'ae_set_reverb_params',
    );
    _setEqEnabled = _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_eq_enabled',
    );
    _setEqGains = _lib.lookupFunction<_SetEqGainsNative, _SetEqGainsDart>(
      'ae_set_eq_gains',
    );
    _setGain = _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_gain',
    );
    try {
      _setReplayGain =
          _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
        'ae_set_replay_gain',
      );
    } catch (_) {
      _setReplayGain = null;
    }
    _setPan = _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_pan',
    );
    _setPitch = _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_pitch',
    );
    _setLowpassEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_lowpass_enabled',
    );
    _setLowpassCutoff =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_lowpass_cutoff',
    );
    _setHighpassEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_highpass_enabled',
    );
    _setHighpassCutoff =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_highpass_cutoff',
    );
    _setDelayEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_delay_enabled',
    );
    _setDelayParams =
        _lib.lookupFunction<_SetReverbParamsNative, _SetReverbParamsDart>(
      'ae_set_delay_params',
    );
    _setStereoWiden =
        _lib.lookupFunction<_SetStereoWidenNative, _SetStereoWidenDart>(
      'ae_set_stereo_widen',
    );
    _setCrossfeedEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_crossfeed_enabled',
    );
    _setCrossfeedPreset =
        _lib.lookupFunction<_SetSingleIntNative, _SetSingleIntDart>(
      'ae_set_crossfeed_preset',
    );
    _setDynamicBassEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_dynamic_bass_enabled',
    );
    _setDynamicBassParams = _lib
        .lookupFunction<_SetDynamicBassParamsNative, _SetDynamicBassParamsDart>(
      'ae_set_dynamic_bass_params',
    );
    // Crystalizer
    _setCrystalizerEnabled = _lib.lookupFunction<_SetCrystalizerEnabledNative,
        _SetCrystalizerEnabledDart>('ae_set_crystalizer_enabled');
    _setCrystalizerParams = _lib.lookupFunction<_SetCrystalizerParamsNative,
        _SetCrystalizerParamsDart>('ae_set_crystalizer_params');
    _getCrystalizerIntensity = _lib.lookupFunction<
        _GetCrystalizerIntensityNative,
        _GetCrystalizerIntensityDart>('ae_get_crystalizer_intensity');
    _setBandpassEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_bandpass_enabled',
    );
    _setBandpassParams =
        _lib.lookupFunction<_SetTwoFloatsNative, _SetTwoFloatsDart>(
      'ae_set_bandpass_params',
    );
    _setPeakEqEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_peak_eq_enabled',
    );
    _setPeakEqParams =
        _lib.lookupFunction<_SetReverbParamsNative, _SetReverbParamsDart>(
      'ae_set_peak_eq_params',
    );
    _setNotchEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_notch_enabled',
    );
    _setNotchParams =
        _lib.lookupFunction<_SetTwoFloatsNative, _SetTwoFloatsDart>(
      'ae_set_notch_params',
    );
    _setLowshelfEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_lowshelf_enabled',
    );
    _setLowshelfParams =
        _lib.lookupFunction<_SetReverbParamsNative, _SetReverbParamsDart>(
      'ae_set_lowshelf_params',
    );
    _setHighshelfEnabled =
        _lib.lookupFunction<_SetFxEnabledNative, _SetFxEnabledDart>(
      'ae_set_highshelf_enabled',
    );
    _setHighshelfParams =
        _lib.lookupFunction<_SetReverbParamsNative, _SetReverbParamsDart>(
      'ae_set_highshelf_params',
    );

    // Custom Filters
    _setCustomLpf1Params = _lib
        .lookupFunction<_SetCustomLpf1ParamsNative, _SetCustomLpf1ParamsDart>(
      'ae_set_custom_lpf1_params',
    );
    _setCustomHpf1Params = _lib
        .lookupFunction<_SetCustomLpf1ParamsNative, _SetCustomLpf1ParamsDart>(
      'ae_set_custom_hpf1_params',
    );
    _setCustomBiquadParams = _lib.lookupFunction<_SetCustomBiquadParamsNative,
        _SetCustomBiquadParamsDart>(
      'ae_set_custom_biquad_params',
    );

    // Spatialization
    _setSpatializationEnabled = _lib.lookupFunction<
        _SetSpatializationEnabledNative,
        _SetSpatializationEnabledDart>('ae_set_spatialization_enabled');
    _setPosition = _lib.lookupFunction<_SetSpatializationVec3Native,
        _SetSpatializationVec3Dart>('ae_set_position');
    _setDirection = _lib.lookupFunction<_SetSpatializationVec3Native,
        _SetSpatializationVec3Dart>('ae_set_direction');
    _setVelocity = _lib.lookupFunction<_SetSpatializationVec3Native,
        _SetSpatializationVec3Dart>('ae_set_velocity');
    _setAttenuationModel = _lib
        .lookupFunction<_SetIntNative, _SetIntDart>('ae_set_attenuation_model');
    _setRolloff =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_rolloff');
    _setMinGain =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_min_gain');
    _setMaxGain =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_max_gain');
    _setMinDistance =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_min_distance');
    _setMaxDistance =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_max_distance');
    _setDopplerFactor =
        _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
            'ae_set_doppler_factor');

    // Fading & Scheduling
    _setFadeInMilliseconds = _lib.lookupFunction<_SetFadeInMillisecondsNative,
        _SetFadeInMillisecondsDart>('ae_set_fade_in_milliseconds');
    _setStartTimeInPcmFrames =
        _lib.lookupFunction<_SetTimeInPcmFramesNative, _SetTimeInPcmFramesDart>(
            'ae_set_start_time_in_pcm_frames');
    _setStopTimeInPcmFrames =
        _lib.lookupFunction<_SetTimeInPcmFramesNative, _SetTimeInPcmFramesDart>(
            'ae_set_stop_time_in_pcm_frames');
    _getEngineTimeInPcmFrames = _lib.lookupFunction<
        _GetEngineTimeInPcmFramesNative,
        _GetEngineTimeInPcmFramesDart>('ae_get_engine_time_in_pcm_frames');
    _setEndCallback =
        _lib.lookupFunction<_SetEndCallbackNative, _SetEndCallbackDart>(
            'ae_set_end_callback');

    // Advanced Audio Features Bindings
    _setExclusiveMode =
        _lib.lookupFunction<_SetExclusiveModeNative, _SetExclusiveModeDart>(
      'ae_set_exclusive_mode',
    );
    _getExclusiveMode =
        _lib.lookupFunction<_GetExclusiveModeNative, _GetExclusiveModeDart>(
      'ae_get_exclusive_mode',
    );
    _setOutputFormat =
        _lib.lookupFunction<_SetOutputFormatNative, _SetOutputFormatDart>(
      'ae_set_output_format',
    );
    _getOutputFormat =
        _lib.lookupFunction<_GetOutputFormatNative, _GetOutputFormatDart>(
      'ae_get_output_format',
    );
    _setOutputSampleRate =
        _lib.lookupFunction<_SetOutputRateNative, _SetOutputRateDart>(
      'ae_set_output_sample_rate',
    );
    _getOutputSampleRate =
        _lib.lookupFunction<_GetOutputRateNative, _GetOutputRateDart>(
      'ae_get_output_sample_rate',
    );
    _setOutputChannels =
        _lib.lookupFunction<_SetOutputChannelsNative, _SetOutputChannelsDart>(
      'ae_set_output_channels',
    );
    _getOutputChannels =
        _lib.lookupFunction<_GetOutputChannelsNative, _GetOutputChannelsDart>(
      'ae_get_output_channels',
    );

    _setEngineResampleAlgorithm = _lib.lookupFunction<
        _SetEngineResampleAlgorithmNative,
        _SetEngineResampleAlgorithmDart>('ae_set_engine_resample_algorithm');
    _getEngineResampleAlgorithm = _lib.lookupFunction<
        _GetEngineResampleAlgorithmNative,
        _GetEngineResampleAlgorithmDart>('ae_get_engine_resample_algorithm');

    _setEngineDitherMode = _lib.lookupFunction<_SetEngineDitherModeNative,
        _SetEngineDitherModeDart>('ae_set_engine_dither_mode');
    _getEngineDitherMode = _lib.lookupFunction<_GetEngineDitherModeNative,
        _GetEngineDitherModeDart>('ae_get_engine_dither_mode');

    // Limiter & Clipping Detection
    _setLimiterEnabled =
        _lib.lookupFunction<_SetLimiterEnabledNative, _SetLimiterEnabledDart>(
            'ae_set_limiter_enabled');
    _setLimiterParams =
        _lib.lookupFunction<_SetLimiterParamsNative, _SetLimiterParamsDart>(
            'ae_set_limiter_params');
    _setClippingDetectionEnabled = _lib.lookupFunction<
        _SetClippingDetectionEnabledNative,
        _SetClippingDetectionEnabledDart>('ae_set_clipping_detection_enabled');
    _getClippedSamplesCount = _lib.lookupFunction<_GetClippedSamplesCountNative,
        _GetClippedSamplesCountDart>('ae_get_clipped_samples_count');
    _resetClippedSamplesCount = _lib.lookupFunction<
        _ResetClippedSamplesCountNative,
        _ResetClippedSamplesCountDart>('ae_reset_clipped_samples_count');

    _initMultibandEq =
        _lib.lookupFunction<_InitMultibandEqNative, _InitMultibandEqDart>(
      'ae_init_multiband_eq',
    );
    _setMultibandEqEnabled = _lib.lookupFunction<_SetMultibandEqEnabledNative,
        _SetMultibandEqEnabledDart>('ae_set_multiband_eq_enabled');
    _setMultibandEqGain =
        _lib.lookupFunction<_SetMultibandEqGainNative, _SetMultibandEqGainDart>(
      'ae_set_multiband_eq_gain',
    );
    _getMultibandEqGain =
        _lib.lookupFunction<_GetMultibandEqGainNative, _GetMultibandEqGainDart>(
      'ae_get_multiband_eq_gain',
    );
    _setMultibandFxEnabled = _lib.lookupFunction<_SetMultibandFxEnabledNative,
        _SetMultibandFxEnabledDart>('ae_set_multiband_fx_enabled');
    _setMultibandFxBands = _lib
        .lookupFunction<_SetMultibandFxBandsNative, _SetMultibandFxBandsDart>(
      'ae_set_multiband_fx_bands',
    );
    _clearMultibandFx =
        _lib.lookupFunction<_ClearMultibandFxNative, _ClearMultibandFxDart>(
      'ae_clear_multiband_fx',
    );

    _initPushStream =
        _lib.lookupFunction<_InitPushStreamNative, _InitPushStreamDart>(
      'ae_init_push_stream',
    );
    _pushStreamChunk =
        _lib.lookupFunction<_PushStreamChunkNative, _PushStreamChunkDart>(
      'ae_push_stream_chunk',
    );
    _endPushStream =
        _lib.lookupFunction<_EndPushStreamNative, _EndPushStreamDart>(
      'ae_end_push_stream',
    );
    _getPushStreamBufferedBytes = _lib.lookupFunction<
        _GetPushStreamBufferedBytesNative, _GetPushStreamBufferedBytesDart>(
      'ae_get_push_stream_buffered_bytes',
    );

    _setAnalyzerEnabled =
        _lib.lookupFunction<_SetAnalyzerEnabledNative, _SetAnalyzerEnabledDart>(
      'ae_set_analyzer_enabled',
    );
    _configureAnalyzer =
        _lib.lookupFunction<_ConfigureAnalyzerNative, _ConfigureAnalyzerDart>(
      'ae_configure_analyzer',
    );
    _getAnalyzerFrameSize = _lib.lookupFunction<_GetAnalyzerFrameSizeNative,
        _GetAnalyzerFrameSizeDart>('ae_get_analyzer_frame_size');
    _pollAnalyzerFrame =
        _lib.lookupFunction<_PollAnalyzerFrameNative, _PollAnalyzerFrameDart>(
      'ae_poll_analyzer_frame',
    );
    _getAnalyzerDroppedFrames = _lib.lookupFunction<
        _GetAnalyzerDroppedFramesNative,
        _GetAnalyzerDroppedFramesDart>('ae_get_analyzer_dropped_frames');

    try {
      _getNetworkStreamingSupport = _lib.lookupFunction<
          _GetNetworkStreamingSupportNative,
          _GetNetworkStreamingSupportDart>('ae_is_network_streaming_supported');
    } catch (_) {
      _getNetworkStreamingSupport = null;
    }
  }

  final ffi.DynamicLibrary _lib;
  ffi.DynamicLibrary get library => _lib;
  late final _CreateEngineDart _createEngine;
  late final _DestroyEngineDart _destroyEngine;
  late final _SetPlaylistDart _setPlaylist;
  late final _AddToPlaylistDart _addToPlaylist;
  late final _InsertToPlaylistDart _insertToPlaylist;
  late final _RemoveFromPlaylistDart _removeFromPlaylist;
  late final _MovePlaylistItemDart _movePlaylistItem;
  late final _ClearPlaylistDart _clearPlaylist;
  late final _BoolOpDart _play;
  late final _BoolOpDart _pause;
  late final _BoolOpDart _stop;
  late final _BoolOpDart _next;
  late final _BoolOpDart _prev;
  late final _SeekDart _seek;
  late final _JumpDart _jumpTo;
  late final _JumpWithPositionDart _jumpToWithPosition;
  late final _GetDeviceLatencyMsDart _getDeviceLatencyMs;
  late final _GetStatusDart _getStatus;
  late final _GetPipelineStateDart _getPipelineState;
  late final _GetLastErrorDart _getLastError;
  late final _ClearLastErrorDart _clearLastError;
  late final _SetIntDart _setLoopMode;
  late final _SetIntDart _setShuffleEnabled;
  late final _ClearPlaylistDart _reshuffle;
  late final _SetIntDart _setCrossfadeEnabled;
  late final _GetIntDart _getCrossfadeEnabled;
  late final _SetIntDart _setCrossfadeDurationMs;
  late final _GetIntDart _getCrossfadeDurationMs;
  late final _SetFxEnabledDart _setReverbEnabled;
  late final _SetReverbParamsDart _setReverbParams;
  late final _SetFxEnabledDart _setEqEnabled;
  late final _SetEqGainsDart _setEqGains;
  late final _SetSingleFloatDart _setGain;
  _SetSingleFloatDart? _setReplayGain;
  late final _SetSingleFloatDart _setPan;
  late final _SetSingleFloatDart _setPitch;
  late final _SetFxEnabledDart _setLowpassEnabled;
  late final _SetSingleFloatDart _setLowpassCutoff;
  late final _SetFxEnabledDart _setHighpassEnabled;
  late final _SetSingleFloatDart _setHighpassCutoff;
  late final _SetFxEnabledDart _setDelayEnabled;
  late final _SetReverbParamsDart _setDelayParams;
  late final _SetStereoWidenDart _setStereoWiden;
  late final _SetFxEnabledDart _setCrossfeedEnabled;
  late final _SetSingleIntDart _setCrossfeedPreset;
  late final _SetFxEnabledDart _setDynamicBassEnabled;
  late final _SetDynamicBassParamsDart _setDynamicBassParams;

  // Crystalizer
  late final _SetCrystalizerEnabledDart _setCrystalizerEnabled;
  late final _SetCrystalizerParamsDart _setCrystalizerParams;
  late final _GetCrystalizerIntensityDart _getCrystalizerIntensity;
  late final _SetFxEnabledDart _setBandpassEnabled;
  late final _SetTwoFloatsDart _setBandpassParams;
  late final _SetFxEnabledDart _setPeakEqEnabled;
  late final _SetReverbParamsDart _setPeakEqParams;
  late final _SetFxEnabledDart _setNotchEnabled;
  late final _SetTwoFloatsDart _setNotchParams;
  late final _SetFxEnabledDart _setLowshelfEnabled;
  late final _SetReverbParamsDart _setLowshelfParams;
  late final _SetFxEnabledDart _setHighshelfEnabled;
  late final _SetReverbParamsDart _setHighshelfParams;

  // Custom filters
  late final _SetCustomLpf1ParamsDart _setCustomLpf1Params;
  late final _SetCustomLpf1ParamsDart _setCustomHpf1Params;
  late final _SetCustomBiquadParamsDart _setCustomBiquadParams;

  // Spatialization
  late final _SetSpatializationEnabledDart _setSpatializationEnabled;
  late final _SetSpatializationVec3Dart _setPosition;
  late final _SetSpatializationVec3Dart _setDirection;
  late final _SetSpatializationVec3Dart _setVelocity;
  late final _SetIntDart _setAttenuationModel;
  late final _SetSingleFloatDart _setRolloff;
  late final _SetSingleFloatDart _setMinGain;
  late final _SetSingleFloatDart _setMaxGain;
  late final _SetSingleFloatDart _setMinDistance;
  late final _SetSingleFloatDart _setMaxDistance;
  late final _SetSingleFloatDart _setDopplerFactor;

  // Fading & Scheduling
  late final _SetFadeInMillisecondsDart _setFadeInMilliseconds;
  late final _SetTimeInPcmFramesDart _setStartTimeInPcmFrames;
  late final _SetTimeInPcmFramesDart _setStopTimeInPcmFrames;
  late final _GetEngineTimeInPcmFramesDart _getEngineTimeInPcmFrames;
  late final _SetEndCallbackDart _setEndCallback;

  // Advanced Audio Features
  late final _SetExclusiveModeDart _setExclusiveMode;
  late final _GetExclusiveModeDart _getExclusiveMode;
  late final _SetOutputFormatDart _setOutputFormat;
  late final _GetOutputFormatDart _getOutputFormat;
  late final _SetOutputRateDart _setOutputSampleRate;
  late final _GetOutputRateDart _getOutputSampleRate;
  late final _SetOutputChannelsDart _setOutputChannels;
  late final _GetOutputChannelsDart _getOutputChannels;

  late final _SetEngineResampleAlgorithmDart _setEngineResampleAlgorithm;
  late final _GetEngineResampleAlgorithmDart _getEngineResampleAlgorithm;
  late final _SetEngineDitherModeDart _setEngineDitherMode;
  late final _GetEngineDitherModeDart _getEngineDitherMode;

  // Limiter & Clipping Detection
  late final _SetLimiterEnabledDart _setLimiterEnabled;
  late final _SetLimiterParamsDart _setLimiterParams;
  late final _SetClippingDetectionEnabledDart _setClippingDetectionEnabled;
  late final _GetClippedSamplesCountDart _getClippedSamplesCount;
  late final _ResetClippedSamplesCountDart _resetClippedSamplesCount;

  late final _InitMultibandEqDart _initMultibandEq;
  late final _SetMultibandEqEnabledDart _setMultibandEqEnabled;
  late final _SetMultibandEqGainDart _setMultibandEqGain;
  late final _GetMultibandEqGainDart _getMultibandEqGain;
  late final _SetMultibandFxEnabledDart _setMultibandFxEnabled;
  late final _SetMultibandFxBandsDart _setMultibandFxBands;
  late final _ClearMultibandFxDart _clearMultibandFx;

  late final _InitPushStreamDart _initPushStream;
  late final _PushStreamChunkDart _pushStreamChunk;
  late final _EndPushStreamDart _endPushStream;
  late final _GetPushStreamBufferedBytesDart _getPushStreamBufferedBytes;

  late final _SetAnalyzerEnabledDart _setAnalyzerEnabled;
  late final _ConfigureAnalyzerDart _configureAnalyzer;
  late final _GetAnalyzerFrameSizeDart _getAnalyzerFrameSize;
  late final _PollAnalyzerFrameDart _pollAnalyzerFrame;
  late final _GetAnalyzerDroppedFramesDart _getAnalyzerDroppedFrames;

  late final _MallocDart _malloc;
  late final _FreeDart _free;
  _GetNetworkStreamingSupportDart? _getNetworkStreamingSupport;

  ffi.Pointer<ffi.Void> _engine;
  ffi.Pointer<ffi.Void> get enginePointer => _engine;

  ffi.Pointer<ffi.Char> _toNativeChar(String value) {
    final bytes = utf8.encode(value);
    final ptr = _malloc(bytes.length + 1).cast<ffi.Uint8>();
    final list = ptr.asTypedList(bytes.length + 1);
    list.setAll(0, bytes);
    list[bytes.length] = 0;
    return ptr.cast<ffi.Char>();
  }

  void _freePtr(ffi.Pointer<ffi.Void> ptr) {
    if (ptr != ffi.nullptr) {
      _free(ptr);
    }
  }

  String _fromNativeCharPtr(ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return '';
    final bytes = <int>[];
    var offset = 0;
    while (true) {
      final b = ptr.cast<ffi.Uint8>().elementAt(offset).value;
      if (b == 0) break;
      bytes.add(b);
      offset++;
    }
    if (bytes.isEmpty) return '';
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _uriToEnginePath(Uri uri) {
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return uri.toString();
  }

  static ffi.DynamicLibrary openLibrary(String? path) {
    if (path != null && path.isNotEmpty) {
      return ffi.DynamicLibrary.open(path);
    }
    if (Platform.isWindows) {
      try {
        return ffi.DynamicLibrary.open('sautiflow.dll');
      } catch (_) {
        return ffi.DynamicLibrary.open('audio_engine.dll');
      }
    }
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    if (Platform.isMacOS) {
      try {
        return ffi.DynamicLibrary.open('libsautiflow.dylib');
      } catch (_) {
        return ffi.DynamicLibrary.open('libaudio_engine.dylib');
      }
    }
    if (Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libsautiflow.so');
      } catch (_) {
        return ffi.DynamicLibrary.open('libaudio_engine.so');
      }
    }
    try {
      return ffi.DynamicLibrary.open('libsautiflow.so');
    } catch (_) {
      return ffi.DynamicLibrary.open('libaudio_engine.so');
    }
  }

  static ffi.DynamicLibrary openAllocatorLibrary() {
    if (Platform.isWindows) return ffi.DynamicLibrary.open('msvcrt.dll');
    if (Platform.isMacOS || Platform.isIOS) return ffi.DynamicLibrary.process();
    if (Platform.isLinux || Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libc.so.6');
      } catch (_) {
        return ffi.DynamicLibrary.process();
      }
    }
    return ffi.DynamicLibrary.process();
  }

  bool create({int sampleRate = 48000, int channels = 2}) {
    if (_engine != ffi.nullptr) return true;
    _engine = _createEngine(sampleRate, channels);
    return _engine != ffi.nullptr;
  }

  void dispose() {
    if (_engine != ffi.nullptr) {
      _destroyEngine(_engine);
      _engine = ffi.nullptr;
    }
  }

  bool isNetworkStreamingSupported() {
    final getter = _getNetworkStreamingSupport;
    if (getter == null) return false;
    return getter() != 0;
  }

  bool setPlaylist(List<String> paths) {
    if (_engine == ffi.nullptr || paths.isEmpty) return false;

    final ptrArray = _malloc(
      ffi.sizeOf<ffi.Pointer<ffi.Char>>() * paths.length,
    ).cast<ffi.Pointer<ffi.Char>>();
    final allocated = <ffi.Pointer<ffi.Char>>[];

    try {
      for (var i = 0; i < paths.length; i++) {
        final c = _toNativeChar(paths[i]);
        allocated.add(c);
        ptrArray[i] = c;
      }
      return _setPlaylist(_engine, ptrArray, paths.length) != 0;
    } finally {
      for (final p in allocated) {
        _freePtr(p.cast<ffi.Void>());
      }
      _freePtr(ptrArray.cast<ffi.Void>());
    }
  }

  bool addToPlaylist(String path) {
    if (_engine == ffi.nullptr) return false;
    final c = _toNativeChar(path);
    try {
      return _addToPlaylist(_engine, c) != 0;
    } finally {
      _freePtr(c.cast<ffi.Void>());
    }
  }

  bool insertAudioSource(int index, String path) {
    if (_engine == ffi.nullptr) return false;
    final c = _toNativeChar(path);
    try {
      return _insertToPlaylist(_engine, index, c) != 0;
    } finally {
      _freePtr(c.cast<ffi.Void>());
    }
  }

  bool removeAudioSourceAt(int index) {
    if (_engine == ffi.nullptr) return false;
    return _removeFromPlaylist(_engine, index) != 0;
  }

  bool moveAudioSource(int fromIndex, int toIndex) {
    if (_engine == ffi.nullptr) return false;
    return _movePlaylistItem(_engine, fromIndex, toIndex) != 0;
  }

  void clearPlaylist() {
    if (_engine == ffi.nullptr) return;
    _clearPlaylist(_engine);
  }

  bool play() => _engine != ffi.nullptr && _play(_engine) != 0;
  bool pause() => _engine != ffi.nullptr && _pause(_engine) != 0;
  bool stop() => _engine != ffi.nullptr && _stop(_engine) != 0;
  bool next() => _engine != ffi.nullptr && _next(_engine) != 0;
  bool prev() => _engine != ffi.nullptr && _prev(_engine) != 0;
  bool jumpTo(int index) =>
      _engine != ffi.nullptr && _jumpTo(_engine, index) != 0;

  bool jumpToWithPosition(int index, Duration position) =>
      _engine != ffi.nullptr &&
      _jumpToWithPosition(
            _engine,
            index,
            position.inMicroseconds / 1000000.0,
          ) !=
          0;

  bool seekToNext() => next();
  bool seekToPrevious() => prev();

  void setLoopMode(LoopMode mode) {
    if (_engine == ffi.nullptr) return;
    _setLoopMode(_engine, mode.index);
  }

  void setShuffleModeEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setShuffleEnabled(_engine, enabled ? 1 : 0);
  }

  void reshuffle() {
    if (_engine == ffi.nullptr) return;
    _reshuffle(_engine);
  }

  void setCrossfadeEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setCrossfadeEnabled(_engine, enabled ? 1 : 0);
  }

  bool getCrossfadeEnabled() {
    if (_engine == ffi.nullptr) return false;
    return _getCrossfadeEnabled(_engine) != 0;
  }

  void setCrossfadeDurationMs(int durationMs) {
    if (_engine == ffi.nullptr) return;
    _setCrossfadeDurationMs(_engine, durationMs);
  }

  int getCrossfadeDurationMs() {
    if (_engine == ffi.nullptr) return 0;
    return _getCrossfadeDurationMs(_engine);
  }

  // Alias matching requested naming style.
  bool addAudioSource(String path) => addToPlaylist(path);
  bool addAudioSourceUri(Uri uri) => addToPlaylist(_uriToEnginePath(uri));

  bool setAudioSources(
    List<AudioSource> sources, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool useLazyPreparation = true,
    Object? shuffleOrder,
  }) {
    final paths = sources.map((s) => _uriToEnginePath(s.uri)).toList();
    final ok = setPlaylist(paths);
    if (!ok) return false;

    if (sources.isEmpty) return false;
    final idx = initialIndex.clamp(0, sources.length - 1);
    final jumped = jumpToWithPosition(idx, initialPosition);

    if (!useLazyPreparation) {
      // Force preload behavior by briefly touching next/prev ordering.
      reshuffle();
    }

    if (shuffleOrder != null) {
      // Placeholder to keep API compatibility with caller; shuffle policy remains engine-defined.
    }

    return jumped;
  }

  bool seekTo(Duration position, {int? index}) {
    if (index != null) {
      return jumpToWithPosition(index, position);
    }

    final s = getStatus();
    if (s.durationSeconds <= 0) return false;
    final percent = (position.inMicroseconds / 1000000.0) / s.durationSeconds;
    return seek(percent);
  }

  bool seek(double percent0to1) =>
      _engine != ffi.nullptr && _seek(_engine, percent0to1) != 0;

  PlayerStatus getStatus() {
    if (_engine == ffi.nullptr) {
      return const PlayerStatus(
        positionSeconds: 0,
        durationSeconds: 0,
        isPlaying: false,
        currentIndex: -1,
        playlistCount: 0,
        shuffleEnabled: false,
        loopMode: LoopMode.off,
      );
    }

    final s = _getStatus(_engine);
    return PlayerStatus(
      positionSeconds: s.position_seconds,
      durationSeconds: s.duration_seconds,
      isPlaying: s.is_playing != 0,
      currentIndex: s.current_index,
      playlistCount: s.playlist_count,
      shuffleEnabled: s.shuffle_enabled != 0,
      loopMode: LoopMode.values[s.loop_mode.clamp(0, 2)],
    );
  }

  double getDeviceLatencyMs() {
    if (_engine == ffi.nullptr) return 0.0;
    return _getDeviceLatencyMs(_engine);
  }

  PipelineAudioState getPipelineState() {
    if (_engine == ffi.nullptr) return PipelineAudioState.empty();
    return PipelineAudioState.fromNative(_getPipelineState(_engine));
  }

  String getLastError() {
    if (_engine == ffi.nullptr) return 'Engine is not initialized';
    return _fromNativeCharPtr(_getLastError(_engine));
  }

  void clearLastError() {
    if (_engine == ffi.nullptr) return;
    _clearLastError(_engine);
  }

  void setReverbEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setReverbEnabled(_engine, enabled ? 1 : 0);
  }

  void setReverbParams({
    required double mix,
    required double feedback,
    required double delayMs,
  }) {
    if (_engine == ffi.nullptr) return;
    _setReverbParams(_engine, mix, feedback, delayMs);
  }

  void setEqEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setEqEnabled(_engine, enabled ? 1 : 0);
  }

  void setEqGains({
    required double low,
    required double mid,
    required double high,
  }) {
    if (_engine == ffi.nullptr) return;
    _setEqGains(_engine, low, mid, high);
  }

  void setGain(double gain) {
    if (_engine == ffi.nullptr) return;
    _setGain(_engine, gain);
  }

  void setReplayGain(double gainDb) {
    if (_engine == ffi.nullptr) return;
    _setReplayGain?.call(_engine, gainDb);
  }

  void setPan(double panMinus1ToPlus1) {
    if (_engine == ffi.nullptr) return;
    _setPan(_engine, panMinus1ToPlus1);
  }

  void setPitch(double pitchMultiplier) {
    if (_engine == ffi.nullptr) return;
    _setPitch(_engine, pitchMultiplier);
  }

  void setLowpassEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setLowpassEnabled(_engine, enabled ? 1 : 0);
  }

  void setLowpassCutoff(double hz) {
    if (_engine == ffi.nullptr) return;
    _setLowpassCutoff(_engine, hz);
  }

  void setHighpassEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setHighpassEnabled(_engine, enabled ? 1 : 0);
  }

  void setHighpassCutoff(double hz) {
    if (_engine == ffi.nullptr) return;
    _setHighpassCutoff(_engine, hz);
  }

  void setDelayEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setDelayEnabled(_engine, enabled ? 1 : 0);
  }

  void setDelayParams({
    required double mix,
    required double feedback,
    required double delayMs,
  }) {
    if (_engine == ffi.nullptr) return;
    _setDelayParams(_engine, mix, feedback, delayMs);
  }

  void setStereoWiden({
    required bool enabled,
    required double width,
    required double delayMs,
  }) {
    if (_engine == ffi.nullptr) return;
    _setStereoWiden(_engine, enabled ? 1 : 0, width, delayMs);
  }

  void setCrossfeedEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setCrossfeedEnabled(_engine, enabled ? 1 : 0);
  }

  void setCrossfeedPreset(int preset) {
    if (_engine == ffi.nullptr) return;
    _setCrossfeedPreset(_engine, preset);
  }

  void setDynamicBassEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setDynamicBassEnabled(_engine, enabled ? 1 : 0);
  }

  void setDynamicBassParams({
    required int preset,
    required double gain,
  }) {
    if (_engine == ffi.nullptr) return;
    _setDynamicBassParams(_engine, preset, gain);
  }

  void setBandpassEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setBandpassEnabled(_engine, enabled ? 1 : 0);
  }

  void setBandpassParams({
    required double cutoffHz,
    required double q,
  }) {
    if (_engine == ffi.nullptr) return;
    _setBandpassParams(_engine, cutoffHz, q);
  }

  void setPeakEqEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setPeakEqEnabled(_engine, enabled ? 1 : 0);
  }

  void setPeakEqParams({
    required double gainDb,
    required double q,
    required double frequencyHz,
  }) {
    if (_engine == ffi.nullptr) return;
    _setPeakEqParams(_engine, gainDb, q, frequencyHz);
  }

  void setNotchEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setNotchEnabled(_engine, enabled ? 1 : 0);
  }

  void setNotchParams({
    required double q,
    required double frequencyHz,
  }) {
    if (_engine == ffi.nullptr) return;
    _setNotchParams(_engine, q, frequencyHz);
  }

  void setLowshelfEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setLowshelfEnabled(_engine, enabled ? 1 : 0);
  }

  void setLowshelfParams({
    required double gainDb,
    required double slope,
    required double frequencyHz,
  }) {
    if (_engine == ffi.nullptr) return;
    _setLowshelfParams(_engine, gainDb, slope, frequencyHz);
  }

  void setHighshelfEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setHighshelfEnabled(_engine, enabled ? 1 : 0);
  }

  void setHighshelfParams({
    required double gainDb,
    required double slope,
    required double frequencyHz,
  }) {
    if (_engine == ffi.nullptr) return;
    _setHighshelfParams(_engine, gainDb, slope, frequencyHz);
  }

  // Custom Filters

  void setCustomLpf1Params({required bool enabled, required double cutoffHz}) {
    if (_engine == ffi.nullptr) return;
    _setCustomLpf1Params(_engine, enabled ? 1 : 0, cutoffHz);
  }

  void setCustomHpf1Params({required bool enabled, required double cutoffHz}) {
    if (_engine == ffi.nullptr) return;
    _setCustomHpf1Params(_engine, enabled ? 1 : 0, cutoffHz);
  }

  void setCustomBiquadParams({
    required bool enabled,
    required double b0,
    required double b1,
    required double b2,
    required double a0,
    required double a1,
    required double a2,
  }) {
    if (_engine == ffi.nullptr) return;
    _setCustomBiquadParams(_engine, enabled ? 1 : 0, b0, b1, b2, a0, a1, a2);
  }

  // Spatialization

  void setSpatializationEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setSpatializationEnabled(_engine, enabled ? 1 : 0);
  }

  void setPosition({required double x, required double y, required double z}) {
    if (_engine == ffi.nullptr) return;
    _setPosition(_engine, x, y, z);
  }

  void setDirection({required double x, required double y, required double z}) {
    if (_engine == ffi.nullptr) return;
    _setDirection(_engine, x, y, z);
  }

  void setVelocity({required double x, required double y, required double z}) {
    if (_engine == ffi.nullptr) return;
    _setVelocity(_engine, x, y, z);
  }

  /// 0 = None, 1 = Inverse, 2 = Linear, 3 = Exponential
  void setAttenuationModel(int model) {
    if (_engine == ffi.nullptr) return;
    _setAttenuationModel(_engine, model);
  }

  void setRolloff(double rolloff) {
    if (_engine == ffi.nullptr) return;
    _setRolloff(_engine, rolloff);
  }

  void setMinGain(double minGain) {
    if (_engine == ffi.nullptr) return;
    _setMinGain(_engine, minGain);
  }

  void setMaxGain(double maxGain) {
    if (_engine == ffi.nullptr) return;
    _setMaxGain(_engine, maxGain);
  }

  void setMinDistance(double minDistance) {
    if (_engine == ffi.nullptr) return;
    _setMinDistance(_engine, minDistance);
  }

  void setMaxDistance(double maxDistance) {
    if (_engine == ffi.nullptr) return;
    _setMaxDistance(_engine, maxDistance);
  }

  void setDopplerFactor(double dopplerFactor) {
    if (_engine == ffi.nullptr) return;
    _setDopplerFactor(_engine, dopplerFactor);
  }

  // Fading & Scheduling

  void setFade(double startVol, double endVol, int durationMs) {
    if (_engine == ffi.nullptr) return;
    _setFadeInMilliseconds(_engine, startVol, endVol, durationMs);
  }

  void scheduleStartTimeInPcmFrames(int absoluteTime) {
    if (_engine == ffi.nullptr) return;
    _setStartTimeInPcmFrames(_engine, absoluteTime);
  }

  void scheduleStopTimeInPcmFrames(int absoluteTime) {
    if (_engine == ffi.nullptr) return;
    _setStopTimeInPcmFrames(_engine, absoluteTime);
  }

  int getEngineTimeInPcmFrames() {
    if (_engine == ffi.nullptr) return 0;
    return _getEngineTimeInPcmFrames(_engine);
  }

  void setEndCallback(
      ffi.Pointer<ffi.NativeFunction<_EndCallbackNative>> callback,
      ffi.Pointer<ffi.Void> userData) {
    if (_engine == ffi.nullptr) return;
    _setEndCallback(_engine, callback, userData);
  }

  // Advanced Audio Features Helpers

  void setExclusiveMode(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setExclusiveMode(_engine, enabled ? 1 : 0);
  }

  bool getExclusiveMode() {
    if (_engine == ffi.nullptr) return false;
    return _getExclusiveMode(_engine) != 0;
  }

  void setOutputFormat(AudioFormat format) {
    if (_engine == ffi.nullptr) return;
    _setOutputFormat(_engine, format.index);
  }

  AudioFormat getOutputFormat() {
    if (_engine == ffi.nullptr) return AudioFormat.f32;
    final index = _getOutputFormat(_engine);
    return AudioFormat.values[index.clamp(0, AudioFormat.values.length - 1)];
  }

  void setOutputSampleRate(int rate) {
    if (_engine == ffi.nullptr) return;
    _setOutputSampleRate(_engine, rate);
  }

  int getOutputSampleRate() {
    if (_engine == ffi.nullptr) return 0;
    return _getOutputSampleRate(_engine);
  }

  void setOutputChannels(int channels) {
    if (_engine == ffi.nullptr) return;
    _setOutputChannels(_engine, channels);
  }

  int getOutputChannels() {
    if (_engine == ffi.nullptr) return 0;
    return _getOutputChannels(_engine);
  }

  void setEngineResampleAlgorithm(int algorithm) {
    if (_engine == ffi.nullptr) return;
    _setEngineResampleAlgorithm(_engine, algorithm);
  }

  int getEngineResampleAlgorithm() {
    if (_engine == ffi.nullptr) return 0;
    return _getEngineResampleAlgorithm(_engine);
  }

  void setEngineDitherMode(int ditherMode) {
    if (_engine == ffi.nullptr) return;
    _setEngineDitherMode(_engine, ditherMode);
  }

  int getEngineDitherMode() {
    if (_engine == ffi.nullptr) return 0;
    return _getEngineDitherMode(_engine);
  }

  // ── Limiter & Clipping Detection ──────────────────────────────────────────

  /// Enable or disable the soft limiter in the audio chain.
  void setLimiterEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setLimiterEnabled(_engine, enabled ? 1 : 0);
  }

  /// Configure the limiter parameters.
  ///
  /// [threshold] – linear amplitude threshold (0.1 – 1.0, default 0.95).
  /// [attackMs]  – attack time in milliseconds (0.1 – 100 ms, default 2 ms).
  /// [releaseMs] – release time in milliseconds (10 – 1000 ms, default 50 ms).
  void setLimiterParams({
    double threshold = 0.95,
    double attackMs = 2.0,
    double releaseMs = 50.0,
  }) {
    if (_engine == ffi.nullptr) return;
    _setLimiterParams(_engine, threshold, attackMs, releaseMs);
  }

  /// Enable or disable clipping detection.
  /// When enabled, samples exceeding ±1.0 are counted by the engine.
  void setClippingDetectionEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setClippingDetectionEnabled(_engine, enabled ? 1 : 0);
  }

  /// Returns the total number of clipped samples since the last reset.
  int getClippedSamplesCount() {
    if (_engine == ffi.nullptr) return 0;
    return _getClippedSamplesCount(_engine);
  }

  /// Resets the clipped-sample counter back to zero.
  void resetClippedSamplesCount() {
    if (_engine == ffi.nullptr) return;
    _resetClippedSamplesCount(_engine);
  }

  void initMultibandEq(
    int bands,
    List<double> frequencies, {
    List<double>? qFactors,
  }) {
    if (_engine == ffi.nullptr) return;
    if (frequencies.length != bands) return;
    if (qFactors != null && qFactors.length != bands) return;

    final freqPtr = _malloc(bands * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final freqList = freqPtr.asTypedList(bands);
    freqList.setAll(0, frequencies);

    ffi.Pointer<ffi.Float> qPtr = ffi.nullptr;
    if (qFactors != null) {
      qPtr = _malloc(bands * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
      final qList = qPtr.asTypedList(bands);
      qList.setAll(0, qFactors);
    }

    try {
      _initMultibandEq(_engine, bands, freqPtr, qPtr);
    } finally {
      _freePtr(freqPtr.cast<ffi.Void>());
      if (qPtr != ffi.nullptr) {
        _freePtr(qPtr.cast<ffi.Void>());
      }
    }
  }

  void setMultibandEqEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setMultibandEqEnabled(_engine, enabled ? 1 : 0);
  }

  void setMultibandEqGain(int bandIndex, double gain) {
    if (_engine == ffi.nullptr) return;
    _setMultibandEqGain(_engine, bandIndex, gain);
  }

  double getMultibandEqGain(int bandIndex) {
    if (_engine == ffi.nullptr) return 0.0;
    return _getMultibandEqGain(_engine, bandIndex);
  }

  void setMultibandFxEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setMultibandFxEnabled(_engine, enabled ? 1 : 0);
  }

  void clearMultibandFx() {
    if (_engine == ffi.nullptr) return;
    _clearMultibandFx(_engine);
  }

  void setMultibandFxBands(List<EqBandConfig> bands) {
    if (_engine == ffi.nullptr) return;
    if (bands.isEmpty) {
      clearMultibandFx();
      return;
    }

    final count = bands.length;
    final typesPtr = _malloc(count * ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();
    final frequencyPtr =
        _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final qPtr = _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final gainPtr = _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final slopePtr = _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    final enabledPtr =
        _malloc(count * ffi.sizeOf<ffi.Int32>()).cast<ffi.Int32>();

    try {
      final types = typesPtr.asTypedList(count);
      final freqs = frequencyPtr.asTypedList(count);
      final qs = qPtr.asTypedList(count);
      final gains = gainPtr.asTypedList(count);
      final slopes = slopePtr.asTypedList(count);
      final enabledFlags = enabledPtr.asTypedList(count);

      for (var i = 0; i < count; i++) {
        final band = bands[i];
        types[i] = band.type.index;
        freqs[i] = band.frequencyHz;
        qs[i] = band.q;
        gains[i] = band.gainDb;
        slopes[i] = band.slope;
        enabledFlags[i] = band.enabled ? 1 : 0;
      }

      _setMultibandFxBands(
        _engine,
        count,
        typesPtr,
        frequencyPtr,
        qPtr,
        gainPtr,
        slopePtr,
        enabledPtr,
      );
    } finally {
      _freePtr(typesPtr.cast<ffi.Void>());
      _freePtr(frequencyPtr.cast<ffi.Void>());
      _freePtr(qPtr.cast<ffi.Void>());
      _freePtr(gainPtr.cast<ffi.Void>());
      _freePtr(slopePtr.cast<ffi.Void>());
      _freePtr(enabledPtr.cast<ffi.Void>());
    }
  }

  // Push Stream API
  void initPushStream() {
    if (_engine == ffi.nullptr) return;
    _initPushStream(_engine);
  }

  void pushStreamChunk(ffi.Pointer<ffi.Uint8> data, int size) {
    if (_engine == ffi.nullptr) return;
    _pushStreamChunk(_engine, data, size);
  }

  void endPushStream() {
    if (_engine == ffi.nullptr) return;
    _endPushStream(_engine);
  }

  int getPushStreamBufferedBytes() {
    if (_engine == ffi.nullptr) return 0;
    return _getPushStreamBufferedBytes(_engine);
  }

  void setAnalyzerEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setAnalyzerEnabled(_engine, enabled ? 1 : 0);
  }

  void configureAnalyzer(int frameSize) {
    if (_engine == ffi.nullptr) return;
    _configureAnalyzer(_engine, frameSize);
  }

  int getAnalyzerFrameSize() {
    if (_engine == ffi.nullptr) return 0;
    return _getAnalyzerFrameSize(_engine);
  }

  int getAnalyzerDroppedFrames() {
    if (_engine == ffi.nullptr) return 0;
    return _getAnalyzerDroppedFrames(_engine);
  }

  Float32List pollAnalyzerFrame({int? maxSamples}) {
    if (_engine == ffi.nullptr) {
      return Float32List(0);
    }

    final size = maxSamples ?? getAnalyzerFrameSize();
    if (size <= 0) {
      return Float32List(0);
    }

    final ptr = _malloc(size * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();
    try {
      final copied = _pollAnalyzerFrame(_engine, ptr, size);
      if (copied <= 0) {
        return Float32List(0);
      }
      final src = ptr.asTypedList(copied);
      return Float32List.fromList(src);
    } finally {
      _freePtr(ptr.cast<ffi.Void>());
    }
  }

  // ---------------------------------------------------------------------------
  // Crystalizer
  // ---------------------------------------------------------------------------

  /// Enable or disable the Crystalizer effect.
  ///
  /// The Crystalizer reconstructs transient detail lost in lossy compression
  /// (MP3/AAC) and optionally adds a gentle high-shelf "air" boost.
  void setCrystalizerEnabled(bool enabled) {
    if (_engine == ffi.nullptr) return;
    _setCrystalizerEnabled(_engine, enabled ? 1 : 0);
  }

  /// Configure the Crystalizer parameters.
  ///
  /// [intensity]          – transient reconstruction strength [0.0 – 1.0] (default 0.5).
  ///                        Higher values add more transient detail and "crispness".
  /// [highShelfEnabled]   – if `true`, a gentle 2nd-order high-shelf is applied
  ///                        above 8 kHz to restore "air" lost in compression.
  /// [highShelfGainDb]    – shelf boost in dB [0.0 – 6.0] (default 2.0).
  void setCrystalizerParams({
    double intensity = 0.5,
    bool highShelfEnabled = true,
    double highShelfGainDb = 2.0,
  }) {
    if (_engine == ffi.nullptr) return;
    _setCrystalizerParams(
      _engine,
      intensity,
      highShelfEnabled ? 1 : 0,
      highShelfGainDb,
    );
  }

  /// Returns the current Crystalizer intensity in [0.0 – 1.0].
  double getCrystalizerIntensity() {
    if (_engine == ffi.nullptr) return 0.0;
    return _getCrystalizerIntensity(_engine);
  }
}
