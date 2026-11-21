import 'dart:typed_data';

import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/dlna_renderer_service.dart';
import 'package:sautiplay/services/dlna_service.dart';
import 'package:sautiplay/services/local_media_server.dart';

void main() {
  group('DLNA DIDL-Lite metadata', () {
    test('setPlayURLXml includes audio class, artist, album, and artwork URI',
        () {
      final xml = XmlText.setPlayURLXml(
        'http://192.168.1.10:8080/stream.flac',
        title: 'Midnight & Blue',
        artist: 'The Quartet',
        album: 'Studio Sessions',
        artworkUrl: 'http://192.168.1.10:8080/artwork.jpg',
        duration: '0:04:12',
        type: AudioMime.flac,
      );

      expect(xml, contains('object.item.audioItem.musicTrack'));
      expect(xml, contains('http-get:*:audio/flac:*'));
      expect(xml, contains('Midnight &amp;amp; Blue'));
      expect(xml, contains('The Quartet'));
      expect(xml, contains('Studio Sessions'));
      expect(xml, contains('http://192.168.1.10:8080/artwork.jpg'));
      expect(xml, contains('&lt;DIDL-Lite'));
      expect(xml, isNot(contains('<upnp:artist>unknow</upnp:artist>')));
    });

    test('xmlUnescape + extractTag parses escaped CurrentURIMetaData', () {
      const escapedMeta =
          '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;'
          '&lt;item id=&quot;0&quot;&gt;'
          '&lt;dc:title&gt;Song Title&lt;/dc:title&gt;'
          '&lt;upnp:artist&gt;Real Artist&lt;/upnp:artist&gt;'
          '&lt;upnp:album&gt;Real Album&lt;/upnp:album&gt;'
          '&lt;upnp:albumArtURI&gt;http://192.168.1.10:8080/artwork.jpg&lt;/upnp:albumArtURI&gt;'
          '&lt;/item&gt;&lt;/DIDL-Lite&gt;';

      final unescaped = DlnaRendererService.xmlUnescape(escapedMeta);
      expect(DlnaRendererService.extractTag(unescaped, 'title'), 'Song Title');
      expect(
          DlnaRendererService.extractTag(unescaped, 'artist'), 'Real Artist');
      expect(DlnaRendererService.extractTag(unescaped, 'album'), 'Real Album');
      expect(
        DlnaRendererService.extractTag(unescaped, 'albumArtURI'),
        'http://192.168.1.10:8080/artwork.jpg',
      );
    });
  });

  group('LocalMediaServer 24-bit WAV header', () {
    test('builds 44-byte 24-bit 96kHz stereo header matching 0x7FFFF000 data',
        () {
      final hdr =
          LocalMediaServer.buildWavHeader24Bit(sampleRate: 96000, channels: 2);
      expect(hdr.length, 44);
      final bd = hdr.buffer.asByteData();
      // BitsPerSample at offset 34
      expect(bd.getUint16(34, Endian.little), 24);
      // SampleRate at offset 24
      expect(bd.getUint32(24, Endian.little), 96000);
      // DataSize at offset 40
      expect(bd.getUint32(40, Endian.little), 0x7FFFF000);
    });
  });

  group('DlnaRendererCapabilities negotiation', () {
    test('parses GetProtocolInfo Sink and selects L16/L24 when WAV absent',
        () {
      const soap = '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:GetProtocolInfoResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
      <Source></Source>
      <Sink>http-get:*:audio/mpeg:*,http-get:*:audio/L16;rate=48000;channels=2:DLNA.ORG_PN=LPCM</Sink>
    </u:GetProtocolInfoResponse>
  </s:Body>
</s:Envelope>''';

      final caps = DlnaRendererCapabilities.fromSoapResponse(soap);
      expect(caps.isKnown, isTrue);
      expect(caps.supportsMime('audio/mpeg'), isTrue);
      expect(caps.supportsMime('audio/flac'), isFalse);
      expect(caps.preferredLiveFormat(), LiveCastStreamFormat.lpcm16);
      expect(caps.maxSampleRateHz(), 48000);
    });

    test('prefers L24 over L16 when renderer advertises audio/L24', () {
      const soap =
          '<Sink>http-get:*:audio/L16;rate=48000:*,http-get:*:audio/L24;rate=96000;channels=2:*</Sink>';
      final caps = DlnaRendererCapabilities.fromSoapResponse(soap);
      expect(caps.preferredLiveFormat(), LiveCastStreamFormat.lpcm24);
      expect(caps.maxSampleRateHz(), 96000);
    });
  });
}
