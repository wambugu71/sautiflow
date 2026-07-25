import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sautiflow/sautiflow.dart';

/// Comprehensive snapshot of active output audio hardware specifications.
class AudioHardwareSpecs {
  final String backendName; // e.g. "WASAPI", "AAudio", "ALSA", "PulseAudio", "Core Audio"
  final String deviceName; // Friendly device name string
  final int sampleRate; // Hardware sample rate in Hz (e.g. 48000, 96000)
  final int bitDepth; // Hardware bit depth in bits (e.g. 16, 24, 32)
  final bool isFloat; // True if 32-bit Floating point PCM
  final int channels; // Channel count (1=Mono, 2=Stereo)
  final int periodSizeFrames; // Frame count per period
  final int periodCount; // Total periods
  final double latencyMs; // Hardware buffer latency in milliseconds
  final bool isExclusiveMode; // True if exclusive mode (Bit-Perfect)
  final String deviceType; // "Speakers", "3.5mm Headphone Jack", "Bluetooth", "USB DAC", "AirPlay"
  final String? bluetoothCodec; // e.g. "LDAC", "aptX HD", "AAC", "SBC", "LC3"

  const AudioHardwareSpecs({
    required this.backendName,
    required this.deviceName,
    required this.sampleRate,
    required this.bitDepth,
    required this.isFloat,
    required this.channels,
    required this.periodSizeFrames,
    required this.periodCount,
    required this.latencyMs,
    required this.isExclusiveMode,
    required this.deviceType,
    this.bluetoothCodec,
  });

  /// Factory constructor to construct specs from miniaudio native hardware info
  factory AudioHardwareSpecs.fromNative(AEHardwareInfo native) {
    String devType = 'Speakers / Output Device';
    final lowerName = native.deviceName.toLowerCase();

    if (lowerName.contains('bluetooth') || lowerName.contains('wh-') || lowerName.contains('airpods') || lowerName.contains('buds')) {
      devType = 'Bluetooth Wireless';
    } else if (lowerName.contains('dac') || lowerName.contains('dragonfly') || lowerName.contains('usb') || lowerName.contains('fiio')) {
      devType = 'USB DAC';
    } else if (lowerName.contains('headphone') || lowerName.contains('jack') || lowerName.contains('headset')) {
      devType = '3.5mm Headphone Jack';
    } else if (lowerName.contains('airplay')) {
      devType = 'AirPlay Stream';
    }

    return AudioHardwareSpecs(
      backendName: native.backendName.isNotEmpty ? native.backendName : 'Audio Backend',
      deviceName: native.deviceName.isNotEmpty ? native.deviceName : 'Default Soundcard',
      sampleRate: native.sampleRate > 0 ? native.sampleRate : 48000,
      bitDepth: native.bitDepth > 0 ? native.bitDepth : 32,
      isFloat: native.isFloat,
      channels: native.channels > 0 ? native.channels : 2,
      periodSizeFrames: native.periodSizeFrames,
      periodCount: native.periodCount,
      latencyMs: native.latencyMs,
      isExclusiveMode: native.isExclusiveMode,
      deviceType: devType,
    );
  }

  /// True if device hardware supports High-Resolution Audio (>48kHz or >16-bit or USB DAC)
  bool get isHiResAudio => sampleRate > 48000 || bitDepth > 16 || deviceType == 'USB DAC';

  /// Human-readable sample rate string (e.g., "96.0 kHz (Hi-Res)")
  String get formattedSampleRate {
    final kHz = (sampleRate / 1000.0).toStringAsFixed(1);
    if (isHiResAudio) {
      return '$kHz kHz (Hi-Res)';
    }
    return '$kHz kHz';
  }

  /// Human-readable bit depth string (e.g., "24-bit Signed PCM" or "32-bit Float")
  String get formattedBitDepth {
    if (isFloat) return '$bitDepth-bit Float PCM';
    return '$bitDepth-bit Int PCM';
  }

  /// Human-readable latency string (e.g., "10.67 ms")
  String get formattedLatency => '${latencyMs.toStringAsFixed(2)} ms';

