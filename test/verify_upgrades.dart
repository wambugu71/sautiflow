import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Sautiflow Audiophile Engine Upgrades Verification', () {
    print('=== Testing Sautiflow Audiophile Engine Upgrades ===');

    final player = MiniAudioPlayer(libraryPath: 'build/windows/audio_engine.dll');
    final ok = player.init();
    expect(ok, isTrue, reason: 'Engine should initialize successfully');
    print('Engine initialized successfully!');

    // 1. Test 64-bit float DSP mode toggle
    expect(player.is64BitProcessingEnabled, isFalse);
    player.set64BitProcessingEnabled(true);
    expect(player.is64BitProcessingEnabled, isTrue);

    // 2. Test Auto Bit-Perfect hardware rate matching toggle
    expect(player.isAutoBitPerfectEnabled, isFalse);
    player.setAutoBitPerfectEnabled(true);
    expect(player.isAutoBitPerfectEnabled, isTrue);

    // 3. Test Ambiophonics R.A.C.E. Crossfeed preset (Preset 4)
    player.setCrossfeed(enabled: true, preset: 4);

    // 4. Test Psychoacoustic Noise Shaping Dither Mode
    player.setEngineDitherMode(6);
    expect(player.getEngineDitherMode(), equals(6));

    final hw = player.getHardwareInfo();
    print('Hardware Device: ${hw.deviceName} (${hw.backendName}) | ${hw.sampleRate}Hz ${hw.bitDepth}-bit');

    player.dispose();
    print('=== All Verification Checks Passed Cleanly! ===');
  });
}
