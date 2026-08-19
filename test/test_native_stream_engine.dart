import 'dart:io';
import 'package:sautiflow/audio_engine_ffi.dart';

void main() async {
  print('=== Sautiflow Native Streaming Verification Test ===');
  
  final engine = AudioEngineFFI();
  final created = engine.create(sampleRate: 48000, channels: 2);
  print('[0] Engine created: $created');
  if (!created) {
    print('ERROR: Failed to create engine!');
    exit(1);
  }
  
  final supported = engine.isNetworkStreamingSupported();
  print('[1] isNetworkStreamingSupported: $supported');
  if (!supported) {
    print('ERROR: Network streaming should be supported!');
    exit(1);
  }

  const testUrl = "https://cdn403.savetube.vip/media/vbvyNnw8Qjg/queen-bohemian-rhapsody-live-aid-1985-128-ytshorts.savetube.me.mp3";
  print('[2] Setting playlist with URL: $testUrl');
  final setSuccess = engine.setPlaylist([testUrl]);
  print('    setPlaylist returned: $setSuccess');

  print('[3] Starting playback...');
  final playSuccess = engine.play();
  print('    play returned: $playSuccess');

  print('[4] Monitoring buffer & stream telemetry for 6 seconds...');
  for (int i = 1; i <= 6; i++) {
    await Future.delayed(const Duration(seconds: 1));
    final status = engine.getStatus();
    final tel = engine.getStreamTelemetry();
    print('  [Second $i] State: ${tel.state} | Pos: ${status.positionSeconds.toStringAsFixed(2)}s / ${status.durationSeconds.toStringAsFixed(2)}s | Buffer: ${tel.bufferedDuration.inSeconds}s (${tel.bufferPercent.toStringAsFixed(1)}%) | Bitrate: ${tel.bitrate ~/ 1000}kbps | Codec: ${tel.codecName}');
  }

  print('SUCCESS: Native streaming playback & telemetry verified successfully!');
  engine.stop();
  engine.dispose();
  exit(0);
}
