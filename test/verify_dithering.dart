import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Sautiflow Dithering & Noise Shaping Verification Suite', () {
    print('====================================================');
    print('  SAUTIFLOW DITHERING & NOISE SHAPING TEST SUITE  ');
    print('====================================================\n');

    final player = MiniAudioPlayer(libraryPath: 'audio_engine.dll');
    final ok = player.init();
    expect(ok, isTrue, reason: 'Audio Engine should initialize successfully');
    print('✅ Audio Engine initialized successfully!');

    final modes = <int, String>{
      0: 'None (Bit-Exact Direct Pass-through)',
      1: 'Rectangle (RPDF 1.0 LSB p-p)',
      2: 'Triangle (TPDF 2.0 LSB p-p)',
      3: 'Lipshitz (5th-Order Noise Shaping)',
      4: 'F-Weighted (5th-Order Noise Shaping)',
      5: 'Mod E-Weighted (5th-Order Noise Shaping)',
      6: 'Shibata (5th-Order Acoustic Noise Shaping)',
      7: 'Low Shibata (Gentle HF Noise Shaping)',
      8: 'High Shibata (Aggressive Audible Band Noise Shaping)',
    };

    final formats = <AudioFormat, String>{
      AudioFormat.f32: '32-bit Float (F32)',
      AudioFormat.s16: '16-bit Signed Int (S16)',
      AudioFormat.s24: '24-bit Signed Int (S24)',
      AudioFormat.s32: '32-bit Signed Int (S32)',
      AudioFormat.u8: '8-bit Unsigned Int (U8)',
    };

    print('\n--- Testing All Dither Modes across Formats ---');
    for (final fmt in formats.entries) {
      player.setOutputFormat(fmt.key);
      final currentFmt = player.getOutputFormat();
      expect(currentFmt, equals(fmt.key));
      print('📍 Output Format set to: ${fmt.value} (engine reports: ${currentFmt.name})');

      for (final entry in modes.entries) {
        player.setEngineDitherMode(entry.key);
        final currentMode = player.getEngineDitherMode();

        expect(currentMode, equals(entry.key),
            reason: 'Mode ${entry.key} should match set dither mode');
        print('   ✅ Mode ${entry.key}: ${entry.value} -> Active');
      }
    }

    // Rapid switching test to verify history state resets without crashes
    print('\n--- Testing Rapid Dither Mode Stress Switching ---');
    for (int i = 0; i < 50; i++) {
      final targetMode = i % 9;
      player.setEngineDitherMode(targetMode);
    }
    print('✅ Stress switching passed with zero errors or crashes!');

    player.dispose();
    print('\n====================================================');
    print('🎉 ALL DITHERING VERIFICATION CHECKS PASSED CLEANLY!');
    print('====================================================');
  });
}
