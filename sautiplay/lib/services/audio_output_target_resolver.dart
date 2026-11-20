import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';

/// Resolved output target for the audio engine based on user settings,
/// active track sample rate, and monitored hardware/Bluetooth capabilities.
class ResolvedOutputTarget {
  /// Target output sample rate in Hz (`0` = let engine follow track native rate).
  final int sampleRateHz;

  /// Target PCM output format (`f32`, `s16`, `s24`, `s32`).
  final AudioFormat format;

  /// Human-readable reason explaining how this target was chosen.
  final String reason;

  /// True when the user explicitly locked the sample rate in Settings.
  final bool isUserOverride;

  const ResolvedOutputTarget({
    required this.sampleRateHz,
    required this.format,
    required this.reason,
    required this.isUserOverride,
  });

  @override
  bool operator ==(Object other) =>
      other is ResolvedOutputTarget &&
      other.sampleRateHz == sampleRateHz &&
      other.format == format &&
      other.isUserOverride == isUserOverride;

  @override
  int get hashCode => Object.hash(sampleRateHz, format, isUserOverride);
}

/// Pure resolver that maps `(user settings, hardware/BT specs, track SR)` into
/// the exact sample rate and bit depth the engine should open.
///
/// Precedence:
/// 1. User explicit sample rate in Settings (`userSampleRateHz > 0`) always wins.
/// 2. Bluetooth A2DP / LE Audio: match the negotiated BT codec sample rate and
///    bit depth (e.g. SBC 16/44.1, AAC 16/44.1 or 48, aptX HD 24/48, LDAC 24/96)
///    so Android AudioFlinger does not perform a hidden secondary resample.
/// 3. USB DAC: match the track's native rate when supported by the DAC (zero SRC),
///    otherwise pick the best supported rate (integer multiple preferred, up to
///    24/192 or 32/384) and the DAC's native integer bit depth.
/// 4. Built-in / Wired output: match track rate if supported, else HAL native rate.
abstract final class AudioOutputTargetResolver {
  static AudioFormat formatForBitDepth(int bits, {bool preferFloat = false}) {
    if (preferFloat && bits >= 32) return AudioFormat.f32;
    if (bits >= 32) return AudioFormat.s32;
    if (bits >= 24) return AudioFormat.s24;
    if (bits <= 8) return AudioFormat.u8;
    return AudioFormat.s16;
  }

