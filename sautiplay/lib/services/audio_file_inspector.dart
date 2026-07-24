import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import '../isolate_player.dart';

class AudioFileInfo {
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final int bitrateKbps;
  final String codec;
  final bool isFloat;

  const AudioFileInfo({
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
    required this.bitrateKbps,
    required this.codec,
    this.isFloat = false,
  });

  String get formattedSampleRate {
    if (sampleRate <= 0) return '44.1 kHz';
    if (sampleRate % 1000 == 0) {
      return '${sampleRate ~/ 1000}.0 kHz';
    }
    final double kHz = sampleRate / 1000.0;
    return '${kHz.toStringAsFixed(1)} kHz';
  }

  String get formattedBitDepth {
    if (isFloat) return '$bitDepth bit float';
    if (bitDepth > 0) return '$bitDepth bit';
    if (bitrateKbps > 0) return '$bitrateKbps kbps';
    return '16 bit';
  }

  String get formattedChannels {
    if (channels == 1) return 'MONO';
    if (channels == 2) return 'STEREO';
    if (channels > 2) return '$channels CHANNELS';
    return 'STEREO';
  }
}

class AudioFileInspector {
  static Future<AudioFileInfo> inspectNative(IsolateAudioPlayer player, String filePath) async {
    try {
      final nativeMap = await player.inspectFile(filePath);
      if (nativeMap != null) {
        final sr = (nativeMap['sampleRate'] as int?) ?? 44100;
        final bd = (nativeMap['bitDepth'] as int?) ?? 16;
        final ch = (nativeMap['channels'] as int?) ?? 2;
        final br = (nativeMap['bitrateKbps'] as int?) ?? 0;
        final isFloat = (nativeMap['isFloat'] as bool?) ?? false;
        final fmt = (nativeMap['formatName'] as String?) ?? 'AUDIO';

        return AudioFileInfo(
          sampleRate: sr > 0 ? sr : 44100,
          bitDepth: bd > 0 ? bd : 16,
          channels: ch > 0 ? ch : 2,
          bitrateKbps: br,
          codec: fmt,
          isFloat: isFloat,
        );
      }
    } catch (e) {
      debugPrint('[AudioFileInspector] Native inspect error: $e');
    }
    return inspect(filePath);
  }

  static Future<AudioFileInfo> inspect(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const AudioFileInfo(
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        bitrateKbps: 0,
        codec: 'AUDIO',
      );
    }

