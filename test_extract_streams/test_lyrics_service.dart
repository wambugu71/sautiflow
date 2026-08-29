import 'dart:io';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';

class LrcLine {
  final Duration time;
  final String text;

  const LrcLine({required this.time, required this.text});
  @override
  String toString() => '[${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}.${((time.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0')}] $text';
}

class LrcParser {
  static List<LrcLine> parse(String content) {
    final lines = <LrcLine>[];
    // Matches [mm:ss.xx] or [mm:ss.xxx] or [m:s.xx] or [mm:ss:xx] or [mm:ss]
    final regExp = RegExp(r'\[(\d+):(\d+)(?:[\.\:](\d+))?\]\s*(.*)');
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final subStr = match.group(3) ?? '0';
        int millis = 0;
        if (subStr.length == 1) {
          millis = int.parse(subStr) * 100;
        } else if (subStr.length == 2) {
          millis = int.parse(subStr) * 10;
        } else if (subStr.length >= 3) {
          millis = int.parse(subStr.substring(0, 3));
        }
        final dur = Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LrcLine(time: dur, text: text));
        }
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}

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

String cleanTrackTitle(String rawTitle) {
  var title = rawTitle;
  // Remove file extension
  title = title.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
  // Remove track numbers like "01 - " or "01. " or "1 - "
  title = title.replaceAll(RegExp(r'^\d+[\s\.\-_]+'), '');
  // Remove audio tags like [Official Video], (Remastered 2011), etc.
  title = title.replaceAll(RegExp(r'\s*[\(\[](?:Official|Remastered|Audio|Video|Lyrics|HD|HQ|1080p|4K|Explicit|Clean)[^\)\]]*[\)\]]', caseSensitive: false), '');
  return title.trim();
}

void main() async {
  print('====================================================');
  print('     COMPREHENSIVE LYRICS EXPERIMENT & PARSING');
  print('====================================================');

  final yt = YTMusic();
  await yt.initialize();

  // 1. Test Title Cleaning
  print('\n[1] Testing Title Cleaning:');
  final testTitles = [
    '01 - Bohemian Rhapsody.flac',
    '03. Hotel California (2013 Remaster).mp3',
    'Imagine (Official Audio).m4a',
    'Shape of You [Official Lyric Video].wav'
  ];
  for (final t in testTitles) {
    print('  Original: "$t" -> Cleaned: "${cleanTrackTitle(t)}"');
  }

  // 2. Test Local song lookup and parsing into LrcLines
  print('\n[2] Testing Local Song Online Search + Parsing:');
  final sampleLocalTracks = [
    {'title': '01 - Imagine.mp3', 'artist': 'John Lennon'},
    {'title': 'Hello', 'artist': 'Adele'},
    {'title': 'Bohemian Rhapsody', 'artist': 'Queen'},
  ];

  for (final track in sampleLocalTracks) {
    final clean = cleanTrackTitle(track['title']!);
    final artist = track['artist'];
    final query = (artist != null && artist.isNotEmpty && !artist.toLowerCase().contains('unknown'))
        ? '$clean $artist'
        : clean;
    print('\nSearching for: "$query"...');
    final results = await yt.searchSongs(query);
    if (results.isEmpty) {
      print('  No song match found.');
      continue;
    }
    final song = results.first;
    print('  Found Match: "${song.name}" by ${song.artist.name} (VideoID: ${song.videoId})');

    try {
      final timed = await yt.getTimedLyrics(song.videoId);
      if (timed != null && timed.timedLyricsData.isNotEmpty) {
        final lrcString = formatTimedLyricsToLrc(timed);
        final parsedLines = LrcParser.parse(lrcString);
        print('  [SUCCESS] Parsed ${parsedLines.length} synchronized lines!');
        print('  First 3 parsed lines:');
        for (var i = 0; i < parsedLines.length && i < 3; i++) {
          print('    ${parsedLines[i]}');
        }
      } else {
        print('  No timed lyrics, attempting plain lyrics...');
        final plain = await yt.getLyrics(song.videoId);
        if (plain != null) {
          print('  [SUCCESS] Got plain lyrics: ${plain.split('\n').length} lines.');
        } else {
          print('  No lyrics found.');
        }
      }
    } catch (e) {
      print('  Error during lyrics retrieval: $e');
    }
  }

  // 3. Test Rapid Song Switching Simulation (Generation Token)
  print('\n[3] Testing Fast Song Switching Simulation:');
  int activeRequestId = 0;
  String? currentDisplayedLyrics;

  Future<void> simulateSongChange(int songIndex, String title) async {
    final requestId = ++activeRequestId;
    currentDisplayedLyrics = null; // Instantly cleared!
    print('  -> Song $songIndex ("$title") started. Request ID #$requestId issued. Lyrics cleared.');

    // Simulate network delay
    final delay = (3 - songIndex) * 50; // song 1 takes 100ms, song 2 takes 50ms
    await Future.delayed(Duration(milliseconds: delay));

    if (requestId != activeRequestId) {
      print('  [DISCARDED] Request ID #$requestId returned late. Active is #$activeRequestId. Ignored stale lyrics!');
      return;
    }
    currentDisplayedLyrics = 'Lyrics for Song $songIndex: $title';
    print('  [APPLIED] Request ID #$requestId displayed lyrics: "$currentDisplayedLyrics"');
  }

  await Future.wait([
    simulateSongChange(1, 'Song 1 Old'),
    Future.delayed(const Duration(milliseconds: 20)).then((_) => simulateSongChange(2, 'Song 2 New')),
  ]);

  print('\nFinal Displayed Lyrics: "$currentDisplayedLyrics"');
  print('====================================================');
}
