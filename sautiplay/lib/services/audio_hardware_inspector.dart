import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  final String
      deviceType; // "Speakers", "3.5mm Headphone Jack", "Bluetooth", "USB DAC"
  final String? dspHardware; // e.g. "Qualcomm Hexagon v73 aDSP", "MediaTek Tensilica HiFi 5"
  final String? socName; // e.g. "Snapdragon 8 Gen 2", "Dimensity 9200"
  final bool isDirectPcm; // True if direct bit-perfect HAL output
  final bool isFixedClock; // True when hardware/HAL/A2DP/mixer clock is fixed
  final bool directMultiRate; // True when multiple hardware rates are directly supported

  // ── Bluetooth-specific fields ─────────────────────────────────────────────
  final String? bluetoothCodec; // e.g. "LDAC", "aptX HD", "AAC", "SBC", "LC3"
  final String?
      bluetoothDeviceName; // Actual BT device name (e.g. "Sony WH-1000XM5")
  final int? btSampleRate; // BT codec negotiated sample rate
  final int? btBitDepth; // BT codec bit depth
  final String? btChannelMode; // e.g. "Stereo", "Mono"
  final String? btQualityLabel; // e.g. "990/909 kbps (Quality)"

  final List<int> supportedSampleRates;
  final List<int> supportedBitDepths;
  final bool usbDacAttached;
  final bool usbHasPermission;

  // ── System info ───────────────────────────────────────────────────────────
  final int? androidVersion; // Android SDK version
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
    this.dspHardware,
    this.socName,
    this.isDirectPcm = false,
    this.isFixedClock = false,
    this.directMultiRate = false,
    this.bluetoothCodec,
    this.bluetoothDeviceName,
    this.btSampleRate,
    this.btBitDepth,
    this.btChannelMode,
    this.btQualityLabel,
    this.supportedSampleRates = const [],
    this.supportedBitDepths = const [],
    this.usbDacAttached = false,
    this.usbHasPermission = false,
    this.androidVersion,
    this.androidRelease,
  });

  /// Factory: build from the Map pushed by the Android EventChannel / MethodChannel.
  factory AudioHardwareSpecs.fromAndroidMap(Map<dynamic, dynamic> m) {
    final rawDevType = m['deviceType']?.toString() ?? 'Built-in Speaker';
    final devName = (m['deviceName']?.toString() ?? '').isNotEmpty
        ? m['deviceName'].toString()
        : 'Default Soundcard';

    final int? btRate = (m['btSampleRate'] as num?)?.toInt();
    final int? btBits = (m['btBitDepth'] as num?)?.toInt();
    final int rawRate = (m['sampleRate'] as num?)?.toInt() ?? 48000;
    final int rawBitDepth = (m['bitDepth'] as num?)?.toInt() ?? 32;
    final bool rawIsFloat = (m['isFloat'] as bool?) ?? true;

    final isBt = rawDevType.contains('Bluetooth') ||
        rawDevType.contains('bluetooth') ||
        m['bluetoothCodec'] != null;

    final int effectiveSampleRate =
        (isBt && btRate != null && btRate > 0) ? btRate : rawRate;
    final int effectiveBitDepth =
        (isBt && btBits != null && btBits > 0) ? btBits : rawBitDepth;
    final bool effectiveIsFloat = isBt ? false : rawIsFloat;

    final supportedRatesRaw = m['supportedSampleRates'];
    final List<int> supportedRates = (supportedRatesRaw is List)
        ? supportedRatesRaw.map((e) => (e as num).toInt()).toList()
        : const <int>[];

    final supportedBitsRaw = m['supportedBitDepths'];
    final List<int> supportedBits = (supportedBitsRaw is List)
        ? supportedBitsRaw.map((e) => (e as num).toInt()).toList()
        : const <int>[];

    final bool usbAttached =
        m['usbDacAttached'] == true || rawDevType.toLowerCase().contains('usb');

    final bool isFixedClock = m['isFixedClock'] is bool
        ? m['isFixedClock'] as bool
        : (isBt || (!usbAttached && supportedRates.length <= 1));
    final bool directMultiRate = m['directMultiRate'] is bool
        ? m['directMultiRate'] as bool
        : (usbAttached || (!isBt && !isFixedClock && supportedRates.length > 1));

    return AudioHardwareSpecs(
      backendName: 'AAudio / Android HAL',
      deviceName: devName,
      sampleRate: effectiveSampleRate,
      bitDepth: effectiveBitDepth,
      isFloat: effectiveIsFloat,
      channels: (m['channels'] as num?)?.toInt() ?? 2,
      periodSizeFrames: (m['periodSizeFrames'] as num?)?.toInt() ?? 192,
      periodCount: (m['periodCount'] as num?)?.toInt() ?? 2,
      latencyMs: (m['latencyMs'] as num?)?.toDouble() ?? 0.0,
      isExclusiveMode: false,
      deviceType: rawDevType,
      dspHardware: m['dspHardware']?.toString(),
      socName: m['socName']?.toString(),
      isDirectPcm: m['isDirectPcm'] == true,
      isFixedClock: isFixedClock,
      directMultiRate: directMultiRate,
      bluetoothCodec: m['bluetoothCodec']?.toString(),
      bluetoothDeviceName: m['bluetoothDeviceName']?.toString(),
      btSampleRate: btRate,
      btBitDepth: btBits,
      btChannelMode: m['btChannelMode']?.toString(),
      btQualityLabel: m['btQualityLabel']?.toString(),
      supportedSampleRates: supportedRates,
      supportedBitDepths: supportedBits,
      usbDacAttached: usbAttached,
      usbHasPermission: m['usbHasPermission'] == true,
      androidVersion: (m['androidVersion'] as num?)?.toInt(),
      androidRelease: m['androidRelease']?.toString(),
    );
  }

  /// Factory: build from native miniaudio AEHardwareInfo (Desktop / iOS).
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
      deviceName: native.deviceName.isNotEmpty
          ? native.deviceName
          : 'Default Soundcard',
      sampleRate: native.sampleRate > 0 ? native.sampleRate : 48000,
      bitDepth: native.bitDepth > 0 ? native.bitDepth : 32,
      isFloat: native.isFloat,
      channels: native.channels > 0 ? native.channels : 2,
      periodSizeFrames: native.periodSizeFrames,
      periodCount: native.periodCount,
      latencyMs: native.latencyMs,
      isExclusiveMode: native.isExclusiveMode,
      deviceType: devType,
      dspHardware: native.dspHardware.isNotEmpty ? native.dspHardware : null,
      socName: native.socName.isNotEmpty ? native.socName : null,
      isDirectPcm: native.isDirectPcm,
      isFixedClock: !native.isExclusiveMode,
      directMultiRate: native.isExclusiveMode,
    );
  }

  // ── Computed properties ───────────────────────────────────────────────────

  /// True if device hardware supports Hi-Res Audio (>48kHz or >16-bit or USB DAC)
  bool get isHiResAudio =>
      sampleRate > 48000 || bitDepth > 16 || deviceType.contains('USB');

  /// True when the active output route or connected device is a USB DAC.
  bool get isUsbDac =>
      usbDacAttached ||
      deviceType.toLowerCase().contains('usb') ||
      backendName == 'USB Direct' ||
      deviceName.toLowerCase().contains('usb') ||
      deviceName.toLowerCase().contains('dac');

  /// True when the native libusb UAC 1.0/2.0 kernel-bypass driver is active.
  bool get isUsbDirectBypass => backendName == 'USB Direct';

  /// True if Bluetooth is the active output route
  bool get isBluetooth =>
      deviceType.contains('Bluetooth') ||
      deviceType.contains('bluetooth') ||
      bluetoothCodec != null;

  /// Human-readable sample rate string
  String get formattedSampleRate {
    final kHz = (sampleRate / 1000.0).toStringAsFixed(1);
    return '$kHz kHz';
  }

  /// Human-readable bit depth string
  String get formattedBitDepth {
    if (isFloat) return '$bitDepth-bit Float';
    return '$bitDepth-bit Int';
  }

  /// Human-readable latency string
  String get formattedLatency => '${latencyMs.toStringAsFixed(2)} ms';

  /// Bluetooth codec + quality string, e.g. "LDAC 96kHz / 24-bit · 990/909 kbps"
  String? get formattedBtCodec {
    if (bluetoothCodec == null) return null;
    final codec = bluetoothCodec!;
    final parts = <String>[codec];
    if (btSampleRate != null && btBitDepth != null) {
      final kHz = (btSampleRate! / 1000.0)
          .toStringAsFixed(btSampleRate! % 1000 == 0 ? 0 : 1);
      parts.add('${kHz}kHz / $btBitDepth-bit');
    }
    if (btQualityLabel != null && btQualityLabel!.isNotEmpty) {
      parts.add(btQualityLabel!);
    }
    return parts.join(' · ');
  }

  /// Node 1: Track Source File / Stream
  /// Node 2: miniaudio DSP / Resampler
  /// Node 3: Audio Engine / HAL Driver
  /// Node 4: Output Route / Connection Type
  /// Node 5: Target Hardware DAC / Device
  List<SignalChainNode> buildPowerampSignalChain({
    String? sourceCodec,
    String? sourceSampleRate,
    String? sourceBitDepth,
    String? sourceChannels,
    String? dspSummary,
  }) {
    final nodes = <SignalChainNode>[];

    // Node 1: Source File / Track Info
    final codec = (sourceCodec?.isNotEmpty ?? false)
        ? sourceCodec!.toUpperCase()
        : 'AUDIO';
    final srcRate =
        sourceSampleRate ?? '${(sampleRate / 1000.0).toStringAsFixed(1)} kHz';
    final srcDepth = sourceBitDepth ?? '$bitDepth-bit';
    nodes.add(SignalChainNode(
      label: 'Track Source',
      sublabel: '$codec · $srcRate · $srcDepth',
      icon: SignalChainIcon.source,
      isHighlight: false,
    ));

    // Node 2: miniaudio DSP / Engine
    final dspText = dspSummary ?? '32-bit Float PCM';
    nodes.add(SignalChainNode(
      label: 'miniaudio DSP',
      sublabel: dspText,
      icon: SignalChainIcon.dsp,
      isHighlight: dspHardware != null || dspSummary != null,
    ));

    // Node 3: Audio Engine / Driver
    if (backendName == 'USB Direct') {
      final latLabel =
          latencyMs > 0 ? ' • ${latencyMs.toStringAsFixed(1)}ms' : '';
      final driverLabel = (dspHardware != null && dspHardware!.isNotEmpty)
          ? dspHardware!
          : 'libusb UAC 2.0 Kernel Bypass';
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: '$driverLabel$latLabel',
        icon: SignalChainIcon.backend,
        isHighlight: true,
      ));
    } else if (isDirectPcm) {
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: backendName == 'DAP Hi-Res'
            ? 'Dedicated DAP Hi-Res Driver'
            : 'Direct Hi-Res Bit-Perfect',
        icon: SignalChainIcon.backend,
        isHighlight: true,
      ));
    } else if (isExclusiveMode) {
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: 'Exclusive Bit-Perfect',
        icon: SignalChainIcon.backend,
        isHighlight: true,
      ));
    } else {
      final osLabel = androidRelease != null
          ? 'Android $androidRelease HAL'
          : 'Shared Mixer';
      final latLabel =
          latencyMs > 0 ? '${latencyMs.toStringAsFixed(1)}ms latency' : osLabel;
      nodes.add(SignalChainNode(
        label: backendName,
        sublabel: latLabel,
        icon: SignalChainIcon.backend,
      ));
    }

    // Node 4: Output Route / Transport
    if (isBluetooth) {
      final codecStr = formattedBtCodec ?? bluetoothCodec ?? 'SBC';
      nodes.add(SignalChainNode(
        label: deviceType,
        sublabel: codecStr,
        icon: SignalChainIcon.bluetooth,
        isHighlight: bluetoothCodec == 'LDAC' ||
            bluetoothCodec == 'aptX HD' ||
            bluetoothCodec == 'LC3',
      ));
    } else {
      final kHz = (sampleRate / 1000.0)
          .toStringAsFixed(sampleRate % 1000 == 0 ? 0 : 1);
      final routeRate = '$kHz kHz / $bitDepth-bit';
      nodes.add(SignalChainNode(
        label: deviceType,
        sublabel: routeRate,
        icon: _iconForDeviceType(deviceType),
        isHighlight: isHiResAudio,
      ));
    }

    // Node 5: Target Hardware DAC / Device
    final effectiveDeviceName = (bluetoothDeviceName?.isNotEmpty ?? false)
        ? bluetoothDeviceName!
        : (dspHardware != null && dspHardware!.isNotEmpty
            ? dspHardware!
            : deviceName);

    final effRate = (isBluetooth && btSampleRate != null && btSampleRate! > 0)
        ? btSampleRate!
        : sampleRate;
    final effBits = (isBluetooth && btBitDepth != null && btBitDepth! > 0)
        ? btBitDepth!
        : bitDepth;
    final kHz = (effRate / 1000.0).toStringAsFixed(effRate % 1000 == 0 ? 0 : 1);
    final outSub = '$kHz kHz / $effBits-bit Out';

    nodes.add(SignalChainNode(
      label: effectiveDeviceName,
      sublabel: outSub,
      icon: SignalChainIcon.output,
      isHighlight: isHiResAudio,
    ));

    return nodes;
  }

  SignalChainIcon _iconForDeviceType(String type) {
    if (type.contains('USB')) return SignalChainIcon.usbDac;
    if (type.contains('3.5mm') ||
        type.contains('Headphone') ||
        type.contains('Headset')) {
      return SignalChainIcon.wiredHeadphone;
    }
    if (type.contains('HDMI')) return SignalChainIcon.hdmi;
    if (type.contains('Speaker')) return SignalChainIcon.speaker;
    return SignalChainIcon.output;
  }
}