    try {
      final ext = filePath.split('.').last.toLowerCase();
      final raf = file.openSync();
      try {
        final fileSize = file.lengthSync();
        final readLen = math.min(1024 * 1024, fileSize); // Read up to 1 MB for headers
        final bytes = raf.readSync(readLen);

        if (ext == 'flac' || _indexOfBytes(bytes, [102, 76, 97, 67]) != -1) {
          final info = _parseFlac(bytes);
          if (info != null) return info;
        }

        if (ext == 'wav' || _startsWithBytes(bytes, [82, 73, 70, 70])) {
          final info = _parseWav(bytes);
          if (info != null) return info;
        }

        if (ext == 'mp3' || _hasMp3Header(bytes)) {
          final info = _parseMp3(bytes);
          if (info != null) return info;
        }

        if (ext == 'm4a' || ext == 'mp4' || ext == 'aac' || ext == 'alac') {
          final info = _parseM4a(bytes);
          if (info != null) return info;
        }

        if (ext == 'aiff' || ext == 'aif') {
          final info = _parseAiff(bytes);
          if (info != null) return info;
        }
      } finally {
        raf.closeSync();
      }

      // Fallback: use audio_metadata_reader
      try {
        final meta = amr.readMetadata(file, getImage: false);
        final sr = meta.sampleRate ?? 44100;
        return AudioFileInfo(
          sampleRate: sr > 0 ? sr : 44100,
          bitDepth: 16,
          channels: 2,
          bitrateKbps: meta.bitrate ?? 0,
          codec: ext.toUpperCase(),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[AudioFileInspector] Error inspecting $filePath: $e');
    }

    return const AudioFileInfo(
      sampleRate: 44100,
      bitDepth: 16,
      channels: 2,
      bitrateKbps: 0,
      codec: 'AUDIO',
    );
  }

  // ── FLAC Parser ──────────────────────────────────────────────────────────
  static AudioFileInfo? _parseFlac(Uint8List bytes) {
    final flacOffset = _indexOfBytes(bytes, [102, 76, 97, 67]); // 'fLaC'
    if (flacOffset == -1) return null;

    int pos = flacOffset + 4; // Skip 'fLaC'
    while (pos + 4 <= bytes.length) {
      final header0 = bytes[pos];
      final isLast = (header0 & 0x80) != 0;
      final blockType = header0 & 0x7F;
      final length = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      pos += 4;

      if (blockType == 0) {
        // STREAMINFO block (34 bytes)
        if (pos + 34 <= bytes.length) {
          final b10 = bytes[pos + 10];
          final b11 = bytes[pos + 11];
          final b12 = bytes[pos + 12];
          final b13 = bytes[pos + 13];

          final sampleRate = (b10 << 12) | (b11 << 4) | ((b12 & 0xF0) >> 4);
          final channels = ((b12 & 0x0E) >> 1) + 1;
          final bitsPerSample = (((b12 & 0x01) << 4) | ((b13 & 0xF0) >> 4)) + 1;

          return AudioFileInfo(
            sampleRate: sampleRate > 0 ? sampleRate : 44100,
            bitDepth: bitsPerSample > 0 ? bitsPerSample : 16,
            channels: channels > 0 ? channels : 2,
            bitrateKbps: 0,
            codec: 'FLAC',
          );
        }
      }

      if (isLast) break;
      pos += length;
    }
    return null;
  }

  // ── WAV Parser ───────────────────────────────────────────────────────────
  static AudioFileInfo? _parseWav(Uint8List bytes) {
    final fmtOffset = _indexOfBytes(bytes, [102, 109, 116, 32]); // 'fmt '
    if (fmtOffset == -1 || fmtOffset + 24 > bytes.length) return null;

    final audioFormat = bytes[fmtOffset + 8] | (bytes[fmtOffset + 9] << 8);
    final channels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
    final sampleRate = bytes[fmtOffset + 12] |
        (bytes[fmtOffset + 13] << 8) |
        (bytes[fmtOffset + 14] << 16) |
        (bytes[fmtOffset + 15] << 24);
    final byteRate = bytes[fmtOffset + 16] |
        (bytes[fmtOffset + 17] << 8) |
        (bytes[fmtOffset + 18] << 16) |
        (bytes[fmtOffset + 19] << 24);
    final bitsPerSample = bytes[fmtOffset + 22] | (bytes[fmtOffset + 23] << 8);

    final isFloat = (audioFormat == 3);
    final bitrateKbps = (byteRate * 8) ~/ 1000;

    return AudioFileInfo(
      sampleRate: sampleRate > 0 ? sampleRate : 44100,
      bitDepth: bitsPerSample > 0 ? bitsPerSample : 16,
      channels: channels > 0 ? channels : 2,
      bitrateKbps: bitrateKbps,
      codec: isFloat ? 'WAV (Float)' : 'WAV',
      isFloat: isFloat,
    );
  }

  // ── MP3 Parser ───────────────────────────────────────────────────────────
  static AudioFileInfo? _parseMp3(Uint8List bytes) {
    // Skip ID3v2 tag if present
    int startPos = 0;
    if (bytes.length >= 10 && _startsWithBytes(bytes, [73, 68, 51])) {
      final id3Size = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      startPos = 10 + id3Size;
    }

    const bitratesMpeg1L3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
    const bitratesMpeg2L3 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
    const sampleRatesMpeg1 = [44100, 48000, 32000];
    const sampleRatesMpeg2 = [22050, 24000, 16000];
    const sampleRatesMpeg25 = [11025, 12000, 8000];

    for (int i = startPos; i < bytes.length - 4; i++) {
      if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
        final b1 = bytes[i + 1];
        final b2 = bytes[i + 2];
        final b3 = bytes[i + 3];

        final mpegVer = (b1 >> 3) & 0x03; // 3 = V1, 2 = V2, 0 = V2.5
        final layer = (b1 >> 1) & 0x03;   // 1 = L3

        if (layer == 1) { // Layer III
          final bitrateIdx = (b2 >> 4) & 0x0F;
          final sampleRateIdx = (b2 >> 2) & 0x03;
          final channelMode = (b3 >> 6) & 0x03; // 3 = Mono, others = Stereo

          int sr = 44100;
          if (mpegVer == 3 && sampleRateIdx < sampleRatesMpeg1.length) {
            sr = sampleRatesMpeg1[sampleRateIdx];
          } else if (mpegVer == 2 && sampleRateIdx < sampleRatesMpeg2.length) {
            sr = sampleRatesMpeg2[sampleRateIdx];
          } else if (mpegVer == 0 && sampleRateIdx < sampleRatesMpeg25.length) {
            sr = sampleRatesMpeg25[sampleRateIdx];
          }

          int br = 0;
          if (mpegVer == 3 && bitrateIdx < bitratesMpeg1L3.length) {
            br = bitratesMpeg1L3[bitrateIdx];
          } else if (bitrateIdx < bitratesMpeg2L3.length) {
            br = bitratesMpeg2L3[bitrateIdx];
          }

          return AudioFileInfo(
            sampleRate: sr,
            bitDepth: 16,
            channels: channelMode == 3 ? 1 : 2,
            bitrateKbps: br,
            codec: 'MP3',
          );
        }
      }
    }
    return null;
  }

