import 'dart:math' as math;
import 'package:sautiflow/audio_engine_ffi.dart';

/// Harmonic compatibility relationship between two Camelot keys.
enum CamelotHarmonicRelation {
  exactMatch,      // e.g. 8A -> 8A (100% harmonically identical)
  relativePair,    // e.g. 8A -> 8B (same scale notes, relative major/minor)
  subdominant,     // e.g. 8A -> 7A (4th / subdominant modulation)
  dominant,        // e.g. 8A -> 9A (5th / dominant modulation)
  energyBoost,     // e.g. 8A -> 3A (+1 semitone or +7 hours)
  nearMiss,        // e.g. 1 semitone apart, pitch-shiftable by ±1 semitone
  incompatible,    // Requires cut transition or large modulation
}

/// Analysis metadata representing a track's rhythmic and harmonic profile.
class TrackAutomixInfo {
  final String uri;
  final double bpm;
  final String musicalKey; // e.g. "Am", "C"
  final String camelotKey; // e.g. "8A", "8B"
  final double introEndSeconds;
  final double outroStartSeconds;

  const TrackAutomixInfo({
    required this.uri,
    required this.bpm,
    required this.musicalKey,
    required this.camelotKey,
    required this.introEndSeconds,
    required this.outroStartSeconds,
  });

  factory TrackAutomixInfo.fallback(String uri, double durationSec) {
    return TrackAutomixInfo(
      uri: uri,
      bpm: 120.0,
      musicalKey: 'C',
      camelotKey: '8B',
      introEndSeconds: math.min(16.0, durationSec * 0.1),
      outroStartSeconds: math.max(durationSec - 32.0, durationSec * 0.85),
    );
  }
}

/// Service providing Camelot Wheel harmonic mixing rules, key conversion,
/// and Auto DJ playlist sequencing algorithms.
class AutomixAnalysisService {
  AutomixAnalysisService._();
  static final AutomixAnalysisService instance = AutomixAnalysisService._();

  static const Map<String, String> _kKeyToCamelot = {
    // Minor keys (A)
    'abm': '1A', 'g#m': '1A', 'g# min': '1A',
    'ebm': '2A', 'd#m': '2A', 'd# min': '2A',
    'bbm': '3A', 'a#m': '3A', 'a# min': '3A',
    'fm': '4A', 'f min': '4A',
    'cm': '5A', 'c min': '5A',
    'gm': '6A', 'g min': '6A',
    'dm': '7A', 'd min': '7A',
    'am': '8A', 'a min': '8A',
    'em': '9A', 'e min': '9A',
    'bm': '10A', 'b min': '10A',
    'f#m': '11A', 'f# min': '11A', 'gbm': '11A',
    'c#m': '12A', 'c# min': '12A', 'dbm': '12A',

    // Major keys (B)
    'b': '1B', 'b maj': '1B', 'cb': '1B',
    'f#': '2B', 'f# maj': '2B', 'gb': '2B',
    'db': '3B', 'db maj': '3B', 'c#': '3B',
    'ab': '4B', 'ab maj': '4B', 'g#': '4B',
    'eb': '5B', 'eb maj': '5B', 'd#': '5B',
    'bb': '6B', 'bb maj': '6B', 'a#': '6B',
    'f': '7B', 'f maj': '7B',
    'c': '8B', 'c maj': '8B',
    'g': '9B', 'g maj': '9B',
    'd': '10B', 'd maj': '10B',
    'a': '11B', 'a maj': '11B',
    'e': '12B', 'e maj': '12B',
  };

  /// Parses a musical key tag (e.g. "Am", "8A", "C# minor") to a standardized Camelot code ("8A").
  String parseCamelotKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '8B';
    final clean = raw.trim().toUpperCase();

    // Direct Camelot format (e.g. "8A", "11B")
    final match = RegExp(r'^([1-9]|1[0-2])([AB])$').firstMatch(clean);
    if (match != null) {
      return clean;
    }

