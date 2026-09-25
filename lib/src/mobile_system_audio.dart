import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../audio_engine_ffi.dart';

class MiniAudioSystemAudioConfig {
  const MiniAudioSystemAudioConfig({
    this.enableDucking = true,
    this.duckGain = 0.25,
    this.normalGain = 1.0,
    this.pauseWhenInterrupted = true,
    this.resumeAfterInterruption = false,
    this.androidNotificationChannelId = 'com.wambugu.miniaudiodart.playback',
    this.androidNotificationChannelName = 'Audio Playback',
    this.androidNotificationOngoing = true,
    this.androidStopForegroundOnPause = true,
    this.androidNotificationIcon = 'drawable/ic_notification',
  });

  final bool enableDucking;
  final double duckGain;
  final double normalGain;
  final bool pauseWhenInterrupted;
  final bool resumeAfterInterruption;
  final String androidNotificationChannelId;
  final String androidNotificationChannelName;
  final bool androidNotificationOngoing;
  final bool androidStopForegroundOnPause;
  final String androidNotificationIcon;
}

class MiniAudioSystemAudioController {
  MiniAudioSystemAudioController({
    required Stream<PlayerStatus> statusStream,
    Stream<StreamTelemetry>? telemetryStream,
    required FutureOr<void> Function() onPlay,
    required FutureOr<void> Function() onPause,
    required FutureOr<void> Function() onStop,
    required FutureOr<void> Function() onNext,
    required FutureOr<void> Function() onPrevious,
    required FutureOr<void> Function(Duration position) onSeek,
    required void Function(double gain) onSetGain,
    double Function()? onGetGain,
    FutureOr<void> Function()? onToggleFavorite,
  })  : _statusStream = statusStream,
        _telemetryStream = telemetryStream,
        _onPlay = onPlay,
        _onPause = onPause,
        _onStop = onStop,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onSeek = onSeek,
        _onSetGain = onSetGain,
        _onGetGain = onGetGain,
        _onToggleFavorite = onToggleFavorite;

  final Stream<PlayerStatus> _statusStream;
  final Stream<StreamTelemetry>? _telemetryStream;
  final FutureOr<void> Function() _onPlay;
  final FutureOr<void> Function() _onPause;
  final FutureOr<void> Function() _onStop;
  final FutureOr<void> Function() _onNext;
  final FutureOr<void> Function() _onPrevious;
  final FutureOr<void> Function(Duration position) _onSeek;
  final void Function(double gain) _onSetGain;
  final double Function()? _onGetGain;
  final FutureOr<void> Function()? _onToggleFavorite;

  AudioHandler? _handler;
  _MiniAudioHandler? _typedHandler;
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<StreamTelemetry>? _telemetrySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  MiniAudioSystemAudioConfig? _config;
  bool _isDucked = false;
  double _preDuckGain = 1.0;
  StreamTelemetry? _latestTelemetry;
  bool _audioSessionActive = false;

  bool get isSupported => Platform.isAndroid || Platform.isIOS;
  bool get isEnabled => _config != null;

  Future<bool> enable({
    MiniAudioSystemAudioConfig config = const MiniAudioSystemAudioConfig(),
  }) async {
    if (!isSupported) return false;

    try {
      _config = config;

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      if (_handler == null) {
        final handler = await AudioService.init(
          builder: () => _MiniAudioHandler(
            onPlay: () async {
              await session.setActive(true);
              await _onPlay();
            },
            onPause: () async {
              await _onPause();
              await session.setActive(false);
            },
            onStop: () async {
              await _onStop();
              await session.setActive(false);
            },
            onNext: _onNext,
            onPrevious: _onPrevious,
            onSeek: _onSeek,
            onToggleFavorite: _onToggleFavorite,
          ),
          config: AudioServiceConfig(
            androidNotificationChannelId: config.androidNotificationChannelId,
            androidNotificationChannelName:
                config.androidNotificationChannelName,
            androidNotificationOngoing: config.androidNotificationOngoing,
            androidStopForegroundOnPause: config.androidStopForegroundOnPause,
            androidNotificationIcon: config.androidNotificationIcon,
          ),
        );
        _handler = handler;
        _typedHandler = handler;
      }

      _telemetrySub?.cancel();
      if (_telemetryStream != null) {
        _telemetrySub = _telemetryStream.listen((tel) {
          _latestTelemetry = tel;
        });
      }

      _statusSub?.cancel();
      _statusSub = _statusStream.listen((status) {
        _typedHandler?.updateFromPlayerStatus(status, telemetry: _latestTelemetry);

        final shouldBeActive = status.isPlaying;
        if (shouldBeActive != _audioSessionActive) {
          _audioSessionActive = shouldBeActive;
          unawaited(session.setActive(shouldBeActive));
        }
      });

      Timer? duckRampTimer;

      void rampGain({required double targetGain, int durationMs = 80}) {
        duckRampTimer?.cancel();
        final startGain = _onGetGain?.call() ?? targetGain;
        final startTime = DateTime.now().millisecondsSinceEpoch;
        final stepInterval = 10;

        duckRampTimer =
            Timer.periodic(Duration(milliseconds: stepInterval), (timer) {
          final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
          final progress = (elapsed / durationMs).clamp(0.0, 1.0);
          final smoothed = 0.5 * (1.0 - math.cos(progress * math.pi));
          final current = startGain + (targetGain - startGain) * smoothed;
          _onSetGain(current);

          if (progress >= 1.0) {
            timer.cancel();
            duckRampTimer = null;
            _onSetGain(targetGain);
          }
        });
      }

      _interruptionSub?.cancel();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        final c = _config;
        if (c == null) return;

        if (event.begin) {
          if (event.type == AudioInterruptionType.duck && c.enableDucking) {
            _preDuckGain = _onGetGain?.call() ?? 1.0;
            rampGain(targetGain: c.duckGain * _preDuckGain, durationMs: 80);
            _isDucked = true;
            return;
          }

          if (c.pauseWhenInterrupted) {
            _onPause();
          }
          return;
        }

        if (_isDucked) {
          rampGain(targetGain: _preDuckGain, durationMs: 80);
          _isDucked = false;
        }

        if (c.resumeAfterInterruption) {
          _onPlay();
        }
      });

