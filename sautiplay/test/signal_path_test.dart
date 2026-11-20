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
      expect(streamDecSrc.liveParams.containsKey('Phase'), isFalse);

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
