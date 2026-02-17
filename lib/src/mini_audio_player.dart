import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import '../audio_engine_ffi.dart';
import 'mobile_system_audio.dart';

class MiniAudioPlayer {
  MiniAudioPlayer({
    String? libraryPath,
    this.statusPollInterval = const Duration(milliseconds: 200),
  }) : _engine = AudioEngineFFI(libraryPath: libraryPath);

  final AudioEngineFFI _engine;
  final Duration statusPollInterval;

  final _statusController = StreamController<PlayerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  late final MiniAudioSystemAudioController _systemAudio =
      MiniAudioSystemAudioController(
    statusStream: _statusController.stream,
    onPlay: () {
      play();
    },
    onPause: () {
      pause();
    },
    onStop: () {
      stop();
    },
    onNext: () {
      seekToNext();
    },
    onPrevious: () {
      seekToPrevious();
    },
    onSeek: (position) {
      seekTo(position);
    },
    onSetGain: (gain) {
      setGain(gain);
    },
  );
  Timer? _statusTimer;
  String _lastLog = '';

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;

  bool init({
    int sampleRate = 48000,
    int channels = 2,
    bool enableSystemAudio = false,
    MiniAudioSystemAudioConfig? systemAudioConfig,
  }) {
    final ok = _engine.create(sampleRate: sampleRate, channels: channels);
    if (ok) {
      _startStatusPolling();
      if (enableSystemAudio) {
        unawaited(
          _systemAudio.enable(
            config: systemAudioConfig ?? const MiniAudioSystemAudioConfig(),
          ),
        );
      }
    }
    return ok;
  }

  void dispose() {
    unawaited(_systemAudio.disable());
    _statusTimer?.cancel();
    _statusController.close();
    _logController.close();
    _engine.dispose();
  }

