import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ftp_service.dart';

/// Parsed HTTP `bytes=` range specification.
class FtpByteRange {
  final int start;
  final int? end; // Inclusive end byte, or null if open-ended (`bytes=N-`).

  const FtpByteRange({required this.start, this.end});

  /// Parses an HTTP `Range` header (e.g. `bytes=0-`, `bytes=0-32767`, `bytes=-512`).
  ///
  /// Returns `null` if the header is missing, malformed, or uses a multi-range
  /// specification (which is not supported by single-part relay).
  static FtpByteRange? parse(String? header, {int? totalSize}) {
    if (header == null) return null;
    final trimmed = header.trim();
    if (!trimmed.toLowerCase().startsWith('bytes=')) return null;
    final spec = trimmed.substring(6).trim();
    if (spec.isEmpty || spec.contains(',')) return null;

    final dashIdx = spec.indexOf('-');
    if (dashIdx < 0) return null;

    final startStr = spec.substring(0, dashIdx).trim();
    final endStr = spec.substring(dashIdx + 1).trim();

    if (startStr.isEmpty) {
      // Suffix byte range: `bytes=-N`
      if (endStr.isEmpty || totalSize == null || totalSize <= 0) return null;
      final suffixLen = int.tryParse(endStr);
      if (suffixLen == null || suffixLen <= 0) return null;
      final start = (totalSize - suffixLen).clamp(0, totalSize - 1);
      return FtpByteRange(start: start, end: totalSize - 1);
    }

    final start = int.tryParse(startStr);
    if (start == null || start < 0) return null;

    if (endStr.isEmpty) {
      return FtpByteRange(
        start: start,
        end: (totalSize != null && totalSize > 0) ? totalSize - 1 : null,
      );
    }

    final parsedEnd = int.tryParse(endStr);
    if (parsedEnd == null || parsedEnd < start) return null;
    final clampedEnd = (totalSize != null && totalSize > 0)
        ? parsedEnd.clamp(start, totalSize - 1)
        : parsedEnd;
    return FtpByteRange(start: start, end: clampedEnd);
  }
}

class _FtpRelayEntry {
  final String token;
  FtpConfig config;
  final String remotePath;
  final String fileName;
  final String mimeType;
  int? knownSizeBytes;

  _FtpRelayEntry({
    required this.token,
    required this.config,
    required this.remotePath,
    required this.fileName,
    required this.mimeType,
    this.knownSizeBytes,
  });

  String get cacheKey => '${config.id}\u0000$remotePath';
}

/// Relays HTTP/1.1 `GET`/`HEAD` byte-range requests directly to an FTP/FTPS
/// server using `REST` + `RETR` over a passive data socket, enabling progressive
/// playback and seeking without downloading whole files to disk first.
class FtpStreamRelay {
  static final FtpStreamRelay instance = FtpStreamRelay._();
  FtpStreamRelay._();

  static const int _maxRegisteredEntries = 512;
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _commandTimeout = Duration(seconds: 15);

  final LinkedHashMap<String, _FtpRelayEntry> _entriesByToken =
      LinkedHashMap<String, _FtpRelayEntry>();
  final Map<String, String> _tokenByKey = <String, String>{};
  final Random _random = Random.secure();
  int _counter = 0;

  /// Registers an FTP file for local HTTP range streaming and returns its URL.
  String registerEntry(
    FtpConfig config,
    FtpFileEntry entry, {
    required int serverPort,
    required String mimeType,
  }) {
    final key = '${config.id}\u0000${entry.path}';
    final existingToken = _tokenByKey[key];
    if (existingToken != null && _entriesByToken.containsKey(existingToken)) {
      final existing = _entriesByToken.remove(existingToken)!;
      existing.config = config;
      if (entry.sizeBytes > 0) {
        existing.knownSizeBytes = entry.sizeBytes;
      }
      _entriesByToken[existingToken] = existing;
      return _buildUrl(serverPort, existingToken, entry.name);
    }

    while (_entriesByToken.length >= _maxRegisteredEntries) {
      final oldestKey = _entriesByToken.keys.first;
      final removed = _entriesByToken.remove(oldestKey);
      if (removed != null) {
        _tokenByKey.remove(removed.cacheKey);
      }
    }

    final token = _nextToken();
    final relayEntry = _FtpRelayEntry(
      token: token,
      config: config,
      remotePath: entry.path,
      fileName: entry.name,
      mimeType: mimeType,
      knownSizeBytes: entry.sizeBytes > 0 ? entry.sizeBytes : null,
    );
    _entriesByToken[token] = relayEntry;
    _tokenByKey[key] = token;
    return _buildUrl(serverPort, token, entry.name);
  }

