import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';
import 'package:sautiplay/services/chromecast_service.dart';
import 'package:sautiplay/streaming_service.dart';
import 'package:sautiplay/widgets/signal_path.dart';

void main() {
  group('StreamTelemetry native state parsing', () {
    test('maps native StreamState::Error (-1) to StreamPlaybackState.error', () {
      expect(
        StreamTelemetry.parseNativeState(-1),
        StreamPlaybackState.error,
      );
      const tel = StreamTelemetry(
        state: StreamPlaybackState.error,
        errorCode: 403,
        errorMessage: 'HTTP 403 Forbidden',
      );
      expect(tel.hasError, isTrue);
      expect(tel.errorMessage, 'HTTP 403 Forbidden');
    });

    test('maps 0..5 states accurately and falls back unknown to idle', () {
      expect(StreamTelemetry.parseNativeState(0), StreamPlaybackState.idle);
      expect(StreamTelemetry.parseNativeState(1), StreamPlaybackState.connecting);
      expect(StreamTelemetry.parseNativeState(2), StreamPlaybackState.buffering);
      expect(StreamTelemetry.parseNativeState(3), StreamPlaybackState.ready);
      expect(StreamTelemetry.parseNativeState(4), StreamPlaybackState.playing);
      expect(StreamTelemetry.parseNativeState(5), StreamPlaybackState.ended);
      expect(StreamTelemetry.parseNativeState(99), StreamPlaybackState.idle);
    });
  });

  group('StreamBufferProfile presets', () {
    test('ordered strictly from fastStart -> balanced -> highStability', () {
      expect(
        StreamBufferProfile.fastStart.prebufferMs <
            StreamBufferProfile.balanced.prebufferMs,
        isTrue,
      );
      expect(
        StreamBufferProfile.balanced.prebufferMs <
            StreamBufferProfile.highStability.prebufferMs,
        isTrue,
      );
      expect(
        StreamBufferProfile.highStability.ringDurationSec >=
            StreamBufferProfile.balanced.ringDurationSec,
        isTrue,
      );
    });
  });

  group('AudioStreamSelector preset selection', () {
    final mixedCandidates = [
      const StreamCandidate(index: 0, bitrateKbps: 50.0, isMp4OrAac: false), // Opus 249
      const StreamCandidate(index: 1, bitrateKbps: 48.0, isMp4OrAac: true),  // Low HE-AAC
      const StreamCandidate(index: 2, bitrateKbps: 72.0, isMp4OrAac: false), // Opus 250
      const StreamCandidate(index: 3, bitrateKbps: 96.0, isMp4OrAac: true),  // Mid AAC
      const StreamCandidate(index: 4, bitrateKbps: 128.0, isMp4OrAac: true), // AAC 140
      const StreamCandidate(index: 5, bitrateKbps: 160.0, isMp4OrAac: false), // Opus 251
    ];

    test('preferAac=false differentiates low/medium/high/audiophile', () {
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.low,
          preferAac: false,
        ),
        1, // lowest bitrate (48k)
      );
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.medium,
          preferAac: false,
        ),
        2, // 72k
      );
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.high,
          preferAac: false,
        ),
        4, // 128k AAC (>=100k)
      );
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.audiophile,
          preferAac: false,
        ),
        5, // 160k Opus
      );
    });

    test('high preset never chooses sub-100k MP4 over 160k Opus', () {
      final lowMp4PlusHighOpus = [
        const StreamCandidate(index: 0, bitrateKbps: 48.0, isMp4OrAac: true),
        const StreamCandidate(index: 1, bitrateKbps: 160.0, isMp4OrAac: false),
      ];
      expect(
        AudioStreamSelector.selectCandidateIndex(
          lowMp4PlusHighOpus,
          quality: AudioQualityPreset.high,
          preferAac: false,
        ),
        1,
      );
    });

    test('preferAac=true tiers medium vs high/audiophile across AAC pool', () {
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.low,
          preferAac: true,
        ),
        1, // 48k AAC
      );
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.medium,
          preferAac: true,
        ),
        3, // 96k AAC (not collapsed to 128k!)
      );
      expect(
        AudioStreamSelector.selectCandidateIndex(
          mixedCandidates,
          quality: AudioQualityPreset.high,
          preferAac: true,
        ),
        4, // 128k AAC
      );
    });
  });

  group('buildSignalPath network SwrContext metadata', () {
    test('reports Linear Phase (Kaiser) and 95.0% passband on network streams', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'OPUS',
          'isNetworkStream': true,
          'inputSampleRate': 44100,
          'inputBitDepth': 32,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'decoderSrcActive': true,
          'deviceSrcActive': false,
          'activeNodeMask': 0,
        },
        const AudioHardwareSpecs(
          deviceName: 'Speaker',
          deviceType: 'Built-in',
          backendName: 'WASAPI',
          sampleRate: 48000,
          channels: 2,
          bitDepth: 32,
          isFloat: true,
          isExclusiveMode: false,
          isDirectPcm: false,
          periodSizeFrames: 480,
          periodCount: 2,
          latencyMs: 10.0,
        ),
        activeDeviceType: 'Built-in',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      final decSrc = result.nodes.firstWhere((n) => n.id == 'decoder_src');
      expect(decSrc.liveParams['Pipeline'], 'FFmpeg Decoder + SwrContext');
      expect(decSrc.liveParams['Phase'], 'Linear Phase (Kaiser)');
      expect(decSrc.liveParams['Passband'], '95.0%');
    });
  });
}
