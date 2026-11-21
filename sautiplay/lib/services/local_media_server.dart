import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart' show AudioEngineFFI;

import 'ftp_service.dart';
import 'ftp_stream_relay.dart';
import 'remote_stream_relay.dart';

typedef _FlushCastTapNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FlushCastTapDart = void Function(ffi.Pointer<ffi.Void>);
typedef _ReadCastPcmNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Int32>,
);
typedef _ReadCastPcmDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Int32>,
  ffi.Pointer<ffi.Int32>,
);
typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

enum LiveCastStreamFormat {
  /// 24-bit signed little-endian RIFF/WAVE stream (`/cast/live_N.wav`).
  wav24,

  /// 24-bit signed big-endian raw DLNA LPCM (`/cast/live_N.l24`).
  lpcm24,

  /// 16-bit signed big-endian raw DLNA LPCM (`/cast/live_N.l16`).
  lpcm16,
}

class LocalMediaServer {
  static final LocalMediaServer instance = LocalMediaServer._internal();
  LocalMediaServer._internal();

  HttpServer? _server;
  int _port = 8080;
  String? _currentFilePath;
  String? _lastLanIp;

  Uint8List? _artworkBytes;
  int _artworkToken = 0;

  int _liveToken = 0;
  int _liveSessionToken = 0;
  int _liveEngineAddress = 0;
  int _liveSampleRate = 48000;
  int _liveChannels = 2;
  bool Function()? _liveIsPlaying;
  VoidCallback? _activeLiveCancel;

  bool _ffiResolved = false;
  _FlushCastTapDart? _aeFlushCastTap;
  _ReadCastPcmDart? _aeReadCastPcmS24Le;
  _MallocDart? _malloc;
  _FreeDart? _free;

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

