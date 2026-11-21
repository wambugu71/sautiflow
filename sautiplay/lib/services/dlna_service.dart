import 'dart:async';
import 'dart:io';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart' show AudioMime, PlayType;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dlna_renderer_service.dart';
import 'local_media_server.dart';

/// Parsed UPnP `ConnectionManager#GetProtocolInfo` Sink capabilities for a renderer.
class DlnaRendererCapabilities {
  final List<String> sinkProtocols;

  const DlnaRendererCapabilities(this.sinkProtocols);

  bool get isKnown => sinkProtocols.isNotEmpty;

  factory DlnaRendererCapabilities.fromSoapResponse(String xml) {
    final rawSink = DlnaRendererService.extractTag(xml, 'Sink') ?? '';
    final unescaped = DlnaRendererService.xmlUnescape(rawSink).trim();
    if (unescaped.isEmpty) {
      return const DlnaRendererCapabilities([]);
    }
    final entries = unescaped
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return DlnaRendererCapabilities(entries);
  }

  bool supportsMime(String mimeType) {
    if (!isKnown) return true;
    final target = mimeType.toLowerCase().split(';').first.trim();
    for (final entry in sinkProtocols) {
      final parts = entry.split(':');
      if (parts.length < 3) continue;
      final protoMime = parts[2].toLowerCase().split(';').first.trim();
      if (protoMime == '*' ||
          protoMime == '*/*' ||
          protoMime == 'audio/*' ||
          protoMime == target) {
        return true;
      }
      // Match equivalent FLAC / WAV / MP3 aliases
      if (target == 'audio/flac' && protoMime == 'audio/x-flac') return true;
      if (target == 'audio/x-flac' && protoMime == 'audio/flac') return true;
      if (target == 'audio/wav' && protoMime == 'audio/x-wav') return true;
      if (target == 'audio/x-wav' && protoMime == 'audio/wav') return true;
      if (target == 'audio/mpeg' && protoMime == 'audio/mp3') return true;
      if (target == 'audio/mp3' && protoMime == 'audio/mpeg') return true;
    }
    return false;
  }

  LiveCastStreamFormat preferredLiveFormat() {
    if (!isKnown || supportsMime('audio/wav')) {
      return LiveCastStreamFormat.wav24;
    }
    if (supportsMime('audio/l24')) {
      return LiveCastStreamFormat.lpcm24;
    }
    if (supportsMime('audio/l16')) {
      return LiveCastStreamFormat.lpcm16;
    }
    return LiveCastStreamFormat.wav24;
  }

