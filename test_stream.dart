import 'dart:async';

import 'package:sautiflow/sautiflow.dart';

class StreamDemo {
  final MiniAudioPlayer player = MiniAudioPlayer();
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<String>? _logSub;

  Future<void> start() async {
    player.init();

    _statusSub = player.statusStream.listen((s) {
      print(
        'playing=${s.isPlaying} '
        'pos=${s.positionSeconds.toStringAsFixed(2)} '
        'dur=${s.durationSeconds.toStringAsFixed(2)}',
      );
    });

    _logSub = player.logStream.listen((msg) {
      print('[engine] $msg');
    });

    try {
      await player.pushStream(
        url:
            'https://cdn402.savetube.vip/media/k07dNNU-adw/mejja-toxic-lyrikali-manifest-official-video-128-ytshorts.savetube.me.mp3',
      );
      // Completes when stream ends.
    } catch (e) {
      print('pushStream failed: $e');
    }
  }

  void stop() {
    player.stop();
  }

  Future<void> dispose() async {
    await _statusSub?.cancel();
    await _logSub?.cancel();
    player.dispose();
  }
}
