import 'dart:math' as math;

import 'package:material_color_utilities/material_color_utilities.dart';

import 'artwork_palette_models.dart';
import 'palette_personality_analyzer.dart';
import 'perceptual_color_analyzer.dart';

/// Generates a refined, dark-surface-compatible semantic UI palette using HCT
/// harmonization and explicit WCAG 2.1 contrast enforcement.
class AdaptiveThemeGenerator {
  AdaptiveThemeGenerator._();

  /// Bump whenever clustering, personality, or theme generation changes so
  /// persistent cached palettes automatically refresh.
  static const int kAlgorithmVersion = 1;

  static const int _darkInk = 0xFF0A0D12;
  static const int _lightInk = 0xFFF8FAFC;

  /// SautiPlay's proven deep dark-blue fallback when artwork is unavailable or
  /// contrast recovery cannot converge.
  static AdaptiveSemanticPalette fallbackPalette() {
    return const AdaptiveSemanticPalette(
      background: 0xFF0F172A,
      surface: 0xFF1A2438,
      elevatedSurface: 0xFF233047,
      primaryAccent: 0xFF38BDF8,
      secondaryAccent: 0xFF7DD3FC,
      onPrimary: 0xFF08121A,
      onSecondary: 0xFF08121A,
      primaryText: 0xFFF4F6FA,
      secondaryText: 0xFF94A3B8,
      progressIndicator: 0xFF38BDF8,
      progressTrack: 0xFF2A3950,
      activeNavigation: 0xFF38BDF8,
      playbackControl: 0xFF38BDF8,
      surfaceTint: 0x1238BDF8,
      isFallback: true,
    );
  }