      _becomingNoisySub?.cancel();
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        _onPause();
      });

      return true;
    } catch (e, stack) {
      // ignore: avoid_print
      print('[system-audio] Error enabling: $e\n$stack');
      _config = null;
      return false;
    }
  }

  Future<void> disable() async {
    _statusSub?.cancel();
    _statusSub = null;
    _interruptionSub?.cancel();
    _interruptionSub = null;
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;

    final c = _config;
    _config = null;

    if (_isDucked && c != null) {
      _onSetGain(c.normalGain);
      _isDucked = false;
    }

    if (isSupported) {
      final session = await AudioSession.instance;
      await session.setActive(false);
      _audioSessionActive = false;
    }
  }

  void setFavorite(bool isFavorite) {
    _typedHandler?.setFavorite(isFavorite);
  }

  Future<void> updateNowPlaying({
    required String title,
    String? artist,
    String? album,
    String? id,
    Duration? duration,
    Uri? artUri,
    bool? isFavorite,
  }) async {
    final h = _typedHandler;
    if (h == null) return;

    if (isFavorite != null) {
      h.setFavorite(isFavorite);
    }

    h.mediaItem.add(
      MediaItem(
        id: id ?? 'miniaudiodart-current',
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: artUri,
      ),
    );
  }
}

class _MiniAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  _MiniAudioHandler({
    required FutureOr<void> Function() onPlay,
    required FutureOr<void> Function() onPause,
    required FutureOr<void> Function() onStop,
    required FutureOr<void> Function() onNext,
    required FutureOr<void> Function() onPrevious,
    required FutureOr<void> Function(Duration position) onSeek,
    FutureOr<void> Function()? onToggleFavorite,
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onStop = onStop,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onSeek = onSeek,
        _onToggleFavorite = onToggleFavorite {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.pause,
          MediaControl.skipToNext,
          MediaControl.favoriteBorder,
          MediaControl.stop,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: [0, 1, 3],
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
  }

  final FutureOr<void> Function()? _onToggleFavorite;
  bool _isFavorite = false;
  PlayerStatus? _lastStatus;
  StreamTelemetry? _lastTelemetry;

  void setFavorite(bool isFavorite) {
    if (_isFavorite == isFavorite) return;
    _isFavorite = isFavorite;
    if (_lastStatus != null) {
      updateFromPlayerStatus(_lastStatus!, telemetry: _lastTelemetry);
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'favorite' || name == 'toggleFavorite') {
      await _onToggleFavorite?.call();
      return null;
    }
    return super.customAction(name, extras);
  }

  final FutureOr<void> Function() _onPlay;
  final FutureOr<void> Function() _onPause;
  final FutureOr<void> Function() _onStop;
  final FutureOr<void> Function() _onNext;
  final FutureOr<void> Function() _onPrevious;
  final FutureOr<void> Function(Duration position) _onSeek;

  @override
  Future<void> play() async {
    await _onPlay();
  }

  @override
  Future<void> pause() async {
    await _onPause();
  }

  @override
  Future<void> stop() async {
    await _onStop();
  }

  @override
  Future<void> skipToNext() async {
    await _onNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _onPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    await _onSeek(position);
  }

  void updateFromPlayerStatus(PlayerStatus status, {StreamTelemetry? telemetry}) {
    _lastStatus = status;
    _lastTelemetry = telemetry;
    final currentPositionMs = (status.positionSeconds * 1000).round();
    final bufferAheadMs = (telemetry != null && telemetry.bufferedDuration > Duration.zero)
        ? telemetry.bufferedDuration.inMilliseconds
        : 0;
    final bufferedMs = currentPositionMs + bufferAheadMs;

    final favoriteControl = _isFavorite ? MediaControl.favorite : MediaControl.favoriteBorder;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          status.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          favoriteControl,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: status.isPlaying,
        updatePosition: Duration(
          milliseconds: currentPositionMs,
        ),
        bufferedPosition: Duration(
          milliseconds: bufferedMs,
        ),
        speed: 1.0,
      ),
    );
  }
}