// ── Signal Chain Model ────────────────────────────────────────────────────────

enum SignalChainIcon {
  source,
  dsp,
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
/// On Android: uses MethodChannel for immediate async lookup and an EventChannel
/// broadcast stream to receive live updates whenever the output device changes.
class AudioHardwareInspector {
  static const MethodChannel _methodChannel =
      MethodChannel('com.wambugu.sautiflow/hardware');
  static const EventChannel _eventChannel =
      EventChannel('com.wambugu.sautiflow/hardware_stream');

  static AudioHardwareSpecs? _currentSpecs;
  static StreamSubscription? _androidEventSub;
  static final StreamController<AudioHardwareSpecs> _controller =
      StreamController<AudioHardwareSpecs>.broadcast();

  /// Synchronous fallback inspection
  static AudioHardwareSpecs inspect(dynamic player) {
    if (_currentSpecs != null) return _currentSpecs!;
    try {
      final nativeInfo = player.getHardwareInfo();
      if (nativeInfo is AEHardwareInfo) {
        _currentSpecs = AudioHardwareSpecs.fromNative(nativeInfo);
        return _currentSpecs!;
      }
    } catch (_) {}

    return const AudioHardwareSpecs(
      backendName: 'Audio Backend',
      deviceName: 'Default Soundcard',
      sampleRate: 48000,
      bitDepth: 32,
      isFloat: true,
      channels: 2,
      periodSizeFrames: 192,
      periodCount: 2,
      latencyMs: 0.0,
      isExclusiveMode: false,
      deviceType: 'Built-in Speaker',
    );
  }

