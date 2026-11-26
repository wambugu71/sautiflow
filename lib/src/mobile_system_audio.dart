import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../audio_engine_ffi.dart';

class MiniAudioSystemAudioConfig {
  const MiniAudioSystemAudioConfig({
    this.enableDucking = true,
    this.duckGain = 0.25,
    this.normalGain = 1.0,
    this.pauseWhenInterrupted = true,
    this.resumeAfterInterruption = true,
    this.pauseOnBecomingNoisy = true,
    this.resumeOnHeadsetConnect = false,
    this.permanentFocusLossAction = 'pause',
    this.handleHeadsetMultiClicks = true,
    this.headsetClickTimeoutMs = 350,
    this.androidNotificationChannelId = 'com.wambugu.miniaudiodart.playback',
    this.androidNotificationChannelName = 'Audio Playback',
    this.androidNotificationOngoing = true,
    this.androidStopForegroundOnPause = true,
    this.androidNotificationIcon = 'drawable/splash',
  });

  final bool enableDucking;
  final double duckGain;
  final double normalGain;
  final bool pauseWhenInterrupted;
  final bool resumeAfterInterruption;
  final bool pauseOnBecomingNoisy;
  final bool resumeOnHeadsetConnect;
  final String permanentFocusLossAction;
  final bool handleHeadsetMultiClicks;
  final int headsetClickTimeoutMs;
  final String androidNotificationChannelId;
  final String androidNotificationChannelName;
  final bool androidNotificationOngoing;
  final bool androidStopForegroundOnPause;
  final String androidNotificationIcon;

  MiniAudioSystemAudioConfig copyWith({
    bool? enableDucking,
    double? duckGain,
    double? normalGain,
    bool? pauseWhenInterrupted,
    bool? resumeAfterInterruption,
    bool? pauseOnBecomingNoisy,
    bool? resumeOnHeadsetConnect,
    String? permanentFocusLossAction,
    bool? handleHeadsetMultiClicks,
    int? headsetClickTimeoutMs,
    String? androidNotificationChannelId,
    String? androidNotificationChannelName,
    bool? androidNotificationOngoing,
    bool? androidStopForegroundOnPause,
    String? androidNotificationIcon,
  }) {
    return MiniAudioSystemAudioConfig(
      enableDucking: enableDucking ?? this.enableDucking,
      duckGain: duckGain ?? this.duckGain,
      normalGain: normalGain ?? this.normalGain,
      pauseWhenInterrupted: pauseWhenInterrupted ?? this.pauseWhenInterrupted,
      resumeAfterInterruption:
          resumeAfterInterruption ?? this.resumeAfterInterruption,
      pauseOnBecomingNoisy: pauseOnBecomingNoisy ?? this.pauseOnBecomingNoisy,
      resumeOnHeadsetConnect:
          resumeOnHeadsetConnect ?? this.resumeOnHeadsetConnect,
      permanentFocusLossAction:
          permanentFocusLossAction ?? this.permanentFocusLossAction,
      handleHeadsetMultiClicks:
          handleHeadsetMultiClicks ?? this.handleHeadsetMultiClicks,
      headsetClickTimeoutMs:
          headsetClickTimeoutMs ?? this.headsetClickTimeoutMs,
      androidNotificationChannelId:
          androidNotificationChannelId ?? this.androidNotificationChannelId,
      androidNotificationChannelName:
          androidNotificationChannelName ?? this.androidNotificationChannelName,
      androidNotificationOngoing:
          androidNotificationOngoing ?? this.androidNotificationOngoing,
      androidStopForegroundOnPause:
          androidStopForegroundOnPause ?? this.androidStopForegroundOnPause,
      androidNotificationIcon:
          androidNotificationIcon ?? this.androidNotificationIcon,
    );
  }
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
    void Function(String message)? onLog,
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
        _onToggleFavorite = onToggleFavorite,
        _onLog = onLog;

  static _MiniAudioHandler? _sharedHandler;

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
  final void Function(String message)? _onLog;

