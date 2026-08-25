import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_media_server.dart';

/// Bridge between the DLNA renderer and the app's player engine.
/// Implemented by the app layer so this service stays UI/engine agnostic.
abstract class DlnaRendererBridge {
  /// Replace current queue with [url] and start playing.
  Future<void> loadUrl(String url, {String? title, String? artist});

  void play();
  void pause();
  void stop();
  Future<void> seek(Duration position);

  /// gain in 0.0..1.0
  void setVolume(double gain);

  ({bool playing, Duration position, Duration duration}) snapshot();
}

class _GenaSubscription {
  final String sid;
  final Uri callback;
  final String service;
  int seq = 0;

  _GenaSubscription(this.sid, this.callback, this.service);
}

/// Turns SautiPlay into a UPnP AVTransport MediaRenderer so other devices
/// (phones, PCs, smart TVs) can discover it and cast audio TO it.
///
/// Pure Dart: SSDP responder (UDP 1900) + HTTP server serving the device
/// description, SCPDs, AVTransport / RenderingControl / ConnectionManager
/// SOAP control endpoints and minimal GENA eventing.
class DlnaRendererService extends ChangeNotifier {
  static final DlnaRendererService instance = DlnaRendererService._internal();
  DlnaRendererService._internal();

  static const MethodChannel _hardwareChannel =
      MethodChannel('com.wambugu.sautiflow/hardware');

  static const String _upnpMulticastV4 = '239.255.255.250';
  static const int _ssdpPort = 1900;
  static const String _serverSig = 'SautiPlay/1.0 UPnP/1.0 DLNADOC/1.50';

  DlnaRendererBridge? bridge;
  bool _running = false;
  String friendlyName = 'SautiPlay';
  String _uuid = '';

  HttpServer? _httpServer;
  RawDatagramSocket? _ssdpSocket;
  StreamSubscription<RawSocketEvent>? _ssdpSub;
  Timer? _aliveTimer;
  int _httpPort = 0;
  String _baseUri = '';

  // Transport state machine
  String _transportState = 'NO_MEDIA_PRESENT';
  String _currentUri = '';
  String _currentTitle = '';
  double _volumePercent = 100;
  bool _muted = false;
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  final Map<String, List<_GenaSubscription>> _eventSubscribers = {
    'AVTransport': <_GenaSubscription>[],
    'RenderingControl': <_GenaSubscription>[],
  };
  final HttpClient _notifyClient = HttpClient();

  bool get isRunning => _running;
  String get transportState => _transportState;

  Future<void> configure({required DlnaRendererBridge bridge}) async {
    this.bridge = bridge;
    final prefs = await SharedPreferences.getInstance();
    _uuid = prefs.getString('dlna_renderer_uuid') ?? _generateUuid();
    await prefs.setString('dlna_renderer_uuid', _uuid);
  }

  Future<void> setFriendlyName(String name) async {
    friendlyName = name.trim().isEmpty ? 'SautiPlay' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dlna_renderer_friendly_name', friendlyName);
    notifyListeners();
  }

  /// Restarts with the persisted friendly name (call once at app boot).
  Future<void> restoreName() async {
    final prefs = await SharedPreferences.getInstance();
    friendlyName = prefs.getString('dlna_renderer_friendly_name') ?? 'SautiPlay';
  }

  Future<bool> start() async {
    if (_running) return true;
    if (bridge == null) {
      debugPrint('[DlnaRenderer] Cannot start: bridge not configured');
      return false;
    }
    if (_uuid.isEmpty) await configure(bridge: bridge!);

    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _httpPort = _httpServer!.port;
      _httpServer!.listen(
        _handleHttp,
        onError: (e) => debugPrint('[DlnaRenderer] HTTP error: $e'),
      );
    } catch (e) {
      debugPrint('[DlnaRenderer] Failed to bind HTTP server: $e');
      return false;
    }

    final ip = await LocalMediaServer.bestLanIpv4();
    if (ip == null) {
      debugPrint('[DlnaRenderer] No usable LAN IPv4 address found');
      stopInternal();
      return false;
    }
    _baseUri = 'http://$ip:$_httpPort';

