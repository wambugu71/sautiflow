import 'dart:io';
import 'dart:math';
import 'package:sautiflow/audio_engine_ffi.dart';

// Generates a 12s stereo WAV of pink-ish noise at ~-6 dBFS.
String _makeLoudWav(String path) {
  final sampleRate = 48000;
  final seconds = 12;
  final frames = sampleRate * seconds;
  final bytes = BytesBuilder();

  final dataBytes = frames * 2 * 2; // stereo, s16
  bytes.add('RIFF'.codeUnits);
  bytes.add(_u32(36 + dataBytes));
  bytes.add('WAVE'.codeUnits);
  bytes.add('fmt '.codeUnits);
  bytes.add(_u32(16));
  bytes.add(_u16(1)); // PCM
  bytes.add(_u16(2)); // stereo
  bytes.add(_u32(sampleRate));
  bytes.add(_u32(sampleRate * 4));
  bytes.add(_u16(4));
  bytes.add(_u16(16));
  bytes.add('data'.codeUnits);
  bytes.add(_u32(dataBytes));

  final rnd = Random(42);
  double b0 = 0, b1 = 0, b2 = 0;
  for (var i = 0; i < frames; i++) {
    // Pink-ish noise via Paul Kellet filter, scaled to ~0.5 amplitude (-6 dBFS)
    final w = rnd.nextDouble() * 2.0 - 1.0;
    b0 = 0.99765 * b0 + w * 0.0990460;
    b1 = 0.96300 * b1 + w * 0.2965164;
    b2 = 0.57000 * b2 + w * 1.0526913;
    var s = (b0 + b1 + b2 + w * 0.1848) * 0.30;
    if (s > 0.95) s = 0.95;
    if (s < -0.95) s = -0.95;
    final v = (s * 32767).round();
    bytes.add(_u16(v & 0xFFFF)); // L
    bytes.add(_u16(v & 0xFFFF)); // R
  }
  File(path).writeAsBytesSync(bytes.toBytes());
  return path;
}

List<int> _u32(int v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255];
List<int> _u16(int v) => [v & 255, (v >> 8) & 255];

void main() async {
  var ok = true;
  void check(String name, bool cond) {
    print('${cond ? "PASS" : "FAIL"}: $name');
    if (!cond) ok = false;
  }

  final wavPath = _makeLoudWav('${Directory.systemTemp.path}\\agc_norm_test.wav');
  print('test wav: $wavPath');

  final ffi = AudioEngineFFI(libraryPath: 'sautiflow.dll');
  if (!ffi.create(sampleRate: 48000, channels: 2)) {
    stderr.writeln('FAIL: engine creation');
    exit(1);
  }

  // Normalizer ON, loudness meter UI toggle OFF — proves meter auto-runs
  // and gain is applied in the audio path.
  ffi.setLoudnessNormalizerEnabled(true);
  ffi.setLoudnessNormalizerTarget(-14.0);
  check('normalizer enabled', ffi.getLoudnessNormalizerEnabled());

  ffi.setPlaylist([wavPath]);
  check('playlist set', true);
  if (!await _play(ffi)) {
    stderr.writeln('FAIL: could not start playback (no audio device?)');
    exit(1);
  }

  // Wait for integrated LUFS to accumulate (>5s of audio analyzed)
  double integrated = -100;
  for (var i = 0; i < 200; i++) {
    await Future.delayed(Duration(milliseconds: 100));
    integrated = ffi.getLoudnessMetrics().integratedLUFS;
    if (integrated > -70) break;
  }
  print('integrated LUFS while playing: $integrated');
  check('meter runs with normalizer on (meter toggle off)', integrated > -70);

  // Source is loud (~-5 LUFS); target -14 -> expect ~-9 dB attenuation.
  final gainDb = ffi.getLoudnessNormalizerGainDb();
  print('applied normalizer gain: $gainDb dB (integrated=${ffi.getLoudnessMetrics().integratedLUFS})');
  check('normalizer gain attenuates loud source', gainDb < -4.0 && gainDb > -12.0);

  // Applied gain should bring measured loudness near target:
  final correctedLufs = ffi.getLoudnessMetrics().integratedLUFS + gainDb;
  print('loudness after correction: $correctedLufs LUFS (target -14)');
  check('corrected loudness within 1.5 LU of target', (correctedLufs - (-14.0)).abs() < 1.5);

  // Disable -> gain should ramp back to ~0
  ffi.setLoudnessNormalizerEnabled(false);
  for (var i = 0; i < 60; i++) {
    await Future.delayed(Duration(milliseconds: 50));
    if (ffi.getLoudnessNormalizerGainDb().abs() < 0.3) break;
  }
  final gainAfterOff = ffi.getLoudnessNormalizerGainDb();
  print('gain after disable: $gainAfterOff dB');
  check('gain ramps back to 0 when disabled', gainAfterOff.abs() < 0.5);

  ffi.stop();
  try {
    File(wavPath).deleteSync();
  } catch (_) {}
  print(ok ? 'ALL TESTS PASSED' : 'TESTS FAILED');
  exit(ok ? 0 : 1);
}

Future<bool> _play(AudioEngineFFI ffi) async {
  for (var i = 0; i < 20; i++) {
    if (ffi.play()) return true;
    await Future.delayed(Duration(milliseconds: 100));
  }
  return false;
}
