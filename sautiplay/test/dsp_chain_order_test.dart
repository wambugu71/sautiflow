import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/models/audio_profile.dart';
import 'package:sautiplay/services/app_state_service.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/widgets/dsp_chain_order_sheet.dart';
import 'package:sautiplay/widgets/signal_path.dart';
import 'package:sautiplay/widgets/signal_path_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DspNodeId normalization & serialization', () {
    test('defaultOrder contains every DspNodeId in canonical order', () {
      expect(DspNodeId.defaultOrder, equals(DspNodeId.values));
      expect(DspNodeId.isDefaultOrder(DspNodeId.defaultOrder), isTrue);
    });

    test('fromKeys deduplicates, ignores unknown keys, and appends missing', () {
      final order = DspNodeId.fromKeys([
        'reverb',
        'unknown_node',
        'reverb',
        'compressor',
      ]);
      expect(order.length, DspNodeId.values.length);
      expect(order[0], DspNodeId.reverb);
      expect(order[1], DspNodeId.compressor);
      expect(order[2], DspNodeId.preamp);
      expect(DspNodeId.isDefaultOrder(order), isFalse);
    });

    test('AppStateService saves and restores custom dspChainOrder', () async {
      PreferencesStore.instance.setMockValues({});
      final custom = DspNodeId.normalizeOrder([
        DspNodeId.reverb,
        DspNodeId.multibandFx,
        DspNodeId.compressor,
      ]);
      await AppStateService.instance.saveDspChainOrder(custom);
      final loaded = await AppStateService.instance.loadDspChainOrder();
      expect(loaded, equals(custom));
    });
  });

  group('reorderDspChainWithFilter', () {
    test('reorders within Active-Only view while keeping hidden modules intact', () {
      final full = [
        DspNodeId.preamp,
        DspNodeId.noiseGate, // hidden
        DspNodeId.compressor, // active 0
        DspNodeId.multibandEq, // hidden
        DspNodeId.reverb, // active 1
        DspNodeId.convolver, // active 2
      ];
      final visible = [
        DspNodeId.compressor,
        DspNodeId.reverb,
        DspNodeId.convolver,
      ];

      // Move Convolver (visible 2) above Compressor (visible 0)
      final movedUp = reorderDspChainWithFilter(
        fullOrder: full,
        visibleOrder: visible,
        oldVisibleIndex: 2,
        newVisibleIndex: 0,
      );
      expect(
        movedUp.take(6).toList(),
        equals([
          DspNodeId.preamp,
          DspNodeId.noiseGate,
          DspNodeId.convolver,
          DspNodeId.compressor,
          DspNodeId.multibandEq,
          DspNodeId.reverb,
        ]),
      );

      // Move Compressor (visible 0) to end (after Convolver -> newVisibleIndex 3)
      final movedDown = reorderDspChainWithFilter(
        fullOrder: full,
        visibleOrder: visible,
        oldVisibleIndex: 0,
        newVisibleIndex: 3,
      );
      expect(
        movedDown.take(6).toList(),
        equals([
          DspNodeId.preamp,
          DspNodeId.noiseGate,
          DspNodeId.multibandEq,
          DspNodeId.reverb,
          DspNodeId.convolver,
          DspNodeId.compressor,
        ]),
      );
    });
  });

  group('AudioProfile dspChainOrder round-trip', () {
    test('toJson and fromJson preserve dspChainOrder when present', () {
      final profile = AudioProfile(
        id: 'custom_chain_test',
        name: 'Custom Chain',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        dspChainOrder: const ['reverb', 'compressor', 'multiband_fx'],
      );
      final json = profile.toJson();
      expect(json['dspChainOrder'], ['reverb', 'compressor', 'multiband_fx']);

      final decoded = AudioProfile.fromJson(json);
      expect(
        decoded.dspChainOrder,
        equals(['reverb', 'compressor', 'multiband_fx']),
      );
    });

    test('fromJson handles profiles without dspChainOrder', () {
      final decoded = AudioProfile.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });
      expect(decoded.dspChainOrder, isNull);
    });
  });

  group('DspChainOrderSheet & SignalPathCard widgets', () {
    testWidgets('DspChainOrderSheet renders anchors, toggles filter, and resets',
        (tester) async {
      List<DspNodeId>? latestOrder;
      bool resetCalled = false;

      final initial = DspNodeId.normalizeOrder([
        DspNodeId.reverb,
        DspNodeId.compressor,
      ]);

      final nodes = [
        const DspChainNodeInfo(
          id: DspNodeId.reverb,
          title: 'Reverb',
          subtitle: 'Dattorro Tank',
          icon: Icons.waves,
          isEnabled: true,
        ),
        const DspChainNodeInfo(
          id: DspNodeId.compressor,
          title: 'Compressor',
          subtitle: '-20 dB / 4.0:1',
          icon: Icons.tune,
          isEnabled: true,
        ),
      ];

      await tester.pumpWidget(
        AppThemeProvider(
          themeData: AppThemeService.instance.currentData,
          child: MaterialApp(
            home: Scaffold(
              body: DspChainOrderSheet(
                initialOrder: initial,
                nodes: nodes,
                onOrderChanged: (o) => latestOrder = o,
                onResetOrder: () => resetCalled = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('DSP Signal Chain'), findsOneWidget);
      expect(find.text('INPUT STAGE (PINNED)'), findsOneWidget);
      expect(find.text('OUTPUT PROTECTION (PINNED)'), findsOneWidget);
      expect(find.text('Active Only (2)'), findsOneWidget);
      expect(find.text('Reverb'), findsOneWidget);
      expect(find.text('Compressor'), findsOneWidget);

      // Tap Reset button
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(resetCalled, isTrue);
      expect(latestOrder, equals(DspNodeId.defaultOrder));
    });

    testWidgets('SignalPathCard shows REORDER pill when onEditChainOrder set',
        (tester) async {
      bool tapped = false;
      const path = SignalPathResult(
        nodes: [
          SignalPathNode(
            kind: ChainNodeKind.source,
            title: 'SOURCE',
            detail: 'FLAC · 48.0 kHz · 24-bit · 2 ch',
          ),
          SignalPathNode(
            kind: ChainNodeKind.output,
            title: 'OUTPUT',
            detail: '48.0 kHz / 24-bit Int (DAC)',
          ),
        ],
        inactiveStageNames: [],
        dspPrecisionLabel: 'Float64',
        outputLabel: '48.0 kHz / 24-bit Int',
        srcLabel: 'OFF',
        resamplerLabel: '—',
        limiterLabel: 'OFF',
      );

      await tester.pumpWidget(
        AppThemeProvider(
          themeData: AppThemeService.instance.currentData,
          child: MaterialApp(
            home: Scaffold(
              body: SignalPathCard(
                path: path,
                cardBg: Colors.black,
                outlineColor: Colors.grey,
                isDark: true,
                textPrimary: Colors.white,
                textMuted: Colors.white70,
                onEditChainOrder: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('REORDER'), findsOneWidget);
      await tester.tap(find.text('REORDER'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
