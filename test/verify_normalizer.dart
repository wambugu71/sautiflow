import 'dart:io';
import 'package:sautiflow/audio_engine_ffi.dart';

void main() {
  final ffi = AudioEngineFFI(libraryPath: 'sautiflow.dll');
  if (!ffi.create(sampleRate: 48000, channels: 2)) {
    stderr.writeln('FAIL: engine creation');
    exit(1);
  }

  var ok = true;
  void check(String name, bool cond) {
    print('${cond ? "PASS" : "FAIL"}: $name');
    if (!cond) ok = false;
  }

  // Default state
  check('normalizer disabled by default', ffi.getLoudnessNormalizerEnabled() == false);
  check('default target is -14 LUFS', (ffi.getLoudnessNormalizerTarget() - (-14.0)).abs() < 0.01);

  // Enable + set target
  ffi.setLoudnessNormalizerEnabled(true);
  check('enable round-trip', ffi.getLoudnessNormalizerEnabled() == true);

  ffi.setLoudnessNormalizerTarget(-18.0);
  check('target round-trip', (ffi.getLoudnessNormalizerTarget() - (-18.0)).abs() < 0.01);

  // Clamping [-30, -6]
  ffi.setLoudnessNormalizerTarget(-100.0);
  check('target clamps to -30', (ffi.getLoudnessNormalizerTarget() - (-30.0)).abs() < 0.01);
  ffi.setLoudnessNormalizerTarget(5.0);
  check('target clamps to -6', (ffi.getLoudnessNormalizerTarget() - (-6.0)).abs() < 0.01);

  // Disable
  ffi.setLoudnessNormalizerEnabled(false);
  check('disable round-trip', ffi.getLoudnessNormalizerEnabled() == false);

  // Meter still functional alongside
  final m = ffi.getLoudnessMetrics();
  print('metrics snapshot: momentary=${m.momentaryLUFS} shortTerm=${m.shortTermLUFS} integrated=${m.integratedLUFS}');
  check('metrics readable', m.momentaryLUFS <= 0.0);

  print(ok ? 'ALL TESTS PASSED' : 'TESTS FAILED');
  exit(ok ? 0 : 1);
}
