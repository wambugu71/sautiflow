import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class LocalMediaServer {
  static final LocalMediaServer instance = LocalMediaServer._internal();
  LocalMediaServer._internal();

  HttpServer? _server;
  int _port = 8080;
  String? _currentFilePath;

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _port = _server!.port;
      debugPrint('[LocalMediaServer] Started on port $_port');

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      });
    } catch (e) {
      // If port 8080 is in use, let OS pick a random port
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        _port = _server!.port;
        debugPrint('[LocalMediaServer] Started on random port $_port');

        _server!.listen((HttpRequest request) {
          _handleRequest(request);
        });
      } catch (e2) {
        debugPrint('[LocalMediaServer] Failed to start server: $e2');
      }
    }
  }

  void _handleRequest(HttpRequest request) async {
    if (_currentFilePath == null || !File(_currentFilePath!).existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
      return;
    }

    final file = File(_currentFilePath!);
    final ext = p.extension(_currentFilePath!).toLowerCase();
    String contentType = 'audio/mpeg'; // default
    if (ext == '.flac') contentType = 'audio/flac';
    if (ext == '.wav') contentType = 'audio/x-wav';
    if (ext == '.m4a' || ext == '.mp4') contentType = 'audio/mp4';
    if (ext == '.aac') contentType = 'audio/aac';
    if (ext == '.ogg') contentType = 'audio/ogg';

    final fileSize = await file.length();

    // DLNA often uses Range requests
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null) {
      final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? fileSize - 1
          : fileSize - 1;

      if (start >= fileSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes */$fileSize');
        await request.response.close();
        return;
      }

      final contentLength = end - start + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, contentLength.toString());
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileSize');

      // Serve the requested range
      final stream = file.openRead(start, end + 1);
      await stream.pipe(request.response).catchError((e) {
        debugPrint(
            '[LocalMediaServer] Pipe error (client probably disconnected): $e');
      });
    } else {
      // Full file request
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, fileSize.toString());
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      final stream = file.openRead();
      await stream.pipe(request.response).catchError((e) {
        debugPrint(
            '[LocalMediaServer] Pipe error (client probably disconnected): $e');
      });
    }
  }

  /// Sets the file that the server will serve at the root endpoint.
  /// Returns the URL that can be given to a DLNA Renderer.
  Future<String?> serveFile(String filePath) async {
    if (_server == null) {
      await start();
    }
    if (_server == null) return null;

    _currentFilePath = filePath;

    String? localIp = await bestLanIpv4();
    localIp ??= '127.0.0.1';

    final ext = p.extension(filePath);
    return 'http://$localIp:$_port/stream$ext';
  }

  /// Picks the IPv4 address most likely reachable by other LAN devices.
  /// On Android, the first non-loopback IPv4 interface is often the cellular
  /// modem (rmnet/CCNAT), which peers cannot reach — prefer Wi-Fi / ethernet.
  static Future<String?> bestLanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      int scoreInterface(NetworkInterface iface) {
        final name = iface.name.toLowerCase();
        if (Platform.isAndroid) {
          if (name.startsWith('wlan')) return 4;
          if (name.startsWith('eth')) return 3;
          if (name.startsWith('ap') || name.contains('swlan')) return 2;
          if (name.startsWith('rmnet') ||
              name.startsWith('ccmni') ||
              name.startsWith('usb') ||
              name.startsWith('tun')) {
            return 0;
          }
        } else {
          if (name.startsWith('eth') ||
              name.startsWith('en') ||
              name.contains('wi-fi') ||
              name.contains('wifi') ||
              name.contains('wireless')) {
            return 4;
          }
        }
        return 1;
      }

      final candidates = <(NetworkInterface, InternetAddress)>[];
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            candidates.add((interface, addr));
          }
        }
      }

      if (candidates.isEmpty) return null;
      candidates.sort(
          (a, b) => scoreInterface(b.$1).compareTo(scoreInterface(a.$1)));
      debugPrint(
          '[LocalMediaServer] Using local IP ${candidates.first.$2.address} (${candidates.first.$1.name})');
      return candidates.first.$2.address;
    } catch (e) {
      debugPrint('[LocalMediaServer] Failed to get local IP: $e');
      return null;
    }
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    _currentFilePath = null;
  }
}
