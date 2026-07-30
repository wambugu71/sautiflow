import 'dart:io';
import 'dart:math' as math;

/// Parsed AutoEQ Result containing preamp cut and 31-band equalizer values.
class AutoEqResult {
  final String profileName;
  final double preampGainDb;
  final List<double> bandLevels31; // Normalized [0.0..1.0] (0.5 = 0 dB)
  final List<double> bandGainDbs31; // Raw dB values (-12 dB to +12 dB)
  final bool isGraphicEq;

  AutoEqResult({
    required this.profileName,
    required this.preampGainDb,
    required this.bandLevels31,
    required this.bandGainDbs31,
    required this.isGraphicEq,
  });
}

class AutoEqParser {
  static const List<double> iso31CenterFreqs = [
    20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0,
    250.0, 315.0, 400.0, 500.0, 630.0, 800.0, 1000.0, 1250.0, 1600.0, 2000.0,
    2500.0, 3150.0, 4000.0, 5000.0, 6300.0, 8000.0, 10000.0, 12500.0, 16000.0, 20000.0
  ];

  /// Parses an AutoEQ file (.txt, GraphicEQ, or ParametricEQ) by file path.
  static AutoEqResult parseFile(String filePath) {
    final file = File(filePath);
    final content = file.readAsStringSync();
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '')
        : 'AutoEQ Profile';
    return parseContent(content, profileName: name);
  }

  /// Parses AutoEQ text content (GraphicEQ or ParametricEQ string).
  static AutoEqResult parseContent(String content, {String profileName = 'AutoEQ Profile'}) {
    if (content.contains('GraphicEQ:')) {
      return _parseGraphicEq(content, profileName);
    } else {
      return _parseParametricEq(content, profileName);
    }
  }

  /// Parses GraphicEQ string format (e.g. GraphicEQ: 20 0; 25 0.5; 31.5 1.2; ...)
  static AutoEqResult _parseGraphicEq(String content, String profileName) {
    final Map<double, double> gainMap = {};
    double preampDb = 0.0;

    // Check for Preamp line if present before GraphicEQ
    final lines = content.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Preamp:')) {
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
      }
    }

    final List<double> rawDbs = [];
    final List<double> normalized = [];

    for (var centerFreq in iso31CenterFreqs) {
      double gainDb = _interpolateGain(gainMap, centerFreq);
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
    );
  }

  /// Parses EqualizerAPO ParametricEQ format
  /// Format:
  /// Preamp: -4.5 dB
  /// Filter 1: ON PK Fc 31 Hz Gain 2.1 dB Q 1.41
  static AutoEqResult _parseParametricEq(String content, String profileName) {
    double preampDb = 0.0;
    final List<_ParametricFilter> filters = [];

    final lines = content.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('Preamp:')) {
        final match = RegExp(r'Preamp:\s*([+-]?\d+\.?\d*)\s*dB', caseSensitive: false).firstMatch(trimmed);
        if (match != null) {
          preampDb = double.tryParse(match.group(1) ?? '0') ?? 0.0;
        }
      } else if (trimmed.startsWith('Filter')) {
        // e.g. Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.71
        final filterMatch = RegExp(
          r'Filter\s+\d+:\s*(ON|OFF)\s+([A-Z0-9]+)\s+Fc\s+(\d+\.?\d*)\s*Hz\s+Gain\s+([+-]?\d+\.?\d*)\s*dB(?:\s+Q\s+(\d+\.?\d*))?',
          caseSensitive: false,
        ).firstMatch(trimmed);

        if (filterMatch != null) {
          final enabled = filterMatch.group(1)?.toUpperCase() == 'ON';
          if (!enabled) continue;

          final typeStr = filterMatch.group(2)?.toUpperCase() ?? 'PK';
          final fc = double.tryParse(filterMatch.group(3) ?? '1000') ?? 1000.0;
          final gain = double.tryParse(filterMatch.group(4) ?? '0') ?? 0.0;
          final q = double.tryParse(filterMatch.group(5) ?? '1.0') ?? 1.0;

          filters.add(_ParametricFilter(type: typeStr, fc: fc, gainDb: gain, q: q));
        }
      }
    }

    // Evaluate response magnitude across 31 center frequencies
    final List<double> rawDbs = [];
    final List<double> normalized = [];

    for (var f in iso31CenterFreqs) {
      double totalDb = 0.0;
      for (var filter in filters) {
        totalDb += filter.evaluateDbAt(f);
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
    );
  }

  /// Linear interpolation helper for frequency points
  static double _interpolateGain(Map<double, double> gainMap, double targetFreq) {
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
        double ratio = (targetFreq - f1) / (f2 - f1);
        return g1 + ratio * (g2 - g1);
      }
    }
    return 0.0;
  }
}

class _ParametricFilter {
  final String type;
  final double fc;
  final double gainDb;
  final double q;

  _ParametricFilter({
    required this.type,
    required this.fc,
    required this.gainDb,
    required this.q,
  });

  /// Evaluates approximate dB response at frequency f
  double evaluateDbAt(double f) {
    if (gainDb == 0.0) return 0.0;

    double ratio = f / fc;
    if (type == 'PK' || type == 'PEAK') {
      // Peaking filter approximation
      double logDist = (math.log(ratio) / math.ln10).abs();
      double bwFactor = 1.0 / (2.0 * math.max(q, 0.1));
      double response = math.exp(-math.pow(logDist / bwFactor, 2));
      return gainDb * response;
    } else if (type == 'LSC' || type == 'LS') {
      // Low shelf
      if (f <= fc) {
        return gainDb;
      } else {
        double logDist = (math.log(ratio) / math.ln10);
        double falloff = math.exp(-logDist * 2.0 * q);
        return gainDb * falloff;
      }
    } else if (type == 'HSC' || type == 'HS') {
      // High shelf
      if (f >= fc) {
        return gainDb;
      } else {
        double logDist = (math.log(fc / f) / math.ln10);
        double falloff = math.exp(-logDist * 2.0 * q);
        return gainDb * falloff;
      }
    }
    return 0.0;
  }
}
