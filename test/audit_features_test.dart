import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

/// Writes a 16-bit PCM stereo WAV file at [sampleRate].
File _writeWavFile(
  Directory dir,
  String name, {
  required int sampleRate,
  required List<double> interleavedStereoSamples,
}) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  final numSamples = interleavedStereoSamples.length;
  final dataBytes = numSamples * 2;
  final totalBytes = 44 + dataBytes;
  final bd = ByteData(totalBytes);

  void writeAscii(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  bd.setUint32(4, totalBytes - 8, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // PCM chunk size
  bd.setUint16(20, 1, Endian.little); // PCM format
  bd.setUint16(22, 2, Endian.little); // stereo
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2 * 2, Endian.little);
  bd.setUint16(32, 4, Endian.little); // block align
  bd.setUint16(34, 16, Endian.little); // bits per sample
  writeAscii(36, 'data');
  bd.setUint32(40, dataBytes, Endian.little);

  for (int i = 0; i < numSamples; i++) {
    final s = (interleavedStereoSamples[i].clamp(-1.0, 1.0) * 32767.0).round();
    bd.setInt16(44 + i * 2, s, Endian.little);
  }

  file.writeAsBytesSync(bd.buffer.asUint8List(), flush: true);
  return file;
}

List<double> _generateSine({
  required int sampleRate,
  required double durationSec,
  required double freqHz,
  required double amplitude,
}) {
  final frames = (sampleRate * durationSec).round();
  final out = List<double>.filled(frames * 2, 0.0);
  for (int i = 0; i < frames; i++) {
    final v = amplitude * math.sin(2.0 * math.pi * freqHz * i / sampleRate);
    out[i * 2] = v;
    out[i * 2 + 1] = v;
  }
  return out;
}