  bool setAudioSources(
    List<AudioSource> sources, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool useLazyPreparation = true,
    Object? shuffleOrder,
  }) {
    final supportsNetwork = isNetworkStreamingSupported();
    for (final source in sources) {
      if (source.isNetwork && !supportsNetwork) {
        throw ArgumentError(
            'Network URLs are not supported in this native build (found: ${source.uri}). Rebuild with network streaming enabled, or use local files/pushStream().');
      }
    }
    return _engine.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      useLazyPreparation: useLazyPreparation,
      shuffleOrder: shuffleOrder,
    );
  }

  bool addAudioSource(AudioSource source) {
    if (source.isNetwork && !isNetworkStreamingSupported()) {
      throw ArgumentError(
          'Network URLs are not supported in this native build (found: ${source.uri}). Rebuild with network streaming enabled, or use local files/pushStream().');
    }
    return _engine.addAudioSourceUri(source.uri);
  }

  bool insertAudioSource(int index, AudioSource source) =>
      _engine.insertAudioSource(
        index,
        source.uri.scheme == 'file'
            ? source.uri.toFilePath()
            : source.uri.toString(),
      );
  bool removeAudioSourceAt(int index) => _engine.removeAudioSourceAt(index);
  void clearAudioSources() => _engine.clearPlaylist();
  bool moveAudioSource(int fromIndex, int toIndex) =>
      _engine.moveAudioSource(fromIndex, toIndex);

  bool play() => _engine.play();
  bool pause() => _engine.pause();
  bool stop() => _engine.stop();

  bool seek(Duration position, {int? index}) =>
      _engine.seekTo(position, index: index);
  bool seekTo(Duration position, {int? index}) =>
      _engine.seekTo(position, index: index);
  bool seekToNext() => _engine.seekToNext();
  bool seekToPrevious() => _engine.seekToPrevious();

  void setLoopMode(LoopMode mode) => _engine.setLoopMode(mode);
  void setShuffleModeEnabled(bool enabled) =>
      _engine.setShuffleModeEnabled(enabled);
  void reshuffle() => _engine.reshuffle();

  PlayerStatus get status => _engine.getStatus();
  String getLastError() => _engine.getLastError();
  void clearLastError() => _engine.clearLastError();
  bool isNetworkStreamingSupported() => _engine.isNetworkStreamingSupported();
  int getPushStreamBufferedBytes() => _engine.getPushStreamBufferedBytes();
  bool get supportsSystemMediaControls => _systemAudio.isSupported;
  bool get systemMediaControlsEnabled => _systemAudio.isEnabled;

  Future<bool> enableSystemMediaControls({
    MiniAudioSystemAudioConfig config = const MiniAudioSystemAudioConfig(),
  }) =>
      _systemAudio.enable(config: config);

  Future<void> disableSystemMediaControls() => _systemAudio.disable();

  Future<void> updateNowPlaying({
    required String title,
    String? artist,
    String? album,
    String? id,
    Duration? duration,
  }) =>
      _systemAudio.updateNowPlaying(
        title: title,
        artist: artist,
        album: album,
        id: id,
        duration: duration,
      );

  void setReverbEnabled(bool enabled) => _engine.setReverbEnabled(enabled);

  void setReverbParams({
    double mix = 0.5,
    double feedback = 0.5,
    double delayMs = 50.0,
  }) {
    _engine.setReverbParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  void setOldEqEnabled(bool enabled) => _engine.setEqEnabled(enabled);

  void setOldEqGains({
    double lowGain = 1.0,
    double midGain = 1.0,
    double highGain = 1.0,
  }) {
    _engine.setEqGains(low: lowGain, mid: midGain, high: highGain);
  }

  // --- Advanced Audio Controls ---

  /// Set the desired output audio format (f32, s16, u8).
  /// This may cause the audio engine to restart.
  void setOutputFormat(AudioFormat format) => _engine.setOutputFormat(format);

  /// Get the current output audio format.
  AudioFormat getOutputFormat() => _engine.getOutputFormat();

  /// Set the desired output sample rate (e.g., 44100, 48000).
  /// Set to 0 to use the device's native sample rate.
  /// This may cause the audio engine to restart.
  void setOutputSampleRate(int rate) => _engine.setOutputSampleRate(rate);

  /// Get the current output sample rate (0 usually means native/auto).
  int getOutputSampleRate() => _engine.getOutputSampleRate();

  /// Set the number of output channels (e.g., 1 for mono, 2 for stereo).
  /// This may cause the audio engine to restart.
  void setOutputChannels(int channels) => _engine.setOutputChannels(channels);

  /// Get the current output channel count.
  int getOutputChannels() => _engine.getOutputChannels();

  /// Initialize the multiband equalizer.
  /// provide a list of center frequencies (Hz) for the bands.
  /// Optional [qFactors] lists the Q factor for each band (defaults to 1.0).
  /// Example 10-band ISO: [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
  void initMultibandEq(List<double> frequencies, {List<double>? qFactors}) =>
      _engine.initMultibandEq(frequencies.length, frequencies,
          qFactors: qFactors);

  /// Enable or disable the multiband equalizer.
  void setMultibandEqEnabled(bool enabled) =>
      _engine.setMultibandEqEnabled(enabled);

  /// Set the gain (in dB) for a specific EQ band.
  void setMultibandEqBandGain(int bandIndex, double gainDb) =>
      _engine.setMultibandEqGain(bandIndex, gainDb);

  /// Get the current gain (in dB) for a specific EQ band.
  double getMultibandEqBandGain(int bandIndex) =>
      _engine.getMultibandEqGain(bandIndex);
  void setReverb(
      {required double mix,
      required double feedback,
      required double delayMs}) {
    _engine.setReverbParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  void setEqEnabled(bool enabled) => _engine.setEqEnabled(enabled);
  void setEq({required double low, required double mid, required double high}) {
    _engine.setEqGains(low: low, mid: mid, high: high);
  }

  void setGain(double gain) => _engine.setGain(gain);
  void setVolume(double volume) => setGain(volume);
  void setPan(double pan) => _engine.setPan(pan);

  void setLowpass({required bool enabled, required double cutoffHz}) {
    _engine.setLowpassEnabled(enabled);
    _engine.setLowpassCutoff(cutoffHz);
  }

  void setHighpass({required bool enabled, required double cutoffHz}) {
    _engine.setHighpassEnabled(enabled);
    _engine.setHighpassCutoff(cutoffHz);
  }

  void setDelay(
      {required bool enabled,
      required double mix,
      required double feedback,
      required double delayMs}) {
    _engine.setDelayEnabled(enabled);
    _engine.setDelayParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  Future<void> pushStream({required String url}) async {
    _engine.initPushStream();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      int bytesReceived = 0;
      bool playbackStarted = false;
      // 64KB buffer threshold before starting playback
      const bufferThreshold = 64 * 1024;

      await for (final chunk in response.stream) {
        final size = chunk.length;
        final ptr = calloc<ffi.Uint8>(size);
        final list = ptr.asTypedList(size);
        list.setAll(0, chunk);

        _engine.pushStreamChunk(ptr, size);
        calloc.free(ptr);

        bytesReceived += size;
        if (!playbackStarted && bytesReceived >= bufferThreshold) {
          play();
          playbackStarted = true;
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
      _engine.endPushStream();
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(statusPollInterval, (_) {
      if (_statusController.isClosed) return;
      _statusController.add(_engine.getStatus());

      if (!_logController.isClosed) {
        final msg = _engine.getLastError();
        if (msg.isNotEmpty && msg != _lastLog) {
          _lastLog = msg;
          _logController.add(msg);
        }
      }
    });
  }
}
