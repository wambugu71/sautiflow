import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sautiplay/database/preferences_store.dart';

/// Audio delivery pipeline mode for network casting (Chromecast & DLNA).
enum CastAudioMode {
  /// Direct original-file pass-through when container/sample-rate/bit-depth allow;
  /// automatically falls back to a 24-bit LPCM WAV engine stream with DSP bypassed
  /// for DSD, 32-bit float, >ceiling sample rates, CUE slices, or ALAC on Cast.
  bitPerfect,

  /// Live 24-bit signed little-endian LPCM WAV engine stream tapped post-DSP
  /// so EQ, AutoEQ, Crossfeed, Surround, Limiter, and Loudness are preserved.
  dspProcessed,
}

/// Configurable sample-rate ceiling for Cast & DLNA output.
enum CastMaxSampleRate {
  hz192000(192000, '192 kHz'),
  hz96000(96000, '96 kHz'),
  hz48000(48000, '48 kHz');

  final int hz;
  final String label;
  const CastMaxSampleRate(this.hz, this.label);
}

/// Represents a discovered or manually added Google Cast receiver on the LAN.
class ChromecastDeviceInfo {
  final String id;
  final String friendlyName;
  final String modelName;
  final String host;
  final int port;
  final int capabilities;
  final bool isManual;

  const ChromecastDeviceInfo({
    required this.id,
    required this.friendlyName,
    required this.modelName,
    required this.host,
    this.port = 8009,
    this.capabilities = 0,
    this.isManual = false,
  });

  bool get supportsAudio => capabilities == 0 || (capabilities & 0x04) != 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'friendlyName': friendlyName,
        'modelName': modelName,
        'host': host,
        'port': port,
        'capabilities': capabilities,
        'isManual': isManual,
      };

  factory ChromecastDeviceInfo.fromJson(Map<String, dynamic> json) {
    return ChromecastDeviceInfo(
      id: (json['id'] as String?) ?? '${json['host']}:${json['port'] ?? 8009}',
      friendlyName: (json['friendlyName'] as String?) ??
          (json['host'] as String?) ??
          'Chromecast',
      modelName: (json['modelName'] as String?) ?? 'Chromecast',
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as int?) ?? 8009,
      capabilities: (json['capabilities'] as int?) ?? 0,
      isManual: json['isManual'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChromecastDeviceInfo &&
      other.id == id &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, host, port);
}

/// Parsed DNS record extracted from an mDNS response packet.
@visibleForTesting
class MdnsParsedRecord {
  final String name;
  final int type;
  final String? ptrTarget;
  final String? srvTarget;
  final int srvPort;
  final Map<String, String> txt;
  final String? ipv4;

  const MdnsParsedRecord({
    required this.name,
    required this.type,
    this.ptrTarget,
    this.srvTarget,
    this.srvPort = 0,
    this.txt = const {},
    this.ipv4,
  });
}

/// Decoded Google Cast V2 `CastMessage` protobuf frame.
class CastWireMessage {
  final int protocolVersion;
  final String sourceId;
  final String destinationId;
  final String namespace;
  final int payloadType;
  final String? payloadUtf8;
  final Uint8List? payloadBinary;

  const CastWireMessage({
    this.protocolVersion = 0,
    required this.sourceId,
    required this.destinationId,
    required this.namespace,
    this.payloadType = 0,
    this.payloadUtf8,
    this.payloadBinary,
  });
}

/// Google Cast (Chromecast) discovery & Cast V2 TLS streaming controller
/// supporting up to 24-bit / 192 kHz Hi-Res LPCM and Bit-Perfect pass-through.
class ChromecastService extends ChangeNotifier {
  ChromecastService._internal() {
    _loadPreferences();
  }

  static final ChromecastService instance = ChromecastService._internal();

  static const _hardwareChannel = MethodChannel('com.wambugu.sautiflow/hardware');
  static const _prefModeKey = 'cast_audio_mode';
  static const _prefMaxRateKey = 'cast_max_sample_rate';
  static const _prefManualIpsKey = 'cast_manual_ips_v1';

  static const _nsConnection = 'urn:x-cast:com.google.cast.tp.connection';
  static const _nsHeartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _nsReceiver = 'urn:x-cast:com.google.cast.receiver';
  static const _nsMedia = 'urn:x-cast:com.google.cast.media';
  static const _defaultMediaReceiverAppId = 'CC1AD845';

  final List<ChromecastDeviceInfo> _devices = [];
  final List<ChromecastDeviceInfo> _manualDevices = [];
  ChromecastDeviceInfo? _activeDevice;
  CastAudioMode _audioMode = CastAudioMode.bitPerfect;
  CastMaxSampleRate _maxSampleRate = CastMaxSampleRate.hz192000;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isStreamingLiveTap = false;
  String? _lastError;
  double _volumeLevel = 1.0;
  bool _isMuted = false;

  SecureSocket? _socket;
  StreamSubscription<Uint8List>? _socketSub;
  final BytesBuilder _rxBuffer = BytesBuilder(copy: false);
  Timer? _heartbeatTimer;
  Timer? _scanTimeoutTimer;
  RawDatagramSocket? _multicastSocket;
  RawDatagramSocket? _unicastSocket;
  int _lastPongMs = 0;

