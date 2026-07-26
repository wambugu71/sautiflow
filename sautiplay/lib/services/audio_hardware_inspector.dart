import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sautiflow/sautiflow.dart';

// ── Data Model ────────────────────────────────────────────────────────────────

/// Comprehensive snapshot of active output audio hardware specifications.
class AudioHardwareSpecs {
  final String backendName; // e.g. "WASAPI", "AAudio", "ALSA", "Core Audio"
  final String deviceName; // Friendly device name string
  final int sampleRate; // Hardware sample rate in Hz (e.g. 48000, 96000)
  final int bitDepth; // Hardware bit depth in bits (e.g. 16, 24, 32)
  final bool isFloat; // True if 32-bit Floating point PCM
  final int channels; // Channel count (1=Mono, 2=Stereo)
  final int periodSizeFrames; // Frame count per period
  final int periodCount; // Total periods
  final double latencyMs; // Hardware buffer latency in milliseconds
  final bool isExclusiveMode; // True if exclusive mode (Bit-Perfect)
  final String deviceType; // "Speakers", "3.5mm Headphone Jack", "Bluetooth", "USB DAC"

  // ── Bluetooth-specific fields ─────────────────────────────────────────────
  final String? bluetoothCodec; // e.g. "LDAC", "aptX HD", "AAC", "SBC", "LC3"
  final String? bluetoothDeviceName; // Actual BT device name (e.g. "Sony WH-1000XM5")
  final int? btSampleRate; // BT codec negotiated sample rate (may differ from HW rate)
  final int? btBitDepth; // BT codec bit depth

