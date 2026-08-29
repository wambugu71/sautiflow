import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/lyrics_service.dart';
import 'package:sautiplay/widgets/synced_lyrics_widget.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';

void main() {
  group('LyricsService & LrcParser Tests', () {
    test('Track title cleaning', () {
      final service = LyricsService.instance;
      expect(service.cleanTrackTitle('01 - Bohemian Rhapsody.flac'),
          equals('Bohemian Rhapsody'));
      expect(
          service.cleanTrackTitle('03. Hotel California (2013 Remaster).mp3'),
          equals('Hotel California'));
      expect(service.cleanTrackTitle('Imagine (Official Audio).m4a'),
          equals('Imagine'));
      expect(
          service.cleanTrackTitle('Shape of You [Official Lyric Video].wav'),
          equals('Shape of You'));
      expect(
          service.cleanTrackTitle('Billie Jean (Live at Wembley 1988).ogg'),
          equals('Billie Jean'));
      expect(
          service.cleanTrackTitle('Pink_Floyd_Comfortably_Numb.mp3'),
          equals('Pink Floyd Comfortably Numb'));
      expect(
          service.cleanTrackTitle(r'C:\Music\Rock\01 - Stairway to Heaven (Remastered).flac'),
          equals('Stairway to Heaven'));
    });

    test('Artist name cleaning', () {
      final service = LyricsService.instance;
      expect(service.cleanArtistName('Queen'), equals('Queen'));
      expect(service.cleanArtistName('Unknown Artist'), isNull);
      expect(service.cleanArtistName('<unknown>'), isNull);
      expect(service.cleanArtistName('Various Artists'), isNull);
      expect(service.cleanArtistName(''), isNull);
      expect(service.cleanArtistName(null), isNull);
    });

    test('parseArtistAndTitle parses title and artist from filename and metadata', () {
      final service = LyricsService.instance;
      final (t1, a1) = service.parseArtistAndTitle(
        rawTitle: '01 - Time.mp3',
        rawArtist: 'Pink Floyd',
      );
      expect(t1, equals('Time'));
      expect(a1, equals('Pink Floyd'));

      final (t2, a2) = service.parseArtistAndTitle(
        rawTitle: 'Queen - Bohemian Rhapsody (2011 Remaster).flac',
        rawArtist: 'Unknown Artist',
      );
      expect(t2, equals('Bohemian Rhapsody'));
      expect(a2, equals('Queen'));

      final (t3, a3) = service.parseArtistAndTitle(
        rawTitle: '',
        rawArtist: null,
        filePath: r'C:\Music\Adele - Someone Like You.mp3',
      );
      expect(t3, equals('Someone Like You'));
      expect(a3, equals('Adele'));
    });

    test('formatTimedLyricsToLrc converts TimedLyricsRes into standard LRC', () {
      final service = LyricsService.instance;
      final timedLyrics = TimedLyricsRes(
        timedLyricsData: [
          TimedLyricsData(
            lyricLine: 'Is this the real life?',
            cueRange: CueRange(
              startTimeMilliseconds: 1520,
              endTimeMilliseconds: 4200,
              metadata: CueRangeMetadata(id: '1'),
            ),
          ),
          TimedLyricsData(
            lyricLine: 'Is this just fantasy?',
            cueRange: CueRange(
              startTimeMilliseconds: 4500,
              endTimeMilliseconds: 8100,
              metadata: CueRangeMetadata(id: '2'),
            ),
          ),
        ],
        sourceMessage: 'Source: Musixmatch',
      );

      final lrc = service.formatTimedLyricsToLrc(timedLyrics);
      final lines = LrcParser.parse(lrc);

      expect(lines.length, equals(2));
      expect(lines[0].text, equals('Is this the real life?'));
      expect(lines[0].time, equals(const Duration(milliseconds: 1520)));
      expect(lines[1].text, equals('Is this just fantasy?'));
      expect(lines[1].time, equals(const Duration(milliseconds: 4500)));
    });

    test('generateEstimatedLrc spreads plain lyrics across total duration', () {
      final service = LyricsService.instance;
      const plain = '''
Line one
Line two
Line three
Line four''';

      final lrc = service.generateEstimatedLrc(plain, 40000);
      final lines = LrcParser.parse(lrc);

      expect(lines.length, equals(4));
      expect(lines[0].time.inMilliseconds, equals(0));
      expect(lines[1].time.inMilliseconds, equals(10000));
      expect(lines[2].time.inMilliseconds, equals(20000));
      expect(lines[3].time.inMilliseconds, equals(30000));
      expect(lines[0].text, equals('Line one'));
    });

    test('LrcParser handles multi-timestamps and milliseconds precision', () {
      const multi = '''
[00:05.10][00:15.50] Refrain text
[01:02.345] High precision text
[00:01] Simple second text
''';
      final parsed = LrcParser.parse(multi);
      expect(parsed.length, equals(4));

      // Sorted by time: 00:01 (1000ms), 00:05.10 (5100ms), 00:15.50 (15500ms), 01:02.345 (62345ms)
      expect(parsed[0].time.inMilliseconds, equals(1000));
      expect(parsed[0].text, equals('Simple second text'));

      expect(parsed[1].time.inMilliseconds, equals(5100));
      expect(parsed[1].text, equals('Refrain text'));

      expect(parsed[2].time.inMilliseconds, equals(15500));
      expect(parsed[2].text, equals('Refrain text'));

      expect(parsed[3].time.inMilliseconds, equals(62345));
      expect(parsed[3].text, equals('High precision text'));
    });

    test('Song change generation token simulates stale discard', () async {
      int activeRequestId = 0;
      String? currentLyrics;

      Future<void> requestLyricsForSong(int songNum, int delayMs, String lyrics) async {
        final reqId = ++activeRequestId;
        currentLyrics = null; // Instant clear on song change

        await Future.delayed(Duration(milliseconds: delayMs));

        if (reqId == activeRequestId) {
          currentLyrics = lyrics;
        }
      }

      // Fast switch: Song 1 requested (slow 80ms), then Song 2 requested (fast 20ms)
      final f1 = requestLyricsForSong(1, 80, 'Lyrics for Song 1');
      await Future.delayed(const Duration(milliseconds: 10));
      final f2 = requestLyricsForSong(2, 20, 'Lyrics for Song 2');

      await Future.wait([f1, f2]);

      // Ensure Song 1's late response did not overwrite Song 2
      expect(currentLyrics, equals('Lyrics for Song 2'));
    });
  });
}