    try {
      final reusePort =
          Platform.isAndroid || Platform.isLinux || Platform.isMacOS;
      _ssdpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _ssdpPort,
        reuseAddress: true,
        reusePort: reusePort,
      );
      _ssdpSocket!.joinMulticast(InternetAddress(_upnpMulticastV4));
      _ssdpSub = _ssdpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        while (true) {
          final dgram = _ssdpSocket!.receive();
          if (dgram == null) break;
          _onDatagram(dgram);
        }
      });
    } catch (e) {
      debugPrint('[DlnaRenderer] SSDP socket bind failed: $e');
      stopInternal();
      return false;
    }

    if (Platform.isAndroid) {
      try {
        await _hardwareChannel.invokeMethod('acquireMulticastLock');
      } catch (_) {}
    }

    _running = true;
    notifyListeners();

    unawaited(_sendAlive());
    _aliveTimer?.cancel();
    _aliveTimer = Timer.periodic(
        const Duration(seconds: 120), (_) => unawaited(_sendAlive()));
    debugPrint('[DlnaRenderer] Started as "$friendlyName" at $_baseUri');
    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _sendByeBye();
    stopInternal();
    notifyListeners();
  }

  void stopInternal() {
    _running = false;
    _aliveTimer?.cancel();
    _aliveTimer = null;
    _ssdpSub?.cancel();
    _ssdpSub = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;
    _httpServer?.close(force: true);
    _httpServer = null;
    for (final list in _eventSubscribers.values) {
      list.clear();
    }
    if (Platform.isAndroid) {
      try {
        _hardwareChannel.invokeMethod('releaseMulticastLock');
      } catch (_) {}
    }
    debugPrint('[DlnaRenderer] Stopped');
  }

  @override
  void dispose() {
    stopInternal();
    super.dispose();
  }

  // ── Transport helpers ─────────────────────────────────────────────────────

  Future<({bool playing, Duration position, Duration duration})>
      readSnapshot() async {
    final snap = bridge?.snapshot();
    if (snap == null) {
      return (
        playing: false,
        position: _lastKnownPosition,
        duration: _lastKnownDuration,
      );
    }
    _lastKnownPosition = snap.position;
    if (snap.duration > Duration.zero) _lastKnownDuration = snap.duration;
    return snap;
  }

  void setTransportState(String state) {
    if (_transportState == state) return;
    _transportState = state;
    unawaited(_notifyEvent('AVTransport', {
      'TransportState': state,
    }));
  }

  // ── SSDP ──────────────────────────────────────────────────────────────────

  List<String> get _usnTargets => [
        'upnp:rootdevice',
        'uuid:$_uuid',
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'urn:schemas-upnp-org:service:RenderingControl:1',
        'urn:schemas-upnp-org:service:ConnectionManager:1',
      ];

  void _onDatagram(Datagram dgram) {
    try {
      final msg = String.fromCharCodes(dgram.data).trim();
      if (!msg.startsWith('M-SEARCH')) return;

      final st = _headerValue(msg, 'ST');
      if (st.isEmpty) return;

      final targets = <String>[];
      if (st == 'ssdp:all') {
        targets.addAll(_usnTargets.where((t) => t != 'uuid:$_uuid'));
        targets.add('uuid:$_uuid');
      } else if (_usnTargets.contains(st)) {
        targets.add(st);
      }
      if (targets.isEmpty) return;

      for (final target in targets) {
        final usn =
            target == 'uuid:$_uuid' ? target : 'uuid:$_uuid::$target';
        final reply = StringBuffer()
          ..write('HTTP/1.1 200 OK\r\n')
          ..write('CACHE-CONTROL: max-age=1800\r\n')
          ..write('EXT:\r\n')
          ..write('LOCATION: $_baseUri/description.xml\r\n')
          ..write('SERVER: $_serverSig\r\n')
          ..write('ST: $target\r\n')
          ..write('USN: $usn\r\n\r\n');
        final delayMs = Random().nextInt(150) + 20;
        Future.delayed(Duration(milliseconds: delayMs), () {
          try {
            _ssdpSocket?.send(utf8.encode(reply.toString()), dgram.address,
                dgram.port);
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('[DlnaRenderer] M-SEARCH handling error: $e');
    }
  }

  Future<void> _sendAlive() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      for (final target in _usnTargets) {
        final usn = target == 'uuid:$_uuid' ? target : 'uuid:$_uuid::$target';
        final msg = StringBuffer()
          ..write('NOTIFY * HTTP/1.1\r\n')
          ..write('HOST: $_upnpMulticastV4:$_ssdpPort\r\n')
          ..write('CACHE-CONTROL: max-age=1800\r\n')
          ..write('LOCATION: $_baseUri/description.xml\r\n')
          ..write('NT: $target\r\n')
          ..write('NTS: ssdp:alive\r\n')
          ..write('SERVER: $_serverSig\r\n')
          ..write('USN: $usn\r\n\r\n');
        try {
          _ssdpSocket?.send(
              utf8.encode(msg.toString()),
              InternetAddress(_upnpMulticastV4),
              _ssdpPort);
        } catch (_) {}
      }
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> _sendByeBye() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      for (final target in _usnTargets) {
        final usn = target == 'uuid:$_uuid' ? target : 'uuid:$_uuid::$target';
        final msg = StringBuffer()
          ..write('NOTIFY * HTTP/1.1\r\n')
          ..write('HOST: $_upnpMulticastV4:$_ssdpPort\r\n')
          ..write('NT: $target\r\n')
          ..write('NTS: ssdp:byebye\r\n')
          ..write('USN: $usn\r\n\r\n');
        try {
          _ssdpSocket?.send(
              utf8.encode(msg.toString()),
              InternetAddress(_upnpMulticastV4),
              _ssdpPort);
        } catch (_) {}
      }
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  // ── HTTP server ───────────────────────────────────────────────────────────

  Future<void> _handleHttp(HttpRequest req) async {
    try {
      final path = req.uri.path.toLowerCase();
      switch (req.method) {
        case 'GET':
        case 'HEAD':
          if (path.endsWith('/description.xml') || path == '/description.xml') {
            await _replyXml(req, _deviceDescriptionXml());
          } else if (path.contains('/scpd/avtransport')) {
            await _replyXml(req, _avTransportScpd());
          } else if (path.contains('/scpd/renderingcontrol')) {
            await _replyXml(req, _renderingControlScpd());
          } else if (path.contains('/scpd/connectionmanager')) {
            await _replyXml(req, _connectionManagerScpd());
          } else if (path.contains('/icon.png') || path.contains('/icon')) {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          } else {
            await _replyXml(req, _deviceDescriptionXml());
          }
          break;
        case 'POST':
          await _handleSoap(req);
          break;
        case 'SUBSCRIBE':
          await _handleSubscribe(req);
          break;
        case 'UNSUBSCRIBE':
          await _handleUnsubscribe(req);
          break;
        default:
          req.response.statusCode = HttpStatus.methodNotAllowed;
          await req.response.close();
      }
    } catch (e) {
      debugPrint('[DlnaRenderer] HTTP handler error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  String _serviceFromPath(HttpRequest req) {
    final p = req.uri.path.toLowerCase();
    if (p.contains('renderingcontrol')) return 'RenderingControl';
    if (p.contains('connectionmanager')) return 'ConnectionManager';
    return 'AVTransport';
  }

  Future<void> _handleSubscribe(HttpRequest req) async {
    final service = _serviceFromPath(req);
    final sidHeader = _headerCase(req.headers.value('SID'), '');
    final callbackRaw = req.headers.value('CALLBACK');

    String sid;
    if (sidHeader.isNotEmpty) {
      // Renewal
      sid = sidHeader;
    } else {
      if (callbackRaw == null || !callbackRaw.contains('http://')) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      final match = RegExp(r'<(http://[^>]+)>').firstMatch(callbackRaw);
      if (match == null) {
        req.response.statusCode = HttpStatus.preconditionFailed;
        await req.response.close();
        return;
      }
      sid = 'uuid:${_generateUuid()}';
      _eventSubscribers[service]!.add(_GenaSubscription(
        sid,
        Uri.parse(match.group(1)!),
        service,
      ));
    }

    req.response.headers.set('SID', sid);
    req.response.headers.set('TIMEOUT', 'Second-1800');
    req.response.statusCode = HttpStatus.ok;
    await req.response.close();

    if (sidHeader.isEmpty) {
      // Send initial full-state event
      unawaited(_initialEvent(service, sid));
    }
  }

  Future<void> _handleUnsubscribe(HttpRequest req) async {
    final service = _serviceFromPath(req);
    final sid = _headerCase(req.headers.value('SID'), '');
    _eventSubscribers[service]?.removeWhere((s) => s.sid == sid);
    req.response.statusCode = HttpStatus.ok;
    await req.response.close();
  }

  Future<void> _initialEvent(String service, String sid) async {
    Map<String, String> props;
    if (service == 'AVTransport') {
      props = {'TransportState': _transportState};
    } else {
      props = {
        'Volume': _volumePercent.round().toString(),
        'Mute': _muted ? '1' : '0',
      };
    }
    await _pushEvent(service, sid, props);
  }

  Future<void> _notifyEvent(String service, Map<String, String> props) async {
    final subs = List<_GenaSubscription>.from(_eventSubscribers[service] ?? []);
    for (final sub in subs) {
      await _pushEvent(service, sub.sid, props);
    }
  }

  Future<void> _pushEvent(
      String service, String sid, Map<String, String> props) async {
    final subs = _eventSubscribers[service];
    if (subs == null) return;
    final sub = subs.firstWhere(
      (s) => s.sid == sid,
      orElse: () => _GenaSubscription('', Uri(), ''),
    );
    if (sub.callback.toString().isEmpty) return;

    final ns = service == 'RenderingControl'
        ? 'urn:schemas-upnp-org:metadata-1-0/RCS/'
        : 'urn:schemas-upnp-org:metadata-1-0/AVT/';
    final inner = StringBuffer()
      ..write('<InstanceID val="0">');
    props.forEach((k, v) {
      inner.write('<$k val="${xmlEscape(v)}"/>');
    });
    inner.write('</InstanceID>');
    final lastChange =
        '<Event xmlns="$ns">${inner.toString()}</Event>';

    final body = StringBuffer()
      ..write('<?xml version="1.0"?>\r\n')
      ..write('<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">')
      ..write('<e:property><LastChange>')
      ..write(xmlEscape(lastChange))
      ..write('</LastChange></e:property></e:propertyset>');

    try {
      final req = await _notifyClient
          .postUrl(sub.callback)
          .timeout(const Duration(seconds: 5));
      req.headers.set('CONTENT-TYPE', 'text/xml; charset="utf-8"');
      req.headers.set('NT', 'upnp:event');
      req.headers.set('NTS', 'upnp:propchange');
      req.headers.set('SID', sub.sid);
      req.headers.set('SEQ', '${sub.seq}');
      req.add(utf8.encode(body.toString()));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      sub.seq++;
      if (res.statusCode >= 400) {
        subs.remove(sub);
      }
    } catch (_) {
      // Dead subscriber; drop it so we don't retry forever.
      subs.remove(sub);
    }
  }

  Future<void> _replyXml(HttpRequest req, String xml,
      {int status = HttpStatus.ok}) async {
    req.response.statusCode = status;
    req.response.headers.contentType =
        ContentType.parse('text/xml; charset="utf-8"');
    req.response.headers.set('CONTENT-LENGTH',
        utf8.encode(xml).length.toString());
    if (req.method == 'HEAD') {
      await req.response.close();
      return;
    }
    req.response.write(xml);
    await req.response.close();
  }

  // ── SOAP ──────────────────────────────────────────────────────────────────

  Future<void> _handleSoap(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final service = _serviceFromPath(req);

    var soapAction = req.headers.value('SOAPACTION') ?? '';
    if (soapAction.startsWith('"') && soapAction.endsWith('"')) {
      soapAction = soapAction.substring(1, soapAction.length - 1);
    }
    final action = soapAction.split('#').last.trim();

    final resp = await _dispatchAction(action, service, body);
    if (resp == null) {
      final fault = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><s:Fault><faultcode>s:Client</faultcode>
<faultstring>UPnPError</faultstring>
<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
<errorCode>401</errorCode><errorDescription>Invalid Action</errorDescription>
</UPnPError></detail></s:Fault></s:Body></s:Envelope>''';
      req.response.statusCode = HttpStatus.internalServerError;
      await _replyXml(req, fault);
      return;
    }
    final envelope =
        '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>$resp</s:Body></s:Envelope>';
    await _replyXml(req, envelope);
  }

  Future<String?> _dispatchAction(
      String action, String service, String body) async {
    if (service == 'ConnectionManager') {
      return _connectionManagerAction(action);
    }
    if (service == 'RenderingControl') {
      return _renderingControlAction(action, body);
    }
    return _avTransportAction(action, body);
  }

  Future<String?> _avTransportAction(
      String action, String body) async {
    switch (action) {
      case 'SetAVTransportURI':
        final uri = extractTag(body, 'CurrentURI');
        final meta = extractTag(body, 'CurrentURIMetaData');
        final title = meta == null ? null : extractTag(meta, 'title');
        if (uri != null && uri.isNotEmpty) {
          _currentUri = xmlUnescape(uri);
          _currentTitle = title == null
              ? _guessTitleFromUri(_currentUri)
              : xmlUnescape(title);
          setTransportState('TRANSITIONING');
          await bridge?.loadUrl(
            _currentUri,
            title: _currentTitle,
          );
          setTransportState('PLAYING');
        }
        return _soapResponse('SetAVTransportURI', 'AVTransport', '');

      case 'Play':
        bridge?.play();
        setTransportState('PLAYING');
        return _soapResponse('Play', 'AVTransport', '');

      case 'Pause':
        bridge?.pause();
        setTransportState('PAUSED_PLAYBACK');
        return _soapResponse('Pause', 'AVTransport', '');

      case 'Stop':
        bridge?.stop();
        setTransportState('STOPPED');
        return _soapResponse('Stop', 'AVTransport', '');

      case 'Seek':
        final unit = extractTag(body, 'Unit') ?? '';
        final target = extractTag(body, 'Target') ?? '';
        if (unit.contains('TIME') || unit.contains('time')) {
          final secs = parseUpnpTime(target);
          if (secs != null) {
            await bridge?.seek(Duration(milliseconds: secs));
          }
        }
        return _soapResponse('Seek', 'AVTransport', '');

      case 'GetTransportInfo':
        return _soapResponse('GetTransportInfo', 'AVTransport',
            '<CurrentTransportState>$_transportState</CurrentTransportState>'
            '<CurrentTransportStatus>OK</CurrentTransportStatus>'
            '<CurrentSpeed>1</CurrentSpeed>');

      case 'GetPositionInfo':
        final snap = await readSnapshot();
        final durStr = formatUpnpTime(snap.duration);
        final posStr = formatUpnpTime(snap.position);
        return _soapResponse('GetPositionInfo', 'AVTransport',
            '<Track>1</Track>'
            '<TrackDuration>${snap.duration > Duration.zero ? durStr : "00:00:00"}</TrackDuration>'
            '<TrackMetaData>${xmlEscape(didlFor(_currentTitle, _currentUri))}</TrackMetaData>'
            '<TrackURI>${xmlEscape(_currentUri)}</TrackURI>'
            '<RelTime>$posStr</RelTime>'
            '<AbsTime>$posStr</AbsTime>');

      case 'GetMediaInfo':
        return _soapResponse('GetMediaInfo', 'AVTransport',
            '<NrTracks>1</NrTracks>'
            '<MediaDuration>00:00:00</MediaDuration>'
            '<CurrentURI>${xmlEscape(_currentUri)}</CurrentURI>'
            '<CurrentURIMetaData>${xmlEscape(didlFor(_currentTitle, _currentUri))}</CurrentURIMetaData>'
            '<NextURI></NextURI><NextURIMetaData></NextURIMetaData>'
            '<PlayMedium>NETWORK</PlayMedium><RecordMedium>NOT_IMPLEMENTED</RecordMedium>'
            '<WriteStatus>NOT_IMPLEMENTED</WriteStatus>');

      case 'GetDeviceCapabilities':
        return _soapResponse('GetDeviceCapabilities', 'AVTransport',
            '<PlayMedia>Network</PlayMedia>'
            '<RecMedia>NotImplemented</RecMedia>'
            '<RecQualityModes>NotImplemented</RecQualityModes>');

      case 'GetTransportSettings':
        return _soapResponse('GetTransportSettings', 'AVTransport',
            '<PlayMode>NORMAL</PlayMode>'
            '<RecQualityMode>NOT_IMPLEMENTED</RecQualityMode>');

      case 'GetCurrentTransportActions':
        return _soapResponse('GetCurrentTransportActions', 'AVTransport',
            '<Actions>Play,Pause,Stop,Seek</Actions>');

      default:
        return null;
    }
  }

  Future<String?> _renderingControlAction(
      String action, String body) async {
    switch (action) {
      case 'SetVolume':
        final v = int.tryParse(extractTag(body, 'DesiredVolume') ?? '');
        if (v != null) {
          _volumePercent = v.clamp(0, 100).toDouble();
          bridge?.setVolume(_volumePercent / 100.0);
        }        return _soapResponse('SetVolume', 'RenderingControl', '');
      case 'GetVolume':
        return _soapResponse('GetVolume', 'RenderingControl',
            '<CurrentVolume>${_volumePercent.round()}</CurrentVolume>');
      case 'SetMute':
        _muted = (extractTag(body, 'DesiredMute') ?? '') == '1';
        bridge?.setVolume(_muted ? 0.0 : _volumePercent / 100.0);        return _soapResponse('SetMute', 'RenderingControl', '');
      case 'GetMute':
        return _soapResponse('GetMute', 'RenderingControl',
            '<CurrentMute>${_muted ? '1' : '0'}</CurrentMute>');
      default:
        return null;
    }
  }

  String? _connectionManagerAction(String action) {
    switch (action) {
      case 'GetProtocolInfo':
        const sink = 'http-get:*:audio/mpeg:*,http-get:*:audio/flac:*,'
            'http-get:*:audio/x-wav:*,http-get:*:audio/wav:*,'
            'http-get:*:audio/aac:*,http-get:*:audio/mp4:*,'
            'http-get:*:audio/ogg:*,http-get:*:application/ogg:*';
        return _soapResponse('GetProtocolInfo', 'ConnectionManager',
            '<Source></Source><Sink>${xmlEscape(sink)}</Sink>');
      case 'GetCurrentConnectionIDs':
        return _soapResponse('GetCurrentConnectionIDs',
            'ConnectionManager', '<ConnectionIDs>0</ConnectionIDs>');
      case 'GetCurrentConnectionInfo':
        return _soapResponse('GetCurrentConnectionInfo',
            'ConnectionManager',
            '<RcsID>0</RcsID><AVTransportID>0</AVTransportID>'
            '<ProtocolInfo></ProtocolInfo><PeerConnectionManager></PeerConnectionManager>'
            '<PeerConnectionID>-1</PeerConnectionID>'
            '<Direction>Input</Direction><Status>OK</Status>');
      default:
        return null;
    }
  }

  // ── XML documents ─────────────────────────────────────────────────────────

  String _deviceDescriptionXml() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <URLBase>$_baseUri</URLBase>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>${xmlEscape(friendlyName)}</friendlyName>
    <manufacturer>SautiPlay</manufacturer>
    <manufacturerURL>https://sautiplay.app</manufacturerURL>
    <modelDescription>SautiPlay Hi-Fi Audio Renderer</modelDescription>
    <modelName>SautiPlay Audio Player</modelName>
    <modelNumber>1.0</modelNumber>
    <UDN>uuid:$_uuid</UDN>
    <dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMR-1.50</dlna:X_DLNADOC>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <SCPDURL>/scpd/AVTransport.xml</SCPDURL>
        <controlURL>/control/AVTransport</controlURL>
        <eventSubURL>/event/AVTransport</eventSubURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
        <SCPDURL>/scpd/RenderingControl.xml</SCPDURL>
        <controlURL>/control/RenderingControl</controlURL>
        <eventSubURL>/event/RenderingControl</eventSubURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
        <SCPDURL>/scpd/ConnectionManager.xml</SCPDURL>
        <controlURL>/control/ConnectionManager</controlURL>
        <eventSubURL>/event/ConnectionManager</eventSubURL>
      </service>
    </serviceList>
  </device>
</root>''';
  }

  String _avTransportScpd() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
${_scpdAction('SetAVTransportURI', ['InstanceID', 'CurrentURI', 'CurrentURIMetaData'], [])}
${_scpdAction('Play', ['InstanceID'], [])}
${_scpdAction('Pause', ['InstanceID'], [])}
${_scpdAction('Stop', ['InstanceID'], [])}
${_scpdAction('Seek', ['InstanceID', 'Unit', 'Target'], [])}
${_scpdAction('GetPositionInfo', ['InstanceID'], ['Track', 'TrackDuration', 'TrackMetaData', 'TrackURI', 'RelTime', 'AbsTime'])}
${_scpdAction('GetTransportInfo', ['InstanceID'], ['CurrentTransportState', 'CurrentTransportStatus', 'CurrentSpeed'])}
${_scpdAction('GetMediaInfo', ['InstanceID'], ['NrTracks', 'MediaDuration', 'CurrentURI', 'CurrentURIMetaData', 'NextURI', 'NextURIMetaData', 'PlayMedium', 'RecordMedium', 'WriteStatus'])}
${_scpdAction('GetDeviceCapabilities', ['InstanceID'], ['PlayMedia', 'RecMedia', 'RecQualityModes'])}
${_scpdAction('GetTransportSettings', ['InstanceID'], ['PlayMode', 'RecQualityMode'])}
${_scpdAction('GetCurrentTransportActions', ['InstanceID'], ['Actions'])}
</actionList>
<serviceStateTable>
${_scpdState('TransportState', 'string')}
${_scpdState('TransportStatus', 'string')}
${_scpdState('PlaybackStorageMedium', 'string')}
${_scpdState('CurrentTrack', 'ui4')}
${_scpdState('NumberOfTracks', 'ui4')}
${_scpdState('CurrentTrackDuration', 'string')}
${_scpdState('CurrentMediaDuration', 'string')}
${_scpdState('CurrentTrackURI', 'string')}
${_scpdState('CurrentTrackMetaData', 'string')}
${_scpdState('AVTransportURI', 'string')}
${_scpdState('AVTransportURIMetaData', 'string')}
${_scpdState('RelativeTimePosition', 'string')}
${_scpdState('AbsoluteTimePosition', 'string')}
${_scpdState('A_ARG_TYPE_InstanceID', 'ui4')}
${_scpdState('A_ARG_TYPE_SeekMode', 'string')}
${_scpdState('A_ARG_TYPE_SeekTarget', 'string')}
</serviceStateTable>
</scpd>''';
  }

  String _renderingControlScpd() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
${_scpdAction('GetVolume', ['InstanceID', 'Channel'], ['CurrentVolume'])}
${_scpdAction('SetVolume', ['InstanceID', 'Channel', 'DesiredVolume'], [])}
${_scpdAction('GetMute', ['InstanceID', 'Channel'], ['CurrentMute'])}
${_scpdAction('SetMute', ['InstanceID', 'Channel', 'DesiredMute'], [])}
</actionList>
<serviceStateTable>
${_scpdState('Volume', 'ui2')}
${_scpdState('Mute', 'boolean')}
${_scpdState('A_ARG_TYPE_InstanceID', 'ui4')}
${_scpdState('A_ARG_TYPE_Channel', 'string')}
${_scpdState('A_ARG_TYPE_Volume', 'ui2')}
${_scpdState('A_ARG_TYPE_Mute', 'boolean')}
</serviceStateTable>
</scpd>''';
  }

  String _connectionManagerScpd() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
${_scpdAction('GetProtocolInfo', [], ['Source', 'Sink'])}
${_scpdAction('GetCurrentConnectionIDs', [], ['ConnectionIDs'])}
${_scpdAction('GetCurrentConnectionInfo', ['ConnectionID'], ['RcsID', 'AVTransportID', 'ProtocolInfo', 'PeerConnectionManager', 'PeerConnectionID', 'Direction', 'Status'])}
</actionList>
<serviceStateTable>
${_scpdState('SourceProtocolInfo', 'string')}
${_scpdState('SinkProtocolInfo', 'string')}
${_scpdState('CurrentConnectionIDs', 'string')}
${_scpdState('A_ARG_TYPE_ConnectionID', 'i4')}
${_scpdState('A_ARG_TYPE_ConnectionStatus', 'string')}
${_scpdState('A_ARG_TYPE_Direction', 'string')}
${_scpdState('A_ARG_TYPE_ProtocolInfo', 'string')}
</serviceStateTable>
</scpd>''';
  }

  String _scpdAction(
      String name, List<String> inArgs, List<String> outArgs) {
    final args = StringBuffer();
    for (final a in inArgs) {
      args.write('<argument><name>$a</name><direction>in</direction>'
          '<relatedStateVariable>A_ARG_TYPE_$a</relatedStateVariable></argument>');
    }
    for (final a in outArgs) {
      args.write('<argument><name>$a</name><direction>out</direction>'
          '<relatedStateVariable>A_ARG_TYPE_$a</relatedStateVariable></argument>');
    }
    return '<action><name>$name</name><argumentList>$args</argumentList></action>';
  }

  String _scpdState(String name, String dataType) =>
      '<stateVariable sendEvents="no"><name>$name</name>'
      '<dataType>$dataType</dataType></stateVariable>';

  // ── Small helpers ─────────────────────────────────────────────────────────

  String _headerValue(String message, String header) {
    final re = RegExp('$header\\s*:\\s*([^\\r\\n]+)', caseSensitive: false);
    return re.firstMatch(message)?.group(1)?.trim() ?? '';
  }

  String _headerCase(String? value, String fallback) =>
      value == null || value.isEmpty ? fallback : value;

  String _soapResponse(String action, String service, String args) {
    return '<u:${action}Response '
        'xmlns:u="urn:schemas-upnp-org:service:$service:1">'
        '$args</u:${action}Response>';
  }

  String _guessTitleFromUri(String uri) {
    final clean = uri.split('?').first;
    final idx = clean.lastIndexOf('/');
    return idx >= 0 && idx < clean.length - 1
        ? Uri.decodeComponent(clean.substring(idx + 1))
        : 'DLNA Cast';
  }

  String didlFor(String title, String uri) {
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="0">'
        '<dc:title>${xmlEscape(title)}</dc:title>'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '</item></DIDL-Lite>';
  }

  static String _generateUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}'
        '-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  // Public XML utilities (also used by tests)
  static String xmlEscape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String xmlUnescape(String input) => input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  /// Extracts the text of the first tag named [tag] anywhere in [xml],
  /// ignoring namespace prefixes and attributes.
  static String? extractTag(String xml, String tag) {
    final re = RegExp('<[^>]*:?$tag(?:\\s[^>]*)?>([\\s\\S]*?)</[^>]*:?$tag>',
        caseSensitive: false);
    final m = re.firstMatch(xml);
    if (m == null) return null;
    final raw = m.group(1) ?? '';
    // Strip CDATA if present
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(raw);
    return (cdata?.group(1) ?? raw).trim();
  }

  /// Parses "H:MM:SS(.fraction)" into milliseconds.
  static int? parseUpnpTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final h = parts.length == 3 ? int.tryParse(parts[0]) ?? 0 : 0;
    final mIdx = parts.length == 3 ? 1 : 0;
    final secParts = (parts.last).split('.');
    final m = int.tryParse(parts[mIdx]) ?? 0;
    final s = int.tryParse(secParts[0]) ?? 0;
    final ms = secParts.length > 1
        ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0
        : 0;
    return (h * 3600 + m * 60 + s) * 1000 + ms;
  }

  static String formatUpnpTime(Duration d) {
    final total = d.inMilliseconds.abs();
    final h = (total ~/ 3600000).toString().padLeft(1, '0');
    final m = ((total % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final s = ((total % 60000) ~/ 1000).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