  int _nextRequestId = 1;
  String? _transportId;
  int? _mediaSessionId;
  Completer<String?>? _launchCompleter;
  bool _disposed = false;

  /// Optional hook invoked when the user seeks while streaming the live WAV tap.
  void Function(Duration position)? onLiveTapSeek;

  List<ChromecastDeviceInfo> get devices => List.unmodifiable(_devices);
  ChromecastDeviceInfo? get activeDevice => _activeDevice;
  CastAudioMode get audioMode => _audioMode;
  CastMaxSampleRate get maxSampleRate => _maxSampleRate;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isStreamingLiveTap => _isStreamingLiveTap;
  String? get lastError => _lastError;
  double get volumeLevel => _volumeLevel;
  bool get isMuted => _isMuted;

  set isStreamingLiveTap(bool value) {
    if (_isStreamingLiveTap != value) {
      _isStreamingLiveTap = value;
      _safeNotify();
    }
  }

  /// Resolves the target sample rate under [ceilingRate] while preserving the
  /// source clock family (44.1 kHz multiples vs 48 kHz multiples).
  static int resolveCastTargetSampleRate(int sourceRate, int ceilingRate) {
    final safeCeiling = ceilingRate > 0 ? ceilingRate : 192000;
    if (sourceRate <= 0) return math.min(48000, safeCeiling);

    final isDsd441 = sourceRate >= 2822400 && sourceRate % 44100 == 0;
    final isDsd48 = sourceRate >= 3072000 && sourceRate % 48000 == 0;
    if (isDsd441 || isDsd48) {
      if (isDsd441) {
        if (safeCeiling >= 176400) return 176400;
        if (safeCeiling >= 88200) return 88200;
        return 44100;
      } else {
        if (safeCeiling >= 192000) return 192000;
        if (safeCeiling >= 96000) return 96000;
        return 48000;
      }
    }

    if (sourceRate <= safeCeiling) {
      return sourceRate;
    }

    if (sourceRate % 44100 == 0) {
      if (safeCeiling >= 176400) return 176400;
      if (safeCeiling >= 88200) return 88200;
      return 44100;
    }
    if (safeCeiling >= 192000) return 192000;
    if (safeCeiling >= 96000) return 96000;
    return 48000;
  }

  /// Whether a track can be handed off as a direct unmodified file URL in
  /// [CastAudioMode.bitPerfect] mode rather than routed through the 24-bit LPCM
  /// engine WAV stream.
  static bool canPassThroughDirectly({
    required Uri uri,
    required bool isClipped,
    required int sampleRate,
    required int bitDepth,
    required bool isFloat,
    required int ceilingRate,
    bool isChromecast = true,
    String? formatName,
  }) {
    if (isClipped) return false;
    if (isFloat) return false;
    if (bitDepth > 24) return false;
    if (sampleRate >= 2822400) return false;
    if (ceilingRate > 0 && sampleRate > ceilingRate) return false;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'file' && scheme != 'http' && scheme != 'https') {
      return false;
    }

    final ext = p.extension(uri.path).toLowerCase();
    const unsupportedDirect = {
      '.dsf',
      '.dff',
      '.wv',
      '.ape',
      '.tak',
      '.mpc',
      '.iso',
      '.cue',
      '.wma',
    };
    if (unsupportedDirect.contains(ext)) return false;

    final fmtLower = (formatName ?? '').toLowerCase();
    if (fmtLower.contains('dsd') || fmtLower.contains('wavpack')) {
      return false;
    }

    if (isChromecast) {
      if (ext == '.aif' || ext == '.aiff') return false;
      if (fmtLower.contains('alac')) return false;
      if (ext == '.m4a' && scheme == 'file' && _fileHasAlacAtom(uri)) {
        return false;
      }
      const chromecastNativeExts = {
        '.flac',
        '.wav',
        '.mp3',
        '.aac',
        '.m4a',
        '.mp4',
        '.ogg',
        '.opus',
        '.webm',
      };
      if (ext.isNotEmpty && !chromecastNativeExts.contains(ext)) {
        return false;
      }
    }