  /// Merges Android platform channel metadata with live native engine [AEHardwareInfo]
  /// so `USB Direct` (`libusb`) and `Direct Hi-Res` routes retain their negotiated parameters.
  static AudioHardwareSpecs _mergeAndroidAndNative(
    Map<dynamic, dynamic> map,
    AEHardwareInfo? nativeHw,
  ) {
    final base = AudioHardwareSpecs.fromAndroidMap(map);
    if (nativeHw == null) return base;

    final bool isUsbDirect = nativeHw.backendName == 'USB Direct';
    final bool isNativeDirect = isUsbDirect ||
        nativeHw.backendName == 'Direct Hi-Res' ||
        nativeHw.backendName == 'DAP Hi-Res' ||
        nativeHw.isDirectPcm ||
        nativeHw.isExclusiveMode;

    if (isUsbDirect) {
      final hasSpecificNativeName = nativeHw.deviceName.isNotEmpty &&
          nativeHw.deviceName != 'USB Direct DAC (Standby)' &&
          nativeHw.deviceName != 'USB Direct DAC';
      final resolvedDeviceName = hasSpecificNativeName
          ? nativeHw.deviceName
          : (base.isUsbDac ? base.deviceName : nativeHw.deviceName);
      final mergedRates = <int>{
        ...base.supportedSampleRates,
        if (nativeHw.sampleRate > 0) nativeHw.sampleRate,
        if (base.supportedSampleRates.isEmpty) ...[
          44100,
          48000,
          88200,
          96000,
          176400,
          192000,
          352800,
          384000,
        ],
      }.toList()
        ..sort();

      return AudioHardwareSpecs(
        backendName: 'USB Direct',
        deviceName: resolvedDeviceName.isNotEmpty
            ? resolvedDeviceName
            : 'USB Audio DAC',
        sampleRate:
            nativeHw.sampleRate > 0 ? nativeHw.sampleRate : base.sampleRate,
        bitDepth: nativeHw.bitDepth > 0 ? nativeHw.bitDepth : base.bitDepth,
        isFloat: nativeHw.isFloat,
        channels: nativeHw.channels > 0 ? nativeHw.channels : base.channels,
        periodSizeFrames: nativeHw.periodSizeFrames > 0
            ? nativeHw.periodSizeFrames
            : base.periodSizeFrames,
        periodCount: nativeHw.periodCount > 0
            ? nativeHw.periodCount
            : base.periodCount,
        latencyMs:
            nativeHw.latencyMs > 0 ? nativeHw.latencyMs : base.latencyMs,
        isExclusiveMode: nativeHw.isExclusiveMode,
        deviceType: 'USB DAC',
        dspHardware: nativeHw.dspHardware.isNotEmpty
            ? nativeHw.dspHardware
            : base.dspHardware,
        socName: nativeHw.socName.isNotEmpty ? nativeHw.socName : base.socName,
        isDirectPcm: true,
        isFixedClock: false,
        directMultiRate: true,
        supportedSampleRates: mergedRates,
        usbDacAttached: base.usbDacAttached || hasSpecificNativeName,
        usbHasPermission: base.usbHasPermission || hasSpecificNativeName,
        androidVersion: base.androidVersion,
        androidRelease: base.androidRelease,
      );
    }

    if (isNativeDirect || nativeHw.bitDepth > 0 || nativeHw.sampleRate > 0) {
      final bool verifiedMultiRate = isUsbDirect ||
          nativeHw.backendName == 'DAP Hi-Res' ||
          (nativeHw.isDirectPcm && base.directMultiRate) ||
          base.directMultiRate;
      return AudioHardwareSpecs(
        backendName: isNativeDirect && nativeHw.backendName.isNotEmpty
            ? nativeHw.backendName
            : base.backendName,
        deviceName: (isNativeDirect &&
                nativeHw.deviceName.isNotEmpty &&
                base.deviceName == 'Default Soundcard')
            ? nativeHw.deviceName
            : base.deviceName,
        sampleRate: (verifiedMultiRate && nativeHw.sampleRate > 0)
            ? nativeHw.sampleRate
            : base.sampleRate,
        bitDepth: nativeHw.bitDepth > 0 ? nativeHw.bitDepth : base.bitDepth,
        isFloat: nativeHw.bitDepth > 0 ? nativeHw.isFloat : base.isFloat,
        channels: base.channels,
        periodSizeFrames: (isNativeDirect && nativeHw.periodSizeFrames > 0)
            ? nativeHw.periodSizeFrames
            : base.periodSizeFrames,
        periodCount: (isNativeDirect && nativeHw.periodCount > 0)
            ? nativeHw.periodCount
            : base.periodCount,
        latencyMs: (isNativeDirect && nativeHw.latencyMs > 0)
            ? nativeHw.latencyMs
            : base.latencyMs,
        isExclusiveMode: isNativeDirect ? nativeHw.isExclusiveMode : base.isExclusiveMode,
        deviceType: base.deviceType,
        dspHardware: nativeHw.dspHardware.isNotEmpty
            ? nativeHw.dspHardware
            : base.dspHardware,
        socName: nativeHw.socName.isNotEmpty ? nativeHw.socName : base.socName,
        isDirectPcm: isNativeDirect ? nativeHw.isDirectPcm : base.isDirectPcm,
        isFixedClock: verifiedMultiRate ? false : base.isFixedClock,
        directMultiRate: verifiedMultiRate,
        bluetoothCodec: base.bluetoothCodec,
        bluetoothDeviceName: base.bluetoothDeviceName,
        btSampleRate: base.btSampleRate,
        btBitDepth: base.btBitDepth,
        btChannelMode: base.btChannelMode,
        btQualityLabel: base.btQualityLabel,
        supportedSampleRates: base.supportedSampleRates,
        supportedBitDepths: base.supportedBitDepths,
        usbDacAttached: base.usbDacAttached,
        usbHasPermission: base.usbHasPermission,
        androidVersion: base.androidVersion,
        androidRelease: base.androidRelease,
      );
    }

    return base;
  }