  AudioHandler? _handler;
  _MiniAudioHandler? _typedHandler;
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<StreamTelemetry>? _telemetrySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  StreamSubscription<Object>? _asyncErrorSub;
  Timer? _deactivateSessionTimer;
  MiniAudioSystemAudioConfig? _config;
  bool _isDucked = false;
  double _preDuckGain = 1.0;
  StreamTelemetry? _latestTelemetry;
  bool _audioSessionActive = false;
  PlayerStatus? _lastPlayerStatus;
  bool _wasPlayingBeforeInterruption = false;
  MediaItem? _pendingMediaItem;
  bool? _pendingIsFavorite;

  bool get isSupported => Platform.isAndroid || Platform.isIOS;
  bool get isEnabled => _config != null;

  void _log(String message) {
    debugPrint(message);
    _onLog?.call(message);
  }

  Future<bool> activateSession() async {
    if (!isSupported) return false;
    _deactivateSessionTimer?.cancel();
    _deactivateSessionTimer = null;
    try {
      final session = await AudioSession.instance;
      final granted = await session.setActive(true);
      _audioSessionActive = granted;
      if (!granted) {
        _log('[system-audio] AudioSession focus request denied');
      }
      return granted;
    } catch (e) {
      _log('[system-audio] AudioSession activateSession error: $e');
      return false;
    }
  }

  void notifyStopped() {
    _deactivateSessionTimer?.cancel();
    _deactivateSessionTimer = null;
    _wasPlayingBeforeInterruption = false;
    _isDucked = false;
    _typedHandler?.markStopped();
    if (isSupported && _audioSessionActive) {
      _audioSessionActive = false;
      unawaited(_deactivateAudioSessionSafely('stop'));
    }
  }

