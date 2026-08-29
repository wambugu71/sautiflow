import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Auto Bit-Perfect Toggle and Sample Rate Recovery Test', () {
    final player = MiniAudioPlayer(libraryPath: 'sautiflow.dll');
    final ok = player.init(sampleRate: 48000);
    expect(ok, isTrue, reason: 'Engine should initialize successfully');

    // 1. Initial state: Auto Bit-Perfect is OFF. The getter reports the ACTIVE
    // hardware rate (never the bogus 0 sentinel) on a fresh engine.
    final initialRate = player.getOutputSampleRate();
    expect(player.isAutoBitPerfectEnabled, isFalse);
    expect(initialRate, greaterThan(0));

    // 2. Enable Auto Bit-Perfect mode
    player.setAutoBitPerfectEnabled(true);
    expect(player.isAutoBitPerfectEnabled, isTrue);

    // Dynamic rate change while playing 44.1 kHz track in Auto Bit-Perfect mode
    player.setOutputSampleRate(44100);
    expect(player.getOutputSampleRate(), equals(44100));

    // 3. Disable Auto Bit-Perfect mode
    player.setAutoBitPerfectEnabled(false);
    expect(player.isAutoBitPerfectEnabled, isFalse);

    // 4. Verify output sample rate is restored (drops the forced 44100 Hz and
    // returns to the active hardware rate) instead of remaining stuck at 44100 Hz
    expect(player.getOutputSampleRate(), isNot(equals(44100)));

    player.dispose();
  });
}
