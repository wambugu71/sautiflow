import 'dart:io';
import 'dart:math' as math;
import 'package:sautiflow/sautiflow.dart';

/// Parsed AutoEQ Result containing preamp cut, actual parametric filters (if PEQ),
/// raw GraphicEQ frequency-gain pairs (if GEQ), and 31-band equalizer values.
class AutoEqResult {
  final String profileName;
  final double preampGainDb;
  final List<double> bandLevels31; // Normalized [0.0..1.0] (0.5 = 0 dB)
  final List<double> bandGainDbs31; // Raw dB values (-12 dB to +12 dB)
  final bool isGraphicEq;
  final List<EqBandConfig> parametricBands;
  final Map<double, double> rawGraphicPairs;

  bool get isParametric => !isGraphicEq;

  AutoEqResult({
    required this.profileName,
    required this.preampGainDb,
    required this.bandLevels31,
    required this.bandGainDbs31,
    required this.isGraphicEq,
    this.parametricBands = const [],
    this.rawGraphicPairs = const {},
  });

  /// Dynamically extracts or interpolates gains for any list of target center frequencies (e.g. 10, 16, 32 bands).
  List<double> getGainsForFrequencies(List<double> targetFreqs) {
    if (isGraphicEq && rawGraphicPairs.isNotEmpty) {
      return targetFreqs
          .map((f) => AutoEqParser.interpolateGain(rawGraphicPairs, f))
          .toList();
    } else if (parametricBands.isNotEmpty) {
      // Evaluate parametric biquad curve directly at target frequencies
      return targetFreqs.map((f) {
        double sumDb = 0.0;
        for (final b in parametricBands) {
          if (!b.enabled) continue;
          sumDb += AutoEqParser.evaluateParametricBandDb(
            type: b.type,
            fc: b.frequencyHz,
            gainDb: b.gainDb,
            q: b.q,
            slope: b.slope,
            f: f,
          );
        }
        return sumDb;
      }).toList();
    } else if (bandGainDbs31.isNotEmpty) {
      final map31 = <double, double>{};
      for (int i = 0; i < AutoEqParser.iso31CenterFreqs.length; i++) {
        if (i < bandGainDbs31.length) {
          map31[AutoEqParser.iso31CenterFreqs[i]] = bandGainDbs31[i];
        }
      }
      return targetFreqs
          .map((f) => AutoEqParser.interpolateGain(map31, f))
          .toList();
    }
    return List.filled(targetFreqs.length, 0.0);
  }
}

class AutoEqParser {
  static const List<double> iso31CenterFreqs = [
    20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0,
    250.0, 315.0, 400.0, 500.0, 630.0, 800.0, 1000.0, 1250.0, 1600.0, 2000.0,
    2500.0, 3150.0, 4000.0, 5000.0, 6300.0, 8000.0, 10000.0, 12500.0, 16000.0, 20000.0
  ];

  /// Returns true if content is GraphicEQ or fixed frequency response table format.
  static bool isGraphicEq(String content) {
    if (content.contains('GraphicEQ:')) return true;

    // Check if lines are comma/tab separated frequency/gain pairs without "Filter"
    final lines = content.split('\n');
    int numericPairCount = 0;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.toLowerCase().startsWith('filter')) return false;

