import 'dart:io';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';

/// Helper to convert TimedLyricsRes into a standard synchronized LRC string format
String formatTimedLyricsToLrc(TimedLyricsRes timedLyrics) {
  final sb = StringBuffer();
  for (final data in timedLyrics.timedLyricsData) {
    final line = data.lyricLine?.trim() ?? '';
    final cue = data.cueRange;
    if (cue == null) {
      if (line.isNotEmpty) sb.writeln(line);
      continue;
    }
    final startMs = cue.startTimeMilliseconds;
    final dur = Duration(milliseconds: startMs);
    final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
    final xx = ((dur.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    sb.writeln('[$mm:$ss.$xx] $line');
  }
  return sb.toString();
}

/// Fallback LRC generator for plain text lyrics across a given duration
String generateEstimatedLrc(String text, int totalDurationMs) {
  final lines = text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (lines.isEmpty || totalDurationMs <= 0) return text;

  final msPerLine = (totalDurationMs / lines.length).floor();
  final sb = StringBuffer();
  for (int i = 0; i < lines.length; i++) {
    final currentMs = i * msPerLine;
    final dur = Duration(milliseconds: currentMs);
    final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
    final xx = ((dur.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    sb.writeln('[$mm:$ss.$xx] ${lines[i]}');
  }
  return sb.toString();
}

/// Checks if internet is available
Future<bool> checkInternetAvailable() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Searches YouTube Music for a song by local metadata (title, artist)
Future<SongDetailed?> findSongOnline(YTMusic ytmusic, {required String title, String? artist}) async {
  final cleanTitle = title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').trim();
  final query = (artist != null && artist.isNotEmpty && artist.toLowerCase() != 'unknown artist')
      ? '$cleanTitle $artist'
      : cleanTitle;

  print('   -> Searching YTMusic for: "$query"...');
  final songs = await ytmusic.searchSongs(query);
  if (songs.isNotEmpty) {
    return songs.first;
  }
  return null;
}

void main(List<String> args) async {
  final ytmusic = YTMusic();
  print('================================================================');
  print('          LYRICS EXPERIMENT & PARSING TEST HARNESS');
  print('================================================================\n');

  print('1. Checking internet connectivity...');
  final hasInternet = await checkInternetAvailable();
  print('   Internet Available: $hasInternet');
  if (!hasInternet) {
    print('   Offline mode: No internet detected.');
    return;
  }

  print('\n2. Initializing YTMusic API...');
  await ytmusic.initialize();
  print('   YTMusic initialized.\n');

  // Test Case A: Online stream with known videoId
  final testTracks = [
    {'title': 'Shape of You', 'artist': 'Ed Sheeran', 'videoId': 'JGwWNGJdvx8'},
    {'title': 'Bohemian Rhapsody', 'artist': 'Queen', 'videoId': 'fJ9rUzIMcZQ'},
    {'title': 'Blinding Lights', 'artist': 'The Weeknd', 'videoId': '4NRXx6U8ABQ'},
  ];

  print('3. Testing Timed vs Plain Lyrics for Online Video IDs:');
  print('----------------------------------------------------------------');

  for (final track in testTracks) {
    final title = track['title']!;
    final artist = track['artist']!;
    final videoId = track['videoId']!;
    print('\n[Track] "$title" by $artist (ID: $videoId)');

    try {
      print('   -> Fetching getTimedLyrics...');
      final timed = await ytmusic.getTimedLyrics(videoId);
      if (timed != null && timed.timedLyricsData.isNotEmpty) {
        print('   [SUCCESS] Received ${timed.timedLyricsData.length} timed lyric cues!');
        final lrc = formatTimedLyricsToLrc(timed);
        final sampleLines = lrc.split('\n').take(4).join('\n');
        print('   Sample LRC Output:\n$sampleLines\n   ...');
      } else {
        print('   [NOTICE] Timed lyrics not available for this track.');
      }

      print('   -> Fetching getLyrics (Plain)...');
      final plain = await ytmusic.getLyrics(videoId);
      if (plain != null && plain.isNotEmpty) {
        print('   [SUCCESS] Received plain lyrics (${plain.split('\n').length} lines).');
        final sampleLines = plain.split('\n').take(3).join('\n');
        print('   Sample Plain Output:\n$sampleLines\n   ...');
      } else {
        print('   [NOTICE] Plain lyrics not available.');
      }
    } catch (e) {
      print('   [ERROR] Failed to fetch lyrics: $e');
    }
  }

  // Test Case B: Simulating Local Music lookup
  print('\n================================================================');
  print('4. Testing Local Song Online Lookup via Title + Artist:');
  print('================================================================');

  final localSongsToLookup = [
    {'title': 'Hotel California', 'artist': 'Eagles'},
    {'title': 'Imagine', 'artist': 'John Lennon'},
    {'title': '01 Track 1 - Unknown Title.mp3', 'artist': 'Unknown Artist'}, // edge case
  ];

  for (final local in localSongsToLookup) {
    final title = local['title']!;
    final artist = local['artist'];
    print('\n[Local Track] Title: "$title", Artist: "$artist"');

    final match = await findSongOnline(ytmusic, title: title, artist: artist);
    if (match != null) {
      print('   [MATCH FOUND] "${match.name}" by ${match.artist.name} (VideoID: ${match.videoId})');
      // Fetch lyrics for matched song
      try {
        final timed = await ytmusic.getTimedLyrics(match.videoId);
        if (timed != null && timed.timedLyricsData.isNotEmpty) {
          print('   [SUCCESS] Timed lyrics fetched for local song!');
          final lrc = formatTimedLyricsToLrc(timed);
          print('   First line: ${lrc.split('\n').first}');
        } else {
          final plain = await ytmusic.getLyrics(match.videoId);
          if (plain != null) {
            print('   [SUCCESS] Plain lyrics fetched for local song (${plain.split('\n').length} lines)');
          } else {
            print('   [NOTICE] No lyrics available on YouTube Music for matched song.');
          }
        }
      } catch (e) {
        print('   [ERROR] Could not fetch lyrics for matched song: $e');
      }
    } else {
      print('   [NO MATCH] No song found for query.');
    }
  }

  print('\n================================================================');
  print('                      EXPERIMENT COMPLETED');
  print('================================================================');
}
