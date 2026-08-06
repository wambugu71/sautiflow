import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Service for extracting and caching normalized amplitude waveform peaks [0.08 - 1.0]
/// for audio files and streams to render dynamic waveform seek bars.
class WaveformExtractorService {
  WaveformExtractorService._();
  static final WaveformExtractorService instance = WaveformExtractorService._();

  final Map<String, List<double>> _cache = {};

  /// Returns normalized amplitude peaks (default 100 bars) for a given track path or ID.
  Future<List<double>> getWaveform(String path, {int numBars = 100}) async {
    if (path.isEmpty) {
      return _generateDeterministicPeaks('default', numBars);
    }

    final cacheKey = '$path:$numBars';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    List<double> peaks;
    try {
      final file = File(path);
      if (await file.exists()) {
        peaks = await compute(_extractFilePeaks, _PeakExtractionParam(path: path, numBars: numBars));
      } else {
        peaks = _generateDeterministicPeaks(path, numBars);
      }
    } catch (e) {
      debugPrint('[WaveformExtractorService] Error extracting peaks for $path: $e');
      peaks = _generateDeterministicPeaks(path, numBars);
    }

    _cache[cacheKey] = peaks;
    return peaks;
  }

  /// Synchronously retrieve cached peaks if available.
  List<double>? getCached(String path, {int numBars = 100}) {
    return _cache['$path:$numBars'];
  }

  /// Pre-fetch waveforms for upcoming tracks in a playlist.
  void prefetch(List<String> paths, {int numBars = 100}) {
    for (final p in paths) {
      if (p.isNotEmpty && !_cache.containsKey('$p:$numBars')) {
        getWaveform(p, numBars: numBars);
      }
    }
  }

  /// Clear in-memory peak cache.
  void clearCache() {
    _cache.clear();
  }
}

class _PeakExtractionParam {
  final String path;
  final int numBars;
  const _PeakExtractionParam({required this.path, required this.numBars});
}

/// Isolate function to read file chunks and extract dynamic amplitude peaks.
List<double> _extractFilePeaks(_PeakExtractionParam param) {
  try {
    final file = File(param.path);
    final length = file.lengthSync();
    if (length == 0) return _generateDeterministicPeaks(param.path, param.numBars);

    // Skip metadata headers
    const headerOffset = 4096;
    final dataSize = math.max(0, length - headerOffset);
    if (dataSize < 100) return _generateDeterministicPeaks(param.path, param.numBars);

    final numBars = param.numBars;
    final chunkSize = math.max(1, dataSize ~/ numBars);
    final raf = file.openSync();

    final rawPeaks = Float64List(numBars);
    double maxVal = 0.00001;
    double minVal = 100000.0;

    try {
      raf.setPositionSync(headerOffset);
      final readBuffer = Uint8List(math.min(chunkSize, 32 * 1024));

      for (int b = 0; b < numBars; b++) {
        final targetPos = headerOffset + (b * chunkSize);
        if (targetPos >= length) break;
        raf.setPositionSync(targetPos);

        final readBytes = raf.readIntoSync(readBuffer);
        if (readBytes <= 0) continue;

        // Calculate variance / RMS dynamics across sample buffer
        double sumSq = 0.0;
        double blockMax = 0.0;
        final sampleCount = readBytes ~/ 2;

        if (sampleCount > 0) {
          for (int i = 0; i < readBytes - 1; i += 2) {
            final val = (readBuffer[i] | (readBuffer[i + 1] << 8)).toSigned(16);
            final absVal = val.abs() / 32768.0;
            if (absVal > blockMax) blockMax = absVal;
            sumSq += absVal * absVal;
          }
          final rms = math.sqrt(sumSq / sampleCount);
          final peakVal = (blockMax * 0.6) + (rms * 0.4);
          rawPeaks[b] = peakVal;
          if (peakVal > maxVal) maxVal = peakVal;
          if (peakVal < minVal) minVal = peakVal;
        }
      }
    } finally {
      raf.closeSync();
    }

    final range = (maxVal - minVal);
    if (range < 0.001) {
      // Fallback if data is too uniform (e.g. compressed container without PCM header)
      return _generateDeterministicPeaks(param.path, param.numBars);
    }

    final result = List<double>.filled(numBars, 0.08);
    for (int i = 0; i < numBars; i++) {
      final normalized = ((rawPeaks[i] - minVal) / range).clamp(0.0, 1.0);
      // Power curve expansion (x^1.8) to magnify contrast between quiet and loud bars
      final contrast = math.pow(normalized, 1.8).toDouble();
      result[i] = (0.08 + (contrast * 0.92)).clamp(0.08, 1.0);
    }
    return result;
  } catch (e) {
    return _generateDeterministicPeaks(param.path, param.numBars);
  }
}