      final parts = line.split(RegExp(r'[,;\t\s]+'));
      if (parts.length >= 2) {
        final f = double.tryParse(parts[0]);
        final g = double.tryParse(parts[1]);
        if (f != null && g != null && f > 0) {
          numericPairCount++;
          if (numericPairCount >= 4) return true;
        }
      }
    }
    return false;
  }

  /// Returns true if content is EqualizerAPO ParametricEQ format.
  static bool isParametricEq(String content) {
    return !isGraphicEq(content);
  }

  /// Parses an AutoEQ file (.txt, GraphicEQ, or ParametricEQ) by file path.
  static AutoEqResult parseFile(String filePath) {
    final file = File(filePath);
    final content = file.readAsStringSync();
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.replaceAll(RegExp(r'\.(txt|csv)$', caseSensitive: false), '')
        : 'AutoEQ Profile';
    return parseContent(content, profileName: name);
  }

  /// Parses AutoEQ text content (GraphicEQ or ParametricEQ string).
  static AutoEqResult parseContent(String content, {String profileName = 'AutoEQ Profile'}) {
    if (isGraphicEq(content)) {
      return _parseGraphicEq(content, profileName);
    } else {
      return _parseParametricEq(content, profileName);
    }
  }

  /// Parses GraphicEQ string format or CSV frequency/gain points.
  static AutoEqResult _parseGraphicEq(String content, String profileName) {
    final Map<double, double> gainMap = {};
    double preampDb = 0.0;

    final lines = content.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('//')) {
        continue;
      }

      if (trimmed.toLowerCase().startsWith('preamp:')) {
        final match = RegExp(r'Preamp:\s*([+-]?\d+\.?\d*)\s*dB', caseSensitive: false).firstMatch(trimmed);
        if (match != null) {
          preampDb = double.tryParse(match.group(1) ?? '0') ?? 0.0;
        }
      } else if (trimmed.contains('GraphicEQ:')) {
        final rawPairs = trimmed.replaceAll('GraphicEQ:', '').trim().split(';');
        for (var pair in rawPairs) {
          final parts = pair.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final freq = double.tryParse(parts[0]);
            final gain = double.tryParse(parts[1]);
            if (freq != null && gain != null) {
              gainMap[freq] = gain;
            }
          }
        }
      } else {
        // Check for CSV / space / tab separated: freq,gain
        final parts = trimmed.split(RegExp(r'[,;\t\s]+'));
        if (parts.length >= 2) {
          final freq = double.tryParse(parts[0]);
          final gain = double.tryParse(parts[1]);
          if (freq != null && gain != null && freq > 0) {
            gainMap[freq] = gain;
          }
        }
      }
    }

    final List<double> rawDbs = [];
    final List<double> normalized = [];

    for (var centerFreq in iso31CenterFreqs) {
      double gainDb = interpolateGain(gainMap, centerFreq);
      rawDbs.add(gainDb);
      // Map [-12 dB .. +12 dB] to [0.0 .. 1.0], with 0 dB = 0.5
      double norm = ((gainDb + 12.0) / 24.0).clamp(0.0, 1.0);
      normalized.add(norm);
    }

    return AutoEqResult(
      profileName: profileName,
      preampGainDb: preampDb,
      bandLevels31: normalized,
      bandGainDbs31: rawDbs,
      isGraphicEq: true,
      rawGraphicPairs: gainMap,
    );
  }

  /// Parses EqualizerAPO ParametricEQ format into actual EqBandConfig filters.
  static AutoEqResult _parseParametricEq(String content, String profileName) {
    double preampDb = 0.0;
    final List<EqBandConfig> pBands = [];

    final lines = content.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('//')) {
        continue;
      }

      if (trimmed.toLowerCase().startsWith('preamp:')) {
        final match = RegExp(r'Preamp:\s*([+-]?\d+\.?\d*)\s*dB', caseSensitive: false).firstMatch(trimmed);
        if (match != null) {
          preampDb = double.tryParse(match.group(1) ?? '0') ?? 0.0;
        }
      } else if (trimmed.toLowerCase().startsWith('filter')) {
        // Supports standard EqualizerAPO with Gain/Q/Slope as well as gainless HP/LP/NO/AP lines
        final filterMatch = RegExp(
          r'Filter\s*(?:\d+)?:\s*(ON|OFF)\s+([A-Z0-9_]+)\s+Fc\s+([0-9.]+)\s*(?:Hz)?(.*)$',
          caseSensitive: false,
        ).firstMatch(trimmed);

        if (filterMatch != null) {
          final enabled = filterMatch.group(1)?.toUpperCase() == 'ON';
          final typeStr = filterMatch.group(2)?.toUpperCase() ?? 'PK';
          final fc = double.tryParse(filterMatch.group(3) ?? '1000') ?? 1000.0;
          final tail = filterMatch.group(4) ?? '';

          final gainMatch = RegExp(
            r'Gain\s+([+-]?[0-9.]+)\s*(?:dB)?',
            caseSensitive: false,
          ).firstMatch(tail);
          final qMatch = RegExp(
            r'(?:^|\s)Q\s+([0-9.]+)',
            caseSensitive: false,
          ).firstMatch(tail);
          final slopeMatch = RegExp(
            r'(?:^|\s)(?:Slope|S)\s+([0-9.]+)',
            caseSensitive: false,
          ).firstMatch(tail);

          EqBandType bType = EqBandType.peak;
          if (typeStr == 'LSC' ||
              typeStr == 'LS' ||
              typeStr == 'LOWSHELF' ||
              typeStr == 'LOW_SHELF') {
            bType = EqBandType.lowshelf;
          } else if (typeStr == 'HSC' ||
              typeStr == 'HS' ||
              typeStr == 'HIGHSHELF' ||
              typeStr == 'HIGH_SHELF') {
            bType = EqBandType.highshelf;
          } else if (typeStr == 'LP' ||
              typeStr == 'LPF' ||
              typeStr == 'LPQ' ||
              typeStr == 'LOWPASS' ||
              typeStr == 'LOW_PASS') {
            bType = EqBandType.lowpass;
          } else if (typeStr == 'HP' ||
              typeStr == 'HPF' ||
              typeStr == 'HPQ' ||
              typeStr == 'HIGHPASS' ||
              typeStr == 'HIGH_PASS') {
            bType = EqBandType.highpass;
          } else if (typeStr == 'BP' ||
              typeStr == 'BPF' ||
              typeStr == 'BANDPASS' ||
              typeStr == 'BAND_PASS') {
            bType = EqBandType.bandpass;
          } else if (typeStr == 'NO' || typeStr == 'NOTCH') {
            bType = EqBandType.notch;
          } else if (typeStr == 'TILT') {
            bType = EqBandType.tilt;
          } else if (typeStr == 'AP' ||
              typeStr == 'ALLPASS' ||
              typeStr == 'ALL_PASS') {
            bType = EqBandType.allpass;
          } else if (typeStr == 'BR' ||
              typeStr == 'BANDREJECT' ||
              typeStr == 'BAND_REJECT') {
            bType = EqBandType.bandreject;
          }

          final parsedGain = gainMatch != null
              ? double.tryParse(gainMatch.group(1) ?? '')
              : null;
          final parsedQ =
              qMatch != null ? double.tryParse(qMatch.group(1) ?? '') : null;
          final parsedSlope = slopeMatch != null
              ? double.tryParse(slopeMatch.group(1) ?? '')
              : null;

          final isShelfOrTilt = bType == EqBandType.lowshelf ||
              bType == EqBandType.highshelf ||
              bType == EqBandType.tilt;
          final isPass =
              bType == EqBandType.lowpass || bType == EqBandType.highpass;

          final gain = (bType == EqBandType.bandreject && parsedGain != null)
              ? parsedGain.clamp(-24.0, 0.0)
              : (parsedGain ?? 0.0);
          final slope = (isShelfOrTilt && parsedSlope != null)
              ? parsedSlope.clamp(0.1, 1.0)
              : 1.0;
          final q = parsedQ ??
              ((isShelfOrTilt && parsedSlope == null) || isPass
                  ? 0.70710678
                  : 1.0);

          pBands.add(EqBandConfig(
            type: bType,
            frequencyHz: fc,
            gainDb: gain,
            q: q,
            slope: slope,
            enabled: enabled,
          ));
        }
      }
    }

    // Evaluate approximate response across 31 ISO center frequencies
    final List<double> rawDbs = [];
    final List<double> normalized = [];

    for (var f in iso31CenterFreqs) {
      double totalDb = 0.0;
      for (var band in pBands) {
        if (!band.enabled) continue;
        totalDb += evaluateParametricBandDb(
          type: band.type,
          fc: band.frequencyHz,
          gainDb: band.gainDb,
          q: band.q,
          slope: band.slope,
          f: f,
        );
      }
      rawDbs.add(totalDb);
      double norm = ((totalDb + 12.0) / 24.0).clamp(0.0, 1.0);
      normalized.add(norm);
    }

    return AutoEqResult(
      profileName: profileName,
      preampGainDb: preampDb,
      bandLevels31: normalized,
      bandGainDbs31: rawDbs,
      isGraphicEq: false,
      parametricBands: pBands,
    );
  }

  /// Linear interpolation helper for frequency points in logarithmic space.
  static double interpolateGain(Map<double, double> gainMap, double targetFreq) {
    if (gainMap.isEmpty) return 0.0;
    if (gainMap.containsKey(targetFreq)) return gainMap[targetFreq]!;

    final sortedFreqs = gainMap.keys.toList()..sort();
    if (targetFreq <= sortedFreqs.first) return gainMap[sortedFreqs.first]!;
    if (targetFreq >= sortedFreqs.last) return gainMap[sortedFreqs.last]!;

    for (int i = 0; i < sortedFreqs.length - 1; i++) {
      double f1 = sortedFreqs[i];
      double f2 = sortedFreqs[i + 1];
      if (targetFreq >= f1 && targetFreq <= f2) {
        double g1 = gainMap[f1]!;
        double g2 = gainMap[f2]!;
        // Logarithmic frequency interpolation
        double logF1 = math.log(math.max(f1, 1.0));
        double logF2 = math.log(math.max(f2, 1.0));
        double logT = math.log(math.max(targetFreq, 1.0));
        double ratio = (logT - logF1) / (logF2 - logF1);
        return g1 + ratio * (g2 - g1);
      }
    }
    return 0.0;
  }

  static double _analogHighShelfMag(
      double freqHz, double fcHz, double a, double k0) {
    final u = freqHz / fcHz;
    final u2 = u * u;
    final sqrtA = math.sqrt(a);
    final imag = k0 * sqrtA * u;
    final numRe = 1.0 - a * u2;
    final denRe = a - u2;
    final numMagSq = numRe * numRe + imag * imag;
    final denMagSq = math.max(denRe * denRe + imag * imag, 1.0e-30);
    return a * math.sqrt(numMagSq / denMagSq);
  }

  /// Evaluates exact Cytomic TPT SVF dB response at frequency [f] for a parametric filter.
  static double evaluateParametricBandDb({
    required EqBandType type,
    required double fc,
    required double gainDb,
    required double q,
    double slope = 1.0,
    required double f,
    double fs = 48000.0,
  }) {
    if (f <= 0 || fc <= 0 || fs <= 0) return 0.0;
    final fcClamped = fc.clamp(10.0, fs * 0.499);
    final clampedGain = gainDb.clamp(-36.0, 36.0);

    final isGainType = type == EqBandType.peak ||
        type == EqBandType.bell ||
        type == EqBandType.lowshelf ||
        type == EqBandType.highshelf ||
        type == EqBandType.tilt;
    if (isGainType && clampedGain.abs() < 0.005) {
      return 0.0;
    }
    if (type == EqBandType.allpass) {
      return 0.0;
    }

    final isShelfOrTilt = type == EqBandType.lowshelf ||
        type == EqBandType.highshelf ||
        type == EqBandType.tilt;
    double rawQ = q;
    if (isShelfOrTilt) {
      const kButterworthQ = 0.7071067811865475;
      if ((slope - 1.0).abs() > 1.0e-5 && slope > 0.0) {
        final s = slope.clamp(0.1, 1.0);
        final aAbs = math.pow(10.0, clampedGain.abs() / 40.0).toDouble();
        final invQ2 = (aAbs + 1.0 / aAbs) * (1.0 / s - 1.0) + 2.0;
        rawQ = 1.0 / math.sqrt(math.max(invQ2, 1.0e-6));
      } else if ((q - 1.0).abs() > 1.0e-5 && q > 0.0) {
        rawQ = q;
      } else {
        rawQ = kButterworthQ;
      }
    }
    final effQ = rawQ.clamp(0.05, 30.0);
    final w0 = 2.0 * math.pi * fcClamped / fs;
    final a = math.pow(10.0, clampedGain / 40.0).toDouble();
    final k0 = 1.0 / effQ;
    final t0 = math.tan(0.5 * w0);

    double g = t0;
    double k = k0;
    double m0 = 1.0;
    double m1 = 0.0;
    double m2 = 0.0;

    switch (type) {
      case EqBandType.peak:
      case EqBandType.bell:
        final absGainDb = clampedGain.abs();
        final aPos = math.pow(10.0, absGainDb / 40.0).toDouble();
        final gPos = aPos * aPos;
        final gb = aPos;
        final r =
            math.sqrt(1.0 + 1.0 / (4.0 * effQ * effQ)) - 1.0 / (2.0 * effQ);
        final t1 = math.tan(0.5 * w0 * r);
        final uNyq = math.pi / w0;
        final oneMinusU2 = 1.0 - uNyq * uNyq;
        final bwTermNum = (aPos * uNyq) / effQ;
        final bwTermDen = uNyq / (effQ * aPos);
        final g1Sq = (oneMinusU2 * oneMinusU2 + bwTermNum * bwTermNum) /
            math.max(oneMinusU2 * oneMinusU2 + bwTermDen * bwTermDen, 1.0e-30);
        final g1 = math.sqrt(math.min(g1Sq, gPos * gPos - 1.0e-15));
        final x0 = math.max(t0 * t0, 1.0e-24);
        final x1 = math.max(t1 * t1, 1.0e-24);
        final g2M1 = math.max(gPos * gPos - 1.0, 1.0e-24);
        final w2 = x0 *
            math.sqrt(math.max((gPos * gPos - g1Sq) / g2M1, 1.0e-18));
        final rhs1 = (gPos * gPos * (w2 - x0) * (w2 - x0) -
                (w2 - g1 * x0) * (w2 - g1 * x0)) /
            x0;
        final rhs2 = (gb * gb * (w2 - x1) * (w2 - x1) -
                (w2 - g1 * x1) * (w2 - g1 * x1)) /
            x1;
        final bd2 = math.max(
            (rhs2 - rhs1) / math.max(gPos * gPos - gb * gb, 1.0e-24), 1.0e-24);
        final bn2 = math.max(rhs1 + gPos * gPos * bd2, 1.0e-24);
        final bn = math.sqrt(bn2);
        final bd = math.sqrt(bd2);
        if (clampedGain >= 0.0) {
          g = math.sqrt(w2);
          k = bd / g;
          m0 = g1;
          m1 = (bn / g) - g1 * k;
          m2 = 1.0 - g1;
        } else {
          final invG1 = 1.0 / g1;
          g = math.sqrt(w2 * invG1);
          k = bd > 0.0 ? (bn * invG1) / g : k0;
          m0 = invG1;
          m1 = ((bd * invG1) / g) - invG1 * k;
          m2 = 1.0 - invG1;
        }
        break;

      case EqBandType.lowshelf:
        g = t0 / math.sqrt(a);
        m0 = 1.0;
        m1 = k0 * (a - 1.0);
        m2 = a * a - 1.0;
        break;

      case EqBandType.highshelf:
        final aPos = math.pow(10.0, clampedGain.abs() / 40.0).toDouble();
        final g1 = _analogHighShelfMag(0.5 * fs, fcClamped, aPos, k0);
        final r = (g1 + aPos) / (1.0 + aPos);
        final w2 = t0 * t0 * r;
        final gBoost = math.sqrt(w2);
        final ratioNyq = (fcClamped / (0.5 * fs)).clamp(0.0, 1.0);
        final blend = ratioNyq * ratioNyq;
        final fRef = (1.0 - blend) * (0.7 * fcClamped) +
            blend * math.sqrt(fcClamped * 0.48 * fs);
        final m = _analogHighShelfMag(fRef, fcClamped, aPos, k0);
        final m2Sq = m * m;
        final t1 = math.tan(math.pi * fRef / fs);
        final x1 = t1 * t1;
        final denomK = w2 * x1 * (m2Sq - aPos * aPos);
        final numK =
            (w2 - g1 * x1) * (w2 - g1 * x1) - m2Sq * (w2 - x1) * (w2 - x1);
        double kEff = k0;
        if (denomK.abs() > 1.0e-12 && (numK / denomK) > 0.0) {
          kEff = math.sqrt(numK / denomK).clamp(0.25 * k0, 4.0 * k0).toDouble();
        }
        if (clampedGain >= 0.0) {
          g = gBoost;
          k = kEff;
          m0 = g1;
          m1 = (aPos - g1) * kEff;
          m2 = 1.0 - g1;
        } else {
          final sqrtG1 = math.sqrt(g1);
          final invG1 = 1.0 / g1;
          g = gBoost / sqrtG1;
          k = (aPos * kEff) / sqrtG1;
          m0 = invG1;
          m1 = (kEff / sqrtG1) - invG1 * k;
          m2 = 1.0 - invG1;
        }
        break;

      case EqBandType.bandpass:
        m0 = 0.0;
        m1 = 1.0;
        m2 = 0.0;
        break;

      case EqBandType.notch:
        m0 = 1.0;
        m1 = -k0;
        m2 = 0.0;
        break;

      case EqBandType.lowpass:
        m0 = 0.0;
        m1 = 0.0;
        m2 = 1.0;
        break;

      case EqBandType.highpass:
        m0 = 1.0;
        m1 = -k0;
        m2 = -1.0;
        break;

      case EqBandType.tilt:
        g = t0 * math.sqrt(a);
        m0 = a;
        m1 = (1.0 - a) * k0;
        m2 = (1.0 / a) - a;
        break;

      case EqBandType.bandreject:
        final gCut = clampedGain.abs() < 0.005
            ? 0.0
            : math.pow(10.0, -clampedGain.abs() / 20.0).toDouble();
        m0 = 1.0;
        m1 = (gCut - 1.0) * k0;
        m2 = 0.0;
        break;

      case EqBandType.allpass:
      case EqBandType.asupercut:
      case EqBandType.asuperpass:
      case EqBandType.asuperstop:
        return 0.0;
    }

    if (f >= 0.5 * fs * (1.0 - 1.0e-7)) {
      return 20.0 * (math.log(math.max(m0.abs(), 1.0e-12)) / math.ln10);
    }
    final t = math.tan(math.pi * f / fs);
    final t2 = t * t;
    final g2 = g * g;
    final kg = k * g;
    final denRe = g2 - t2;
    final denIm = kg * t;
    final numRe = m0 * denRe + m2 * g2;
    final numIm = (m0 * kg + m1 * g) * t;
    final numMagSq = numRe * numRe + numIm * numIm;
    final denMagSq = math.max(denRe * denRe + denIm * denIm, 1.0e-30);
    final magSq = numMagSq / denMagSq;
    if (magSq <= 1.0e-12) return -60.0;
    return 10.0 * (math.log(magSq) / math.ln10);
  }
}
