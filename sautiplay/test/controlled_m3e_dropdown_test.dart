import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/widgets/app_m3e_widgets.dart';

Widget _buildHarness(Widget child) {
  return M3EMaterialApp(
    data: M3EThemeData.light(),
    theme: ThemeData.light(useMaterial3: true),
    // ignore: deprecated_member_use
    appBuilder: (context, appChild) => MaterialUiCompatibilityBridge(
      child: appChild ?? const SizedBox.shrink(),
    ),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'ControlledM3EDropdown allows re-selecting initial value after change',
    (tester) async {
      String selected = 'Option A';
      final changes = <String>[];

      await tester.pumpWidget(
        _buildHarness(
          StatefulBuilder(
            builder: (context, setState) {
              return ControlledM3EDropdown<String>(
                value: selected,
                items: const [
                  M3EDropdownItem(value: 'Option A', label: 'Option A'),
                  M3EDropdownItem(value: 'Option B', label: 'Option B'),
                  M3EDropdownItem(value: 'Option C', label: 'Option C'),
                ],
                onChanged: (val) {
                  changes.add(val);
                  setState(() => selected = val);
                },
              );
            },
          ),
        ),
      );

      expect(find.text('Option A'), findsOneWidget);

      // Select Option B
      await tester.tap(find.text('Option A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option B').last);
      await tester.pumpAndSettle();

      expect(selected, 'Option B');
      expect(changes, ['Option B']);

      // Re-select initial Option A (previously blocked by stale closure value)
      await tester.tap(find.text('Option B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option A').last);
      await tester.pumpAndSettle();

      expect(selected, 'Option A');
      expect(changes, ['Option B', 'Option A']);
    },
  );

  testWidgets(
    'ControlledM3EDropdown invokes updated items and handler when engine switches',
    (tester) async {
      int engine = 0; // 0 = Dattorro, 1 = Diffusion
      String dattorroPreset = 'Custom';
      String diffusionPreset = 'Custom';

      await tester.pumpWidget(
        _buildHarness(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(() => engine = 1),
                    child: const Text('Switch Engine'),
                  ),
                  if (engine == 0)
                    ControlledM3EDropdown<String>(
                      key: ValueKey(engine),
                      value: dattorroPreset,
                      items: const [
                        M3EDropdownItem(value: 'Custom', label: 'Custom'),
                        M3EDropdownItem(
                            value: 'Studio Plate', label: 'Studio Plate'),
                      ],
                      onChanged: (v) => setState(() => dattorroPreset = v),
                    )
                  else
                    ControlledM3EDropdown<String>(
                      key: ValueKey(engine),
                      value: diffusionPreset,
                      items: const [
                        M3EDropdownItem(value: 'Custom', label: 'Custom'),
                        M3EDropdownItem(
                            value: 'Shimmer Diffuse', label: 'Shimmer Diffuse'),
                      ],
                      onChanged: (v) => setState(() => diffusionPreset = v),
                    ),
                ],
              );
            },
          ),
        ),
      );

      // Switch to engine 1 (Diffusion)
      await tester.tap(find.text('Switch Engine'));
      await tester.pumpAndSettle();

      // Open dropdown and select Diffusion preset
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shimmer Diffuse').last);
      await tester.pumpAndSettle();

      expect(diffusionPreset, 'Shimmer Diffuse');
      expect(dattorroPreset, 'Custom');
      expect(find.text('Shimmer Diffuse'), findsOneWidget);
    },
  );

  testWidgets(
    'ControlledM3EDropdown updates callback even without a ValueKey change',
    (tester) async {
      bool useSecondHandler = false;
      String activeVal = 'A1';
      String? lastHandlerCalled;

      await tester.pumpWidget(
        _buildHarness(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      useSecondHandler = true;
                      activeVal = 'B1';
                    }),
                    child: const Text('Swap Props'),
                  ),
                  ControlledM3EDropdown<String>(
                    value: activeVal,
                    items: useSecondHandler
                        ? const [
                            M3EDropdownItem(value: 'B1', label: 'B1'),
                            M3EDropdownItem(value: 'B2', label: 'B2'),
                          ]
                        : const [
                            M3EDropdownItem(value: 'A1', label: 'A1'),
                            M3EDropdownItem(value: 'A2', label: 'A2'),
                          ],
                    onChanged: (v) => setState(() {
                      lastHandlerCalled =
                          useSecondHandler ? 'second:$v' : 'first:$v';
                      activeVal = v;
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Swap Props'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('B1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B2').last);
      await tester.pumpAndSettle();

      expect(lastHandlerCalled, 'second:B2');
      expect(activeVal, 'B2');
    },
  );

  testWidgets(
    'ControlledM3EDropdown keeps selection when re-tapping active item',
    (tester) async {
      String selected = 'Smooth Cloud';

      await tester.pumpWidget(
        _buildHarness(
          StatefulBuilder(
            builder: (context, setState) {
              return ControlledM3EDropdown<String>(
                value: selected,
                items: const [
                  M3EDropdownItem(value: 'Custom', label: 'Custom'),
                  M3EDropdownItem(value: 'Smooth Cloud', label: 'Smooth Cloud'),
                ],
                onChanged: (v) => setState(() => selected = v),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Smooth Cloud'));
      await tester.pumpAndSettle();

      // Re-tap the already-selected item inside the open menu
      await tester.tap(find.text('Smooth Cloud').last);
      await tester.pumpAndSettle();

      expect(selected, 'Smooth Cloud');
      expect(find.text('Smooth Cloud'), findsOneWidget);
      expect(find.text('Select'), findsNothing);
    },
  );
}
