import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(List<String> args) async {
  final yt = YoutubeExplode();
  final videoIdStr = args.isNotEmpty ? args[0] : 'vbvyNnw8Qjg';

  print('================================================================');
  print('       TESTING DIRECT YOUTUBE STREAM EXTRACTION (YOUTUBE_EXPLODE)');
  print('================================================================');
  print('Target Video ID / URL: $videoIdStr\n');

  try {
    // 1. Resolve Video ID & Metadata
    final videoId = VideoId(videoIdStr);
    print('--> Fetching Video Metadata...');
    final video = await yt.videos.get(videoId);

    print('Title:       ${video.title}');
    print('Author:      ${video.author}');
    print('Duration:    ${video.duration?.inSeconds}s (${video.duration})');
    print('Upload Date: ${video.uploadDate}');
    print('Thumbnails:');
    print('  - Low:     ${video.thumbnails.lowResUrl}');
    print('  - Med:     ${video.thumbnails.mediumResUrl}');
    print('  - High:    ${video.thumbnails.highResUrl}');
    print('  - MaxRes:  ${video.thumbnails.maxResUrl}');
    print('');

    // 2. Fetch Stream Manifest
    print('--> Fetching Stream Manifest from YouTube...');
    final stopwatch = Stopwatch()..start();
    final manifest = await yt.videos.streams.getManifest(videoId);
    stopwatch.stop();
    print('Manifest resolved in ${stopwatch.elapsedMilliseconds}ms.');
    print('');

    // 3. Inspect Audio-Only Streams
    final audioStreams = manifest.audioOnly.toList();
    print('Found ${audioStreams.length} Audio-Only Streams:');
    print('----------------------------------------------------------------');
    for (var i = 0; i < audioStreams.length; i++) {
      final s = audioStreams[i];
      print('[$i] Tag/Itag: ${s.tag}');
      print('    Container: ${s.container.name.toUpperCase()}');
      print('    Audio Codec: ${s.audioCodec}');
      print('    Bitrate:   ${s.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps');
      print('    Size:      ${(s.size.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('    Direct URL: ${s.url}');
      print('');
    }

    // 4. Select Best Stream for Audiophile / Miniaudio Playback
    // - Highest bitrate AAC (m4a): native compatibility with standard AAC decoders
    // - Highest bitrate Opus (webm): often 160 kbps Opus for high fidelity
    final bestAudio = manifest.audioOnly.withHighestBitrate();
    print('----------------------------------------------------------------');
    print('--> Best Overall Audio Stream:');
    print('    Codec:     ${bestAudio.audioCodec}');
    print('    Container: ${bestAudio.container.name}');
    print('    Bitrate:   ${bestAudio.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps');
    print('    URL:       ${bestAudio.url}');
    print('');

    // Filter AAC specifically if engine prefers MP4/AAC
    final aacStreams = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
    if (aacStreams.isNotEmpty) {
      final bestAac = aacStreams.withHighestBitrate();
      print('--> Best AAC/MP4 Stream (Ideal for Miniaudio AAC Decoder):');
      print('    Tag:       ${bestAac.tag}');
      print('    Bitrate:   ${bestAac.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps');
      print('    URL:       ${bestAac.url}');
      print('');
    }

    // 5. Test Live HTTP Stream Availability & Range Request Test
    print('--> Testing Stream URL Availability with HTTP Request...');
    final testUrl = bestAudio.url;
    final headResponse = await http.head(testUrl);
    print('    HEAD Response Status: ${headResponse.statusCode}');
    print('    Content-Type:        ${headResponse.headers['content-type']}');
    print('    Content-Length:      ${headResponse.headers['content-length']} bytes');
    print('    Accept-Ranges:       ${headResponse.headers['accept-ranges']}');

    // Test byte-range request (first 64 KB for header inspection)
    final rangeResponse = await http.get(testUrl, headers: {'Range': 'bytes=0-65535'});
    print('    Range (0-65535) Status: ${rangeResponse.statusCode} (Expected 206 Partial Content)');
    print('    Bytes received:      ${rangeResponse.bodyBytes.length} bytes');

    print('\n[SUCCESS] Direct stream extraction and connectivity verified!');

  } catch (e, st) {
    print('\n[ERROR] Stream extraction failed: $e');
    print(st);
  } finally {
    yt.close();
  }
}
