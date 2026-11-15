import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/chromecast_service.dart';
import 'package:sautiplay/services/local_media_server.dart';

Uint8List _buildSyntheticCastMdnsResponse() {
  final out = BytesBuilder(copy: false);

  void writeU16(int v) {
    out.addByte((v >> 8) & 0xFF);
    out.addByte(v & 0xFF);
  }

  void writeU32(int v) {
    out.addByte((v >> 24) & 0xFF);
    out.addByte((v >> 16) & 0xFF);
    out.addByte((v >> 8) & 0xFF);
    out.addByte(v & 0xFF);
  }

  void writeLabel(String label) {
    final bytes = utf8.encode(label);
    out.addByte(bytes.length);
    out.add(bytes);
  }

  void writePtr(int offset) {
    out.addByte(0xC0 | ((offset >> 8) & 0x3F));
    out.addByte(offset & 0xFF);
  }

  // DNS Header (12 bytes): Response, 0 Questions, 1 Answer, 0 Auth, 3 Additional
  writeU16(0x0000); // Transaction ID
  writeU16(0x8400); // Standard query response, authoritative
  writeU16(0); // QDCOUNT
  writeU16(1); // ANCOUNT
  writeU16(0); // NSCOUNT
  writeU16(3); // ARCOUNT

  // Answer 1: PTR _googlecast._tcp.local -> Living-Room._googlecast._tcp.local
  final serviceNameOffset = out.length; // 12
  writeLabel('_googlecast');
  writeLabel('_tcp');
  writeLabel('local');
  out.addByte(0x00);
  writeU16(12); // TYPE = PTR
  writeU16(1); // CLASS = IN
  writeU32(120); // TTL

  final ptrTargetBytes = BytesBuilder(copy: false);
  final instanceLabel = utf8.encode('Living-Room');
  ptrTargetBytes.addByte(instanceLabel.length);
  ptrTargetBytes.add(instanceLabel);
  ptrTargetBytes.addByte(0xC0 | ((serviceNameOffset >> 8) & 0x3F));
  ptrTargetBytes.addByte(serviceNameOffset & 0xFF);
  final ptrRdata = ptrTargetBytes.toBytes();

  writeU16(ptrRdata.length);
  final instanceNameOffset = out.length;
  out.add(ptrRdata);

  // Additional 1: SRV Living-Room._googlecast._tcp.local -> cast-host.local:8009
  writePtr(instanceNameOffset);
  writeU16(33); // TYPE = SRV
  writeU16(0x8001); // CLASS = IN + cache-flush
  writeU32(120);
  final hostBytes = BytesBuilder(copy: false);
  final hostLabel = utf8.encode('cast-host');
  final localLabel = utf8.encode('local');
  hostBytes.addByte(hostLabel.length);
  hostBytes.add(hostLabel);
  hostBytes.addByte(localLabel.length);
  hostBytes.add(localLabel);
  hostBytes.addByte(0x00);
  final hostEncoded = hostBytes.toBytes();

  writeU16(6 + hostEncoded.length); // priority(2)+weight(2)+port(2)+target
  writeU16(0); // priority
  writeU16(0); // weight
  writeU16(8009); // port
  final targetHostOffset = out.length;
  out.add(hostEncoded);

  // Additional 2: TXT Living-Room._googlecast._tcp.local
  writePtr(instanceNameOffset);
  writeU16(16); // TYPE = TXT
  writeU16(0x8001);
  writeU32(120);
  final txtBuilder = BytesBuilder(copy: false);
  for (final kv in const [
    'id=abcd1234',
    'fn=Living Room Speaker',
    'md=Chromecast Audio',
    'ca=4',
  ]) {
    final kvBytes = utf8.encode(kv);
    txtBuilder.addByte(kvBytes.length);
    txtBuilder.add(kvBytes);
  }
  final txtRdata = txtBuilder.toBytes();
  writeU16(txtRdata.length);
  out.add(txtRdata);

  // Additional 3: A cast-host.local -> 192.168.1.77
  writePtr(targetHostOffset);
  writeU16(1); // TYPE = A
  writeU16(0x8001);
  writeU32(120);
  writeU16(4); // RDLENGTH
  out.add([192, 168, 1, 77]);

  return out.toBytes();
}

