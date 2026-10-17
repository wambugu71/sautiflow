import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:sautiflow/sautiflow.dart';

import 'app_state_service.dart';

/// Available air gesture actions triggered by the proximity sensor.
enum ProximityGestureAction {
  nextTrack,
  previousTrack,
}

/// Service managing proximity sensor air gestures for hands-free track navigation.
///
/// Gesture mapping:
/// - **1 Wave**: Next song in current playlist.
/// - **2 Waves**: Previous song in current playlist.
///
/// Efficiency & Reliability:
/// - **Lifecycle & Battery Optimization**: The hardware proximity sensor stream is ONLY
///   active when proximity gestures are enabled AND the player is actively playing
///   (or always active if `onlyWhenPlaying == false`). When playback stops or pauses, the
///   sensor subscription is immediately paused/cancelled to consume 0% background battery.
/// - **Jitter & False-Positive Filtering**:
///   - Discards near-events < 30ms (sensor optical noise/jitter).
///   - Discards prolonged occlusion > 900ms (phone in pocket, face-down on table, held to ear).
///   - Post-action refractory cooldown (500ms) to ignore trailing hand movements.
/// - **Multi-Wave Window**: 500ms debounce timer to accurately differentiate 1 wave from 2 waves.
/// - **Haptic Confirmation**: Generates tactile haptic buzz on wave registration.
/// - **Platform Safe**: Checks `isSupported` (Android/iOS only) before any platform channel
///   invocations to guarantee zero crashes on desktop (Windows/Linux/macOS) and web.
class ProximityGestureService {
  ProximityGestureService._();
  static final ProximityGestureService instance = ProximityGestureService._();

  /// Whether the current device platform supports hardware proximity sensors.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  VoidCallback? _onNext;
  VoidCallback? _onPrevious;
  void Function(ProximityGestureAction action)? _onGestureAction;

  ProximityGestureSettings _settings = const ProximityGestureSettings();
  ProximityGestureSettings get settings => _settings;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  bool _isListening = false;
  bool get isListening => _isListening;

  StreamSubscription<dynamic>? _sensorSubscription;
  StreamSubscription<PlayerStatus>? _statusSubscription;

  // Wave detection state tracking
  bool _isNear = false;
  int _nearStartTime = 0;
  int _pendingWaves = 0;
  Timer? _multiWaveTimer;
  int _cooldownUntil = 0;

  StreamController<bool> _listeningStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get listeningStateStream => _listeningStateController.stream;

  StreamController<ProximityGestureAction> _gestureActionController =
      StreamController<ProximityGestureAction>.broadcast();
  Stream<ProximityGestureAction> get gestureActionStream =>
      _gestureActionController.stream;

  /// Initializes the proximity gesture service with navigation callbacks and player status.
  Future<void> init({
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    void Function(ProximityGestureAction action)? onGestureAction,
    Stream<PlayerStatus>? statusStream,
  }) async {
    _ensureControllersOpen();
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onGestureAction = onGestureAction;

    _statusSubscription?.cancel();
    if (statusStream != null) {
      _statusSubscription = statusStream.listen((status) {
        setPlayerPlaying(status.isPlaying);
      });
    }

    await _loadInitialSettings();
  }

  void _ensureControllersOpen() {
    if (_listeningStateController.isClosed) {
      _listeningStateController = StreamController<bool>.broadcast();
    }
    if (_gestureActionController.isClosed) {
      _gestureActionController =
          StreamController<ProximityGestureAction>.broadcast();
    }
  }

  Future<void> _loadInitialSettings() async {
    _settings = await AppStateService.instance.loadProximitySettings();
    _syncSensorState();
  }

  /// Updates whether the player is currently playing music.
  void setPlayerPlaying(bool isPlaying) {
    if (_isPlaying == isPlaying) return;
    _isPlaying = isPlaying;
    _syncSensorState();
  }

  /// Updates settings and synchronizes sensor subscription.
  Future<void> updateSettings(ProximityGestureSettings newSettings) async {
    _settings = newSettings;
    await AppStateService.instance.saveProximitySettings(newSettings);
    _syncSensorState();
  }

  /// Enables or disables proximity gestures.
  Future<void> setEnabled(bool enabled) async {
    await updateSettings(_settings.copyWith(enabled: enabled));
  }

  /// Sets whether the sensor should only be active while audio is playing.
  Future<void> setOnlyWhenPlaying(bool onlyWhenPlaying) async {
    await updateSettings(_settings.copyWith(onlyWhenPlaying: onlyWhenPlaying));
  }

  /// Enables or disables haptic feedback on wave detection.
  Future<void> setHapticFeedback(bool hapticFeedback) async {
    await updateSettings(_settings.copyWith(hapticFeedback: hapticFeedback));
  }

  /// Sets the multi-wave detection timeout window (ms).
  Future<void> setWaveDebounceMs(int debounceMs) async {
    await updateSettings(_settings.copyWith(waveDebounceMs: debounceMs));
  }