  void _applyCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type, Accept');
  }

  void _handleRequest(HttpRequest request) async {
    _applyCors(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final reqPath = request.uri.path;
    if (reqPath == '/artwork.jpg') {
      await _handleArtworkRequest(request);
      return;
    }

    if (reqPath.startsWith('/cast/live_') &&
        (reqPath.endsWith('.wav') ||
            reqPath.endsWith('.l24') ||
            reqPath.endsWith('.l16'))) {
      await _handleLiveWavRequest(request);
      return;
    }

    if (reqPath.startsWith('/ftp/')) {
      await FtpStreamRelay.instance.handleHttpRequest(request);
      return;
    }

    if (reqPath.startsWith('/remote/')) {
      await RemoteStreamRelay.instance.handleHttpRequest(request);
      return;
    }

    if (_currentFilePath == null || !File(_currentFilePath!).existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File(_currentFilePath!);
    final ext = p.extension(_currentFilePath!).toLowerCase();
    final contentType = _mimeTypeForExtension(ext);
    final fileSize = await file.length();
    final isHead = request.method == 'HEAD';

    // DLNA / Chromecast often send Range requests
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null) {
      final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? (int.tryParse(parts[1]) ?? fileSize - 1).clamp(start, fileSize - 1)
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
      request.response.headers.set('transferMode.dlna.org', 'Streaming');
      request.response.headers.set('contentFeatures.dlna.org',
          'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');

      if (isHead) {
        await request.response.close();
        return;
      }

      final stream = file.openRead(start, end + 1);
      await stream.pipe(request.response).catchError((e) {
        debugPrint(
            '[LocalMediaServer] Pipe error (client probably disconnected): $e');
      });
    } else {
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, fileSize.toString());
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set('transferMode.dlna.org', 'Streaming');
      request.response.headers.set('contentFeatures.dlna.org',
          'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');

      if (isHead) {
        await request.response.close();
        return;
      }

      final stream = file.openRead();
      await stream.pipe(request.response).catchError((e) {
        debugPrint(
            '[LocalMediaServer] Pipe error (client probably disconnected): $e');
      });
    }
  }

  static String _mimeTypeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.flac':
        return 'audio/flac';
      case '.wav':
        return 'audio/wav';
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.mp4':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.webm':
        return 'audio/webm';
      case '.wv':
        return 'audio/x-wavpack';
      case '.aif':
      case '.aiff':
        return 'audio/aiff';
      case '.dsf':
        return 'audio/dsf';
      case '.dff':
        return 'audio/dff';
      default:
        return 'audio/mpeg';
    }
  }

  /// Stores current cover artwork bytes to serve over `/artwork.jpg`.
  void setArtworkBytes(Uint8List? bytes) {
    _artworkBytes = (bytes != null && bytes.isNotEmpty) ? bytes : null;
    _artworkToken++;
  }

  /// Returns the URL of the active cover artwork if the server is running and
  /// artwork bytes are present.
  String? get artworkUrl {
    if (_server == null || _artworkBytes == null || _lastLanIp == null) {
      return null;
    }
    return 'http://$_lastLanIp:$_port/artwork.jpg?v=$_artworkToken';
  }

  /// Ensures the HTTP server is listening and returns the cover artwork URL if available.
  Future<String?> ensureArtworkUrl() async {
    if (_artworkBytes == null || _artworkBytes!.isEmpty) return null;
    if (_server == null) await start();
    if (_server == null) return null;
    _lastLanIp ??= await bestLanIpv4() ?? '127.0.0.1';
    return artworkUrl;
  }

  Future<void> _handleArtworkRequest(HttpRequest request) async {
    final bytes = _artworkBytes;
    if (bytes == null || bytes.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final isPng = bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    request.response.headers
        .set(HttpHeaders.contentTypeHeader, isPng ? 'image/png' : 'image/jpeg');
    request.response.headers
        .set(HttpHeaders.contentLengthHeader, bytes.length.toString());
    request.response.headers.set('Cache-Control', 'no-cache');
    if (request.method != 'HEAD') {
      request.response.add(bytes);
    }
    await request.response.close();
  }

  /// Builds a standard 44-byte 24-bit signed little-endian LPCM WAVE header.
  static Uint8List buildWavHeader24Bit({
    required int sampleRate,
    required int channels,
    int dataSize = 0x7FFFF000,
  }) {
    final safeSr = sampleRate > 0 ? sampleRate : 48000;
    final safeCh = channels > 0 ? channels : 2;
    const bitsPerSample = 24;
    final blockAlign = safeCh * (bitsPerSample ~/ 8);
    final byteRate = safeSr * blockAlign;
    final riffSize = 36 + dataSize;

    final hdr = Uint8List(44);
    final bd = ByteData.sublistView(hdr);
    hdr.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    bd.setUint32(4, riffSize, Endian.little);
    hdr.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]); // 'WAVE'
    hdr.setRange(12, 16, const [0x66, 0x6D, 0x74, 0x20]); // 'fmt '
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, safeCh, Endian.little);
    bd.setUint32(24, safeSr, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    hdr.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]); // 'data'
    bd.setUint32(40, dataSize, Endian.little);
    return hdr;
  }

  void _ensureLiveFfi() {
    if (_ffiResolved) return;
    _ffiResolved = true;
    try {
      final lib = AudioEngineFFI.openLibrary(null);
      final allocLib = AudioEngineFFI.openAllocatorLibrary();
      _malloc = allocLib.lookupFunction<_MallocNative, _MallocDart>('malloc');
      _free = allocLib.lookupFunction<_FreeNative, _FreeDart>('free');
      _aeFlushCastTap = lib.lookupFunction<_FlushCastTapNative, _FlushCastTapDart>(
        'ae_flush_cast_pcm_tap',
      );
      _aeReadCastPcmS24Le =
          lib.lookupFunction<_ReadCastPcmNative, _ReadCastPcmDart>(
        'ae_read_cast_pcm_s24le',
      );
    } catch (e) {
      debugPrint('[LocalMediaServer] Failed resolving Cast tap FFI: $e');
    }
  }

  /// Registers a live 24-bit WAV or DLNA raw LPCM (`audio/L24` / `audio/L16`)
  /// stream backed by `ae_read_cast_pcm_s24le` and returns its LAN HTTP URL.
  Future<String?> serveLive24BitWav({
    required int engineAddress,
    required int sampleRate,
    required int channels,
    required bool Function() isPlaying,
    LiveCastStreamFormat format = LiveCastStreamFormat.wav24,
  }) async {
    if (_server == null) {
      await start();
    }
    if (_server == null || engineAddress == 0) return null;

    _activeLiveCancel?.call();
    _liveToken++;
    _liveSessionToken = _liveToken;
    _liveEngineAddress = engineAddress;
    _liveSampleRate = sampleRate > 0 ? sampleRate : 48000;
    _liveChannels = channels > 0 ? channels : 2;
    _liveIsPlaying = isPlaying;

    String? localIp = await bestLanIpv4();
    localIp ??= '127.0.0.1';
    _lastLanIp = localIp;

    final ext = switch (format) {
      LiveCastStreamFormat.wav24 => 'wav',
      LiveCastStreamFormat.lpcm24 => 'l24',
      LiveCastStreamFormat.lpcm16 => 'l16',
    };
    return 'http://$localIp:$_port/cast/live_$_liveToken.$ext';
  }

  void stopLiveWavStream() {
    _liveSessionToken = 0;
    _activeLiveCancel?.call();
    _activeLiveCancel = null;
  }

  Future<void> _handleLiveWavRequest(HttpRequest request) async {
    _ensureLiveFfi();
    final reqPath = request.uri.path;
    final LiveCastStreamFormat fmt;
    final String tokenStr;
    if (reqPath.endsWith('.l24')) {
      fmt = LiveCastStreamFormat.lpcm24;
      tokenStr = reqPath.replaceFirst('/cast/live_', '').replaceFirst('.l24', '');
    } else if (reqPath.endsWith('.l16')) {
      fmt = LiveCastStreamFormat.lpcm16;
      tokenStr = reqPath.replaceFirst('/cast/live_', '').replaceFirst('.l16', '');
    } else {
      fmt = LiveCastStreamFormat.wav24;
      tokenStr = reqPath.replaceFirst('/cast/live_', '').replaceFirst('.wav', '');
    }
    final reqToken = int.tryParse(tokenStr);
    if (_liveEngineAddress == 0 ||
        reqToken == null ||
        reqToken != _liveSessionToken ||
        _aeReadCastPcmS24Le == null ||
        _malloc == null ||
        _free == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final sr = _liveSampleRate;
    final ch = _liveChannels;
    final isWav = fmt == LiveCastStreamFormat.wav24;
    final header = isWav ? buildWavHeader24Bit(sampleRate: sr, channels: ch) : Uint8List(0);
    final contentType = switch (fmt) {
      LiveCastStreamFormat.wav24 => 'audio/wav',
      LiveCastStreamFormat.lpcm24 => 'audio/L24;rate=$sr;channels=$ch',
      LiveCastStreamFormat.lpcm16 => 'audio/L16;rate=$sr;channels=$ch',
    };

    request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.response.headers.set('Cache-Control', 'no-cache, no-store');
    request.response.headers.set('transferMode.dlna.org', 'Streaming');
    request.response.headers.set('contentFeatures.dlna.org',
        'DLNA.ORG_OP=00;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000');

    if (request.method == 'HEAD') {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
      await request.response.close();
      return;
    }

    // Handle tiny probe ranges (e.g. bytes=0-1 or bytes=0-43) without opening
    // the continuous engine stream or flushing audio.
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (isWav && rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.replaceFirst('bytes=', '').split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1])
          : null;
      if (end != null && end < header.length && start <= end) {
        const virtualTotal = 44 + 0x7FFFF000;
        final slice = header.sublist(start, end + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, slice.length.toString());
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$virtualTotal',
        );
        request.response.add(slice);
        await request.response.close();
        return;
      }
    }

    _activeLiveCancel?.call();
    request.response.statusCode = HttpStatus.ok;
    request.response.bufferOutput = false;
    // Provide an explicit Content-Length so Dart's HttpServer does NOT use
    // Transfer-Encoding: chunked (many DLNA renderers mute or stall on chunked audio).
    request.response.contentLength = header.length + 0x7FFFF000;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');

    final enginePtr = ffi.Pointer<ffi.Void>.fromAddress(_liveEngineAddress);
    _aeFlushCastTap?.call(enginePtr);
    if (header.isNotEmpty) {
      request.response.add(header);
    }

    final inFrameBytes = math.max(3, ch * 3);
    final outBytesPerSample = fmt == LiveCastStreamFormat.lpcm16 ? 2 : 3;
    final outFrameBytes = math.max(2, ch * outBytesPerSample);
    final framesPer20ms = math.max(1, (sr * 20) ~/ 1000);
    final chunk20msInBytes = framesPer20ms * inFrameBytes;
    final readBufCapacity = math.max(65536, chunk20msInBytes * 4);
    final nativeBuf = _malloc!(readBufCapacity).cast<ffi.Uint8>();
    final outSrPtr = _malloc!(4).cast<ffi.Int32>();
    final outChPtr = _malloc!(4).cast<ffi.Int32>();
    final silence20ms = Uint8List(framesPer20ms * outFrameBytes);

    var closed = false;
    Timer? timer;
    int emptyTicks = 0;

    void cleanup() {
      if (closed) return;
      closed = true;
      timer?.cancel();
      timer = null;
      try {
        request.response.close();
      } catch (_) {}
      try {
        _free!(nativeBuf.cast<ffi.Void>());
        _free!(outSrPtr.cast<ffi.Void>());
        _free!(outChPtr.cast<ffi.Void>());
      } catch (_) {}
      if (_activeLiveCancel == cleanup) {
        _activeLiveCancel = null;
      }
    }

    _activeLiveCancel = cleanup;
    request.response.done.then((_) => cleanup()).catchError((_) => cleanup());

    timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (closed || reqToken != _liveSessionToken) {
        cleanup();
        return;
      }

      try {
        final playing = _liveIsPlaying?.call() ?? false;
        final n = _aeReadCastPcmS24Le!(
          enginePtr,
          nativeBuf,
          readBufCapacity,
          outSrPtr,
          outChPtr,
        );

        if (n > 0) {
          emptyTicks = 0;
          final raw = nativeBuf.asTypedList(n);
          final Uint8List bytes;
          if (fmt == LiveCastStreamFormat.wav24) {
            bytes = Uint8List.fromList(raw);
          } else if (fmt == LiveCastStreamFormat.lpcm24) {
            // S24LE -> S24BE (DLNA audio/L24)
            final sampleCount = n ~/ 3;
            bytes = Uint8List(sampleCount * 3);
            for (var i = 0; i < sampleCount; i++) {
              final off = i * 3;
              bytes[off] = raw[off + 2];
              bytes[off + 1] = raw[off + 1];
              bytes[off + 2] = raw[off];
            }
          } else {
            // S24LE -> S16BE (DLNA audio/L16)
            final sampleCount = n ~/ 3;
            bytes = Uint8List(sampleCount * 2);
            for (var i = 0; i < sampleCount; i++) {
              final inOff = i * 3;
              final outOff = i * 2;
              bytes[outOff] = raw[inOff + 2];
              bytes[outOff + 1] = raw[inOff + 1];
            }
          }
          request.response.add(bytes);
        } else if (!playing) {
          emptyTicks = 0;
          request.response.add(silence20ms);
        } else {
          emptyTicks++;
          // Keep the live WAV stream flowing during brief engine restarts /
          // rate switches so DLNA renderers and FFmpeg probers never starve.
          if (emptyTicks >= 2) {
            emptyTicks = 0;
            request.response.add(silence20ms);
          }
        }
      } catch (_) {
        cleanup();
      }
    });
  }

  /// Sets the file that the server will serve at the root endpoint.
  /// Returns the URL that can be given to a Chromecast or DLNA Renderer.
  Future<String?> serveFile(String filePath) async {
    if (_server == null) {
      await start();
    }
    if (_server == null) return null;

    stopLiveWavStream();
    _currentFilePath = filePath;

    String? localIp = await bestLanIpv4();
    localIp ??= '127.0.0.1';
    _lastLanIp = localIp;

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
          if (name.contains('vethernet') ||
              name.contains('virtual') ||
              name.contains('vmware') ||
              name.contains('vbox') ||
              name.contains('wsl') ||
              name.contains('hyper-v') ||
              name.contains('docker') ||
              name.contains('tailscale') ||
              name.contains('zerotier') ||
              name.startsWith('tun') ||
              name.startsWith('tap')) {
            return 0;
          }
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

  /// Registers an FTP track for local HTTP byte-range streaming and returns its
  /// `http://127.0.0.1:<port>/ftp/...` relay URL, or `null` if the server could
  /// not start.
  Future<String?> registerFtpTrack(FtpConfig config, FtpFileEntry entry) async {
    await start();
    if (_server == null) return null;
    return FtpStreamRelay.instance.registerEntry(
      config,
      entry,
      serverPort: _port,
      mimeType: mimeTypeForPathOrExt(entry.name),
    );
  }

  /// Registers a generic [RemoteByteSource] (WebDAV, SFTP, SMB) for local
  /// HTTP byte-range streaming and returns its loopback URL.
  Future<String?> registerRemoteSource(RemoteByteSource source) async {
    await start();
    if (_server == null) return null;
    return RemoteStreamRelay.instance.registerSource(source, _port);
  }

  static String mimeTypeForPathOrExt(String pathOrExt) =>
      _mimeTypeForExtension(p.extension(pathOrExt).isNotEmpty ? p.extension(pathOrExt) : pathOrExt);

  void stop() {
    stopLiveWavStream();
    _server?.close(force: true);
    _server = null;
    _currentFilePath = null;
  }
}