  // ── System info ───────────────────────────────────────────────────────────
  final int? androidVersion; // Android SDK version (for display)
  final String? androidRelease; // Android version string (e.g. "14")

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
    this.bluetoothDeviceName,
    this.btSampleRate,
    this.btBitDepth,
    this.androidVersion,
    this.androidRelease,
  });

  /// Factory: build from the Map pushed by the Android EventChannel / MethodChannel.
  factory AudioHardwareSpecs.fromAndroidMap(Map<dynamic, dynamic> m) {
    final rawDevType = m['deviceType']?.toString() ?? 'Speakers / Output Device';
    return AudioHardwareSpecs(
      backendName: 'AAudio / Android HAL',
      deviceName: (m['deviceName']?.toString() ?? '').isNotEmpty
          ? m['deviceName'].toString()
          : 'Default Output Device',
      sampleRate: (m['sampleRate'] as num?)?.toInt() ?? 48000,
      bitDepth: (m['bitDepth'] as num?)?.toInt() ?? 32,
      isFloat: (m['isFloat'] as bool?) ?? true,
      channels: (m['channels'] as num?)?.toInt() ?? 2,
      periodSizeFrames: (m['periodSizeFrames'] as num?)?.toInt() ?? 0,
      periodCount: (m['periodCount'] as num?)?.toInt() ?? 2,
      latencyMs: (m['latencyMs'] as num?)?.toDouble() ?? 0.0,
      isExclusiveMode: false, // Not exposed on Android
      deviceType: rawDevType,
      bluetoothCodec: m['bluetoothCodec']?.toString(),
      bluetoothDeviceName: m['bluetoothDeviceName']?.toString(),
      btSampleRate: (m['btSampleRate'] as num?)?.toInt(),
      btBitDepth: (m['btBitDepth'] as num?)?.toInt(),
      androidVersion: (m['androidVersion'] as num?)?.toInt(),
      androidRelease: m['androidRelease']?.toString(),
    );
  }

  /// Factory: build from the native miniaudio AEHardwareInfo (Desktop / iOS).
  factory AudioHardwareSpecs.fromNative(AEHardwareInfo native) {
    String devType = 'Speakers / Output Device';
    final lowerName = native.deviceName.toLowerCase();

    if (lowerName.contains('bluetooth') ||
        lowerName.contains('wh-') ||
        lowerName.contains('airpods') ||
        lowerName.contains('buds')) {
      devType = 'Bluetooth Wireless';
    } else if (lowerName.contains('dac') ||
        lowerName.contains('dragonfly') ||
        lowerName.contains('usb') ||
        lowerName.contains('fiio')) {
      devType = 'USB DAC';
    } else if (lowerName.contains('headphone') ||
        lowerName.contains('jack') ||
        lowerName.contains('headset')) {
      devType = '3.5mm Headphone Jack';
    } else if (lowerName.contains('airplay')) {
      devType = 'AirPlay Stream';
    }

    return AudioHardwareSpecs(
      backendName:
          native.backendName.isNotEmpty ? native.backendName : 'Audio Backend',
      deviceName:
          native.deviceName.isNotEmpty ? native.deviceName : 'Default Soundcard',
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

  // ── Computed properties ───────────────────────────────────────────────────

  /// True if device hardware supports Hi-Res Audio (>48kHz or >16-bit or USB DAC)
  bool get isHiResAudio => sampleRate > 48000 || bitDepth > 16 || deviceType == 'USB DAC';

  /// True if Bluetooth is the active output route
  bool get isBluetooth =>
      deviceType.contains('Bluetooth') ||
      deviceType.contains('bluetooth') ||
      bluetoothCodec != null;

  /// Human-readable sample rate string (e.g., "96.0 kHz (Hi-Res)")
  String get formattedSampleRate {
    final kHz = (sampleRate / 1000.0).toStringAsFixed(1);
    return isHiResAudio ? '$kHz kHz (Hi-Res)' : '$kHz kHz';
  }

  /// Human-readable bit depth string (e.g., "24-bit Signed PCM" or "32-bit Float")
  String get formattedBitDepth {
    if (isFloat) return '$bitDepth-bit Float PCM';
    return '$bitDepth-bit Int PCM';
  }

  /// Human-readable latency string (e.g., "10.67 ms")
  String get formattedLatency => '${latencyMs.toStringAsFixed(2)} ms';

  /// Bluetooth codec + quality string, e.g. "LDAC 96kHz / 24-bit"
  String? get formattedBtCodec {
    if (bluetoothCodec == null) return null;
    final codec = bluetoothCodec!;
    if (btSampleRate != null && btBitDepth != null) {
      final kHz = (btSampleRate! / 1000.0).toStringAsFixed(btSampleRate! % 1000 == 0 ? 0 : 1);
      return '$codec ${kHz}kHz / $btBitDepth-bit';
    }
    return codec;
  }

  /// Poweramp-style signal chain string.
  /// Example (BT): "FLAC → AAudio → Bluetooth → LDAC 96kHz/24-bit → Sony WH-1000XM5"
  /// Example (wired): "AAudio → Android 14 HAL → 3.5mm Headphone → [Device Name]"
  /// Example (desktop): "WASAPI Exclusive → USB DAC → FiiO K3"
  List<SignalChainNode> get signalChain {
    final nodes = <SignalChainNode>[];

    // 1. Audio backend
    if (isExclusiveMode) {
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: 'Exclusive / Bit-Perfect',
        icon: SignalChainIcon.backend,
        isHighlight: true,
      ));
    } else {
      final osLabel = androidRelease != null ? 'Android $androidRelease HAL' : null;
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: osLabel ?? 'Shared Mixer',
        icon: SignalChainIcon.backend,
      ));
    }

    // 2. Route / connection type
    if (isBluetooth) {
      final codecStr = formattedBtCodec ?? 'SBC';
      nodes.add(SignalChainNode(
        label: deviceType,
        sublabel: codecStr,
        icon: SignalChainIcon.bluetooth,
        isHighlight: bluetoothCodec == 'LDAC' ||
            bluetoothCodec == 'aptX HD' ||
            bluetoothCodec == 'LC3',
      ));
    } else {
      nodes.add(SignalChainNode(
        label: deviceType,
        sublabel: '$sampleRate Hz / $bitDepth-bit',
        icon: _iconForDeviceType(deviceType),
        isHighlight: isHiResAudio,
      ));
    }

    // 3. Output device / DAC
    final effectiveDeviceName =
        (bluetoothDeviceName?.isNotEmpty ?? false)
            ? bluetoothDeviceName!
            : deviceName;
    nodes.add(SignalChainNode(
      label: effectiveDeviceName,
      sublabel: isBluetooth
          ? (btSampleRate != null
              ? '${(btSampleRate! / 1000.0).toStringAsFixed(0)}kHz · ${btBitDepth ?? 16}-bit out'
              : 'Output Device')
          : (isHiResAudio ? 'Hi-Res Output' : 'Output Device'),
      icon: SignalChainIcon.output,
    ));

    return nodes;
  }

  SignalChainIcon _iconForDeviceType(String type) {
    if (type.contains('USB')) return SignalChainIcon.usbDac;
    if (type.contains('3.5mm') || type.contains('Headphone')) return SignalChainIcon.wiredHeadphone;
    if (type.contains('HDMI')) return SignalChainIcon.hdmi;
    if (type.contains('Speaker')) return SignalChainIcon.speaker;
    return SignalChainIcon.output;
  }

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
        'bluetoothDeviceName': bluetoothDeviceName,
        'btSampleRate': btSampleRate,
        'btBitDepth': btBitDepth,
        'isHiResAudio': isHiResAudio,
      };
}

