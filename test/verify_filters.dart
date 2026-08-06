import 'package:sautiflow/sautiflow.dart';

void main() {
  print('=== Testing Miniaudio Filter FFI Classes ===');

  final ffi = MiniaudioFiltersFFI(libraryPath: 'audio_engine.dll');

  print('1. Testing Band-Pass Filters (BPF2 & BPF)...');
  final bpf2 = MiniaudioBpf2(ffi, AudioFormat.f32, 2, 44100, 1000.0, 1.0);
  print('MiniaudioBpf2 initialized: ${bpf2.isInitialized}');
  bpf2.reinit(AudioFormat.f32, 2, 48000, 1200.0, 0.707);
  bpf2.dispose();

  final bpf = MiniaudioBpf(ffi, AudioFormat.f32, 2, 44100, 1000.0, 4);
  print('MiniaudioBpf initialized: ${bpf.isInitialized}');
  bpf.reinit(AudioFormat.f32, 2, 48000, 1200.0, 4);
  bpf.dispose();

  print('2. Testing Notch Filter (Notch2)...');
  final notch2 = MiniaudioNotch2(ffi, AudioFormat.f32, 2, 44100, 1.0, 60.0);
  print('MiniaudioNotch2 initialized: ${notch2.isInitialized}');
  notch2.reinit(AudioFormat.f32, 2, 48000, 1.0, 50.0);
  notch2.dispose();

  print('3. Testing Peaking EQ Filter (Peak2)...');
  final peak2 = MiniaudioPeak2(ffi, AudioFormat.f32, 2, 44100, 3.0, 1.0, 1000.0);
  print('MiniaudioPeak2 initialized: ${peak2.isInitialized}');
  peak2.reinit(AudioFormat.f32, 2, 48000, 6.0, 1.0, 2000.0);
  peak2.dispose();

  print('4. Testing Low Shelf Filter (Loshelf2)...');
  final loshelf2 = MiniaudioLoshelf2(ffi, AudioFormat.f32, 2, 44100, 4.0, 1.0, 250.0);
  print('MiniaudioLoshelf2 initialized: ${loshelf2.isInitialized}');
  loshelf2.reinit(AudioFormat.f32, 2, 48000, 2.0, 1.0, 300.0);
  loshelf2.dispose();

  print('5. Testing High Shelf Filter (Hishelf2)...');
  final hishelf2 = MiniaudioHishelf2(ffi, AudioFormat.f32, 2, 44100, 3.0, 1.0, 8000.0);
  print('MiniaudioHishelf2 initialized: ${hishelf2.isInitialized}');
  hishelf2.reinit(AudioFormat.f32, 2, 48000, 5.0, 1.0, 10000.0);
  hishelf2.dispose();

  print('=== All Miniaudio Filter FFI Tests Passed! ===');
}
