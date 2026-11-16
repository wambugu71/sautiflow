import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';
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

    test('Z5 float island emits F64 -> F32 -> F64 warning arrow', () {
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
          'float64EndToEnd': false,
          'decoderSrcActive': false,
          'deviceSrcActive': false,
          'reverbEnabled': true,
          'reverbEngine': 'Dattorro Plate',
          'activeNodeMask': ActiveNodeMask.z5Spatial | ActiveNodeMask.floatIslandZ5,
        },
        _specs(sampleRate: 48000, bitDepth: 24),
        activeDeviceType: 'Headphones',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      final z5 = result.nodes.firstWhere((n) => n.badge == 'Z5');
      expect(z5.isWarning, isTrue);
      expect(z5.outgoingArrow?.formatLabel, 'F64 → F32 → F64');
      expect(z5.outgoingArrow?.note, 'float island');
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

    test('Z1 Restoration only lists actually enabled sub-nodes', () {
      final result = buildSignalPath(
        {
          'hardware': {'outputFormat': 's16', 'bitDepth': 16},
          'fileType': 'FLAC',
          'inputSampleRate': 48000,
          'inputBitDepth': 16,
          'engineSampleRate': 48000,
          'processingSampleRate': 48000,
          'processingChannels': 2,
          'outputSampleRate': 48000,
          'activeNodeMask':
              ActiveNodeMask.z1Restoration | ActiveNodeMask.z1Subsonic,
        },
        _specs(sampleRate: 48000, bitDepth: 16),
        activeDeviceType: 'Speaker',
        isCastingOut: false,
        castMode: CastAudioMode.dspProcessed,
        castMaxSampleRateHz: 96000,
      );

      final z1 = result.nodes.firstWhere((n) => n.badge == 'Z1');
      expect(z1.detail, 'Subsonic / Protection Filter');
      expect(z1.detail, isNot(contains('Noise Gate')));
      expect(z1.detail, isNot(contains('Expander')));
    });
  });

  group('SignalPathCard & AudioEngineDiagnosticPanel widgets', () {
    testWidgets('collapses inactive stages, omits 0.00 ms, scales at 2.0x',
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
        'activeNodeMask': ActiveNodeMask.z4DynamicsEq,
        'eqEnabled': true,
      });

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: MaterialApp(
            home: Scaffold(
              body: AudioEngineDiagnosticPanel(player: player),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Signal Path'), findsOneWidget);
      expect(find.text('0.00 ms'), findsNothing);
      expect(find.textContaining('inactive stages'), findsOneWidget);
      expect(find.text('ON (Look-Ahead)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
