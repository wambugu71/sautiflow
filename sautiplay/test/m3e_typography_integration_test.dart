import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/services/m3e_typography_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M3ETypographyService.emphasized produces standard M3E 15-role scale', () {
    final base = ThemeData.light().textTheme;
    final emp = M3ETypographyService.emphasized(base, rond: 10.0, bodyRond: 80.0);

    expect(emp.displayLarge?.fontSize, 57.0);
    expect(emp.displayLarge?.fontWeight, FontWeight.w500);
    expect(emp.headlineLarge?.fontSize, 32.0);
    expect(emp.titleMedium?.fontSize, 16.0);
    expect(emp.titleMedium?.fontWeight, FontWeight.w700);
    expect(emp.bodyLarge?.fontSize, 16.0);
    expect(emp.bodyLarge?.fontWeight, FontWeight.w500);
    expect(emp.labelLarge?.fontSize, 14.0);
    expect(emp.labelLarge?.fontWeight, FontWeight.w700);

    // Font variations
    final displayVars = emp.displayLarge?.fontVariations;
    expect(displayVars, isNotNull);
    final rondVar = displayVars!.firstWhere((v) => v.axis == 'ROND');
    expect(rondVar.value, 10.0);

    final bodyVars = emp.bodyLarge?.fontVariations;
    expect(bodyVars, isNotNull);
    final bodyRondVar = bodyVars!.firstWhere((v) => v.axis == 'ROND');
    expect(bodyRondVar.value, 80.0);
  });

  test('M3ETypographyService.resolveTextTheme resolves Outfit with M3E', () {
    final base = ThemeData.light().textTheme;
    final resolved = M3ETypographyService.resolveTextTheme(
      base,
      fontFamily: 'Outfit',
      useM3E: true,
      rond: 0.0,
      bodyRond: 50.0,
    );

    expect(resolved.displayLarge?.fontSize, 57.0);
    expect(resolved.displayLarge?.fontFamily, contains('Outfit'));
  });

  test('M3EEmphasizedTextThemeExtension toEmphasized works on TextTheme', () {
    final base = ThemeData.dark().textTheme;
    final emp = base.toEmphasized();
    expect(emp.displayMedium?.fontSize, 45.0);
    expect(emp.headlineSmall?.fontSize, 24.0);
  });
}
