import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WavParseResult {
  final Float32List samples;
  final int sampleRate;
  final int channels; // 1 = mono, 2 = stereo, 4 = true-stereo [LL, LR, RL, RR]
  final int sourceChannels;
  final bool channelWarning;
  final bool truncatedData;

  const WavParseResult({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.sourceChannels,
    this.channelWarning = false,
    this.truncatedData = false,
  });
}

class WavParser {
  static const int _maxFramesCap = 30 * 192000; // 30s @ 192 kHz hard cap

  static Float32List parse(String path) {
    final bytes = File(path).readAsBytesSync();
    return parseBytes(bytes);
  }

  static Float32List parseBytes(Uint8List bytes) {
    final res = parseBytesDetailed(bytes);
    if (res.channels == 2) return res.samples;

    // Backwards-compatible stereo view for legacy callers expecting 2-ch
    final frameCount = res.samples.length ~/ res.channels;
    final stereo = Float32List(frameCount * 2);
    if (res.channels == 1) {
      for (int i = 0; i < frameCount; i++) {
        final v = res.samples[i];
        stereo[i * 2] = v;
        stereo[i * 2 + 1] = v;
      }
    } else if (res.channels == 4) {
      // [LL, LR, RL, RR] -> fallback ipsilateral [LL, RR]
      for (int i = 0; i < frameCount; i++) {
        stereo[i * 2] = res.samples[i * 4];
        stereo[i * 2 + 1] = res.samples[i * 4 + 3];
      }
    }
    return stereo;
  }

  static WavParseResult parseDetailed(String path) {
    final bytes = File(path).readAsBytesSync();
    return parseBytesDetailed(bytes);
  }

