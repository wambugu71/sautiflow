// Dithering DSP verification: exercises the standalone resampler's dithered
// path (int -> f32 -> resample -> dither/quantize -> int) and validates the
// actual numerics, not just API plumbing.
//
// Run:  dart run test/dither_dsp_test.dart
import 'dart:ffi' as dfi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:sautiflow/audio_engine_ffi.dart' show AudioFormat;
import 'package:sautiflow/src/miniaudio_filters.dart';

const int sampleRate = 48000;
const int channels = 1;
const int chunkFrames = 4096;

int passed = 0;
int failed = 0;

void check(bool cond, String label) {
  if (cond) {
    passed++;
    print('  PASS  $label');
  } else {
    failed++;
    print('  FAIL  $label');
  }
}

dfi.Pointer<dfi.Int16> allocInt16(int samples) => malloc<dfi.Int16>(samples);

void fill(dfi.Pointer<dfi.Int16> p, int samples, int value) {
  for (int i = 0; i < samples; i++) {
    p[i] = value;
  }
}

List<int> runChunk(
    MiniaudioFiltersFFI filters, dfi.Pointer<dfi.Void> rs, int inputValue) {
  final inP = allocInt16(chunkFrames);
  fill(inP, chunkFrames, inputValue);
  final outP = allocInt16(chunkFrames);
  final inCount = malloc<dfi.Uint64>()..value = chunkFrames;
  final outCount = malloc<dfi.Uint64>()..value = chunkFrames;

  List<int> once() {
    final ok = filters.processResampler(
        rs, inP.cast(), inCount, outP.cast(), outCount);
    if (ok != true) {
      throw StateError('processResampler failed');
    }
    final produced = outCount.value;
    return List<int>.generate(produced, (i) => outP[i]);
  }

  // Pump twice: the linear resampler has ~1 frame of latency, so the first
  // pass after an input step contains a transition frame. The second pass is
  // steady-state.
  once();
  final result = once();

  malloc.free(inP);
  malloc.free(outP);
  malloc.free(inCount);
  malloc.free(outCount);
  return result;
}

/// Creates a resampler and pumps one warmup chunk so latency/buffering
/// settles; returns the handle.
dfi.Pointer<dfi.Void> makeResampler(
    MiniaudioFiltersFFI filters, DitherMode mode) {
  final rs = filters.createResampler(AudioFormat.s16, channels, sampleRate,
      sampleRate, ResampleAlgorithm.miniaudioLinear, mode);
  if (rs == dfi.nullptr) {
    throw StateError('createResampler(${mode.name}) returned null');
  }
  runChunk(filters, rs, 0); // warmup
  return rs;
}

