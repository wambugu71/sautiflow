import 'dart:math' as math;

/// Configurable scoring weights and thresholds for accent candidate ranking.
class AccentScoringConfig {
  final double chromaWeight;
  final double distinctivenessWeight;
  final double populationWeight;
  final double luminanceWeight;
  final double contrastPotentialWeight;
  final double designCompatibilityWeight;
  final double minAccentPopulation;
  final double minAccentChroma;
  final double minCandidateDeltaE;
  final int maxCandidates;

  const AccentScoringConfig({
    this.chromaWeight = 0.28,
    this.distinctivenessWeight = 0.24,
    this.populationWeight = 0.14,
    this.luminanceWeight = 0.14,
    this.contrastPotentialWeight = 0.12,
    this.designCompatibilityWeight = 0.08,
    this.minAccentPopulation = 0.004,
    this.minAccentChroma = 18.0,
    this.minCandidateDeltaE = 18.0,
    this.maxCandidates = 5,
  });

  Map<String, Object?> toJson() => {
        'chromaWeight': chromaWeight,
        'distinctivenessWeight': distinctivenessWeight,
        'populationWeight': populationWeight,
        'luminanceWeight': luminanceWeight,
        'contrastPotentialWeight': contrastPotentialWeight,
        'designCompatibilityWeight': designCompatibilityWeight,
        'minAccentPopulation': minAccentPopulation,
        'minAccentChroma': minAccentChroma,
        'minCandidateDeltaE': minCandidateDeltaE,
        'maxCandidates': maxCandidates,
      };

  factory AccentScoringConfig.fromJson(Map<String, Object?> json) {
    return AccentScoringConfig(
      chromaWeight: (json['chromaWeight'] as num?)?.toDouble() ?? 0.28,
      distinctivenessWeight:
          (json['distinctivenessWeight'] as num?)?.toDouble() ?? 0.24,
      populationWeight: (json['populationWeight'] as num?)?.toDouble() ?? 0.14,
      luminanceWeight: (json['luminanceWeight'] as num?)?.toDouble() ?? 0.14,
      contrastPotentialWeight:
          (json['contrastPotentialWeight'] as num?)?.toDouble() ?? 0.12,
      designCompatibilityWeight:
          (json['designCompatibilityWeight'] as num?)?.toDouble() ?? 0.08,
      minAccentPopulation:
          (json['minAccentPopulation'] as num?)?.toDouble() ?? 0.004,
      minAccentChroma: (json['minAccentChroma'] as num?)?.toDouble() ?? 18.0,
      minCandidateDeltaE:
          (json['minCandidateDeltaE'] as num?)?.toDouble() ?? 18.0,
      maxCandidates: (json['maxCandidates'] as num?)?.toInt() ?? 5,
    );
  }
}

/// Configurable parameters for artwork sampling and perceptual clustering.
class PaletteExtractionConfig {
  final int targetDimension;
  final int clusterCount;
  final int maxIterations;
  final double convergenceDeltaE;
  final double mergeDeltaE;
  final int alphaThreshold;
  final int quantBitsPerChannel;
  final AccentScoringConfig scoring;

  const PaletteExtractionConfig({
    this.targetDimension = 160,
    this.clusterCount = 7,
    this.maxIterations = 30,
    this.convergenceDeltaE = 0.5,
    this.mergeDeltaE = 10.0,
    this.alphaThreshold = 128,
    this.quantBitsPerChannel = 6,
    this.scoring = const AccentScoringConfig(),
  });

  Map<String, Object?> toJson() => {
        'targetDimension': targetDimension,
        'clusterCount': clusterCount,
        'maxIterations': maxIterations,
        'convergenceDeltaE': convergenceDeltaE,
        'mergeDeltaE': mergeDeltaE,
        'alphaThreshold': alphaThreshold,
        'quantBitsPerChannel': quantBitsPerChannel,
        'scoring': scoring.toJson(),
      };

  factory PaletteExtractionConfig.fromJson(Map<String, Object?> json) {
    final scoringRaw = json['scoring'];
    return PaletteExtractionConfig(
      targetDimension: (json['targetDimension'] as num?)?.toInt() ?? 160,
      clusterCount: (json['clusterCount'] as num?)?.toInt() ?? 7,
      maxIterations: (json['maxIterations'] as num?)?.toInt() ?? 30,
      convergenceDeltaE:
          (json['convergenceDeltaE'] as num?)?.toDouble() ?? 0.5,
      mergeDeltaE: (json['mergeDeltaE'] as num?)?.toDouble() ?? 10.0,
      alphaThreshold: (json['alphaThreshold'] as num?)?.toInt() ?? 128,
      quantBitsPerChannel: (json['quantBitsPerChannel'] as num?)?.toInt() ?? 6,
      scoring: scoringRaw is Map
          ? AccentScoringConfig.fromJson(Map<String, Object?>.from(scoringRaw))
          : const AccentScoringConfig(),
    );
  }
}

