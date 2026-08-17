import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Auto Bit-Perfect Toggle and Sample Rate Recovery Test', () {
    final player = MiniAudioPlayer(libraryPath: 'sautiflow.dll');
    final ok = player.init(sampleRate: 48000);
    expect(ok, isTrue, reason: 'Engine should initialize successfully');

    // 1. Initial state: Auto Bit-Perfect is OFF, output sample rate is 0 (native)
    expect(player.isAutoBitPerfectEnabled, isFalse);
    expect(player.getOutputSampleRate(), equals(0));

    // 2. Enable Auto Bit-Perfect mode
    player.setAutoBitPerfectEnabled(true);
    expect(player.isAutoBitPerfectEnabled, isTrue);

    // Dynamic rate change while playing 44.1 kHz track in Auto Bit-Perfect mode
    player.setOutputSampleRate(44100);
    expect(player.getOutputSampleRate(), equals(44100));

    // 3. Disable Auto Bit-Perfect mode
    player.setAutoBitPerfectEnabled(false);
    expect(player.isAutoBitPerfectEnabled, isFalse);

    // 4. Verify output sample rate is restored to user output rate (0 = native)
    // instead of remaining stuck at 44100 Hz
    expect(player.getOutputSampleRate(), equals(0));

    player.dispose();
  });
}