  /// Returns the highest explicitly advertised PCM `rate=` parameter if any
  /// entry specifies one, or `null` if the renderer does not cap via `rate=`.
  int? maxSampleRateHz() {
    int? maxRate;
    final rateRe = RegExp(r'rate=(\d+)', caseSensitive: false);
    for (final entry in sinkProtocols) {
      final lower = entry.toLowerCase();
      if (!lower.contains('audio/l16') &&
          !lower.contains('audio/l24') &&
          !lower.contains('audio/wav')) {
        continue;
      }
      final m = rateRe.firstMatch(entry);
      if (m != null) {
        final r = int.tryParse(m.group(1)!);
        if (r != null && r > 0 && (maxRate == null || r > maxRate)) {
          maxRate = r;
        }
      }
    }
    return maxRate;
  }
}

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
  final Map<String, DlnaRendererCapabilities> _capabilitiesCache = {};
  bool _isSearching = false;
  bool _isStreamingLiveTap = false;
  String? _lastError;
  DlnaDeviceInfo? _activeRenderer;
  void Function(Duration position)? onLiveTapSeek;

  List<DlnaDeviceInfo> get devices => List.unmodifiable(_devices);
  List<DlnaDeviceInfo> get mediaServers =>
      _devices.where((d) => d.isMediaServer).toList();
  List<DlnaDeviceInfo> get mediaRenderers =>
      _devices.where((d) => d.isMediaRenderer).toList();
  bool get isSearching => _isSearching;
  bool get isStreamingLiveTap => _isStreamingLiveTap;
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

  /// Queries and caches UPnP `ConnectionManager#GetProtocolInfo` capabilities
  /// for [renderer]. Returns `null` if the device does not respond.
  Future<DlnaRendererCapabilities?> fetchRendererCapabilities(
    DlnaDeviceInfo renderer,
  ) async {
    final cached = _capabilitiesCache[renderer.id];
    if (cached != null) return cached;
    try {
      final xml = await renderer.deviceRef
          .getProtocolInfo()
          .timeout(const Duration(seconds: 3));
      final caps = DlnaRendererCapabilities.fromSoapResponse(xml);
      _capabilitiesCache[renderer.id] = caps;
      return caps;
    } catch (e) {
      debugPrint(
          '[DlnaService] GetProtocolInfo unavailable for ${renderer.name}: $e');
      return null;
    }
  }

  /// Sets active DLNA Renderer for audio casting.
  void setActiveRenderer(DlnaDeviceInfo? renderer) {
    _activeRenderer = renderer;
    if (renderer == null) {
      _isStreamingLiveTap = false;
    }
    notifyListeners();
  }

  /// Casts an audio stream URL to the specified DLNA MediaRenderer.
  Future<bool> castAudioUrl({
    required DlnaDeviceInfo renderer,
    required String audioUrl,
    String title = 'Sautiplay Audio Stream',
    String artist = '',
    String album = '',
    String? artworkUrl,
    double? durationSeconds,
    String? mimeType,
    String? protocolInfoOverride,
    bool isLiveStream = false,
  }) async {
    try {
      final device = renderer.deviceRef;
      debugPrint('[DlnaService] Casting to ${renderer.name}: $title');

      // Stop any active transport first so renderers cleanly transition
      // between Bit-Perfect pass-through and live DSP WAV streams.
      try {
        await device.stop();
      } catch (_) {}

      final playType = _resolveAudioMime(audioUrl, mimeType);
      final durStr = _formatUpnpDuration(durationSeconds);

      await device.setUrl(
        audioUrl,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl ?? '',
        duration: durStr,
        protocolInfoOverride: protocolInfoOverride,
        type: playType,
      );
      await device.play();

      _isStreamingLiveTap = isLiveStream;
      setActiveRenderer(renderer);
      return true;
    } catch (e) {
      debugPrint('[DlnaService] Failed to cast to ${renderer.name}: $e');
      return false;
    }
  }

  static PlayType _resolveAudioMime(String url, String? mimeType) {
    final mime = (mimeType ?? '').toLowerCase();
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (mime.contains('wav') || path.endsWith('.wav')) return AudioMime.wav;
    if (mime.contains('flac') || path.endsWith('.flac')) return AudioMime.flac;
    if (mime.contains('mpeg') || mime.contains('mp3') || path.endsWith('.mp3')) {
      return AudioMime.mp3;
    }
    if (mime.contains('mp4') || path.endsWith('.m4a') || path.endsWith('.mp4')) {
      return AudioMime.mp4;
    }
    if (mime.contains('aac') || path.endsWith('.aac')) return AudioMime.aac;
    if (mime.contains('ogg') || path.endsWith('.ogg')) return AudioMime.ogg;
    if (mime.contains('opus') || path.endsWith('.opus')) return AudioMime.opus;
    if (mime.contains('aiff') || path.endsWith('.aif') || path.endsWith('.aiff')) {
      return AudioMime.aiff;
    }
    if (mime.contains('dsf') || path.endsWith('.dsf')) return AudioMime.dsf;
    if (mime.contains('wma') || path.endsWith('.wma')) return AudioMime.wma;
    if (mime.contains('ape') || path.endsWith('.ape')) return AudioMime.xApe;
    return AudioMime.any;
  }

  static String _formatUpnpDuration(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds <= 0) return '';
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
      _isStreamingLiveTap = false;
      setActiveRenderer(null);
    } catch (e) {
      debugPrint('[DlnaService] Stop command error: $e');
    }
  }

  /// Sends UPnP AVTransport Seek (REL_TIME `HH:MM:SS`) to active renderer.
  Future<void> seek(Duration position) async {
    if (_activeRenderer == null || _isStreamingLiveTap) return;
    try {
      final secs = position.inSeconds < 0 ? 0 : position.inSeconds;
      final h = (secs ~/ 3600).toString().padLeft(2, '0');
      final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
      final s = (secs % 60).toString().padLeft(2, '0');
      await _activeRenderer!.deviceRef.seek('$h:$m:$s');
    } catch (e) {
      debugPrint('[DlnaService] Seek command error: $e');
    }
  }

  @override
  void dispose() {
    stopSearch();
    super.dispose();
  }
}
