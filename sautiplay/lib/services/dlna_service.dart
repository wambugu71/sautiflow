import 'dart:async';
import 'dart:io';
import 'package:dlna_dart/dlna.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Representation of a discovered DLNA device on the local network.
class DlnaDeviceInfo {
  final String id;
  final String name;
  final String deviceType;
  final String locationUrl;
  final DLNADevice deviceRef;

  const DlnaDeviceInfo({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.locationUrl,
    required this.deviceRef,
  });

  bool get isMediaServer =>
      deviceType.toLowerCase().contains('mediaserver') ||
      deviceType.toLowerCase().contains('contentdirectory');

  bool get isMediaRenderer =>
      deviceType.toLowerCase().contains('mediarenderer') ||
      deviceType.toLowerCase().contains('avtransport');
}

/// Service managing DLNA/UPnP network discovery, Media Server browsing, and Renderer casting.
class DlnaService extends ChangeNotifier {
  static final DlnaService instance = DlnaService._internal();
  DlnaService._internal();

  static const MethodChannel _hardwareChannel =
      MethodChannel('com.wambugu.sautiflow/hardware');

  DLNAManager? _dlnaManager;
  DeviceManager? _deviceManager;
  StreamSubscription? _deviceSubscription;

  final List<DlnaDeviceInfo> _devices = [];
  bool _isSearching = false;
  String? _lastError;
  DlnaDeviceInfo? _activeRenderer;

  List<DlnaDeviceInfo> get devices => List.unmodifiable(_devices);
  List<DlnaDeviceInfo> get mediaServers =>
      _devices.where((d) => d.isMediaServer).toList();
  List<DlnaDeviceInfo> get mediaRenderers =>
      _devices.where((d) => d.isMediaRenderer).toList();
  bool get isSearching => _isSearching;
  String? get lastError => _lastError;
  DlnaDeviceInfo? get activeRenderer => _activeRenderer;

  /// Starts SSDP discovery for DLNA devices on the local Wi-Fi / network.
  Future<void> startSearch() async {
    if (_isSearching) return;
    _isSearching = true;
    _devices.clear();
    _lastError = null;
    notifyListeners();

    if (Platform.isAndroid) {
      try {
        await _hardwareChannel.invokeMethod('acquireMulticastLock');
      } catch (e) {
        debugPrint('[DlnaService] Could not acquire Android MulticastLock: $e');
      }
    }

    try {
      _dlnaManager = DLNAManager();
      // reusePort (SO_REUSEPORT) avoids 'Address already in use' on Android
      // when another app already holds UDP port 1900.
      _deviceManager = await _dlnaManager!.start(
        reusePort: Platform.isAndroid || Platform.isLinux || Platform.isMacOS,
      );

      _deviceSubscription?.cancel();
      _deviceSubscription = _deviceManager!.devices.stream.listen(
        (Map<String, DLNADevice> deviceMap) {
          _devices.clear();
          deviceMap.forEach((key, device) {
            final name = device.info.friendlyName.isNotEmpty
                ? device.info.friendlyName
                : 'DLNA Device ($key)';
            final type = device.info.deviceType;
            final locUrl = device.info.URLBase;

            _devices.add(DlnaDeviceInfo(
              id: key,
              name: name,
              deviceType: type,
              locationUrl: locUrl,
              deviceRef: device,
            ));
          });
          notifyListeners();
        },
        onError: (e) {
          debugPrint('[DlnaService] Error during SSDP discovery stream: $e');
        },
      );
    } catch (e) {
      debugPrint('[DlnaService] Failed to start DLNA search: $e');
      _lastError =
          'DLNA discovery failed to start: check that Wi-Fi is on and this '
          'device is on the same network as your DLNA hardware.';
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Stops ongoing SSDP discovery search.
  void stopSearch() {
    _deviceSubscription?.cancel();
    _deviceSubscription = null;
    _dlnaManager?.stop();
    _dlnaManager = null;
    _deviceManager = null;
    _isSearching = false;

    if (Platform.isAndroid) {
      try {
        _hardwareChannel.invokeMethod('releaseMulticastLock');
      } catch (e) {
        debugPrint('[DlnaService] Could not release Android MulticastLock: $e');
      }
    }

    notifyListeners();
  }

  /// Sets active DLNA Renderer for audio casting.
  void setActiveRenderer(DlnaDeviceInfo? renderer) {
    _activeRenderer = renderer;
    notifyListeners();
  }

  /// Casts an audio stream URL to the specified DLNA MediaRenderer.
  Future<bool> castAudioUrl({
    required DlnaDeviceInfo renderer,
    required String audioUrl,
    String title = 'Sautiplay Audio Stream',
  }) async {
    try {
      final device = renderer.deviceRef;
      debugPrint('[DlnaService] Casting to ${renderer.name}');

      await device.setUrl(audioUrl, title: title);
      await device.play();

      setActiveRenderer(renderer);
      return true;
    } catch (e) {
      debugPrint('[DlnaService] Failed to cast to ${renderer.name}: $e');
      return false;
    }
  }

  /// Sends Play command to active renderer.
  Future<void> play() async {
    if (_activeRenderer == null) return;
    try {
      await _activeRenderer!.deviceRef.play();
    } catch (e) {
      debugPrint('[DlnaService] Play command error: $e');
    }
  }

  /// Sends Pause command to active renderer.
  Future<void> pause() async {
    if (_activeRenderer == null) return;
    try {
      await _activeRenderer!.deviceRef.pause();
    } catch (e) {
      debugPrint('[DlnaService] Pause command error: $e');
    }
  }

  /// Sends Stop command to active renderer.
  Future<void> stop() async {
    if (_activeRenderer == null) return;
    try {
      await _activeRenderer!.deviceRef.stop();
      setActiveRenderer(null);
    } catch (e) {
      debugPrint('[DlnaService] Stop command error: $e');
    }
  }

  @override
  void dispose() {
    stopSearch();
    super.dispose();
  }
}
