import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';
import 'package:sautiplay/services/audio_output_target_resolver.dart';
import 'package:sautiplay/services/chromecast_service.dart';
import 'package:sautiplay/widgets/audio_engine_diagnostic_panel.dart';
import 'package:sautiplay/widgets/signal_path.dart';

class _FakeDiagPlayer extends Fake implements IsolateAudioPlayer {
  final Map<String, dynamic> telemetryData;
  _FakeDiagPlayer(this.telemetryData);

  @override
  Future<Map<String, dynamic>> getEngineTelemetry() async => telemetryData;

  @override
  void setClippingDetectionEnabled(bool enabled) {}

  @override
  void setTruePeakMeterEnabled(bool enabled) {}

  @override
  void setLoudnessMeterEnabled(bool enabled) {}
}

AudioHardwareSpecs _specs({
  int sampleRate = 48000,
  int bitDepth = 24,
  bool isFloat = false,
  bool isDirectPcm = false,
  bool isExclusive = false,
}) {
  return AudioHardwareSpecs(
    deviceName: 'Test DAC',
    deviceType: 'USB DAC',
    backendName: 'WASAPI',
    sampleRate: sampleRate,
    channels: 2,
    bitDepth: bitDepth,
    isFloat: isFloat,
    isExclusiveMode: isExclusive,
    isDirectPcm: isDirectPcm,
    periodSizeFrames: 512,
    periodCount: 2,
    latencyMs: 10.67,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildSignalPath', () {
    test('exclusive mode produces bypassed DSP node and Bypassed label', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 3, 'bitDepth': 24, 'isExclusiveMode': true},
          'fileType': 'FLAC',
          'inputSampleRate': 96000,
          'inputBitDepth': 24,
          'engineSampleRate': 96000,
          'processingSampleRate': 96000,
          'processingChannels': 2,
          'outputSampleRate': 96000,
          'outputFormat': 3,
          'precision64Reasons': Precision64Reason.exclusive | Precision64Reason.intOutput,
          'appDspBypassed': true,
          'float64EndToEnd': true,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
          'eqEnabled': true,
          'activeNodeMask': 0,
        },
        _specs(sampleRate: 96000, isExclusive: true),
        activeDeviceType: 'USB DAC',
        isCastingOut: false,
        castMode: CastAudioMode.bitPerfect,
        castMaxSampleRateHz: 192000,
      );

      expect(result.dspPrecisionLabel, 'Bypassed (Exclusive)');
      expect(
        result.nodes.any((n) => n.kind == ChainNodeKind.bypassedDsp),
        isTrue,
      );
      expect(
        result.nodes.any((n) => n.kind == ChainNodeKind.zone),
        isFalse,
      );
    });

    test('S16 output with user 64-bit off explains auto int output reason', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 's16', 'bitDepth': 16},
          'fileType': 'FLAC',
          'inputSampleRate': 44100,
          'inputBitDepth': 16,
          'engineSampleRate': 44100,
          'processingSampleRate': 44100,
          'processingChannels': 2,
          'outputSampleRate': 44100,
          'outputFormat': 0, // requested F32, but hw opened S16
          'precision64Reasons': Precision64Reason.intOutput,
          'float64EndToEnd': true,
          'appDspBypassed': false,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
          'activeNodeMask': 0,
        },
        _specs(sampleRate: 44100, bitDepth: 16),
        activeDeviceType: 'Speaker',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      expect(result.dspPrecisionLabel, 'Float64 → 16-bit Int (auto · int output)');
      expect(result.outputLabel, contains('16-bit Int'));
      final precisionNode =
          result.nodes.firstWhere((n) => n.kind == ChainNodeKind.precision);
      expect(precisionNode.badge, 'auto · int output');
      expect(
        result.nodes.any((n) => n.kind == ChainNodeKind.dither),
        isTrue,
      );
    });

    test('source == device != engine shows both DECODER SRC and DEVICE SRC', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'FLAC',
          'inputSampleRate': 44100,
          'inputBitDepth': 16,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 44100,
          'outputFormat': 0,
          'precision64Reasons': Precision64Reason.user,
          'float64EndToEnd': false,
          'appDspBypassed': false,
          'decoderSrcActive': true,
          'deviceSrcActive': true,
          'resampleAlgorithm': 'r8brain24MinimumPhase',
          'deviceResamplerAlgo': 0,
          'resampleLatencyMs': 1.25,
          'activeNodeMask': 0,
        },
        _specs(sampleRate: 44100, bitDepth: 32, isFloat: true),
        activeDeviceType: 'Speaker',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      expect(result.srcLabel, 'ON (44.1 kHz → 48.0 kHz → 44.1 kHz)');
      expect(
        result.resamplerLabel,
        'r8brain Minimum Phase (Dec) + Linear LPF4 (Dev)',
      );
      expect(result.dspPrecisionLabel, 'Float64 (→F32 @ SRC)');
      expect(
        result.nodes.any((n) => n.kind == ChainNodeKind.decoderSrc),
        isTrue,
      );
      final devSrc =
          result.nodes.firstWhere((n) => n.kind == ChainNodeKind.deviceSrc);
      expect(devSrc.outgoingArrow?.formatLabel, 'F64 → F32');
      expect(devSrc.outgoingArrow?.note, 'SRC downcast');
    });

    test('Reverb under 64-bit DSP stays uniformly F64 with no float island', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 4, 'bitDepth': 24},
          'fileType': 'FLAC',
          'inputSampleRate': 48000,
          'inputBitDepth': 24,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'precision64Reasons': Precision64Reason.user,
          'float64EndToEnd': true,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
          'reverbEnabled': true,
          'reverbEngine': 'Dattorro Plate',
          'activeNodeMask': ActiveNodeMask.z5Spatial,
        },
        _specs(sampleRate: 48000, bitDepth: 24),
        activeDeviceType: 'Headphones',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      final reverb = result.nodes.firstWhere((n) => n.title == 'REVERB');
      expect(reverb.isWarning, isFalse);
      expect(reverb.badge, 'F64');
      expect(reverb.outgoingArrow?.formatLabel, 'F64');
    });

    test('DSD DoP passthrough collapses chain to Source -> DoP -> Output', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 4, 'bitDepth': 24},
          'fileType': 'DSF',
          'inputSampleRate': 2822400,
          'sourceDsdRate': 2822400,
          'activeDsdMode': 2, // DoP
          'processingSampleRate': 176400,
          'outputSampleRate': 176400,
        },
        _specs(sampleRate: 176400, bitDepth: 24),
        activeDeviceType: 'USB DAC',
        isCastingOut: false,
        castMode: CastAudioMode.bitPerfect,
        castMaxSampleRateHz: 192000,
      );

      expect(result.nodes.length, 3);
      expect(result.nodes[1].title, 'DoP v1.1 PACKER');
      expect(result.srcLabel, 'OFF (DSD Bit-Perfect)');
    });

    test('activeDspNodes renders real individual DSP effects without zone grouping', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 's24', 'bitDepth': 24},
          'fileType': 'FLAC',
          'inputSampleRate': 96000,
          'inputBitDepth': 24,
          'engineSampleRate': 96000,
          'processingSampleRate': 96000,
          'processingChannels': 2,
          'outputSampleRate': 96000,
          'activeDspNodes': [
            {
              'id': 'harmonic_bass',
              'name': 'Harmonic Bass',
              'precision': 'F32',
              'summary': '80 Hz · +4.5 dB · Boost 45%',
              'params': {'Cutoff': '80 Hz', 'Gain': '+4.5 dB', 'Harmonic Boost': '45%'},
            },
            {
              'id': 'clarity',
              'name': 'Audio Clarity',
              'precision': 'F32',
              'summary': 'Intensity 60% · 2x OS',
              'params': {'Intensity': '60%', 'Oversampling': '2x'},
            },
            {
              'id': 'lookahead_limiter',
              'name': 'Look-Ahead Limiter',
              'precision': 'F64',
              'summary': 'Ceiling -1.0 dBTP · GR -0.5 dB',
              'latencyMs': 2.0,
              'params': {'Ceiling': '-1.0 dBTP', 'Live GR': '-0.5 dB'},
            },
          ],
        },
        _specs(sampleRate: 96000, bitDepth: 24),
        activeDeviceType: 'USB DAC',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 192000,
      );

      expect(result.nodes.any((n) => n.kind == ChainNodeKind.zone), isFalse);
      final bass = result.nodes.firstWhere((n) => n.id == 'harmonic_bass');
      final clarity = result.nodes.firstWhere((n) => n.id == 'clarity');
      final limiter = result.nodes.firstWhere((n) => n.id == 'lookahead_limiter');
      expect(bass.title, 'HARMONIC BASS');
      expect(bass.liveParams['Cutoff'], '80 Hz');
      expect(clarity.title, 'AUDIO CLARITY');
      expect(clarity.liveParams['Intensity'], '60%');
      expect(limiter.latencyMs, 2.0);
      expect(result.srcLabel, 'OFF (Matched 96.0 kHz)');
    });

    test('24-bit 44.1 kHz FLAC into 32-bit 48.0 kHz output always reports Decoder SRC ON and zero OS/HAL SRC', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'FLAC',
          'inputSampleRate': 44100,
          'inputBitDepth': 24,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'outputFormat': 0,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
          'resampleAlgorithm': 'r8brain24MinimumPhase',
          'resampleLatencyMs': 1.4,
        },
        _specs(sampleRate: 48000, bitDepth: 32, isFloat: true),
        activeDeviceType: 'Speakers',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      expect(result.srcLabel, 'ON (44.1 kHz → 48.0 kHz)');
      expect(result.resamplerLabel, contains('r8brain'));
      final decSrc =
          result.nodes.firstWhere((n) => n.kind == ChainNodeKind.decoderSrc);
      expect(decSrc.detail, contains('44.1 kHz → 48.0 kHz'));
      expect(
        result.nodes.any((n) => n.kind == ChainNodeKind.deviceSrc),
        isFalse,
      );
      final outNode =
          result.nodes.firstWhere((n) => n.kind == ChainNodeKind.output);
      expect(outNode.liveParams['OS / HAL SRC'], 'None (1:1 Matched)');
    });

    test('online streams show FFmpeg SwrContext while local files show r8brain', () {
      final streamResult = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'AAC',
          'isNetworkStream': true,
          'inputSampleRate': 44100,
          'inputBitDepth': 16,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'resampleAlgorithm': 'r8brain24MinimumPhase',
        },
        _specs(sampleRate: 48000, bitDepth: 32, isFloat: true),
        activeDeviceType: 'Speakers',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      expect(streamResult.resamplerLabel, 'FFmpeg SwrContext (Stream)');
      expect(streamResult.resamplerLabel, isNot(contains('r8brain')));
      final streamDecSrc = streamResult.nodes
          .firstWhere((n) => n.kind == ChainNodeKind.decoderSrc);
      expect(streamDecSrc.liveParams['Algorithm'], 'FFmpeg SwrContext');
      expect(
        streamDecSrc.liveParams['Pipeline'],
        'FFmpeg Decoder + SwrContext',
      );
      expect(streamDecSrc.liveParams['Phase'], 'Linear Phase (Kaiser)');
      expect(streamDecSrc.liveParams['Passband'], '95.0%');

      final localResult = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'OPUS',
          'isNetworkStream': false,
          'inputSampleRate': 44100,
          'inputBitDepth': 24,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'resampleAlgorithm': 'r8brain24MinimumPhase',
        },
        _specs(sampleRate: 48000, bitDepth: 32, isFloat: true),
        activeDeviceType: 'Speakers',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      expect(localResult.resamplerLabel, 'r8brain Minimum Phase (Decoder)');
      final localDecSrc = localResult.nodes
          .firstWhere((n) => n.kind == ChainNodeKind.decoderSrc);
      expect(localDecSrc.liveParams['Algorithm'], 'r8brain Minimum Phase');
      expect(localDecSrc.liveParams['Phase'], 'Minimum Phase');
    });
  });

  group('AudioOutputTargetResolver', () {
    test('matches Bluetooth SBC 16/44.1 and LDAC 24/96 automatically', () {
      const sbcSpecs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: 'BT Earbuds',
        sampleRate: 44100,
        bitDepth: 16,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 8.7,
        isExclusiveMode: false,
        deviceType: 'Bluetooth Wireless',
        bluetoothCodec: 'SBC',
        btSampleRate: 44100,
        btBitDepth: 16,
      );
      final sbcTarget = AudioOutputTargetResolver.resolve(
        specs: sbcSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 48000,
      );
      expect(sbcTarget.sampleRateHz, 44100);
      expect(sbcTarget.format, AudioFormat.s16);
      expect(sbcTarget.isUserOverride, isFalse);

      const ldacSpecs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: 'Sony WH-1000XM5',
        sampleRate: 96000,
        bitDepth: 24,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 4.0,
        isExclusiveMode: false,
        deviceType: 'Bluetooth Wireless',
        bluetoothCodec: 'LDAC',
        btSampleRate: 96000,
        btBitDepth: 24,
      );
      final ldacTarget = AudioOutputTargetResolver.resolve(
        specs: ldacSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 44100,
      );
      expect(ldacTarget.sampleRateHz, 96000);
      expect(ldacTarget.format, AudioFormat.s24);
    });

    test('matches USB DAC native track rate (zero SRC) and 32/384 capability', () {
      const dacSpecs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: 'FiiO KA17',
        sampleRate: 384000,
        bitDepth: 32,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 2.0,
        isExclusiveMode: false,
        deviceType: 'USB DAC',
        supportedSampleRates: [44100, 48000, 88200, 96000, 176400, 192000, 384000],
        supportedBitDepths: [16, 24, 32],
        usbDacAttached: true,
      );

      final native192 = AudioOutputTargetResolver.resolve(
        specs: dacSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 192000,
      );
      expect(native192.sampleRateHz, 192000);
      expect(native192.format, AudioFormat.s32);

      final userOverride = AudioOutputTargetResolver.resolve(
        specs: dacSpecs,
        userSampleRateHz: 384000,
        userFormat: AudioFormat.s32,
        sourceSampleRateHz: 44100,
      );
      expect(userOverride.sampleRateHz, 384000);
      expect(userOverride.isUserOverride, isTrue);

      final autoDacNoTrack = AudioOutputTargetResolver.resolve(
        specs: dacSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: null,
      );
      expect(autoDacNoTrack.sampleRateHz, 0);
      expect(autoDacNoTrack.isUserOverride, isFalse);

      // USB DAC capped at 24-bit/192 kHz playing 384 kHz clamps down to 192 kHz / S24
      const dac192Specs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: '24/192 USB DAC',
        sampleRate: 192000,
        bitDepth: 24,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 2.0,
        isExclusiveMode: false,
        deviceType: 'USB DAC',
        supportedSampleRates: [44100, 48000, 88200, 96000, 176400, 192000],
        supportedBitDepths: [16, 24],
        usbDacAttached: true,
        isFixedClock: false,
        directMultiRate: true,
      );
      final clamped384 = AudioOutputTargetResolver.resolve(
        specs: dac192Specs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 384000,
      );
      expect(clamped384.sampleRateHz, 192000);
      expect(clamped384.format, AudioFormat.s24);

      final native96On192 = AudioOutputTargetResolver.resolve(
        specs: dac192Specs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 96000,
      );
      expect(native96On192.sampleRateHz, 96000);
      expect(native96On192.format, AudioFormat.s24);
    });

    test('fixed-clock 32/48 kHz phone clamps 96k/44.1k to 48k for r8brain SRC and matches 48k 1:1', () {
      const phoneSpecs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: 'Built-in Speaker',
        sampleRate: 48000,
        bitDepth: 32,
        isFloat: true,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 8.0,
        isExclusiveMode: false,
        deviceType: 'Built-in Speaker',
        supportedSampleRates: [48000],
        isFixedClock: true,
        directMultiRate: false,
      );

      final target96 = AudioOutputTargetResolver.resolve(
        specs: phoneSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 96000,
      );
      expect(target96.sampleRateHz, 48000);
      expect(target96.isUserOverride, isFalse);

      final target44 = AudioOutputTargetResolver.resolve(
        specs: phoneSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 44100,
      );
      expect(target44.sampleRateHz, 48000);

      final target48 = AudioOutputTargetResolver.resolve(
        specs: phoneSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 48000,
      );
      expect(target48.sampleRateHz, 48000);

      final targetNull = AudioOutputTargetResolver.resolve(
        specs: phoneSpecs,
        userSampleRateHz: 0,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: null,
      );
      expect(targetNull.sampleRateHz, 48000);

      final sig96to48 = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'FLAC',
          'inputSampleRate': 96000,
          'inputBitDepth': 24,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'decoderSrcActive': true,
          'deviceSrcActive': false,
          'resampleAlgorithm': 'r8brain24MinimumPhase',
        },
        phoneSpecs,
        activeDeviceType: 'Built-in Speaker',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );
      expect(sig96to48.srcLabel, 'ON (96.0 kHz → 48.0 kHz)');
      expect(sig96to48.resamplerLabel, contains('r8brain'));
      expect(
        sig96to48.nodes.any((n) => n.kind == ChainNodeKind.deviceSrc),
        isFalse,
      );
      final out96 = sig96to48.nodes.firstWhere((n) => n.kind == ChainNodeKind.output);
      expect(out96.liveParams['OS / HAL SRC'], 'None (1:1 Matched)');

      final sig48Matched = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'FLAC',
          'inputSampleRate': 48000,
          'inputBitDepth': 24,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
        },
        phoneSpecs,
        activeDeviceType: 'Built-in Speaker',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );
      expect(sig48Matched.srcLabel, 'OFF (Matched 48.0 kHz)');
    });

    test('AudioHardwareSpecs.fromAndroidMap parses isFixedClock and directMultiRate flags', () {
      final fixedSpecs = AudioHardwareSpecs.fromAndroidMap({
        'deviceName': 'Phone Speaker',
        'sampleRate': 48000,
        'bitDepth': 32,
        'isFloat': true,
        'deviceType': 'Built-in Speaker',
        'isFixedClock': true,
        'directMultiRate': false,
        'supportedSampleRates': [48000],
      });
      expect(fixedSpecs.isFixedClock, isTrue);
      expect(fixedSpecs.directMultiRate, isFalse);
      expect(fixedSpecs.sampleRate, 48000);

      final directDapSpecs = AudioHardwareSpecs.fromAndroidMap({
        'deviceName': 'LG Quad DAC',
        'sampleRate': 48000,
        'bitDepth': 24,
        'isFloat': false,
        'deviceType': '3.5mm Headphones',
        'isFixedClock': false,
        'directMultiRate': true,
        'supportedSampleRates': [44100, 48000, 88200, 96000, 192000],
      });
      expect(directDapSpecs.isFixedClock, isFalse);
      expect(directDapSpecs.directMultiRate, isTrue);
    });

    test('dynamic non-48k fixed-clock device capability (96 kHz) governs clamping and 1:1 SRC OFF', () {
      const soundcard96Specs = AudioHardwareSpecs(
        backendName: 'WASAPI',
        deviceName: 'Studio Soundcard (96 kHz Shared)',
        sampleRate: 96000,
        bitDepth: 32,
        isFloat: true,
        channels: 2,
        periodSizeFrames: 480,
        periodCount: 2,
        latencyMs: 10.0,
        isExclusiveMode: false,
        deviceType: 'Speakers / Output Device',
        supportedSampleRates: [96000],
        isFixedClock: true,
        directMultiRate: false,
      );

      expect(
        AudioOutputTargetResolver.resolve(
          specs: soundcard96Specs,
          userSampleRateHz: 0,
          userFormat: AudioFormat.f32,
          sourceSampleRateHz: 44100,
        ).sampleRateHz,
        96000,
      );
      expect(
        AudioOutputTargetResolver.resolve(
          specs: soundcard96Specs,
          userSampleRateHz: 0,
          userFormat: AudioFormat.f32,
          sourceSampleRateHz: 192000,
        ).sampleRateHz,
        96000,
      );
      expect(
        AudioOutputTargetResolver.resolve(
          specs: soundcard96Specs,
          userSampleRateHz: 0,
          userFormat: AudioFormat.f32,
          sourceSampleRateHz: 96000,
        ).sampleRateHz,
        96000,
      );

      final sig96Matched = buildSignalPath(
        {
          'hardware': {'outputFormat': 0, 'bitDepth': 32},
          'fileType': 'FLAC',
          'inputSampleRate': 96000,
          'inputBitDepth': 24,
          'engineSampleRate': 96000,
          'processingSampleRate': 96000,
          'processingChannels': 2,
          'outputSampleRate': 96000,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
        },
        soundcard96Specs,
        activeDeviceType: 'Speakers / Output Device',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );
      expect(sig96Matched.srcLabel, 'OFF (Matched 96.0 kHz)');
    });

    test('user sample-rate setting is honored within DAC capability and clamped above max', () {
      const dac192Specs = AudioHardwareSpecs(
        backendName: 'USB Direct',
        deviceName: '192 kHz DAC',
        sampleRate: 192000,
        bitDepth: 24,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 256,
        periodCount: 2,
        latencyMs: 2.7,
        isExclusiveMode: true,
        deviceType: 'USB DAC',
        supportedSampleRates: [44100, 48000, 88200, 96000, 176400, 192000],
        supportedBitDepths: [16, 24],
        usbDacAttached: true,
        isFixedClock: false,
        directMultiRate: true,
      );

      final user48 = AudioOutputTargetResolver.resolve(
        specs: dac192Specs,
        userSampleRateHz: 48000,
        userFormat: AudioFormat.s24,
        sourceSampleRateHz: 44100,
      );
      expect(user48.sampleRateHz, 48000);
      expect(user48.isUserOverride, isTrue);

      final user96 = AudioOutputTargetResolver.resolve(
        specs: dac192Specs,
        userSampleRateHz: 96000,
        userFormat: AudioFormat.s24,
        sourceSampleRateHz: 44100,
      );
      expect(user96.sampleRateHz, 96000);
      expect(user96.isUserOverride, isTrue);

      final user384Clamped = AudioOutputTargetResolver.resolve(
        specs: dac192Specs,
        userSampleRateHz: 384000,
        userFormat: AudioFormat.s24,
        sourceSampleRateHz: 44100,
      );
      expect(user384Clamped.sampleRateHz, 192000);
      expect(user384Clamped.isUserOverride, isTrue);

      const phone48Specs = AudioHardwareSpecs(
        backendName: 'AAudio / Android HAL',
        deviceName: 'Phone Speaker',
        sampleRate: 48000,
        bitDepth: 32,
        isFloat: true,
        channels: 2,
        periodSizeFrames: 192,
        periodCount: 2,
        latencyMs: 8.0,
        isExclusiveMode: false,
        deviceType: 'Built-in Speaker',
        supportedSampleRates: [48000],
        isFixedClock: true,
        directMultiRate: false,
      );
      final user192OnPhone = AudioOutputTargetResolver.resolve(
        specs: phone48Specs,
        userSampleRateHz: 192000,
        userFormat: AudioFormat.f32,
        sourceSampleRateHz: 44100,
      );
      expect(user192OnPhone.sampleRateHz, 48000);
      expect(user192OnPhone.isUserOverride, isTrue);

      const openMultiSpecs = AudioHardwareSpecs(
        backendName: 'WASAPI',
        deviceName: 'Open DAC',
        sampleRate: 48000,
        bitDepth: 24,
        isFloat: false,
        channels: 2,
        periodSizeFrames: 256,
        periodCount: 2,
        latencyMs: 5.0,
        isExclusiveMode: true,
        deviceType: 'USB DAC',
        supportedSampleRates: [],
        isFixedClock: false,
        directMultiRate: true,
      );
      final user96Open = AudioOutputTargetResolver.resolve(
        specs: openMultiSpecs,
        userSampleRateHz: 96000,
        userFormat: AudioFormat.s24,
        sourceSampleRateHz: 44100,
      );
      expect(user96Open.sampleRateHz, 96000);
      expect(user96Open.isUserOverride, isTrue);
    });

    test('AudioHardwareSpecs.fromNative reflects Exclusive vs Shared rates without hardcoding 48 kHz', () {
      final shared96 = AudioHardwareSpecs.fromNative(
        AEHardwareInfo(
          backendName: 'WASAPI',
          deviceName: 'Interface',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.f32,
          bitDepth: 32,
          isFloat: true,
          sampleRate: 96000,
          channels: 2,
          periodSizeFrames: 480,
          periodCount: 2,
          latencyMs: 10.0,
          isExclusiveMode: false,
          isDirectPcm: false,
        ),
        supportedSampleRates: [44100, 48000, 96000],
      );
      expect(shared96.isFixedClock, isTrue);
      expect(shared96.directMultiRate, isFalse);
      expect(shared96.supportedSampleRates, [96000]);
      expect(shared96.sampleRate, 96000);

      final exclMulti = AudioHardwareSpecs.fromNative(
        AEHardwareInfo(
          backendName: 'WASAPI',
          deviceName: 'Interface',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.s24,
          bitDepth: 24,
          isFloat: false,
          sampleRate: 96000,
          channels: 2,
          periodSizeFrames: 256,
          periodCount: 2,
          latencyMs: 5.3,
          isExclusiveMode: true,
          isDirectPcm: true,
        ),
        supportedSampleRates: [44100, 48000, 96000, 192000],
      );
      expect(exclMulti.isFixedClock, isFalse);
      expect(exclMulti.directMultiRate, isTrue);
      expect(exclMulti.supportedSampleRates, [44100, 48000, 96000, 192000]);

      final exclFixed44 = AudioHardwareSpecs.fromNative(
        AEHardwareInfo(
          backendName: 'WASAPI',
          deviceName: 'Fixed DAC',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.s16,
          bitDepth: 16,
          isFloat: false,
          sampleRate: 44100,
          channels: 2,
          periodSizeFrames: 256,
          periodCount: 2,
          latencyMs: 5.8,
          isExclusiveMode: true,
          isDirectPcm: true,
        ),
        supportedSampleRates: [44100],
      );
      expect(exclFixed44.isFixedClock, isTrue);
      expect(exclFixed44.directMultiRate, isFalse);
      expect(exclFixed44.supportedSampleRates, [44100]);
    });
  });

  group('Android Oboe hardware merge & priority rule', () {
    test('fixed-clock 48 kHz device with Oboe MMAP preserves fixed clock so app resamples once', () {
      final merged = AudioHardwareInspector.mergeAndroidAndNativeForTest(
        {
          'deviceType': 'Built-in Speaker',
          'deviceName': 'Pixel Speaker',
          'sampleRate': 48000,
          'bitDepth': 32,
          'isFloat': true,
          'channels': 2,
          'supportedSampleRates': [48000],
          'isFixedClock': true,
          'directMultiRate': false,
        },
        AEHardwareInfo(
          backendName: 'Oboe (AAudio MMAP)',
          deviceName: 'Oboe',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.s32,
          bitDepth: 32,
          isFloat: false,
          sampleRate: 48000,
          channels: 2,
          periodSizeFrames: 192,
          periodCount: 2,
          latencyMs: 4.0,
          isExclusiveMode: true,
          isDirectPcm: true,
        ),
      );

      expect(merged.backendName, 'Oboe (AAudio MMAP)');
      expect(merged.sampleRate, 48000);
      expect(merged.bitDepth, 32);
      expect(merged.isFixedClock, isTrue);
      expect(merged.directMultiRate, isFalse);
      expect(merged.isExclusiveMode, isTrue);
      expect(merged.isDirectPcm, isTrue);
      expect(merged.periodSizeFrames, 192);
      expect(merged.periodCount, 2);
      expect(merged.latencyMs, 4.0);

      final chain = merged.buildPowerampSignalChain();
      final backendNode =
          chain.firstWhere((n) => n.label == 'Oboe (AAudio MMAP)');
      expect(backendNode.sublabel, contains('MMAP Exclusive Low-Latency'));

      final target = AudioOutputTargetResolver.resolve(
        specs: merged,
        userSampleRateHz: 0,
        userFormat: AudioFormat.s32,
        sourceSampleRateHz: 96000,
      );
      expect(target.sampleRateHz, 48000);
    });

    test('multi-rate Android DAC with Oboe MMAP switches hardware rate to match 96 kHz song', () {
      final merged = AudioHardwareInspector.mergeAndroidAndNativeForTest(
        {
          'deviceType': 'Wired Headset',
          'deviceName': 'Hi-Fi DAC',
          'sampleRate': 48000,
          'bitDepth': 32,
          'isFloat': false,
          'channels': 2,
          'supportedSampleRates': [44100, 48000, 96000, 192000],
          'isFixedClock': false,
          'directMultiRate': true,
        },
        AEHardwareInfo(
          backendName: 'Oboe (AAudio MMAP)',
          deviceName: 'Oboe',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.s32,
          bitDepth: 32,
          isFloat: false,
          sampleRate: 96000,
          channels: 2,
          periodSizeFrames: 256,
          periodCount: 2,
          latencyMs: 5.3,
          isExclusiveMode: true,
          isDirectPcm: true,
        ),
      );

      expect(merged.backendName, 'Oboe (AAudio MMAP)');
      expect(merged.sampleRate, 96000);
      expect(merged.isFixedClock, isFalse);
      expect(merged.directMultiRate, isTrue);
      expect(merged.isExclusiveMode, isTrue);
      expect(merged.isDirectPcm, isTrue);

      final target = AudioOutputTargetResolver.resolve(
        specs: merged,
        userSampleRateHz: 0,
        userFormat: AudioFormat.s32,
        sourceSampleRateHz: 96000,
      );
      expect(target.sampleRateHz, 96000);
    });

    test('Bluetooth A2DP device with Oboe Shared preserves Oboe backend & latency without claiming exclusive', () {
      final merged = AudioHardwareInspector.mergeAndroidAndNativeForTest(
        {
          'deviceType': 'Bluetooth A2DP',
          'deviceName': 'Sony WH-1000XM5',
          'bluetoothCodec': 'LDAC',
          'btSampleRate': 96000,
          'btBitDepth': 24,
          'sampleRate': 48000,
          'bitDepth': 24,
          'isFloat': false,
          'channels': 2,
        },
        AEHardwareInfo(
          backendName: 'Oboe (AAudio)',
          deviceName: 'Oboe',
          dspHardware: '',
          socName: '',
          outputFormat: AudioFormat.f32,
          bitDepth: 32,
          isFloat: true,
          sampleRate: 48000,
          channels: 2,
          periodSizeFrames: 480,
          periodCount: 4,
          latencyMs: 18.0,
          isExclusiveMode: false,
          isDirectPcm: false,
        ),
      );

      expect(merged.backendName, 'Oboe (AAudio)');
      expect(merged.isExclusiveMode, isFalse);
      expect(merged.isDirectPcm, isFalse);
      expect(merged.latencyMs, 18.0);
      expect(merged.periodSizeFrames, 480);
      expect(merged.sampleRate, 96000);
    });
  });

  group('SignalPathCard & AudioEngineDiagnosticPanel widgets', () {
    testWidgets('collapses inactive stages, taps node to reveal live params, scales at 2.0x',
        (tester) async {
      final player = _FakeDiagPlayer({
        'hardware': {'outputFormat': 1, 'bitDepth': 16},
        'fileType': 'FLAC',
        'bitrateKbps': 900,
        'fileSizeBytes': 12000000,
        'inputSampleRate': 44100,
        'inputBitDepth': 16,
        'engineSampleRate': 44100,
        'processingSampleRate': 44100,
        'processingChannels': 2,
        'outputSampleRate': 44100,
        'precision64Reasons': Precision64Reason.intOutput,
        'float64EndToEnd': true,
        'activeLimiter': 2,
        'lookaheadLimiterEnabled': true,
        'limiterGainReductionDB': -0.4,
        'deviceLatencyMs': 10.5,
        'activeDspNodes': [
          {
            'id': 'harmonic_bass',
            'name': 'Harmonic Bass',
            'precision': 'F32',
            'summary': '80 Hz · +4.0 dB',
            'params': {'Cutoff': '80 Hz', 'Gain': '+4.0 dB'},
          },
          {
            'id': 'lookahead_limiter',
            'name': 'Look-Ahead Limiter',
            'precision': 'F64',
            'summary': 'Ceiling -1.0 dBTP · GR -0.4 dB',
            'params': {'Ceiling': '-1.0 dBTP', 'Live GR': '-0.4 dB'},
          },
        ],
        'eqEnabled': false,
      });

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 900),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: AudioEngineDiagnosticPanel(player: player),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Signal Path'), findsOneWidget);
      expect(find.text('0.00 ms'), findsNothing);
      expect(find.text('HARMONIC BASS'), findsOneWidget);
      expect(find.text('Cutoff'), findsNothing);

      // Tap the Harmonic Bass node to expand its real-time queried parameters
      await tester.ensureVisible(find.text('HARMONIC BASS'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('HARMONIC BASS'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cutoff'), findsOneWidget);
      expect(find.text('80 Hz'), findsOneWidget);
      expect(find.textContaining('inactive stages'), findsOneWidget);
      expect(find.text('ON (Look-Ahead)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
