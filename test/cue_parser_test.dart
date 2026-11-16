import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

Uint8List _buildFlacHeaderWithStreamInfo({
  int sampleRate = 44100,
  int totalSamples = 44100 * 600,
  bool streamInfoIsLast = false,
}) {
  final out = BytesBuilder();
  out.add(ascii.encode('fLaC'));

  // METADATA_BLOCK_HEADER: isLast (bit 7), type = 0 (STREAMINFO), len = 34
  out.addByte(streamInfoIsLast ? 0x80 : 0x00);
  out.add([0x00, 0x00, 34]);

  final info = Uint8List(34);
  // 20-bit sampleRate at bytes 10..12, totalSamples (36-bit) at bytes 13..17
  info[10] = (sampleRate >> 12) & 0xFF;
  info[11] = (sampleRate >> 4) & 0xFF;
  info[12] = (sampleRate & 0x0F) << 4;
  info[13] = (totalSamples >> 32) & 0x0F;
  info[14] = (totalSamples >> 24) & 0xFF;
  info[15] = (totalSamples >> 16) & 0xFF;
  info[16] = (totalSamples >> 8) & 0xFF;
  info[17] = totalSamples & 0xFF;
  out.add(info);
  return out.toBytes();
}

Uint8List _buildFlacWithVorbisCue(String cueText) {
  final out = BytesBuilder();
  out.add(_buildFlacHeaderWithStreamInfo());

  final vendor = utf8.encode('sautiflow-test');
  final album = utf8.encode('ALBUM=Vorbis Album');
  final artist = utf8.encode('ARTIST=Vorbis Artist');
  final cueComment = utf8.encode('CUESHEET=$cueText');
  final comments = [album, artist, cueComment];

  final payload = BytesBuilder();
  final vendorLenBd = ByteData(4)..setUint32(0, vendor.length, Endian.little);
  payload.add(vendorLenBd.buffer.asUint8List());
  payload.add(vendor);

  final countBd = ByteData(4)..setUint32(0, comments.length, Endian.little);
  payload.add(countBd.buffer.asUint8List());

  for (final c in comments) {
    final lenBd = ByteData(4)..setUint32(0, c.length, Endian.little);
    payload.add(lenBd.buffer.asUint8List());
    payload.add(c);
  }

  final payloadBytes = payload.toBytes();
  // METADATA_BLOCK_HEADER: isLast = 1 (0x80) | blockType = 4 (VORBIS_COMMENT)
  out.addByte(0x84);
  out.add([
    (payloadBytes.length >> 16) & 0xFF,
    (payloadBytes.length >> 8) & 0xFF,
    payloadBytes.length & 0xFF,
  ]);
  out.add(payloadBytes);
  return out.toBytes();
}

Uint8List _buildFlacWithBinaryCueBlock({
  int sampleRate = 44100,
  int totalSamples = 44100 * 600,
}) {
  final out = BytesBuilder();
  out.add(
    _buildFlacHeaderWithStreamInfo(
      sampleRate: sampleRate,
      totalSamples: totalSamples,
    ),
  );

  final block = BytesBuilder();
  // 395 bytes (128 MCN + 8 lead-in + 1 flags + 258 reserved) + 1 byte numTracks
  block.add(Uint8List(395));
  block.addByte(3); // 2 audio tracks + 1 lead-out (0xAA)

  void addTrack({
    required int offsetSamples,
    required int trackNum,
    required List<({int num, int offsetSamples})> indexPoints,
  }) {
    final header = ByteData(36);
    header.setUint64(0, offsetSamples, Endian.big);
    header.setUint8(8, trackNum);
    // 12 bytes ISRC (9..20), flags = 0 (AUDIO) at 21, 13 reserved (22..34)
    header.setUint8(35, indexPoints.length);
    block.add(header.buffer.asUint8List());

    for (final pt in indexPoints) {
      final idxData = ByteData(12);
      idxData.setUint64(0, pt.offsetSamples, Endian.big);
      idxData.setUint8(8, pt.num);
      block.add(idxData.buffer.asUint8List());
    }
  }

  // Track 1: starts at sample 0
  addTrack(
    offsetSamples: 0,
    trackNum: 1,
    indexPoints: [(num: 1, offsetSamples: 0)],
  );
  // Track 2: offset 10s (INDEX 00 at 0 relative = 10s, INDEX 01 at 2s relative = 12s)
  addTrack(
    offsetSamples: sampleRate * 10,
    trackNum: 2,
    indexPoints: [
      (num: 0, offsetSamples: 0),
      (num: 1, offsetSamples: sampleRate * 2),
    ],
  );
  // Lead-out track 170 (0xAA) at 300s
  addTrack(
    offsetSamples: sampleRate * 300,
    trackNum: 170,
    indexPoints: const [],
  );

  final blockBytes = block.toBytes();
  // METADATA_BLOCK_HEADER: isLast = 1 (0x80) | blockType = 5 (CUESHEET)
  out.addByte(0x85);
  out.add([
    (blockBytes.length >> 16) & 0xFF,
    (blockBytes.length >> 8) & 0xFF,
    blockBytes.length & 0xFF,
  ]);
  out.add(blockBytes);
  return out.toBytes();
}