  String _nextToken() {
    _counter++;
    final randPart = _random.nextInt(0x7fffffff).toRadixString(36);
    return '${_counter.toRadixString(36)}_$randPart';
  }

  String _buildUrl(int port, String token, String fileName) {
    final safeName = Uri.encodeComponent(
      fileName.isEmpty ? 'stream.bin' : fileName,
    );
    return 'http://127.0.0.1:$port/ftp/$token/$safeName';
  }

  /// Handles an incoming `/ftp/<token>/<name>` HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'ftp') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final token = segments[1];
    final entry = _entriesByToken[token];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD, OPTIONS');
      await request.response.close();
      return;
    }

    _FtpControlSession? ftp;
    Socket? dataSocket;

    try {
      ftp = await _FtpControlSession.connect(
        entry.config,
        connectTimeout: _connectTimeout,
        commandTimeout: _commandTimeout,
      );

      int? totalSize = entry.knownSizeBytes;
      if (totalSize == null || totalSize <= 0) {
        totalSize = await ftp.size(entry.remotePath);
        if (totalSize != null && totalSize > 0) {
          entry.knownSizeBytes = totalSize;
        }
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final parsedRange = FtpByteRange.parse(rangeHeader, totalSize: totalSize);

      if (rangeHeader != null && parsedRange == null) {
        // Malformed or unsatisfiable range (e.g. suffix range without known size).
        if (totalSize != null && totalSize > 0) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers
              .set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
          await request.response.close();
          return;
        }
      }

      final start = parsedRange?.start ?? 0;
      if (totalSize != null && totalSize > 0 && start >= totalSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
        await request.response.close();
        return;
      }

      final int? end = parsedRange?.end ??
          ((totalSize != null && totalSize > 0) ? totalSize - 1 : null);
      final int? contentLength =
          (end != null && end >= start) ? (end - start + 1) : null;

      request.response.headers.set(HttpHeaders.contentTypeHeader, entry.mimeType);
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (totalSize != null && totalSize > 0) {
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }

      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.ok;
        if (totalSize != null && totalSize > 0) {
          request.response.contentLength = totalSize;
        }
        await request.response.close();
        return;
      }

      // Open passive data channel and start RETR (with REST if start > 0).
      final dataPort = await ftp.openPassivePort();
      if (start > 0) {
        final restOk = await ftp.restartAt(start);
        if (!restOk) {
          request.response.statusCode = HttpStatus.notImplemented;
          await request.response.close();
          return;
        }
      }

      await ftp.sendRetr(entry.remotePath);
      dataSocket = await ftp.connectDataSocket(dataPort);

      final startReply = await ftp.readReply();
      if (startReply.code != 125 && startReply.code != 150) {
        debugPrint(
            '[FtpStreamRelay] RETR rejected (${startReply.code}): ${startReply.message}');
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      if (parsedRange != null) {
        request.response.statusCode = HttpStatus.partialContent;
        if (end != null) {
          final sizeStr =
              (totalSize != null && totalSize > 0) ? '$totalSize' : '*';
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$sizeStr',
          );
        }
      } else {
        request.response.statusCode = HttpStatus.ok;
      }

      if (contentLength != null) {
        request.response.contentLength = contentLength;
      }

      await _pipeBoundedData(
        dataSocket: dataSocket,
        response: request.response,
        maxBytes: contentLength,
      );
    } catch (e) {
      debugPrint('[FtpStreamRelay] Error relaying ${entry.remotePath}: $e');
      try {
        // Only set error status if headers haven't been flushed yet.
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      try {
        dataSocket?.destroy();
      } catch (_) {}
      await ftp?.closeQuietly();
    }
  }

  /// Streams bytes from [dataSocket] to [response], stopping after [maxBytes]
  /// (if specified) or immediately if the HTTP client disconnects.
  Future<void> _pipeBoundedData({
    required Socket dataSocket,
    required HttpResponse response,
    required int? maxBytes,
  }) async {
    final completer = Completer<void>();
    int remaining = maxBytes ?? -1;
    bool closed = false;
    late StreamSubscription<Uint8List> sub;

    void abort() {
      if (closed) return;
      closed = true;
      sub.cancel();
      try {
        dataSocket.destroy();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Abort FTP transfer immediately if the HTTP client (FFmpeg) closes early.
    response.done.then((_) => abort(), onError: (_) => abort());

    sub = dataSocket.listen(
      (Uint8List chunk) {
        if (closed) return;
        if (chunk.isEmpty) return;

        Uint8List toSend = chunk;
        bool reachedLimit = false;
        if (remaining >= 0) {
          if (remaining == 0) {
            abort();
            return;
          }
          if (chunk.length >= remaining) {
            toSend = chunk.sublist(0, remaining);
            remaining = 0;
            reachedLimit = true;
          } else {
            remaining -= chunk.length;
          }
        }

        try {
          response.add(toSend);
        } catch (_) {
          abort();
          return;
        }

        if (reachedLimit) {
          closed = true;
          sub.cancel();
          try {
            dataSocket.destroy();
          } catch (_) {}
          response.close().then(
            (_) {
              if (!completer.isCompleted) completer.complete();
            },
            onError: (_) {
              if (!completer.isCompleted) completer.complete();
            },
          );
        }
      },
      onError: (Object err) {
        if (!closed) {
          closed = true;
          response.close().then(
            (_) {
              if (!completer.isCompleted) completer.complete();
            },
            onError: (_) {
              if (!completer.isCompleted) completer.complete();
            },
          );
        }
      },
      onDone: () {
        if (!closed) {
          closed = true;
          response.close().then(
            (_) {
              if (!completer.isCompleted) completer.complete();
            },
            onError: (_) {
              if (!completer.isCompleted) completer.complete();
            },
          );
        }
      },
      cancelOnError: true,
    );

    await completer.future;
  }
}

class _FtpReply {
  final int code;
  final String message;

  const _FtpReply(this.code, this.message);

  bool get isSuccess => code >= 200 && code < 300;
}

class _FtpControlSession {
  Socket _socket;
  final FtpConfig _config;
  final Duration _connectTimeout;
  final Duration _commandTimeout;
  bool _useTlsData = false;

  final List<int> _rxBuffer = <int>[];
  final StreamController<String> _lineController = StreamController<String>();
  late StreamIterator<String> _lineIterator;
  StreamSubscription<Uint8List>? _socketSub;

  _FtpControlSession._(
    this._socket,
    this._config,
    this._connectTimeout,
    this._commandTimeout,
  ) {
    _lineIterator = StreamIterator<String>(_lineController.stream);
    _attachReader(_socket);
  }

  void _attachReader(Socket sock) {
    _socketSub?.cancel();
    _socketSub = sock.listen(
      (Uint8List data) {
        _rxBuffer.addAll(data);
        while (true) {
          final lfIdx = _rxBuffer.indexOf(10); // '\n'
          if (lfIdx < 0) break;
          final rawLine = _rxBuffer.sublist(0, lfIdx);
          _rxBuffer.removeRange(0, lfIdx + 1);
          if (rawLine.isNotEmpty && rawLine.last == 13) {
            rawLine.removeLast(); // '\r'
          }
          _lineController.add(utf8.decode(rawLine, allowMalformed: true));
        }
      },
      onError: (Object err) {
        if (!_lineController.isClosed) {
          _lineController.addError(err);
        }
      },
      onDone: () {
        if (!_lineController.isClosed) {
          _lineController.close();
        }
      },
    );
  }

  static Future<_FtpControlSession> connect(
    FtpConfig config, {
    required Duration connectTimeout,
    required Duration commandTimeout,
  }) async {
    final sock = await Socket.connect(
      config.host,
      config.port,
      timeout: connectTimeout,
    );
    final session = _FtpControlSession._(
      sock,
      config,
      connectTimeout,
      commandTimeout,
    );

    try {
      final greeting = await session.readReply();
      if (!greeting.isSuccess) {
        throw HttpException('FTP greeting failed: ${greeting.code}');
      }

      if (config.isSecure) {
        final auth = await session.sendCommand('AUTH TLS');
        if (auth.code != 234) {
          throw HttpException('FTPS AUTH TLS rejected: ${auth.code}');
        }
        await session._upgradeToTls();
        await session.sendCommand('PBSZ 0');
        final prot = await session.sendCommand('PROT P');
        session._useTlsData = prot.isSuccess;
      }

      final userReply = await session.sendCommand('USER ${config.user}');
      if (userReply.code == 331) {
        final passReply = await session.sendCommand('PASS ${config.password}');
        if (!passReply.isSuccess) {
          throw HttpException('FTP login failed: ${passReply.code}');
        }
      } else if (!userReply.isSuccess) {
        throw HttpException('FTP USER rejected: ${userReply.code}');
      }

      final typeReply = await session.sendCommand('TYPE I');
      if (!typeReply.isSuccess) {
        throw HttpException('FTP TYPE I failed: ${typeReply.code}');
      }

      return session;
    } catch (e) {
      await session.closeQuietly();
      rethrow;
    }
  }

  Future<void> _upgradeToTls() async {
    await _socketSub?.cancel();
    _socketSub = null;
    final secure = await SecureSocket.secure(
      _socket,
      onBadCertificate: (_) => true,
    ).timeout(_connectTimeout);
    _socket = secure;
    _attachReader(secure);
  }

  Future<_FtpReply> readReply() async {
    final lines = <String>[];
    int? code;

    while (true) {
      final hasNext = await _lineIterator.moveNext().timeout(_commandTimeout);
      if (!hasNext) {
        throw const HttpException('FTP control connection closed unexpectedly');
      }
      final line = _lineIterator.current;
      lines.add(line);

      if (line.length >= 4 &&
          _isDigit(line.codeUnitAt(0)) &&
          _isDigit(line.codeUnitAt(1)) &&
          _isDigit(line.codeUnitAt(2))) {
        final parsedCode = int.parse(line.substring(0, 3));
        final sep = line[3];
        if (code == null) {
          code = parsedCode;
          if (sep == ' ') break;
        } else if (parsedCode == code && sep == ' ') {
          break;
        }
      } else if (line.length == 3 &&
          _isDigit(line.codeUnitAt(0)) &&
          _isDigit(line.codeUnitAt(1)) &&
          _isDigit(line.codeUnitAt(2))) {
        code = int.parse(line);
        break;
      }
    }

    return _FtpReply(code, lines.join('\n'));
  }

  static bool _isDigit(int c) => c >= 48 && c <= 57;

  Future<_FtpReply> sendCommand(String cmd) async {
    _socket.write('$cmd\r\n');
    await _socket.flush().timeout(_commandTimeout);
    return readReply();
  }

  Future<int?> size(String remotePath) async {
    final reply = await sendCommand('SIZE $remotePath');
    if (reply.code == 213) {
      final parts = reply.message.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return int.tryParse(parts.last);
      }
    }
    return null;
  }

  Future<int> openPassivePort() async {
    final epsv = await sendCommand('EPSV');
    if (epsv.code == 229) {
      final match = RegExp(r'\(\|\|\|(\d+)\|\)').firstMatch(epsv.message);
      if (match != null) {
        final port = int.tryParse(match.group(1)!);
        if (port != null && port > 0) return port;
      }
    }

    final pasv = await sendCommand('PASV');
    if (pasv.code == 227) {
      final match = RegExp(
        r'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)',
      ).firstMatch(pasv.message);
      if (match != null) {
        final p1 = int.parse(match.group(5)!);
        final p2 = int.parse(match.group(6)!);
        return (p1 << 8) + p2;
      }
    }

    throw HttpException('FTP passive mode failed: ${pasv.message}');
  }

  Future<bool> restartAt(int offset) async {
    final reply = await sendCommand('REST $offset');
    return reply.code == 350;
  }

  Future<void> sendRetr(String remotePath) async {
    _socket.write('RETR $remotePath\r\n');
    await _socket.flush().timeout(_commandTimeout);
  }

  Future<Socket> connectDataSocket(int port) async {
    final sock = await Socket.connect(
      _config.host,
      port,
      timeout: _connectTimeout,
    );
    if (_config.isSecure && _useTlsData) {
      return SecureSocket.secure(
        sock,
        onBadCertificate: (_) => true,
      ).timeout(_connectTimeout);
    }
    return sock;
  }

  Future<void> closeQuietly() async {
    try {
      await _socketSub?.cancel();
    } catch (_) {}
    try {
      _socket.destroy();
    } catch (_) {}
    try {
      if (!_lineController.isClosed) {
        await _lineController.close();
      }
    } catch (_) {}
  }
}
