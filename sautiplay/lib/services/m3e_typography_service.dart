import 'dart:ui' show FontVariation;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// Representation of a selectable font family with aesthetic metadata.
@immutable
class AppFontOption {
  final String id;
  final String name;
  final String category;
  final String description;
  final bool isVariable;

  const AppFontOption({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.isVariable = false,
  });
}

/// Official Material 3 Expressive (M3E) Emphasized Typography scale and
/// font-resolution service.
///
/// Material 3 Expressive introduces an elevated typographic scale featuring
/// increased font weights, optical sizes (`opsz`), and rounded variation axes (`ROND`).
abstract final class M3ETypographyService {
  /// Curated collection of high-quality fonts for audiophile and modern UI presentation.
  static const List<AppFontOption> availableFonts = [
    AppFontOption(
      id: 'System',
      name: 'System Default',
      category: 'Platform Native',
      description: 'Default OS font (Roboto, SF Pro, Segoe UI) with native rendering',
    ),
    AppFontOption(
      id: 'Google Sans Flex',
      name: 'Google Sans Flex',
      category: 'M3 Variable',
      description: 'Official M3 Expressive variable font with wght, opsz & ROND axes',
      isVariable: true,
    ),
    AppFontOption(
      id: 'Outfit',
      name: 'Outfit',
      category: 'Expressive Sans',
      description: 'Iconic M3 geometric circles, bold headings, and clean balance',
    ),
    AppFontOption(
      id: 'Plus Jakarta Sans',
      name: 'Plus Jakarta Sans',
      category: 'Neo-Grotesque',
      description: 'Contemporary, sharp grotesque with high legibility and refined elegance',
    ),
    AppFontOption(
      id: 'Inter',
      name: 'Inter',
      category: 'Modern Grotesque',
      description: 'Precision-engineered screen typography with tall x-height',
    ),
    AppFontOption(
      id: 'Poppins',
      name: 'Poppins',
      category: 'Geometric Rounded',
      description: 'Friendly geometric curves with circular stroke terminals',
    ),
    AppFontOption(
      id: 'Lexend',
      name: 'Lexend',
      category: 'Reading Flow',
      description: 'Scientifically engineered for effortless reading cadence and instant scanning',
    ),
    AppFontOption(
      id: 'Manrope',
      name: 'Manrope',
      category: 'Semi-Round Sans',
      description: 'Modern crossover of semi-rounded and geometric grotesque styling',
    ),
    AppFontOption(
      id: 'Space Grotesk',
      name: 'Space Grotesk',
      category: 'Cyber & Tech',
      description: 'Bold monospace-infused proportional grotesque with distinctive tech quirks',
    ),
    AppFontOption(
      id: 'Montserrat',
      name: 'Montserrat',
      category: 'Architectural',
      description: 'Classic poster and architectural geometric typography with wide proportions',
    ),
    AppFontOption(
      id: 'JetBrains Mono',
      name: 'JetBrains Mono',
      category: 'Audiophile Monospace',
      description: 'Engineered monospace typography ideal for frequencies, bitrates, and telemetry',
    ),
    AppFontOption(
      id: 'Playfair Display',
      name: 'Playfair Display',
      category: 'Classical Serif',
      description: 'High-contrast luxury serif for acoustic, classical and jazz music lovers',
    ),
  ];

