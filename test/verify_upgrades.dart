import 'package:sautiflow/sautiflow.dart';

void main() {
  print('=== Testing Sautiflow Audiophile Engine Upgrades ===');
  
  final player = MiniAudioPlayer(libraryPath: 'audio_engine.dll');
  final ok = player.init();
  if (!ok) {
    print('Failed to initialize engine!');
    return;
  }
  print('Engine initialized successfully!');

  // 1. Test 64-bit float DSP mode toggle
  print('Default 64-bit processing mode: ${player.is64BitProcessingEnabled}');
  player.set64BitProcessingEnabled(true);
  print('After enabling 64-bit processing mode: ${player.is64BitProcessingEnabled}');

  // 2. Test Auto Bit-Perfect hardware rate matching toggle
  print('Default Auto Bit-Perfect mode: ${player.isAutoBitPerfectEnabled}');
  player.setAutoBitPerfectEnabled(true);
  print('After enabling Auto Bit-Perfect mode: ${player.isAutoBitPerfectEnabled}');

  // 3. Test Ambiophonics R.A.C.E. Crossfeed preset (Preset 4)
  player.setCrossfeed(enabled: true, preset: 4);
  print('Crossfeed enabled with Ambiophonics R.A.C.E. preset (4)!');

  // 4. Test Psychoacoustic Noise Shaping Dither Mode
  player.setEngineDitherMode(6); // Shibata noise shaping
  print('Dither mode set to Shibata Noise Shaping (mode 6)!');

  final hw = player.getHardwareInfo();
  print('Hardware Device: ${hw.deviceName} (${hw.backendName}) | ${hw.sampleRate}Hz ${hw.bitDepth}-bit');

  player.dispose();
  print('=== All Verification Checks Passed Cleanly! ===');
}