  /// Single async fetch — updates cached specs and notifies broadcast subscribers.
  static Future<AudioHardwareSpecs> inspectAsync(dynamic player) async {
    AEHardwareInfo? nativeHw;
    try {
      final rawNative = await player.getHardwareInfo();
      if (rawNative is AEHardwareInfo) {
        nativeHw = rawNative;
      }
    } catch (e) {
      debugPrint('[AudioHardwareInspector] Native getHardwareInfo error: $e');
    }

    if (Platform.isAndroid) {
      try {
        final res = await _methodChannel.invokeMethod('getHardwareAudioSpecs');
        if (res is Map) {
          _currentSpecs = _mergeAndroidAndNative(res, nativeHw);
          _controller.add(_currentSpecs!);
          return _currentSpecs!;
        }
      } catch (e) {
        debugPrint('[AudioHardwareInspector] Android MethodChannel error: $e');
      }
    }

    if (nativeHw != null) {
      _currentSpecs = AudioHardwareSpecs.fromNative(nativeHw);
      _controller.add(_currentSpecs!);
      return _currentSpecs!;
    }

    _currentSpecs ??= const AudioHardwareSpecs(
      backendName: 'AAudio / Android HAL',
      deviceName: 'Built-in Speaker',
      sampleRate: 48000,
      bitDepth: 32,
      isFloat: true,
      channels: 2,
      periodSizeFrames: 192,
      periodCount: 2,
      latencyMs: 0.0,
      isExclusiveMode: false,
      deviceType: 'Built-in Speaker',
    );
    return _currentSpecs!;
  }

