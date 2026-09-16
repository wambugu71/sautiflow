import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/widgets/audio_engine_diagnostic_panel.dart';

class MockIsolateAudioPlayer extends Fake implements IsolateAudioPlayer {
  Map<String, dynamic> telemetryData;

  MockIsolateAudioPlayer(this.telemetryData);

  @override
  Future<Map<String, dynamic>> getEngineTelemetry() async {
    return telemetryData;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AudioEngineDiagnosticPanel displays "null" when ReplayGain is unavailable', (tester) async {
    final player = MockIsolateAudioPlayer({
      'hardware': {},
      'fileType': 'FLAC',
      'bitrateKbps': 1411,
      'fileSizeBytes': 25000000,
      'inputSampleRate': 44100,
      'inputBitDepth': 16,
      'processingSampleRate': 44100,
      'processingChannels': 2,
      'outputSampleRate': 44100,
      'replayGainTrack': null,
      'replayGainAlbum': null,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioEngineDiagnosticPanel(player: player),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ReplayGain'), findsOneWidget);
    expect(find.text('null'), findsOneWidget);
  });

  testWidgets('AudioEngineDiagnosticPanel displays track ReplayGain when present', (tester) async {
    final player = MockIsolateAudioPlayer({
      'hardware': {},
      'fileType': 'FLAC',
      'bitrateKbps': 1411,
      'fileSizeBytes': 25000000,
      'inputSampleRate': 44100,
      'inputBitDepth': 16,
      'processingSampleRate': 44100,
      'processingChannels': 2,
      'outputSampleRate': 44100,
      'replayGainTrack': -4.20,
      'replayGainAlbum': null,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioEngineDiagnosticPanel(player: player),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ReplayGain'), findsOneWidget);
    expect(find.text('-4.20 dB (Track)'), findsOneWidget);
  });

  testWidgets('AudioEngineDiagnosticPanel displays both track and album ReplayGain when present', (tester) async {
    final player = MockIsolateAudioPlayer({
      'hardware': {},
      'fileType': 'FLAC',
      'bitrateKbps': 1411,
      'fileSizeBytes': 25000000,
      'inputSampleRate': 44100,
      'inputBitDepth': 16,
      'processingSampleRate': 44100,
      'processingChannels': 2,
      'outputSampleRate': 44100,
      'replayGainTrack': 1.25,
      'replayGainAlbum': -0.50,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioEngineDiagnosticPanel(player: player),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ReplayGain'), findsOneWidget);
    expect(find.text('+1.25 dB (Track) / -0.50 dB (Album)'), findsOneWidget);
  });
}
