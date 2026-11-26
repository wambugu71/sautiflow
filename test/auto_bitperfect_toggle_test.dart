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

    // 2. Enable Auto Bit-Perfect mode in fixed-clock Shared Mode.
    player.setAutoBitPerfectEnabled(true);
    expect(player.isAutoBitPerfectEnabled, isTrue);

    // Shared Mode locks to the OS mixer rate (initialRate) to prevent hidden OS SRC,
    // without corrupting userOutputSampleRate.
    player.setOutputSampleRate(44100);
    expect(player.getOutputSampleRate(), equals(initialRate));

    // 3. If Exclusive Mode is accepted by host hardware, verify dynamic 44.1 kHz
    // switching when supported, then return to Shared Mode.
    player.setExclusiveMode(true);
    if (player.isExclusiveModeActive()) {
      final supportedRates = player.getHardwareSupportedSampleRates();
      if (supportedRates.contains(44100)) {
        player.setOutputSampleRate(44100);
        expect(player.getOutputSampleRate(), equals(44100));
      }
      player.setExclusiveMode(false);
    }

    // 4. Disable Auto Bit-Perfect mode and confirm initial rate is restored cleanly.
    player.setAutoBitPerfectEnabled(false);
    expect(player.isAutoBitPerfectEnabled, isFalse);
    expect(player.getOutputSampleRate(), equals(initialRate));

    // 5. Verify batched applyOutputConfig updates format and dither cleanly.
    player.applyOutputConfig(
      format: AudioFormat.s32,
      ditherMode: 2,
      autoSampleRate: false,
    );
    expect(player.getOutputFormat(), equals(AudioFormat.s32));
    expect(player.getEngineDitherMode(), equals(2));

    player.dispose();
  });
}