  /// Generates a complete, contrast-validated [AdaptiveSemanticPalette].
  static AdaptiveSemanticPalette generate({
    required List<AnalyzedColorCluster> clusters,
    required List<RankedAccentCandidate> rankedAccents,
    required PalettePersonalityAnalysis personality,
  }) {
    if (clusters.isEmpty) {
      return fallbackPalette();
    }

    final profile = PalettePersonalityAnalyzer.profileFor(
      personality.personality,
    );

    // 1. Primary accent seed selection.
    final primaryCluster =
        rankedAccents.isNotEmpty ? rankedAccents.first.cluster : clusters.first;
    final rawPrimaryHct = Hct.fromInt(primaryCluster.argb);
    final isTrulyAchromatic =
        personality.maxChroma < 14.0 && rawPrimaryHct.chroma < 14.0;

    final fixedSeedHct = isTrulyAchromatic
        ? Hct.from(215.0, math.min(rawPrimaryHct.chroma, 10.0), 76.0)
        : (rawPrimaryHct.chroma >= 20.0
            ? DislikeAnalyzer.fixIfDisliked(rawPrimaryHct)
            : rawPrimaryHct);

    final baseHue = fixedSeedHct.hue;

    // 2. Stable deep neutral foundation with subtle artwork hue harmony.
    final neutralBaseChroma = isTrulyAchromatic ? 2.0 : profile.neutralChroma;
    final background =
        Hct.from(baseHue, neutralBaseChroma * 0.70, 7.0).toInt();
    final surface = Hct.from(baseHue, neutralBaseChroma, 12.5).toInt();
    final elevatedSurface =
        Hct.from(baseHue, neutralBaseChroma * 1.15, 17.5).toInt();

    final primaryText = Hct.from(baseHue, 2.5, 96.0).toInt();
    int secondaryText = Hct.from(
      baseHue,
      math.min(8.0, neutralBaseChroma * 1.6),
      69.0,
    ).toInt();

    // 3. Primary accent harmonized for dark-surface usability.
    final double targetPrimaryChroma = isTrulyAchromatic
        ? math.min(profile.maxPrimaryChroma, 10.0)
        : rawPrimaryHct.chroma
            .clamp(profile.minPrimaryChroma, profile.maxPrimaryChroma);

    int primaryAccent = Hct.from(
      baseHue,
      targetPrimaryChroma,
      profile.primaryTone,
    ).toInt();

    // 4. Secondary accent: prefer a genuinely distinct second candidate from
    // the artwork harmonized toward primary; otherwise derive via HCT hue shift.
    int secondaryAccent;
    final distinctSecond = _findDistinctSecondaryCandidate(
      rankedAccents,
      primaryHue: baseHue,
    );
    if (distinctSecond != null && !isTrulyAchromatic) {
      final harmonizedInt = Blend.harmonize(
        distinctSecond.cluster.argb,
        primaryAccent,
      );
      final secHct = DislikeAnalyzer.fixIfDisliked(Hct.fromInt(harmonizedInt));
      final secChroma = secHct.chroma.clamp(
        profile.minSecondaryChroma,
        profile.maxSecondaryChroma,
      );
      secondaryAccent = Hct.from(secHct.hue, secChroma, 74.0).toInt();
    } else {
      final shiftedHue = _safeHarmonizedHue(
        baseHue,
        profile.secondaryHueShift,
      );
      final secChroma = isTrulyAchromatic
          ? 6.0
          : (targetPrimaryChroma * 0.72).clamp(
              profile.minSecondaryChroma,
              profile.maxSecondaryChroma,
            );
      secondaryAccent = Hct.from(shiftedHue, secChroma, 76.0).toInt();
    }

    // 5. Subtle artwork-derived surface tint & progress track.
    final tintAlphaByte =
        (profile.surfaceTintAlpha * 255.0).round().clamp(8, 24);
    final surfaceTint =
        (tintAlphaByte << 24) | (primaryAccent & 0x00FFFFFF);
    final tintedSurface =
        PerceptualColorAnalyzer.alphaCompositeOver(surfaceTint, surface);
    final tintedElevated = PerceptualColorAnalyzer.alphaCompositeOver(
      surfaceTint,
      elevatedSurface,
    );

    final progressTrack = Hct.from(
      baseHue,
      neutralBaseChroma * 1.4,
      26.0,
    ).toInt();

    final darkSurfaces = <int>[
      background,
      surface,
      elevatedSurface,
      tintedSurface,
      tintedElevated,
    ];

    // 6. Explicit WCAG 2.1 validation & HCT tone adjustment pass.
    final validatedPrimaryText = _ensureMinContrast(
      primaryText,
      darkSurfaces,
      minRatio: 4.5,
      preferLighter: true,
    );
    secondaryText = _ensureMinContrast(
      secondaryText,
      darkSurfaces,
      minRatio: 4.5,
      preferLighter: true,
    );

    final primaryPair = _validateAccentAndForeground(
      accentArgb: primaryAccent,
      darkSurfaces: darkSurfaces,
      minSurfaceContrast: 4.5,
      minForegroundContrast: 4.5,
    );
    primaryAccent = primaryPair.accent;
    final onPrimary = primaryPair.onAccent;

    final secondaryPair = _validateAccentAndForeground(
      accentArgb: secondaryAccent,
      darkSurfaces: darkSurfaces,
      minSurfaceContrast: 3.5,
      minForegroundContrast: 4.5,
    );
    secondaryAccent = secondaryPair.accent;
    final onSecondary = secondaryPair.onAccent;

    final activeNavigation = _ensureMinContrast(
      primaryAccent,
      [background, surface],
      minRatio: 4.5,
      preferLighter: true,
    );

    final playbackControl = _ensureMinContrast(
      primaryAccent,
      darkSurfaces,
      minRatio: 4.5,
      preferLighter: true,
    );

    final progressIndicator = _ensureMinContrast(
      primaryAccent,
      [background, surface, elevatedSurface, progressTrack],
      minRatio: 3.1,
      preferLighter: true,
    );

    final validatedTint =
        (tintAlphaByte << 24) | (primaryAccent & 0x00FFFFFF);

    final candidate = AdaptiveSemanticPalette(
      background: background,
      surface: surface,
      elevatedSurface: elevatedSurface,
      primaryAccent: primaryAccent,
      secondaryAccent: secondaryAccent,
      onPrimary: onPrimary,
      onSecondary: onSecondary,
      primaryText: validatedPrimaryText,
      secondaryText: secondaryText,
      progressIndicator: progressIndicator,
      progressTrack: progressTrack,
      activeNavigation: activeNavigation,
      playbackControl: playbackControl,
      surfaceTint: validatedTint,
      isFallback: false,
    );

    if (!_passesAllContrastInvariants(candidate)) {
      return fallbackPalette();
    }
    return candidate;
  }

  static RankedAccentCandidate? _findDistinctSecondaryCandidate(
    List<RankedAccentCandidate> rankedAccents, {
    required double primaryHue,
  }) {
    if (rankedAccents.length < 2) return null;
    for (int i = 1; i < rankedAccents.length; i++) {
      final c = rankedAccents[i];
      if (c.cluster.chroma < 18.0) continue;
      final hct = Hct.fromInt(c.cluster.argb);
      if (_hueDistance(hct.hue, primaryHue) >= 28.0) {
        return c;
      }
    }
    return null;
  }