  /// Synchronizes the hardware sensor listening state according to settings and playback state.
  void _syncSensorState() {
    if (!isSupported) {
      _stopListening();
      return;
    }

    final shouldListen = _settings.enabled &&
        (!_settings.onlyWhenPlaying || _isPlaying);

    if (shouldListen) {
      _startListening();
    } else {
      _stopListening();
    }
  }

  void _startListening() {
    if (_isListening || _sensorSubscription != null) return;

    try {
      _sensorSubscription = ProximitySensor.events.listen(
        _onSensorData,
        onError: (err) {
          debugPrint('[ProximityGestureService] Sensor stream error: $err');
          _stopListening();
        },
        cancelOnError: false,
      );
      _isListening = true;
      if (!_listeningStateController.isClosed) {
        _listeningStateController.add(true);
      }
      debugPrint('[ProximityGestureService] Started listening to proximity sensor');
    } catch (e) {
      debugPrint('[ProximityGestureService] Failed to listen to proximity sensor: $e');
      _stopListening();
    }
  }

  void _stopListening() {
    if (!_isListening && _sensorSubscription == null) return;

    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    _isListening = false;
    _isNear = false;
    _pendingWaves = 0;
    _multiWaveTimer?.cancel();
    _multiWaveTimer = null;
    if (!_listeningStateController.isClosed) {
      _listeningStateController.add(false);
    }
    debugPrint('[ProximityGestureService] Stopped listening to proximity sensor');
  }

  void _onSensorData(int event) {
    processSensorEvent(event, DateTime.now().millisecondsSinceEpoch);
  }

  /// Core wave event processing with explicit timestamp for testing and production.
  @visibleForTesting
  void processSensorEvent(int event, int timestampMs) {
    final isNearNow = event > 0;

    if (isNearNow) {
      // Hand entered proximity region
      _isNear = true;
      _nearStartTime = timestampMs;
    } else {
      // Hand left proximity region
      if (!_isNear) return;
      _isNear = false;

      final duration = timestampMs - _nearStartTime;

      // 1. Discard noise (< 30ms) or prolonged obstruction / pocket mode (> 900ms)
      if (duration < 30 || duration > 900) {
        return;
      }

      // 2. Discard if in refractory cooldown after triggering an action
      if (timestampMs < _cooldownUntil) {
        return;
      }

      _onValidWave(timestampMs);
    }
  }

  void _onValidWave(int now) {
    _pendingWaves++;

    if (_settings.hapticFeedback) {
      if (_pendingWaves == 1) {
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
      } else {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
      }
    }

    if (_pendingWaves == 1) {
      // Start waiting for a potential second wave
      _multiWaveTimer?.cancel();
      _multiWaveTimer = Timer(Duration(milliseconds: _settings.waveDebounceMs), () {
        _multiWaveTimer = null;
        if (_pendingWaves == 1) {
          _triggerNextTrack(now + _settings.waveDebounceMs);
        }
        _pendingWaves = 0;
      });
    } else if (_pendingWaves >= 2) {
      // Double wave detected: trigger previous track immediately
      _multiWaveTimer?.cancel();
      _multiWaveTimer = null;
      _pendingWaves = 0;
      _triggerPreviousTrack(now);
    }
  }

  void _triggerNextTrack([int? nowMs]) {
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _cooldownUntil = currentMs + 500;
    debugPrint('[ProximityGestureService] Wave 1x -> Next Song');
    if (!_gestureActionController.isClosed) {
      _gestureActionController.add(ProximityGestureAction.nextTrack);
    }
    try {
      _onGestureAction?.call(ProximityGestureAction.nextTrack);
      _onNext?.call();
    } catch (e) {
      debugPrint('[ProximityGestureService] Error triggering onNext: $e');
    }
  }

  void _triggerPreviousTrack([int? nowMs]) {
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _cooldownUntil = currentMs + 600;
    debugPrint('[ProximityGestureService] Wave 2x -> Previous Song');
    if (!_gestureActionController.isClosed) {
      _gestureActionController.add(ProximityGestureAction.previousTrack);
    }
    try {
      _onGestureAction?.call(ProximityGestureAction.previousTrack);
      _onPrevious?.call();
    } catch (e) {
      debugPrint('[ProximityGestureService] Error triggering onPrevious: $e');
    }
  }

  /// Resets internal state for unit tests without closing streams permanently.
  @visibleForTesting
  void resetForTesting() {
    _stopListening();
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _onNext = null;
    _onPrevious = null;
    _onGestureAction = null;
    _isNear = false;
    _nearStartTime = 0;
    _pendingWaves = 0;
    _multiWaveTimer?.cancel();
    _multiWaveTimer = null;
    _cooldownUntil = 0;
    _isPlaying = false;
    _settings = const ProximityGestureSettings();
  }

  /// Disposes active subscriptions and timers.
  void dispose() {
    _stopListening();
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _listeningStateController.close();
    _gestureActionController.close();
  }
}
