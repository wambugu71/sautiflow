import 'dart:io';
import 'dart:typed_data';

class WavParser {
  static Float32List parse(String path) {
    final bytes = File(path).readAsBytesSync();
    return parseBytes(bytes);
  }

  static Float32List parseBytes(Uint8List bytes) {
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);

    if (bytes.length < 44) {
      throw Exception('Invalid WAV file: too small');
    }

    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') {
      throw Exception('Not a RIFF file');
    }

    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw Exception('Not a WAVE file');
    }

    int offset = 12;
    int numChannels = 1;
    int bitsPerSample = 16;
    int audioFormat = 1;
    
    int dataOffset = -1;
    int dataSize = -1;

    while (offset < bytes.length) {
      if (offset + 8 > bytes.length) break;
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      
      if (chunkId == 'fmt ') {
        audioFormat = data.getUint16(offset + 8, Endian.little);
        numChannels = data.getUint16(offset + 10, Endian.little);
        // sampleRate = data.getUint32(offset + 12, Endian.little);
        // byteRate = data.getUint32(offset + 16, Endian.little);
        // blockAlign = data.getUint16(offset + 20, Endian.little);
        bitsPerSample = data.getUint16(offset + 22, Endian.little);
        if (audioFormat == 65534 && chunkSize >= 40) {
          // WAVE_FORMAT_EXTENSIBLE: real format code lives in SubFormat GUID
          audioFormat = data.getUint16(offset + 32, Endian.little);
        }
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break; // found data, we can stop parsing chunks
      }
      offset += 8 + chunkSize;
    }

    if (dataOffset == -1) {
      throw Exception('Data chunk not found');
    }

    int numSamples = dataSize ~/ (bitsPerSample ~/ 8);
    int frameCount = numSamples ~/ numChannels;
    
    // Always output stereo (2 channels)
    final floatList = Float32List(frameCount * 2);

    if (audioFormat == 1) { // PCM
      if (bitsPerSample == 16) {
        for (int i = 0; i < frameCount; i++) {
          for (int c = 0; c < numChannels; c++) {
            int byteOffset = dataOffset + (i * numChannels + c) * 2;
            if (byteOffset + 2 > bytes.length) break;
            int sample = data.getInt16(byteOffset, Endian.little);
            double val = sample / 32768.0;
            if (numChannels == 1) {
              floatList[i * 2] = val;     // L
              floatList[i * 2 + 1] = val; // R
            } else if (c < 2) {
              floatList[i * 2 + c] = val;
            }
          }
        }
      } else if (bitsPerSample == 24) {
        for (int i = 0; i < frameCount; i++) {
          for (int c = 0; c < numChannels; c++) {
            int byteOffset = dataOffset + (i * numChannels + c) * 3;
            if (byteOffset + 3 > bytes.length) break;
            int sample = bytes[byteOffset] | (bytes[byteOffset + 1] << 8) | (bytes[byteOffset + 2] << 16);
            if ((sample & 0x800000) != 0) {
              sample |= 0xFF000000;
            }
            double val = sample.toSigned(32) / 8388608.0;
            if (numChannels == 1) {
              floatList[i * 2] = val;
              floatList[i * 2 + 1] = val;
            } else if (c < 2) {
              floatList[i * 2 + c] = val;
            }
          }
        }
      } else if (bitsPerSample == 32) {
        for (int i = 0; i < frameCount; i++) {
          for (int c = 0; c < numChannels; c++) {
            int byteOffset = dataOffset + (i * numChannels + c) * 4;
            if (byteOffset + 4 > bytes.length) break;
            int sample = data.getInt32(byteOffset, Endian.little);
            double val = sample / 2147483648.0;
            if (numChannels == 1) {
              floatList[i * 2] = val;
              floatList[i * 2 + 1] = val;
            } else if (c < 2) {
              floatList[i * 2 + c] = val;
            }
          }
        }
      } else {
        throw Exception('Unsupported bit depth for PCM: $bitsPerSample');
      }
    } else if (audioFormat == 3) { // IEEE Float
      if (bitsPerSample == 32) {
        for (int i = 0; i < frameCount; i++) {
          for (int c = 0; c < numChannels; c++) {
            int byteOffset = dataOffset + (i * numChannels + c) * 4;
            if (byteOffset + 4 > bytes.length) break;
            double val = data.getFloat32(byteOffset, Endian.little);
            if (numChannels == 1) {
              floatList[i * 2] = val;
              floatList[i * 2 + 1] = val;
            } else if (c < 2) {
              floatList[i * 2 + c] = val;
            }
          }
        }
      } else {
        throw Exception('Unsupported bit depth for Float: $bitsPerSample');
      }
    } else {
      throw Exception('Unsupported audio format: $audioFormat');
    }

    return floatList;
  }
}
