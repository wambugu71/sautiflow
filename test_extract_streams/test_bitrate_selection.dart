import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum AudioQualityPreset {
  low,        // ~50 kbps (Data saver / 2G/3G / Tag 249 Opus)
  medium,     // ~70-128 kbps (Standard mobile / Tag 250 Opus or Tag 140 AAC)
  high,       // ~128-160 kbps (Tag 140 AAC or Tag 251 Opus)
  audiophile, // Highest available bitrate (usually Tag 251 Opus ~160 kbps)
}

class AudioStreamSelector {
  static AudioOnlyStreamInfo selectStream(
    StreamManifest manifest, {
    AudioQualityPreset quality = AudioQualityPreset.audiophile,
    bool preferAac = false,
  }) {
    final audioStreams = manifest.audioOnly.toList();
    if (audioStreams.isEmpty) {
      throw Exception('No audio-only streams found in manifest.');
    }

    // Sort ascending by bitrate
    audioStreams.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));

    if (preferAac) {
      final aacStreams = audioStreams.where((s) => s.container == StreamContainer.mp4).toList();
      if (aacStreams.isNotEmpty) {
        switch (quality) {
          case AudioQualityPreset.low:
            return aacStreams.first; // Lowest AAC
          case AudioQualityPreset.medium:
          case AudioQualityPreset.high:
          case AudioQualityPreset.audiophile:
            return aacStreams.last;  // Highest AAC (usually 128 kbps Tag 140)
        }
      }
    }

    switch (quality) {
      case AudioQualityPreset.low:
        // Return lowest bitrate stream (usually ~50 kbps Opus Tag 249)
        return audioStreams.first;

      case AudioQualityPreset.medium:
        // Pick stream around 70 - 128 kbps
        final midStreams = audioStreams.where((s) => s.bitrate.kiloBitsPerSecond >= 60 && s.bitrate.kiloBitsPerSecond <= 130).toList();
        return midStreams.isNotEmpty ? midStreams.first : audioStreams[audioStreams.length ~/ 2];

      case AudioQualityPreset.high:
        // Pick high stream (~128 - 140 kbps)
        final highStreams = audioStreams.where((s) => s.bitrate.kiloBitsPerSecond >= 120).toList();
        return highStreams.isNotEmpty ? highStreams.first : audioStreams.last;

      case AudioQualityPreset.audiophile:
        // Maximum bitrate
        return audioStreams.last;
    }
  }
}

void main() async {
  final yt = YoutubeExplode();
  final videoId = VideoId('vbvyNnw8Qjg'); // Bohemian Rhapsody

  print('================================================================');
  print('       TESTING AUDIO BITRATE SELECTION & TIERS');
  print('================================================================');

  final manifest = await yt.videos.streams.getManifest(videoId);
  final allAudio = manifest.audioOnly.toList();

  print('Available Audio Streams in Manifest:');
  for (var s in allAudio) {
    print('  - Tag ${s.tag.toString().padRight(4)} | ${s.container.name.toUpperCase().padRight(5)} | ${s.audioCodec.padRight(12)} | ${s.bitrate.kiloBitsPerSecond.toStringAsFixed(1).padLeft(5)} kbps | Size: ${(s.size.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB');
  }

  print('\n---------------- Preset Selections ----------------');
  for (var preset in AudioQualityPreset.values) {
    final stream = AudioStreamSelector.selectStream(manifest, quality: preset);
    print('[${preset.name.toUpperCase().padRight(10)}] -> Tag: ${stream.tag} | Codec: ${stream.audioCodec} | Bitrate: ${stream.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps | Container: ${stream.container.name}');
  }

  print('\n[PREFER AAC NATIVE] ->');
  final aacStream = AudioStreamSelector.selectStream(manifest, quality: AudioQualityPreset.audiophile, preferAac: true);
  print('  Tag: ${aacStream.tag} | Bitrate: ${aacStream.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps | Container: ${aacStream.container.name}');

  yt.close();
}
