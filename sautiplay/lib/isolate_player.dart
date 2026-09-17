import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // For RootIsolateToken
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/desktop_system_audio.dart';
import 'package:sautiplay/services/wav_parser.dart';
import 'package:sautiplay/services/dlna_service.dart';

/// A wrapper that runs [MiniAudioPlayer] in a separate isolate.
class IsolateAudioPlayer {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Completer<void> _ready = Completer();

  final _statusController = StreamController<PlayerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _analyzerController = StreamController<Float32List>.broadcast();
  final _telemetryController = StreamController<StreamTelemetry>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();

  final List<Map<String, dynamic>> _pendingCommands = [];
  bool _networkStreamingSupported = false;
  StreamTelemetry _lastTelemetry = const StreamTelemetry();
  bool _isBuffering = false;
  PlayerStatus? _lastStatus;
  bool _isPlaying = false;

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  Stream<Float32List> get analyzerStream => _analyzerController.stream;
  Stream<StreamTelemetry> get streamTelemetryStream =>
      _telemetryController.stream;
  Stream<bool> get bufferingStream => _bufferingController.stream;
  StreamTelemetry get streamTelemetry => _lastTelemetry;
  bool get isBuffering => _isBuffering;
  PlayerStatus? get currentStatus => _lastStatus;
  bool get isPlaying => _isPlaying;

  MiniAudioSystemAudioController? _systemAudio;
  DesktopSystemAudioController? _desktopAudio;

  int _nextRequestId = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  StreamSubscription<PlayerStatus>? _desktopAudioSub;
  ReceivePort? _errorPort;

  Future<void> init({bool enableSystemAudio = true}) async {
    // Spawn the isolate with an error port
    final token = RootIsolateToken.instance;
    _errorPort = ReceivePort();
    _errorPort!.listen((error) {
      _logController.add('[isolate-error] $error');
    });

    // Always disable system audio inside the isolate to prevent conflicts.
    // We will handle it on the main isolate.
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateInitData(_receivePort.sendPort, token, false),
      onError: _errorPort!.sendPort,
    );