Uint8List _buildApev2WithCue(String cueText, {bool appendId3v1 = false}) {
  final out = BytesBuilder();
  // Simulated WavPack/Monkey's Audio payload before APEv2 tag
  out.add(Uint8List(64));

  final keyBytes = ascii.encode('CUESHEET');
  final valBytes = utf8.encode(cueText);

  final itemsBuilder = BytesBuilder();
  final itemHeader = ByteData(8)
    ..setUint32(0, valBytes.length, Endian.little)
    ..setUint32(4, 0, Endian.little); // flags=0 -> UTF-8 text item
  itemsBuilder.add(itemHeader.buffer.asUint8List());
  itemsBuilder.add(keyBytes);
  itemsBuilder.addByte(0); // NUL terminator for key
  itemsBuilder.add(valBytes);
  final itemsBytes = itemsBuilder.toBytes();

  final tagSize = itemsBytes.length + 32; // items + footer
  final footer = ByteData(32)
    ..setUint32(8, 2000, Endian.little) // version 2000
    ..setUint32(12, tagSize, Endian.little)
    ..setUint32(16, 1, Endian.little); // itemCount = 1
  final footerBytes = footer.buffer.asUint8List();
  footerBytes.setRange(0, 8, ascii.encode('APETAGEX'));

  out.add(itemsBytes);
  out.add(footerBytes);

  if (appendId3v1) {
    final id3 = Uint8List(128);
    id3.setRange(0, 3, ascii.encode('TAG'));
    out.add(id3);
  }

  return out.toBytes();
}

