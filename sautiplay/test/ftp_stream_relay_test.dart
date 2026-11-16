import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/ftp_service.dart';
import 'package:sautiplay/services/ftp_stream_relay.dart';
import 'package:sautiplay/services/local_media_server.dart';

class _MockFtpServer {
  final Uint8List payload;
  late final ServerSocket _controlServer;
  int get port => _controlServer.port;
  int connectionCount = 0;

  _MockFtpServer(this.payload);

  Future<void> start() async {
    _controlServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _controlServer.listen(_handleControlClient);
  }

  void _handleControlClient(Socket control) {
    connectionCount++;
    control.write('220 Mock FTP Server Ready\r\n');

    ServerSocket? dataServer;
    Socket? pendingDataClient;
    Completer<Socket>? dataClientCompleter;
    int restartOffset = 0;
    final rxBuf = <int>[];

    control.listen(
      (Uint8List chunk) async {
        rxBuf.addAll(chunk);
        while (true) {
          final lf = rxBuf.indexOf(10);
          if (lf < 0) break;
          final raw = rxBuf.sublist(0, lf);
          rxBuf.removeRange(0, lf + 1);
          if (raw.isNotEmpty && raw.last == 13) raw.removeLast();
          final line = utf8.decode(raw).trim();
          if (line.isEmpty) continue;

          final spaceIdx = line.indexOf(' ');
          final cmd =
              (spaceIdx >= 0 ? line.substring(0, spaceIdx) : line).toUpperCase();
          final arg = spaceIdx >= 0 ? line.substring(spaceIdx + 1).trim() : '';

          switch (cmd) {
            case 'USER':
              control.write('331 Password required\r\n');
              break;
            case 'PASS':
              control.write('230 Logged in\r\n');
              break;
            case 'TYPE':
              control.write('200 Type set to I\r\n');
              break;
            case 'SIZE':
              control.write('213 ${payload.length}\r\n');
              break;
            case 'EPSV':
              await dataServer?.close();
              dataClientCompleter = Completer<Socket>();
              dataServer =
                  await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
              dataServer!.listen((Socket ds) {
                pendingDataClient = ds;
                if (dataClientCompleter != null &&
                    !dataClientCompleter!.isCompleted) {
                  dataClientCompleter!.complete(ds);
                }
              });
              control.write(
                  '229 Entering Extended Passive Mode (|||${dataServer!.port}|)\r\n');
              break;
            case 'REST':
              restartOffset = int.tryParse(arg) ?? 0;
              control.write('350 Restarting at $restartOffset\r\n');
              break;
            case 'RETR':
              control.write('150 Opening binary data connection\r\n');
              final ds = pendingDataClient ??
                  await dataClientCompleter!.future
                      .timeout(const Duration(seconds: 5));
              final slice = payload.sublist(
                restartOffset.clamp(0, payload.length),
              );
              ds.add(slice);
              await ds.flush();
              await ds.close();
              await dataServer?.close();
              dataServer = null;
              pendingDataClient = null;
              restartOffset = 0;
              control.write('226 Transfer complete\r\n');
              break;
            case 'QUIT':
              control.write('221 Goodbye\r\n');
              await control.close();
              break;
            default:
              control.write('502 Command not implemented\r\n');
          }
        }
      },
      onDone: () {
        dataServer?.close();
      },
      onError: (_) {
        dataServer?.close();
      },
    );
  }

  Future<void> stop() async {
    await _controlServer.close();
  }
}

void main() {
  group('FtpByteRange.parse', () {
    test('parses bounded, open-ended, and suffix ranges', () {
      final bounded = FtpByteRange.parse('bytes=0-32767', totalSize: 100000);
      expect(bounded?.start, 0);
      expect(bounded?.end, 32767);

      final open = FtpByteRange.parse('bytes=500-', totalSize: 1000);
      expect(open?.start, 500);
      expect(open?.end, 999);

      final suffix = FtpByteRange.parse('bytes=-100', totalSize: 1000);
      expect(suffix?.start, 900);
      expect(suffix?.end, 999);

      expect(FtpByteRange.parse(null), isNull);
      expect(FtpByteRange.parse('bytes=0-10,20-30', totalSize: 100), isNull);
      expect(FtpByteRange.parse('bytes=50-10', totalSize: 100), isNull);
    });
  });

  group('FtpStreamRelay end-to-end', () {
    late Uint8List testBytes;
    late _MockFtpServer mockFtp;
    late FtpConfig config;
    late FtpFileEntry entry;
    late String relayUrl;

    setUpAll(() async {
      testBytes = Uint8List.fromList(
        List<int>.generate(4096, (i) => (i * 7 + 13) & 0xff),
      );
      mockFtp = _MockFtpServer(testBytes);
      await mockFtp.start();

      config = FtpConfig(
        id: 'test-ftp-relay',
        name: 'Test FTP',
        host: '127.0.0.1',
        port: mockFtp.port,
        user: 'tester',
        password: 'secret',
      );
      entry = const FtpFileEntry(
        name: 'track01.flac',
        path: '/music/track01.flac',
        isDirectory: false,
        sizeBytes: 0, // Force relay to query SIZE from FTP server
      );

      final url = await LocalMediaServer.instance.registerFtpTrack(config, entry);
      expect(url, isNotNull);
      relayUrl = url!;
    });

    tearDownAll(() async {
      await mockFtp.stop();
      LocalMediaServer.instance.stop();
    });

    test('HEAD returns size, mime type, and Accept-Ranges', () async {
      final client = HttpClient();
      final req = await client.openUrl('HEAD', Uri.parse(relayUrl));
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, HttpStatus.ok);
      expect(res.contentLength, testBytes.length);
      expect(res.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(res.headers.contentType?.mimeType, 'audio/flac');
      client.close();
    });

    test('GET without Range streams full file', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(relayUrl));
      final res = await req.close();
      final body = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(res.statusCode, HttpStatus.ok);
      expect(body, testBytes);
      client.close();
    });

    test('GET with bounded Range streams exact slice', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(relayUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-127');
      final res = await req.close();
      final body = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(res.statusCode, HttpStatus.partialContent);
      expect(
        res.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-127/${testBytes.length}',
      );
      expect(body, testBytes.sublist(0, 128));
      client.close();
    });

    test('GET with offset Range uses REST and streams tail', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(relayUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=2048-');
      final res = await req.close();
      final body = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      expect(res.statusCode, HttpStatus.partialContent);
      expect(
        res.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 2048-${testBytes.length - 1}/${testBytes.length}',
      );
      expect(body, testBytes.sublist(2048));
      client.close();
    });

    test('GET with out-of-bounds Range returns 416', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(relayUrl));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=99999-');
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      client.close();
    });
  });
}