/// Perceptual CIELAB D65 color coordinates.
class LabColor {
  final double l;
  final double a;
  final double b;

  const LabColor(this.l, this.a, this.b);

  double get chroma => math.sqrt(a * a + b * b);

  double get hue {
    if (a == 0.0 && b == 0.0) return 0.0;
    final deg = math.atan2(b, a) * 180.0 / math.pi;
    return deg < 0.0 ? deg + 360.0 : deg;
  }

  double deltaESq(LabColor other) {
    final dl = l - other.l;
    final da = a - other.a;
    final db = b - other.b;
    return dl * dl + da * da + db * db;
  }

  double deltaE(LabColor other) => math.sqrt(deltaESq(other));

  Map<String, Object?> toJson() => {'l': l, 'a': a, 'b': b};

  factory LabColor.fromJson(Map<String, Object?> json) {
    return LabColor(
      (json['l'] as num).toDouble(),
      (json['a'] as num).toDouble(),
      (json['b'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabColor && l == other.l && a == other.a && b == other.b;

  @override
  int get hashCode => Object.hash(l, a, b);
}

/// Semantic perceptual categories assigned to extracted clusters.
enum ColorCategory {
  dominant,
  vibrant,
  muted,
  neutral,
  dark,
  light,
  accentCandidate,
}

/// A perceptual color cluster extracted from album artwork.
class AnalyzedColorCluster {
  final int argb;
  final LabColor lab;
  final double population;
  final double lightness;
  final double chroma;
  final double hue;
  final double distinctiveness;
  final Set<ColorCategory> categories;

  const AnalyzedColorCluster({
    required this.argb,
    required this.lab,
    required this.population,
    required this.lightness,
    required this.chroma,
    required this.hue,
    required this.distinctiveness,
    required this.categories,
  });

  Map<String, Object?> toJson() => {
        'argb': argb,
        'lab': lab.toJson(),
        'population': population,
        'lightness': lightness,
        'chroma': chroma,
        'hue': hue,
        'distinctiveness': distinctiveness,
        'categories': categories.map((c) => c.name).toList(growable: false),
      };

  factory AnalyzedColorCluster.fromJson(Map<String, Object?> json) {
    final catRaw = (json['categories'] as List<Object?>?) ?? const [];
    final categories = <ColorCategory>{};
    for (final entry in catRaw) {
      final name = entry?.toString();
      for (final value in ColorCategory.values) {
        if (value.name == name) {
          categories.add(value);
          break;
        }
      }
    }
    return AnalyzedColorCluster(
      argb: (json['argb'] as num).toInt(),
      lab: LabColor.fromJson(
        Map<String, Object?>.from(json['lab'] as Map),
      ),
      population: (json['population'] as num).toDouble(),
      lightness: (json['lightness'] as num).toDouble(),
      chroma: (json['chroma'] as num).toDouble(),
      hue: (json['hue'] as num).toDouble(),
      distinctiveness: (json['distinctiveness'] as num).toDouble(),
      categories: Set.unmodifiable(categories),
    );
  }
}

/// An accent color candidate with deterministic score breakdown.
class RankedAccentCandidate {
  final AnalyzedColorCluster cluster;
  final double score;
  final double chromaScore;
  final double distinctivenessScore;
  final double populationScore;
  final double luminanceScore;
  final double contrastScore;
  final double designCompatibilityScore;

  const RankedAccentCandidate({
    required this.cluster,
    required this.score,
    required this.chromaScore,
    required this.distinctivenessScore,
    required this.populationScore,
    required this.luminanceScore,
    required this.contrastScore,
    required this.designCompatibilityScore,
  });

  Map<String, Object?> toJson() => {
        'cluster': cluster.toJson(),
        'score': score,
        'chromaScore': chromaScore,
        'distinctivenessScore': distinctivenessScore,
        'populationScore': populationScore,
        'luminanceScore': luminanceScore,
        'contrastScore': contrastScore,
        'designCompatibilityScore': designCompatibilityScore,
      };

  factory RankedAccentCandidate.fromJson(Map<String, Object?> json) {
    return RankedAccentCandidate(
      cluster: AnalyzedColorCluster.fromJson(
        Map<String, Object?>.from(json['cluster'] as Map),
      ),
      score: (json['score'] as num).toDouble(),
      chromaScore: (json['chromaScore'] as num).toDouble(),
      distinctivenessScore: (json['distinctivenessScore'] as num).toDouble(),
      populationScore: (json['populationScore'] as num).toDouble(),
      luminanceScore: (json['luminanceScore'] as num).toDouble(),
      contrastScore: (json['contrastScore'] as num).toDouble(),
      designCompatibilityScore:
          (json['designCompatibilityScore'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// Visual personality detected deterministically from cluster statistics.
enum PalettePersonality {
  ambient,
  electronic,
  vintage,
  monochromatic,
  cinematic,
  natural,
}

/// HCT generation bounds derived from a [PalettePersonality].
class PalettePersonalityProfile {
  final double minPrimaryChroma;
  final double maxPrimaryChroma;
  final double primaryTone;
  final double minSecondaryChroma;
  final double maxSecondaryChroma;
  final double neutralChroma;
  final double surfaceTintAlpha;
  final double secondaryHueShift;

  const PalettePersonalityProfile({
    required this.minPrimaryChroma,
    required this.maxPrimaryChroma,
    required this.primaryTone,
    required this.minSecondaryChroma,
    required this.maxSecondaryChroma,
    required this.neutralChroma,
    required this.surfaceTintAlpha,
    required this.secondaryHueShift,
  });
}

/// Deterministic palette personality characterization metrics.
class PalettePersonalityAnalysis {
  final PalettePersonality personality;
  final double averageChroma;
  final double maxChroma;
  final double hueSpreadDegrees;
  final double luminanceVariance;
  final double paletteDiversity;
  final double dominantShare;
  final double warmRatio;
  final double earthinessScore;

  const PalettePersonalityAnalysis({
    required this.personality,
    required this.averageChroma,
    required this.maxChroma,
    required this.hueSpreadDegrees,
    required this.luminanceVariance,
    required this.paletteDiversity,
    required this.dominantShare,
    required this.warmRatio,
    required this.earthinessScore,
  });

  Map<String, Object?> toJson() => {
        'personality': personality.name,
        'averageChroma': averageChroma,
        'maxChroma': maxChroma,
        'hueSpreadDegrees': hueSpreadDegrees,
        'luminanceVariance': luminanceVariance,
        'paletteDiversity': paletteDiversity,
        'dominantShare': dominantShare,
        'warmRatio': warmRatio,
        'earthinessScore': earthinessScore,
      };

  factory PalettePersonalityAnalysis.fromJson(Map<String, Object?> json) {
    final rawName = json['personality']?.toString();
    final personality = PalettePersonality.values.firstWhere(
      (p) => p.name == rawName,
      orElse: () => PalettePersonality.ambient,
    );
    return PalettePersonalityAnalysis(
      personality: personality,
      averageChroma: (json['averageChroma'] as num).toDouble(),
      maxChroma: (json['maxChroma'] as num).toDouble(),
      hueSpreadDegrees: (json['hueSpreadDegrees'] as num).toDouble(),
      luminanceVariance: (json['luminanceVariance'] as num).toDouble(),
      paletteDiversity: (json['paletteDiversity'] as num).toDouble(),
      dominantShare: (json['dominantShare'] as num).toDouble(),
      warmRatio: (json['warmRatio'] as num).toDouble(),
      earthinessScore: (json['earthinessScore'] as num).toDouble(),
    );
  }
}

/// Coherent semantic color palette stored as ARGB 32-bit integers.
class AdaptiveSemanticPalette {
  final int background;
  final int surface;
  final int elevatedSurface;
  final int primaryAccent;
  final int secondaryAccent;
  final int onPrimary;
  final int onSecondary;
  final int primaryText;
  final int secondaryText;
  final int progressIndicator;
  final int progressTrack;
  final int activeNavigation;
  final int playbackControl;
  final int surfaceTint;
  final bool isFallback;

  const AdaptiveSemanticPalette({
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.onPrimary,
    required this.onSecondary,
    required this.primaryText,
    required this.secondaryText,
    required this.progressIndicator,
    required this.progressTrack,
    required this.activeNavigation,
    required this.playbackControl,
    required this.surfaceTint,
    this.isFallback = false,
  });

  Map<String, Object?> toJson() => {
        'background': background,
        'surface': surface,
        'elevatedSurface': elevatedSurface,
        'primaryAccent': primaryAccent,
        'secondaryAccent': secondaryAccent,
        'onPrimary': onPrimary,
        'onSecondary': onSecondary,
        'primaryText': primaryText,
        'secondaryText': secondaryText,
        'progressIndicator': progressIndicator,
        'progressTrack': progressTrack,
        'activeNavigation': activeNavigation,
        'playbackControl': playbackControl,
        'surfaceTint': surfaceTint,
        'isFallback': isFallback,
      };

  factory AdaptiveSemanticPalette.fromJson(Map<String, Object?> json) {
    return AdaptiveSemanticPalette(
      background: (json['background'] as num).toInt(),
      surface: (json['surface'] as num).toInt(),
      elevatedSurface: (json['elevatedSurface'] as num).toInt(),
      primaryAccent: (json['primaryAccent'] as num).toInt(),
      secondaryAccent: (json['secondaryAccent'] as num).toInt(),
      onPrimary: (json['onPrimary'] as num).toInt(),
      onSecondary: (json['onSecondary'] as num).toInt(),
      primaryText: (json['primaryText'] as num).toInt(),
      secondaryText: (json['secondaryText'] as num).toInt(),
      progressIndicator: (json['progressIndicator'] as num).toInt(),
      progressTrack: (json['progressTrack'] as num).toInt(),
      activeNavigation: (json['activeNavigation'] as num).toInt(),
      playbackControl: (json['playbackControl'] as num).toInt(),
      surfaceTint: (json['surfaceTint'] as num).toInt(),
      isFallback: json['isFallback'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdaptiveSemanticPalette &&
          background == other.background &&
          surface == other.surface &&
          elevatedSurface == other.elevatedSurface &&
          primaryAccent == other.primaryAccent &&
          secondaryAccent == other.secondaryAccent &&
          onPrimary == other.onPrimary &&
          onSecondary == other.onSecondary &&
          primaryText == other.primaryText &&
          secondaryText == other.secondaryText &&
          progressIndicator == other.progressIndicator &&
          progressTrack == other.progressTrack &&
          activeNavigation == other.activeNavigation &&
          playbackControl == other.playbackControl &&
          surfaceTint == other.surfaceTint &&
          isFallback == other.isFallback;

  @override
  int get hashCode => Object.hash(
        background,
        surface,
        elevatedSurface,
        primaryAccent,
        secondaryAccent,
        onPrimary,
        onSecondary,
        primaryText,
        secondaryText,
        progressIndicator,
        progressTrack,
        activeNavigation,
        playbackControl,
        surfaceTint,
        isFallback,
      );
}

/// Complete serializable output of the artwork analysis and theme pipeline.
class ArtworkPaletteAnalysis {
  final String artworkHash;
  final int algorithmVersion;
  final List<AnalyzedColorCluster> clusters;
  final List<RankedAccentCandidate> rankedAccents;
  final PalettePersonalityAnalysis personality;
  final AdaptiveSemanticPalette semanticPalette;

  const ArtworkPaletteAnalysis({
    required this.artworkHash,
    required this.algorithmVersion,
    required this.clusters,
    required this.rankedAccents,
    required this.personality,
    required this.semanticPalette,
  });

  Map<String, Object?> toJson() => {
        'artworkHash': artworkHash,
        'algorithmVersion': algorithmVersion,
        'clusters': clusters.map((c) => c.toJson()).toList(growable: false),
        'rankedAccents':
            rankedAccents.map((r) => r.toJson()).toList(growable: false),
        'personality': personality.toJson(),
        'semanticPalette': semanticPalette.toJson(),
      };

  factory ArtworkPaletteAnalysis.fromJson(Map<String, Object?> json) {
    final clusterList = (json['clusters'] as List<Object?>? ?? const [])
        .map((e) => AnalyzedColorCluster.fromJson(
              Map<String, Object?>.from(e as Map),
            ))
        .toList(growable: false);
    final accentList = (json['rankedAccents'] as List<Object?>? ?? const [])
        .map((e) => RankedAccentCandidate.fromJson(
              Map<String, Object?>.from(e as Map),
            ))
        .toList(growable: false);
    return ArtworkPaletteAnalysis(
      artworkHash: json['artworkHash'] as String,
      algorithmVersion: (json['algorithmVersion'] as num).toInt(),
      clusters: List.unmodifiable(clusterList),
      rankedAccents: List.unmodifiable(accentList),
      personality: PalettePersonalityAnalysis.fromJson(
        Map<String, Object?>.from(json['personality'] as Map),
      ),
      semanticPalette: AdaptiveSemanticPalette.fromJson(
        Map<String, Object?>.from(json['semanticPalette'] as Map),
      ),
    );
  }
}

/// Performance and cache instrumentation for a single theme extraction request.
class ArtworkExtractionMetrics {
  final String artworkHash;
  final String cacheTier;
  final int decodeMs;
  final int analysisMs;
  final int themeGenMs;
  final int totalMs;
  final int sampledPixelCount;
  final int workingBufferBytes;

  const ArtworkExtractionMetrics({
    required this.artworkHash,
    required this.cacheTier,
    required this.decodeMs,
    required this.analysisMs,
    required this.themeGenMs,
    required this.totalMs,
    required this.sampledPixelCount,
    required this.workingBufferBytes,
  });
}
