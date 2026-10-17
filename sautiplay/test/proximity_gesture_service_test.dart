import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/services/app_state_service.dart';
import 'package:sautiplay/services/proximity_gesture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PreferencesStore.instance.setMockValues();
    await PreferencesStore.instance.init();
    ProximityGestureService.instance.resetForTesting();
  });

  tearDown(() {
    ProximityGestureService.instance.resetForTesting();
  });

  group('ProximityGestureService Tests', () {
    test('Initial state loads defaults', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
      );

      expect(service.settings.enabled, isFalse);
      expect(service.settings.onlyWhenPlaying, isTrue);
      expect(service.settings.hapticFeedback, isTrue);
      expect(service.settings.waveDebounceMs, equals(500));
      expect(nextCount, equals(0));
      expect(prevCount, equals(0));
    });

    test('Single wave triggers Next Track after debounce timer', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;
      final actions = <ProximityGestureAction>[];

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
        onGestureAction: (action) => actions.add(action),
      );

      await service.updateSettings(
        const ProximityGestureSettings(
          enabled: true,
          onlyWhenPlaying: false,
          waveDebounceMs: 100,
        ),
      );

      // Simulate Wave 1: Near at t=1000, Far at t=1200 (duration = 200ms -> valid wave)
      service.processSensorEvent(1, 1000);
      service.processSensorEvent(0, 1200);

      // Immediately before debounce timer: not triggered yet
      expect(nextCount, equals(0));
      expect(actions.isEmpty, isTrue);

      // Wait for debounce timer (100ms) to fire
      await Future.delayed(const Duration(milliseconds: 150));

      expect(nextCount, equals(1));
      expect(prevCount, equals(0));
      expect(actions, equals([ProximityGestureAction.nextTrack]));
    });

    test('Two waves within debounce window trigger Previous Track immediately', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;
      final actions = <ProximityGestureAction>[];

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
        onGestureAction: (action) => actions.add(action),
      );

      await service.updateSettings(
        const ProximityGestureSettings(
          enabled: true,
          onlyWhenPlaying: false,
          waveDebounceMs: 200,
        ),
      );

      // Wave 1: near at t=1000, far at t=1150 (duration 150ms)
      service.processSensorEvent(1, 1000);
      service.processSensorEvent(0, 1150);

      // Wave 2: near at t=1200, far at t=1320 (duration 120ms)
      service.processSensorEvent(1, 1200);
      service.processSensorEvent(0, 1320);

      // Double wave fires immediately
      expect(prevCount, equals(1));
      expect(nextCount, equals(0));
      expect(actions, equals([ProximityGestureAction.previousTrack]));

      // Wait past the debounce timer to ensure nextTrack does NOT also fire
      await Future.delayed(const Duration(milliseconds: 250));
      expect(nextCount, equals(0));
      expect(prevCount, equals(1));
    });

    test('Optical jitter (< 30ms) is discarded', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
      );

      await service.updateSettings(
        const ProximityGestureSettings(
          enabled: true,
          onlyWhenPlaying: false,
          waveDebounceMs: 100,
        ),
      );

      // Jitter event: duration is only 15ms
      service.processSensorEvent(1, 1000);
      service.processSensorEvent(0, 1015);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(nextCount, equals(0));
      expect(prevCount, equals(0));
    });

    test('Prolonged occlusion (> 900ms, pocket mode / face down) is discarded', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
      );

      await service.updateSettings(
        const ProximityGestureSettings(
          enabled: true,
          onlyWhenPlaying: false,
          waveDebounceMs: 100,
        ),
      );

      // Phone covered for 1500ms (e.g. slipped into pocket)
      service.processSensorEvent(1, 1000);
      service.processSensorEvent(0, 2500);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(nextCount, equals(0));
      expect(prevCount, equals(0));
    });

    test('Refractory cooldown rejects trailing hand recoil', () async {
      final service = ProximityGestureService.instance;
      int nextCount = 0;
      int prevCount = 0;

      await service.init(
        onNext: () => nextCount++,
        onPrevious: () => prevCount++,
      );

      await service.updateSettings(
        const ProximityGestureSettings(
          enabled: true,
          onlyWhenPlaying: false,
          waveDebounceMs: 50,
        ),
      );

      // Wave 1 & Wave 2 -> triggers Previous track at t=1250, cooldown until 1250 + 600 = 1850ms
      service.processSensorEvent(1, 1000);
      service.processSensorEvent(0, 1100);
      service.processSensorEvent(1, 1150);
      service.processSensorEvent(0, 1250);

      expect(prevCount, equals(1));

      // Trailing hand movement at t=1400 is inside cooldown (1400 < 1850), rejected!
      service.processSensorEvent(1, 1400);
      service.processSensorEvent(0, 1500);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(prevCount, equals(1));
      expect(nextCount, equals(0));

      // New wave well after cooldown (t=2000 > 1850) is accepted!
      service.processSensorEvent(1, 2000);
      service.processSensorEvent(0, 2150);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(nextCount, equals(1));
    });

    test('Settings persistence round-trip through AppStateService', () async {
      final service = ProximityGestureService.instance;
      await service.init(
        onNext: () {},
        onPrevious: () {},
      );

      await service.setEnabled(true);
      await service.setOnlyWhenPlaying(false);
      await service.setHapticFeedback(false);
      await service.setWaveDebounceMs(650);

      final loaded = await AppStateService.instance.loadProximitySettings();
      expect(loaded.enabled, isTrue);
      expect(loaded.onlyWhenPlaying, isFalse);
      expect(loaded.hapticFeedback, isFalse);
      expect(loaded.waveDebounceMs, equals(650));
    });
  });
}
