import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/audio_engine_ffi.dart';

void main() {
  test('Backend selection and hardware info verification', () {
    final engine = AudioEngineFFI(libraryPath: 'sautiflow.dll');
    final ok = engine.create(sampleRate: 48000, channels: 2);
    expect(ok, isTrue);

    final initialBackend = engine.getOutputBackend();
    print('Initial backend: $initialBackend');

    final hwInfo = engine.getHardwareInfo();
    print('Backend name: ${hwInfo.backendName}');
    print('Device name: ${hwInfo.deviceName}');
    print('DSP hardware: "${hwInfo.dspHardware}"');
    print('SoC name: "${hwInfo.socName}"');
    print('Sample rate: ${hwInfo.sampleRate}');
    print('Channels: ${hwInfo.channels}');
    print('Bit depth: ${hwInfo.bitDepth}');
    print('Format: ${hwInfo.outputFormat}');
    print('Latency ms: ${hwInfo.latencyMs}');
    print('Exclusive mode: ${hwInfo.isExclusiveMode}');
    print('Direct PCM: ${hwInfo.isDirectPcm}');

    expect(hwInfo.backendName.isNotEmpty, isTrue);
    expect(hwInfo.sampleRate, equals(48000));
    expect(hwInfo.channels, equals(2));
    expect(hwInfo.dspHardware.isNotEmpty, isTrue);
    expect(hwInfo.socName.isNotEmpty, isTrue);

    engine.dispose();
  });
}
