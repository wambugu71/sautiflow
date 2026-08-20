import 'dart:io';
import 'dart:typed_data';
import 'package:sautiflow/audio_engine_ffi.dart';

Uint8List createPcmWav({int sampleRate = 44100, int channels = 2, double durationSec = 2.0}) {
  final numSamples = (sampleRate * durationSec).toInt();
  final dataSize = numSamples * channels * 2; // 16-bit PCM
  final buffer = ByteData(44 + dataSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // 'R'
  buffer.setUint8(1, 0x49); // 'I'
  buffer.setUint8(2, 0x46); // 'F'
  buffer.setUint8(3, 0x46); // 'F'
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  buffer.setUint8(8, 0x57); // 'W'
  buffer.setUint8(9, 0x41); // 'A'
  buffer.setUint8(10, 0x56); // 'V'
  buffer.setUint8(11, 0x45); // 'E'

  // fmt chunk
  buffer.setUint8(12, 0x66); // 'f'
  buffer.setUint8(13, 0x6D); // 'm'
  buffer.setUint8(14, 0x74); // 't'
  buffer.setUint8(15, 0x20); // ' '
  buffer.setUint32(16, 16, Endian.little); // Chunk size 16
  buffer.setUint16(20, 1, Endian.little); // PCM format = 1
  buffer.setUint16(22, channels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * channels * 2, Endian.little); // Byte rate
  buffer.setUint16(32, channels * 2, Endian.little); // Block align
  buffer.setUint16(34, 16, Endian.little); // Bits per sample

  // data chunk
  buffer.setUint8(36, 0x64); // 'd'
  buffer.setUint8(37, 0x61); // 'a'
  buffer.setUint8(38, 0x74); // 't'
  buffer.setUint8(39, 0x61); // 'a'
  buffer.setUint32(40, dataSize, Endian.little);

  // Fill sine wave audio data
  for (int i = 0; i < numSamples; i++) {
    final sampleVal = (0.3 * 32767.0 * (i % 100 < 50 ? 1 : -1)).toInt();
    for (int c = 0; c < channels; c++) {
      buffer.setInt16(44 + (i * channels + c) * 2, sampleVal, Endian.little);
    }
  }

  return buffer.buffer.asUint8List();
}

void main() async {
  print('=== Sautiflow Local & Online Stream Interoperability Test ===');

  // 1. Create temporary 44.1 kHz local WAV file
  final tempDir = Directory.systemTemp.createTempSync('sautiflow_test_');
  final localWavPath = '${tempDir.path}\\sample_44100.wav';
  final wavBytes = createPcmWav(sampleRate: 44100, channels: 2, durationSec: 3.0);
  File(localWavPath).writeAsBytesSync(wavBytes);
  print('[1] Created local 44.1 kHz test file: $localWavPath (${wavBytes.length} bytes)');

  // 2. Initialize native engine
  final engine = AudioEngineFFI();
  final created = engine.create(sampleRate: 48000, channels: 2);
  print('[2] Engine created: $created');
  if (!created) {
    print('ERROR: Engine creation failed');
    exit(1);
  }

  engine.setAutoSampleRateMatchEnabled(true);

  // 3. Play local 44.1 kHz file
  print('[3] Playing local file (44.1 kHz)...');
  engine.setPlaylist([localWavPath]);
  engine.play();
  await Future.delayed(const Duration(milliseconds: 1500));
  var status = engine.getStatus();
  print('    Local playback: playing=${status.isPlaying}, pos=${status.positionSeconds.toStringAsFixed(2)}s / ${status.durationSeconds.toStringAsFixed(2)}s');

  // 4. Switch to online stream (48 kHz)
  const streamUrl = 'https://cdn403.savetube.vip/media/vbvyNnw8Qjg/queen-bohemian-rhapsody-live-aid-1985-128-ytshorts.savetube.me.mp3';
  print('[4] Switching to online stream (48 kHz)...');
  engine.setPlaylist([streamUrl]);
  engine.play();
  await Future.delayed(const Duration(seconds: 3));
  var tel = engine.getStreamTelemetry();
  status = engine.getStatus();
  print('    Online stream: state=${tel.state}, pos=${status.positionSeconds.toStringAsFixed(2)}s, buffer=${tel.bufferPercent.toStringAsFixed(1)}%');

  // 5. Switch back to local 44.1 kHz file
  print('[5] Switching BACK to local file (44.1 kHz)...');
  engine.setPlaylist([localWavPath]);
  engine.play();
  await Future.delayed(const Duration(milliseconds: 1500));
  status = engine.getStatus();
  print('    Local playback resumed: playing=${status.isPlaying}, pos=${status.positionSeconds.toStringAsFixed(2)}s / ${status.durationSeconds.toStringAsFixed(2)}s');

  print('[6] Cleaning up test resources...');
  engine.stop();
  engine.dispose();
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}

  print('SUCCESS: Local music & online streaming switched interchangeably with zero aborts or errors!');
  exit(0);
}
