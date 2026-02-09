import 'dart:async';

import '../audio_engine_ffi.dart';

class MiniAudioPlayer {
  MiniAudioPlayer({
    String? libraryPath,
    this.statusPollInterval = const Duration(milliseconds: 200),
  }) : _engine = AudioEngineFFI(libraryPath: libraryPath);

  final AudioEngineFFI _engine;
  final Duration statusPollInterval;

  final _statusController = StreamController<PlayerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  Timer? _statusTimer;
  String _lastLog = '';

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;

  bool init({int sampleRate = 48000, int channels = 2}) {
    final ok = _engine.create(sampleRate: sampleRate, channels: channels);
    if (ok) {
      _startStatusPolling();
    }
    return ok;
  }

  void dispose() {
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
    return _engine.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      useLazyPreparation: useLazyPreparation,
      shuffleOrder: shuffleOrder,
    );
  }

  bool addAudioSource(AudioSource source) =>
      _engine.addAudioSourceUri(source.uri);
  bool insertAudioSource(int index, AudioSource source) =>
      _engine.insertAudioSource(
        index,
        source.uri.scheme == 'file'
            ? source.uri.toFilePath()
            : source.uri.toString(),
      );
  bool removeAudioSourceAt(int index) => _engine.removeAudioSourceAt(index);
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

  void setReverbEnabled(bool enabled) => _engine.setReverbEnabled(enabled);
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
