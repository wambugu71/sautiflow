import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

enum LoopMode { off, all, one }

class AudioSource {
  final Uri uri;
  const AudioSource.uri(this.uri);
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

typedef _GetStatusNative = PlayerStatusNative Function(ffi.Pointer<ffi.Void>);
typedef _GetStatusDart = PlayerStatusNative Function(ffi.Pointer<ffi.Void>);

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

typedef _SetSingleFloatNative = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Float);
typedef _SetSingleFloatDart = void Function(ffi.Pointer<ffi.Void>, double);

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

class AudioEngineFFI {
  AudioEngineFFI({String? libraryPath})
      : _lib = _openLibrary(libraryPath),
        _engine = ffi.nullptr {
    final allocLib = _openAllocatorLibrary();
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
    _getStatus = _lib.lookupFunction<_GetStatusNative, _GetStatusDart>(
      'ae_get_status',
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
    _setPan = _lib.lookupFunction<_SetSingleFloatNative, _SetSingleFloatDart>(
      'ae_set_pan',
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
  }

  final ffi.DynamicLibrary _lib;
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
  late final _GetStatusDart _getStatus;
  late final _GetLastErrorDart _getLastError;
  late final _ClearLastErrorDart _clearLastError;
  late final _SetIntDart _setLoopMode;
  late final _SetIntDart _setShuffleEnabled;
  late final _ClearPlaylistDart _reshuffle;
  late final _SetFxEnabledDart _setReverbEnabled;
  late final _SetReverbParamsDart _setReverbParams;
  late final _SetFxEnabledDart _setEqEnabled;
  late final _SetEqGainsDart _setEqGains;
  late final _SetSingleFloatDart _setGain;
  late final _SetSingleFloatDart _setPan;
  late final _SetFxEnabledDart _setLowpassEnabled;
  late final _SetSingleFloatDart _setLowpassCutoff;
  late final _SetFxEnabledDart _setHighpassEnabled;
  late final _SetSingleFloatDart _setHighpassCutoff;
  late final _SetFxEnabledDart _setDelayEnabled;
  late final _SetReverbParamsDart _setDelayParams;
  late final _MallocDart _malloc;
  late final _FreeDart _free;

  ffi.Pointer<ffi.Void> _engine;

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

  static ffi.DynamicLibrary _openLibrary(String? path) {
    if (path != null && path.isNotEmpty) {
      return ffi.DynamicLibrary.open(path);
    }
    if (Platform.isWindows) return ffi.DynamicLibrary.open('audio_engine.dll');
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    if (Platform.isMacOS)
      return ffi.DynamicLibrary.open('libaudio_engine.dylib');
    if (Platform.isAndroid)
      return ffi.DynamicLibrary.open('libaudio_engine.so');
    return ffi.DynamicLibrary.open('libaudio_engine.so');
  }

  static ffi.DynamicLibrary _openAllocatorLibrary() {
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

  void setPan(double panMinus1ToPlus1) {
    if (_engine == ffi.nullptr) return;
    _setPan(_engine, panMinus1ToPlus1);
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
}
