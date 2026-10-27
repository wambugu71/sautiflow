import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sautiflow/sautiflow.dart';
import '../isolate_player.dart';

enum SleepTimerMode {
  countdown,
  endOfTrack,
}

class SleepTimerState {
  final bool isActive;
  final SleepTimerMode mode;
  final int remainingSeconds;
  final int totalSeconds;
  final bool fadeOut;
  final int? targetTrackIndex;

  const SleepTimerState({
    this.isActive = false,
    this.mode = SleepTimerMode.countdown,
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
    this.fadeOut = true,
    this.targetTrackIndex,
  });

  double get progress {
    if (!isActive || totalSeconds <= 0) return 0.0;
    return (1.0 - (remainingSeconds / totalSeconds)).clamp(0.0, 1.0);
  }

  String get formattedRemaining {
    if (!isActive) return 'Off';
    if (mode == SleepTimerMode.endOfTrack) {
      if (remainingSeconds <= 0) return 'End of track';
      final m = remainingSeconds ~/ 60;
      final s = remainingSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')} (End of track)';
    }
    final hours = remainingSeconds ~/ 3600;
    final mins = (remainingSeconds % 3600) ~/ 60;
    final secs = remainingSeconds % 60;
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get shortFormattedRemaining {
    if (!isActive) return '';
    if (mode == SleepTimerMode.endOfTrack) {
      return 'Track End';
    }
    final mins = (remainingSeconds + 59) ~/ 60;
    return '${mins}m';
  }
}

/// Centralized service managing sleep timers across Sautiplay.
class SleepTimerService {
  SleepTimerService._();
  static final SleepTimerService instance = SleepTimerService._();

  final ValueNotifier<SleepTimerState> state =
      ValueNotifier(const SleepTimerState());

  Timer? _ticker;
  IsolateAudioPlayer? _player;
  StreamSubscription<PlayerStatus>? _statusSub;
  double _preFadeGain = 1.0;
  bool _isFading = false;

  void attachPlayer(IsolateAudioPlayer player) {
    if (_player == player) return;
    _statusSub?.cancel();
    _player = player;
    _statusSub = player.statusStream.listen(_onPlayerStatus);
  }

  void _onPlayerStatus(PlayerStatus status) {
    if (!state.value.isActive) return;

    if (state.value.mode == SleepTimerMode.endOfTrack) {
      final targetIdx = state.value.targetTrackIndex;
      final currentIdx = status.currentIndex;

      if (targetIdx != null && currentIdx != targetIdx) {
        // Track advanced to the next track -> trigger sleep pause immediately
        _finishAndPause();
        return;
      }

      final dur = status.durationSeconds;
      final pos = status.positionSeconds;
      if (dur > 0) {
        final remainingSec = (dur - pos).clamp(0.0, 86400.0).toInt();

        // Check if track reached natural end
        if (remainingSec <= 0 || (!status.isPlaying && pos >= (dur - 1.0))) {
          _finishAndPause();
          return;
        }

        // Apply smooth fadeout during final 15 seconds if enabled
        if (state.value.fadeOut && remainingSec <= 15 && _player != null) {
          _isFading = true;
          final factor = (remainingSec / 15.0).clamp(0.0, 1.0);
          _player?.setGain(_preFadeGain * factor);
        }

        state.value = SleepTimerState(
          isActive: true,
          mode: SleepTimerMode.endOfTrack,
          remainingSeconds: remainingSec,
          totalSeconds: dur.toInt(),
          fadeOut: state.value.fadeOut,
          targetTrackIndex: targetIdx,
        );
      }
    }
  }

  /// Starts a countdown sleep timer for the given [minutes].
  void startTimer({required int minutes, bool fadeOut = true}) {
    cancelTimer();
    final totalSec = minutes * 60;
    _preFadeGain = _player?.gain ?? 1.0;
    _isFading = false;

    state.value = SleepTimerState(
      isActive: true,
      mode: SleepTimerMode.countdown,
      remainingSeconds: totalSec,
      totalSeconds: totalSec,
      fadeOut: fadeOut,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final curSec = state.value.remainingSeconds - 1;
      if (curSec <= 0) {
        _finishAndPause();
      } else {
        if (state.value.fadeOut && curSec <= 15 && _player != null) {
          _isFading = true;
          final factor = (curSec / 15.0).clamp(0.0, 1.0);
          _player?.setGain(_preFadeGain * factor);
        }
        state.value = SleepTimerState(
          isActive: true,
          mode: SleepTimerMode.countdown,
          remainingSeconds: curSec,
          totalSeconds: state.value.totalSeconds,
          fadeOut: state.value.fadeOut,
        );
      }
    });
  }

  /// Starts a timer to stop playback after the current track completes.
  void startEndOfTrack({
    required int currentTrackIndex,
    double trackDurationSeconds = 0.0,
    double currentPositionSeconds = 0.0,
    bool fadeOut = true,
  }) {
    cancelTimer();
    _preFadeGain = _player?.gain ?? 1.0;
    _isFading = false;

    final remainingSec = (trackDurationSeconds > 0 && currentPositionSeconds >= 0)
        ? (trackDurationSeconds - currentPositionSeconds).clamp(0.0, 86400.0).toInt()
        : 0;

    state.value = SleepTimerState(
      isActive: true,
      mode: SleepTimerMode.endOfTrack,
      remainingSeconds: remainingSec,
      totalSeconds: trackDurationSeconds.toInt(),
      fadeOut: fadeOut,
      targetTrackIndex: currentTrackIndex,
    );
  }

  /// Extends the active timer by [minutes].
  void addMinutes(int minutes) {
    if (!state.value.isActive || state.value.mode != SleepTimerMode.countdown) {
      startTimer(minutes: minutes);
      return;
    }
    final additionalSec = minutes * 60;
    final newRemaining = state.value.remainingSeconds + additionalSec;
    final newTotal = state.value.totalSeconds + additionalSec;

    // If we were fading, restore original gain
    if (_isFading && _player != null) {
      _player?.setGain(_preFadeGain);
      _isFading = false;
    }

    state.value = SleepTimerState(
      isActive: true,
      mode: SleepTimerMode.countdown,
      remainingSeconds: newRemaining,
      totalSeconds: newTotal,
      fadeOut: state.value.fadeOut,
    );
  }

  /// Cancels the sleep timer and restores volume if it was fading.
  void cancelTimer() {
    _ticker?.cancel();
    _ticker = null;
    if (_isFading && _player != null) {
      _player?.setGain(_preFadeGain);
      _isFading = false;
    }
    state.value = const SleepTimerState(isActive: false);
  }

  void _finishAndPause() {
    _ticker?.cancel();
    _ticker = null;
    _player?.pause();
    if (_isFading && _player != null) {
      _player?.setGain(_preFadeGain);
      _isFading = false;
    }
    state.value = const SleepTimerState(isActive: false);
  }
}