  /// Returns a broadcast [Stream<AudioHardwareSpecs>] that emits current specs immediately
  /// and receives real-time updates on route/hardware changes.
  static Stream<AudioHardwareSpecs> hardwareStream(dynamic player) {
    // Eagerly fetch initial state if not cached
    if (_currentSpecs == null) {
      inspectAsync(player);
    }

    if (Platform.isAndroid && _androidEventSub == null) {
      _androidEventSub = _eventChannel.receiveBroadcastStream().listen(
        (event) async {
          if (event is Map) {
            AEHardwareInfo? nativeHw;
            try {
              final rawNative = await player.getHardwareInfo();
              if (rawNative is AEHardwareInfo) {
                nativeHw = rawNative;
              }
            } catch (_) {}
            _currentSpecs = _mergeAndroidAndNative(event, nativeHw);
            _controller.add(_currentSpecs!);
          }
        },
        onError: (e) {
          debugPrint('[AudioHardwareInspector] EventChannel error: $e');
        },
      );
    }

    return _controller.stream;
  }

  /// Get current cached specs synchronously (or null if not yet fetched)
  static AudioHardwareSpecs? get currentSpecs => _currentSpecs;

  /// Resets cached stream and specs (e.g. on hot restart)
  static void resetStream() {
    _androidEventSub?.cancel();
    _androidEventSub = null;
    _currentSpecs = null;
  }
}
