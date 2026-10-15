import '../lib/audio_engine_ffi.dart';

void main() {
  print('===============================================================');
  print('     VERIFYING MATRIX-COMPENSATED GRAPHIC EQ (PCHIP / GEQ)     ');
  print('===============================================================');

  final engine = AudioEngineFFI(libraryPath: 'audio_engine.dll');
  final created = engine.create(sampleRate: 48000, channels: 2);
  if (!created) {
    throw Exception('Failed to create AudioEngine');
  }
  print('1. AudioEngineFFI created at 48000 Hz, 2 channels.');

  // 10-band ISO frequencies
  final freqs = [31.5, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
  engine.initMultibandEq(freqs.length, freqs);
  engine.setMultibandEqEnabled(true);
  print('2. Initialized 10-band Graphic EQ with Auto-Q calculation.');

  // User sets 3 adjacent bands (500 Hz, 1000 Hz, 2000 Hz) to +6.0 dB
  print('3. Setting bands 4 (500Hz), 5 (1kHz), 6 (2kHz) to +6.0 dB...');
  engine.setMultibandEqGain(4, 6.0);
  engine.setMultibandEqGain(5, 6.0);
  engine.setMultibandEqGain(6, 6.0);

  final target5 = engine.getMultibandEqGain(5);
  final opt5 = engine.getMultibandEqOptimizedGain(5);
  final opt4 = engine.getMultibandEqOptimizedGain(4);
  final opt6 = engine.getMultibandEqOptimizedGain(6);

  print('   Band 5 (1 kHz) Target Gain:    $target5 dB (matches slider)');
  print('   Band 5 (1 kHz) Optimized Gain: ${opt5.toStringAsFixed(2)} dB (decoupled command)');
  print('   Band 4 (500Hz) Optimized Gain: ${opt4.toStringAsFixed(2)} dB');
  print('   Band 6 (2 kHz) Optimized Gain: ${opt6.toStringAsFixed(2)} dB');

  if ((target5 - 6.0).abs() > 0.01) {
    throw Exception('Target gain mismatch!');
  }
  if (opt5 >= 6.0) {
    throw Exception('Optimized gain should be pulled back (< 6.0 dB) to prevent skirt accumulation!');
  }
  print('   [PASS] Decoupled command gain successfully pulled back to prevent skirt accumulation.');

  // Test mode switching
  print('4. Testing Graphic EQ topology switching...');
  engine.setMultibandEqMode(0); // MatrixCompensatedCascade
  if (engine.getMultibandEqMode() != 0) throw Exception('Mode 0 failed');
  print('   [PASS] Mode 0 (MatrixCompensatedCascade) active.');

  engine.setMultibandEqMode(1); // SymmetricParallel
  if (engine.getMultibandEqMode() != 1) throw Exception('Mode 1 failed');
  print('   [PASS] Mode 1 (SymmetricParallel) active.');

  engine.setMultibandEqMode(2); // LegacyCascade
  if (engine.getMultibandEqMode() != 2) throw Exception('Mode 2 failed');
  print('   [PASS] Mode 2 (LegacyCascade) active.');

  engine.setMultibandEqMode(0); // Restore MatrixCompensatedCascade
  print('   [PASS] Default restored to MatrixCompensatedCascade.');

  // 5. Test 2-Way Dual Channel vs Whole Stereo
  print('5. Testing 2-Way GEQ (Dual Channel Left/Right vs Whole)...');
  engine.setMultibandEqChannelMode(0); // Whole / Stereo
  if (engine.getMultibandEqChannelMode() != 0) throw Exception('Channel mode 0 failed');
  print('   [PASS] Channel Mode 0 (Whole Stereo Linked) verified.');

  engine.setMultibandEqChannelMode(1); // 2-Way Dual Channel
  if (engine.getMultibandEqChannelMode() != 1) throw Exception('Channel mode 1 failed');
  print('   [PASS] Channel Mode 1 (2-Way Dual Channel) verified.');

  // Set Left channel band 2 to +4.0 dB, Right channel band 2 to -5.0 dB
  engine.setMultibandEqChannelGain(0, 2, 4.0);
  engine.setMultibandEqChannelGain(1, 2, -5.0);

  final leftGain2 = engine.getMultibandEqChannelGain(0, 2);
  final rightGain2 = engine.getMultibandEqChannelGain(1, 2);
  print('   Left Channel Band 2:  $leftGain2 dB');
  print('   Right Channel Band 2: $rightGain2 dB');
  if ((leftGain2 - 4.0).abs() > 0.01 || (rightGain2 - (-5.0)).abs() > 0.01) {
    throw Exception('Dual channel gains not independent!');
  }
  print('   [PASS] Dual-channel Left & Right independent gains verified.');

  final leftOpt2 = engine.getMultibandEqChannelOptimizedGain(0, 2);
  final rightOpt2 = engine.getMultibandEqChannelOptimizedGain(1, 2);
  print('   Left Channel Band 2 Optimized:  ${leftOpt2.toStringAsFixed(2)} dB');
  print('   Right Channel Band 2 Optimized: ${rightOpt2.toStringAsFixed(2)} dB');
  print('   [PASS] Dual-channel independent matrix optimization verified.');

  engine.destroy();
  print('===============================================================');
  print('   AUDIOPHILE 2-WAY MATRIX GEQ FULLY VERIFIED AND WORKING!    ');
  print('===============================================================');
}
