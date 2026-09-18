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
        // e.g. Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.71
        // or Filter: ON LSC Fc 105 Gain 5.5 Q 0.71
        final filterMatch = RegExp(
          r'Filter\s*(?:\d+)?:\s*(ON|OFF)\s+([A-Z0-9_]+)\s+Fc\s+([0-9.]+)\s*(?:Hz)?\s+Gain\s+([+-]?[0-9.]+)\s*(?:dB)?(?:\s+Q\s+([0-9.]+))?',
          caseSensitive: false,
        ).firstMatch(trimmed);

        if (filterMatch != null) {
          final enabled = filterMatch.group(1)?.toUpperCase() == 'ON';
          final typeStr = filterMatch.group(2)?.toUpperCase() ?? 'PK';
          final fc = double.tryParse(filterMatch.group(3) ?? '1000') ?? 1000.0;
          final gain = double.tryParse(filterMatch.group(4) ?? '0') ?? 0.0;
          final q = double.tryParse(filterMatch.group(5) ?? '1.0') ?? 1.0;

          EqBandType bType = EqBandType.peak;
          if (typeStr == 'LSC' || typeStr == 'LS' || typeStr == 'LOWSHELF' || typeStr == 'LOW_SHELF') {
            bType = EqBandType.lowshelf;
          } else if (typeStr == 'HSC' || typeStr == 'HS' || typeStr == 'HIGHSHELF' || typeStr == 'HIGH_SHELF') {
            bType = EqBandType.highshelf;
          } else if (typeStr == 'LP' || typeStr == 'LPF' || typeStr == 'LOWPASS' || typeStr == 'LOW_PASS') {
            bType = EqBandType.lowpass;
          } else if (typeStr == 'HP' || typeStr == 'HPF' || typeStr == 'HIGHPASS' || typeStr == 'HIGH_PASS') {
            bType = EqBandType.highpass;
          } else if (typeStr == 'BP' || typeStr == 'BPF' || typeStr == 'BANDPASS' || typeStr == 'BAND_PASS') {
            bType = EqBandType.bandpass;
          } else if (typeStr == 'NO' || typeStr == 'NOTCH') {
            bType = EqBandType.notch;
          } else if (typeStr == 'TILT') {
            bType = EqBandType.tilt;
          } else if (typeStr == 'AP' || typeStr == 'ALLPASS' || typeStr == 'ALL_PASS') {
            bType = EqBandType.allpass;
          }

          pBands.add(EqBandConfig(
            type: bType,
            frequencyHz: fc,
            gainDb: gain,
            q: q,
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

  /// Evaluates approximate dB response at frequency f for a parametric biquad filter.
  static double evaluateParametricBandDb({
    required EqBandType type,
    required double fc,
    required double gainDb,
    required double q,
    required double f,
  }) {
    if (gainDb == 0.0 && type != EqBandType.notch && type != EqBandType.lowpass && type != EqBandType.highpass) {
      return 0.0;
    }
    if (f <= 0 || fc <= 0) return 0.0;

    double ratio = f / fc;
    if (type == EqBandType.peak || type == EqBandType.bell) {
      // Peaking filter approximation
      double logDist = (math.log(ratio) / math.ln10).abs();
      double bwFactor = 1.0 / (2.0 * math.max(q, 0.1));
      double response = math.exp(-math.pow(logDist / bwFactor, 2));
      return gainDb * response;
    } else if (type == EqBandType.lowshelf) {
      if (f <= fc) {
        return gainDb;
      } else {
        double logDist = (math.log(ratio) / math.ln10);
        double falloff = math.exp(-logDist * 2.0 * math.max(q, 0.2));
        return gainDb * falloff;
      }
    } else if (type == EqBandType.highshelf) {
      if (f >= fc) {
        return gainDb;
      } else {
        double logDist = (math.log(fc / f) / math.ln10);
        double falloff = math.exp(-logDist * 2.0 * math.max(q, 0.2));
        return gainDb * falloff;
      }
    } else if (type == EqBandType.notch) {
      double logDist = (math.log(ratio) / math.ln10).abs();
      double bwFactor = 1.0 / (2.0 * math.max(q, 0.5));
      if (logDist < bwFactor) {
        return -24.0 * (1.0 - (logDist / bwFactor));
      }
      return 0.0;
    }
    return 0.0;
  }
}