List<double> _generateSilence({
  required int sampleRate,
  required double durationSec,
}) {
  final frames = (sampleRate * durationSec).round();
  return List<double>.filled(frames * 2, 0.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File tone4sWav;
  late File shortWav;
  late File analysisWav;
  late File click120BpmWav;
  late File podcastSilenceWav;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('sautiflow_audit_');
    const sr = 48000;

    // 1. 4-second 440 Hz stereo tone for seeking tests
    tone4sWav = _writeWavFile(
      tempDir,
      'tone_4s.wav',
      sampleRate: sr,
      interleavedStereoSamples: _generateSine(
        sampleRate: sr,
        durationSec: 4.0,
        freqHz: 440.0,
        amplitude: 0.25,
      ),
    );

    // 2. Short 0.35-second WAV for track-ended callback/event tests
    shortWav = _writeWavFile(
      tempDir,
      'short_035s.wav',
      sampleRate: sr,
      interleavedStereoSamples: _generateSine(
        sampleRate: sr,
        durationSec: 0.35,
        freqHz: 660.0,
        amplitude: 0.2,
      ),
    );

    // 3. Analysis WAV: 1.0s silence + 3.0s 1 kHz sine @ 0.25 (-12.04 dBFS) + 1.5s silence
    final analysisSamples = <double>[
      ..._generateSilence(sampleRate: sr, durationSec: 1.0),
      ..._generateSine(
        sampleRate: sr,
        durationSec: 3.0,
        freqHz: 1000.0,
        amplitude: 0.25,
      ),
      ..._generateSilence(sampleRate: sr, durationSec: 1.5),
    ];
    analysisWav = _writeWavFile(
      tempDir,
      'analysis_tone.wav',
      sampleRate: sr,
      interleavedStereoSamples: analysisSamples,
    );

    // 4. 120 BPM click track (10s, beat every 0.5s)
    const clickDur = 10.0;
    final clickFrames = (sr * clickDur).round();
    final clickSamples = List<double>.filled(clickFrames * 2, 0.0);
    for (double beatSec = 0.0; beatSec < clickDur; beatSec += 0.5) {
      final startFrame = (beatSec * sr).round();
      final burstLen = (0.04 * sr).round();
      for (int j = 0; j < burstLen && (startFrame + j) < clickFrames; j++) {
        final env = math.exp(-j / (0.008 * sr));
        final v = 0.7 * env * math.sin(2.0 * math.pi * 80.0 * j / sr);
        clickSamples[(startFrame + j) * 2] = v;
        clickSamples[(startFrame + j) * 2 + 1] = v;
      }
    }
    click120BpmWav = _writeWavFile(
      tempDir,
      'click_120bpm.wav',
      sampleRate: sr,
      interleavedStereoSamples: clickSamples,
    );

    // 5. Podcast WAV: 0.35s tone + 1.5s silence + 0.4s tone
    podcastSilenceWav = _writeWavFile(
      tempDir,
      'podcast_silence.wav',
      sampleRate: sr,
      interleavedStereoSamples: <double>[
        ..._generateSine(
          sampleRate: sr,
          durationSec: 0.35,
          freqHz: 500.0,
          amplitude: 0.3,
        ),
        ..._generateSilence(sampleRate: sr, durationSec: 1.5),
        ..._generateSine(
          sampleRate: sr,
          durationSec: 0.40,
          freqHz: 500.0,
          amplitude: 0.3,
        ),
      ],
    );
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Audit Items 1–6 Verification', () {
    late MiniAudioPlayer player;

    setUp(() {
      player = MiniAudioPlayer(libraryPath: 'sautiflow.dll');
      expect(player.init(sampleRate: 48000, channels: 2), isTrue);
    });

    tearDown(() {
      player.dispose();
    });

    test('1. Direct seeking by seconds, PCM frame, and Duration', () async {
      final loaded = player.setAudioSources(
        [AudioSource.file(tone4sWav.path)],
        autoPlay: false,
      );
      expect(loaded, isTrue);

      expect(player.seekToSeconds(2.5), isTrue);
      expect(player.status.positionSeconds, closeTo(2.5, 0.08));

      expect(player.seekToPcmFrame(48000), isTrue);
      expect(player.status.positionSeconds, closeTo(1.0, 0.08));

      expect(player.seekTo(const Duration(milliseconds: 1500)), isTrue);
      expect(player.status.positionSeconds, closeTo(1.5, 0.08));
    });

    test('2. Stateless offline file analysis (R128 LUFS, True Peak, BPM, silence bounds)', () async {
      final res = player.analyzeFile(analysisWav.path, silenceThresholdDb: -50.0);
      expect(res, isNotNull);
      expect(res!.valid, isTrue);
      expect(res.sampleRate, equals(48000));
      expect(res.channels, equals(2));
      expect(res.durationSeconds, closeTo(5.5, 0.05));
      expect(res.samplePeakLinear, closeTo(0.25, 0.01));
      expect(res.truePeakDbtp, closeTo(-12.04, 0.6));
      expect(res.integratedLufs, inInclusiveRange(-14.5, -10.0));
      expect(res.replayGainTrackGainDb, closeTo(-18.0 - res.integratedLufs, 0.05));
      expect(res.leadingSilenceSec, closeTo(1.0, 0.1));
      expect(res.trailingSilenceSec, closeTo(1.5, 0.1));

      final bpmRes = player.analyzeFile(click120BpmWav.path);
      expect(bpmRes, isNotNull);
      expect(bpmRes!.bpm, inInclusiveRange(115.0, 125.0));
      expect(bpmRes.bpmConfidence, greaterThan(0.1));

      final bgRes = await AudioEngineFFI.analyzeFileAsync(
        analysisWav.path,
        libraryPath: 'sautiflow.dll',
      );
      expect(bgRes, isNotNull);
      expect(bgRes!.valid, isTrue);
      expect(bgRes.durationSeconds, closeTo(5.5, 0.05));
    });

    test('3. Output device enumeration & selection', () {
      final devices = player.listOutputDevices();
      expect(devices, isA<List<AEOutputDeviceInfo>>());
      expect(player.setOutputDevice('invalid_device:nonexistent'), isFalse);
      if (devices.isNotEmpty) {
        final target = devices.first;
        expect(target.id, isNotEmpty);
        expect(target.name, isNotEmpty);
        expect(player.setOutputDevice(target.id), isTrue);
        expect(player.getOutputDevice(), equals(target.id));
        expect(player.setOutputDevice(null), isTrue);
        expect(player.getOutputDevice(), isEmpty);
      }
    });

    test('4. Push event stream (error, trackChanged, trackEnded) & safe onTrackEnded', () async {
      final events = <EngineEvent>[];
      final sub = player.eventStream.listen(events.add);

      final endedCompleter = Completer<void>();
      player.setOnTrackEnded(() {
        if (!endedCompleter.isCompleted) endedCompleter.complete();
      });

      // Trigger an out-of-range error without calling getLastError()
      player.setAudioSources(
        [AudioSource.file(shortWav.path), AudioSource.file(tone4sWav.path)],
        autoPlay: false,
      );
      player.setLoopMode(LoopMode.off);
      final jumpedBad = player.seekTo(Duration.zero, index: 99);
      expect(jumpedBad, isFalse);

      // Play short WAV to completion and verify trackEnded event + safe callback
      expect(
        player.setAudioSources(
          [AudioSource.file(shortWav.path)],
          initialIndex: 0,
          autoPlay: true,
        ),
        isTrue,
      );

      await endedCompleter.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        events.any((e) => e.type == EngineEventType.error),
        isTrue,
        reason: 'Out-of-range jump should push an error event',
      );
      expect(
        events.any((e) => e.type == EngineEventType.trackEnded),
        isTrue,
        reason: 'Completing short track should push a trackEnded event',
      );

      await sub.cancel();
    });

    test('5. Edge trimming & mid-track podcast silence skipping', () async {
      player.setSilenceConfig(const SilenceConfig(
        edgeTrimEnabled: true,
        skipSilenceEnabled: false,
        thresholdDb: -45.0,
      ));
      final cfg = player.getSilenceConfig();
      expect(cfg.edgeTrimEnabled, isTrue);
      expect(cfg.skipSilenceEnabled, isFalse);
      expect(cfg.thresholdDb, closeTo(-45.0, 0.1));

      expect(
        player.setAudioSources(
          [AudioSource.file(analysisWav.path)],
          autoPlay: false,
        ),
        isTrue,
      );
      // 1.0s leading silence should be trimmed near ~0.985s
      expect(player.status.positionSeconds, greaterThan(0.85));

      // Now test mid-track podcast silence skipping
      player.resetSkippedSilenceMs();
      expect(player.getSkippedSilenceMs(), equals(0));
      player.setSilenceConfig(const SilenceConfig(
        edgeTrimEnabled: false,
        skipSilenceEnabled: true,
        thresholdDb: -40.0,
        minSilenceMs: 200,
        keepSilenceMs: 100,
        silenceSpeedFactor: 0.0,
      ));
      expect(
        player.setAudioSources(
          [AudioSource.file(podcastSilenceWav.path)],
          autoPlay: true,
        ),
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(player.getSkippedSilenceMs(), greaterThanOrEqualTo(400));
    });

    test('6. Automix Key Lock config round-trip', () {
      player.setAutomixConfig(const AutomixConfig(
        enabled: true,
        style: AutomixStyle.smartHybrid,
        transitionBars: 16,
        tempoSyncEnabled: true,
        keyLockEnabled: false,
      ));
      final got = player.getAutomixConfig();
      expect(got.enabled, isTrue);
      expect(got.keyLockEnabled, isFalse);
      expect(got.tempoSyncEnabled, isTrue);
    });
  });
}
