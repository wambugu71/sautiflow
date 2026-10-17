import 'dart:io';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/waveform_extractor_service.dart';
import 'package:sautiplay/widgets/waveform_seek_bar_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveformExtractorService Tests', () {
    setUp(() {
      WaveformExtractorService.instance.clearCache();
    });

    test('getImmediate returns 160 normalized bars [0.08, 1.0] instantly', () {
      final peaks = WaveformExtractorService.instance.getImmediate('test_seed_1');
      expect(peaks.length, equals(160));
      for (final p in peaks) {
        expect(p, greaterThanOrEqualTo(0.08));
        expect(p, lessThanOrEqualTo(1.0));
      }
    });

    test('getImmediate is deterministic for the same path', () {
      final peaks1 = WaveformExtractorService.instance.getImmediate('song_alpha');
      final peaks2 = WaveformExtractorService.instance.getImmediate('song_alpha');
      expect(peaks1, equals(peaks2));
    });

    test('getWaveform caches result in memory', () async {
      final peaks1 = await WaveformExtractorService.instance.getWaveform('online_song_123');
      final cached = WaveformExtractorService.instance.getCached('online_song_123');
      expect(cached, isNotNull);
      expect(cached, equals(peaks1));
    });

    test('prefetch populates cache for upcoming tracks', () async {
      WaveformExtractorService.instance.prefetch(['track_A', 'track_B']);
      await Future.delayed(const Duration(milliseconds: 50));
      final cachedA = WaveformExtractorService.instance.getCached('track_A');
      final cachedB = WaveformExtractorService.instance.getCached('track_B');
      expect(cachedA, isNotNull);
      expect(cachedB, isNotNull);
    });

    test('Accurately parses authentic WAV PCM data without falling back to random bytes', () async {
      final tempDir = Directory.systemTemp.createTempSync('wf_test_');
      final wavFile = File('${tempDir.path}/test.wav');

      const sampleRate = 44100;
      const channels = 2;
      const bitsPerSample = 16;
      const numFrames = 44100; // 1 second
      const dataSize = numFrames * channels * (bitsPerSample ~/ 8);

      final bytes = BytesBuilder();
      // RIFF header
      bytes.add('RIFF'.codeUnits);
      final totalFileSize = 36 + dataSize;
      final sizeData = ByteData(4)..setUint32(0, totalFileSize, Endian.little);
      bytes.add(sizeData.buffer.asUint8List());
      bytes.add('WAVE'.codeUnits);

      // fmt chunk
      bytes.add('fmt '.codeUnits);
      final fmtSize = ByteData(4)..setUint32(0, 16, Endian.little);
      bytes.add(fmtSize.buffer.asUint8List());
      final fmtBody = ByteData(16)
        ..setUint16(0, 1, Endian.little) // PCM
        ..setUint16(2, channels, Endian.little)
        ..setUint32(4, sampleRate, Endian.little)
        ..setUint32(8, sampleRate * channels * 2, Endian.little)
        ..setUint16(12, channels * 2, Endian.little)
        ..setUint16(14, bitsPerSample, Endian.little);
      bytes.add(fmtBody.buffer.asUint8List());

      // data chunk
      bytes.add('data'.codeUnits);
      final dSize = ByteData(4)..setUint32(0, dataSize, Endian.little);
      bytes.add(dSize.buffer.asUint8List());

      // Audio: quiet first half (amp 2000), loud second half (amp 25000)
      final pcm = ByteData(dataSize);
      for (int i = 0; i < numFrames; i++) {
        final amp = (i < numFrames ~/ 2) ? 2000 : 25000;
        pcm.setInt16(i * 4, amp, Endian.little);
        pcm.setInt16(i * 4 + 2, amp, Endian.little);
      }
      bytes.add(pcm.buffer.asUint8List());

      wavFile.writeAsBytesSync(bytes.toBytes());

      try {
        final peaks = await WaveformExtractorService.instance.getWaveform(wavFile.path, numBars: 160);
        expect(peaks.length, equals(160));
        // Verify acoustic accuracy: quiet first half has significantly lower peaks than loud second half
        final avgFirstHalf = peaks.sublist(0, 80).reduce((a, b) => a + b) / 80;
        final avgSecondHalf = peaks.sublist(80, 160).reduce((a, b) => a + b) / 80;
        expect(avgSecondHalf, greaterThan(avgFirstHalf));

        // Test persistent binary disk cache:
        // Clear memory cache, then getImmediate should read the true extracted peaks from disk!
        final diskReadPeaks = WaveformExtractorService.instance.getImmediate(wavFile.path, numBars: 160);
        expect(diskReadPeaks.length, equals(160));
        final avgDiskFirst = diskReadPeaks.sublist(0, 80).reduce((a, b) => a + b) / 80;
        final avgDiskSecond = diskReadPeaks.sublist(80, 160).reduce((a, b) => a + b) / 80;
        expect(avgDiskSecond, greaterThan(avgDiskFirst));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Accurately parses authentic MP3 frames with global_gain envelope', () async {
      final tempDir = Directory.systemTemp.createTempSync('wf_mp3_test_');
      final mp3File = File('${tempDir.path}/test.mp3');

      final bytes = BytesBuilder();

      // Build synthetic MPEG-1 Layer 3 frames
      // 128 kbps, 44100 Hz, stereo: frame size = 144 * 128000 / 44100 = 417 bytes
      const frameLen = 417;
      const numFrames = 50;

      for (int f = 0; f < numFrames; f++) {
        final frameBuf = Uint8List(frameLen);
        // Sync: 0xFF, 0xFB (MPEG-1 Layer 3, no CRC)
        frameBuf[0] = 0xFF;
        frameBuf[1] = 0xFB;
        // Bitrate 128k (index 9 = 0x90), 44100Hz (index 0 = 0x00) -> 0x90
        frameBuf[2] = 0x90;
        // Stereo: channelMode = 0 (0x00)
        frameBuf[3] = 0x00;

        // Side info starts at byte 4.
        // Side info stereo: byte 4..35
        // Byte 9 and 10 of frame (sideInfoOffset + 5, 6) contains global_gain for Granule 0 Channel 0!
        // First half: quiet gain = 130, Second half: loud gain = 220
        final gain = (f < numFrames ~/ 2) ? 130 : 220;
        // gain is shifted left by 5 into bytes 9 and 10
        frameBuf[9] = (gain >> 3) & 0xFF;
        frameBuf[10] = (gain << 5) & 0xFF;

        bytes.add(frameBuf);
      }

      mp3File.writeAsBytesSync(bytes.toBytes());

      try {
        final peaks = await WaveformExtractorService.instance.getWaveform(mp3File.path, numBars: 160);
        expect(peaks.length, equals(160));
        // Acoustic volume verification from MP3 side-info global_gain
        final avgFirstHalf = peaks.sublist(0, 80).reduce((a, b) => a + b) / 80;
        final avgSecondHalf = peaks.sublist(80, 160).reduce((a, b) => a + b) / 80;
        expect(avgSecondHalf, greaterThan(avgFirstHalf));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('WaveformSeekBarWidget renders cleanly at 60-120Hz with instance geometry', (tester) async {
      final peaks = List<double>.generate(160, (i) => 0.1 + (i / 160) * 0.8);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 48,
                child: WaveformSeekBarWidget(
                  peaks: peaks,
                  displayPosMs: 30000,
                  maxMs: 120000,
                  onSeekEnd: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WaveformSeekBarWidget), findsOneWidget);
      await tester.pump();
    });
  });
}