  static ResolvedOutputTarget resolve({
    required AudioHardwareSpecs specs,
    required int userSampleRateHz,
    required AudioFormat userFormat,
    int? sourceSampleRateHz,
  }) {
    // 1. User explicit sample rate in Settings (clamped strictly to real hardware capability if known)
    if (userSampleRateHz > 0) {
      if (specs.isFixedClock && !specs.directMultiRate && specs.sampleRate > 0) {
        if (userSampleRateHz == specs.sampleRate) {
          return ResolvedOutputTarget(
            sampleRateHz: userSampleRateHz,
            format: userFormat,
            reason: 'User target (${(userSampleRateHz / 1000.0).toStringAsFixed(1)} kHz)',
            isUserOverride: true,
          );
        }
        return ResolvedOutputTarget(
          sampleRateHz: specs.sampleRate,
          format: userFormat,
          reason:
              'User target clamped to device capability (${(specs.sampleRate / 1000.0).toStringAsFixed(1)} kHz)',
          isUserOverride: true,
        );
      }
      if (specs.supportedSampleRates.isNotEmpty) {
        if (specs.supportedSampleRates.contains(userSampleRateHz)) {
          return ResolvedOutputTarget(
            sampleRateHz: userSampleRateHz,
            format: userFormat,
            reason: 'User target (${(userSampleRateHz / 1000.0).toStringAsFixed(1)} kHz)',
            isUserOverride: true,
          );
        }
        final clamped = _pickBestSupportedRate(
          userSampleRateHz,
          specs.supportedSampleRates,
        );
        return ResolvedOutputTarget(
          sampleRateHz: clamped,
          format: userFormat,
          reason:
              'User target clamped to DAC capability (${(clamped / 1000.0).toStringAsFixed(1)} kHz)',
          isUserOverride: true,
        );
      }
      return ResolvedOutputTarget(
        sampleRateHz: userSampleRateHz,
        format: userFormat,
        reason: 'User override (${(userSampleRateHz / 1000.0).toStringAsFixed(1)} kHz)',
        isUserOverride: true,
      );
    }

    // 2. Bluetooth: match negotiated codec sample rate & bit depth
    if (specs.isBluetooth) {
      final int btRate = (specs.btSampleRate != null && specs.btSampleRate! > 0)
          ? specs.btSampleRate!
          : (specs.sampleRate > 0 ? specs.sampleRate : 0);
      final int btBits = (specs.btBitDepth != null && specs.btBitDepth! > 0)
          ? specs.btBitDepth!
          : (specs.bitDepth > 0 ? specs.bitDepth : 16);
      final codec = specs.bluetoothCodec ?? 'Bluetooth';
      return ResolvedOutputTarget(
        sampleRateHz: btRate,
        format: formatForBitDepth(btBits, preferFloat: false),
        reason: btRate > 0
            ? '$codec codec match ($btBits-bit / ${(btRate / 1000.0).toStringAsFixed(1)} kHz)'
            : '$codec codec match ($btBits-bit)',
        isUserOverride: false,
      );
    }

    // 3. USB DAC: zero-SRC native match when supported, else best DAC rate + bit depth
    if (specs.isUsbDac) {
      final supportedRates = specs.supportedSampleRates;
      final supportedBits = specs.supportedBitDepths;
      final int bestBits = supportedBits.isNotEmpty
          ? supportedBits.reduce((a, b) => a > b ? a : b)
          : (specs.bitDepth > 0 ? specs.bitDepth : 24);
      final fmt = formatForBitDepth(bestBits, preferFloat: false);

      if (sourceSampleRateHz != null && sourceSampleRateHz > 0) {
        if (supportedRates.contains(sourceSampleRateHz)) {
          return ResolvedOutputTarget(
            sampleRateHz: sourceSampleRateHz,
            format: fmt,
            reason: 'USB DAC native match (${(sourceSampleRateHz / 1000.0).toStringAsFixed(1)} kHz)',
            isUserOverride: false,
          );
        }
        if (supportedRates.isNotEmpty) {
          final picked = _pickBestSupportedRate(sourceSampleRateHz, supportedRates);
          return ResolvedOutputTarget(
            sampleRateHz: picked,
            format: fmt,
            reason: 'USB DAC best supported (${(picked / 1000.0).toStringAsFixed(1)} kHz)',
            isUserOverride: false,
          );
        }
      }

      // Let engine auto-match track rate + DAC capability without forcing max rate
      return ResolvedOutputTarget(
        sampleRateHz: 0,
        format: fmt,
        reason: 'USB DAC capability ($bestBits-bit)',
        isUserOverride: false,
      );
    }

    // 4. Built-in / Wired / Desktop output
    if (specs.isFixedClock && !specs.directMultiRate) {
      final int halRate = specs.sampleRate;
      if (halRate <= 0) {
        return ResolvedOutputTarget(
          sampleRateHz: 0,
          format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
          reason: 'HAL native auto',
          isUserOverride: false,
        );
      }
      final bool matched =
          sourceSampleRateHz != null && sourceSampleRateHz == halRate;
      return ResolvedOutputTarget(
        sampleRateHz: halRate,
        format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
        reason: matched
            ? 'Fixed-clock HAL native match (${(halRate / 1000.0).toStringAsFixed(1)} kHz)'
            : 'Fixed-clock HAL (${(halRate / 1000.0).toStringAsFixed(1)} kHz · engine SRC)',
        isUserOverride: false,
      );
    }

    if (specs.directMultiRate &&
        specs.supportedSampleRates.isNotEmpty &&
        sourceSampleRateHz != null &&
        sourceSampleRateHz > 0) {
      final int picked = specs.supportedSampleRates.contains(sourceSampleRateHz)
          ? sourceSampleRateHz
          : _pickBestSupportedRate(
              sourceSampleRateHz,
              specs.supportedSampleRates,
            );
      final bool matched = picked == sourceSampleRateHz;
      return ResolvedOutputTarget(
        sampleRateHz: picked,
        format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
        reason: matched
            ? 'Hardware native match (${(picked / 1000.0).toStringAsFixed(1)} kHz)'
            : 'Hardware best supported (${(picked / 1000.0).toStringAsFixed(1)} kHz)',
        isUserOverride: false,
      );
    }

    if (sourceSampleRateHz != null &&
        sourceSampleRateHz > 0 &&
        specs.supportedSampleRates.contains(sourceSampleRateHz)) {
      return ResolvedOutputTarget(
        sampleRateHz: sourceSampleRateHz,
        format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
        reason: 'Hardware native match (${(sourceSampleRateHz / 1000.0).toStringAsFixed(1)} kHz)',
        isUserOverride: false,
      );
    }

    if (sourceSampleRateHz == null || sourceSampleRateHz <= 0) {
      return ResolvedOutputTarget(
        sampleRateHz: 0,
        format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
        reason: 'HAL native auto',
        isUserOverride: false,
      );
    }

    final int halRate = specs.sampleRate > 0 ? specs.sampleRate : 0;
    return ResolvedOutputTarget(
      sampleRateHz: halRate,
      format: formatForBitDepth(specs.bitDepth, preferFloat: specs.isFloat),
      reason: halRate > 0
          ? 'HAL native (${(halRate / 1000.0).toStringAsFixed(1)} kHz)'
          : 'HAL native auto',
      isUserOverride: false,
    );
  }

  static int _pickBestSupportedRate(int sourceRate, List<int> supportedRates) {
    final sorted = List<int>.from(supportedRates)..sort();
    // 1. Prefer smallest integer upsampling multiple (e.g. 44.1 -> 88.2 / 176.4)
    for (final r in sorted) {
      if (r >= sourceRate && r % sourceRate == 0) {
        return r;
      }
    }
    // 2. Otherwise smallest supported rate >= sourceRate
    for (final r in sorted) {
      if (r >= sourceRate) {
        return r;
      }
    }
    // 3. Otherwise highest supported rate
    return sorted.last;
  }
}
