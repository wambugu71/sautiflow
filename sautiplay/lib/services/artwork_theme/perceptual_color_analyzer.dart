import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';

import 'artwork_palette_models.dart';

/// Pure-Dart perceptual color space conversion, deterministic K-Means++
/// clustering in CIELAB, cluster classification, and accent ranking.
class PerceptualColorAnalyzer {
  PerceptualColorAnalyzer._();

  static const double _xn = 0.95047;
  static const double _yn = 1.00000;
  static const double _zn = 1.08883;
  static const double _labEpsilon = 216.0 / 24389.0; // (6/29)^3
  static const double _labKappa = 24389.0 / 27.0; // (29/3)^3

  static final Float64List _srgbToLinearLut = _buildSrgbToLinearLut();

  static Float64List _buildSrgbToLinearLut() {
    final lut = Float64List(256);
    for (int i = 0; i < 256; i++) {
      final c = i / 255.0;
      lut[i] = c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    return lut;
  }

  /// Linearizes an 8-bit sRGB channel `[0..255]` per IEC 61966-2-1.
  static double srgbChannelToLinear(int channel) =>
      _srgbToLinearLut[channel.clamp(0, 255)];

  /// Encodes a linear RGB channel `[0..1]` back to 8-bit sRGB `[0..255]`.
  static int linearToSrgbChannel(double linear) {
    final c = linear.clamp(0.0, 1.0);
    final srgb = c <= 0.0031308
        ? 12.92 * c
        : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
    return (srgb * 255.0).round().clamp(0, 255);
  }

  /// Converts 8-bit sRGB components into CIELAB (D65 illuminant).
  static LabColor rgbToLab(int r, int g, int b) {
    final rl = _srgbToLinearLut[r.clamp(0, 255)];
    final gl = _srgbToLinearLut[g.clamp(0, 255)];
    final bl = _srgbToLinearLut[b.clamp(0, 255)];

    final x = 0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl;
    final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
    final z = 0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl;

    final fx = _labF(x / _xn);
    final fy = _labF(y / _yn);
    final fz = _labF(z / _zn);

    return LabColor(
      116.0 * fy - 16.0,
      500.0 * (fx - fy),
      200.0 * (fy - fz),
    );
  }

  /// Converts a 32-bit ARGB color into CIELAB (D65).
  static LabColor argbToLab(int argb) =>
      rgbToLab((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);

  /// Converts CIELAB (D65) coordinates back to opaque sRGB `0xFFRRGGBB`.
  static int labToArgb(LabColor lab) {
    final fy = (lab.l + 16.0) / 116.0;
    final fx = lab.a / 500.0 + fy;
    final fz = fy - lab.b / 200.0;

    final fx3 = fx * fx * fx;
    final fz3 = fz * fz * fz;

    final xr = fx3 > _labEpsilon ? fx3 : (116.0 * fx - 16.0) / _labKappa;
    final yr = lab.l > _labKappa * _labEpsilon
        ? math.pow((lab.l + 16.0) / 116.0, 3.0).toDouble()
        : lab.l / _labKappa;
    final zr = fz3 > _labEpsilon ? fz3 : (116.0 * fz - 16.0) / _labKappa;

    final x = xr * _xn;
    final y = yr * _yn;
    final z = zr * _zn;

    final rl = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final gl = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    final r = linearToSrgbChannel(rl);
    final g = linearToSrgbChannel(gl);
    final b = linearToSrgbChannel(bl);
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  static double _labF(double t) {
    if (t > _labEpsilon) {
      return math.pow(t, 1.0 / 3.0).toDouble();
    }
    return (_labKappa * t + 16.0) / 116.0;
  }

  /// Computes WCAG 2.1 relative luminance `[0..1]` for an opaque ARGB color.
  static double relativeLuminance(int argb) {
    final r = _srgbToLinearLut[(argb >> 16) & 0xFF];
    final g = _srgbToLinearLut[(argb >> 8) & 0xFF];
    final b = _srgbToLinearLut[argb & 0xFF];
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Computes WCAG 2.1 contrast ratio `[1..21]` between two opaque ARGB colors.
  static double wcagContrastRatio(int argbA, int argbB) {
    final lumA = relativeLuminance(argbA);
    final lumB = relativeLuminance(argbB);
    final lighter = lumA >= lumB ? lumA : lumB;
    final darker = lumA >= lumB ? lumB : lumA;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Alpha-composites [fgArgb] over an opaque [bgArgb].
  static int alphaCompositeOver(int fgArgb, int bgArgb) {
    final alpha = ((fgArgb >> 24) & 0xFF) / 255.0;
    if (alpha >= 1.0) return fgArgb | 0xFF000000;
    if (alpha <= 0.0) return bgArgb | 0xFF000000;

    final fr = (fgArgb >> 16) & 0xFF;
    final fg = (fgArgb >> 8) & 0xFF;
    final fb = fgArgb & 0xFF;

    final br = (bgArgb >> 16) & 0xFF;
    final bg = (bgArgb >> 8) & 0xFF;
    final bb = bgArgb & 0xFF;

    final r = (fr * alpha + br * (1.0 - alpha)).round().clamp(0, 255);
    final g = (fg * alpha + bg * (1.0 - alpha)).round().clamp(0, 255);
    final b = (fb * alpha + bb * (1.0 - alpha)).round().clamp(0, 255);
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  /// Decodes, normalizes EXIF orientation, resizes preserving aspect ratio
  /// up to [config.targetDimension], and runs perceptual clustering.
  static ({
    List<AnalyzedColorCluster> clusters,
    List<RankedAccentCandidate> rankedAccents,
    int sampledPixelCount,
    int workingWidth,
    int workingHeight,
    int decodeMs,
    int analysisMs,
  })? analyzeEncodedBytes(
    Uint8List bytes, {
    PaletteExtractionConfig config = const PaletteExtractionConfig(),
  }) {
    if (bytes.isEmpty) return null;

    final decodeSw = Stopwatch()..start();
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }

    var working = img.bakeOrientation(decoded);
    final maxDim = config.targetDimension.clamp(32, 512);
    if (working.width > maxDim || working.height > maxDim) {
      if (working.width >= working.height) {
        working = img.copyResize(
          working,
          width: maxDim,
          interpolation: img.Interpolation.average,
        );
      } else {
        working = img.copyResize(
          working,
          height: maxDim,
          interpolation: img.Interpolation.average,
        );
      }
    }

    final rgbaImage = (working.format == img.Format.uint8 &&
            working.numChannels == 4 &&
            !working.hasPalette)
        ? working
        : working.convert(
            format: img.Format.uint8,
            numChannels: 4,
            noAnimation: true,
          );
    final rgba = rgbaImage.getBytes(order: img.ChannelOrder.rgba);
    decodeSw.stop();

    final analysis = analyzeRgbaPixels(
      rgba,
      rgbaImage.width,
      rgbaImage.height,
      config: config,
    );
    if (analysis == null) return null;

    return (
      clusters: analysis.clusters,
      rankedAccents: analysis.rankedAccents,
      sampledPixelCount: analysis.sampledPixelCount,
      workingWidth: rgbaImage.width,
      workingHeight: rgbaImage.height,
      decodeMs: decodeSw.elapsedMilliseconds,
      analysisMs: analysis.analysisMs,
    );
  }

  /// Analyzes a pre-decoded RGBA byte buffer (`width * height * 4`).
  static ({
    List<AnalyzedColorCluster> clusters,
    List<RankedAccentCandidate> rankedAccents,
    int sampledPixelCount,
    int analysisMs,
  })? analyzeRgbaPixels(
    Uint8List rgba,
    int width,
    int height, {
    PaletteExtractionConfig config = const PaletteExtractionConfig(),
  }) {
    if (width <= 0 || height <= 0) return null;
    final expectedLen = width * height * 4;
    if (rgba.length < expectedLen) return null;

    final sw = Stopwatch()..start();

    final bits = config.quantBitsPerChannel.clamp(4, 8);
    final shift = 8 - bits;
    final alphaThreshold = config.alphaThreshold.clamp(1, 255);

    final buckets = <int, _ColorBucket>{};
    int opaquePixels = 0;

    for (int idx = 0; idx < expectedLen; idx += 4) {
      final a = rgba[idx + 3];
      if (a < alphaThreshold) continue;

      final r = rgba[idx];
      final g = rgba[idx + 1];
      final b = rgba[idx + 2];
      opaquePixels++;

      final key =
          ((r >> shift) << (2 * bits)) | ((g >> shift) << bits) | (b >> shift);
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = _ColorBucket(key, r, g, b);
      } else {
        existing.add(r, g, b);
      }
    }

    if (opaquePixels == 0 || buckets.isEmpty) {
      return null;
    }

    // Sort deterministically by quantized bucket key so clustering is invariant
    // to hash map iteration order.
    final sortedBuckets = buckets.values.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));

    final n = sortedBuckets.length;
    final bL = Float64List(n);
    final bA = Float64List(n);
    final bB = Float64List(n);
    final bWeight = Float64List(n);

    for (int i = 0; i < n; i++) {
      final bucket = sortedBuckets[i];
      final count = bucket.count;
      final meanR = (bucket.sumR / count).round().clamp(0, 255);
      final meanG = (bucket.sumG / count).round().clamp(0, 255);
      final meanB = (bucket.sumB / count).round().clamp(0, 255);
      final lab = rgbToLab(meanR, meanG, meanB);
      bL[i] = lab.l;
      bA[i] = lab.a;
      bB[i] = lab.b;
      bWeight[i] = count.toDouble();
    }

    final targetK = math.min(config.clusterCount.clamp(2, 16), n);
    final centroids = _runDeterministicKMeansPlusPlus(
      sortedBuckets: sortedBuckets,
      bL: bL,
      bA: bA,
      bB: bB,
      bWeight: bWeight,
      k: targetK,
      maxIterations: config.maxIterations,
      convergenceDeltaE: config.convergenceDeltaE,
      totalPixels: opaquePixels,
    );

    final merged = _mergeNearDuplicateClusters(
      centroids,
      mergeDeltaE: config.mergeDeltaE,
    );

    final clusters = _classifyClusters(
      merged,
      totalPixels: opaquePixels,
      scoring: config.scoring,
    );

    final rankedAccents = rankAccentCandidates(
      clusters,
      scoring: config.scoring,
    );

    sw.stop();
    return (
      clusters: clusters,
      rankedAccents: rankedAccents,
      sampledPixelCount: opaquePixels,
      analysisMs: sw.elapsedMilliseconds,
    );
  }

  static List<_LabClusterAccumulator> _runDeterministicKMeansPlusPlus({
    required List<_ColorBucket> sortedBuckets,
    required Float64List bL,
    required Float64List bA,
    required Float64List bB,
    required Float64List bWeight,
    required int k,
    required int maxIterations,
    required double convergenceDeltaE,
    required int totalPixels,
  }) {
    final n = sortedBuckets.length;
    final cL = Float64List(k);
    final cA = Float64List(k);
    final cB = Float64List(k);

    // Deterministic FNV-1a seed from image statistics.
    int seed = 0x811C9DC5 ^ totalPixels ^ n;
    seed = ((seed ^ sortedBuckets.first.key) * 0x01000193) & 0x7FFFFFFF;
    seed = ((seed ^ sortedBuckets[n ~/ 2].key) * 0x01000193) & 0x7FFFFFFF;
    seed = ((seed ^ sortedBuckets.last.key) * 0x01000193) & 0x7FFFFFFF;
    final rng = math.Random(seed);

    // Centroid 0: highest-weight bucket (deterministic tie-break on index).
    int bestIdx = 0;
    double bestWeight = -1.0;
    for (int i = 0; i < n; i++) {
      if (bWeight[i] > bestWeight) {
        bestWeight = bWeight[i];
        bestIdx = i;
      }
    }
    cL[0] = bL[bestIdx];
    cA[0] = bA[bestIdx];
    cB[0] = bB[bestIdx];

    final minDistSq = Float64List(n);
    for (int i = 0; i < n; i++) {
      final dl = bL[i] - cL[0];
      final da = bA[i] - cA[0];
      final db = bB[i] - cB[0];
      minDistSq[i] = dl * dl + da * da + db * db;
    }

    // Remaining k-1 centroids via D^2 weighted K-Means++.
    for (int c = 1; c < k; c++) {
      double totalPotential = 0.0;
      for (int i = 0; i < n; i++) {
        totalPotential += bWeight[i] * minDistSq[i];
      }

      int chosen = 0;
      if (totalPotential > 0.0) {
        final target = rng.nextDouble() * totalPotential;
        double cumulative = 0.0;
        chosen = n - 1;
        for (int i = 0; i < n; i++) {
          cumulative += bWeight[i] * minDistSq[i];
          if (cumulative >= target) {
            chosen = i;
            break;
          }
        }
      } else {
        chosen = c % n;
      }

      cL[c] = bL[chosen];
      cA[c] = bA[chosen];
      cB[c] = bB[chosen];

      if (c + 1 < k) {
        for (int i = 0; i < n; i++) {
          final dl = bL[i] - cL[c];
          final da = bA[i] - cA[c];
          final db = bB[i] - cB[c];
          final dSq = dl * dl + da * da + db * db;
          if (dSq < minDistSq[i]) {
            minDistSq[i] = dSq;
          }
        }
      }
    }

    final assignments = Int32List(n);
    final sumL = Float64List(k);
    final sumA = Float64List(k);
    final sumB = Float64List(k);
    final sumW = Float64List(k);
    final convSq = convergenceDeltaE * convergenceDeltaE;

    for (int iter = 0; iter < maxIterations; iter++) {
      for (int c = 0; c < k; c++) {
        sumL[c] = 0.0;
        sumA[c] = 0.0;
        sumB[c] = 0.0;
        sumW[c] = 0.0;
      }

      for (int i = 0; i < n; i++) {
        final l = bL[i];
        final a = bA[i];
        final b = bB[i];
        final w = bWeight[i];

        int nearest = 0;
        double nearestSq = double.infinity;
        for (int c = 0; c < k; c++) {
          final dl = l - cL[c];
          final da = a - cA[c];
          final db = b - cB[c];
          final dSq = dl * dl + da * da + db * db;
          if (dSq < nearestSq) {
            nearestSq = dSq;
            nearest = c;
          }
        }
        assignments[i] = nearest;
        sumL[nearest] += l * w;
        sumA[nearest] += a * w;
        sumB[nearest] += b * w;
        sumW[nearest] += w;
      }

      double maxShiftSq = 0.0;
      for (int c = 0; c < k; c++) {
        if (sumW[c] <= 0.0) continue;
        final newL = sumL[c] / sumW[c];
        final newA = sumA[c] / sumW[c];
        final newB = sumB[c] / sumW[c];
        final dl = newL - cL[c];
        final da = newA - cA[c];
        final db = newB - cB[c];
        final shiftSq = dl * dl + da * da + db * db;
        if (shiftSq > maxShiftSq) {
          maxShiftSq = shiftSq;
        }
        cL[c] = newL;
        cA[c] = newA;
        cB[c] = newB;
      }

      if (maxShiftSq < convSq) {
        break;
      }
    }

    // Final exact assignment pass so weights match final centroids.
    for (int c = 0; c < k; c++) {
      sumL[c] = 0.0;
      sumA[c] = 0.0;
      sumB[c] = 0.0;
      sumW[c] = 0.0;
    }
    for (int i = 0; i < n; i++) {
      final l = bL[i];
      final a = bA[i];
      final b = bB[i];
      final w = bWeight[i];
      int nearest = 0;
      double nearestSq = double.infinity;
      for (int c = 0; c < k; c++) {
        final dl = l - cL[c];
        final da = a - cA[c];
        final db = b - cB[c];
        final dSq = dl * dl + da * da + db * db;
        if (dSq < nearestSq) {
          nearestSq = dSq;
          nearest = c;
        }
      }
      sumL[nearest] += l * w;
      sumA[nearest] += a * w;
      sumB[nearest] += b * w;
      sumW[nearest] += w;
    }

    final result = <_LabClusterAccumulator>[];
    for (int c = 0; c < k; c++) {
      if (sumW[c] <= 0.0) continue;
      result.add(
        _LabClusterAccumulator(
          lab: LabColor(
            sumL[c] / sumW[c],
            sumA[c] / sumW[c],
            sumB[c] / sumW[c],
          ),
          weight: sumW[c],
        ),
      );
    }
    return result;
  }

  static List<_LabClusterAccumulator> _mergeNearDuplicateClusters(
    List<_LabClusterAccumulator> raw, {
    required double mergeDeltaE,
  }) {
    final working = List<_LabClusterAccumulator>.from(raw)
      ..sort((a, b) => b.weight.compareTo(a.weight));

    bool mergedAny = true;
    while (mergedAny && working.length > 1) {
      mergedAny = false;
      double closestDeltaE = mergeDeltaE;
      int mergeI = -1;
      int mergeJ = -1;

      for (int i = 0; i < working.length; i++) {
        for (int j = i + 1; j < working.length; j++) {
          final d = working[i].lab.deltaE(working[j].lab);
          if (d < closestDeltaE) {
            closestDeltaE = d;
            mergeI = i;
            mergeJ = j;
          }
        }
      }

      if (mergeI != -1 && mergeJ != -1) {
        final a = working[mergeI];
        final b = working[mergeJ];
        final totalW = a.weight + b.weight;
        working[mergeI] = _LabClusterAccumulator(
          lab: LabColor(
            (a.lab.l * a.weight + b.lab.l * b.weight) / totalW,
            (a.lab.a * a.weight + b.lab.a * b.weight) / totalW,
            (a.lab.b * a.weight + b.lab.b * b.weight) / totalW,
          ),
          weight: totalW,
        );
        working.removeAt(mergeJ);
        working.sort((x, y) => y.weight.compareTo(x.weight));
        mergedAny = true;
      }
    }
    return working;
  }

  static List<AnalyzedColorCluster> _classifyClusters(
    List<_LabClusterAccumulator> merged, {
    required int totalPixels,
    required AccentScoringConfig scoring,
  }) {
    if (merged.isEmpty) return const [];
    final dominantLab = merged.first.lab;
    final clusters = <AnalyzedColorCluster>[];

    for (int i = 0; i < merged.length; i++) {
      final entry = merged[i];
      final pop = (entry.weight / totalPixels).clamp(0.0, 1.0);
      final lab = entry.lab;
      final argb = labToArgb(lab);
      final chroma = lab.chroma;
      final lightness = lab.l;
      final hue = lab.hue;

      double distinctiveness = 0.0;
      if (merged.length > 1) {
        double weightedSum = 0.0;
        double otherWeightSum = 0.0;
        for (int j = 0; j < merged.length; j++) {
          if (i == j) continue;
          final otherPop = (merged[j].weight / totalPixels).clamp(0.0, 1.0);
          weightedSum += lab.deltaE(merged[j].lab) * otherPop;
          otherWeightSum += otherPop;
        }
        final weightedMeanDelta =
            otherWeightSum > 0 ? weightedSum / otherWeightSum : 0.0;
        distinctiveness = i == 0
            ? weightedMeanDelta
            : 0.60 * lab.deltaE(dominantLab) + 0.40 * weightedMeanDelta;
      }

      final categories = <ColorCategory>{};
      if (i == 0 || pop >= 0.22) {
        categories.add(ColorCategory.dominant);
      }
      if (chroma < 14.0) {
        categories.add(ColorCategory.neutral);
      } else if (chroma < 34.0) {
        categories.add(ColorCategory.muted);
      } else if (lightness >= 18.0 && lightness <= 88.0) {
        categories.add(ColorCategory.vibrant);
      }

      if (lightness < 30.0) {
        categories.add(ColorCategory.dark);
      } else if (lightness > 72.0) {
        categories.add(ColorCategory.light);
      }

      if (chroma >= scoring.minAccentChroma &&
          pop >= scoring.minAccentPopulation &&
          lightness >= 12.0 &&
          lightness <= 95.0) {
        categories.add(ColorCategory.accentCandidate);
      }

      clusters.add(
        AnalyzedColorCluster(
          argb: argb,
          lab: lab,
          population: pop,
          lightness: lightness,
          chroma: chroma,
          hue: hue,
          distinctiveness: distinctiveness,
          categories: Set.unmodifiable(categories),
        ),
      );
    }

    return List.unmodifiable(clusters);
  }

  /// Deterministically scores and ranks distinct accent candidates from [clusters].
  static List<RankedAccentCandidate> rankAccentCandidates(
    List<AnalyzedColorCluster> clusters, {
    AccentScoringConfig scoring = const AccentScoringConfig(),
  }) {
    if (clusters.isEmpty) return const [];

    const darkSurfaceProbe = 0xFF141923;
    final scored = <RankedAccentCandidate>[];
    final totalWeight = scoring.chromaWeight +
        scoring.distinctivenessWeight +
        scoring.populationWeight +
        scoring.luminanceWeight +
        scoring.contrastPotentialWeight +
        scoring.designCompatibilityWeight;
    final norm = totalWeight > 0 ? totalWeight : 1.0;

    for (final cluster in clusters) {
      final chroma = cluster.chroma;
      final lStar = cluster.lightness;
      final pop = cluster.population;

      // 1. Chroma score: heavily rewards genuine chromatic presence over gray.
      final double chromaScore;
      if (chroma < 10.0) {
        chromaScore = (chroma / 10.0) * 0.10;
      } else if (chroma < 42.0) {
        chromaScore = 0.10 + 0.65 * ((chroma - 10.0) / 32.0);
      } else if (chroma <= 88.0) {
        chromaScore = 0.75 + 0.25 * ((chroma - 42.0) / 46.0);
      } else {
        chromaScore = 1.0 - ((chroma - 88.0) / 80.0).clamp(0.0, 0.15);
      }

      // 2. Perceptual distinctiveness from dominant / surrounding clusters.
      final distinctivenessScore =
          (cluster.distinctiveness / 65.0).clamp(0.0, 1.0);

      // 3. Sub-linear population curve so small focal accents stay competitive
      // while 1-pixel noise below minAccentPopulation is penalized.
      final double populationScore;
      if (pop < scoring.minAccentPopulation) {
        populationScore = (pop / scoring.minAccentPopulation) * 0.12;
      } else {
        populationScore = math.pow(pop, 0.35).toDouble().clamp(0.0, 1.0);
      }

      // 4. Luminance suitability (prefers clean chromatic mid-tones L* 35..78).
      final double luminanceScore;
      if (lStar >= 35.0 && lStar <= 78.0) {
        luminanceScore = 1.0;
      } else if (lStar < 35.0) {
        luminanceScore = ((lStar - 8.0) / 27.0).clamp(0.05, 1.0);
      } else {
        luminanceScore = (1.0 - (lStar - 78.0) / 22.0).clamp(0.10, 1.0);
      }

      // 5. Contrast potential in HCT on dark SautiPlay surfaces + dislike penalty.
      final hct = Hct.fromInt(cluster.argb);
      final adapted = Hct.from(
        hct.hue,
        hct.chroma.clamp(16.0, 62.0),
        72.0,
      );
      final contrastRatio =
          wcagContrastRatio(adapted.toInt(), darkSurfaceProbe);
      double contrastScore = ((contrastRatio - 1.5) / 6.5).clamp(0.0, 1.0);
      if (DislikeAnalyzer.isDisliked(hct)) {
        contrastScore *= 0.85;
      }

      // 6. Compatibility with SautiPlay's dark audiophile aesthetic.
      double designCompat = 1.0;
      if (lStar < 14.0 || lStar > 94.0) {
        designCompat *= 0.20;
      }
      if (chroma < 14.0) {
        designCompat *= 0.25;
      }
      if (chroma > 95.0) {
        designCompat *= 0.85;
      }

      final weighted = (chromaScore * scoring.chromaWeight +
              distinctivenessScore * scoring.distinctivenessWeight +
              populationScore * scoring.populationWeight +
              luminanceScore * scoring.luminanceWeight +
              contrastScore * scoring.contrastPotentialWeight +
              designCompat * scoring.designCompatibilityWeight) /
          norm;

      final isCandidate =
          cluster.categories.contains(ColorCategory.accentCandidate);
      final finalScore = isCandidate ? weighted : weighted * 0.40;

      scored.add(
        RankedAccentCandidate(
          cluster: cluster,
          score: finalScore,
          chromaScore: chromaScore,
          distinctivenessScore: distinctivenessScore,
          populationScore: populationScore,
          luminanceScore: luminanceScore,
          contrastScore: contrastScore,
          designCompatibilityScore: designCompat,
        ),
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      final popCmp = b.cluster.population.compareTo(a.cluster.population);
      if (popCmp != 0) return popCmp;
      return a.cluster.argb.compareTo(b.cluster.argb);
    });

    // Deduplicate ranked candidates so the theme generator gets perceptually
    // distinct accent choices.
    final selected = <RankedAccentCandidate>[];
    for (final candidate in scored) {
      if (selected.length >= scoring.maxCandidates) break;
      final isDistinct = selected.every(
        (kept) =>
            candidate.cluster.lab.deltaE(kept.cluster.lab) >=
            scoring.minCandidateDeltaE,
      );
      if (isDistinct) {
        selected.add(candidate);
      }
    }

    if (selected.isEmpty && scored.isNotEmpty) {
      selected.add(scored.first);
    }

    return List.unmodifiable(selected);
  }
}

class _ColorBucket {
  final int key;
  int count = 1;
  int sumR;
  int sumG;
  int sumB;

  _ColorBucket(this.key, this.sumR, this.sumG, this.sumB);

  void add(int r, int g, int b) {
    count++;
    sumR += r;
    sumG += g;
    sumB += b;
  }
}

class _LabClusterAccumulator {
  final LabColor lab;
  final double weight;

  const _LabClusterAccumulator({required this.lab, required this.weight});
}
