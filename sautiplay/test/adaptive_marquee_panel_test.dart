import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/now_playing_screen.dart';
import 'package:sautiplay/widgets/adaptive_marquee_text.dart';
import 'package:sautiplay/widgets/audio_engine_diagnostic_panel.dart';
import 'package:sautiplay/widgets/music_info_dialog.dart';

class FakeDiagnosticPlayer extends Fake implements IsolateAudioPlayer {
  final Map<String, dynamic> telemetryData;

  FakeDiagnosticPlayer(this.telemetryData);

  @override
  Stream<PlayerStatus> get statusStream => const Stream<PlayerStatus>.empty();

  @override
  Stream<StreamTelemetry> get streamTelemetryStream =>
      const Stream<StreamTelemetry>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Future<Map<String, dynamic>> getEngineTelemetry() async => telemetryData;

  @override
  Future<AEHardwareInfo> getHardwareInfo() async =>
      Future<AEHardwareInfo>.error(UnimplementedError());

  @override
  Future<Map<String, dynamic>> getAudioProperties() async =>
      <String, dynamic>{};

  @override
  void setClippingDetectionEnabled(bool enabled) {}

  @override
  void setTruePeakMeterEnabled(bool enabled) {}

  @override
  void setLoudnessMeterEnabled(bool enabled) {}

  @override
  void setRate(double rate) {}

  @override
  void setPitch(double pitch) {}

  @override
  void setPitchCorrection(bool enabled) {}

  @override
  void setAbRepeat({
    required bool enabled,
    required double startSeconds,
    required double endSeconds,
  }) {}
}