  Future<void> _deactivateAudioSessionSafely(String reason) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      _log('[system-audio] AudioSession deactivate error ($reason): $e');
    }
  }

  void updateConfig(MiniAudioSystemAudioConfig config) {
    _config = config;
    _typedHandler?.updateHeadsetSettings(
      handleHeadsetMultiClicks: config.handleHeadsetMultiClicks,
      headsetClickTimeoutMs: config.headsetClickTimeoutMs,
    );
  }

  Future<bool> enable({
    MiniAudioSystemAudioConfig config = const MiniAudioSystemAudioConfig(),
  }) async {
    if (!isSupported) return false;

    try {
      _config = config;

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      Future<void> handlePlay() async {
        _deactivateSessionTimer?.cancel();
        _deactivateSessionTimer = null;
        final granted = await session.setActive(true);
        _audioSessionActive = granted;
        if (!granted) {
          _log('[system-audio] AudioSession focus denied on play callback');
        }
        await _onPlay();
      }

      Future<void> handlePause() async {
        await _onPause();
        _deactivateSessionTimer?.cancel();
        _deactivateSessionTimer = null;
        _audioSessionActive = false;
        await session.setActive(false);
      }

      Future<void> handleStop() async {
        await _onStop();
        _deactivateSessionTimer?.cancel();
        _deactivateSessionTimer = null;
        _audioSessionActive = false;
        await session.setActive(false);
      }

      if (_handler == null && _sharedHandler == null) {
        final handler = await AudioService.init(
          builder: () => _MiniAudioHandler(
            onPlay: handlePlay,
            onPause: handlePause,
            onStop: handleStop,
            onNext: _onNext,
            onPrevious: _onPrevious,
            onSeek: _onSeek,
            onToggleFavorite: _onToggleFavorite,
            handleHeadsetMultiClicks: config.handleHeadsetMultiClicks,
            headsetClickTimeoutMs: config.headsetClickTimeoutMs,
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
        _sharedHandler = handler;
        _handler = handler;
        _typedHandler = handler;
      } else {
        final existing = _typedHandler ?? _sharedHandler!;
        existing.rebindCallbacks(
          onPlay: handlePlay,
          onPause: handlePause,
          onStop: handleStop,
          onNext: _onNext,
          onPrevious: _onPrevious,
          onSeek: _onSeek,
          onToggleFavorite: _onToggleFavorite,
        );
        existing.updateHeadsetSettings(
          handleHeadsetMultiClicks: config.handleHeadsetMultiClicks,
          headsetClickTimeoutMs: config.headsetClickTimeoutMs,
        );
        _handler = existing;
        _typedHandler = existing;
      }

      _asyncErrorSub?.cancel();
      _asyncErrorSub = AudioService.asyncError.listen((err) {
        _log('[system-audio] AudioService asyncError: $err');
      });

      if (_pendingIsFavorite != null) {
        _typedHandler?.setFavorite(_pendingIsFavorite!);
      }
      if (_pendingMediaItem != null) {
        _typedHandler?.mediaItem.add(_pendingMediaItem!);
      }
      if (_lastPlayerStatus != null) {
        _typedHandler?.updateFromPlayerStatus(
          _lastPlayerStatus!,
          telemetry: _latestTelemetry,
          force: true,
        );
      }

      _telemetrySub?.cancel();
      if (_telemetryStream != null) {
        _telemetrySub = _telemetryStream.listen((tel) {
          _latestTelemetry = tel;
        });
      }

      _statusSub?.cancel();
      _statusSub = _statusStream.listen((status) {
        _lastPlayerStatus = status;
        _typedHandler?.updateFromPlayerStatus(status, telemetry: _latestTelemetry);

        if (status.isPlaying) {
          _deactivateSessionTimer?.cancel();
          _deactivateSessionTimer = null;
          if (!_audioSessionActive) {
            _audioSessionActive = true;
            unawaited(
              session.setActive(true).then((granted) {
                if (!granted) {
                  _audioSessionActive = false;
                  _log('[system-audio] AudioSession focus denied on playback');
                }
              }).catchError((Object e) {
                _audioSessionActive = false;
                _log('[system-audio] AudioSession setActive(true) error: $e');
              }),
            );
          }
        } else if (_audioSessionActive &&
            (_deactivateSessionTimer == null || !_deactivateSessionTimer!.isActive)) {
          _deactivateSessionTimer = Timer(const Duration(seconds: 2), () {
            _deactivateSessionTimer = null;
            if (_lastPlayerStatus?.isPlaying == true || _wasPlayingBeforeInterruption) {
              return;
            }
            if (_audioSessionActive) {
              _audioSessionActive = false;
              unawaited(_deactivateAudioSessionSafely('pause-debounce'));
            }
          });
        }
      });

      Timer? duckRampTimer;

      void rampGain({required double targetGain, int durationMs = 80}) {
        duckRampTimer?.cancel();
        final startGain = _onGetGain?.call() ?? targetGain;
        final startTime = DateTime.now().millisecondsSinceEpoch;
        const stepInterval = 10;

        duckRampTimer =
            Timer.periodic(const Duration(milliseconds: stepInterval), (timer) {
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

          _wasPlayingBeforeInterruption = _lastPlayerStatus?.isPlaying == true;

          if (event.type == AudioInterruptionType.unknown) {
            // Permanent focus loss (e.g. another media app took exclusive playback)
            _deactivateSessionTimer?.cancel();
            _deactivateSessionTimer = null;
            _audioSessionActive = false;
            if (c.permanentFocusLossAction == 'stop') {
              _onStop();
            } else {
              _onPause();
            }
            _wasPlayingBeforeInterruption = false;
            return;
          }

          if (c.pauseWhenInterrupted) {
            _deactivateSessionTimer?.cancel();
            _deactivateSessionTimer = null;
            _audioSessionActive = false;
            _onPause();
          }
          return;
        }

        // Interruption ended (phone call concluded, notification chime finished)
        if (_isDucked) {
          rampGain(targetGain: _preDuckGain, durationMs: 80);
          _isDucked = false;
        }

        if (c.resumeAfterInterruption && _wasPlayingBeforeInterruption) {
          _wasPlayingBeforeInterruption = false;
          unawaited(activateSession());
          _onPlay();
        }
      });

      _becomingNoisySub?.cancel();
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (_config?.pauseOnBecomingNoisy == true) {
          _onPause();
        }
      });

      _devicesSub?.cancel();
      _devicesSub = session.devicesChangedEventStream.listen((event) {
        final c = _config;
        if (c == null || !c.resumeOnHeadsetConnect) return;

        final hasAddedHeadset = event.devicesAdded.any((d) =>
            d.type == AudioDeviceType.wiredHeadset ||
            d.type == AudioDeviceType.wiredHeadphones ||
            d.type == AudioDeviceType.bluetoothA2dp ||
            d.type == AudioDeviceType.bluetoothSco ||
            d.type == AudioDeviceType.bluetoothLe);

        if (hasAddedHeadset && !(_lastPlayerStatus?.isPlaying ?? false)) {
          _onPlay();
        }
      });

      return true;
    } catch (e, stack) {
      _log('[system-audio] Error enabling: $e\n$stack');
      _config = null;
      return false;
    }
  }

  Future<void> disable() async {
    _deactivateSessionTimer?.cancel();
    _deactivateSessionTimer = null;
    _statusSub?.cancel();
    _statusSub = null;
    _telemetrySub?.cancel();
    _telemetrySub = null;
    _asyncErrorSub?.cancel();
    _asyncErrorSub = null;
    _interruptionSub?.cancel();
    _interruptionSub = null;
    _becomingNoisySub?.cancel();
    _becomingNoisySub = null;
    _devicesSub?.cancel();
    _devicesSub = null;

    final c = _config;
    _config = null;
    _pendingMediaItem = null;
    _pendingIsFavorite = null;
    _wasPlayingBeforeInterruption = false;

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
    _pendingIsFavorite = isFavorite;
    _typedHandler?.setFavorite(isFavorite);
  }

  void refreshNotification() {
    final h = _typedHandler;
    if (h == null) return;
    if (_pendingMediaItem != null) {
      h.mediaItem.add(_pendingMediaItem!);
    }
    if (_lastPlayerStatus != null) {
      h.updateFromPlayerStatus(
        _lastPlayerStatus!,
        telemetry: _latestTelemetry,
        force: true,
      );
    }
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
    if (isFavorite != null) {
      _pendingIsFavorite = isFavorite;
    }

    final item = MediaItem(
      id: id ?? 'miniaudiodart-current',
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: artUri,
    );
    _pendingMediaItem = item;

    final h = _typedHandler;
    if (h == null) return;

    if (isFavorite != null) {
      h.setFavorite(isFavorite);
    }

    h.mediaItem.add(item);
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
    bool handleHeadsetMultiClicks = true,
    int headsetClickTimeoutMs = 350,
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onStop = onStop,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onSeek = onSeek,
        _onToggleFavoriteFallback = onToggleFavorite,
        _onToggleFavorite = onToggleFavorite,
        _handleHeadsetMultiClicks = handleHeadsetMultiClicks,
        _headsetClickTimeoutMs = headsetClickTimeoutMs {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.pause,
          MediaControl.skipToNext,
          _favoriteBorderControl,
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

  static const _favoriteControl = MediaControl(
    androidIcon: 'drawable/audio_service_favorite',
    label: 'Favorite',
    action: MediaAction.custom,
    customAction: CustomMediaAction(name: 'favorite'),
  );

  static const _favoriteBorderControl = MediaControl(
    androidIcon: 'drawable/audio_service_favorite_border',
    label: 'Favorite',
    action: MediaAction.custom,
    customAction: CustomMediaAction(name: 'favorite'),
  );

  final FutureOr<void> Function()? _onToggleFavoriteFallback;
  FutureOr<void> Function()? _onToggleFavorite;
  bool _isFavorite = false;
  PlayerStatus? _lastStatus;
  StreamTelemetry? _lastTelemetry;
  bool _handleHeadsetMultiClicks;
  int _headsetClickTimeoutMs;
  Timer? _mediaClickTimer;
  int _mediaClickCount = 0;

  bool? _lastPushedPlaying;
  int? _lastPushedIndex;
  bool? _lastPushedFavorite;
  int _lastPushedBufferedMs = 0;
  int _lastPushedPosMs = 0;
  int _lastPushTimeMs = 0;
  bool _isStopped = false;

  void rebindCallbacks({
    required FutureOr<void> Function() onPlay,
    required FutureOr<void> Function() onPause,
    required FutureOr<void> Function() onStop,
    required FutureOr<void> Function() onNext,
    required FutureOr<void> Function() onPrevious,
    required FutureOr<void> Function(Duration position) onSeek,
    FutureOr<void> Function()? onToggleFavorite,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;
    _onStop = onStop;
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onSeek = onSeek;
    _onToggleFavorite = onToggleFavorite ?? _onToggleFavoriteFallback;
  }

  void updateHeadsetSettings({
    required bool handleHeadsetMultiClicks,
    required int headsetClickTimeoutMs,
  }) {
    _handleHeadsetMultiClicks = handleHeadsetMultiClicks;
    _headsetClickTimeoutMs = headsetClickTimeoutMs;
  }

  void setFavorite(bool isFavorite) {
    if (_isFavorite == isFavorite) return;
    _isFavorite = isFavorite;
    if (_lastStatus != null && !_isStopped) {
      updateFromPlayerStatus(
        _lastStatus!,
        telemetry: _lastTelemetry,
        force: true,
      );
    }
  }

  void markStopped() {
    _isStopped = true;
    _lastPushedPlaying = false;
    _lastPushTimeMs = 0;
    final current = playbackState.hasValue ? playbackState.value : PlaybackState();
    playbackState.add(
      current.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'favorite' || name == 'toggleFavorite') {
      await _onToggleFavorite?.call();
      return null;
    }
    return super.customAction(name, extras);
  }

  FutureOr<void> Function() _onPlay;
  FutureOr<void> Function() _onPause;
  FutureOr<void> Function() _onStop;
  FutureOr<void> Function() _onNext;
  FutureOr<void> Function() _onPrevious;
  FutureOr<void> Function(Duration position) _onSeek;

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
    markStopped();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (_lastStatus?.isPlaying != true) {
      await stop();
    }
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

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.next) {
      await skipToNext();
      return;
    }
    if (button == MediaButton.previous) {
      await skipToPrevious();
      return;
    }

    if (!_handleHeadsetMultiClicks) {
      if (_lastStatus?.isPlaying == true) {
        await pause();
      } else {
        await play();
      }
      return;
    }

    // Multi-click detection for 3.5mm headphones and Bluetooth headsets:
    // 1 click: Play / Pause toggle
    // 2 clicks: Next song in current playlist
    // 3 clicks: Previous song in current playlist
    _mediaClickCount++;
    _mediaClickTimer?.cancel();
    _mediaClickTimer =
        Timer(Duration(milliseconds: _headsetClickTimeoutMs), () async {
      final count = _mediaClickCount;
      _mediaClickCount = 0;
      _mediaClickTimer = null;

      if (count == 1) {
        if (_lastStatus?.isPlaying == true) {
          await pause();
        } else {
          await play();
        }
      } else if (count == 2) {
        await skipToNext();
      } else if (count >= 3) {
        await skipToPrevious();
      }
    });
  }

  void updateFromPlayerStatus(
    PlayerStatus status, {
    StreamTelemetry? telemetry,
    bool force = false,
  }) {
    _lastStatus = status;
    _lastTelemetry = telemetry;

    if (_isStopped && !status.isPlaying && !force) {
      return;
    }

    final currentPositionMs = math.max(0, (status.positionSeconds * 1000).round());
    final bufferAheadMs = (telemetry != null && telemetry.bufferedDuration > Duration.zero)
        ? telemetry.bufferedDuration.inMilliseconds
        : 0;
    final bufferedMs = currentPositionMs + bufferAheadMs;

    final wasStopped = _isStopped && status.isPlaying;
    if (wasStopped) {
      _isStopped = false;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedSincePushMs = nowMs - _lastPushTimeMs;
    final expectedPosMs = (_lastPushedPlaying == true && _lastPushTimeMs > 0)
        ? _lastPushedPosMs + elapsedSincePushMs
        : _lastPushedPosMs;
    final seekDetected = _lastPushTimeMs > 0 &&
        (currentPositionMs - expectedPosMs).abs() > 1200;
    final stateChanged = status.isPlaying != _lastPushedPlaying ||
        status.currentIndex != _lastPushedIndex ||
        _isFavorite != _lastPushedFavorite ||
        wasStopped ||
        (!status.isPlaying && (bufferedMs - _lastPushedBufferedMs).abs() > 5000);
    final periodicSyncDue = _lastPushTimeMs == 0 || elapsedSincePushMs >= 15000;

    if (!force && !stateChanged && !seekDetected && !periodicSyncDue) {
      return;
    }

    _lastPushedPlaying = status.isPlaying;
    _lastPushedIndex = status.currentIndex;
    _lastPushedFavorite = _isFavorite;
    _lastPushedBufferedMs = bufferedMs;
    _lastPushedPosMs = currentPositionMs;
    _lastPushTimeMs = nowMs;

    final favoriteControl = _isFavorite ? _favoriteControl : _favoriteBorderControl;

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
