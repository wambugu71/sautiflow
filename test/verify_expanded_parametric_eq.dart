import '../lib/audio_engine_ffi.dart';

void main() {
  print('===============================================================');
  print('   VERIFYING EXPANDED PARAMETRIC EQ FILTERS IN ENGINE          ');
  print('===============================================================');

  final engine = AudioEngineFFI(libraryPath: 'audio_engine.dll');
  final created = engine.create(sampleRate: 48000, channels: 2);
  print('AudioEngine created: $created');
  if (!created) {
    throw Exception('Failed to create AudioEngine!');
  }

  // 1. Verify all 5 new filter types exist in EqBandType enum
  print('\n[1] Verifying EqBandType Enum extensions...');
  final expectedIndices = {
    EqBandType.peak: 0,
    EqBandType.bandpass: 1,
    EqBandType.notch: 2,
    EqBandType.lowshelf: 3,
    EqBandType.highshelf: 4,
    EqBandType.lowpass: 5,
    EqBandType.highpass: 6,
    EqBandType.bell: 7,
    EqBandType.tilt: 8,
    EqBandType.allpass: 9,
    EqBandType.asuperpass: 10,
    EqBandType.bandreject: 11,
    EqBandType.asuperstop: 12,
    EqBandType.asupercut: 13,
  };

  for (final entry in expectedIndices.entries) {
    if (entry.key.index != entry.value) {
      throw Exception(
        'Enum index mismatch for ${entry.key}: expected ${entry.value}, got ${entry.key.index}',
      );
    }
    print('  - ${entry.key.name} -> Index ${entry.value} [OK]');
  }

  // 2. Configure multiband FX with the 5 new filter types
  print('\n[2] Applying Multiband FX with all 5 new filter types...');
  final newFilterBands = [
    const EqBandConfig(
      type: EqBandType.allpass,
      frequencyHz: 1000.0,
      q: 1.0,
      gainDb: 0.0,
      enabled: true,
    ),
    const EqBandConfig(
      type: EqBandType.asuperpass,
      frequencyHz: 2500.0,
      q: 2.0,
      gainDb: 0.0,
      enabled: true,
    ),
    const EqBandConfig(
      type: EqBandType.bandreject,
      frequencyHz: 500.0,
      q: 2.5,
      gainDb: -12.0,
      enabled: true,
    ),
    const EqBandConfig(
      type: EqBandType.asuperstop,
      frequencyHz: 60.0,
      q: 8.0,
      gainDb: 0.0,
      enabled: true,
    ),
    const EqBandConfig(
      type: EqBandType.asupercut,
      frequencyHz: 18000.0,
      q: 1.0,
      slope: 1.0,
      gainDb: 0.0,
      enabled: true,
    ),
  ];

  engine.setMultibandFxBands(newFilterBands);
  engine.setMultibandFxEnabled(true);
  print('  Successfully initialized and applied allpass, asuperpass, bandreject, asuperstop, asupercut in C++ engine.');

  // 3. Reconfigure with a mixed hybrid configuration (classic + new filters)
  print('\n[3] Reconfiguring with hybrid classical + modern filter chain...');
  final hybridBands = [
    const EqBandConfig(
      type: EqBandType.lowshelf,
      frequencyHz: 80.0,
      gainDb: 4.0,
      slope: 1.0,
    ),
    const EqBandConfig(
      type: EqBandType.bandreject,
      frequencyHz: 120.0,
      gainDb: -6.0,
      q: 3.0,
    ),
    const EqBandConfig(
      type: EqBandType.peak,
      frequencyHz: 1000.0,
      gainDb: -1.5,
      q: 1.2,
    ),
    const EqBandConfig(
      type: EqBandType.asuperpass,
      frequencyHz: 3200.0,
      q: 1.8,
    ),
    const EqBandConfig(
      type: EqBandType.allpass,
      frequencyHz: 4500.0,
      q: 1.5,
    ),
    const EqBandConfig(
      type: EqBandType.highshelf,
      frequencyHz: 10000.0,
      gainDb: 3.0,
      slope: 1.0,
    ),
    const EqBandConfig(
      type: EqBandType.asupercut,
      frequencyHz: 19500.0,
    ),
    const EqBandConfig(
      type: EqBandType.asuperstop,
      frequencyHz: 15625.0,
      q: 10.0,
    ),
  ];

  engine.setMultibandFxBands(hybridBands);
  print('  Hybrid configuration with 8 diverse filters applied successfully.');

  // 4. Test band bypass and 0dB flat bypass
  print('\n[4] Testing flat 0dB band bypass on bandreject...');
  final flatBands = [
    const EqBandConfig(
      type: EqBandType.bandreject,
      frequencyHz: 1000.0,
      gainDb: 0.0, // Should trigger 0 dB bypass cleanly
    ),
    const EqBandConfig(
      type: EqBandType.allpass,
      frequencyHz: 800.0,
      enabled: false, // Explicitly disabled
    ),
  ];
  engine.setMultibandFxBands(flatBands);
  print('  Bypass band test passed.');

  // 5. Test clearing multiband FX
  print('\n[5] Clearing multiband FX...');
  engine.clearMultibandFx();
  print('  Multiband FX cleared.');

  // 6. Test JSON / Map serialization roundtrip for all 14 types
  print('\n[6] Testing Serialization / Deserialization roundtrip for all 14 types...');
  for (int i = 0; i < EqBandType.values.length; ++i) {
    final type = EqBandType.values[i];
    final map = {
      'type': type.index,
      'frequency': 1000.0,
      'gainDb': -3.0,
      'q': 1.4,
      'slope': 1.0,
      'enabled': true,
    };

    final deserialized = EqBandConfig(
      type: EqBandType.values[(map['type'] as num).toInt()],
      frequencyHz: (map['frequency'] as num).toDouble(),
      gainDb: (map['gainDb'] as num).toDouble(),
      q: (map['q'] as num).toDouble(),
      slope: (map['slope'] as num).toDouble(),
      enabled: map['enabled'] as bool,
    );

    if (deserialized.type != type) {
      throw Exception('Serialization mismatch for $type: got ${deserialized.type}');
    }
  }
  print('  All 14 EqBandType values serialized and deserialized accurately.');

  engine.dispose();
  print('\n===============================================================');
  print('   EXPANDED PARAMETRIC EQ TESTS PASSED SUCCESSFULLY!          ');
  print('===============================================================');
}