    return true;
  }

  static bool _fileHasAlacAtom(Uri uri) {
    try {
      final path = uri.toFilePath(windows: Platform.isWindows);
      final file = File(path);
      if (!file.existsSync()) return false;
      final raf = file.openSync(mode: FileMode.read);
      try {
        final len = math.min(raf.lengthSync(), 16384);
        final bytes = raf.readSync(len);
        // Quick scan for 'alac' 4CC atom in MP4/M4A moov/stsd header.
        for (int i = 0; i <= bytes.length - 4; i++) {
          if (bytes[i] == 0x61 && // 'a'
              bytes[i + 1] == 0x6C && // 'l'
              bytes[i + 2] == 0x61 && // 'a'
              bytes[i + 3] == 0x63) { // 'c'
            return true;
          }
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      // Best-effort check; fall back cleanly.
    }
    return false;
  }

  void _loadPreferences() {
    try {
      final modeStr = PreferencesStore.instance.getString(_prefModeKey);
      if (modeStr == CastAudioMode.dspProcessed.name) {
        _audioMode = CastAudioMode.dspProcessed;
      } else {
        _audioMode = CastAudioMode.bitPerfect;
      }

      final maxRate = PreferencesStore.instance.getInt(
        _prefMaxRateKey,
        defaultValue: CastMaxSampleRate.hz192000.hz,
      );
      _maxSampleRate = CastMaxSampleRate.values.firstWhere(
        (e) => e.hz == maxRate,
        orElse: () => CastMaxSampleRate.hz192000,
      );

      final manualRaw = PreferencesStore.instance.getString(_prefManualIpsKey);
      if (manualRaw != null && manualRaw.isNotEmpty) {
        final decoded = jsonDecode(manualRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final dev = ChromecastDeviceInfo.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (dev.host.isNotEmpty) {
                _manualDevices.add(dev);
                _upsertDevice(dev);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ChromecastService] Failed loading prefs: $e');
    }
  }

  Future<void> setAudioMode(CastAudioMode mode) async {
    if (_audioMode == mode) return;
    _audioMode = mode;
    try {
      await PreferencesStore.instance.setString(_prefModeKey, mode.name);
    } catch (_) {}
    _safeNotify();
  }

  Future<void> setMaxSampleRate(CastMaxSampleRate rate) async {
    if (_maxSampleRate == rate) return;
    _maxSampleRate = rate;
    try {
      await PreferencesStore.instance.setInt(_prefMaxRateKey, rate.hz);
    } catch (_) {}
    _safeNotify();
  }

  void _saveManualDevices() {
    try {
      final jsonStr = jsonEncode(_manualDevices.map((e) => e.toJson()).toList());
      PreferencesStore.instance.setString(_prefManualIpsKey, jsonStr);
    } catch (_) {}
  }

  /// Adds or probes a Chromecast / Cast Built-in device manually by LAN IP.
  Future<ChromecastDeviceInfo?> addManualDevice(
    String hostInput, {
    int port = 8009,
    String? friendlyName,
  }) async {
    final host = hostInput.trim();
    if (host.isEmpty) return null;

    String resolvedName =
        (friendlyName != null && friendlyName.trim().isNotEmpty)
            ? friendlyName.trim()
            : 'Chromecast ($host)';
    String model = 'Google Cast Device';
    String id = 'manual:$host:$port';

    // Probe Cast eureka_info on port 8008 for friendly name/model when open.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('http://$host:8008/setup/eureka_info?options=detail'),
      );
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data is Map) {
          final n = data['name']?.toString().trim();
          if (n != null && n.isNotEmpty) resolvedName = n;
          final detail = data['detail'];
          if (detail is Map && detail['model_name'] != null) {
            model = detail['model_name'].toString();
          }
          final ssdpUdn = data['ssdp_udn']?.toString().trim();
          if (ssdpUdn != null && ssdpUdn.isNotEmpty) {
            id = ssdpUdn;
          }
        }
      }
    } catch (_) {
      // Keep fallback friendly name & connect straight to Cast V2 TLS 8009.
    } finally {
      client.close(force: true);
    }

    final device = ChromecastDeviceInfo(
      id: id,
      friendlyName: resolvedName,
      modelName: model,
      host: host,
      port: port,
      isManual: true,
    );

    _manualDevices.removeWhere((d) => d.host == host && d.port == port);
    _manualDevices.add(device);
    _saveManualDevices();
    _upsertDevice(device);
    return device;
  }

  Future<void> removeManualDevice(ChromecastDeviceInfo device) async {
    _manualDevices.removeWhere((d) => d.host == device.host && d.port == device.port);
    _devices.removeWhere((d) => d.host == device.host && d.port == device.port && d.isManual);
    _saveManualDevices();
    _safeNotify();
  }

  /// Discovers `_googlecast._tcp.local` receivers on the local network via mDNS.
  Future<void> startDiscovery({
    Duration duration = const Duration(seconds: 4),
  }) async {
    await stopDiscovery();
    _isScanning = true;
    _lastError = null;
    _devices.removeWhere((d) => !d.isManual);
    for (final manual in _manualDevices) {
      _upsertDevice(manual);
    }
    _safeNotify();

    try {
      await _hardwareChannel.invokeMethod('acquireMulticastLock');
    } catch (_) {}

    final instances = <String, _MdnsInstanceState>{};
    final hostIps = <String, String>{};

    void handlePacket(Uint8List datagram, String remoteIp) {
      final records = parseMdnsPacket(datagram);
      if (records.isEmpty) return;

      for (final rr in records) {
        if (rr.type == 12 && rr.ptrTarget != null) {
          // PTR -> Service Instance Name
          final inst = instances.putIfAbsent(
            rr.ptrTarget!.toLowerCase(),
            () => _MdnsInstanceState(instanceName: rr.ptrTarget!),
          );
          inst.fallbackIp ??= remoteIp;
        } else if (rr.type == 33 && rr.srvTarget != null) {
          final key = rr.name.toLowerCase();
          final inst = instances.putIfAbsent(
            key,
            () => _MdnsInstanceState(instanceName: rr.name),
          );
          inst.srvTarget = rr.srvTarget!.toLowerCase();
          inst.port = rr.srvPort > 0 ? rr.srvPort : 8009;
          inst.fallbackIp ??= remoteIp;
        } else if (rr.type == 16 && rr.txt.isNotEmpty) {
          final key = rr.name.toLowerCase();
          final inst = instances.putIfAbsent(
            key,
            () => _MdnsInstanceState(instanceName: rr.name),
          );
          inst.txt.addAll(rr.txt);
          inst.fallbackIp ??= remoteIp;
        } else if (rr.type == 1 && rr.ipv4 != null) {
          hostIps[rr.name.toLowerCase()] = rr.ipv4!;
        }
      }

      for (final inst in instances.values) {
        if (inst.port <= 0) continue;
        final ip = (inst.srvTarget != null ? hostIps[inst.srvTarget!] : null) ??
            inst.fallbackIp;
        if (ip == null || ip.isEmpty) continue;

        final fn = inst.txt['fn']?.trim();
        final id = inst.txt['id']?.trim();
        final md = inst.txt['md']?.trim();
        final ca = int.tryParse(inst.txt['ca'] ?? '') ?? 0;

        final defaultName = inst.instanceName.split('._googlecast').first;
        final device = ChromecastDeviceInfo(
          id: (id != null && id.isNotEmpty) ? id : '$ip:${inst.port}',
          friendlyName: (fn != null && fn.isNotEmpty)
              ? fn
              : (defaultName.isNotEmpty ? defaultName : 'Chromecast ($ip)'),
          modelName: (md != null && md.isNotEmpty) ? md : 'Chromecast',
          host: ip,
          port: inst.port,
          capabilities: ca,
        );
        _upsertDevice(device);
      }
    }

    try {
      final mdnsGroup = InternetAddress('224.0.0.251');
      final quPacket = buildMdnsPtrQuery('_googlecast._tcp.local', unicastReply: true);
      final qmPacket = buildMdnsPtrQuery('_googlecast._tcp.local', unicastReply: false);

      // 1. Ephemeral socket for unicast (QU) responses (works cleanly even when
      //    another daemon holds UDP 5353 on Windows/macOS).
      _unicastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _unicastSocket!.broadcastEnabled = true;
      _unicastSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _unicastSocket?.receive();
          if (dg != null) {
            handlePacket(dg.data, dg.address.address);
          }
        }
      });
      _unicastSocket!.send(quPacket, mdnsGroup, 5353);

      // 2. Multicast listener on 224.0.0.251:5353 when OS permits reuse.
      try {
        _multicastSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          5353,
          reuseAddress: true,
        );
        _multicastSocket!.multicastHops = 255;
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          try {
            _multicastSocket!.joinMulticast(mdnsGroup, iface);
          } catch (_) {}
        }
        try {
          _multicastSocket!.joinMulticast(mdnsGroup);
        } catch (_) {}
        _multicastSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _multicastSocket?.receive();
            if (dg != null) {
              handlePacket(dg.data, dg.address.address);
            }
          }
        });
        _multicastSocket!.send(qmPacket, mdnsGroup, 5353);
      } catch (e) {
        debugPrint('[ChromecastService] Port 5353 multicast bind skipped ($e); using QU socket');
      }

      // Send one follow-up query 800ms later to improve mDNS recall.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!_isScanning) return;
        try {
          _unicastSocket?.send(quPacket, mdnsGroup, 5353);
          _multicastSocket?.send(qmPacket, mdnsGroup, 5353);
        } catch (_) {}
      });

      _scanTimeoutTimer = Timer(duration, () {
        stopDiscovery();
      });
    } catch (e) {
      _lastError = 'Chromecast scan failed: $e';
      await stopDiscovery();
    }
  }

  Future<void> stopDiscovery() async {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    try {
      _unicastSocket?.close();
    } catch (_) {}
    _unicastSocket = null;
    try {
      _multicastSocket?.close();
    } catch (_) {}
    _multicastSocket = null;
    try {
      await _hardwareChannel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
    if (_isScanning) {
      _isScanning = false;
      _safeNotify();
    }
  }

  void _upsertDevice(ChromecastDeviceInfo device) {
    final idx = _devices.indexWhere(
      (d) =>
          (d.id == device.id && device.id.isNotEmpty) ||
          (d.host == device.host && d.port == device.port),
    );
    if (idx >= 0) {
      final prev = _devices[idx];
      _devices[idx] = ChromecastDeviceInfo(
        id: device.id,
        friendlyName: device.friendlyName,
        modelName: device.modelName,
        host: device.host,
        port: device.port,
        capabilities: device.capabilities != 0 ? device.capabilities : prev.capabilities,
        isManual: prev.isManual || device.isManual,
      );
    } else {
      _devices.add(device);
    }
    _safeNotify();
  }

  /// Connects via Cast V2 TLS and ensures the Default Media Receiver (`CC1AD845`)
  /// is active so media URLs can be loaded immediately.
  Future<bool> connect(ChromecastDeviceInfo device) async {
    if (_activeDevice == device && _socket != null && _transportId != null) {
      return true;
    }

    await disconnect();
    _isConnecting = true;
    _lastError = null;
    _safeNotify();

    try {
      final sock = await SecureSocket.connect(
        device.host,
        device.port,
        onBadCertificate: (_) => true, // Cast receivers use self-signed certs.
        timeout: const Duration(seconds: 6),
      );

      _socket = sock;
      _activeDevice = device;
      _transportId = null;
      _mediaSessionId = null;
      _rxBuffer.clear();
      _lastPongMs = DateTime.now().millisecondsSinceEpoch;

      _socketSub = sock.listen(
        _onSocketBytes,
        onError: (Object err) {
          debugPrint('[ChromecastService] Socket error: $err');
          _lastError = 'Cast connection lost: $err';
          disconnect();
        },
        onDone: () {
          debugPrint('[ChromecastService] Socket closed by receiver');
          disconnect();
        },
        cancelOnError: true,
      );

      // Virtual connection to receiver-0 + heartbeat keep-alive
      _sendJson(_nsConnection, 'receiver-0', {'type': 'CONNECT'});
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_socket == null) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastPongMs > 20000) {
          debugPrint('[ChromecastService] Heartbeat timeout');
          _lastError = 'Cast heartbeat timed out';
          disconnect();
          return;
        }
        _sendJson(_nsHeartbeat, 'receiver-0', {'type': 'PING'});
      });

      final launched = await _ensureMediaReceiverLaunched();
      _isConnecting = false;
      if (launched == null) {
        _lastError ??= 'Could not launch Cast Media Receiver on ${device.friendlyName}';
        await disconnect();
        return false;
      }

      // Query current volume state
      _sendJson(_nsReceiver, 'receiver-0', {
        'type': 'GET_STATUS',
        'requestId': _nextRequestId++,
      });

      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('[ChromecastService] Connect failed: $e');
      _lastError = 'Unable to connect to ${device.friendlyName}: $e';
      _isConnecting = false;
      await disconnect();
      return false;
    }
  }

  Future<String?> _ensureMediaReceiverLaunched() async {
    if (_transportId != null) return _transportId;
    final completer = Completer<String?>();
    _launchCompleter = completer;

    _sendJson(_nsReceiver, 'receiver-0', {
      'type': 'LAUNCH',
      'appId': _defaultMediaReceiverAppId,
      'requestId': _nextRequestId++,
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return _transportId;
    } finally {
      if (_launchCompleter == completer) {
        _launchCompleter = null;
      }
    }
  }

  /// Sends a `LOAD` command to the active Cast receiver.
  Future<bool> castMedia({
    required String url,
    required String contentType,
    required String title,
    String? artist,
    String? album,
    String? artworkUrl,
    double? durationSeconds,
    bool isLiveStream = false,
    double startPositionSeconds = 0.0,
  }) async {
    if (_activeDevice == null) return false;
    if (_socket == null || _transportId == null) {
      final ok = await connect(_activeDevice!);
      if (!ok) return false;
    }

    final transportId = _transportId;
    if (transportId == null) return false;

    final metadata = <String, dynamic>{
      'metadataType': 3, // MUSIC_TRACK
      'title': title,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
      if (album != null && album.isNotEmpty) 'albumName': album,
      if (artworkUrl != null && artworkUrl.isNotEmpty)
        'images': [
          {'url': artworkUrl}
        ],
    };

    final mediaInfo = <String, dynamic>{
      'contentId': url,
      'streamType': isLiveStream ? 'LIVE' : 'BUFFERED',
      'contentType': contentType,
      'metadata': metadata,
      if (!isLiveStream && durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds,
    };

    _isStreamingLiveTap = isLiveStream;
    _mediaSessionId = null;

    _sendJson(_nsMedia, transportId, {
      'type': 'LOAD',
      'requestId': _nextRequestId++,
      'autoplay': true,
      if (!isLiveStream && startPositionSeconds > 0)
        'currentTime': startPositionSeconds,
      'media': mediaInfo,
    });
    _safeNotify();
    return true;
  }

  Future<void> play() async {
    final transport = _transportId;
    final sid = _mediaSessionId;
    if (transport == null || sid == null) return;
    _sendJson(_nsMedia, transport, {
      'type': 'PLAY',
      'mediaSessionId': sid,
      'requestId': _nextRequestId++,
    });
  }

  Future<void> pause() async {
    final transport = _transportId;
    final sid = _mediaSessionId;
    if (transport == null || sid == null) return;
    _sendJson(_nsMedia, transport, {
      'type': 'PAUSE',
      'mediaSessionId': sid,
      'requestId': _nextRequestId++,
    });
  }

  Future<void> stop() async {
    final transport = _transportId;
    final sid = _mediaSessionId;
    if (transport == null || sid == null) return;
    _sendJson(_nsMedia, transport, {
      'type': 'STOP',
      'mediaSessionId': sid,
      'requestId': _nextRequestId++,
    });
  }

  Future<void> seek(double seconds) async {
    final transport = _transportId;
    final sid = _mediaSessionId;
    if (transport == null || sid == null) return;
    _sendJson(_nsMedia, transport, {
      'type': 'SEEK',
      'mediaSessionId': sid,
      'currentTime': math.max(0.0, seconds),
      'requestId': _nextRequestId++,
    });
  }

  Future<void> setVolume(double level) async {
    if (_socket == null) return;
    final clamped = level.clamp(0.0, 1.0);
    _volumeLevel = clamped;
    _sendJson(_nsReceiver, 'receiver-0', {
      'type': 'SET_VOLUME',
      'volume': {'level': clamped},
      'requestId': _nextRequestId++,
    });
    _safeNotify();
  }

  Future<void> setMuted(bool muted) async {
    if (_socket == null) return;
    _isMuted = muted;
    _sendJson(_nsReceiver, 'receiver-0', {
      'type': 'SET_VOLUME',
      'volume': {'muted': muted},
      'requestId': _nextRequestId++,
    });
    _safeNotify();
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_launchCompleter != null && !_launchCompleter!.isCompleted) {
      _launchCompleter!.complete(null);
    }
    _launchCompleter = null;

    if (_socket != null) {
      try {
        if (_transportId != null) {
          _sendJson(_nsConnection, _transportId!, {'type': 'CLOSE'});
        }
        _sendJson(_nsConnection, 'receiver-0', {'type': 'CLOSE'});
      } catch (_) {}
    }

    try {
      await _socketSub?.cancel();
    } catch (_) {}
    _socketSub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _rxBuffer.clear();

    final hadDevice = _activeDevice != null;
    _activeDevice = null;
    _transportId = null;
    _mediaSessionId = null;
    _isConnecting = false;
    _isStreamingLiveTap = false;

    if (hadDevice) {
      _safeNotify();
    }
  }

  void _sendJson(String namespace, String destinationId, Map<String, dynamic> body) {
    final sock = _socket;
    if (sock == null) return;
    try {
      final frame = encodeCastFrame(
        CastWireMessage(
          protocolVersion: 0,
          sourceId: 'sender-0',
          destinationId: destinationId,
          namespace: namespace,
          payloadType: 0,
          payloadUtf8: jsonEncode(body),
        ),
      );
      sock.add(frame);
    } catch (e) {
      debugPrint('[ChromecastService] Send error: $e');
    }
  }

  void _onSocketBytes(Uint8List chunk) {
    _rxBuffer.add(chunk);
    final accumulated = _rxBuffer.takeBytes();
    int offset = 0;

    while (accumulated.length - offset >= 4) {
      final bd = ByteData.sublistView(accumulated, offset, offset + 4);
      final frameLen = bd.getUint32(0, Endian.big);
      if (frameLen == 0 || frameLen > 1048576) {
        // Invalid frame length; drop accumulated framing noise.
        offset = accumulated.length;
        break;
      }
      if (accumulated.length - offset < 4 + frameLen) {
        break;
      }

      final payload = Uint8List.sublistView(
        accumulated,
        offset + 4,
        offset + 4 + frameLen,
      );
      offset += 4 + frameLen;

      final msg = decodeCastMessage(payload);
      if (msg != null) {
        _handleCastMessage(msg);
      }
    }

    if (offset < accumulated.length) {
      _rxBuffer.add(Uint8List.sublistView(accumulated, offset));
    }
  }

  void _handleCastMessage(CastWireMessage msg) {
    _lastPongMs = DateTime.now().millisecondsSinceEpoch;
    final utf8Str = msg.payloadUtf8;
    if (utf8Str == null || utf8Str.isEmpty) return;

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8Str);
      if (decoded is! Map) return;
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = json['type']?.toString();
    if (msg.namespace == _nsHeartbeat) {
      if (type == 'PING') {
        _sendJson(_nsHeartbeat, 'receiver-0', {'type': 'PONG'});
      }
      return;
    }

    if (msg.namespace == _nsReceiver && type == 'RECEIVER_STATUS') {
      final status = json['status'];
      if (status is Map) {
        final vol = status['volume'];
        if (vol is Map) {
          final lvl = (vol['level'] as num?)?.toDouble();
          final muted = vol['muted'] as bool?;
          if (lvl != null) _volumeLevel = lvl.clamp(0.0, 1.0);
          if (muted != null) _isMuted = muted;
        }

        final apps = status['applications'];
        if (apps is List) {
          for (final app in apps) {
            if (app is Map && app['appId'] == _defaultMediaReceiverAppId) {
              final tid = app['transportId']?.toString();
              if (tid != null && tid.isNotEmpty) {
                final isNew = _transportId != tid;
                _transportId = tid;
                if (isNew) {
                  _sendJson(_nsConnection, tid, {'type': 'CONNECT'});
                }
                if (_launchCompleter != null && !_launchCompleter!.isCompleted) {
                  _launchCompleter!.complete(tid);
                }
              }
            }
          }
        }
        _safeNotify();
      }
      return;
    }

    if (msg.namespace == _nsMedia && type == 'MEDIA_STATUS') {
      final statuses = json['status'];
      if (statuses is List && statuses.isNotEmpty) {
        final first = statuses.first;
        if (first is Map) {
          final sid = (first['mediaSessionId'] as num?)?.toInt();
          if (sid != null) {
            _mediaSessionId = sid;
          }
        }
      }
      return;
    }

    if (type == 'LAUNCH_ERROR') {
      _lastError = 'Cast receiver failed to launch: ${json['reason']}';
      if (_launchCompleter != null && !_launchCompleter!.isCompleted) {
        _launchCompleter!.complete(null);
      }
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopDiscovery();
    disconnect();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Pure-Dart Cast V2 Protobuf Codec (RFC-style wire format, zero dependencies)
  // ---------------------------------------------------------------------------

  /// Encodes a [CastWireMessage] prefixed with its 4-byte big-endian length.
  static Uint8List encodeCastFrame(CastWireMessage msg) {
    final payload = encodeCastMessage(msg);
    final frame = Uint8List(4 + payload.length);
    ByteData.view(frame.buffer).setUint32(0, payload.length, Endian.big);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  /// Encodes a [CastWireMessage] into raw `CastMessage` protobuf bytes.
  static Uint8List encodeCastMessage(CastWireMessage msg) {
    final out = BytesBuilder(copy: false);
    _writeVarintField(out, 1, msg.protocolVersion);
    _writeStringField(out, 2, msg.sourceId);
    _writeStringField(out, 3, msg.destinationId);
    _writeStringField(out, 4, msg.namespace);
    _writeVarintField(out, 5, msg.payloadType);
    if (msg.payloadUtf8 != null) {
      _writeStringField(out, 6, msg.payloadUtf8!);
    }
    if (msg.payloadBinary != null) {
      _writeBytesField(out, 7, msg.payloadBinary!);
    }
    return out.toBytes();
  }

  /// Decodes raw `CastMessage` protobuf bytes into [CastWireMessage].
  static CastWireMessage? decodeCastMessage(Uint8List bytes) {
    int offset = 0;
    int protocolVersion = 0;
    String sourceId = '';
    String destinationId = '';
    String namespace = '';
    int payloadType = 0;
    String? payloadUtf8;
    Uint8List? payloadBinary;

    while (offset < bytes.length) {
      final tagRes = _readVarint(bytes, offset);
      if (tagRes == null) return null;
      final tag = tagRes.$1;
      offset = tagRes.$2;

      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      if (wireType == 0) {
        final valRes = _readVarint(bytes, offset);
        if (valRes == null) return null;
        offset = valRes.$2;
        if (fieldNum == 1) protocolVersion = valRes.$1;
        if (fieldNum == 5) payloadType = valRes.$1;
      } else if (wireType == 2) {
        final lenRes = _readVarint(bytes, offset);
        if (lenRes == null) return null;
        final len = lenRes.$1;
        offset = lenRes.$2;
        if (len < 0 || offset + len > bytes.length) return null;
        final slice = Uint8List.sublistView(bytes, offset, offset + len);
        offset += len;

        switch (fieldNum) {
          case 2:
            sourceId = utf8.decode(slice, allowMalformed: true);
            break;
          case 3:
            destinationId = utf8.decode(slice, allowMalformed: true);
            break;
          case 4:
            namespace = utf8.decode(slice, allowMalformed: true);
            break;
          case 6:
            payloadUtf8 = utf8.decode(slice, allowMalformed: true);
            break;
          case 7:
            payloadBinary = Uint8List.fromList(slice);
            break;
        }
      } else if (wireType == 1) {
        if (offset + 8 > bytes.length) return null;
        offset += 8;
      } else if (wireType == 5) {
        if (offset + 4 > bytes.length) return null;
        offset += 4;
      } else {
        return null;
      }
    }

    return CastWireMessage(
      protocolVersion: protocolVersion,
      sourceId: sourceId,
      destinationId: destinationId,
      namespace: namespace,
      payloadType: payloadType,
      payloadUtf8: payloadUtf8,
      payloadBinary: payloadBinary,
    );
  }

  static void _writeVarint(BytesBuilder out, int value) {
    int v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v & 0x7F);
  }

  static void _writeVarintField(BytesBuilder out, int field, int value) {
    _writeVarint(out, (field << 3) | 0);
    _writeVarint(out, value);
  }

  static void _writeStringField(BytesBuilder out, int field, String value) {
    final encoded = utf8.encode(value);
    _writeVarint(out, (field << 3) | 2);
    _writeVarint(out, encoded.length);
    out.add(encoded);
  }

  static void _writeBytesField(BytesBuilder out, int field, Uint8List bytes) {
    _writeVarint(out, (field << 3) | 2);
    _writeVarint(out, bytes.length);
    out.add(bytes);
  }

  static (int, int)? _readVarint(Uint8List bytes, int offset) {
    int result = 0;
    int shift = 0;
    while (offset < bytes.length && shift < 64) {
      final b = bytes[offset++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return (result, offset);
      shift += 7;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pure-Dart mDNS Query Builder & RFC 1035 Response Parser
  // ---------------------------------------------------------------------------

  /// Builds a standard DNS PTR query for [serviceName] (e.g. `_googlecast._tcp.local`).
  static Uint8List buildMdnsPtrQuery(
    String serviceName, {
    bool unicastReply = true,
  }) {
    final out = BytesBuilder(copy: false);
    // Transaction ID (0), Flags (0), Questions (1), Answers/Auth/Add (0)
    out.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    for (final label in serviceName.split('.').where((s) => s.isNotEmpty)) {
      final utf = utf8.encode(label);
      out.addByte(utf.length);
      out.add(utf);
    }
    out.addByte(0x00); // Root label
    out.add([0x00, 0x0C]); // QTYPE = PTR (12)
    out.add([unicastReply ? 0x80 : 0x00, 0x01]); // QCLASS = IN (+ QU bit)
    return out.toBytes();
  }

  /// Parses Answer, Authority, and Additional records from a raw mDNS packet.
  static List<MdnsParsedRecord> parseMdnsPacket(Uint8List data) {
    if (data.length < 12) return const [];
    final bd = ByteData.sublistView(data);
    final qdCount = bd.getUint16(4, Endian.big);
    final anCount = bd.getUint16(6, Endian.big);
    final nsCount = bd.getUint16(8, Endian.big);
    final arCount = bd.getUint16(10, Endian.big);

    int offset = 12;
    for (int i = 0; i < qdCount; i++) {
      final nameRes = _readDnsName(data, offset);
      if (nameRes == null) return const [];
      offset = nameRes.$2 + 4; // QTYPE (2) + QCLASS (2)
      if (offset > data.length) return const [];
    }

    final totalRRs = anCount + nsCount + arCount;
    final out = <MdnsParsedRecord>[];

    for (int i = 0; i < totalRRs && offset < data.length; i++) {
      final nameRes = _readDnsName(data, offset);
      if (nameRes == null) break;
      final rrName = nameRes.$1;
      offset = nameRes.$2;
      if (offset + 10 > data.length) break;

      final type = bd.getUint16(offset, Endian.big);
      final rdLength = bd.getUint16(offset + 8, Endian.big);
      offset += 10;
      if (offset + rdLength > data.length) break;

      final rdataStart = offset;
      final rdataEnd = offset + rdLength;

      if (type == 12) {
        // PTR
        final targetRes = _readDnsName(data, rdataStart);
        if (targetRes != null) {
          out.add(MdnsParsedRecord(name: rrName, type: type, ptrTarget: targetRes.$1));
        }
      } else if (type == 33 && rdLength >= 6) {
        // SRV
        final port = bd.getUint16(rdataStart + 4, Endian.big);
        final targetRes = _readDnsName(data, rdataStart + 6);
        if (targetRes != null) {
          out.add(
            MdnsParsedRecord(
              name: rrName,
              type: type,
              srvTarget: targetRes.$1,
              srvPort: port,
            ),
          );
        }
      } else if (type == 16) {
        // TXT
        final txt = <String, String>{};
        int pTxt = rdataStart;
        while (pTxt < rdataEnd) {
          final l = data[pTxt++];
          if (pTxt + l > rdataEnd) break;
          final entry = utf8.decode(
            Uint8List.sublistView(data, pTxt, pTxt + l),
            allowMalformed: true,
          );
          pTxt += l;
          final eq = entry.indexOf('=');
          if (eq > 0) {
            txt[entry.substring(0, eq)] = entry.substring(eq + 1);
          }
        }
        out.add(MdnsParsedRecord(name: rrName, type: type, txt: txt));
      } else if (type == 1 && rdLength == 4) {
        // A (IPv4)
        final ip =
            '${data[rdataStart]}.${data[rdataStart + 1]}.${data[rdataStart + 2]}.${data[rdataStart + 3]}';
        out.add(MdnsParsedRecord(name: rrName, type: type, ipv4: ip));
      }

      offset = rdataEnd;
    }

    return out;
  }

  static (String, int)? _readDnsName(Uint8List data, int offset) {
    final labels = <String>[];
    int cur = offset;
    int nextOffsetAfterName = -1;
    int jumps = 0;

    while (cur < data.length && jumps < 32) {
      final len = data[cur];
      if (len == 0) {
        if (nextOffsetAfterName < 0) nextOffsetAfterName = cur + 1;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        if (cur + 1 >= data.length) return null;
        if (nextOffsetAfterName < 0) nextOffsetAfterName = cur + 2;
        final ptr = ((len & 0x3F) << 8) | data[cur + 1];
        if (ptr >= data.length) return null;
        cur = ptr;
        jumps++;
        continue;
      }
      cur++;
      if (cur + len > data.length) return null;
      labels.add(
        utf8.decode(Uint8List.sublistView(data, cur, cur + len), allowMalformed: true),
      );
      cur += len;
    }

    if (nextOffsetAfterName < 0) return null;
    return (labels.join('.'), nextOffsetAfterName);
  }
}

class _MdnsInstanceState {
  final String instanceName;
  String? srvTarget;
  int port = 8009;
  String? fallbackIp;
  final Map<String, String> txt = {};

  _MdnsInstanceState({required this.instanceName});
}
