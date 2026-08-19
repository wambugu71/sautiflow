import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(List<String> args) async {
  final ytmusic = YTMusic();
  final ytExplode = YoutubeExplode();

  final searchQuery = args.isNotEmpty ? args.join(' ') : 'Bohemian Rhapsody Queen';

  print('================================================================');
  print('     TESTING YTMUSIC API + YOUTUBE_EXPLODE DIRECT STREAMING');
  print('================================================================');
  print('1. Initializing YTMusic API...');
  await ytmusic.initialize();
  print('   YTMusic API Initialized successfully.\n');

  print('2. Searching YouTube Music for: "$searchQuery"...');
  final searchResults = await ytmusic.searchSongs(searchQuery);
  print('   Found ${searchResults.length} song results.\n');

  if (searchResults.isEmpty) {
    print('No songs found.');
    ytExplode.close();
    return;
  }

  // Display top 3 results
  print('Top Search Results:');
  print('----------------------------------------------------------------');
  for (var i = 0; i < searchResults.length && i < 3; i++) {
    final song = searchResults[i];
    print('[$i] Title:    ${song.name}');
    print('    Artist:   ${song.artist.name}');
    print('    Album:    ${song.album?.name ?? "Single / Unknown"}');
    print('    Duration: ${song.duration}s');
    print('    Video ID: ${song.videoId}');
    print('');
  }

  // Pick top song
  final topSong = searchResults.first;
  final videoId = topSong.videoId;
  print('Selected Top Song: "${topSong.name}" by ${topSong.artist.name} (VideoId: $videoId)');
  print('----------------------------------------------------------------');

  // 3. Try fetching Lyrics if available
  try {
    print('3. Fetching lyrics from YouTube Music...');
    final lyrics = await ytmusic.getLyrics(videoId);
    if (lyrics != null && lyrics.isNotEmpty) {
      final preview = lyrics.length > 150
          ? '${lyrics.substring(0, 150)}...'
          : lyrics;
      print('   Lyrics found (Preview):\n   "$preview"\n');
    } else {
      print('   No plain lyrics found for this track.\n');
    }
  } catch (e) {
    print('   Lyrics fetch notice: $e\n');
  }

  // 4. Extract Direct Audio Stream using youtube_explode_dart
  print('4. Resolving Direct Audio Stream via youtube_explode_dart...');
  final stopwatch = Stopwatch()..start();
  try {
    final manifest = await ytExplode.videos.streams.getManifest(videoId);
    stopwatch.stop();

    final bestAudio = manifest.audioOnly.withHighestBitrate();
    final aacAudio = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();

    print('   Stream resolved in ${stopwatch.elapsedMilliseconds}ms:');
    print('   [Highest Quality Overall] Codec: ${bestAudio.audioCodec} | Container: ${bestAudio.container.name} | Bitrate: ${bestAudio.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps');
    print('   Direct Stream URL: ${bestAudio.url}');
    print('');

    if (aacAudio.isNotEmpty) {
      final bestAac = aacAudio.withHighestBitrate();
      print('   [Native AAC / MP4 for Miniaudio] Tag: ${bestAac.tag} | Bitrate: ${bestAac.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps');
      print('   Direct AAC Stream URL: ${bestAac.url}');
    }

    print('\n[SUCCESS] Integrated YTMusic metadata discovery + direct Explode streaming verified!');
  } catch (e, st) {
    print('   Failed to resolve streams: $e');
    print(st);
  } finally {
    ytExplode.close();
  }
}
