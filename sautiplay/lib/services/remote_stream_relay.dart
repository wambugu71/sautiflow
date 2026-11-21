import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ftp_stream_relay.dart' show FtpByteRange;
import 'remote_file_entry.dart';

/// Abstraction for a seekable remote byte stream (WebDAV, SFTP, SMB).
abstract interface class RemoteByteSource {
  /// Stable identifier used to deduplicate registered relay URLs.
  String get id;

  /// Display/extension file name used for MIME type inference.
  String get fileName;

  /// Known byte size if available, or `null` if it must be probed.
  int? get knownSizeBytes;

  /// Resolves the total byte size of the remote resource.
  Future<int?> resolveSizeBytes();

  /// Opens a stream reading bytes from [start] through [end] (inclusive),
  /// or to EOF when [end] is `null`.
  Future<Stream<Uint8List>> openRangeStream(int start, int? end);
}

/// Generic HTTP byte-range relay for remote protocols (WebDAV, SFTP, SMB).
///
/// Exposes registered [RemoteByteSource] instances at
/// `http://127.0.0.1:<port>/remote/<token>/<fileName>` so the native audio
/// engine can stream and seek via standard HTTP `Range` requests.
class RemoteStreamRelay {
  static final RemoteStreamRelay instance = RemoteStreamRelay._internal();
  RemoteStreamRelay._internal();

  static const int _maxRegisteredEntries = 512;

  final LinkedHashMap<String, RemoteByteSource> _entries =
      LinkedHashMap<String, RemoteByteSource>();
  final Map<String, String> _idToToken = {};
  final Random _rng = Random.secure();

  String _generateToken() {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Registers [source] and returns its local loopback relay URL.
  String registerSource(RemoteByteSource source, int port) {
    final existingToken = _idToToken[source.id];
    if (existingToken != null && _entries.containsKey(existingToken)) {
      _entries[existingToken] = source;
      final encodedName = Uri.encodeComponent(source.fileName);
      return 'http://127.0.0.1:$port/remote/$existingToken/$encodedName';
    }

    while (_entries.length >= _maxRegisteredEntries) {
      final oldestKey = _entries.keys.first;
      final removed = _entries.remove(oldestKey);
      if (removed != null) {
        _idToToken.remove(removed.id);
      }
    }

    final token = _generateToken();
    _entries[token] = source;
    _idToToken[source.id] = token;
    final encodedName = Uri.encodeComponent(source.fileName);
    return 'http://127.0.0.1:$port/remote/$token/$encodedName';
  }

  /// Handles an incoming `/remote/<token>/...` HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'remote') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final token = segments[1];
    final source = _entries[token];
    if (source == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final isHead = request.method.toUpperCase() == 'HEAD';
    final contentType = mimeTypeForAudioFile(source.fileName);

    int? totalSize = source.knownSizeBytes;
    if (totalSize == null || totalSize <= 0) {
      try {
        totalSize = await source.resolveSizeBytes();
      } catch (e) {
        debugPrint('[RemoteStreamRelay] Size probe failed for ${source.fileName}: $e');
      }
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final parsedRange = rangeHeader != null
        ? FtpByteRange.parse(rangeHeader, totalSize: totalSize)
        : null;

    if (rangeHeader != null && parsedRange == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      if (totalSize != null && totalSize > 0) {
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
      }
      await request.response.close();
      return;
    }

    final int start = parsedRange?.start ?? 0;
    final int? end = parsedRange?.end ??
        (totalSize != null && totalSize > 0 ? totalSize - 1 : null);

    if (totalSize != null && totalSize > 0 && start >= totalSize) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
      await request.response.close();
      return;
    }

    request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (parsedRange != null) {
      request.response.statusCode = HttpStatus.partialContent;
      if (end != null) {
        final len = end - start + 1;
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, len.toString());
        final totalStr =
            (totalSize != null && totalSize > 0) ? totalSize.toString() : '*';
        request.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalStr');
      }
    } else {
      request.response.statusCode = HttpStatus.ok;
      if (totalSize != null && totalSize > 0) {
        request.response.headers
            .set(HttpHeaders.contentLengthHeader, totalSize.toString());
      }
    }

    if (isHead) {
      await request.response.close();
      return;
    }

    try {
      final stream = await source.openRangeStream(start, end);
      await for (final chunk in stream) {
        request.response.add(chunk);
      }
    } on SocketException {
      // Client closed connection early (seek / skip).
    } on HttpException {
      // Response already aborted by client.
    } catch (e) {
      debugPrint('[RemoteStreamRelay] Stream error (${source.fileName}): $e');
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