void main() {
  final filters = MiniaudioFiltersFFI(libraryPath: 'audio_engine.dll');

  print('=== Dithering DSP Verification (standalone resampler path) ===\n');

  // ---------------------------------------------------------------
  // 1. Mode none: bit-exact passthrough on the integer fast path.
  // ---------------------------------------------------------------
  print('[1] DitherMode.none -> bit-exact passthrough');
  {
    final rs = makeResampler(filters, DitherMode.none);
    const v = -12345;
    final out = runChunk(filters, rs, v);
    check(out.isNotEmpty, 'produces frames');
    check(out.every((s) => s == v), 'every sample == $v (bit-exact)');
    filters.destroyResampler(rs);
  }

  // ---------------------------------------------------------------
  // 2. TPDF statistics at DC 0:
  //    triangular dither of 2 LSB p-p rounds to {-1,0,+1} LSB with
  //    P(0)=3/4, P(+1)=P(-1)=1/8. Allow generous tolerance.
  // ---------------------------------------------------------------
  print('[2] DitherMode.triangle -> triangular statistics @ DC 0');
  {
    final rs = makeResampler(filters, DitherMode.triangle);
    final out = runChunk(filters, rs, 0);
    check(out.every((s) => s >= -1 && s <= 1),
        'all samples within +-1 LSB (got range ${out.reduce(math.min)}..${out.reduce(math.max)})');
    final zeros = out.where((s) => s == 0).length / out.length;
    final plus = out.where((s) => s == 1).length / out.length;
    final minus = out.where((s) => s == -1).length / out.length;
    check(zeros > 0.65 && zeros < 0.85,
        'P(0) ~ 0.75 (got ${zeros.toStringAsFixed(3)})');
    check(plus > 0.06 && plus < 0.19,
        'P(+1) ~ 0.125 (got ${plus.toStringAsFixed(3)})');
    check(minus > 0.06 && minus < 0.19,
        'P(-1) ~ 0.125 (got ${minus.toStringAsFixed(3)})');
    filters.destroyResampler(rs);
  }

  // ---------------------------------------------------------------
  // 3. RPDF at DC 0: uniform 1 LSB p-p dither decorrelates without
  //    adding energy beyond the rounding step -> nearly all zeros.
  // ---------------------------------------------------------------
  print('[3] DitherMode.rectangle -> decorrelated, bounded @ DC 0');
  {
    final rs = makeResampler(filters, DitherMode.rectangle);
    final out = runChunk(filters, rs, 0);
    check(out.every((s) => s >= -1 && s <= 1),
        'all samples within +-1 LSB (got range ${out.reduce(math.min)}..${out.reduce(math.max)})');
    final nonzeros = out.where((s) => s != 0).length;
    check(nonzeros < out.length * 0.02,
        'RPDF stays inside the same LSB step (<2% toggles, got $nonzeros/${out.length})');
    filters.destroyResampler(rs);
  }

  // ---------------------------------------------------------------
  // 4. Noise shaping (Shibata): error feedback keeps the output
  //    locked to the input long-term but permits a few LSBs of
  //    high-pass shaped noise. Must stay bounded and active.
  // ---------------------------------------------------------------
  print('[4] DitherMode.shibata -> bounded shaped noise @ DC 0');
  {
    final rs = makeResampler(filters, DitherMode.shibata);
    final out = runChunk(filters, rs, 0);
    final maxAbs = out.map((s) => s.abs()).reduce(math.max);
    check(maxAbs <= 4, '|error| bounded <= 4 LSB (got $maxAbs)');
    check(out.any((s) => s != 0), 'shaper is active (non-constant output)');
    final mean = out.fold<int>(0, (a, b) => a + b) / out.length;
    check(mean.abs() < 0.05,
        'long-term mean tracks DC input (got ${mean.toStringAsFixed(4)})');
    filters.destroyResampler(rs);
  }

  // ---------------------------------------------------------------
  // 5. Modes actually differ from each other (wiring sanity).
  // ---------------------------------------------------------------
  print('[5] Mode outputs differ (none vs triangle vs shibata)');
  {
    final outs = <DitherMode, List<int>>{};
    for (final m in [DitherMode.none, DitherMode.triangle, DitherMode.shibata]) {
      final rs = makeResampler(filters, m);
      outs[m] = runChunk(filters, rs, 0);
      filters.destroyResampler(rs);
    }
    bool differs(List<int> a, List<int> b) {
      for (int i = 0; i < math.min(a.length, b.length); i++) {
        if (a[i] != b[i]) return true;
      }
      return false;
    }

    check(differs(outs[DitherMode.none]!, outs[DitherMode.triangle]!),
        'none != triangle');
    check(differs(outs[DitherMode.triangle]!, outs[DitherMode.shibata]!),
        'triangle != shibata');
  }

  // ---------------------------------------------------------------
  // 6. Full-scale safety: +full-scale DC through every dither mode
  //    must never wrap around or exceed s16 bounds.
  // ---------------------------------------------------------------
  print('[6] Full-scale clamp safety across all modes');
  {
    for (final m in DitherMode.values) {
      final rs = makeResampler(filters, m);
      final out = runChunk(filters, rs, 32767);
      final inRange = out.every((s) => s >= -32768 && s <= 32767);
      // Wraparound would slam to the opposite rail (-32768); shaped noise
      // may legitimately overshoot a few LSBs but never the whole range.
      check(inRange && out.every((s) => s > -8),
          '${m.name}: bounded near full scale, no wrap (min ${out.reduce(math.min)}, max ${out.reduce(math.max)})');
      filters.destroyResampler(rs);
    }
  }

  // ---------------------------------------------------------------
  // 7. Determinism: identical runs reproduce identical sequences
  //    (fixed per-channel PRNG seeds).
  // ---------------------------------------------------------------
  print('[7] Reproducibility');
  {
    List<int> once() {
      final rs = makeResampler(filters, DitherMode.triangle);
      final out = runChunk(filters, rs, 512);
      filters.destroyResampler(rs);
      return out;
    }

    final a = once();
    final b = once();
    check(a.length == b.length && _listEquals(a, b),
        'two identical runs produce identical output');
  }

  print('\n=== $passed passed, $failed failed ===');
  if (failed > 0) {
    throw StateError('$failed dither DSP checks failed');
  }
}

bool _listEquals(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
