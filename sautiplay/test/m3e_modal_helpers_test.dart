import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/widgets/m3e_modal_helpers.dart';

Widget _buildTestApp(Widget child) {
  return M3EMaterialApp(
    data: M3EThemeData.light(),
    theme: ThemeData.light(useMaterial3: true),
    // ignore: deprecated_member_use
    appBuilder: (context, appChild) => MaterialUiCompatibilityBridge(
      child: appChild ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'showSautiM3EBottomSheet provides Material ancestor for ActionChip',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showSautiM3EBottomSheet<void>(
                  context,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ActionChip(
                        label: const Text('Preset Chip'),
                        onPressed: () => tapped = true,
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Preset Chip'), findsOneWidget);

      await tester.tap(find.text('Preset Chip'));
      await tester.pump();
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'showSautiM3EDialog provides Material ancestor for ActionChip and ListTile',
    (tester) async {
      var chipTapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showSautiM3EDialog<void>(
                  context,
                  dialog: M3EDialog(
                    title: 'Test Dialog',
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ActionChip(
                          label: const Text('Dialog Chip'),
                          onPressed: () => chipTapped = true,
                        ),
                        const ListTile(title: Text('Dialog Tile')),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Dialog Chip'), findsOneWidget);
      expect(find.text('Dialog Tile'), findsOneWidget);

      await tester.tap(find.text('Dialog Chip'));
      await tester.pump();
      expect(chipTapped, isTrue);
    },
  );
}
