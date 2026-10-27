import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/sleep_timer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SleepTimerService', () {
    final service = SleepTimerService.instance;

    setUp(() {
      service.cancelTimer();
    });

    tearDown(() {
      service.cancelTimer();
    });

    test('initial state is inactive', () {
      expect(service.state.value.isActive, isFalse);
      expect(service.state.value.remainingSeconds, equals(0));
      expect(service.state.value.formattedRemaining, equals('Off'));
    });

    test('startTimer initiates countdown with correct remaining seconds', () {
      service.startTimer(minutes: 15, fadeOut: true);
      final s = service.state.value;

      expect(s.isActive, isTrue);
      expect(s.mode, equals(SleepTimerMode.countdown));
      expect(s.remainingSeconds, equals(15 * 60));
      expect(s.totalSeconds, equals(15 * 60));
      expect(s.fadeOut, isTrue);
      expect(s.shortFormattedRemaining, equals('15m'));
      expect(s.formattedRemaining, equals('15:00'));
    });

    test('addMinutes extends active countdown', () {
      service.startTimer(minutes: 10);
      expect(service.state.value.remainingSeconds, equals(10 * 60));

      service.addMinutes(5);
      expect(service.state.value.remainingSeconds, equals(15 * 60));
      expect(service.state.value.totalSeconds, equals(15 * 60));
      expect(service.state.value.shortFormattedRemaining, equals('15m'));
    });

    test('cancelTimer resets state to inactive', () {
      service.startTimer(minutes: 30);
      expect(service.state.value.isActive, isTrue);

      service.cancelTimer();
      expect(service.state.value.isActive, isFalse);
      expect(service.state.value.remainingSeconds, equals(0));
    });

    test('startEndOfTrack configures endOfTrack mode properly', () {
      service.startEndOfTrack(
        currentTrackIndex: 3,
        trackDurationSeconds: 240,
        currentPositionSeconds: 60,
        fadeOut: true,
      );

      final s = service.state.value;
      expect(s.isActive, isTrue);
      expect(s.mode, equals(SleepTimerMode.endOfTrack));
      expect(s.targetTrackIndex, equals(3));
      expect(s.remainingSeconds, equals(180));
      expect(s.shortFormattedRemaining, equals('Track End'));
      expect(s.formattedRemaining, contains('End of track'));
    });
  });
}
