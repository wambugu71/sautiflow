import 'dart:async';
import 'dart:io';

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
    this.androidNotificationIcon = 'mipmap/ic_launcher',
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
    required FutureOr<void> Function() onPlay,
    required FutureOr<void> Function() onPause,
    required FutureOr<void> Function() onStop,
    required FutureOr<void> Function() onNext,
    required FutureOr<void> Function() onPrevious,
    required FutureOr<void> Function(Duration position) onSeek,
    required void Function(double gain) onSetGain,
  })  : _statusStream = statusStream,
        _onPlay = onPlay,
        _onPause = onPause,
        _onStop = onStop,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onSeek = onSeek,
        _onSetGain = onSetGain;

  final Stream<PlayerStatus> _statusStream;
  final FutureOr<void> Function() _onPlay;
  final FutureOr<void> Function() _onPause;
  final FutureOr<void> Function() _onStop;
  final FutureOr<void> Function() _onNext;
  final FutureOr<void> Function() _onPrevious;
  final FutureOr<void> Function(Duration position) _onSeek;
  final void Function(double gain) _onSetGain;

  AudioHandler? _handler;
  _MiniAudioHandler? _typedHandler;
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  MiniAudioSystemAudioConfig? _config;
  bool _isDucked = false;
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

      _statusSub?.cancel();
      _statusSub = _statusStream.listen((status) {
        _typedHandler?.updateFromPlayerStatus(status);

        final shouldBeActive = status.isPlaying;
        if (shouldBeActive != _audioSessionActive) {
          _audioSessionActive = shouldBeActive;
          unawaited(session.setActive(shouldBeActive));
        }
      });

      _interruptionSub?.cancel();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        final c = _config;
        if (c == null) return;

        if (event.begin) {
          if (event.type == AudioInterruptionType.duck && c.enableDucking) {
            _onSetGain(c.duckGain);
            _isDucked = true;
            return;
          }

          if (c.pauseWhenInterrupted) {
            _onPause();
          }
          return;
        }

        if (_isDucked) {
          _onSetGain(c.normalGain);
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

  Future<void> updateNowPlaying({
    required String title,
    String? artist,
    String? album,
    String? id,
    Duration? duration,
    Uri? artUri,
  }) async {
    final h = _typedHandler;
    if (h == null) return;

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
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onStop = onStop,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onSeek = onSeek {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.pause,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: [0, 1, 4],
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
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

  void updateFromPlayerStatus(PlayerStatus status) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          status.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: AudioProcessingState.ready,
        playing: status.isPlaying,
        updatePosition: Duration(
          milliseconds: (status.positionSeconds * 1000).round(),
        ),
        bufferedPosition: Duration(
          milliseconds: (status.positionSeconds * 1000).round(),
        ),
        speed: 1.0,
      ),
    );
  }
}
