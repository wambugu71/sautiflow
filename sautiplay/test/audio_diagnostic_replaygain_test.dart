import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/widgets/audio_engine_diagnostic_panel.dart';

class MockIsolateAudioPlayer extends Fake implements IsolateAudioPlayer {
  Map<String, dynamic> telemetryData;

  MockIsolateAudioPlayer(this.telemetryData);

  @override
  Future<Map<String, dynamic>> getEngineTelemetry() async {
    return telemetryData;
  }

  @override
  void setClippingDetectionEnabled(bool enabled) {}

  @override
  void setTruePeakMeterEnabled(bool enabled) {}

  @override
  void setLoudnessMeterEnabled(bool enabled) {}
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

  testWidgets('AudioEngineDiagnosticPanel adapts colors to Light Theme', (tester) async {
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

    final lightTheme = AppThemeService.dataFor(AppThemeId.light);

    await tester.pumpWidget(
      AppThemeProvider(
        themeData: lightTheme,
        child: MaterialApp(
          theme: lightTheme.toThemeData(),
          home: Scaffold(
            body: AudioEngineDiagnosticPanel(player: player),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Audio Info & Diagnostics'));
    expect(title.style?.color, const Color(0xFF1A1A2E));

    final formatVal = tester.widget<Text>(find.text('FLAC'));
    expect(formatVal.style?.color, lightTheme.primary);
  });

  testWidgets('AudioEngineDiagnosticPanel adapts colors to Sunset (Orange) Theme', (tester) async {
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

    final sunsetTheme = AppThemeService.dataFor(AppThemeId.orange);

    await tester.pumpWidget(
      AppThemeProvider(
        themeData: sunsetTheme,
        child: MaterialApp(
          theme: sunsetTheme.toThemeData(),
          home: Scaffold(
            body: AudioEngineDiagnosticPanel(player: player),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Audio Info & Diagnostics'));
    expect(title.style?.color, Colors.white);

    final formatVal = tester.widget<Text>(find.text('FLAC'));
    expect(formatVal.style?.color, const Color(0xFFFF7A00));
  });

  testWidgets('AudioEngineDiagnosticPanel adapts colors to AMOLED Black Theme', (tester) async {
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

    final amoledTheme = AppThemeService.dataFor(AppThemeId.amoledBlack);

    await tester.pumpWidget(
      AppThemeProvider(
        themeData: amoledTheme,
        child: MaterialApp(
          theme: amoledTheme.toThemeData(),
          home: Scaffold(
            body: AudioEngineDiagnosticPanel(player: player),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final formatVal = tester.widget<Text>(find.text('FLAC'));
    expect(formatVal.style?.color, const Color(0xFF00E5FF));
  });
}
