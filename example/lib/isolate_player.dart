import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart'; // For RootIsolateToken
import 'package:sautiflow/sautiflow.dart';

/// A wrapper that runs [MiniAudioPlayer] in a separate isolate.
class IsolateAudioPlayer {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _ready = Completer();

  final _statusController = StreamController<PlayerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();

  final List<Map<String, dynamic>> _pendingCommands = [];
  bool _networkStreamingSupported = false;

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;

  MiniAudioSystemAudioController? _systemAudio;

  Future<void> init({bool enableSystemAudio = true}) async {
    // Spawn the isolate
    final token = RootIsolateToken.instance;

    // Always disable system audio inside the isolate to prevent conflicts.
    // We will handle it on the main isolate.
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateInitData(_receivePort.sendPort, token, false),
    );

    // Initialize system audio controller on the main isolate
    if (enableSystemAudio) {
      _systemAudio = MiniAudioSystemAudioController(
        statusStream: statusStream,
        onPlay: play,
        onPause: pause,
        onStop: stop,
        onNext: next,
        onPrevious: previous,
        onSeek: (pos) => seekTo(pos),
        onSetGain: setGain,
      );
      await _systemAudio!.enable();
    }

    // Listen for messages from the isolate
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _flushPendingCommands();
        if (!_ready.isCompleted) _ready.complete();
      } else if (message is PlayerStatus) {
        _statusController.add(message);
      } else if (message is Map) {
        if (message['type'] == 'capabilities') {
          final supported = message['networkStreamingSupported'] == true;
          _networkStreamingSupported = supported;
          _logController.add(
            '[capabilities] network streaming: ${supported ? 'enabled' : 'disabled'}',
          );
        }
      } else if (message is String) {
        if (message.startsWith('[log]')) {
          _logController.add(message.substring(5));
        } else {
          _logController.add(message);
        }
      }
    });
  }

  void _flushPendingCommands() {
    if (_sendPort == null) return;
    for (final cmd in _pendingCommands) {
      _sendPort!.send(cmd);
    }
    _pendingCommands.clear();
  }

  void _send(Map<String, dynamic> cmd) {
    if (_sendPort != null) {
      _sendPort!.send(cmd);
    } else {
      _pendingCommands.add(cmd);
    }
  }

  void dispose() {
    _send({'cmd': 'dispose'});
    _isolate?.kill();
    _statusController.close();
    _logController.close();
    _receivePort.close();
  }

  // --- Commands ---

  void play() => _send({'cmd': 'play'});
  void pause() => _send({'cmd': 'pause'});
  void stop() => _send({'cmd': 'stop'});

  void load(AudioSource source) => _send({'cmd': 'load', 'source': source});

  void setAudioSources(List<AudioSource> sources,
      {int initialIndex = 0,
      Duration? initialPosition,
      bool useLazyPreparation = true}) {
    _send({
      'cmd': 'setAudioSources',
      'sources': sources,
      'index': initialIndex,
      'position': initialPosition?.inMilliseconds,
      'lazy': useLazyPreparation
    });
  }

  void addAudioSource(AudioSource source) =>
      _send({'cmd': 'addAudioSource', 'source': source});

  void seekTo(Duration position, {int? index}) {
    _send(
        {'cmd': 'seekTo', 'position': position.inMilliseconds, 'index': index});
  }

  void seekToNext() => next();
  void seekToPrevious() => previous();

  void setEqEnabled(bool enabled) =>
      _send({'cmd': 'setEqEnabled', 'enabled': enabled});
  void setEq({double? low, double? mid, double? high}) {
    _send({'cmd': 'setEq', 'low': low, 'mid': mid, 'high': high});
  }

  void setGain(double gain) => _send({'cmd': 'setGain', 'gain': gain});
  void setPan(double pan) => _send({'cmd': 'setPan', 'pan': pan});

  void setReverbEnabled(bool enabled) =>
      _send({'cmd': 'setReverbEnabled', 'enabled': enabled});
  void setReverb({double? mix, double? feedback, double? delayMs}) {
    _send({
      'cmd': 'setReverb',
      'mix': mix,
      'feedback': feedback,
      'delayMs': delayMs
    });
  }

  void setLowpass({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setLowpass', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setHighpass({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setHighpass', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setDelay(
      {double? mix, double? feedback, double? delayMs, bool? enabled}) {
    _send({
      'cmd': 'setDelay',
      'mix': mix,
      'feedback': feedback,
      'delayMs': delayMs,
      'enabled': enabled
    });
  }

  void setBandpass({bool? enabled, double? cutoffHz, double? q}) {
    _send({
      'cmd': 'setBandpass',
      'enabled': enabled,
      'cutoffHz': cutoffHz,
      'q': q,
    });
  }

  void setPeakEq({
    bool? enabled,
    double? gainDb,
    double? q,
    double? frequencyHz,
  }) {
    _send({
      'cmd': 'setPeakEq',
      'enabled': enabled,
      'gainDb': gainDb,
      'q': q,
      'frequencyHz': frequencyHz,
    });
  }

  void setNotch({bool? enabled, double? q, double? frequencyHz}) {
    _send({
      'cmd': 'setNotch',
      'enabled': enabled,
      'q': q,
      'frequencyHz': frequencyHz,
    });
  }

  void setLowshelf({
    bool? enabled,
    double? gainDb,
    double? slope,
    double? frequencyHz,
  }) {
    _send({
      'cmd': 'setLowshelf',
      'enabled': enabled,
      'gainDb': gainDb,
      'slope': slope,
      'frequencyHz': frequencyHz,
    });
  }

  void setHighshelf({
    bool? enabled,
    double? gainDb,
    double? slope,
    double? frequencyHz,
  }) {
    _send({
      'cmd': 'setHighshelf',
      'enabled': enabled,
      'gainDb': gainDb,
      'slope': slope,
      'frequencyHz': frequencyHz,
    });
  }

  void setMultibandEqEnabled(bool enabled) =>
      _send({'cmd': 'setMultibandEqEnabled', 'enabled': enabled});

  void initMultibandEq(List<double> frequencies) {
    _send({'cmd': 'initMultibandEq', 'frequencies': frequencies});
  }

  void setMultibandEqBandGain(int index, double gain) {
    _send({'cmd': 'setMultibandEqBandGain', 'index': index, 'gain': gain});
  }

  void setOutputFormat(AudioFormat format) =>
      _send({'cmd': 'setOutputFormat', 'format': format.index});
  void setOutputSampleRate(int rate) =>
      _send({'cmd': 'setOutputSampleRate', 'rate': rate});
  void setOutputChannels(int channels) =>
      _send({'cmd': 'setOutputChannels', 'channels': channels});

  void pushStream(String url) => _send({'cmd': 'pushStream', 'url': url});

  bool isNetworkStreamingSupported() => _networkStreamingSupported;
  String getLastError() => "";
  void clearLastError() => _send({'cmd': 'clearLastError'});

  // ignore: avoid_void_async
  Future<void> updateNowPlaying({
    required String id,
    required String title,
    required String artist,
    required Duration duration,
    String? album,
    String? artUri,
  }) async {
    if (_systemAudio != null) {
      await _systemAudio!.updateNowPlaying(
        id: id,
        title: title,
        artist: artist,
        duration: duration,
        album: album,
      );
    }
  }

  void setLoopMode(LoopMode mode) =>
      _send({'cmd': 'setLoopMode', 'mode': mode.index});
  void setShuffleModeEnabled(bool enabled) =>
      _send({'cmd': 'setShuffle', 'enabled': enabled});
  void next() => _send({'cmd': 'next'});
  void previous() => _send({'cmd': 'previous'});
  void moveAudioSource(int oldIndex, int newIndex) =>
      _send({'cmd': 'move', 'oldIndex': oldIndex, 'newIndex': newIndex});
  void removeAudioSourceAt(int index) =>
      _send({'cmd': 'removeAudioSourceAt', 'index': index});
}

class _IsolateInitData {
  final SendPort sendPort;
  final RootIsolateToken? rootToken;
  final bool enableSystemAudio;

  _IsolateInitData(this.sendPort, this.rootToken, this.enableSystemAudio);
}

void _isolateEntry(_IsolateInitData initData) {
  if (initData.rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(initData.rootToken!);
  }

  final receivePort = ReceivePort();
  initData.sendPort.send(receivePort.sendPort);

  final player = MiniAudioPlayer();
  player.init(enableSystemAudio: initData.enableSystemAudio);
  initData.sendPort.send({
    'type': 'capabilities',
    'networkStreamingSupported': player.isNetworkStreamingSupported(),
  });

  player.statusStream.listen((status) {
    initData.sendPort.send(status);
  });

  player.logStream.listen((log) {
    initData.sendPort.send('[log]$log');
  });

  receivePort.listen((message) {
    if (message is Map) {
      final cmd = message['cmd'];
      switch (cmd) {
        case 'play':
          player.play();
          break;
        case 'pause':
          player.pause();
          break;
        case 'stop':
          player.stop();
          break;
        case 'load':
          try {
            player.setAudioSources([message['source'] as AudioSource]);
          } catch (e) {
            initData.sendPort.send('[log]Error loading source: $e');
          }
          break;
        case 'setAudioSources':
          try {
            player.setAudioSources(
                (message['sources'] as List).cast<AudioSource>(),
                initialIndex: message['index'] ?? 0,
                initialPosition: message['position'] != null
                    ? Duration(milliseconds: message['position'])
                    : Duration.zero);
          } catch (e) {
            initData.sendPort.send('[log]Error setting sources: $e');
          }
          break;
        case 'addAudioSource':
          try {
            player.addAudioSource(message['source'] as AudioSource);
          } catch (e) {
            initData.sendPort.send('[log]Error adding source: $e');
          }
          break;
        case 'seekTo':
          player.seekTo(Duration(milliseconds: message['position']),
              index: message['index']);
          break;
        case 'setEqEnabled':
          player.setEqEnabled(message['enabled']);
          break;
        case 'setEq':
          player.setEq(
              low: message['low'], mid: message['mid'], high: message['high']);
          break;
        case 'setGain':
          player.setGain(message['gain']);
          break;
        case 'setPan':
          player.setPan(message['pan']);
          break;
        case 'setReverbEnabled':
          player.setReverbEnabled(message['enabled']);
          break;
        case 'setReverb':
          player.setReverb(
              mix: message['mix'],
              feedback: message['feedback'],
              delayMs: message['delayMs']);
          break;
        case 'setDelay':
          player.setDelay(
              enabled: message['enabled'],
              mix: message['mix'],
              feedback: message['feedback'],
              delayMs: message['delayMs']);
          break;
        case 'setBandpass':
          player.setBandpass(
            enabled: message['enabled'] ?? false,
            cutoffHz: message['cutoffHz'] ?? 1000.0,
            q: message['q'] ?? 0.707,
          );
          break;
        case 'setPeakEq':
          player.setPeakEq(
            enabled: message['enabled'] ?? false,
            gainDb: message['gainDb'] ?? 0.0,
            q: message['q'] ?? 1.0,
            frequencyHz: message['frequencyHz'] ?? 1000.0,
          );
          break;
        case 'setNotch':
          player.setNotch(
            enabled: message['enabled'] ?? false,
            q: message['q'] ?? 1.0,
            frequencyHz: message['frequencyHz'] ?? 1000.0,
          );
          break;
        case 'setLowshelf':
          player.setLowshelf(
            enabled: message['enabled'] ?? false,
            gainDb: message['gainDb'] ?? 0.0,
            slope: message['slope'] ?? 1.0,
            frequencyHz: message['frequencyHz'] ?? 200.0,
          );
          break;
        case 'setHighshelf':
          player.setHighshelf(
            enabled: message['enabled'] ?? false,
            gainDb: message['gainDb'] ?? 0.0,
            slope: message['slope'] ?? 1.0,
            frequencyHz: message['frequencyHz'] ?? 4000.0,
          );
          break;
        case 'setLowpass':
          player.setLowpass(
              enabled: message['enabled'], cutoffHz: message['cutoffHz']);
          break;
        case 'setHighpass':
          player.setHighpass(
              enabled: message['enabled'], cutoffHz: message['cutoffHz']);
          break;
        case 'setMultibandEqEnabled':
          player.setMultibandEqEnabled(message['enabled']);
          break;
        case 'initMultibandEq':
          player
              .initMultibandEq((message['frequencies'] as List).cast<double>());
          break;
        case 'setMultibandEqBandGain':
          player.setMultibandEqBandGain(message['index'], message['gain']);
          break;
        case 'setOutputFormat':
          player.setOutputFormat(AudioFormat.values[message['format']]);
          break;
        case 'setOutputSampleRate':
          player.setOutputSampleRate(message['rate']);
          break;
        case 'setOutputChannels':
          player.setOutputChannels(message['channels']);
          break;
        case 'clearLastError':
          player.clearLastError();
          break;
        case 'setLoopMode':
          player.setLoopMode(LoopMode.values[message['mode']]);
          break;
        case 'setShuffle':
          player.setShuffleModeEnabled(message['enabled']);
          break;
        case 'next':
          player.seekToNext();
          break;
        case 'previous':
          player.seekToPrevious();
          break;
        case 'move':
          player.moveAudioSource(message['oldIndex'], message['newIndex']);
          break;
        case 'removeAudioSourceAt':
          player.removeAudioSourceAt(message['index']);
          break;
        case 'updateNowPlaying':
          player.updateNowPlaying(
            id: message['id'],
            title: message['title'],
            artist: message['artist'],
            duration: Duration(milliseconds: message['duration']),
          );
          break;
        case 'pushStream':
          player.pushStream(url: message['url']).catchError((e) {
            initData.sendPort.send('[log]PushStream Error: $e');
          });
          break;
        case 'dispose':
          player.dispose();
          Isolate.current.kill();
          break;
      }
    }
  });
}
