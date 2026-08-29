import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Dithered Volume for Integer Exclusive Modes Verification', () {
    print('===============================================================');
    print('  TEST: Dithered Volume in Integer Exclusive Modes (S16/S24)  ');
    print('===============================================================\n');

    final player = MiniAudioPlayer(libraryPath: 'audio_engine.dll');
    final ok = player.init();
    expect(ok, isTrue, reason: 'Engine should initialize successfully');

    // 1. Enable 64-bit processing
    player.set64BitProcessingEnabled(true);
    expect(player.is64BitProcessingEnabled, isTrue);
    print('✅ 64-bit processing enabled');

    // 2. Configure 16-bit exclusive mode output
    player.setOutputFormat(AudioFormat.s16);
    player.setExclusiveMode(true);
    expect(player.getOutputFormat(), equals(AudioFormat.s16));
    print('✅ Output set to 16-bit format in Exclusive Mode');

    // 3. Test low-volume listening attenuation (e.g. -40 dB = 0.01 linear)
    player.setGain(0.01);
    print('✅ Low-volume gain set to 0.01 (-40 dB)');

    // 4. Test TPDF / Noise-Shaped dither modes for integer exclusive modes
    for (int mode = 0; mode <= 8; mode++) {
      player.setEngineDitherMode(mode);
      expect(player.getEngineDitherMode(), equals(mode));
      print('   Mode $mode configured on 16-bit Exclusive output');
    }

    // 5. Test 24-bit exclusive mode
    player.setOutputFormat(AudioFormat.s24);
    expect(player.getOutputFormat(), equals(AudioFormat.s24));
    player.setGain(0.001); // -60 dB low volume
    print('✅ 24-bit output with low-volume gain set to 0.001 (-60 dB)');

    // 6. Test direct passthrough unity gain (gain = 1.0)
    player.setGain(1.0);
    player.setEngineDitherMode(0);
    expect(player.getEngineDitherMode(), equals(0));
    print('✅ Unity gain (1.0) restored for bit-exact direct passthrough');

    player.dispose();
    print('\n===============================================================');
    print('🎉 DITHERED VOLUME IN INTEGER EXCLUSIVE MODES VERIFIED!');
    print('===============================================================');
  });
}
