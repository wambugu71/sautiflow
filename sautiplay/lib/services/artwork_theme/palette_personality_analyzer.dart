import 'dart:math' as math;

import 'artwork_palette_models.dart';

/// Deterministic heuristic analyzer that characterizes artwork visual mood
/// and produces bounded HCT generation profiles.
class PalettePersonalityAnalyzer {
  PalettePersonalityAnalyzer._();

  static const Map<PalettePersonality, PalettePersonalityProfile> _profiles = {
    PalettePersonality.ambient: PalettePersonalityProfile(
      minPrimaryChroma: 22.0,
      maxPrimaryChroma: 36.0,
      primaryTone: 72.0,
      minSecondaryChroma: 16.0,
      maxSecondaryChroma: 28.0,
      neutralChroma: 3.5,
      surfaceTintAlpha: 0.05,
      secondaryHueShift: 28.0,
    ),
    PalettePersonality.electronic: PalettePersonalityProfile(
      minPrimaryChroma: 48.0,
      maxPrimaryChroma: 72.0,
      primaryTone: 70.0,
      minSecondaryChroma: 36.0,
      maxSecondaryChroma: 54.0,
      neutralChroma: 5.0,
      surfaceTintAlpha: 0.08,
      secondaryHueShift: 42.0,
    ),
    PalettePersonality.vintage: PalettePersonalityProfile(
      minPrimaryChroma: 26.0,
      maxPrimaryChroma: 44.0,
      primaryTone: 72.0,
      minSecondaryChroma: 20.0,
      maxSecondaryChroma: 34.0,
      neutralChroma: 4.5,
      surfaceTintAlpha: 0.06,
      secondaryHueShift: 30.0,
    ),
    PalettePersonality.monochromatic: PalettePersonalityProfile(
      minPrimaryChroma: 6.0,
      maxPrimaryChroma: 20.0,
      primaryTone: 78.0,
      minSecondaryChroma: 4.0,
      maxSecondaryChroma: 14.0,
      neutralChroma: 2.0,
      surfaceTintAlpha: 0.04,
      secondaryHueShift: 15.0,
    ),
    PalettePersonality.cinematic: PalettePersonalityProfile(
      minPrimaryChroma: 38.0,
      maxPrimaryChroma: 58.0,
      primaryTone: 68.0,
      minSecondaryChroma: 24.0,
      maxSecondaryChroma: 40.0,
      neutralChroma: 4.0,
      surfaceTintAlpha: 0.07,
      secondaryHueShift: 48.0,
    ),
    PalettePersonality.natural: PalettePersonalityProfile(
      minPrimaryChroma: 28.0,
      maxPrimaryChroma: 48.0,
      primaryTone: 72.0,
      minSecondaryChroma: 22.0,
      maxSecondaryChroma: 36.0,
      neutralChroma: 4.0,
      surfaceTintAlpha: 0.06,
      secondaryHueShift: 34.0,
    ),
  };

  /// Returns the HCT parameter profile associated with [personality].
  static PalettePersonalityProfile profileFor(PalettePersonality personality) =>
      _profiles[personality]!;