  /// Json map representation
  Map<String, dynamic> toJson() => {
        'backendName': backendName,
        'deviceName': deviceName,
        'sampleRate': sampleRate,
        'formattedSampleRate': formattedSampleRate,
        'bitDepth': bitDepth,
        'formattedBitDepth': formattedBitDepth,
        'isFloat': isFloat,
        'channels': channels,
        'periodSizeFrames': periodSizeFrames,
        'periodCount': periodCount,
        'latencyMs': latencyMs,
        'formattedLatency': formattedLatency,
        'isExclusiveMode': isExclusiveMode,
        'deviceType': deviceType,
        'bluetoothCodec': bluetoothCodec,
        'isHiResAudio': isHiResAudio,
      };
}

/// Service to inspect active hardware audio specifications and device routes
class AudioHardwareInspector {
  static const MethodChannel _channel = MethodChannel('com.wambugu.sautiflow/hardware');

  static AudioHardwareSpecs inspect(dynamic player) {
    final nativeInfo = player.getHardwareInfo();
    if (nativeInfo is AEHardwareInfo) {
      return AudioHardwareSpecs.fromNative(nativeInfo);
    }
    return const AudioHardwareSpecs(
      backendName: 'Audio Backend',
      deviceName: 'Default Soundcard',
      sampleRate: 48000,
      bitDepth: 32,
      isFloat: true,
      channels: 2,
      periodSizeFrames: 0,
      periodCount: 0,
      latencyMs: 0.0,
      isExclusiveMode: false,
      deviceType: 'Speakers / Output Device',
    );
  }

  static Future<AudioHardwareSpecs> inspectAsync(dynamic player) async {
    if (Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod('getHardwareAudioSpecs');
        if (res is Map) {
          final rawNative = await player.getHardwareInfo();
          final AEHardwareInfo hwInfo = (rawNative is AEHardwareInfo)
              ? rawNative
              : const AEHardwareInfo(
                  backendName: 'AAudio',
                  deviceName: 'Default Output Device',
                  outputFormat: AudioFormat.f32,
                  bitDepth: 32,
                  isFloat: true,
                  sampleRate: 48000,
                  channels: 2,
                  periodSizeFrames: 0,
                  periodCount: 0,
                  latencyMs: 0.0,
                  isExclusiveMode: false,
                );
          final String devName = res['deviceName']?.toString() ?? hwInfo.deviceName;
          final int sRate = (res['sampleRate'] as num?)?.toInt() ?? hwInfo.sampleRate;
          final int bDepth = (res['bitDepth'] as num?)?.toInt() ?? hwInfo.bitDepth;
          final bool isFl = (res['isFloat'] as bool?) ?? hwInfo.isFloat;
          final String devType = res['deviceType']?.toString() ?? 'Speakers / Output Device';
          final double latMs = (res['latencyMs'] as num?)?.toDouble() ?? hwInfo.latencyMs;

          return AudioHardwareSpecs(
            backendName: 'AAudio / Android HAL',
            deviceName: devName.isNotEmpty ? devName : 'Default Soundcard',
            sampleRate: sRate > 0 ? sRate : 48000,
            bitDepth: bDepth > 0 ? bDepth : 32,
            isFloat: isFl,
            channels: 2,
            periodSizeFrames: (res['periodSizeFrames'] as num?)?.toInt() ?? hwInfo.periodSizeFrames,
            periodCount: 2,
            latencyMs: latMs,
            isExclusiveMode: false,
            deviceType: devType,
          );
        }
      } catch (_) {
        // Fallback
      }
    }
    final rawNative = await player.getHardwareInfo();
    if (rawNative is AEHardwareInfo) {
      return AudioHardwareSpecs.fromNative(rawNative);
    }
    return const AudioHardwareSpecs(
      backendName: 'Audio Backend',
      deviceName: 'Default Soundcard',
      sampleRate: 48000,
      bitDepth: 32,
      isFloat: true,
      channels: 2,
      periodSizeFrames: 0,
      periodCount: 0,
      latencyMs: 0.0,
      isExclusiveMode: false,
      deviceType: 'Speakers / Output Device',
    );
  }
}
