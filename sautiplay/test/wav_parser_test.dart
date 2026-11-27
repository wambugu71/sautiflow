import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/wav_parser.dart';

Uint8List _buildWav({
  required String riffTag,
  required int audioFormat,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required List<int> dataBytes,
  List<int> extraPaddingChunk = const [],
  bool extensible = false,
  int? overrideDataSize,
  int? ds64DataSize,
}) {
  final out = BytesBuilder();
  final header = ByteData(12);
  out.add(riffTag.codeUnits);
  out.add(Uint8List(4)); // placeholder RIFF size
  out.add('WAVE'.codeUnits);

  if (ds64DataSize != null) {
    final ds64 = ByteData(28);
    ds64.setUint64(0, 0, Endian.little);
    ds64.setUint64(8, ds64DataSize, Endian.little);
    ds64.setUint64(16, 0, Endian.little);
    ds64.setUint32(24, 0, Endian.little);
    out.add('ds64'.codeUnits);
    final sz = ByteData(4)..setUint32(0, 28, Endian.little);
    out.add(sz.buffer.asUint8List());
    out.add(ds64.buffer.asUint8List());
  }

  if (extraPaddingChunk.isNotEmpty) {
    out.add('LIST'.codeUnits);
    final sz = ByteData(4)..setUint32(0, extraPaddingChunk.length, Endian.little);
    out.add(sz.buffer.asUint8List());
    out.add(extraPaddingChunk);
    if (extraPaddingChunk.length.isOdd) {
      out.addByte(0); // RIFF word alignment padding byte
    }
  }

  final fmtSize = extensible ? 40 : 16;
  final fmt = ByteData(fmtSize);
  fmt.setUint16(0, extensible ? 65534 : audioFormat, Endian.little);
  fmt.setUint16(2, channels, Endian.little);
  fmt.setUint32(4, sampleRate, Endian.little);
  fmt.setUint32(8, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little);
  fmt.setUint16(12, channels * (bitsPerSample ~/ 8), Endian.little);
  fmt.setUint16(14, bitsPerSample, Endian.little);
  if (extensible) {
    fmt.setUint16(16, 22, Endian.little);
    fmt.setUint16(18, bitsPerSample, Endian.little);
    fmt.setUint32(24, audioFormat, Endian.little);
  }
  out.add('fmt '.codeUnits);
  out.add((ByteData(4)..setUint32(0, fmtSize, Endian.little)).buffer.asUint8List());
  out.add(fmt.buffer.asUint8List());

  out.add('data'.codeUnits);
  final declared = overrideDataSize ?? dataBytes.length;
  out.add((ByteData(4)..setUint32(0, declared, Endian.little)).buffer.asUint8List());
  out.add(dataBytes);
  if (dataBytes.length.isOdd) {
    out.addByte(0);
  }

  final bytes = out.toBytes();
  ByteData.view(bytes.buffer).setUint32(
      4, (riffTag == 'RF64') ? 0xFFFFFFFF : bytes.length - 8, Endian.little);
  final _ = header;
  return bytes;
}