  static double _hueDistance(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static double _safeHarmonizedHue(double baseHue, double shift) {
    final plus = (baseHue + shift) % 360.0;
    final probePlus = Hct.from(plus, 34.0, 48.0);
    if (!DislikeAnalyzer.isDisliked(probePlus)) {
      return plus;
    }
    return (baseHue - shift + 360.0) % 360.0;
  }

  static ({int accent, int onAccent}) _validateAccentAndForeground({
    required int accentArgb,
    required List<int> darkSurfaces,
    required double minSurfaceContrast,
    required double minForegroundContrast,
  }) {
    final accent = _ensureMinContrast(
      accentArgb,
      darkSurfaces,
      minRatio: minSurfaceContrast,
      preferLighter: true,
    );

    final onAccent = _bestForegroundInk(accent);
    if (PerceptualColorAnalyzer.wcagContrastRatio(onAccent, accent) >=
        minForegroundContrast) {
      return (accent: accent, onAccent: onAccent);
    }

    // Nudge tone upward so dark ink cleanly achieves >= 4.5:1 while keeping
    // surface contrast strong.
    final hct = Hct.fromInt(accent);
    for (double tone = math.max(hct.tone, 64.0); tone <= 92.0; tone += 2.0) {
      final candidate = Hct.from(hct.hue, hct.chroma, tone).toInt();
      final ink = _bestForegroundInk(candidate);
      final fgOk =
          PerceptualColorAnalyzer.wcagContrastRatio(ink, candidate) >=
              minForegroundContrast;
      final surfOk = darkSurfaces.every(
        (bg) =>
            PerceptualColorAnalyzer.wcagContrastRatio(candidate, bg) >=
            minSurfaceContrast,
      );
      if (fgOk && surfOk) {
        return (accent: candidate, onAccent: ink);
      }
    }

    // Also try stepping darker if light ink on darker accent converges cleanly.
    for (double tone = math.min(hct.tone, 48.0); tone >= 30.0; tone -= 2.0) {
      final candidate = Hct.from(hct.hue, hct.chroma, tone).toInt();
      final ink = _bestForegroundInk(candidate);
      final fgOk =
          PerceptualColorAnalyzer.wcagContrastRatio(ink, candidate) >=
              minForegroundContrast;
      final surfOk = darkSurfaces.every(
        (bg) =>
            PerceptualColorAnalyzer.wcagContrastRatio(candidate, bg) >=
            minSurfaceContrast,
      );
      if (fgOk && surfOk) {
        return (accent: candidate, onAccent: ink);
      }
    }

    return (accent: accent, onAccent: onAccent);
  }

  static int _bestForegroundInk(int backgroundArgb) {
    final darkRatio =
        PerceptualColorAnalyzer.wcagContrastRatio(_darkInk, backgroundArgb);
    final lightRatio =
        PerceptualColorAnalyzer.wcagContrastRatio(_lightInk, backgroundArgb);
    return darkRatio >= lightRatio ? _darkInk : _lightInk;
  }

  static int _ensureMinContrast(
    int fgArgb,
    List<int> bgArgbs, {
    required double minRatio,
    required bool preferLighter,
  }) {
    bool satisfies(int color) => bgArgbs.every(
          (bg) =>
              PerceptualColorAnalyzer.wcagContrastRatio(color, bg) >= minRatio,
        );

    if (satisfies(fgArgb)) return fgArgb;

    final hct = Hct.fromInt(fgArgb);
    final double step = preferLighter ? 2.0 : -2.0;
    double tone = hct.tone;

    for (int i = 0; i < 45; i++) {
      tone = (tone + step).clamp(6.0, 97.0);
      final candidate = Hct.from(hct.hue, hct.chroma, tone).toInt();
      if (satisfies(candidate)) return candidate;
      if (tone <= 6.0 || tone >= 97.0) break;
    }

    // Fallback: gently relax chroma at extreme tone if gamut clipped luminance.
    for (double c = hct.chroma; c >= 0.0; c -= 6.0) {
      final candidate =
          Hct.from(hct.hue, c, preferLighter ? 94.0 : 10.0).toInt();
      if (satisfies(candidate)) return candidate;
    }

    return preferLighter ? _lightInk : _darkInk;
  }

  static bool _passesAllContrastInvariants(AdaptiveSemanticPalette p) {
    final surfaces = [p.background, p.surface, p.elevatedSurface];
    for (final bg in surfaces) {
      if (PerceptualColorAnalyzer.wcagContrastRatio(p.primaryText, bg) < 4.5) {
        return false;
      }
      if (PerceptualColorAnalyzer.wcagContrastRatio(p.secondaryText, bg) <
          4.5) {
        return false;
      }
      if (PerceptualColorAnalyzer.wcagContrastRatio(p.primaryAccent, bg) <
          3.0) {
        return false;
      }
      if (PerceptualColorAnalyzer.wcagContrastRatio(p.secondaryAccent, bg) <
          3.0) {
        return false;
      }
      if (PerceptualColorAnalyzer.wcagContrastRatio(p.playbackControl, bg) <
          3.0) {
        return false;
      }
    }

    if (PerceptualColorAnalyzer.wcagContrastRatio(
            p.onPrimary, p.primaryAccent) <
        4.5) {
      return false;
    }
    if (PerceptualColorAnalyzer.wcagContrastRatio(
            p.onSecondary, p.secondaryAccent) <
        4.5) {
      return false;
    }
    if (PerceptualColorAnalyzer.wcagContrastRatio(
            p.activeNavigation, p.background) <
        4.5) {
      return false;
    }
    if (PerceptualColorAnalyzer.wcagContrastRatio(
            p.progressIndicator, p.progressTrack) <
        3.0) {
      return false;
    }
    if (PerceptualColorAnalyzer.relativeLuminance(p.background) >= 0.03) {
      return false;
    }
    return true;
  }
}