  /// Builds an emphasized [TextTheme] according to the official Material 3
  /// Expressive specification, configuring elevated weights, optical sizing (opsz),
  /// and corner roundness (ROND).
  static TextTheme emphasized(
    TextTheme base, {
    double rond = 0.0,
    double? bodyRond,
  }) {
    final effectiveBodyRond = bodyRond ?? rond;

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 57.0,
        height: 64.0 / 57.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 57.0),
        ],
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 45.0,
        height: 52.0 / 45.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 45.0),
        ],
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 36.0,
        height: 44.0 / 36.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 36.0),
        ],
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 32.0,
        height: 40.0 / 32.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 32.0),
        ],
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 28.0,
        height: 36.0 / 28.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 28.0),
        ],
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 24.0,
        height: 32.0 / 24.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 24.0),
        ],
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 22.0,
        height: 28.0 / 22.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 22.0),
        ],
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16.0,
        height: 24.0 / 16.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 600.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 16.0),
        ],
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14.0,
        height: 20.0 / 14.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 600.0),
          FontVariation('ROND', rond),
          const FontVariation('opsz', 14.0),
        ],
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16.0,
        height: 24.0 / 16.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 16.0),
        ],
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14.0,
        height: 20.0 / 14.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 14.0),
        ],
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12.0,
        height: 16.0 / 12.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        fontVariations: [
          const FontVariation('wght', 500.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 12.0),
        ],
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14.0,
        height: 20.0 / 14.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.0,
        fontVariations: [
          const FontVariation('wght', 600.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 14.0),
        ],
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12.0,
        height: 16.0 / 12.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        fontVariations: [
          const FontVariation('wght', 600.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 12.0),
        ],
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11.0,
        height: 16.0 / 11.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        fontVariations: [
          const FontVariation('wght', 600.0),
          FontVariation('ROND', effectiveBodyRond),
          const FontVariation('opsz', 11.0),
        ],
      ),
    );
  }

  /// Resolves the full [TextTheme] based on selected font family, M3E scale toggle,
  /// and roundness axes.
  static TextTheme resolveTextTheme(
    TextTheme base, {
    required String fontFamily,
    required bool useM3E,
    double rond = 0.0,
    double? bodyRond,
  }) {
    TextTheme theme = base;

    if (fontFamily.isNotEmpty && fontFamily != 'System') {
      if (fontFamily == 'Google Sans Flex') {
        theme = theme.apply(fontFamily: 'GoogleSansFlex');
      } else {
        try {
          theme = GoogleFonts.getTextTheme(fontFamily, theme);
        } catch (_) {
          theme = theme.apply(fontFamily: fontFamily);
        }
      }
    }

    if (useM3E) {
      theme = emphasized(theme, rond: rond, bodyRond: bodyRond);
    }

    // Preserve non-Latin Ethiopic fallback scripts
    return theme.apply(
      fontFamilyFallback: const ['Noto Sans Ethiopic', 'Nyala', 'Ebrima'],
    );
  }

  /// Returns a preview [TextStyle] for displaying a sample in the font picker card.
  static TextStyle getPreviewStyle(String fontFamily, {TextStyle? baseStyle}) {
    final style = baseStyle ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    if (fontFamily == 'System' || fontFamily.isEmpty) {
      return style;
    }
    if (fontFamily == 'Google Sans Flex') {
      return style.copyWith(fontFamily: 'GoogleSansFlex');
    }
    try {
      return GoogleFonts.getFont(fontFamily, textStyle: style);
    } catch (_) {
      return style.copyWith(fontFamily: fontFamily);
    }
  }
}

/// Extension on [TextTheme] to access Material 3 Expressive Emphasized typography.
extension M3EEmphasizedTextThemeExtension on TextTheme {
  /// Computes the emphasized [TextTheme] using default roundness (`ROND: 0.0`).
  TextTheme get emphasized => M3ETypographyService.emphasized(this);

  /// Converts this [TextTheme] to an emphasized scale with custom [rond] and [bodyRond] axes.
  TextTheme toEmphasized({double rond = 0.0, double? bodyRond}) {
    return M3ETypographyService.emphasized(this, rond: rond, bodyRond: bodyRond);
  }
}

/// Extension on [ThemeData] for convenience access to emphasized typography.
extension M3EEmphasizedThemeDataExtension on ThemeData {
  /// Returns the emphasized [TextTheme] from the current [textTheme].
  TextTheme get emphasizedTextTheme => textTheme.emphasized;
}

/// Extension on [BuildContext] for ergonomic access to emphasized typography.
extension M3EEmphasizedContextExtension on BuildContext {
  /// Returns the current theme's emphasized [TextTheme].
  TextTheme get emphasizedTextTheme => Theme.of(this).textTheme.emphasized;
}
