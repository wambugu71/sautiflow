import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  group('M3U / M3U8 Playlist Parser Tests', () {
    test('Parse basic M3U playlist with #EXTINF metadata', () {
      const sampleM3u = '''
#EXTM3U
#EXTINF:215,Artist One - Sample Track Title
/path/to/song1.mp3
#EXTINF:180,Artist Two - Second Song
https://example.com/stream.flac
''';

      final entries = M3uParser.parse(sampleM3u);
      expect(entries.length, equals(2));

      expect(entries[0].title, equals('Sample Track Title'));
      expect(entries[0].artist, equals('Artist One'));
      expect(entries[0].pathOrUrl, equals('/path/to/song1.mp3'));
      expect(entries[0].durationSeconds, equals(215));
      expect(entries[0].isNetwork, isFalse);

      expect(entries[1].title, equals('Second Song'));
      expect(entries[1].artist, equals('Artist Two'));
      expect(entries[1].pathOrUrl, equals('https://example.com/stream.flac'));
      expect(entries[1].durationSeconds, equals(180));
      expect(entries[1].isNetwork, isTrue);
    });

    test('AudioSource.fromM3uContent creates file and network sources', () {
      const sampleM3u = '''
#EXTM3U
#EXTINF:120,Local Audio
local_track.wav
#EXTINF:-1,Radio Stream
http://stream.radio.org/live.mp3
''';

      final sources = AudioSource.fromM3uContent(sampleM3u, baseDirectory: '/music');
      expect(sources.length, equals(2));

      expect(sources[0].isNetwork, isFalse);
      expect(sources[0].title, equals('Local Audio'));
      expect(sources[0].duration, equals(const Duration(seconds: 120)));

      expect(sources[1].isNetwork, isTrue);
      expect(sources[1].title, equals('Radio Stream'));
      expect(sources[1].uri.toString(), equals('http://stream.radio.org/live.mp3'));
    });

    test('Encode M3U playlist back to string', () {
      const entries = [
        M3uEntry(
          title: 'Track A',
          artist: 'Artist A',
          pathOrUrl: '/music/a.mp3',
          durationSeconds: 200,
        ),
        M3uEntry(
          title: 'Live Stream',
          artist: 'Radio Station',
          pathOrUrl: 'http://radio.com/live',
          durationSeconds: -1,
        ),
      ];

      final encoded = M3uParser.encode(entries);
      expect(encoded, contains('#EXTM3U'));
      expect(encoded, contains('#EXTINF:200,Artist A - Track A'));
      expect(encoded, contains('/music/a.mp3'));
      expect(encoded, contains('http://radio.com/live'));
    });
  });
}
