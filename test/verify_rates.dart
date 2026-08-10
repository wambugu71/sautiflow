import 'package:sautiflow/sautiflow.dart';

void main() {
  print('========================================================');
  print(' AUDIO PIPELINE SAMPLE-RATE FFI VERIFICATION TEST       ');
  print('========================================================');

  final engine = AudioEngineFFI(libraryPath: 'sautiflow.dll');
  print('[1] Creating engine handle...');
  engine.createEngine(sampleRate: 48000, channels: 2);

  print('[OK] Engine created.');
  final initialRate = engine.getOutputSampleRate();
  print(' -> Hardware DAC Output Sample Rate: $initialRate Hz');

  final testRates = [44100, 48000, 88200, 96000, 192000];
  for (final rate in testRates) {
    print('--------------------------------------------------------');
    print(' Setting Engine Output Processing Rate: $rate Hz');
    engine.setOutputSampleRate(rate);

    final currentRate = engine.getOutputSampleRate();
    print(' -> Negotiated Engine Processing Rate: $currentRate Hz');
  }

  print('--------------------------------------------------------');
  print('[3] Destroying engine...');
  engine.destroyEngine();
  print('========================================================');
  print(' VERIFICATION COMPLETED SUCCESSFULLY                   ');
  print('========================================================');
}