  // ── M4A / AAC / ALAC Parser ──────────────────────────────────────────────
  static AudioFileInfo? _parseM4a(Uint8List bytes) {
    // Check if ALAC atom is present
    final isAlac = _indexOfBytes(bytes, [97, 108, 97, 99]) != -1; // 'alac'
    final isMp4a = _indexOfBytes(bytes, [109, 112, 52, 97]) != -1; // 'mp4a'

    if (isAlac) {
      final alacPos = _indexOfBytes(bytes, [97, 108, 97, 99]);
      int bitDepth = 16;
      int sampleRate = 44100;
      int channels = 2;

      // ALAC cookie format (if present 28 bytes after 'alac')
      if (alacPos + 36 <= bytes.length) {
        final bSampleDepth = bytes[alacPos + 21];
        if (bSampleDepth > 0) bitDepth = bSampleDepth;
        final bNumChannels = bytes[alacPos + 25];
        if (bNumChannels > 0) channels = bNumChannels;
        final sr = (bytes[alacPos + 32] << 24) |
            (bytes[alacPos + 33] << 16) |
            (bytes[alacPos + 34] << 8) |
            bytes[alacPos + 35];
        if (sr > 0 && sr < 384000) sampleRate = sr;
      }

      return AudioFileInfo(
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
        bitrateKbps: 0,
        codec: 'ALAC (Apple Lossless)',
      );
    }

    if (isMp4a) {
      return const AudioFileInfo(
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        bitrateKbps: 256,
        codec: 'AAC',
      );
    }

    return null;
  }

  // ── AIFF Parser ──────────────────────────────────────────────────────────
  static AudioFileInfo? _parseAiff(Uint8List bytes) {
    final commOffset = _indexOfBytes(bytes, [67, 79, 77, 77]); // 'COMM'
    if (commOffset == -1 || commOffset + 18 > bytes.length) return null;

    final channels = (bytes[commOffset + 8] << 8) | bytes[commOffset + 9];
    final sampleSize = (bytes[commOffset + 14] << 8) | bytes[commOffset + 15];

    // Read 80-bit IEEE 754 float sample rate
    final exp = ((bytes[commOffset + 16] & 0x7F) << 8) | bytes[commOffset + 17];
    final mant = (bytes[commOffset + 18] << 24) |
        (bytes[commOffset + 19] << 16) |
        (bytes[commOffset + 20] << 8) |
        bytes[commOffset + 21];

    int sr = 44100;
    if (exp >= 16383) {
      sr = (mant >> (31 - (exp - 16383))).abs();
    }

    return AudioFileInfo(
      sampleRate: sr > 0 ? sr : 44100,
      bitDepth: sampleSize > 0 ? sampleSize : 16,
      channels: channels > 0 ? channels : 2,
      bitrateKbps: 0,
      codec: 'AIFF',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static bool _hasMp3Header(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (_startsWithBytes(bytes, [73, 68, 51])) return true; // ID3 tag
    for (int i = 0; i < math.min(1024, bytes.length - 2); i++) {
      if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) return true;
    }
    return false;
  }

  static bool _startsWithBytes(Uint8List data, List<int> pattern) {
    if (data.length < pattern.length) return false;
    for (int i = 0; i < pattern.length; i++) {
      if (data[i] != pattern[i]) return false;
    }
    return true;
  }

  static int _indexOfBytes(Uint8List data, List<int> pattern) {
    for (int i = 0; i <= data.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
