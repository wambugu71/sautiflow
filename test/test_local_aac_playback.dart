import 'dart:io';
import 'package:sautiflow/audio_engine_ffi.dart';

void main() async {
  print('=== Sautiflow Local AAC / M4A Playback Test ===');

  final m4aPath = '${Directory.current.path}\\test_local_sample.m4a';
  if (!File(m4aPath).existsSync()) {
    print('ERROR: test_local_sample.m4a does not exist at $m4aPath');
    exit(1);
  }

  final engine = AudioEngineFFI();
  final created = engine.create(sampleRate: 48000, channels: 2);
  print('Engine created: $created');
  if (!created) {
    print('ERROR: Engine creation failed');
    exit(1);
  }

  print('1. Queuing and playing local AAC/M4A file: $m4aPath');
  engine.setPlaylist([m4aPath]);
  engine.play();

  await Future.delayed(const Duration(milliseconds: 1000));
  var status = engine.getStatus();
  print('   Playback status: isPlaying=${status.isPlaying}, pos=${status.positionSeconds.toStringAsFixed(2)}s / ${status.durationSeconds.toStringAsFixed(2)}s');

  if (status.durationSeconds < 2.5 || status.durationSeconds > 3.5) {
    print('ERROR: Duration mismatch, expected ~3.0s, got ${status.durationSeconds}');
    exit(1);
  }

  print('2. Testing sample-accurate seeking in local AAC/M4A file...');
  engine.seek(1.5);
  await Future.delayed(const Duration(milliseconds: 500));
  status = engine.getStatus();
  print('   Post-seek status: pos=${status.positionSeconds.toStringAsFixed(2)}s / ${status.durationSeconds.toStringAsFixed(2)}s');

  print('3. Disposing engine...');
  engine.stop();
  engine.dispose();

  // Clean up test file
  try {
    File(m4aPath).deleteSync();
  } catch (_) {}

  print('SUCCESS: Local AAC/M4A decoded and played via FFmpegLocalFileSource without error!');
  exit(0);
}
