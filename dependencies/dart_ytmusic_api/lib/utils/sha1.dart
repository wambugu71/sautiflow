import 'dart:convert';
import 'dart:typed_data';

/// Pure Dart SHA-1 implementation (RFC 3174) with zero external dependencies.
String computeSha1(String input) {
  final bytes = utf8.encode(input);
  final bitLength = bytes.length * 8;

  // Pre-processing (Padding)
  final paddedLength = ((bytes.length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLength);
  padded.setAll(0, bytes);
  padded[bytes.length] = 0x80;

  final byteData = ByteData.view(padded.buffer);
  byteData.setUint64(paddedLength - 8, bitLength, Endian.big);

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  final w = Uint32List(80);

  for (var i = 0; i < paddedLength; i += 64) {
    for (var t = 0; t < 16; t++) {
      w[t] = byteData.getUint32(i + t * 4, Endian.big);
    }
    for (var t = 16; t < 80; t++) {
      final v = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16];
      w[t] = ((v << 1) | (v >>> 31)) & 0xFFFFFFFF;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;

    for (var t = 0; t < 80; t++) {
      int f;
      int k;
      if (t < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5A827999;
      } else if (t < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (t < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }

      final temp = (((a << 5) | (a >>> 27)) + f + e + k + w[t]) & 0xFFFFFFFF;
      e = d;
      d = c;
      c = ((b << 30) | (b >>> 2)) & 0xFFFFFFFF;
      b = a;
      a = temp;
    }

    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
  }

  String hex32(int val) => val.toRadixString(16).padLeft(8, '0');
  return '${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}${hex32(h4)}';
}
