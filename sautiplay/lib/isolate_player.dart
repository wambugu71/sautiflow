import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // For RootIsolateToken
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/desktop_system_audio.dart';
import 'package:sautiplay/services/wav_parser.dart';
import 'package:sautiplay/services/vdc_parser.dart';
import 'package:sautiplay/services/autoeq_parser.dart';
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

  final List<Map<String, dynamic>> _pendingCommands = [];
  bool _networkStreamingSupported = false;

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  Stream<Float32List> get analyzerStream => _analyzerController.stream;

  MiniAudioSystemAudioController? _systemAudio;
  DesktopSystemAudioController? _desktopAudio;

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
      if (Platform.isAndroid || Platform.isIOS) {
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

        _statusController.stream.listen((status) {
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
        _statusController.add(message);
      } else if (message is Float32List) {
        _analyzerController.add(message);
      } else if (message is Map) {
        if (message['type'] == 'capabilities') {
          final supported = message['networkStreamingSupported'] == true;
          _networkStreamingSupported = supported;
          _logController.add(
            '[capabilities] network streaming: ${supported ? 'enabled' : 'disabled'}',
          );
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

  void dispose() {
    _seekDebounceTimer?.cancel();
    _send({'cmd': 'dispose'});
    _isolate?.kill();
    _systemAudio?.disable();
    _desktopAudio?.dispose();
    _statusController.close();
    _logController.close();
    _analyzerController.close();
    _receivePort.close();
  }

  // --- Commands ---

  void play() {
    if (DlnaService.instance.activeRenderer != null) {
      DlnaService.instance.play();
    }
    _send({'cmd': 'play'});
  }

  void pause() {
    if (DlnaService.instance.activeRenderer != null) {
      DlnaService.instance.pause();
    }
    _send({'cmd': 'pause'});
  }

  void stop() {
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

  // Debounce timer for seek: collapses rapid seek calls (e.g. from system
  // media controls) into a single command before hitting the isolate.
  // The slider in NowPlayingScreen already uses onChangeEnd so this is a
  // secondary safety net for programmatic callers.
  Timer? _seekDebounceTimer;

  void seekTo(Duration position, {int? index}) {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 80), () {
      _send({
        'cmd': 'seekTo',
        'position': position.inMilliseconds,
        'index': index
      });
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
  void setReplayGain(double gainDb) => _send({'cmd': 'setReplayGain', 'gainDb': gainDb});
  void setPan(double pan) => _send({'cmd': 'setPan', 'pan': pan});
  void setPitch(double pitch) => _send({'cmd': 'setPitch', 'pitch': pitch});

  void setSpatializationEnabled(bool enabled) =>
      _send({'cmd': 'setSpatializationEnabled', 'enabled': enabled});
  void setPosition({required double x, required double y, required double z}) {
    _send({'cmd': 'setPosition', 'x': x, 'y': y, 'z': z});
  }
  void setDirection({required double x, required double y, required double z}) =>
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

  void setAutoSampleRateMatchEnabled(bool enabled) {
    _send({'cmd': 'setAutoSampleRateMatchEnabled', 'enabled': enabled});
  }

  void setAutoBitPerfectEnabled(bool enabled) => setAutoSampleRateMatchEnabled(enabled);

  // --- Limiter & Clipping Detection ---

  int _clippedSamplesCount = 0;

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

  // --- ViPER DSP ---
  void setViperEnabled(bool enabled) => _send({'cmd': 'setViperEnabled', 'enabled': enabled});
  void setViperSamplingRate(int sampleRate) => _send({'cmd': 'setViperSamplingRate', 'sampleRate': sampleRate});
  void resetViperAll() => _send({'cmd': 'resetViperAll'});
  void setViperMasterLimiter({required double threshold, required double outputVolume, required double channelPan}) => _send({'cmd': 'setViperMasterLimiter', 'threshold': threshold, 'outputVolume': outputVolume, 'channelPan': channelPan});
  void setViperPlaybackGain({required bool enable, required double strength, required double maxGain, required double outputThreshold}) => _send({'cmd': 'setViperPlaybackGain', 'enable': enable, 'strength': strength, 'maxGain': maxGain, 'outputThreshold': outputThreshold});
  void setViperLufs({required bool enable, required double target, required double maxGainDb, int speed = 1}) => _send({'cmd': 'setViperLufs', 'enable': enable, 'target': target, 'maxGainDb': maxGainDb, 'speed': speed});
  void setViperFetCompressor({required bool enable, required double threshold, required double ratio, required double knee, required bool kneeAuto, required double gain, required bool gainAuto, required double attack, required bool attackAuto, required double release, required bool releaseAuto, required double kneeMulti, required double maxAttack, required double maxRelease, required double crest, required double adapt, required bool noClip}) => _send({'cmd': 'setViperFetCompressor', 'enable': enable, 'threshold': threshold, 'ratio': ratio, 'knee': knee, 'kneeAuto': kneeAuto, 'gain': gain, 'gainAuto': gainAuto, 'attack': attack, 'attackAuto': attackAuto, 'release': release, 'releaseAuto': releaseAuto, 'kneeMulti': kneeMulti, 'maxAttack': maxAttack, 'maxRelease': maxRelease, 'crest': crest, 'adapt': adapt, 'noClip': noClip});
  void setViperBass({required bool enable, required int mode, required int frequencyHz, required double gain, required bool antiPop}) => _send({'cmd': 'setViperBass', 'enable': enable, 'mode': mode, 'frequencyHz': frequencyHz, 'gain': gain, 'antiPop': antiPop});
  void setViperBassMono({required bool enable, required int mode, required int frequencyHz, required double gain, required bool antiPop}) => _send({'cmd': 'setViperBassMono', 'enable': enable, 'mode': mode, 'frequencyHz': frequencyHz, 'gain': gain, 'antiPop': antiPop});
  void setViperPsychoacousticBass({required bool enable, required int cutoffHz, required int intensity, required int harmonicOrder, required int originalLevel}) => _send({'cmd': 'setViperPsychoacousticBass', 'enable': enable, 'cutoffHz': cutoffHz, 'intensity': intensity, 'harmonicOrder': harmonicOrder, 'originalLevel': originalLevel});
  void setViperSpectrumExtension({required bool enable, required int strength, required double exciter}) => _send({'cmd': 'setViperSpectrumExtension', 'enable': enable, 'strength': strength, 'exciter': exciter});
  void setViperConvolver({required bool enable, required double crossChannel}) => _send({'cmd': 'setViperConvolver', 'enable': enable, 'crossChannel': crossChannel});
  void loadViperConvolver(String path) => _send({'cmd': 'loadViperConvolver', 'path': path});
  void setViperDdc(bool enable) => _send({'cmd': 'setViperDdc', 'enable': enable});
  void loadViperDdc(String path) => _send({'cmd': 'loadViperDdc', 'path': path});
  void setViperFieldSurround({required bool enable, required double widening, required double midImage, required int depth}) => _send({'cmd': 'setViperFieldSurround', 'enable': enable, 'widening': widening, 'midImage': midImage, 'depth': depth});
  void setViperDiffSurround({required bool enable, required double delay, required bool reverse, required double wetDryMix, required double lpCutoffHz}) => _send({'cmd': 'setViperDiffSurround', 'enable': enable, 'delay': delay, 'reverse': reverse, 'wetDryMix': wetDryMix, 'lpCutoffHz': lpCutoffHz});
  void setViperStereoImager({required bool enable, required double lowWidth, required double midWidth, required double highWidth, required double lowCrossoverHz, required double highCrossoverHz}) => _send({'cmd': 'setViperStereoImager', 'enable': enable, 'lowWidth': lowWidth, 'midWidth': midWidth, 'highWidth': highWidth, 'lowCrossoverHz': lowCrossoverHz, 'highCrossoverHz': highCrossoverHz});
  void setViperHeadphoneSurround({required bool enable, required int quality}) => _send({'cmd': 'setViperHeadphoneSurround', 'enable': enable, 'quality': quality});
  void setViperReverb({required bool enable, required double roomSize, required double width, required double damp, required double wet, required double dry}) => _send({'cmd': 'setViperReverb', 'enable': enable, 'roomSize': roomSize, 'width': width, 'damp': damp, 'wet': wet, 'dry': dry});
  void setViperDynamicSystem({required bool enable, required int xCoeffLow, required int xCoeffHigh, required int yCoeffLow, required int yCoeffHigh, required double sideGainLow, required double sideGainHigh, required double strength}) => _send({'cmd': 'setViperDynamicSystem', 'enable': enable, 'xCoeffLow': xCoeffLow, 'xCoeffHigh': xCoeffHigh, 'yCoeffLow': yCoeffLow, 'yCoeffHigh': yCoeffHigh, 'sideGainLow': sideGainLow, 'sideGainHigh': sideGainHigh, 'strength': strength});
  void setViperClarity({required bool enable, required int mode, required double gain}) => _send({'cmd': 'setViperClarity', 'enable': enable, 'mode': mode, 'gain': gain});
  void setViperCure({required bool enable, required int preset}) => _send({'cmd': 'setViperCure', 'enable': enable, 'preset': preset});
  void setViperTubeSimulator(bool enable) => _send({'cmd': 'setViperTubeSimulator', 'enable': enable});
  void setViperAnalogX({required bool enable, required int mode}) => _send({'cmd': 'setViperAnalogX', 'enable': enable, 'mode': mode});
  void setViperSpeakerCorrection(bool enable) => _send({'cmd': 'setViperSpeakerCorrection', 'enable': enable});
  void setViperMultibandCompressor({required bool enable, required List<double> crossoverFreqs, required List<Map<String, dynamic>> bands}) => _send({'cmd': 'setViperMultibandCompressor', 'enable': enable, 'crossoverFreqs': crossoverFreqs, 'bands': bands});
  void setViperDynamicEq({required bool enable, required List<Map<String, dynamic>> bands}) => _send({'cmd': 'setViperDynamicEq', 'enable': enable, 'bands': bands});
  void setViperEqualizer({required bool enable, required List<double> bandLevels}) => _send({'cmd': 'setViperEqualizer', 'enable': enable, 'bandLevels': bandLevels});
  void loadViperAutoEqText(String path) => _send({'cmd': 'loadViperAutoEqText', 'path': path});
  void setViperAdaptiveLoudness({required bool enable, required int mode, required double strength, required double attenuationDb}) => _send({'cmd': 'setViperAdaptiveLoudness', 'enable': enable, 'mode': mode, 'strength': strength, 'attenuationDb': attenuationDb});
  void setViperOversampling(int factor) => _send({'cmd': 'setViperOversampling', 'factor': factor});

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

  void configureAnalyzer({int frameSize = 512}) =>
      _send({'cmd': 'configureAnalyzer', 'frameSize': frameSize});

  void setAnalyzerEnabled(bool enabled) =>
      _send({'cmd': 'setAnalyzerEnabled', 'enabled': enabled});

  void setOutputFormat(AudioFormat format) =>
      _send({'cmd': 'setOutputFormat', 'format': format.index});
  void setOutputSampleRate(int rate) =>
      _send({'cmd': 'setOutputSampleRate', 'rate': rate});
  void setOutputChannels(int channels) =>
      _send({'cmd': 'setOutputChannels', 'channels': channels});

  void setPhaseInversion({required bool invertLeft, required bool invertRight}) =>
      _send({
        'cmd': 'setPhaseInversion',
        'invertLeft': invertLeft,
        'invertRight': invertRight,
      });

  void setLrSwap(bool enabled) =>
      _send({'cmd': 'setLrSwap', 'enabled': enabled});

  void setChannelGains({required double leftLinear, required double rightLinear}) =>
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
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getExclusiveMode',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return response as bool;
  }

  Future<double> getDeviceLatencyMs() async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getDeviceLatencyMs',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return response as double;
  }

  Future<PipelineAudioState> getPipelineState() async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getPipelineState',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return response as PipelineAudioState;
  }

  Future<AEHardwareInfo> getHardwareInfo() async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getHardwareInfo',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return response as AEHardwareInfo;
  }

  Future<Map<String, dynamic>> getAudioProperties() async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getAudioProperties',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> inspectFile(String path) async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'inspectFile',
      'path': path,
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      return null;
    }
    return response as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> getEngineTelemetry() async {
    final responsePort = ReceivePort();
    _send({
      'cmd': 'getEngineTelemetry',
      'replyTo': responsePort.sendPort,
    });
    final response = await responsePort.first;
    responsePort.close();
    if (response is Map && response.containsKey('error')) {
      throw Exception(response['error']);
    }
    return (response as Map).cast<String, dynamic>();
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
      final systemAudio = _systemAudio as dynamic;
      if (artUri != null && artUri.isNotEmpty) {
        final parsedUri = Uri.tryParse(artUri);
        try {
          await Function.apply(
            systemAudio.updateNowPlaying,
            [],
            {
              #id: id,
              #title: title,
              #artist: artist,
              #duration: duration,
              #album: album,
              #artUri: parsedUri,
            },
          );
          _logController.add('[now-playing] artwork path: artUri');
          return;
        } catch (_) {
          try {
            await Function.apply(
              systemAudio.updateNowPlaying,
              [],
              {
                #id: id,
                #title: title,
                #artist: artist,
                #duration: duration,
                #album: album,
                #artworkUri: parsedUri,
              },
            );
            _logController.add('[now-playing] artwork path: artworkUri');
            return;
          } catch (e) {
            _logController.add(
                '[now-playing] artwork unsupported by API; fallback without artwork. Error: $e');
            // fall back below
          }
        }
      }

      await _systemAudio!.updateNowPlaying(
        id: id,
        title: title,
        artist: artist,
        duration: duration,
        album: album,
      );
      if (artUri == null || artUri.isEmpty) {
        _logController
            .add('[now-playing] no artwork available for current track');
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

  player.logStream.listen((log) {
    initData.sendPort.send('[log]$log');
  });

  player.analyzerStream.listen((samples) {
    initData.sendPort.send(samples);
  });

  List<AudioSource> isolateSources = [];

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
        case 'setPitch':
          player.setPitch(message['pitch']);
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
          final algoIdx = (message['algorithm'] as int? ?? 0).clamp(0, CrossfeedAlgorithm.values.length - 1);
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
            player.setEngineResampleAlgorithm(
                ResampleAlgorithm.values[algoIdx]);
          } else {
            player.setEngineResampleAlgorithm(ResampleAlgorithm.miniaudioLinear);
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
          player.configureAnalyzer(
            frameSize: (message['frameSize'] as int?) ?? 512,
          );
          break;
        case 'setSpeakerProtectionParams':
          {
            final bool enabled = message['enabled'] == true;
            final double subHz = (message['subsonicCutoffHz'] as num?)?.toDouble() ?? 25.0;
            final double ultraHz = (message['ultrasonicCutoffHz'] as num?)?.toDouble() ?? 20000.0;
            final double threshold = (message['limiterThreshold'] as num?)?.toDouble() ?? 0.95;
            final double attenDb = (message['safetyAttenuationDb'] as num?)?.toDouble() ?? -1.0;

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
              double outputVol = math.pow(10.0, attenDb / 20.0).toDouble().clamp(0.1, 1.0);
              player.viper.setMasterLimiter(
                threshold: threshold.clamp(0.5, 1.0),
                outputVolume: outputVol,
                channelPan: 0.0,
              );
              player.setLimiterEnabled(true);
              player.setLimiterParams(threshold: threshold);
            } else {
              player.setHighpass(enabled: false, cutoffHz: 20.0);
              player.setLowpass(enabled: false, cutoffHz: 20000.0);
              player.viper.setMasterLimiter(
                threshold: 1.0,
                outputVolume: 1.0,
                channelPan: 0.0,
              );
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
        case 'set64BitProcessingEnabled':
          player.set64BitProcessingEnabled(message['enabled'] == true);
          break;
        case 'setAutoSampleRateMatchEnabled':
        case 'setAutoBitPerfectEnabled':
          player.setAutoSampleRateMatchEnabled(message['enabled'] == true);
          break;
        case 'getExclusiveMode':
          final SendPort replyTo1 = message['replyTo'];
          try {
            replyTo1.send(player.getExclusiveMode());
          } catch (e) {
            replyTo1.send({'error': e.toString()});
          }
          break;
        case 'getPipelineState':
          final SendPort replyTo = message['replyTo'];
          try {
            replyTo.send(player.pipelineState);
          } catch (e) {
            replyTo.send({'error': e.toString()});
          }
          break;
        case 'getDeviceLatencyMs':
          final SendPort replyTo2 = message['replyTo'];
          try {
            replyTo2.send(player.deviceLatencyMs);
          } catch (e) {
            replyTo2.send({'error': e.toString()});
          }
          break;
        case 'getAudioProperties':
          final SendPort replyTo = message['replyTo'];
          try {
            replyTo.send({
              'channels': player.getOutputChannels(),
              'format': player.getOutputFormat().name,
              'sampleRate': player.getOutputSampleRate(),
            });
          } catch (e) {
            replyTo.send({'error': e.toString()});
          }
          break;
        case 'getEngineTelemetry':
          final SendPort replyTo = message['replyTo'];
          try {
            final hw = player.hardwareInfo;
            final ps = player.pipelineState;
            final samples = player.engineLatencySamples;
            final ms = player.engineLatencyMs;
            final devMs = player.deviceLatencyMs;
            final clipped = player.getClippedSamplesCount();
            final resampleAlgo = player.getEngineResampleAlgorithm().name;
            final crossfeedParams = player.getCrossfeedParams();
            final viperOn = player.viperEnabled;
            int inputRate = ps.inputSampleRate;
            int inputChannels = ps.inputChannels;
            int inputBitDepth = 16;
            final status = player.status;
            if (status.currentIndex >= 0 && status.currentIndex < isolateSources.length) {
              final src = isolateSources[status.currentIndex];
              if (!src.isNetwork) {
                final path = src.uri.toFilePath();
                final info = player.inspectFile(path);
                if (info != null && info.sampleRate > 0) {
                  inputRate = info.sampleRate;
                  if (info.channels > 0) inputChannels = info.channels;
                  if (info.bitDepth > 0) inputBitDepth = info.bitDepth;
                }
              }
            }

            replyTo.send({
              'hardware': hw.toJson(),
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
              'crossfeedAlgo': crossfeedParams.algorithm.name,
              'crossfeedMix': crossfeedParams.mix,
              'crossfeedDelayMs': crossfeedParams.delayMs,
              'crossfeedCutoffHz': crossfeedParams.cutoffHz,
              'crossfeedComp': crossfeedParams.outputCompensation,
              'viperEnabled': viperOn,
            });
          } catch (e) {
            replyTo.send({'error': e.toString()});
          }
          break;
        case 'inspectFile':
          final SendPort replyTo = message['replyTo'];
          try {
            final path = message['path'] as String;
            final info = player.inspectFile(path);
            replyTo.send(info?.toJson());
          } catch (e) {
            replyTo.send({'error': e.toString()});
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
          player.setNextReplayGain((message['gainDb'] as num?)?.toDouble() ?? 0.0);
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
        case 'setViperEnabled': player.viper.setEnabled(message['enabled']); break;
        case 'setViperSamplingRate': player.viper.setSamplingRate(message['sampleRate']); break;
        case 'resetViperAll': player.viper.reset(); break;
        case 'setViperMasterLimiter': player.viper.setMasterLimiter(threshold: message['threshold'], outputVolume: message['outputVolume'], channelPan: message['channelPan']); break;
        case 'setViperPlaybackGain': player.viper.setPlaybackGain(enable: message['enable'], strength: message['strength'], maxGain: message['maxGain'], outputThreshold: message['outputThreshold']); break;
        case 'setViperLufs': player.viper.setLufs(enable: message['enable'], target: message['target'], maxGainDb: message['maxGainDb'], speed: ViperLufsSpeed.values[message['speed']]); break;
        case 'setViperFetCompressor': player.viper.setFetCompressor(enable: message['enable'], threshold: message['threshold'] ?? 0.0, ratio: message['ratio'] ?? 2.0, knee: message['knee'] ?? 0.0, kneeAuto: message['kneeAuto'] ?? false, gain: message['gain'] ?? 0.0, gainAuto: message['gainAuto'] ?? false, attack: message['attack'] ?? 10.0, attackAuto: message['attackAuto'] ?? false, release: message['release'] ?? 100.0, releaseAuto: message['releaseAuto'] ?? false, kneeMulti: message['kneeMulti'] ?? 0.0, maxAttack: message['maxAttack'] ?? 100.0, maxRelease: message['maxRelease'] ?? 1000.0, crest: message['crest'] ?? 0.0, adapt: message['adapt'] ?? 0.0, noClip: message['noClip'] ?? false); break;
        case 'setViperBass': player.viper.setBass(enable: message['enable'], mode: ViperBassMode.values[message['mode']], frequencyHz: message['frequencyHz'], gain: message['gain'], antiPop: message['antiPop']); break;
        case 'setViperBassMono': player.viper.setBassMono(enable: message['enable'], mode: ViperBassMode.values[message['mode']], frequencyHz: message['frequencyHz'], gain: message['gain'], antiPop: message['antiPop']); break;
        case 'setViperPsychoacousticBass': player.viper.setPsychoacousticBass(enable: message['enable'], cutoffHz: message['cutoffHz'], intensity: message['intensity'], harmonicOrder: message['harmonicOrder'], originalLevel: message['originalLevel']); break;
        case 'setViperSpectrumExtension': player.viper.setSpectrumExtension(enable: message['enable'], strength: message['strength'], exciter: message['exciter']); break;
        case 'setViperConvolver': player.viper.setConvolver(enable: message['enable'], crossChannel: message['crossChannel']); break;
        case 'loadViperConvolver': 
          try {
            final samples = WavParser.parse(message['path']);
            player.viper.loadConvolverKernel(samples, 2, 1); // Using 2 channels (stereo) and kernelId 1
          } catch(e) {
            initData.sendPort.send('[log]loadViperConvolver Error: $e');
          }
          break;
        case 'setViperDdc': player.viper.setDdc(message['enable']); break;
        case 'loadViperDdc':
          try {
            final ddcData = VdcParser.parse(message['path']);
            player.viper.loadDdcCoefficients(
              sections44100: ddcData['sections44100']!,
              sections48000: ddcData['sections48000']!,
              sectionCount: ddcData['sectionCount']![0].toInt()
            );
          } catch(e) {
            initData.sendPort.send('[log]loadViperDdc Error: $e');
          }
          break;
        case 'setViperFieldSurround': player.viper.setFieldSurround(enable: message['enable'], widening: message['widening'], midImage: message['midImage'], depth: message['depth']); break;
        case 'setViperDiffSurround': player.viper.setDiffSurround(enable: message['enable'], delay: message['delay'], reverse: message['reverse'], wetDryMix: message['wetDryMix'], lpCutoffHz: message['lpCutoffHz']); break;
        case 'setViperStereoImager': player.viper.setStereoImager(enable: message['enable'], lowWidth: message['lowWidth'], midWidth: message['midWidth'], highWidth: message['highWidth'], lowCrossoverHz: message['lowCrossoverHz'], highCrossoverHz: message['highCrossoverHz']); break;
        case 'setViperHeadphoneSurround': player.viper.setHeadphoneSurround(enable: message['enable'], quality: message['quality']); break;
        case 'setViperReverb': player.viper.setReverb(enable: message['enable'], roomSize: message['roomSize'], width: message['width'], damp: message['damp'], wet: message['wet'], dry: message['dry']); break;
        case 'setViperDynamicSystem': player.viper.setDynamicSystem(enable: message['enable'], xCoeffLow: message['xCoeffLow'], xCoeffHigh: message['xCoeffHigh'], yCoeffLow: message['yCoeffLow'], yCoeffHigh: message['yCoeffHigh'], sideGainLow: message['sideGainLow'], sideGainHigh: message['sideGainHigh'], strength: message['strength']); break;
        case 'setViperClarity': player.viper.setClarity(enable: message['enable'], mode: ViperClarityMode.values[message['mode']], gain: message['gain']); break;
        case 'setViperCure': player.viper.setCure(enable: message['enable'], preset: ViperCureCrossfeedPreset.values[message['preset']]); break;
        case 'setViperTubeSimulator': player.viper.setTubeSimulator(message['enable']); break;
        case 'setViperAnalogX': player.viper.setAnalogX(enable: message['enable'], mode: ViperAnalogXMode.values[message['mode']]); break;
        case 'setViperSpeakerCorrection': player.viper.setSpeakerCorrection(message['enable']); break;
        case 'setViperMultibandCompressor':
          final bands = (message['bands'] as List).map((m) => ViperMultibandCompressorBand(
            enable: m['enable'] ?? false,
            threshold: m['threshold'] ?? 0.0,
            ratio: m['ratio'] ?? 0.0,
            knee: m['knee'] ?? 0.0,
            kneeAuto: m['kneeAuto'] ?? false,
            gain: m['gain'] ?? 0.0,
            gainAuto: m['gainAuto'] ?? false,
            attack: m['attack'] ?? 0.0,
            attackAuto: m['attackAuto'] ?? false,
            release: m['release'] ?? 0.0,
            releaseAuto: m['releaseAuto'] ?? false,
            kneeMulti: m['kneeMulti'] ?? 0.0,
            maxAttack: m['maxAttack'] ?? 0.0,
            maxRelease: m['maxRelease'] ?? 0.0,
            crest: m['crest'] ?? 0.0,
            adapt: m['adapt'] ?? 0.0,
            noClip: m['noClip'] ?? false,
          )).toList();
          player.viper.setMultibandCompressor(
            enable: message['enable'],
            crossoverFreqs: (message['crossoverFreqs'] as List).cast<double>(),
            bands: bands,
          );
          break;
        case 'setViperDynamicEq':
          final bands = (message['bands'] as List).map((m) => ViperDynamicEqBand(
            frequencyHz: m['frequencyHz'] ?? 1000.0,
            q: m['q'] ?? 1.0,
            gainDb: m['gainDb'] ?? 0.0,
            thresholdDb: m['thresholdDb'] ?? 0.0,
            attackMs: m['attackMs'] ?? 20.0,
            releaseMs: m['releaseMs'] ?? 100.0,
            filterType: m['filterType'] ?? 0,
          )).toList();
          player.viper.setDynamicEq(enable: message['enable'], bands: bands);
          break;
        case 'setViperEqualizer': player.viper.setEqualizer(enable: message['enable'], bandLevels: (message['bandLevels'] as List).cast<double>()); break;
        case 'loadViperAutoEqText':
          try {
            final result = AutoEqParser.parseFile(message['path']);
            if (result.preampGainDb < 0) {
              double linearVol = math.pow(10.0, result.preampGainDb / 20.0).toDouble().clamp(0.1, 1.0);
              player.viper.setMasterLimiter(outputVolume: linearVol);
            }
            player.viper.setEqualizer(enable: true, bandLevels: result.bandLevels31);
          } catch(e) {
            initData.sendPort.send('[log]loadViperAutoEqText Error: $e');
          }
          break;
        case 'setViperAdaptiveLoudness': player.viper.setAdaptiveLoudness(enable: message['enable'], mode: ViperAlcMode.values[message['mode']], strength: message['strength'], attenuationDb: message['attenuationDb']); break;
        case 'setViperOversampling':
          final factor = (message['factor'] as int?) ?? 1;
          ViperOversamplingFactor mode = ViperOversamplingFactor.off;
          if (factor == 2) mode = ViperOversamplingFactor.x2;
          if (factor == 4) mode = ViperOversamplingFactor.x4;
          player.viper.setOversampling(mode);
          break;
        case 'getHardwareInfo':
          final replyTo = message['replyTo'] as SendPort?;
          if (replyTo != null) {
            try {
              final info = player.getHardwareInfo();
              replyTo.send(info);
            } catch (e) {
              replyTo.send({'error': e.toString()});
            }
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