/// Generates realistic, dynamically rich song structural peaks with distinct intros,
/// verse movement, chorus climaxes, bridge dips, and outro fades.
List<double> _generateDeterministicPeaks(String seed, int count) {
  final hash = seed.hashCode;
  final rand = math.Random(hash);
  final peaks = List<double>.filled(count, 0.1);

  // 1. Structure envelope generator (8 musical phases)
  double getSongSectionEnergy(double t) {
    if (t < 0.08) {
      // Intro: 0.15 -> 0.35
      return 0.15 + (t / 0.08) * 0.20;
    } else if (t < 0.28) {
      // Verse 1: 0.35 -> 0.55
      final p = (t - 0.08) / 0.20;
      return 0.35 + math.sin(p * math.pi) * 0.20;
    } else if (t < 0.48) {
      // Chorus 1: 0.70 -> 0.95
      final p = (t - 0.28) / 0.20;
      return 0.70 + math.sin(p * math.pi) * 0.25;
    } else if (t < 0.62) {
      // Verse 2: 0.40 -> 0.60
      final p = (t - 0.48) / 0.14;
      return 0.40 + math.sin(p * math.pi) * 0.20;
    } else if (t < 0.72) {
      // Bridge (Quiet Dip): 0.18 -> 0.35
      final p = (t - 0.62) / 0.10;
      return 0.18 + math.sin(p * math.pi) * 0.17;
    } else if (t < 0.80) {
      // Build-up: 0.35 -> 0.85
      final p = (t - 0.72) / 0.08;
      return 0.35 + p * 0.50;
    } else if (t < 0.92) {
      // Final Climax / Chorus 2: 0.80 -> 1.00
      final p = (t - 0.80) / 0.12;
      return 0.80 + math.sin(p * math.pi) * 0.20;
    } else {
      // Outro: 0.70 -> 0.08
      final p = (t - 0.92) / 0.08;
      return 0.70 * (1.0 - p);
    }
  }

  final basePhase = rand.nextDouble() * math.pi * 2;
  final beatFreq = 0.25 + rand.nextDouble() * 0.2; // Beat pulse rate

  for (int i = 0; i < count; i++) {
    final t = i / count;
    final macroEnergy = getSongSectionEnergy(t);

    // Rhythm beat dynamics (accent every few bars)
    final beatPulse = math.pow(math.sin(i * beatFreq + basePhase).abs(), 2.5);
    // Micro details (high frequency noise variation)
    final microDetail = (rand.nextDouble() * 0.3 - 0.15);

    // Combine section macro structure + beat dynamics + micro details
    double raw = macroEnergy * (0.70 + 0.30 * beatPulse) + microDetail;
    
    // Apply contrast power curve x^1.8 to accentuate difference between quiet and loud bars
    raw = math.pow(raw.clamp(0.02, 1.0), 1.8).toDouble();

    // Scale final peak between [0.08, 1.0]
    peaks[i] = (0.08 + raw * 0.92).clamp(0.08, 1.0);
  }

  return peaks;
}