  /// Analyzes extracted perceptual clusters into a [PalettePersonalityAnalysis].
  static PalettePersonalityAnalysis analyze(
    List<AnalyzedColorCluster> clusters,
  ) {
    if (clusters.isEmpty) {
      return const PalettePersonalityAnalysis(
        personality: PalettePersonality.ambient,
        averageChroma: 0.0,
        maxChroma: 0.0,
        hueSpreadDegrees: 0.0,
        luminanceVariance: 0.0,
        paletteDiversity: 0.0,
        dominantShare: 1.0,
        warmRatio: 0.0,
        earthinessScore: 0.0,
      );
    }

    double totalPop = 0.0;
    double weightedChroma = 0.0;
    double weightedL = 0.0;
    double maxChroma = 0.0;
    double maxSignificantChroma = 0.0;
    double dominantShare = 0.0;
    double chromaticMass = 0.0;
    double minL = 100.0;
    double maxL = 0.0;

    double hueSinSum = 0.0;
    double hueCosSum = 0.0;
    double chromaticWeightSum = 0.0;
    double warmWeight = 0.0;
    double earthyWeight = 0.0;
    final chromaticClusters = <AnalyzedColorCluster>[];

    for (final c in clusters) {
      final pop = c.population;
      totalPop += pop;
      weightedChroma += pop * c.chroma;
      weightedL += pop * c.lightness;
      if (pop > dominantShare) dominantShare = pop;
      if (c.chroma > maxChroma) maxChroma = c.chroma;
      if (pop >= 0.004 && c.chroma > maxSignificantChroma) {
        maxSignificantChroma = c.chroma;
      }
      if (pop >= 0.004) {
        if (c.lightness < minL) minL = c.lightness;
        if (c.lightness > maxL) maxL = c.lightness;
      }

      if (c.chroma >= 14.0) {
        chromaticClusters.add(c);
        chromaticMass += pop;
        final w = pop * c.chroma;
        final rad = c.hue * math.pi / 180.0;
        hueSinSum += w * math.sin(rad);
        hueCosSum += w * math.cos(rad);
        chromaticWeightSum += w;

        // Warm range: reds, oranges, ambers, warm yellows, crimson.
        if (c.hue <= 75.0 || c.hue >= 330.0) {
          warmWeight += w;
        }
        // Organic/earthy range: terracotta, ochre, amber, olive, forest green.
        if (c.hue >= 20.0 &&
            c.hue <= 145.0 &&
            c.chroma >= 14.0 &&
            c.chroma <= 52.0 &&
            c.lightness >= 22.0 &&
            c.lightness <= 72.0) {
          earthyWeight += w;
        }
      }
    }

    final normPop = totalPop > 0.0 ? totalPop : 1.0;
    final avgChroma = weightedChroma / normPop;
    final meanL = weightedL / normPop;
    final effectiveMaxChroma =
        maxSignificantChroma > 0.0 ? maxSignificantChroma : maxChroma;

    double lumVar = 0.0;
    double entropy = 0.0;
    for (final c in clusters) {
      final p = c.population / normPop;
      final dl = c.lightness - meanL;
      lumVar += p * dl * dl;
      if (p > 1e-9) {
        entropy -= p * math.log(p);
      }
    }

    final maxEntropy = clusters.length > 1 ? math.log(clusters.length) : 1.0;
    final normalizedEntropy = (entropy / maxEntropy).clamp(0.0, 1.0);

    int separatedPairs = 0;
    int totalPairs = 0;
    for (int i = 0; i < clusters.length; i++) {
      for (int j = i + 1; j < clusters.length; j++) {
        totalPairs++;
        if (clusters[i].lab.deltaE(clusters[j].lab) >= 18.0) {
          separatedPairs++;
        }
      }
    }
    final separationRatio =
        totalPairs > 0 ? separatedPairs / totalPairs : 0.0;
    final paletteDiversity =
        (0.6 * normalizedEntropy + 0.4 * separationRatio).clamp(0.0, 1.0);

    double hueSpreadDegrees = 0.0;
    if (chromaticClusters.length > 1 && chromaticWeightSum > 0.0) {
      final resultant = math
              .sqrt(hueSinSum * hueSinSum + hueCosSum * hueCosSum) /
          chromaticWeightSum;
      final clampedR = resultant.clamp(1e-6, 1.0);
      hueSpreadDegrees =
          (math.sqrt(-2.0 * math.log(clampedR)) * 180.0 / math.pi)
              .clamp(0.0, 180.0);
    }

    double maxHueSpan = 0.0;
    for (int i = 0; i < chromaticClusters.length; i++) {
      for (int j = i + 1; j < chromaticClusters.length; j++) {
        final diff =
            (chromaticClusters[i].hue - chromaticClusters[j].hue).abs() % 360.0;
        final circularDiff = diff > 180.0 ? 360.0 - diff : diff;
        if (circularDiff > maxHueSpan) maxHueSpan = circularDiff;
      }
    }

    final warmRatio =
        chromaticWeightSum > 0.0 ? (warmWeight / chromaticWeightSum) : 0.0;
    final earthinessScore =
        chromaticWeightSum > 0.0 ? (earthyWeight / chromaticWeightSum) : 0.0;
    final lumRange = (maxL - minL).clamp(0.0, 100.0);

    final personality = _classify(
      averageChroma: avgChroma,
      maxChroma: effectiveMaxChroma,
      chromaticMass: chromaticMass,
      hueSpreadDegrees: hueSpreadDegrees,
      maxHueSpan: maxHueSpan,
      luminanceVariance: lumVar,
      luminanceRange: lumRange,
      dominantShare: dominantShare,
      warmRatio: warmRatio,
      earthinessScore: earthinessScore,
    );

    return PalettePersonalityAnalysis(
      personality: personality,
      averageChroma: avgChroma,
      maxChroma: effectiveMaxChroma,
      hueSpreadDegrees: hueSpreadDegrees,
      luminanceVariance: lumVar,
      paletteDiversity: paletteDiversity,
      dominantShare: dominantShare,
      warmRatio: warmRatio,
      earthinessScore: earthinessScore,
    );
  }

  static PalettePersonality _classify({
    required double averageChroma,
    required double maxChroma,
    required double chromaticMass,
    required double hueSpreadDegrees,
    required double maxHueSpan,
    required double luminanceVariance,
    required double luminanceRange,
    required double dominantShare,
    required double warmRatio,
    required double earthinessScore,
  }) {
    // 1. Monochromatic: truly achromatic/grayscale or tightly restrained
    // single-hue tonal artwork without strong dramatic contrast.
    if (maxChroma < 12.0 ||
        (averageChroma < 8.0 && maxChroma < 18.0) ||
        (chromaticMass >= 0.05 &&
            hueSpreadDegrees < 10.0 &&
            maxHueSpan < 18.0 &&
            maxChroma < 42.0 &&
            averageChroma < 34.0 &&
            luminanceVariance < 450.0)) {
      return PalettePersonality.monochromatic;
    }

    // 2. Electronic: vivid, saturated chromatic presence.
    if (maxChroma >= 62.0 &&
        (averageChroma >= 34.0 || chromaticMass >= 0.35)) {
      return PalettePersonality.electronic;
    }

    // 3. Cinematic: strong dark/light luminance variance or dramatic focal
    // accent against a strongly dominant dark/light ground.
    if ((luminanceVariance >= 550.0 && maxChroma >= 22.0) ||
        (dominantShare >= 0.70 &&
            maxChroma >= 45.0 &&
            luminanceRange >= 35.0)) {
      return PalettePersonality.cinematic;
    }

    // 4. Vintage: warm-leaning, moderate/muted chroma.
    if (warmRatio >= 0.62 &&
        averageChroma >= 14.0 &&
        averageChroma <= 48.0 &&
        maxChroma < 65.0) {
      return PalettePersonality.vintage;
    }

    // 5. Natural: earthy organic hues (olive, forest, ochre, terracotta).
    if (earthinessScore >= 0.45 &&
        averageChroma >= 14.0 &&
        averageChroma <= 50.0) {
      return PalettePersonality.natural;
    }

    // 6. Ambient: subdued, calm, low-to-moderate chroma default.
    return PalettePersonality.ambient;
  }
}