void main() {
  group('Cast V2 Protobuf Codec', () {
    test('encodes and decodes UTF-8 JSON CastWireMessage', () {
      const msg = CastWireMessage(
        protocolVersion: 0,
        sourceId: 'sender-0',
        destinationId: 'receiver-0',
        namespace: 'urn:x-cast:com.google.cast.media',
        payloadType: 0,
        payloadUtf8: '{"type":"GET_STATUS","requestId":1}',
      );

      final encoded = ChromecastService.encodeCastMessage(msg);
      final decoded = ChromecastService.decodeCastMessage(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.protocolVersion, equals(0));
      expect(decoded.sourceId, equals('sender-0'));
      expect(decoded.destinationId, equals('receiver-0'));
      expect(decoded.namespace, equals('urn:x-cast:com.google.cast.media'));
      expect(decoded.payloadType, equals(0));
      expect(decoded.payloadUtf8, equals('{"type":"GET_STATUS","requestId":1}'));
      expect(decoded.payloadBinary, isNull);
    });

    test('encodes and decodes binary CastWireMessage and 4-byte BE frame', () {
      final binary = Uint8List.fromList([1, 2, 3, 4, 255]);
      final msg = CastWireMessage(
        protocolVersion: 0,
        sourceId: 'sender-0',
        destinationId: 'tr-1',
        namespace: 'urn:x-cast:com.google.cast.media',
        payloadType: 1,
        payloadBinary: binary,
      );

      final encoded = ChromecastService.encodeCastMessage(msg);
      final decoded = ChromecastService.decodeCastMessage(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.payloadType, equals(1));
      expect(decoded.payloadUtf8, isNull);
      expect(decoded.payloadBinary, orderedEquals([1, 2, 3, 4, 255]));

      final frame = ChromecastService.encodeCastFrame(msg);
      expect(frame.length, equals(4 + encoded.length));
      final prefixLen = ByteData.sublistView(frame).getUint32(0, Endian.big);
      expect(prefixLen, equals(encoded.length));
      expect(frame.sublist(4), orderedEquals(encoded));
    });
  });

  group('mDNS Query & RFC 1035 Parser', () {
    test('buildMdnsPtrQuery emits valid PTR query with QU bit', () {
      final query = ChromecastService.buildMdnsPtrQuery(
        '_googlecast._tcp.local',
        unicastReply: true,
      );

      expect(query.length, greaterThan(16));
      final bd = ByteData.sublistView(query);
      expect(bd.getUint16(4, Endian.big), equals(1)); // QDCOUNT == 1
      expect(bd.getUint16(query.length - 4, Endian.big), equals(12)); // PTR
      expect(
        bd.getUint16(query.length - 2, Endian.big),
        equals(0x8001),
      ); // IN + QU
    });

    test('parseMdnsPacket decodes PTR, SRV, TXT, and A with RFC 1035 pointers', () {
      final packet = _buildSyntheticCastMdnsResponse();
      final records = ChromecastService.parseMdnsPacket(packet);

      expect(records, hasLength(4));

      final ptr = records.firstWhere((r) => r.type == 12);
      expect(ptr.name, equals('_googlecast._tcp.local'));
      expect(ptr.ptrTarget, equals('Living-Room._googlecast._tcp.local'));

      final srv = records.firstWhere((r) => r.type == 33);
      expect(srv.name, equals('Living-Room._googlecast._tcp.local'));
      expect(srv.srvTarget, equals('cast-host.local'));
      expect(srv.srvPort, equals(8009));

      final txt = records.firstWhere((r) => r.type == 16);
      expect(txt.name, equals('Living-Room._googlecast._tcp.local'));
      expect(txt.txt['id'], equals('abcd1234'));
      expect(txt.txt['fn'], equals('Living Room Speaker'));
      expect(txt.txt['md'], equals('Chromecast Audio'));
      expect(txt.txt['ca'], equals('4'));

      final a = records.firstWhere((r) => r.type == 1);
      expect(a.name, equals('cast-host.local'));
      expect(a.ipv4, equals('192.168.1.77'));
    });
  });

  group('Cast Sample Rate & Pass-Through Routing', () {
    test('resolveCastTargetSampleRate preserves 44.1k/48k families under ceilings', () {
      // 192 kHz ceiling
      expect(ChromecastService.resolveCastTargetSampleRate(44100, 192000), 44100);
      expect(ChromecastService.resolveCastTargetSampleRate(88200, 192000), 88200);
      expect(ChromecastService.resolveCastTargetSampleRate(176400, 192000), 176400);
      expect(ChromecastService.resolveCastTargetSampleRate(352800, 192000), 176400);
      expect(ChromecastService.resolveCastTargetSampleRate(48000, 192000), 48000);
      expect(ChromecastService.resolveCastTargetSampleRate(96000, 192000), 96000);
      expect(ChromecastService.resolveCastTargetSampleRate(192000, 192000), 192000);
      expect(ChromecastService.resolveCastTargetSampleRate(384000, 192000), 192000);
      expect(ChromecastService.resolveCastTargetSampleRate(2822400, 192000), 176400);

      // 96 kHz ceiling
      expect(ChromecastService.resolveCastTargetSampleRate(176400, 96000), 88200);
      expect(ChromecastService.resolveCastTargetSampleRate(192000, 96000), 96000);
      expect(ChromecastService.resolveCastTargetSampleRate(2822400, 96000), 88200);

      // 48 kHz ceiling
      expect(ChromecastService.resolveCastTargetSampleRate(88200, 48000), 44100);
      expect(ChromecastService.resolveCastTargetSampleRate(96000, 48000), 48000);
      expect(ChromecastService.resolveCastTargetSampleRate(2822400, 48000), 44100);
    });

    test('canPassThroughDirectly enforces ceiling, depth, float, DSD, clip & ALAC rules', () {
      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/track.flac'),
          isClipped: false,
          sampleRate: 192000,
          bitDepth: 24,
          isFloat: false,
          ceilingRate: 192000,
        ),
        isTrue,
      );

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/track.flac'),
          isClipped: false,
          sampleRate: 192000,
          bitDepth: 24,
          isFloat: false,
          ceilingRate: 96000,
        ),
        isFalse,
      );

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/float32.wav'),
          isClipped: false,
          sampleRate: 48000,
          bitDepth: 32,
          isFloat: true,
          ceilingRate: 192000,
        ),
        isFalse,
      );

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/int32.wav'),
          isClipped: false,
          sampleRate: 48000,
          bitDepth: 32,
          isFloat: false,
          ceilingRate: 192000,
        ),
        isFalse,
      );

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/cue_track.flac'),
          isClipped: true,
          sampleRate: 44100,
          bitDepth: 16,
          isFloat: false,
          ceilingRate: 192000,
        ),
        isFalse,
      );

      for (final ext in const ['.dsf', '.dff', '.wv']) {
        expect(
          ChromecastService.canPassThroughDirectly(
            uri: Uri.parse('file:///music/dsd$ext'),
            isClipped: false,
            sampleRate: 44100,
            bitDepth: 16,
            isFloat: false,
            ceilingRate: 192000,
          ),
          isFalse,
        );
      }

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/alac_track.m4a'),
          isClipped: false,
          sampleRate: 96000,
          bitDepth: 24,
          isFloat: false,
          ceilingRate: 192000,
          isChromecast: true,
          formatName: 'ALAC',
        ),
        isFalse,
      );

      expect(
        ChromecastService.canPassThroughDirectly(
          uri: Uri.parse('file:///music/alac_track.m4a'),
          isClipped: false,
          sampleRate: 96000,
          bitDepth: 24,
          isFloat: false,
          ceilingRate: 192000,
          isChromecast: false,
          formatName: 'ALAC',
        ),
        isTrue,
      );
    });
  });

  group('LocalMediaServer 24-bit LPCM WAV Header', () {
    test('buildWavHeader24Bit produces valid 24-bit / 192 kHz stereo RIFF header', () {
      final hdr = LocalMediaServer.buildWavHeader24Bit(
        sampleRate: 192000,
        channels: 2,
      );

      expect(hdr.length, equals(44));
      expect(ascii.decode(hdr.sublist(0, 4)), equals('RIFF'));
      expect(ascii.decode(hdr.sublist(8, 12)), equals('WAVE'));
      expect(ascii.decode(hdr.sublist(12, 16)), equals('fmt '));
      expect(ascii.decode(hdr.sublist(36, 40)), equals('data'));

      final bd = ByteData.sublistView(hdr);
      expect(bd.getUint16(20, Endian.little), equals(1)); // PCM format = 1
      expect(bd.getUint16(22, Endian.little), equals(2)); // channels
      expect(bd.getUint32(24, Endian.little), equals(192000)); // sample rate
      expect(bd.getUint32(28, Endian.little), equals(1152000)); // 192000 * 6
      expect(bd.getUint16(32, Endian.little), equals(6)); // blockAlign = 2 * 3
      expect(bd.getUint16(34, Endian.little), equals(24)); // bitsPerSample
    });
  });

  group('Native AudioEngineFFI Cast Tap Smoke Test', () {
    test('toggles local mute and cast PCM tap when Windows DLL is present', () {
      String? dllPath;
      if (Platform.isWindows) {
        if (File('../audio_engine.dll').existsSync()) {
          dllPath = '../audio_engine.dll';
        } else if (File('audio_engine.dll').existsSync()) {
          dllPath = 'audio_engine.dll';
        }
      }

      if (dllPath == null) {
        return;
      }

      final engine = AudioEngineFFI(libraryPath: dllPath);
      final created = engine.create(sampleRate: 48000, channels: 2);
      expect(created, isTrue);

      try {
        engine.setLocalOutputMuted(true);
        expect(engine.getLocalOutputMuted(), isTrue);
        engine.setLocalOutputMuted(false);
        expect(engine.getLocalOutputMuted(), isFalse);

        engine.setCastPcmTapEnabled(true, bypassDsp: true);
        expect(engine.getCastPcmTapEnabled(), isTrue);
        engine.flushCastPcmTap();
        engine.setCastPcmTapEnabled(false);
        expect(engine.getCastPcmTapEnabled(), isFalse);
      } finally {
        engine.dispose();
      }
    });
  });
}