    final lower = raw.trim().toLowerCase().replaceAll('major', 'maj').replaceAll('minor', 'min');
    return _kKeyToCamelot[lower] ?? '8B';
  }

  /// Determines the harmonic relationship between two Camelot keys.
  CamelotHarmonicRelation getHarmonicRelation(String keyA, String keyB) {
    if (keyA == keyB) return CamelotHarmonicRelation.exactMatch;

    final numA = int.tryParse(keyA.replaceAll(RegExp(r'[^0-9]'), '')) ?? 8;
    final numB = int.tryParse(keyB.replaceAll(RegExp(r'[^0-9]'), '')) ?? 8;
    final letterA = keyA.endsWith('B') ? 'B' : 'A';
    final letterB = keyB.endsWith('B') ? 'B' : 'A';

    // Relative Major / Minor (same number, different letter)
    if (numA == numB && letterA != letterB) {
      return CamelotHarmonicRelation.relativePair;
    }

    if (letterA == letterB) {
      // 1 hour counter-clockwise = subdominant (4th)
      final sub = (numA == 1) ? 12 : numA - 1;
      if (numB == sub) return CamelotHarmonicRelation.subdominant;

      // 1 hour clockwise = dominant (5th)
      final dom = (numA == 12) ? 1 : numA + 1;
      if (numB == dom) return CamelotHarmonicRelation.dominant;

      // Energy boost modulation (+7 hours on wheel = +1 semitone)
      final boost = ((numA + 7 - 1) % 12) + 1;
      if (numB == boost) return CamelotHarmonicRelation.energyBoost;
    }

    // Diagonal wheel modulation (e.g. 8A -> 9B or 8A -> 7B)
    final diff = (numA - numB).abs();
    if (diff == 1 || diff == 11) {
      return CamelotHarmonicRelation.nearMiss;
    }

    return CamelotHarmonicRelation.incompatible;
  }

  /// Calculates a harmonic compatibility score [0.0 - 1.0] for transition planning.
  double getHarmonicScore(String keyA, String keyB) {
    switch (getHarmonicRelation(keyA, keyB)) {
      case CamelotHarmonicRelation.exactMatch:
        return 1.0;
      case CamelotHarmonicRelation.relativePair:
        return 0.95;
      case CamelotHarmonicRelation.subdominant:
      case CamelotHarmonicRelation.dominant:
        return 0.90;
      case CamelotHarmonicRelation.energyBoost:
        return 0.85;
      case CamelotHarmonicRelation.nearMiss:
        return 0.70;
      case CamelotHarmonicRelation.incompatible:
        return 0.20;
    }
  }

  /// Re-orders an input playlist for optimal Auto DJ sequencing by
  /// minimizing BPM variance and maximizing harmonic Camelot transitions.
  List<TrackAutomixInfo> optimizePlaylistOrder(List<TrackAutomixInfo> tracks) {
    if (tracks.length <= 2) return List.from(tracks);

    final unvisited = List<TrackAutomixInfo>.from(tracks);
    final result = <TrackAutomixInfo>[unvisited.removeAt(0)];

    while (unvisited.isNotEmpty) {
      final current = result.last;
      int bestIdx = 0;
      double highestScore = -1.0;

      for (int i = 0; i < unvisited.length; i++) {
        final candidate = unvisited[i];
        final harmonicScore = getHarmonicScore(current.camelotKey, candidate.camelotKey);

        // BPM proximity factor (penalize large tempo jumps)
        final bpmRatio = candidate.bpm > 0 ? (current.bpm / candidate.bpm) : 1.0;
        final bpmDelta = (1.0 - bpmRatio).abs();
        final bpmScore = math.max(0.0, 1.0 - (bpmDelta * 5.0));

        // Combined fitness function: 60% harmonic harmony, 40% tempo continuity
        final totalScore = (harmonicScore * 0.60) + (bpmScore * 0.40);

        if (totalScore > highestScore) {
          highestScore = totalScore;
          bestIdx = i;
        }
      }

      result.add(unvisited.removeAt(bestIdx));
    }

    return result;
  }

  /// Automatically recommends the optimal transition style between two tracks
  /// based on Camelot harmonic compatibility and tempo difference.
  AutomixStyle recommendTransitionStyle(TrackAutomixInfo fromTrack, TrackAutomixInfo toTrack) {
    final relation = getHarmonicRelation(fromTrack.camelotKey, toTrack.camelotKey);
    final bpmRatio = toTrack.bpm > 0 ? (fromTrack.bpm / toTrack.bpm) : 1.0;
    final bpmDelta = (1.0 - bpmRatio).abs();

    // Large tempo jump or harmonic clash -> Drop Cut or Filter Sweep
    if (bpmDelta > 0.15 || relation == CamelotHarmonicRelation.incompatible) {
      return AutomixStyle.dropCut;
    }
    // High compatibility -> Multi-stage Smart Hybrid (HPF/LPF sweep + LR4 bass swap)
    if (relation == CamelotHarmonicRelation.exactMatch ||
        relation == CamelotHarmonicRelation.relativePair ||
        relation == CamelotHarmonicRelation.dominant ||
        relation == CamelotHarmonicRelation.subdominant) {
      return AutomixStyle.smartHybrid;
    }
    // Moderate modulation -> Resonant Filter Sweep
    return AutomixStyle.filterSweep;
  }
}