void main() {
  test('parses sample rate and skips odd-sized RIFF LIST padding byte', () {
    final pcm = ByteData(8);
    pcm.setInt16(0, 16384, Endian.little); // L = 0.5
    pcm.setInt16(2, -16384, Endian.little); // R = -0.5
    pcm.setInt16(4, 8192, Endian.little); // L = 0.25
    pcm.setInt16(6, 0, Endian.little); // R = 0.0

    final bytes = _buildWav(
      riffTag: 'RIFF',
      audioFormat: 1,
      channels: 2,
      sampleRate: 44100,
      bitsPerSample: 16,
      dataBytes: pcm.buffer.asUint8List(),
      extraPaddingChunk: [1, 2, 3, 4, 5], // odd length 5 + 1 pad byte
    );

    final res = WavParser.parseBytesDetailed(bytes);
    expect(res.sampleRate, 44100);
    expect(res.channels, 2);
    expect(res.samples.length, 4);
    expect(res.samples[0], closeTo(0.5, 1e-4));
    expect(res.samples[1], closeTo(-0.5, 1e-4));
    expect(res.samples[2], closeTo(0.25, 1e-4));
    expect(res.channelWarning, isFalse);
  });

  test('supports 8-bit PCM, 64-bit IEEE float, and RF64 ds64', () {
    // 8-bit unsigned PCM
    final wav8 = _buildWav(
      riffTag: 'RIFF',
      audioFormat: 1,
      channels: 1,
      sampleRate: 48000,
      bitsPerSample: 8,
      dataBytes: [128, 255, 0],
    );
    final res8 = WavParser.parseBytesDetailed(wav8);
    expect(res8.sampleRate, 48000);
    expect(res8.channels, 1);
    expect(res8.samples[0], closeTo(0.0, 1e-6));
    expect(res8.samples[1], closeTo(127.0 / 128.0, 1e-5));
    expect(res8.samples[2], closeTo(-1.0, 1e-5));

    // 64-bit IEEE float
    final f64 = ByteData(16);
    f64.setFloat64(0, 0.75, Endian.little);
    f64.setFloat64(8, -0.25, Endian.little);
    final wav64 = _buildWav(
      riffTag: 'RF64',
      audioFormat: 3,
      channels: 2,
      sampleRate: 96000,
      bitsPerSample: 64,
      dataBytes: f64.buffer.asUint8List(),
      overrideDataSize: 0xFFFFFFFF,
      ds64DataSize: 16,
    );
    final res64 = WavParser.parseBytesDetailed(wav64);
    expect(res64.sampleRate, 96000);
    expect(res64.channels, 2);
    expect(res64.samples[0], closeTo(0.75, 1e-6));
    expect(res64.samples[1], closeTo(-0.25, 1e-6));
  });

  test('routes 4-ch, 7-ch, and 14-ch HeSuVi to true-stereo and warns on 5-ch', () {
    // 14-ch single frame: ch0=0.9 (LL), ch1=0.2 (LR), ch7=0.8 (RR), ch8=0.3 (RL)
    final f14 = ByteData(14 * 4);
    f14.setFloat32(0 * 4, 0.9, Endian.little);
    f14.setFloat32(1 * 4, 0.2, Endian.little);
    f14.setFloat32(7 * 4, 0.8, Endian.little);
    f14.setFloat32(8 * 4, 0.3, Endian.little);
    final res14 = WavParser.parseBytesDetailed(_buildWav(
      riffTag: 'RIFF',
      audioFormat: 3,
      channels: 14,
      sampleRate: 44100,
      bitsPerSample: 32,
      extensible: true,
      dataBytes: f14.buffer.asUint8List(),
    ));
    expect(res14.channels, 4);
    expect(res14.channelWarning, isFalse);
    expect(res14.samples[0], closeTo(0.9, 1e-6));
    expect(res14.samples[1], closeTo(0.2, 1e-6));
    expect(res14.samples[2], closeTo(0.3, 1e-6));
    expect(res14.samples[3], closeTo(0.8, 1e-6));

    // 7-ch symmetric HeSuVi: [0]=0.7, [1]=0.15 -> [0.7, 0.15, 0.15, 0.7]
    final f7 = ByteData(7 * 4);
    f7.setFloat32(0, 0.7, Endian.little);
    f7.setFloat32(4, 0.15, Endian.little);
    final res7 = WavParser.parseBytesDetailed(_buildWav(
      riffTag: 'RIFF',
      audioFormat: 3,
      channels: 7,
      sampleRate: 44100,
      bitsPerSample: 32,
      dataBytes: f7.buffer.asUint8List(),
    ));
    expect(res7.channels, 4);
    expect(res7.samples[0], closeTo(0.7, 1e-6));
    expect(res7.samples[1], closeTo(0.15, 1e-6));
    expect(res7.samples[2], closeTo(0.15, 1e-6));
    expect(res7.samples[3], closeTo(0.7, 1e-6));

    // 5-ch sets channelWarning
    final f5 = ByteData(5 * 4);
    f5.setFloat32(0, 0.5, Endian.little);
    f5.setFloat32(4, 0.4, Endian.little);
    final res5 = WavParser.parseBytesDetailed(_buildWav(
      riffTag: 'RIFF',
      audioFormat: 3,
      channels: 5,
      sampleRate: 48000,
      bitsPerSample: 32,
      dataBytes: f5.buffer.asUint8List(),
    ));
    expect(res5.channels, 2);
    expect(res5.channelWarning, isTrue);
  });

  test('clamps malformed huge dataSize safely without OOM', () {
    final pcm = ByteData(4);
    pcm.setInt16(0, 16384, Endian.little);
    pcm.setInt16(2, -16384, Endian.little);
    final malformed = _buildWav(
      riffTag: 'RIFF',
      audioFormat: 1,
      channels: 2,
      sampleRate: 48000,
      bitsPerSample: 16,
      dataBytes: pcm.buffer.asUint8List(),
      overrideDataSize: 0x7FFFFFF0, // absurdly huge declared dataSize
    );

    final res = WavParser.parseBytesDetailed(malformed);
    expect(res.truncatedData, isTrue);
    expect(res.samples.length, 2); // only 1 complete frame available
    expect(res.samples[0], closeTo(0.5, 1e-4));
    expect(res.samples[1], closeTo(-0.5, 1e-4));
  });
}