/// Unmounts active [Marquee] / diagnostic panel widgets and drains delayed
/// scroll timers so Flutter test invariants exit cleanly.
Future<void> _disposeMarqueeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PreferencesStore.instance.setMockValues(<String, Object>{});
  });

  group('AdaptiveMarqueeText', () {
    testWidgets('renders static aligned Text when content fits bounded width',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: AdaptiveMarqueeText(
                text: 'FLAC',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Marquee), findsNothing);
      final textWidget = tester.widget<Text>(find.text('FLAC'));
      expect(textWidget.textAlign, TextAlign.right);
      expect(textWidget.maxLines, 1);
      expect(textWidget.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('switches to Marquee when content overflows narrow width',
        (tester) async {
      const longText =
          'Audiophile High-Resolution USB-C External DAC Audio Output';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 140,
              child: AdaptiveMarqueeText(
                text: longText,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Marquee), findsOneWidget);

      await _disposeMarqueeTree(tester);
    });

    testWidgets('scales height with TextScaler without layout overflow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: SizedBox(
                width: 160,
                child: AdaptiveMarqueeText(
                  text: 'Sample Rate 192kHz',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Marquee), findsOneWidget);

      await _disposeMarqueeTree(tester);
    });

    testWidgets(
        'uses horizontal scroll fallback without ellipsis when animations disabled',
        (tester) async {
      const longText = 'Very Long Song Name That Does Not Fit On Mobile';
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 120,
                child: AdaptiveMarqueeText(
                  text: longText,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Marquee), findsNothing);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text(longText));
      expect(textWidget.overflow, isNot(TextOverflow.ellipsis));
    });
  });

  group('Diagnostic panel & sheets on narrow mobile viewport', () {
    testWidgets(
        'AudioEngineDiagnosticPanel DSP Status marquees long values and keeps short values static on 360px mobile screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = FakeDiagnosticPlayer(<String, dynamic>{
        'hardware': <String, dynamic>{
          'backendName': 'WASAPI (Exclusive High-Resolution Mode)',
          'sampleRate': 192000,
          'bitDepth': 32,
          'isExclusiveMode': true,
        },
        'fileType': 'FLAC',
        'bitrateKbps': 4608,
        'fileSizeBytes': 52000000,
        'inputSampleRate': 192000,
        'inputBitDepth': 24,
        'processingSampleRate': 192000,
        'processingChannels': 2,
        'outputSampleRate': 192000,
        'replayGainTrack': -4.25,
        'replayGainAlbum': -5.10,
        'crossfeedEnabled': true,
        'crossfeedMix': 0.3,
        'crossfeedAlgo': 'Ambiophonics RACE Studio Matrix',
        'loudnessNormalizerEnabled': true,
        'loudnessNormalizerTarget': -14.0,
        'loudnessNormalizerGainDb': -2.4,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioEngineDiagnosticPanel(player: player),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('DSP Status'), findsOneWidget);

      // Short telemetry values still render cleanly as static Text.
      final flacText = tester.widget<Text>(find.text('FLAC'));
      expect(flacText.overflow, isNot(TextOverflow.ellipsis));

      // Long telemetry values on a narrow 360px mobile viewport use Marquee instead of ellipsis.
      expect(
        find.descendant(
          of: find.byType(AudioEngineDiagnosticPanel),
          matching: find.byType(Marquee),
        ),
        findsWidgets,
      );

      // No Text widget inside the panel should truncate via TextOverflow.ellipsis.
      final panelTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(AudioEngineDiagnosticPanel),
          matching: find.byType(Text),
        ),
      );
      expect(
        panelTexts.where((t) => t.overflow == TextOverflow.ellipsis),
        isEmpty,
      );

      await _disposeMarqueeTree(tester);
    });

    testWidgets(
        'MusicInfoDialog M3EBottomSheet uses Marquee for overflowing title and artist on mobile',
        (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  MusicInfoDialog.show(
                    ctx,
                    title:
                        'Symphony No. 9 in D Minor, Op. 125 (2026 Audiophile Remaster)',
                    artist:
                        'Ludwig van Beethoven & The Vienna Philharmonic Studio Orchestra',
                    sourceType: 'local',
                    duration: const Duration(minutes: 15, seconds: 24),
                  );
                },
                child: const Text('Open Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(MusicInfoDialog),
          matching: find.byType(Marquee),
        ),
        findsNWidgets(2),
      );

      await _disposeMarqueeTree(tester);
    });
  });

  group('NowPlayingScreen mobile marquee', () {
    testWidgets(
        'overflowing header, track title, and artist render via Marquee without ellipsis on 360px mobile screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final player = FakeDiagnosticPlayer(<String, dynamic>{
        'hardware': <String, dynamic>{},
      });
      final statusNotifier = ValueNotifier<PlayerStatus>(
        const PlayerStatus(
          isPlaying: false,
          positionSeconds: 12,
          durationSeconds: 240,
          currentIndex: 0,
          playlistCount: 1,
          shuffleEnabled: false,
          loopMode: LoopMode.off,
        ),
      );
      addTearDown(statusNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingScreen(
            statusNotifier: statusNotifier,
            player: player,
            getTitle: (_) =>
                'Ultra Long Progressive Instrumental Track Title That Exceeds Mobile Viewport',
            artist:
                'Ultra Long Collaborating Artists Ensemble & Featuring Studio Collective',
            onMinimize: () {},
            onPlayQueueIndex: (_) {},
            onReorderQueue: (_, __) {},
            sourceType: 'local',
            analyzerEnabled: false,
            onAnalyzerEnabledChanged: (_) {},
            analyzerType: 'spectrum',
            analyzerAutoFit: true,
            analyzerShowGrids: true,
            outputSampleRate: 48000,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);

      // Header, track title, and artist subtitle render via Marquee on narrow mobile layout.
      final titleMarquee = find.byWidgetPredicate(
        (w) =>
            w is AdaptiveMarqueeText &&
            w.text.contains('Ultra Long Progressive'),
      );
      final artistMarquee = find.byWidgetPredicate(
        (w) =>
            w is AdaptiveMarqueeText &&
            w.text.contains('Ultra Long Collaborating'),
      );
      expect(titleMarquee, findsOneWidget);
      expect(artistMarquee, findsOneWidget);
      expect(
        find.descendant(of: titleMarquee, matching: find.byType(Marquee)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: artistMarquee, matching: find.byType(Marquee)),
        findsOneWidget,
      );

      final adaptiveTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(AdaptiveMarqueeText),
          matching: find.byType(Text),
        ),
      );
      expect(
        adaptiveTexts.where((t) => t.overflow == TextOverflow.ellipsis),
        isEmpty,
      );

      await _disposeMarqueeTree(tester);
    });
  });
}