// ── Signal Chain Model ────────────────────────────────────────────────────────

enum SignalChainIcon {
  backend,
  bluetooth,
  wiredHeadphone,
  usbDac,
  speaker,
  hdmi,
  output,
}

class SignalChainNode {
  final String label;
  final String? sublabel;
  final SignalChainIcon icon;
  final bool isHighlight;

  const SignalChainNode({
    required this.label,
    this.sublabel,
    required this.icon,
    this.isHighlight = false,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Service to inspect active hardware audio specifications and device routes.
///
/// On Android: uses an EventChannel to receive live updates whenever the output
/// device changes (headphone plug, BT connect/disconnect, USB DAC attach).
///
/// On Desktop/iOS: queries the native miniaudio AEHardwareInfo synchronously.
class AudioHardwareInspector {
  static const MethodChannel _methodChannel =
      MethodChannel('com.wambugu.sautiflow/hardware');
  static const EventChannel _eventChannel =
      EventChannel('com.wambugu.sautiflow/hardware_stream');

  // Cached stream — one subscription shared across the app lifetime
  static Stream<AudioHardwareSpecs>? _androidStream;

  // ── One-shot (Desktop / iOS) ──────────────────────────────────────────────

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

  /// Single async fetch — kept for backward compatibility & initial load on Android.
  static Future<AudioHardwareSpecs> inspectAsync(dynamic player) async {
    if (Platform.isAndroid) {
      try {
        final res = await _methodChannel.invokeMethod('getHardwareAudioSpecs');
        if (res is Map) {
          return AudioHardwareSpecs.fromAndroidMap(res);
        }
      } catch (e) {
        // Fall through to native
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

  // ── Live Stream (Android EventChannel) ───────────────────────────────────

  /// Returns a broadcast [Stream<AudioHardwareSpecs>] that emits a new value
  /// whenever the active audio output route changes (plug/unplug, BT events).
  ///
  /// On non-Android platforms returns a single-element stream from [inspectAsync].
  static Stream<AudioHardwareSpecs> hardwareStream(dynamic player) {
    if (!Platform.isAndroid) {
      // Desktop / iOS: one-shot stream
      return Stream.fromFuture(inspectAsync(player));
    }

    // Android: reuse existing subscription
    _androidStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            return AudioHardwareSpecs.fromAndroidMap(event);
          }
          return const AudioHardwareSpecs(
            backendName: 'AAudio / Android HAL',
            deviceName: 'Default Output Device',
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
        })
        .handleError((e) {
          // Don't crash the stream on error
        })
        .asBroadcastStream();

    return _androidStream!;
  }

  /// Clears the cached Android stream (call this if the Flutter engine restarts).
  static void resetStream() {
    _androidStream = null;
  }
}