  static WavParseResult parseBytesDetailed(Uint8List bytes) {
    if (bytes.lengthInBytes < 12) {
      throw Exception('Invalid WAV file: too small');
    }
    final data =
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);

    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final bool isRf64 = riff == 'RF64';
    if (riff != 'RIFF' && !isRf64) {
      throw Exception('Not a RIFF/RF64 file');
    }

    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw Exception('Not a WAVE file');
    }

    int offset = 12;
    bool hasFmt = false;
    int numChannels = 1;
    int sampleRate = 44100;
    int bitsPerSample = 16;
    int audioFormat = 1;

    int ds64DataSize = -1;
    int dataOffset = -1;
    int declaredDataSize = -1;

    while (offset + 8 <= bytes.lengthInBytes) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final payloadStart = offset + 8;

      if (chunkId == 'ds64' && isRf64 && chunkSize >= 28 && payloadStart + 24 <= bytes.lengthInBytes) {
        // ds64: riffSize(8), dataSize(8), sampleCount(8), tableLength(4)
        final ds64Data = data.getUint64(payloadStart + 8, Endian.little);
        if (ds64Data <= 0x7FFFFFFF) {
          ds64DataSize = ds64Data;
        }
      } else if (chunkId == 'fmt ') {
        if (chunkSize < 16 || payloadStart + 16 > bytes.lengthInBytes) {
          throw Exception('Invalid fmt chunk');
        }
        hasFmt = true;
        audioFormat = data.getUint16(payloadStart, Endian.little);
        numChannels = data.getUint16(payloadStart + 2, Endian.little);
        sampleRate = data.getUint32(payloadStart + 4, Endian.little);
        bitsPerSample = data.getUint16(payloadStart + 14, Endian.little);
        if (audioFormat == 65534 &&
            chunkSize >= 40 &&
            payloadStart + 40 <= bytes.lengthInBytes) {
          // WAVE_FORMAT_EXTENSIBLE: SubFormat first 2 bytes at offset +24 inside fmt payload
          audioFormat = data.getUint16(payloadStart + 24, Endian.little);
        }
      } else if (chunkId == 'data') {
        dataOffset = payloadStart;
        if (isRf64 && chunkSize == 0xFFFFFFFF && ds64DataSize >= 0) {
          declaredDataSize = ds64DataSize;
        } else {
          declaredDataSize = chunkSize;
        }
        break;
      }

      // RIFF chunks are word-aligned; odd-sized chunks have 1 pad byte.
      final paddedSize = chunkSize + (chunkSize & 1);
      final nextOffset = payloadStart + paddedSize;
      if (nextOffset <= offset) {
        break; // guard against overflow/wraparound
      }
      offset = nextOffset;
    }

    if (!hasFmt) {
      throw Exception('fmt chunk not found');
    }
    if (dataOffset == -1 || declaredDataSize < 0) {
      throw Exception('Data chunk not found');
    }
    if (numChannels <= 0 || numChannels > 254) {
      throw Exception('Invalid channel count: $numChannels');
    }
    if (sampleRate <= 0) {
      throw Exception('Invalid sample rate: $sampleRate');
    }
    if (bitsPerSample != 8 &&
        bitsPerSample != 16 &&
        bitsPerSample != 24 &&
        bitsPerSample != 32 &&
        bitsPerSample != 64) {
      throw Exception('Unsupported bit depth: $bitsPerSample');
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final bytesPerFrame = bytesPerSample * numChannels;
    final availableBytes = math.max(0, bytes.lengthInBytes - dataOffset);
    final bool truncatedData = declaredDataSize > availableBytes;
    final effectiveBytes = math.min(declaredDataSize, availableBytes);
    final availableFrames = effectiveBytes ~/ bytesPerFrame;
    final maxFrames = math.min(_maxFramesCap, math.max(1, sampleRate * 30));
    final frameCount = math.min(availableFrames, maxFrames);

    final int outChannels;
    bool channelWarning = false;
    if (numChannels == 1) {
      outChannels = 1;
    } else if (numChannels == 2) {
      outChannels = 2;
    } else if (numChannels == 4 || numChannels == 7 || numChannels == 14) {
      outChannels = 4; // True-stereo [LL, LR, RL, RR]
    } else {
      outChannels = 2;
      channelWarning = true;
    }

    final out = Float32List(frameCount * outChannels);

    if (audioFormat == 1) {
      if (bitsPerSample == 8) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final val = (bytes[frameBase + c] - 128) / 128.0;
            _routeSample(out, i, c, numChannels, outChannels, val);
          }
        }
      } else if (bitsPerSample == 16) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final sample = data.getInt16(frameBase + c * 2, Endian.little);
            _routeSample(out, i, c, numChannels, outChannels, sample / 32768.0);
          }
        }
      } else if (bitsPerSample == 24) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final off = frameBase + c * 3;
            int sample =
                bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16);
            if ((sample & 0x800000) != 0) {
              sample |= 0xFF000000;
            }
            _routeSample(
                out, i, c, numChannels, outChannels, sample.toSigned(32) / 8388608.0);
          }
        }
      } else if (bitsPerSample == 32) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final sample = data.getInt32(frameBase + c * 4, Endian.little);
            _routeSample(
                out, i, c, numChannels, outChannels, sample / 2147483648.0);
          }
        }
      } else {
        throw Exception('Unsupported bit depth for PCM: $bitsPerSample');
      }
    } else if (audioFormat == 3) {
      if (bitsPerSample == 32) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final val = data.getFloat32(frameBase + c * 4, Endian.little);
            _routeSample(out, i, c, numChannels, outChannels, val);
          }
        }
      } else if (bitsPerSample == 64) {
        for (int i = 0; i < frameCount; i++) {
          final frameBase = dataOffset + i * bytesPerFrame;
          for (int c = 0; c < numChannels; c++) {
            final val = data.getFloat64(frameBase + c * 8, Endian.little);
            _routeSample(out, i, c, numChannels, outChannels, val);
          }
        }
      } else {
        throw Exception('Unsupported bit depth for Float: $bitsPerSample');
      }
    } else {
      throw Exception('Unsupported audio format: $audioFormat');
    }

    return WavParseResult(
      samples: out,
      sampleRate: sampleRate,
      channels: outChannels,
      sourceChannels: numChannels,
      channelWarning: channelWarning,
      truncatedData: truncatedData,
    );
  }

  static void _routeSample(
    Float32List out,
    int frameIndex,
    int channel,
    int numChannels,
    int outChannels,
    double val,
  ) {
    if (numChannels == 1) {
      out[frameIndex] = val;
    } else if (numChannels == 4 && outChannels == 4) {
      if (channel < 4) {
        out[frameIndex * 4 + channel] = val;
      }
    } else if (numChannels == 7 && outChannels == 4) {
      // Symmetric 7-channel HeSuVi: [0]=LL/RR, [1]=LR/RL
      if (channel == 0) {
        out[frameIndex * 4 + 0] = val;
        out[frameIndex * 4 + 3] = val;
      } else if (channel == 1) {
        out[frameIndex * 4 + 1] = val;
        out[frameIndex * 4 + 2] = val;
      }
    } else if (numChannels == 14 && outChannels == 4) {
      // Full 14-channel HeSuVi: [0]=LL, [1]=LR, [8]=RL, [7]=RR
      if (channel == 0) {
        out[frameIndex * 4 + 0] = val;
      } else if (channel == 1) {
        out[frameIndex * 4 + 1] = val;
      } else if (channel == 8) {
        out[frameIndex * 4 + 2] = val;
      } else if (channel == 7) {
        out[frameIndex * 4 + 3] = val;
      }
    } else if (channel < 2 && outChannels == 2) {
      out[frameIndex * 2 + channel] = val;
    }
  }
}