void main() {
  group('CueParser', () {
    test('parses multi-track CUE sheet with 75fps timing and ReplayGain tags', () {
      const sampleCue = '''
REM GENRE Progressive Rock
REM DATE 1973
REM REPLAYGAIN_ALBUM_GAIN -7.45 dB
REM REPLAYGAIN_ALBUM_PEAK 0.991234
PERFORMER "Pink Floyd"
TITLE "Mr. Tambourine & Side A"
FILE "Side A.flac" FLAC
  TRACK 01 AUDIO
    TITLE "Speak to Me / Breathe"
    PERFORMER "Pink Floyd"
    REM REPLAYGAIN_TRACK_GAIN -6.20 dB
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "On the Run"
    REM REPLAYGAIN_TRACK_GAIN -8.10 dB
    INDEX 00 03:44:00
    INDEX 01 03:45:37
  TRACK 03 AUDIO
    TITLE "Time"
    INDEX 01 07:20:74
''';

      final sheet = CueParser.parse(
        sampleCue,
        cueFilePath: '/music/Album/Side A.cue',
        baseDirectory: '/music/Album',
      );

      expect(sheet.genre, 'Progressive Rock');
      expect(sheet.year, 1973);
      expect(sheet.replayGainAlbumDb, closeTo(-7.45, 0.001));
      expect(sheet.replayGainAlbumPeak, closeTo(0.991234, 0.0001));
      expect(sheet.title, 'Mr. Tambourine & Side A');
      expect(sheet.performer, 'Pink Floyd');

      final tracks = sheet.allTracks;
      expect(tracks.length, 3);

      // Track 1: 00:00:00 -> Track 2 INDEX 00 (03:44:00 = 224000 ms)
      expect(tracks[0].trackNumber, 1);
      expect(tracks[0].title, 'Speak to Me / Breathe');
      expect(tracks[0].effectiveArtist, 'Pink Floyd');
      expect(tracks[0].startMs, 0);
      expect(tracks[0].endMs, 224000);
      expect(tracks[0].replayGainTrackDb, closeTo(-6.20, 0.001));
      expect(tracks[0].replayGainAlbumDb, closeTo(-7.45, 0.001));

      // Track 2: 03:45:37 => 225s + round(37 * 1000 / 75) = 225493 ms
      // End boundary: Track 3 INDEX 01 07:20:74 => 440s + round(74 * 1000 / 75) = 440987 ms
      expect(tracks[1].trackNumber, 2);
      expect(tracks[1].title, 'On the Run');
      expect(tracks[1].effectiveArtist, 'Pink Floyd'); // inherits album performer
      expect(tracks[1].pregapMs, 224000);
      expect(tracks[1].startMs, 225493);
      expect(tracks[1].endMs, 440987);
      expect(tracks[1].replayGainTrackDb, closeTo(-8.10, 0.001));

      // Track 3: last track with no overrideFileDurationMs has open endMs
      expect(tracks[2].trackNumber, 3);
      expect(tracks[2].startMs, 440987);
      expect(tracks[2].endMs, isNull);
    });

    test('resolves fallback lossless extensions when FILE references .wav', () {
      final tempDir = Directory.systemTemp.createTempSync('cue_fallback_test_');
      try {
        final flacFile = File(p.join(tempDir.path, 'concert_image.flac'))
          ..writeAsBytesSync(const [0x66, 0x4C, 0x61, 0x43]);
        final cueFile = File(p.join(tempDir.path, 'concert_image.cue'))
          ..writeAsStringSync('''
TITLE "Live Concert"
PERFORMER "Test Ensemble"
FILE "concert_image.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Opening Overture"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Finale"
    INDEX 01 05:00:00
''');

        final sheet = CueParser.parseFileSync(cueFile.path);
        expect(sheet, isNotNull);
        expect(sheet!.files.length, 1);
        expect(
          p.canonicalize(sheet.files.first.resolvedFilePath),
          p.canonicalize(flacFile.path),
        );
        expect(sheet.allTracks.length, 2);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('CueVirtualPath and AudioSource.file preserve and decode track clips', () {
      final tempDir = Directory.systemTemp.createTempSync('cue_virtual_test_');
      try {
        final realFlacPath = p.join(tempDir.path, 'Greatest Hits.flac');
        File(realFlacPath).writeAsBytesSync(const [0x66, 0x4C, 0x61, 0x43]);

        final encoded = CueVirtualPath.encode(
          realFilePath: realFlacPath,
          trackNumber: 2,
          startMs: 120000,
          endMs: 265500,
          title: 'Song Two',
          artist: 'Artist Two',
          album: 'Mr. Tambourine Vol. 1',
          genre: 'Jazz',
          year: 1965,
          replayGainTrackDb: -5.25,
          replayGainAlbumDb: -6.10,
          cueFilePath: p.join(tempDir.path, 'Greatest Hits.cue'),
        );

        expect(CueVirtualPath.isVirtual(encoded), isTrue);
        expect(CueVirtualPath.strip(encoded), realFlacPath);

        // Dot in album query parameter must not leak past CueVirtualPath.strip
        expect(p.extension(CueVirtualPath.strip(encoded)).toLowerCase(), '.flac');

        final uncanonical =
            '${p.join(tempDir.path, '.', 'Greatest Hits.flac')}${encoded.substring(encoded.indexOf(CueVirtualPath.marker))}';
        expect(
          CueVirtualPath.canonicalize(uncanonical),
          CueVirtualPath.canonicalize(encoded),
        );
        expect(
          CueVirtualPath.canonicalize(uncanonical).endsWith(
            encoded.substring(encoded.indexOf(CueVirtualPath.marker)),
          ),
          isTrue,
        );
        expect(
          CueVirtualPath.normalizedKey(uncanonical),
          CueVirtualPath.normalizedKey(encoded),
        );

        final parsed = CueVirtualPath.parse(encoded);
        expect(parsed, isNotNull);
        expect(parsed!.trackNumber, 2);
        expect(parsed.startMs, 120000);
        expect(parsed.endMs, 265500);
        expect(parsed.title, 'Song Two');
        expect(parsed.artist, 'Artist Two');
        expect(parsed.album, 'Mr. Tambourine Vol. 1');
        expect(parsed.genre, 'Jazz');
        expect(parsed.year, 1965);
        expect(parsed.replayGainTrackDb, closeTo(-5.25, 0.01));
        expect(parsed.replayGainAlbumDb, closeTo(-6.10, 0.01));
        expect(parsed.duration, const Duration(milliseconds: 145500));

        final source = AudioSource.file(encoded);
        expect(source.isClipped, isTrue);
        expect(source.uri.toFilePath(), realFlacPath);
        expect(source.clipStart, const Duration(milliseconds: 120000));
        expect(source.clipEnd, const Duration(milliseconds: 265500));
        expect(source.duration, const Duration(milliseconds: 145500));
        expect(source.title, 'Song Two');
        expect(source.artist, 'Artist Two');
        expect(source.album, 'Mr. Tambourine Vol. 1');
        expect(source.trackNumber, 2);
        expect(source.replayGainTrackDb, closeTo(-5.25, 0.01));
        expect(source.replayGainAlbumDb, closeTo(-6.10, 0.01));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extractEmbeddedCueSync reads FLAC VORBIS_COMMENT and binary CUESHEET blocks', () {
      final tempDir = Directory.systemTemp.createTempSync('cue_flac_embed_');
      try {
        const embeddedCueText = '''
TITLE "Embedded Vorbis Album"
PERFORMER "FLAC Artist"
FILE "CDImage.flac" FLAC
  TRACK 01 AUDIO
    TITLE "First Movement"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second Movement"
    INDEX 01 04:00:00
''';
        final vorbisFlac = File(p.join(tempDir.path, 'vorbis_cue.flac'))
          ..writeAsBytesSync(_buildFlacWithVorbisCue(embeddedCueText));

        final vorbisSheet = CueParser.extractEmbeddedCueSync(vorbisFlac.path);
        expect(vorbisSheet, isNotNull);
        expect(vorbisSheet!.title, 'Embedded Vorbis Album');
        expect(vorbisSheet.allTracks.length, 2);
        expect(vorbisSheet.allTracks[0].filePath, vorbisFlac.path);
        expect(vorbisSheet.allTracks[0].endMs, 240000);
        // Last track inherits STREAMINFO duration (600,000 ms)
        expect(vorbisSheet.allTracks[1].endMs, 600000);

        final binaryFlac = File(p.join(tempDir.path, 'binary_cue.flac'))
          ..writeAsBytesSync(_buildFlacWithBinaryCueBlock());

        final binarySheet = CueParser.extractEmbeddedCueSync(binaryFlac.path);
        expect(binarySheet, isNotNull);
        expect(binarySheet!.allTracks.length, 2);
        expect(binarySheet.allTracks[0].startMs, 0);
        // Track 2 INDEX 00 is at 10s -> Track 1 endMs is 10000 ms
        expect(binarySheet.allTracks[0].endMs, 10000);
        // Track 2 INDEX 01 is at 12s -> Track 2 startMs is 12000 ms, lead-out at 300s
        expect(binarySheet.allTracks[1].startMs, 12000);
        expect(binarySheet.allTracks[1].endMs, 300000);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extractEmbeddedCueSync reads APEv2 CUESHEET from .wv and .ape files', () {
      final tempDir = Directory.systemTemp.createTempSync('cue_ape_embed_');
      try {
        const apeCueText = '''
TITLE "WavPack Image"
PERFORMER "WV Performer"
FILE "image.wv" WAVE
  TRACK 01 AUDIO
    TITLE "Intro"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Main Theme"
    INDEX 01 02:30:00
''';
        final wvFile = File(p.join(tempDir.path, 'album.wv'))
          ..writeAsBytesSync(_buildApev2WithCue(apeCueText));
        final wvSheet = CueParser.extractEmbeddedCueSync(wvFile.path);
        expect(wvSheet, isNotNull);
        expect(wvSheet!.title, 'WavPack Image');
        expect(wvSheet.allTracks.length, 2);
        expect(wvSheet.allTracks[0].filePath, wvFile.path);
        expect(wvSheet.allTracks[1].startMs, 150000);

        final apeWithId3 = File(p.join(tempDir.path, 'album.ape'))
          ..writeAsBytesSync(_buildApev2WithCue(apeCueText, appendId3v1: true));
        final apeSheet = CueParser.extractEmbeddedCueSync(apeWithId3.path);
        expect(apeSheet, isNotNull);
        expect(apeSheet!.allTracks.length, 2);
        expect(apeSheet.allTracks[0].filePath, apeWithId3.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