    // Initialize system audio controller on the main isolate
    if (enableSystemAudio) {
      if (Platform.isAndroid || Platform.isIOS) {
        _systemAudio = MiniAudioSystemAudioController(
          statusStream: statusStream,
          telemetryStream: _telemetryController.stream,
          onPlay: play,
          onPause: pause,
          onStop: stop,
          onNext: next,
          onPrevious: previous,
          onSeek: (pos) => seekTo(pos),
          onSetGain: setGain,
        );
        await _systemAudio!.enable(
          config: const MiniAudioSystemAudioConfig(
            androidNotificationIcon: 'mipmap/launcher_icon',
          ),
        );
      } else if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        _desktopAudio = DesktopSystemAudioController(
          onPlay: play,
          onPause: pause,
          onNext: next,
          onPrevious: previous,
          onSeek: (pos) => seekTo(pos),
        );
        await _desktopAudio!.enable();

        _desktopAudioSub?.cancel();
        _desktopAudioSub = _statusController.stream.listen((status) {
          _desktopAudio?.updatePlaybackStatus(status.isPlaying);
        });
      }
    }

    // Listen for messages from the isolate
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _flushPendingCommands();
        if (!_ready.isCompleted) _ready.complete();
      } else if (message is PlayerStatus) {
        _lastStatus = message;
        _isPlaying = message.isPlaying;
        _statusController.add(message);
      } else if (message is Float32List) {
        _analyzerController.add(message);
      } else if (message is StreamTelemetry) {
        _lastTelemetry = message;
        _telemetryController.add(message);
      } else if (message is Map) {
        if (message.containsKey('_replyId')) {
          final reqId = message['_replyId'] as int;
          final completer = _pendingRequests.remove(reqId);
          if (completer != null && !completer.isCompleted) {
            if (message.containsKey('error')) {
              completer.completeError(Exception(message['error']));
            } else {
              completer.complete(message['result']);
            }
          }
          return;
        }

        if (message['type'] == 'capabilities') {
          final supported = message['networkStreamingSupported'] == true;
          _networkStreamingSupported = supported;
          _logController.add(
            '[capabilities] network streaming: ${supported ? 'enabled' : 'disabled'}',
          );
        } else if (message['type'] == 'buffering') {
          final buffering = message['isBuffering'] == true;
          _isBuffering = buffering;
          _bufferingController.add(buffering);
        } else if (message['type'] == 'clippedCount') {
          _clippedSamplesCount = (message['count'] as int?) ?? 0;
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

  Future<dynamic> _request(String cmd,
      [Map<String, dynamic>? data,
      Duration timeout = const Duration(milliseconds: 500)]) {
    final reqId = ++_nextRequestId;
    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;
    _send({
      'cmd': cmd,
      '_reqId': reqId,
      if (data != null) ...data,
    });
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequests.remove(reqId);
      return null;
    });
  }

  void dispose() {
    _desktopAudioSub?.cancel();
    _desktopAudioSub = null;
    _errorPort?.close();
    _errorPort = null;

    _send({'cmd': 'dispose'});

    Future.delayed(const Duration(milliseconds: 250), () {
      _isolate?.kill();
      _isolate = null;
    });

    _systemAudio?.disable();
    _desktopAudio?.dispose();
    _statusController.close();
    _logController.close();
    _analyzerController.close();
    _telemetryController.close();
    _bufferingController.close();
    _receivePort.close();
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pendingRequests.clear();
  }

  // --- Commands ---

  void play() {
    _isPlaying = true;
    if (DlnaService.instance.activeRenderer != null) {
      DlnaService.instance.play();
    }
    _send({'cmd': 'play'});
  }

  void pause() {
    _isPlaying = false;
    if (DlnaService.instance.activeRenderer != null) {
      DlnaService.instance.pause();
    }
    _send({'cmd': 'pause'});
  }

  void stop() {
    _isPlaying = false;
    if (DlnaService.instance.activeRenderer != null) {
      DlnaService.instance.stop();
    }
    _send({'cmd': 'stop'});
  }

  void load(AudioSource source) => _send({'cmd': 'load', 'source': source});

  void setAudioSources(List<AudioSource> sources,
      {int initialIndex = 0,
      Duration? initialPosition,
      bool useLazyPreparation = true,
      bool autoPlay = true}) {
    _send({
      'cmd': 'setAudioSources',
      'sources': sources,
      'index': initialIndex,
      'position': initialPosition?.inMilliseconds,
      'lazy': useLazyPreparation,
      'autoPlay': autoPlay,
    });
  }

  void addAudioSource(AudioSource source) =>
      _send({'cmd': 'addAudioSource', 'source': source});

  void seekTo(Duration position, {int? index}) {
    _send({
      'cmd': 'seekTo',
      'position': position.inMilliseconds,
      'index': index,
    });
  }

  void seekToNext() => next();
  void seekToPrevious() => previous();

  void setEqEnabled(bool enabled) =>
      _send({'cmd': 'setEqEnabled', 'enabled': enabled});
  void setEq({double? low, double? mid, double? high}) {
    _send({'cmd': 'setEq', 'low': low, 'mid': mid, 'high': high});
  }

  void setGain(double gain) => _send({'cmd': 'setGain', 'gain': gain});
  void setReplayGain(double gainDb) =>
      _send({'cmd': 'setReplayGain', 'gainDb': gainDb});
  void setPan(double pan) => _send({'cmd': 'setPan', 'pan': pan});
  void setRate(double rate) => _send({'cmd': 'setRate', 'rate': rate});
  void setPitch(double pitch) => _send({'cmd': 'setPitch', 'pitch': pitch});
  void setPitchCorrection(bool enabled) =>
      _send({'cmd': 'setPitchCorrection', 'enabled': enabled});

  void setSpatializationEnabled(bool enabled) =>
      _send({'cmd': 'setSpatializationEnabled', 'enabled': enabled});
  void setPosition({required double x, required double y, required double z}) {
    _send({'cmd': 'setPosition', 'x': x, 'y': y, 'z': z});
  }

  void setDirection(
          {required double x, required double y, required double z}) =>
      _send({'cmd': 'setDirection', 'x': x, 'y': y, 'z': z});
  void setVelocity({required double x, required double y, required double z}) =>
      _send({'cmd': 'setVelocity', 'x': x, 'y': y, 'z': z});
  void setSoundCone({
    required double innerAngleRad,
    required double outerAngleRad,
    required double outerGain,
  }) =>
      _send({
        'cmd': 'setSoundCone',
        'innerAngleRad': innerAngleRad,
        'outerAngleRad': outerAngleRad,
        'outerGain': outerGain,
      });
  void setAttenuationModel(int model) =>
      _send({'cmd': 'setAttenuationModel', 'model': model});
  void setRolloff(double rolloff) =>
      _send({'cmd': 'setRolloff', 'rolloff': rolloff});
  void setMinGain(double minGain) =>
      _send({'cmd': 'setMinGain', 'minGain': minGain});
  void setMaxGain(double maxGain) =>
      _send({'cmd': 'setMaxGain', 'maxGain': maxGain});
  void setMinDistance(double minDistance) =>
      _send({'cmd': 'setMinDistance', 'minDistance': minDistance});
  void setMaxDistance(double maxDistance) =>
      _send({'cmd': 'setMaxDistance', 'maxDistance': maxDistance});
  void setDopplerFactor(double dopplerFactor) =>
      _send({'cmd': 'setDopplerFactor', 'dopplerFactor': dopplerFactor});

  void setListenerPosition(
          {required double x, required double y, required double z}) =>
      _send({'cmd': 'setListenerPosition', 'x': x, 'y': y, 'z': z});
  void setListenerDirection(
          {required double x, required double y, required double z}) =>
      _send({'cmd': 'setListenerDirection', 'x': x, 'y': y, 'z': z});
  void setListenerVelocity(
          {required double x, required double y, required double z}) =>
      _send({'cmd': 'setListenerVelocity', 'x': x, 'y': y, 'z': z});
  void setListenerWorldUp(
          {required double x, required double y, required double z}) =>
      _send({'cmd': 'setListenerWorldUp', 'x': x, 'y': y, 'z': z});
  void setListenerCone({
    required double innerAngleRad,
    required double outerAngleRad,
    required double outerGain,
  }) =>
      _send({
        'cmd': 'setListenerCone',
        'innerAngleRad': innerAngleRad,
        'outerAngleRad': outerAngleRad,
        'outerGain': outerGain,
      });

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

  void setReverbEx({
    required bool enabled,
    required double wet,
    required double dry,
    required double roomSize,
    required double damping,
    required double preDelayMs,
    required double width,
  }) {
    _send({
      'cmd': 'setReverbEx',
      'enabled': enabled,
      'wet': wet,
      'dry': dry,
      'roomSize': roomSize,
      'damping': damping,
      'preDelayMs': preDelayMs,
      'width': width,
    });
  }

  void setReverbGains({required double wet, required double dry}) {
    _send({'cmd': 'setReverbGains', 'wet': wet, 'dry': dry});
  }

  void setLowpass({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setLowpass', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setHighpass({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setHighpass', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setCustomLpf1({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setCustomLpf1', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setCustomHpf1({bool? enabled, double? cutoffHz}) {
    _send({'cmd': 'setCustomHpf1', 'enabled': enabled, 'cutoffHz': cutoffHz});
  }

  void setCustomBiquad({
    bool? enabled,
    double? b0,
    double? b1,
    double? b2,
    double? a0,
    double? a1,
    double? a2,
  }) {
    _send({
      'cmd': 'setCustomBiquad',
      'enabled': enabled,
      'b0': b0,
      'b1': b1,
      'b2': b2,
      'a0': a0,
      'a1': a1,
      'a2': a2,
    });
  }

  void setEngineResampleAlgorithm(int algorithm) {
    _send({'cmd': 'setEngineResampleAlgorithm', 'algorithm': algorithm});
  }

  void setEngineDitherMode(int mode) {
    _send({'cmd': 'setEngineDitherMode', 'mode': mode});
  }

  void set64BitProcessingEnabled(bool enabled) {
    _send({'cmd': 'set64BitProcessingEnabled', 'enabled': enabled});
  }

  void setDspOversampling(int factor) {
    _send({'cmd': 'setDspOversampling', 'factor': factor});
  }

  void setAutoSampleRateMatchEnabled(bool enabled) {
    _send({'cmd': 'setAutoSampleRateMatchEnabled', 'enabled': enabled});
  }

  void setAutoBitPerfectEnabled(bool enabled) =>
      setAutoSampleRateMatchEnabled(enabled);

  // --- Limiter & Clipping Detection ---

  int _clippedSamplesCount = 0;

  // --- Dynamic Range Compressor ---

  void setCompressorEnabled(bool enabled) =>
      _send({'cmd': 'setCompressorEnabled', 'enabled': enabled});

  void setCompressorParams({
    double thresholdDb = -20.0,
    double ratio = 4.0,
    double attackMs = 10.0,
    double releaseMs = 100.0,
    double makeupGainDb = 0.0,
    double kneeDb = 6.0,
    int detector = 0,
    bool stereoLink = true,
    bool autoMakeup = false,
    double mix = 1.0,
  }) =>
      _send({
        'cmd': 'setCompressorParams',
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'makeupGainDb': makeupGainDb,
        'kneeDb': kneeDb,
        'detector': detector,
        'stereoLink': stereoLink,
        'autoMakeup': autoMakeup,
        'mix': mix,
      });

  Future<double> getCompressorGainReductionDB() async {
    final response = await _request('getCompressorGainReductionDB');
    return (response as num?)?.toDouble() ?? 0.0;
  }

  void setLimiterEnabled(bool enabled) =>
      _send({'cmd': 'setLimiterEnabled', 'enabled': enabled});

  void setLimiterParams({
    double threshold = 0.95,
    double attackMs = 2.0,
    double releaseMs = 50.0,
  }) =>
      _send({
        'cmd': 'setLimiterParams',
        'threshold': threshold,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
      });

  void setClippingDetectionEnabled(bool enabled) =>
      _send({'cmd': 'setClippingDetectionEnabled', 'enabled': enabled});

  int getClippedSamplesCount() => _clippedSamplesCount;

  void resetClippedSamplesCount() {
    _clippedSamplesCount = 0;
    _send({'cmd': 'resetClippedSamplesCount'});
  }

  // ── Release 1 Quality Foundation API ────────────────────────────────────────

  void setLoudnessNormalizerEnabled(bool enabled) =>
      _send({'cmd': 'setLoudnessNormalizerEnabled', 'enabled': enabled});

  void setLoudnessNormalizerTarget(double targetLUFS) =>
      _send({'cmd': 'setLoudnessNormalizerTarget', 'targetLUFS': targetLUFS});

  void resetLoudnessMeter() => _send({'cmd': 'resetLoudnessMeter'});

  void setLookaheadLimiterEnabled(bool enabled) =>
      _send({'cmd': 'setLookaheadLimiterEnabled', 'enabled': enabled});

  void setLookaheadLimiterParams({
    double ceilingDBTP = -1.0,
    double attackMs = 2.0,
    double releaseMs = 50.0,
  }) =>
      _send({
        'cmd': 'setLookaheadLimiterParams',
        'ceilingDBTP': ceilingDBTP,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
      });

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

  void setStereoWiden(
      {required bool enabled, required double width, required double delayMs}) {
    _send({
      'cmd': 'setStereoWiden',
      'enabled': enabled,
      'width': width,
      'delayMs': delayMs
    });
  }

  void setStereoImager({
    required bool enabled,
    required double width,
    int mode = 0,
    double monoBelowHz = 150.0,
    double airBoostDb = 1.5,
    double delayMs = 15.0,
  }) {
    _send({
      'cmd': 'setStereoImager',
      'enabled': enabled,
      'width': width,
      'mode': mode,
      'monoBelowHz': monoBelowHz,
      'airBoostDb': airBoostDb,
      'delayMs': delayMs,
    });
  }

  void setStereoEnhancement({required bool enabled, double mix = 0.5}) {
    _send({
      'cmd': 'setStereoEnhancement',
      'enabled': enabled,
      'mix': mix,
    });
  }

  void setCrossfeed({required bool enabled, required int preset}) {
    _send({'cmd': 'setCrossfeed', 'enabled': enabled, 'preset': preset});
  }

  void setCrossfeedAlgorithm(CrossfeedAlgorithm algorithm) {
    _send({'cmd': 'setCrossfeedAlgorithm', 'algorithm': algorithm.index});
  }

  void setCrossfeedParams({
    required double mix,
    required double delayMs,
    required double cutoffHz,
    bool outputCompensation = true,
  }) {
    _send({
      'cmd': 'setCrossfeedParams',
      'mix': mix,
      'delayMs': delayMs,
      'cutoffHz': cutoffHz,
      'outputCompensation': outputCompensation,
    });
  }

  void setRaceParams({
    double delayMs = 0.166,
    double alpha = 0.55,
    double lpfHz = 2500.0,
  }) {
    _send({
      'cmd': 'setRaceParams',
      'delayMs': delayMs,
      'alpha': alpha,
      'lpfHz': lpfHz,
    });
  }

  void setOpenStageParams({
    double angleDegrees = 60.0,
    double gainDb = -1.0,
  }) {
    _send({
      'cmd': 'setOpenStageParams',
      'angleDegrees': angleDegrees,
      'gainDb': gainDb,
    });
  }

  void setDynamicBass(
      {required bool enabled, required int preset, required double gain}) {
    _send({
      'cmd': 'setDynamicBass',
      'enabled': enabled,
      'preset': preset,
      'gain': gain,
    });
  }

  void setCrystalizer({
    required bool enabled,
    double intensity = 0.5,
    bool highShelfEnabled = true,
    double highShelfGainDb = 2.0,
  }) {
    _send({
      'cmd': 'setCrystalizer',
      'enabled': enabled,
      'intensity': intensity,
      'highShelfEnabled': highShelfEnabled,
      'highShelfGainDb': highShelfGainDb,
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

  void initMultibandFx(List<EqBandConfig> bands, {bool enabled = true}) {
    _send({
      'cmd': 'initMultibandFx',
      'bands': bands
          .map((b) => {
                'type': b.type.index,
                'frequencyHz': b.frequencyHz,
                'q': b.q,
                'gainDb': b.gainDb,
                'slope': b.slope,
                'enabled': b.enabled,
              })
          .toList(),
      'enabled': enabled,
    });
  }

  void setMultibandFxBands(List<EqBandConfig> bands) {
    _send({
      'cmd': 'setMultibandFxBands',
      'bands': bands
          .map((b) => {
                'type': b.type.index,
                'frequencyHz': b.frequencyHz,
                'q': b.q,
                'gainDb': b.gainDb,
                'slope': b.slope,
                'enabled': b.enabled,
              })
          .toList(),
    });
  }

  void setMultibandFxEnabled(bool enabled) =>
      _send({'cmd': 'setMultibandFxEnabled', 'enabled': enabled});

  void clearMultibandFx() => _send({'cmd': 'clearMultibandFx'});

  // --- Sauti Clean-Room Audio DSP Suite ---
  void resetDsp() => _send({'cmd': 'resetDsp'});

  void setClarity({
    required bool enabled,
    AudioClarityProfile profile = AudioClarityProfile.transientCrisp,
    double intensity = 0.5,
  }) =>
      _send({
        'cmd': 'setClarity',
        'enabled': enabled,
        'profile': profile.value,
        'intensity': intensity,
      });

  void setHarmonicBass({
    required bool enabled,
    HarmonicBassProfile profile = HarmonicBassProfile.subBassResonant,
    double cutoffHz = 60.0,
    double boost = 1.0,
  }) =>
      _send({
        'cmd': 'setHarmonicBass',
        'enabled': enabled,
        'profile': profile.value,
        'cutoffHz': cutoffHz,
        'boost': boost,
      });

  void setDynamicSystem({
    required bool enabled,
    TransducerProfile profile = TransducerProfile.earphone,
    double strength = 0.5,
  }) =>
      _send({
        'cmd': 'setDynamicSystem',
        'enabled': enabled,
        'profile': profile.value,
        'strength': strength,
      });

  void setAnalogWarmth({
    required bool enabled,
    AnalogWarmthProfile profile = AnalogWarmthProfile.triode12AX7,
    double drive = 0.5,
  }) =>
      _send({
        'cmd': 'setAnalogWarmth',
        'enabled': enabled,
        'profile': profile.value,
        'drive': drive,
      });

  void setDialogEnhancer({
    required bool enabled,
    DialogEnhancerProfile profile = DialogEnhancerProfile.cinema,
    double amount = 0.65,
    double ducking = 0.55,
    double clarity = 0.60,
    double centerFocus = 0.70,
  }) =>
      _send({
        'cmd': 'setDialogEnhancer',
        'enabled': enabled,
        'profile': profile.value,
        'amount': amount,
        'ducking': ducking,
        'clarity': clarity,
        'centerFocus': centerFocus,
      });

  void setDeEsser({
    required bool enabled,
    DeEsserMode mode = DeEsserMode.splitBand,
    double intensity = 0.5,
  }) =>
      _send({
        'cmd': 'setDeEsser',
        'enabled': enabled,
        'mode': mode.value,
        'intensity': intensity,
      });

  void setDeEsserEx({
    required bool enabled,
    DeEsserMode mode = DeEsserMode.splitBand,
    double frequencyHz = 5500.0,
    double thresholdDb = -22.0,
    double ratio = 4.0,
    double maxReductionDb = 12.0,
    double attackMs = 1.0,
    double releaseMs = 35.0,
  }) =>
      _send({
        'cmd': 'setDeEsserEx',
        'enabled': enabled,
        'mode': mode.value,
        'frequencyHz': frequencyHz,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'maxReductionDb': maxReductionDb,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
      });

  void setDeEsserPreset(DeEsserPreset preset) =>
      _send({
        'cmd': 'setDeEsserPreset',
        'preset': preset.value,
      });

  Future<double> getDeEsserGainReductionDB() async {
    final response = await _request('getDeEsserGainReductionDB');
    return (response as num?)?.toDouble() ?? 0.0;
  }

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
  }) =>
      _send({
        'cmd': 'setDownwardExpander',
        'enabled': enabled,
        'preset': preset.value,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'rangeDb': rangeDb,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'kneeDb': kneeDb,
        'sidechainHpfHz': sidechainHpfHz,
      });

  void setDownwardExpanderEx({
    required bool enabled,
    double thresholdDb = -52.0,
    double ratio = 1.8,
    double rangeDb = -16.0,
    double attackMs = 12.0,
    double releaseMs = 280.0,
    double kneeDb = 6.0,
    double sidechainHpfHz = 50.0,
  }) =>
      _send({
        'cmd': 'setDownwardExpanderEx',
        'enabled': enabled,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'rangeDb': rangeDb,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'kneeDb': kneeDb,
        'sidechainHpfHz': sidechainHpfHz,
      });

  void setConvolverEnabled(bool enabled) =>
      _send({'cmd': 'setConvolverEnabled', 'enabled': enabled});

  /// Spatial Surround Suite:
  /// - Cinema Matrix 5.1 (Cleanroom Pro Logic II)
  /// - Binaural HRTF Virtualizer (Reconstructed from Dolby analysis_dlby2)
  /// - 3D Acoustic Stage (Reconstructed from AM3D Zirene re_workspace)
  void setSurround({
    required bool enabled,
    SurroundMode mode = SurroundMode.off,
    // Mode 1: Cinema Matrix 5.1
    double centerFocus = 0.6,
    double surroundBoost = 1.2,
    double surroundDelayMs = 15.0,
    double headRadiusCm = 8.75,
    // Mode 2: Binaural Virtualizer
    int binauralMode = 0,
    double binauralBoost = 0.65,
    int binauralRoomPreset = 2,
    double binauralRoomMix = 0.35,
    int binauralSpeakerAngle = 1,
    double binauralShadowCutoff = 3500.0,
    // Mode 3: 3D Acoustic Stage
    int stageProfile = 0,
    int stageMode = 0,
    double stageWidth = 1.2,
    double stageDepth = 0.5,
    double stageCancellation = 0.60,
    double stageAirPresence = 0.40,
    double stageBassAnchorHz = 60.0,
    // Backwards compatibility
    double fieldWidth = 1.4,
    int vhsRoomPreset = 2,
    double haasDelayMs = 5.5,
  }) =>
      _send({
        'cmd': 'setSurround',
        'enabled': enabled,
        'mode': mode.value,
        'centerFocus': centerFocus,
        'surroundBoost': surroundBoost,
        'surroundDelayMs': surroundDelayMs,
        'headRadiusCm': headRadiusCm,
        'binauralMode': binauralMode,
        'binauralBoost': binauralBoost,
        'binauralRoomPreset': binauralRoomPreset,
        'binauralRoomMix': binauralRoomMix,
        'binauralSpeakerAngle': binauralSpeakerAngle,
        'binauralShadowCutoff': binauralShadowCutoff,
        'stageProfile': stageProfile,
        'stageMode': stageMode,
        'stageWidth': stageWidth,
        'stageDepth': stageDepth,
        'stageCancellation': stageCancellation,
        'stageAirPresence': stageAirPresence,
        'stageBassAnchorHz': stageBassAnchorHz,
        'fieldWidth': fieldWidth,
        'vhsRoomPreset': vhsRoomPreset,
        'haasDelayMs': haasDelayMs,
      });

  void loadConvolverIr(String path) {
    if (path.startsWith('assets/')) {
      _loadConvolverIrAsset(path);
      return;
    }
    _send({'cmd': 'loadConvolverIr', 'path': path});
  }

  Future<void> _loadConvolverIrAsset(String assetKey) async {
    try {
      final data = await rootBundle.load(assetKey);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      _send({'cmd': 'loadConvolverIrData', 'bytes': bytes});
    } catch (e) {
      debugPrint('loadConvolverIrAsset($assetKey) failed: $e');
    }
  }

  void clearConvolverIr() => _send({'cmd': 'clearConvolverIr'});

  void setConvolverMix({double wet = 1.0, double dry = 0.0}) =>
      _send({'cmd': 'setConvolverMix', 'wet': wet, 'dry': dry});

  void setMasterLimiter({
    required bool enabled,
    double ceilingDb = -0.1,
    double outputGainDb = 0.0,
    double releaseMs = 60.0,
  }) =>
      _send({
        'cmd': 'setMasterLimiter',
        'enabled': enabled,
        'ceilingDb': ceilingDb,
        'outputGainDb': outputGainDb,
        'releaseMs': releaseMs,
      });

  // --- Dynamic Loudness (ISO 226 Equal-Loudness Contour) ---
  void setDynamicLoudnessEnabled(bool enabled) =>
      _send({'cmd': 'setDynamicLoudnessEnabled', 'enabled': enabled});

  void setDynamicLoudnessParams({
    double refLevelDb = 0.0,
    double maxBassBoostDb = 9.0,
    double maxTrebleBoostDb = 4.5,
    double bassFreqHz = 90.0,
    double trebleFreqHz = 9000.0,
  }) =>
      _send({
        'cmd': 'setDynamicLoudnessParams',
        'refLevelDb': refLevelDb,
        'maxBassBoostDb': maxBassBoostDb,
        'maxTrebleBoostDb': maxTrebleBoostDb,
        'bassFreqHz': bassFreqHz,
        'trebleFreqHz': trebleFreqHz,
      });

  Future<({double bassBoostDb, double trebleBoostDb})>
      getDynamicLoudnessCurrentBoost() async {
    final response = await _request('getDynamicLoudnessCurrentBoost');
    if (response is Map) {
      return (
        bassBoostDb: (response['bassBoostDb'] as num?)?.toDouble() ?? 0.0,
        trebleBoostDb: (response['trebleBoostDb'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return (bassBoostDb: 0.0, trebleBoostDb: 0.0);
  }

  // --- AutoEQ Headphone Profile Importer ---
  Future<({int bandCount, double preampDb})> loadAutoEqProfileFile(
      String filePath) async {
    final response = await _request('loadAutoEqProfileFile', {'path': filePath},
        const Duration(seconds: 3));
    if (response is Map) {
      return (
        bandCount: (response['bandCount'] as num?)?.toInt() ?? -1,
        preampDb: (response['preampDb'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return (bandCount: -1, preampDb: 0.0);
  }

  Future<({int bandCount, double preampDb})> loadAutoEqProfileString(
      String profileText) async {
    final response = await _request(
        'loadAutoEqProfileString', {'text': profileText},
        const Duration(seconds: 3));
    if (response is Map) {
      return (
        bandCount: (response['bandCount'] as num?)?.toInt() ?? -1,
        preampDb: (response['preampDb'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return (bandCount: -1, preampDb: 0.0);
  }

  // --- Studio Noise Gate ---
  void setNoiseGateEnabled(bool enabled) =>
      _send({'cmd': 'setNoiseGateEnabled', 'enabled': enabled});

  void setNoiseGateParams({
    double openThreshDb = -42.0,
    double closeThreshDb = -48.0,
    double holdMs = 80.0,
    double attackMs = 1.0,
    double releaseMs = 120.0,
    double sidechainHpfHz = 80.0,
  }) =>
      _send({
        'cmd': 'setNoiseGateParams',
        'openThreshDb': openThreshDb,
        'closeThreshDb': closeThreshDb,
        'holdMs': holdMs,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'sidechainHpfHz': sidechainHpfHz,
      });

  Future<double> getNoiseGateGainReductionDb() async {
    final response = await _request('getNoiseGateGainReductionDb');
    return (response as num?)?.toDouble() ?? 0.0;
  }

  // --- Broadcast Leveller (Slow-Window AGC) ---
  void setLevellerEnabled(bool enabled) =>
      _send({'cmd': 'setLevellerEnabled', 'enabled': enabled});

  void setLevellerParams({
    double targetLufs = -16.0,
    double maxRiseDbSec = 0.75,
    double maxFallDbSec = 1.5,
    double maxBoostDb = 9.0,
    double maxAttenuationDb = 12.0,
    double silenceGateLufs = -45.0,
  }) =>
      _send({
        'cmd': 'setLevellerParams',
        'targetLufs': targetLufs,
        'maxRiseDbSec': maxRiseDbSec,
        'maxFallDbSec': maxFallDbSec,
        'maxBoostDb': maxBoostDb,
        'maxAttenuationDb': maxAttenuationDb,
        'silenceGateLufs': silenceGateLufs,
      });

  Future<double> getLevellerCurrentGainDb() async {
    final response = await _request('getLevellerCurrentGainDb');
    return (response as num?)?.toDouble() ?? 0.0;
  }

  // --- 6-Band Dynamic Parametric EQ (DynamicEqDSP) ---
  void setDynamicEqEnabled(bool enabled) =>
      _send({'cmd': 'setDynamicEqEnabled', 'enabled': enabled});

  void setDynamicEqBand({
    required int bandIndex,
    DynamicEqFilterType filterType = DynamicEqFilterType.peak,
    DynamicEqMode mode = DynamicEqMode.compress,
    required double freqHz,
    double q = 1.0,
    double baseGainDb = 0.0,
    double thresholdDb = -24.0,
    double rangeDb = 6.0,
    double ratio = 3.0,
    double attackMs = 2.0,
    double releaseMs = 60.0,
    bool enabled = true,
  }) =>
      _send({
        'cmd': 'setDynamicEqBand',
        'bandIndex': bandIndex,
        'filterType': filterType.value,
        'mode': mode.value,
        'freqHz': freqHz,
        'q': q,
        'baseGainDb': baseGainDb,
        'thresholdDb': thresholdDb,
        'rangeDb': rangeDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'enabled': enabled,
      });

  Future<double> getDynamicEqBandGainOffsetDb(int bandIndex) async {
    final response =
        await _request('getDynamicEqBandGainOffsetDb', {'bandIndex': bandIndex});
    return (response as num?)?.toDouble() ?? 0.0;
  }

  // --- Vintage Tape Wow, Flutter & Drift (TapeDriftDSP) ---
  void setTapeDriftEnabled(bool enabled) =>
      _send({'cmd': 'setTapeDriftEnabled', 'enabled': enabled});

  void setTapeDriftParams({
    double wowRateHz = 0.8,
    double wowDepthMs = 0.35,
    double flutterRateHz = 12.0,
    double flutterDepthMs = 0.08,
    double driftDepthMs = 0.10,
    double stereoPhaseDeg = 45.0,
    double hfDampingHz = 18000.0,
  }) =>
      _send({
        'cmd': 'setTapeDriftParams',
        'wowRateHz': wowRateHz,
        'wowDepthMs': wowDepthMs,
        'flutterRateHz': flutterRateHz,
        'flutterDepthMs': flutterDepthMs,
        'driftDepthMs': driftDepthMs,
        'stereoPhaseDeg': stereoPhaseDeg,
        'hfDampingHz': hfDampingHz,
      });

  void setTapeDriftPreset(TapeDriftPreset preset) =>
      _send({'cmd': 'setTapeDriftPreset', 'preset': preset.value});

  void setSpeakerProtectionParams({
    required bool enabled,
    required double subsonicCutoffHz,
    required double ultrasonicCutoffHz,
    required double limiterThreshold,
    required double safetyAttenuationDb,
  }) =>
      _send({
        'cmd': 'setSpeakerProtectionParams',
        'enabled': enabled,
        'subsonicCutoffHz': subsonicCutoffHz,
        'ultrasonicCutoffHz': ultrasonicCutoffHz,
        'limiterThreshold': limiterThreshold,
        'safetyAttenuationDb': safetyAttenuationDb,
      });

  void configureAnalyzer({int frameSize = 512, String? windowType}) =>
      _send({
        'cmd': 'configureAnalyzer',
        'frameSize': frameSize,
        if (windowType != null) 'windowType': windowType,
      });

  void setAnalyzerWindowType(String windowType) =>
      _send({'cmd': 'setAnalyzerWindowType', 'windowType': windowType});

  void setAnalyzerEnabled(bool enabled) =>
      _send({'cmd': 'setAnalyzerEnabled', 'enabled': enabled});

  void setOutputFormat(AudioFormat format) =>
      _send({'cmd': 'setOutputFormat', 'format': format.index});
  void setOutputSampleRate(int rate) =>
      _send({'cmd': 'setOutputSampleRate', 'rate': rate});
  void setOutputChannels(int channels) =>
      _send({'cmd': 'setOutputChannels', 'channels': channels});

  void setOutputBuffer({int periodFrames = 0, int periodCount = 0}) =>
      _send({
        'cmd': 'setOutputBuffer',
        'periodFrames': periodFrames,
        'periodCount': periodCount,
      });

  Future<({int periodFrames, int periodCount})> getOutputBuffer() async {
    final response = await _request('getOutputBuffer');
    if (response is Map) {
      return (
        periodFrames: (response['periodFrames'] as int?) ?? 0,
        periodCount: (response['periodCount'] as int?) ?? 0,
      );
    }
    return (periodFrames: 0, periodCount: 0);
  }

  void setPhaseInversion(
          {required bool invertLeft, required bool invertRight}) =>
      _send({
        'cmd': 'setPhaseInversion',
        'invertLeft': invertLeft,
        'invertRight': invertRight,
      });

  void setLrSwap(bool enabled) =>
      _send({'cmd': 'setLrSwap', 'enabled': enabled});

  void setChannelGains(
          {required double leftLinear, required double rightLinear}) =>
      _send({
        'cmd': 'setChannelGains',
        'leftLinear': leftLinear,
        'rightLinear': rightLinear,
      });

  void setChannelGainsDb({required double leftDb, required double rightDb}) =>
      _send({
        'cmd': 'setChannelGainsDb',
        'leftDb': leftDb,
        'rightDb': rightDb,
      });

  void setExclusiveMode(bool enabled) =>
      _send({'cmd': 'setExclusiveMode', 'enabled': enabled});

  Future<bool> getExclusiveMode() async {
    final response = await _request('getExclusiveMode');
    return response as bool? ?? false;
  }

  void setOutputBackend(AudioOutputBackend backend) =>
      _send({'cmd': 'setOutputBackend', 'backend': backend.value});

  Future<AudioOutputBackend> getOutputBackend() async {
    final response = await _request('getOutputBackend');
    if (response is int) {
      return AudioOutputBackend.fromInt(response);
    }
    return AudioOutputBackend.auto;
  }

  Future<bool> isBackendSupported(AudioOutputBackend backend) async {
    final response =
        await _request('isBackendSupported', {'backend': backend.value});
    return response as bool? ?? false;
  }

  Future<double> getDeviceLatencyMs() async {
    final response = await _request('getDeviceLatencyMs');
    return (response as num?)?.toDouble() ?? 0.0;
  }

  Future<PipelineAudioState> getPipelineState() async {
    final response = await _request('getPipelineState');
    return response as PipelineAudioState;
  }

  Future<AEHardwareInfo> getHardwareInfo() async {
    final response = await _request('getHardwareInfo');
    return response as AEHardwareInfo;
  }

  Future<Map<String, dynamic>> getAudioProperties() async {
    final response = await _request('getAudioProperties');
    return (response as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> inspectFile(String path) async {
    final response = await _request('inspectFile', {'path': path});
    return (response as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> readFileTags(String path) async {
    final response = await _request('readFileTags', {'path': path});
    return (response as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> getEngineTelemetry() async {
    final response = await _request('getEngineTelemetry');
    return (response as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

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
    if (_desktopAudio != null) {
      await _desktopAudio!.updateNowPlaying(
        id: id,
        title: title,
        artist: artist,
        duration: duration,
        album: album,
        artUri: artUri,
      );
    }

    if (_systemAudio != null) {
      final parsedUri = (artUri != null && artUri.isNotEmpty)
          ? Uri.tryParse(artUri)
          : null;
      try {
        await _systemAudio!.updateNowPlaying(
          id: id,
          title: title,
          artist: artist,
          duration: duration,
          album: album,
          artUri: parsedUri,
        );
      } catch (e) {
        _logController.add('[now-playing] system audio update error: $e');
      }
    }
  }

  void setLoopMode(LoopMode mode) =>
      _send({'cmd': 'setLoopMode', 'mode': mode.index});
  void setShuffleModeEnabled(bool enabled) =>
      _send({'cmd': 'setShuffle', 'enabled': enabled});
  void setCrossfadeEnabled(bool enabled) =>
      _send({'cmd': 'setCrossfadeEnabled', 'enabled': enabled});
  void setCrossfadeDurationMs(int durationMs) =>
      _send({'cmd': 'setCrossfadeDurationMs', 'durationMs': durationMs});
  void setLoudnessCrossfadeEnabled(bool enabled) =>
      _send({'cmd': 'setLoudnessCrossfadeEnabled', 'enabled': enabled});
  void setNextReplayGain(double gainDb) =>
      _send({'cmd': 'setNextReplayGain', 'gainDb': gainDb});
  void next() => _send({'cmd': 'next'});
  void previous() => _send({'cmd': 'previous'});
  void moveAudioSource(int oldIndex, int newIndex) =>
      _send({'cmd': 'move', 'oldIndex': oldIndex, 'newIndex': newIndex});
  void removeAudioSourceAt(int index) =>
      _send({'cmd': 'removeAudioSourceAt', 'index': index});

  /// Enable or disable A-B repeat loop.
  /// Set [enabled] to false (with any start/end) to clear the loop.
  void setAbRepeat({
    required bool enabled,
    required double startSeconds,
    required double endSeconds,
  }) =>
      _send({
        'cmd': 'setAbRepeat',
        'enabled': enabled,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
      });
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

  player.streamTelemetryStream.listen((tel) {
    initData.sendPort.send(tel);
  });

  player.bufferingStream.listen((buffering) {
    initData.sendPort.send({'type': 'buffering', 'isBuffering': buffering});
  });

  player.logStream.listen((log) {
    initData.sendPort.send('[log]$log');
  });

  player.analyzerStream.listen((samples) {
    initData.sendPort.send(samples);
  });

  List<AudioSource> isolateSources = [];
  final Map<String, TrackNativeInfo> fileInfoCache = {};
  final Map<String, NativeAudioMetadata> metadataCache = {};

  void sendResponse(Map message, dynamic result, [Object? error]) {
    final reqId = message['_reqId'];
    if (reqId != null) {
      if (error != null) {
        initData.sendPort.send({'_replyId': reqId, 'error': error.toString()});
      } else {
        initData.sendPort.send({'_replyId': reqId, 'result': result});
      }
      return;
    }
    final replyTo = message['replyTo'] as SendPort?;
    if (replyTo != null) {
      if (error != null) {
        replyTo.send({'error': error.toString()});
      } else {
        replyTo.send(result);
      }
    }
  }

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
            final source = message['source'] as AudioSource;
            isolateSources = [source];
            if (!player.isNetworkStreamingSupported() && source.isNetwork) {
              final url = source.uri.toString();
              initData.sendPort.send(
                '[log]Native network streaming unavailable; falling back to pushStream for: $url',
              );
              player.pushStream(url: url).catchError((e) {
                initData.sendPort.send('[log]PushStream Error: $e');
              });
              break;
            }
            player.setAudioSources([source]);
          } catch (e) {
            initData.sendPort.send('[log]Error loading source: $e');
          }
          break;
        case 'setAudioSources':
          try {
            final sources = (message['sources'] as List).cast<AudioSource>();
            isolateSources = List<AudioSource>.from(sources);
            if (!player.isNetworkStreamingSupported()) {
              final hasNetworkSource = sources.any((s) => s.isNetwork);
              if (hasNetworkSource) {
                if (sources.length == 1) {
                  final url = sources.first.uri.toString();
                  initData.sendPort.send(
                    '[log]Native network streaming unavailable; falling back to pushStream for: $url',
                  );
                  player.pushStream(url: url).catchError((e) {
                    initData.sendPort.send('[log]PushStream Error: $e');
                  });
                } else {
                  initData.sendPort.send(
                    '[log]Native network streaming unavailable for playlist network sources. Build Android native libs with curl to enable direct network playlist playback.',
                  );
                }
                break;
              }
            }

            player.setAudioSources(
              sources,
              initialIndex: message['index'] ?? 0,
              initialPosition: message['position'] != null
                  ? Duration(milliseconds: message['position'])
                  : Duration.zero,
              autoPlay: message['autoPlay'] ?? true,
            );
          } catch (e) {
            initData.sendPort.send('[log]Error setting sources: $e');
          }
          break;
        case 'addAudioSource':
          try {
            final src = message['source'] as AudioSource;
            isolateSources.add(src);
            player.addAudioSource(src);
          } catch (e) {
            initData.sendPort.send('[log]Error adding source: $e');
          }
          break;
        case 'seekTo':
          // Execute the seek synchronously inside the isolate.
          // The UI layer (onChangeEnd slider) and the debounce timer on the
          // sender side guarantee only one seek arrives at a time.
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
        case 'setReplayGain':
          player.setReplayGain(message['gainDb'] as double);
          break;
        case 'setPan':
          player.setPan(message['pan']);
          break;
        case 'setRate':
          final r = (message['rate'] as num?)?.toDouble() ?? 1.0;
          player.setRate(r);
          break;
        case 'setPitch':
          final p = (message['pitch'] as num?)?.toDouble() ?? 1.0;
          player.setPitch(p);
          break;
        case 'setPitchCorrection':
          final en = message['enabled'] as bool? ?? true;
          player.setPitchCorrection(en);
          break;
        case 'setSpatializationEnabled':
          player.setSpatializationEnabled(message['enabled']);
          break;
        case 'setPosition':
          player.setPosition(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setDirection':
          player.setDirection(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setVelocity':
          player.setVelocity(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setSoundCone':
          player.setSoundCone(
            innerAngleRad: message['innerAngleRad'],
            outerAngleRad: message['outerAngleRad'],
            outerGain: message['outerGain'],
          );
          break;
        case 'setAttenuationModel':
          player.setAttenuationModel(message['model']);
          break;
        case 'setRolloff':
          player.setRolloff(message['rolloff']);
          break;
        case 'setMinGain':
          player.setMinGain(message['minGain']);
          break;
        case 'setMaxGain':
          player.setMaxGain(message['maxGain']);
          break;
        case 'setMinDistance':
          player.setMinDistance(message['minDistance']);
          break;
        case 'setMaxDistance':
          player.setMaxDistance(message['maxDistance']);
          break;
        case 'setDopplerFactor':
          player.setDopplerFactor(message['dopplerFactor']);
          break;
        case 'setListenerPosition':
          player.setListenerPosition(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setListenerDirection':
          player.setListenerDirection(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setListenerVelocity':
          player.setListenerVelocity(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setListenerWorldUp':
          player.setListenerWorldUp(
            x: message['x'],
            y: message['y'],
            z: message['z'],
          );
          break;
        case 'setListenerCone':
          player.setListenerCone(
            innerAngleRad: message['innerAngleRad'],
            outerAngleRad: message['outerAngleRad'],
            outerGain: message['outerGain'],
          );
          break;
        case 'setReverbEnabled':
          player.setReverbEnabled(message['enabled']);
          break;
        case 'setReverb':
          player.setReverb(
              mix: message['mix'] ?? 0.25,
              feedback: message['feedback'] ?? 0.5,
              delayMs: message['delayMs'] ?? 50.0);
          break;
        case 'setReverbEx':
          player.setReverbEx(
            enabled: message['enabled'] as bool? ?? false,
            wet: (message['wet'] as num?)?.toDouble() ?? 0.25,
            dry: (message['dry'] as num?)?.toDouble() ?? 0.75,
            roomSize: (message['roomSize'] as num?)?.toDouble() ?? 0.6,
            damping: (message['damping'] as num?)?.toDouble() ?? 0.4,
            preDelayMs: (message['preDelayMs'] as num?)?.toDouble() ?? 20.0,
            width: (message['width'] as num?)?.toDouble() ?? 1.0,
          );
          break;
        case 'setReverbGains':
          player.setReverbGains(
            wet: (message['wet'] as num?)?.toDouble() ?? 0.25,
            dry: (message['dry'] as num?)?.toDouble() ?? 0.75,
          );
          break;
        case 'setDelay':
          player.setDelay(
              enabled: message['enabled'] ?? false,
              mix: message['mix'] ?? 0.3,
              feedback: message['feedback'] ?? 0.4,
              delayMs: message['delayMs'] ?? 250.0);
          break;
        case 'setStereoWiden':
          player.setStereoWiden(
              enabled: message['enabled'] ?? false,
              width: message['width'] ?? 1.5,
              delayMs: message['delayMs'] ?? 15.0);
          break;
        case 'setStereoImager':
          player.setStereoImager(
            enabled: message['enabled'] ?? false,
            width: (message['width'] as num?)?.toDouble() ?? 1.2,
            mode: message['mode'] ?? 0,
            monoBelowHz: (message['monoBelowHz'] as num?)?.toDouble() ?? 150.0,
            airBoostDb: (message['airBoostDb'] as num?)?.toDouble() ?? 1.5,
            delayMs: (message['delayMs'] as num?)?.toDouble() ?? 15.0,
          );
          break;
        case 'setStereoEnhancement':
          player.setStereoEnhancement(
            enabled: message['enabled'] ?? false,
            mix: (message['mix'] as num?)?.toDouble() ?? 0.5,
          );
          break;
        case 'setCrossfeed':
          player.setCrossfeed(
              enabled: message['enabled'] ?? false,
              preset: message['preset'] ?? 0);
          break;
        case 'setCrossfeedAlgorithm':
          final algoIdx = (message['algorithm'] as int? ?? 0)
              .clamp(0, CrossfeedAlgorithm.values.length - 1);
          player.setCrossfeedAlgorithm(CrossfeedAlgorithm.values[algoIdx]);
          break;
        case 'setCrossfeedParams':
          player.setCrossfeedParams(
            mix: (message['mix'] as num?)?.toDouble() ?? 0.5,
            delayMs: (message['delayMs'] as num?)?.toDouble() ?? 0.40,
            cutoffHz: (message['cutoffHz'] as num?)?.toDouble() ?? 700.0,
            outputCompensation: message['outputCompensation'] as bool? ?? true,
          );
          break;
        case 'setRaceParams':
          player.setRaceParams(
            delayMs: (message['delayMs'] as num?)?.toDouble() ?? 0.166,
            alpha: (message['alpha'] as num?)?.toDouble() ?? 0.55,
            lpfHz: (message['lpfHz'] as num?)?.toDouble() ?? 2500.0,
          );
          break;
        case 'setOpenStageParams':
          player.setOpenStageParams(
            angleDegrees:
                (message['angleDegrees'] as num?)?.toDouble() ?? 60.0,
            gainDb: (message['gainDb'] as num?)?.toDouble() ?? -1.0,
          );
          break;
        case 'setDynamicBass':
          player.setDynamicBass(
              enabled: message['enabled'] ?? false,
              preset: message['preset'] ?? 18,
              gain: message['gain'] ?? 100.0);
          break;
        case 'setCrystalizer':
          player.setCrystalizer(
            enabled: message['enabled'] ?? false,
            intensity: (message['intensity'] as num?)?.toDouble() ?? 0.5,
            highShelfEnabled: message['highShelfEnabled'] ?? true,
            highShelfGainDb:
                (message['highShelfGainDb'] as num?)?.toDouble() ?? 2.0,
          );
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
        case 'setCustomLpf1':
          player.setCustomLpf1(
              enabled: message['enabled'] ?? false,
              cutoffHz: message['cutoffHz'] ?? 500.0);
          break;
        case 'setCustomHpf1':
          player.setCustomHpf1(
              enabled: message['enabled'] ?? false,
              cutoffHz: message['cutoffHz'] ?? 120.0);
          break;
        case 'setCustomBiquad':
          player.setCustomBiquad(
            enabled: message['enabled'] ?? false,
            b0: message['b0'] ?? 1.0,
            b1: message['b1'] ?? 0.0,
            b2: message['b2'] ?? 0.0,
            a0: message['a0'] ?? 1.0,
            a1: message['a1'] ?? 0.0,
            a2: message['a2'] ?? 0.0,
          );
          break;
        case 'setEngineResampleAlgorithm':
          final algoIdx = (message['algorithm'] as int?) ?? 0;
          if (algoIdx >= 0 && algoIdx < ResampleAlgorithm.values.length) {
            player
                .setEngineResampleAlgorithm(ResampleAlgorithm.values[algoIdx]);
          } else {
            player
                .setEngineResampleAlgorithm(ResampleAlgorithm.miniaudioLinear);
          }
          break;
        case 'setEngineDitherMode':
          player.setEngineDitherMode(message['mode'] ?? 0);
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
        case 'initMultibandFx':
          {
            final rawBands = (message['bands'] as List)
                .cast<Map>()
                .cast<Map<dynamic, dynamic>>();
            final bands = rawBands
                .map(
                  (m) => EqBandConfig(
                    type: EqBandType.values[(m['type'] as int)],
                    frequencyHz: (m['frequencyHz'] as num).toDouble(),
                    q: (m['q'] as num).toDouble(),
                    gainDb: (m['gainDb'] as num).toDouble(),
                    slope: (m['slope'] as num).toDouble(),
                    enabled: (m['enabled'] as bool?) ?? true,
                  ),
                )
                .toList();
            player.initMultibandFx(
              bands,
              enabled: (message['enabled'] as bool?) ?? true,
            );
          }
          break;
        case 'setMultibandFxBands':
          {
            final rawBands = (message['bands'] as List)
                .cast<Map>()
                .cast<Map<dynamic, dynamic>>();
            final bands = rawBands
                .map(
                  (m) => EqBandConfig(
                    type: EqBandType.values[(m['type'] as int)],
                    frequencyHz: (m['frequencyHz'] as num).toDouble(),
                    q: (m['q'] as num).toDouble(),
                    gainDb: (m['gainDb'] as num).toDouble(),
                    slope: (m['slope'] as num).toDouble(),
                    enabled: (m['enabled'] as bool?) ?? true,
                  ),
                )
                .toList();
            player.setMultibandFxBands(bands);
          }
          break;
        case 'setMultibandFxEnabled':
          player.setMultibandFxEnabled(message['enabled'] == true);
          break;
        case 'clearMultibandFx':
          player.clearMultibandFx();
          break;
        case 'setAnalyzerEnabled':
          player.setAnalyzerEnabled(message['enabled'] == true);
          break;
        case 'configureAnalyzer':
          final wtStr = message['windowType'] as String?;
          final wt = wtStr != null ? FftWindowType.fromString(wtStr) : null;
          player.configureAnalyzer(
            frameSize: (message['frameSize'] as int?) ?? 512,
            windowType: wt,
          );
          break;
        case 'setAnalyzerWindowType':
          final wtStr = message['windowType'] as String?;
          if (wtStr != null) {
            player.setAnalyzerWindowType(FftWindowType.fromString(wtStr));
          }
          break;
        case 'setSpeakerProtectionParams':
          {
            final bool enabled = message['enabled'] == true;
            final double subHz =
                (message['subsonicCutoffHz'] as num?)?.toDouble() ?? 25.0;
            final double ultraHz =
                (message['ultrasonicCutoffHz'] as num?)?.toDouble() ?? 20000.0;
            final double threshold =
                (message['limiterThreshold'] as num?)?.toDouble() ?? 0.95;

            if (enabled) {
              if (subHz > 0) {
                player.setHighpass(enabled: true, cutoffHz: subHz);
              } else {
                player.setHighpass(enabled: false, cutoffHz: 20.0);
              }
              if (ultraHz > 0) {
                player.setLowpass(enabled: true, cutoffHz: ultraHz);
              } else {
                player.setLowpass(enabled: false, cutoffHz: 20000.0);
              }
              player.setLimiterEnabled(true);
              player.setLimiterParams(threshold: threshold);
            } else {
              player.setHighpass(enabled: false, cutoffHz: 20.0);
              player.setLowpass(enabled: false, cutoffHz: 20000.0);
            }
          }
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
        case 'setOutputBuffer':
          player.setOutputBuffer(
            periodFrames: message['periodFrames'] ?? 0,
            periodCount: message['periodCount'] ?? 0,
          );
          break;
        case 'setPhaseInversion':
          player.setPhaseInversion(
            invertLeft: message['invertLeft'] == true,
            invertRight: message['invertRight'] == true,
          );
          initData.sendPort.send(
            '[log]Phase Inversion updated: L=${message['invertLeft']}, R=${message['invertRight']}',
          );
          break;
        case 'setLrSwap':
          player.setLrSwap(message['enabled'] == true);
          initData.sendPort.send(
            '[log]L/R Swap updated: ${message['enabled']}',
          );
          break;
        case 'setChannelGains':
          player.setChannelGains(
            leftLinear: (message['leftLinear'] as num).toDouble(),
            rightLinear: (message['rightLinear'] as num).toDouble(),
          );
          initData.sendPort.send(
            '[log]Channel Gains updated: L=${message['leftLinear']}, R=${message['rightLinear']}',
          );
          break;
        case 'setChannelGainsDb':
          player.setChannelGainsDb(
            leftDb: (message['leftDb'] as num).toDouble(),
            rightDb: (message['rightDb'] as num).toDouble(),
          );
          initData.sendPort.send(
            '[log]Channel Gains dB updated: L=${message['leftDb']}dB, R=${message['rightDb']}dB',
          );
          break;
        case 'setExclusiveMode':
          player.setExclusiveMode(message['enabled'] == true);
          break;
        case 'setOutputBackend':
          final bVal = message['backend'] as int? ?? 0;
          player.setOutputBackend(AudioOutputBackend.fromInt(bVal));
          break;
        case 'setLoudnessNormalizerEnabled':
          player.setLoudnessNormalizerEnabled(message['enabled'] == true);
          break;
        case 'setLoudnessNormalizerTarget':
          player.setLoudnessNormalizerTarget(
              (message['targetLUFS'] as num).toDouble());
          break;
        case 'resetLoudnessMeter':
          player.resetLoudnessMeter();
          break;
        case 'setLookaheadLimiterEnabled':
          player.setLookaheadLimiterEnabled(message['enabled'] == true);
          break;
        case 'setLookaheadLimiterParams':
          player.setLookaheadLimiterParams(
            ceilingDBTP: (message['ceilingDBTP'] as num?)?.toDouble() ?? -1.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 2.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 50.0,
          );
          break;
        case 'set64BitProcessingEnabled':
          player.set64BitProcessingEnabled(message['enabled'] == true);
          break;
        case 'setDspOversampling':
          player.setDspOversampling((message['factor'] as num?)?.toInt() ?? 1);
          break;
        case 'setAutoSampleRateMatchEnabled':
        case 'setAutoBitPerfectEnabled':
          player.setAutoSampleRateMatchEnabled(message['enabled'] == true);
          break;
        case 'getExclusiveMode':
          try {
            sendResponse(message, player.getExclusiveMode());
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getOutputBackend':
          try {
            sendResponse(message, player.getOutputBackend().value);
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'isBackendSupported':
          final supVal = message['backend'] as int? ?? 0;
          try {
            sendResponse(message, player.isBackendSupported(AudioOutputBackend.fromInt(supVal)));
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getPipelineState':
          try {
            sendResponse(message, player.pipelineState);
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getDeviceLatencyMs':
          try {
            sendResponse(message, player.deviceLatencyMs);
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getAudioProperties':
          try {
            sendResponse(message, {
              'channels': player.getOutputChannels(),
              'format': player.getOutputFormat().name,
              'sampleRate': player.getOutputSampleRate(),
            });
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getOutputBuffer':
          try {
            final buf = player.getOutputBuffer();
            sendResponse(message, {
              'periodFrames': buf.periodFrames,
              'periodCount': buf.periodCount,
            });
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'getEngineTelemetry':
          try {
            final hw = player.hardwareInfo;
            final ps = player.pipelineState;
            final samples = player.engineLatencySamples;
            final ms = player.engineLatencyMs;
            final devMs = player.deviceLatencyMs;
            final clipped = player.getClippedSamplesCount();
            final resamplePolicy = player.getResamplingPolicyInfo();
            final resampleAlgo = player.getEngineResampleAlgorithm().name;
            final crossfeedParams = player.getCrossfeedParams();
            final dspOn = ps.eqEnabled || ps.limiterEnabled || ps.reverbEnabled;
            final qt = player.getQualityTelemetry();
            final st = player.getStreamTelemetry();
            int inputRate = ps.inputSampleRate;
            int inputChannels = ps.inputChannels;
            int inputBitDepth = 16;
            String fileType = 'PCM';
            int bitrateKbps = 0;
            int fileSizeBytes = 0;
            double? rgTrack;
            double? rgAlbum;
            double? rgTrackPeak;
            double? rgAlbumPeak;
            String? currentFilePath;
            final status = player.status;
            if (status.currentIndex >= 0 &&
                status.currentIndex < isolateSources.length) {
              final src = isolateSources[status.currentIndex];
              if (!src.isNetwork) {
                String? path;
                try {
                  if (src.uri.scheme == 'file') {
                    path = src.uri.toFilePath();
                  } else {
                    final str = Uri.decodeFull(src.uri.toString());
                    if (str.startsWith(RegExp(r'^[a-zA-Z]:[\\/]')) ||
                        str.startsWith('/')) {
                      path = str;
                    }
                  }
                } catch (_) {}

                if (path != null) {
                  currentFilePath = path;
                  TrackNativeInfo? info = fileInfoCache[path];
                  if (info == null) {
                    info = player.inspectFile(path);
                    if (info != null) {
                      if (fileInfoCache.length >= 500) {
                        fileInfoCache.remove(fileInfoCache.keys.first);
                      }
                      fileInfoCache[path] = info;
                    }
                  }
                  if (info != null) {
                    if (info.sampleRate > 0) inputRate = info.sampleRate;
                    if (info.channels > 0) inputChannels = info.channels;
                    if (info.bitDepth > 0) inputBitDepth = info.bitDepth;
                    if (info.formatName.isNotEmpty) fileType = info.formatName;
                    bitrateKbps = info.bitrateKbps;
                    fileSizeBytes = info.fileSizeBytes;
                  }

                  NativeAudioMetadata? meta = metadataCache[path];
                  if (meta == null) {
                    try {
                      meta = readMetadata(path, getImage: false);
                      if (metadataCache.length >= 500) {
                        metadataCache.remove(metadataCache.keys.first);
                      }
                      metadataCache[path] = meta;
                    } catch (_) {}
                  }
                  if (meta != null) {
                    if (meta.trackGainDb != 0.0) rgTrack = meta.trackGainDb;
                    if (meta.albumGainDb != 0.0) rgAlbum = meta.albumGainDb;
                    if (meta.trackPeak != 1.0 && meta.trackPeak > 0.0) {
                      rgTrackPeak = meta.trackPeak;
                    }
                    if (meta.albumPeak != 1.0 && meta.albumPeak > 0.0) {
                      rgAlbumPeak = meta.albumPeak;
                    }
                  }
                }
              } else {
                fileType = st.codecName.isNotEmpty
                    ? st.codecName.toUpperCase()
                    : 'STREAM';
                bitrateKbps = st.bitrate;
              }
            }

            sendResponse(message, {
              'hardware': hw.toJson(),
              'fileType': fileType,
              'bitrateKbps': bitrateKbps,
              'fileSizeBytes': fileSizeBytes,
              'filePath': currentFilePath,
              'replayGainTrack': rgTrack,
              'replayGainAlbum': rgAlbum,
              'replayGainTrackPeak': rgTrackPeak,
              'replayGainAlbumPeak': rgAlbumPeak,
              'inputFormat': ps.inputFormat,
              'inputSampleRate': inputRate,
              'inputChannels': inputChannels,
              'inputBitDepth': inputBitDepth,
              'processingFormat': ps.processingFormat,
              'processingSampleRate': ps.processingSampleRate,
              'processingChannels': ps.processingChannels,
              'outputFormat': ps.outputFormat,
              'outputSampleRate': ps.outputSampleRate,
              'outputChannels': ps.outputChannels,
              'eqEnabled': ps.eqEnabled,
              'reverbEnabled': ps.reverbEnabled,
              'limiterEnabled': ps.limiterEnabled,
              'stereoWidenEnabled': ps.stereoWidenEnabled,
              'stereoEnhancementEnabled': ps.stereoEnhancementEnabled,
              'spatializationEnabled': ps.spatializationEnabled,
              'delayEnabled': ps.delayEnabled,
              'gain': ps.gain,
              'pan': ps.pan,
              'pitch': ps.pitch,
              'engineLatencySamples': samples,
              'engineLatencyMs': ms,
              'deviceLatencyMs': devMs,
              'clippedCount': clipped,
              'resampleAlgorithm': resampleAlgo,
              'resampleLatencyMs': resamplePolicy.resamplerLatencyMs,
              'resampleIsLinearPhase': resamplePolicy.isLinearPhase,
              'resampleIsBypassed': resamplePolicy.isBypassed,
              'resampleFilterPassbandRatio': resamplePolicy.filterPassbandRatio,
              'crossfeedAlgo': crossfeedParams.algorithm.name,
              'crossfeedMix': crossfeedParams.mix,
              'crossfeedDelayMs': crossfeedParams.delayMs,
              'crossfeedCutoffHz': crossfeedParams.cutoffHz,
              'crossfeedComp': crossfeedParams.outputCompensation,
              'sautiDspEnabled': dspOn,
              'truePeakDBTP': qt.truePeakDBTP,
              'momentaryLUFS': qt.momentaryLUFS,
              'shortTermLUFS': qt.shortTermLUFS,
              'integratedLUFS': qt.integratedLUFS,
              'loudnessRangeLRA': qt.loudnessRangeLRA,
              'limiterGainReductionDB': qt.limiterGainReductionDB,
              'crestFactorDB': qt.crestFactorDB,
              'streamState': st.state.name,
              'streamBufferedDurationMs': st.bufferedDuration.inMilliseconds,
              'streamTotalDurationMs': st.totalDuration.inMilliseconds,
              'streamBufferPercent': st.bufferPercent,
              'streamBitrate': st.bitrate,
              'streamCodecName': st.codecName,
              'streamIcyTitle': st.icyTitle,
              'streamIcyArtist': st.icyArtist,
              'streamIsLive': st.isLive,
              'streamIsSeekable': st.isSeekable,
              'streamIsBuffering': st.isBuffering,
            });
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'inspectFile':
          try {
            final path = message['path'] as String;
            TrackNativeInfo? info = fileInfoCache[path];
            if (info == null) {
              info = player.inspectFile(path);
              if (info != null) {
                if (fileInfoCache.length >= 500) {
                  fileInfoCache.remove(fileInfoCache.keys.first);
                }
                fileInfoCache[path] = info;
              }
            }
            sendResponse(message, info?.toJson());
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'readFileTags':
          try {
            final path = message['path'] as String;
            final tags = player.readFileTags(path);
            sendResponse(message, tags?.toJson());
          } catch (e) {
            sendResponse(message, null, e);
          }
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
        case 'setCrossfadeEnabled':
          player.setCrossfadeEnabled(message['enabled'] == true);
          break;
        case 'setCrossfadeDurationMs':
          player.setCrossfadeDurationMs((message['durationMs'] as int?) ?? 0);
          break;
        case 'setLoudnessCrossfadeEnabled':
          player.setLoudnessCrossfadeEnabled(message['enabled'] == true);
          break;
        case 'setNextReplayGain':
          player.setNextReplayGain(
              (message['gainDb'] as num?)?.toDouble() ?? 0.0);
          break;
        case 'next':
          player.seekToNext();
          break;
        case 'previous':
          player.seekToPrevious();
          break;
        case 'move':
          final oldIdx = message['oldIndex'] as int;
          final newIdx = message['newIndex'] as int;
          player.moveAudioSource(oldIdx, newIdx);
          if (oldIdx >= 0 &&
              oldIdx < isolateSources.length &&
              newIdx >= 0 &&
              newIdx < isolateSources.length) {
            final item = isolateSources.removeAt(oldIdx);
            isolateSources.insert(newIdx, item);
          }
          break;
        case 'removeAudioSourceAt':
          final remIdx = message['index'] as int;
          player.removeAudioSourceAt(remIdx);
          if (remIdx >= 0 && remIdx < isolateSources.length) {
            isolateSources.removeAt(remIdx);
          }
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
        case 'setCompressorEnabled':
          player.setCompressorEnabled(message['enabled'] == true);
          break;
        case 'setCompressorParams':
          player.setCompressorParams(
            thresholdDb:
                (message['thresholdDb'] as num?)?.toDouble() ?? -20.0,
            ratio: (message['ratio'] as num?)?.toDouble() ?? 4.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 10.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 100.0,
            makeupGainDb:
                (message['makeupGainDb'] as num?)?.toDouble() ?? 0.0,
            kneeDb: (message['kneeDb'] as num?)?.toDouble() ?? 6.0,
            detector: (message['detector'] as int?) ?? 0,
            stereoLink: message['stereoLink'] != false,
            autoMakeup: message['autoMakeup'] == true,
            mix: (message['mix'] as num?)?.toDouble() ?? 1.0,
          );
          break;
        case 'getCompressorGainReductionDB':
          try {
            sendResponse(message, player.getCompressorGainReductionDB());
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setLimiterEnabled':
          player.setLimiterEnabled(message['enabled'] == true);
          break;
        case 'setLimiterParams':
          player.setLimiterParams(
            threshold: (message['threshold'] as num?)?.toDouble() ?? 0.95,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 2.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 50.0,
          );
          break;
        case 'setClippingDetectionEnabled':
          player.setClippingDetectionEnabled(message['enabled'] == true);
          initData.sendPort.send({
            'type': 'clippedCount',
            'count': player.getClippedSamplesCount(),
          });
          break;
        case 'resetClippedSamplesCount':
          player.resetClippedSamplesCount();
          initData.sendPort.send({'type': 'clippedCount', 'count': 0});
          break;
        case 'resetDsp':
          player.dsp.reset();
          break;
        case 'setClarity':
          player.dsp.setClarity(
            enabled: message['enabled'] == true,
            profile: AudioClarityProfile.values.firstWhere(
              (p) => p.value == message['profile'],
              orElse: () => AudioClarityProfile.transientCrisp,
            ),
            intensity: (message['intensity'] as num?)?.toDouble() ?? 0.5,
          );
          break;
        case 'setHarmonicBass':
          player.dsp.setHarmonicBass(
            enabled: message['enabled'] == true,
            profile: HarmonicBassProfile.values.firstWhere(
              (p) => p.value == message['profile'],
              orElse: () => HarmonicBassProfile.subBassResonant,
            ),
            cutoffHz: (message['cutoffHz'] as num?)?.toDouble() ?? 60.0,
            boost: (message['boost'] as num?)?.toDouble() ?? 1.0,
          );
          break;
        case 'setDynamicSystem':
          player.dsp.setDynamicSystem(
            enabled: message['enabled'] == true,
            profile: TransducerProfile.values.firstWhere(
              (p) => p.value == message['profile'],
              orElse: () => TransducerProfile.earphone,
            ),
            strength: (message['strength'] as num?)?.toDouble() ?? 0.5,
          );
          break;
        case 'setAnalogWarmth':
          player.dsp.setAnalogWarmth(
            enabled: message['enabled'] == true,
            profile: AnalogWarmthProfile.values.firstWhere(
              (p) => p.value == message['profile'],
              orElse: () => AnalogWarmthProfile.triode12AX7,
            ),
            drive: (message['drive'] as num?)?.toDouble() ?? 0.5,
          );
          break;
        case 'setDialogEnhancer':
          player.dsp.setDialogEnhancer(
            enabled: message['enabled'] == true,
            profile: DialogEnhancerProfile.values.firstWhere(
              (p) => p.value == message['profile'],
              orElse: () => DialogEnhancerProfile.cinema,
            ),
            amount: (message['amount'] as num?)?.toDouble() ?? 0.65,
            ducking: (message['ducking'] as num?)?.toDouble() ?? 0.55,
            clarity: (message['clarity'] as num?)?.toDouble() ?? 0.60,
            centerFocus: (message['centerFocus'] as num?)?.toDouble() ?? 0.70,
          );
          break;
        case 'setDeEsser':
          player.dsp.setDeEsser(
            enabled: message['enabled'] == true,
            mode: DeEsserMode.values.firstWhere(
              (m) => m.value == message['mode'],
              orElse: () => DeEsserMode.splitBand,
            ),
            intensity: (message['intensity'] as num?)?.toDouble() ?? 0.5,
          );
          break;
        case 'setDeEsserEx':
          player.dsp.setDeEsserEx(
            enabled: message['enabled'] == true,
            mode: DeEsserMode.values.firstWhere(
              (m) => m.value == message['mode'],
              orElse: () => DeEsserMode.splitBand,
            ),
            frequencyHz: (message['frequencyHz'] as num?)?.toDouble() ?? 5500.0,
            thresholdDb: (message['thresholdDb'] as num?)?.toDouble() ?? -22.0,
            ratio: (message['ratio'] as num?)?.toDouble() ?? 4.0,
            maxReductionDb:
                (message['maxReductionDb'] as num?)?.toDouble() ?? 12.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 1.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 35.0,
          );
          break;
        case 'setDeEsserPreset':
          player.dsp.setDeEsserPreset(
            DeEsserPreset.values.firstWhere(
              (p) => p.value == message['preset'],
              orElse: () => DeEsserPreset.gentleVocal,
            ),
          );
          break;
        case 'getDeEsserGainReductionDB':
          try {
            sendResponse(message, player.dsp.deEsserGainReductionDb);
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setDownwardExpander':
          player.dsp.setDownwardExpander(
            enabled: message['enabled'] == true,
            preset: DownwardExpanderPreset.values.firstWhere(
              (p) => p.value == message['preset'],
              orElse: () => DownwardExpanderPreset.vinylClean,
            ),
            thresholdDb: (message['thresholdDb'] as num?)?.toDouble(),
            ratio: (message['ratio'] as num?)?.toDouble(),
            rangeDb: (message['rangeDb'] as num?)?.toDouble(),
            attackMs: (message['attackMs'] as num?)?.toDouble(),
            releaseMs: (message['releaseMs'] as num?)?.toDouble(),
            kneeDb: (message['kneeDb'] as num?)?.toDouble(),
            sidechainHpfHz: (message['sidechainHpfHz'] as num?)?.toDouble(),
          );
          break;
        case 'setDownwardExpanderEx':
          player.dsp.setDownwardExpanderEx(
            enabled: message['enabled'] == true,
            thresholdDb:
                (message['thresholdDb'] as num?)?.toDouble() ?? -52.0,
            ratio: (message['ratio'] as num?)?.toDouble() ?? 1.8,
            rangeDb: (message['rangeDb'] as num?)?.toDouble() ?? -16.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 12.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 280.0,
            kneeDb: (message['kneeDb'] as num?)?.toDouble() ?? 6.0,
            sidechainHpfHz:
                (message['sidechainHpfHz'] as num?)?.toDouble() ?? 50.0,
          );
          break;
        case 'setConvolverEnabled':
          player.dsp.setConvolverEnabled(message['enabled'] == true);
          break;
        case 'setSurround':
          final mode = SurroundMode.values.firstWhere(
            (m) => m.value == message['mode'],
            orElse: () => SurroundMode.off,
          );
          final enabled = message['enabled'] == true;

          switch (mode) {
            case SurroundMode.matrixSurround:
              player.dsp.setSurroundMatrix(
                enabled: enabled,
                centerFocus: (message['centerFocus'] as num?)?.toDouble() ?? 0.6,
                surroundBoost: (message['surroundBoost'] as num?)?.toDouble() ?? 1.2,
                surroundDelayMs: (message['surroundDelayMs'] as num?)?.toDouble() ?? 15.0,
                headRadiusCm: (message['headRadiusCm'] as num?)?.toDouble() ?? 8.75,
              );
              break;
            case SurroundMode.binauralVirtualizer:
              player.dsp.setSurroundBinaural(
                enabled: enabled,
                mode: (message['binauralMode'] as num?)?.toInt() ?? 0,
                boost: (message['binauralBoost'] as num?)?.toDouble() ?? 0.65,
                roomPreset: (message['binauralRoomPreset'] as num?)?.toInt() ??
                    (message['vhsRoomPreset'] as num?)?.toInt() ?? 2,
                roomMix: (message['binauralRoomMix'] as num?)?.toDouble() ?? 0.35,
                speakerAngle: (message['binauralSpeakerAngle'] as num?)?.toInt() ?? 1,
                shadowCutoffHz: (message['binauralShadowCutoff'] as num?)?.toDouble() ?? 3500.0,
              );
              break;
            case SurroundMode.acousticStage:
              player.dsp.setSurroundStage(
                enabled: enabled,
                profile: (message['stageProfile'] as num?)?.toInt() ?? 0,
                mode: (message['stageMode'] as num?)?.toInt() ?? 0,
                width: (message['stageWidth'] as num?)?.toDouble() ??
                    (message['fieldWidth'] as num?)?.toDouble() ?? 1.2,
                depth: (message['stageDepth'] as num?)?.toDouble() ?? 0.5,
                cancellation: (message['stageCancellation'] as num?)?.toDouble() ?? 0.60,
                airPresence: (message['stageAirPresence'] as num?)?.toDouble() ?? 0.40,
                bassAnchorHz: (message['stageBassAnchorHz'] as num?)?.toDouble() ?? 60.0,
              );
              break;
            case SurroundMode.off:
              player.dsp.setSurround(
                enabled: false,
                mode: SurroundMode.off,
              );
              break;
          }
          break;
        case 'loadConvolverIr':
          try {
            final samples = WavParser.parse(message['path']);
            player.dsp.loadImpulseResponse(samples, 2);
          } catch (e) {
            initData.sendPort.send('[log]loadConvolverIr Error: $e');
          }
          break;
        case 'loadConvolverIrData':
          try {
            final bytes = message['bytes'] as Uint8List;
            final samples = WavParser.parseBytes(bytes);
            player.dsp.loadImpulseResponse(samples, 2);
          } catch (e) {
            initData.sendPort.send('[log]loadConvolverIrData Error: $e');
          }
          break;
        case 'clearConvolverIr':
          player.dsp.clearImpulseResponse();
          break;
        case 'setConvolverMix':
          player.dsp.setConvolverMix(
            wet: (message['wet'] as num?)?.toDouble() ?? 1.0,
            dry: (message['dry'] as num?)?.toDouble() ?? 0.0,
          );
          break;
        case 'setMasterLimiter':
          player.dsp.setMasterLimiter(
            enabled: message['enabled'] == true,
            ceilingDb: (message['ceilingDb'] as num?)?.toDouble() ?? -0.1,
            outputGainDb: (message['outputGainDb'] as num?)?.toDouble() ?? 0.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 60.0,
          );
          break;
        case 'setDynamicLoudnessEnabled':
          player.dsp.setDynamicLoudnessEnabled(message['enabled'] == true);
          break;
        case 'setDynamicLoudnessParams':
          player.dsp.setDynamicLoudnessParams(
            refLevelDb: (message['refLevelDb'] as num?)?.toDouble() ?? 0.0,
            maxBassBoostDb:
                (message['maxBassBoostDb'] as num?)?.toDouble() ?? 9.0,
            maxTrebleBoostDb:
                (message['maxTrebleBoostDb'] as num?)?.toDouble() ?? 4.5,
            bassFreqHz: (message['bassFreqHz'] as num?)?.toDouble() ?? 90.0,
            trebleFreqHz:
                (message['trebleFreqHz'] as num?)?.toDouble() ?? 9000.0,
          );
          break;
        case 'getDynamicLoudnessCurrentBoost':
          try {
            final boost = player.dsp.getDynamicLoudnessCurrentBoost();
            sendResponse(message, {
              'bassBoostDb': boost.bassBoostDb,
              'trebleBoostDb': boost.trebleBoostDb,
            });
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'loadAutoEqProfileFile':
          try {
            double preamp = 0.0;
            final count = player.loadAutoEqProfileFile(
              message['path'] as String,
              onPreampExtracted: (p) => preamp = p,
            );
            sendResponse(message, {'bandCount': count, 'preampDb': preamp});
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'loadAutoEqProfileString':
          try {
            double preamp = 0.0;
            final count = player.loadAutoEqProfileString(
              message['text'] as String,
              onPreampExtracted: (p) => preamp = p,
            );
            sendResponse(message, {'bandCount': count, 'preampDb': preamp});
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setNoiseGateEnabled':
          player.dsp.setNoiseGateEnabled(message['enabled'] == true);
          break;
        case 'setNoiseGateParams':
          player.dsp.setNoiseGateParams(
            openThreshDb:
                (message['openThreshDb'] as num?)?.toDouble() ?? -42.0,
            closeThreshDb:
                (message['closeThreshDb'] as num?)?.toDouble() ?? -48.0,
            holdMs: (message['holdMs'] as num?)?.toDouble() ?? 80.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 1.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 120.0,
            sidechainHpfHz:
                (message['sidechainHpfHz'] as num?)?.toDouble() ?? 80.0,
          );
          break;
        case 'getNoiseGateGainReductionDb':
          try {
            sendResponse(message, player.dsp.getNoiseGateGainReductionDb());
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setLevellerEnabled':
          player.dsp.setLevellerEnabled(message['enabled'] == true);
          break;
        case 'setLevellerParams':
          player.dsp.setLevellerParams(
            targetLufs: (message['targetLufs'] as num?)?.toDouble() ?? -16.0,
            maxRiseDbSec:
                (message['maxRiseDbSec'] as num?)?.toDouble() ?? 0.75,
            maxFallDbSec: (message['maxFallDbSec'] as num?)?.toDouble() ?? 1.5,
            maxBoostDb: (message['maxBoostDb'] as num?)?.toDouble() ?? 9.0,
            maxAttenuationDb:
                (message['maxAttenuationDb'] as num?)?.toDouble() ?? 12.0,
            silenceGateLufs:
                (message['silenceGateLufs'] as num?)?.toDouble() ?? -45.0,
          );
          break;
        case 'getLevellerCurrentGainDb':
          try {
            sendResponse(message, player.dsp.getLevellerCurrentGainDb());
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setDynamicEqEnabled':
          player.dsp.setDynamicEqEnabled(message['enabled'] == true);
          break;
        case 'setDynamicEqBand':
          final rawType = (message['filterType'] as num?)?.toInt() ?? 0;
          final fType =
              (rawType >= 0 && rawType < DynamicEqFilterType.values.length)
                  ? DynamicEqFilterType.values[rawType]
                  : DynamicEqFilterType.peak;
          final rawMode = (message['mode'] as num?)?.toInt() ?? 0;
          final fMode =
              (rawMode >= 0 && rawMode < DynamicEqMode.values.length)
                  ? DynamicEqMode.values[rawMode]
                  : DynamicEqMode.compress;
          player.dsp.setDynamicEqBand(
            bandIndex: (message['bandIndex'] as num?)?.toInt() ?? 0,
            filterType: fType,
            mode: fMode,
            freqHz: (message['freqHz'] as num?)?.toDouble() ?? 1000.0,
            q: (message['q'] as num?)?.toDouble() ?? 1.0,
            baseGainDb: (message['baseGainDb'] as num?)?.toDouble() ?? 0.0,
            thresholdDb: (message['thresholdDb'] as num?)?.toDouble() ?? -24.0,
            rangeDb: (message['rangeDb'] as num?)?.toDouble() ?? 6.0,
            ratio: (message['ratio'] as num?)?.toDouble() ?? 3.0,
            attackMs: (message['attackMs'] as num?)?.toDouble() ?? 2.0,
            releaseMs: (message['releaseMs'] as num?)?.toDouble() ?? 60.0,
            enabled: message['enabled'] == true,
          );
          break;
        case 'getDynamicEqBandGainOffsetDb':
          try {
            final bandIdx = (message['bandIndex'] as num?)?.toInt() ?? 0;
            sendResponse(
                message, player.dsp.getDynamicEqBandGainOffsetDb(bandIdx));
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setTapeDriftEnabled':
          player.dsp.setTapeDriftEnabled(message['enabled'] == true);
          break;
        case 'setTapeDriftParams':
          player.dsp.setTapeDriftParams(
            wowRateHz: (message['wowRateHz'] as num?)?.toDouble() ?? 0.8,
            wowDepthMs: (message['wowDepthMs'] as num?)?.toDouble() ?? 0.35,
            flutterRateHz:
                (message['flutterRateHz'] as num?)?.toDouble() ?? 12.0,
            flutterDepthMs:
                (message['flutterDepthMs'] as num?)?.toDouble() ?? 0.08,
            driftDepthMs: (message['driftDepthMs'] as num?)?.toDouble() ?? 0.10,
            stereoPhaseDeg:
                (message['stereoPhaseDeg'] as num?)?.toDouble() ?? 45.0,
            hfDampingHz:
                (message['hfDampingHz'] as num?)?.toDouble() ?? 18000.0,
          );
          break;
        case 'setTapeDriftPreset':
          final rawPreset = (message['preset'] as num?)?.toInt() ?? 0;
          final preset =
              (rawPreset >= 0 && rawPreset < TapeDriftPreset.values.length)
                  ? TapeDriftPreset.values[rawPreset]
                  : TapeDriftPreset.subtleHiFi;
          player.dsp.setTapeDriftPreset(preset);
          break;
        case 'getHardwareInfo':
          try {
            final info = player.getHardwareInfo();
            sendResponse(message, info);
          } catch (e) {
            sendResponse(message, null, e);
          }
          break;
        case 'setAbRepeat':
          player.setAbRepeat(
            enabled: message['enabled'] as bool,
            startSeconds: (message['startSeconds'] as num).toDouble(),
            endSeconds: (message['endSeconds'] as num).toDouble(),
          );
          break;
        case 'dispose':
          player.dispose();
          Isolate.current.kill();
          break;
      }
    }
  });
}
