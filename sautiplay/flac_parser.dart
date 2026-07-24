import 'dart:io';

int? getFlacBitDepth(String path) {
  try {
    final file = File(path);
    final raf = file.openSync();
    final header = raf.readSync(4);
    if (String.fromCharCodes(header) != 'fLaC') {
      raf.closeSync();
      return null;
    }
    
    // Read METADATA_BLOCK_HEADER
    final blockHeader = raf.readSync(4);
    final isLast = (blockHeader[0] & 0x80) != 0;
    final blockType = blockHeader[0] & 0x7F;
    final blockLength = (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];
    
    if (blockType == 0 && blockLength == 34) {
      final streamInfo = raf.readSync(34);
      
      // Bits per sample is in bytes 12 and 13 of STREAMINFO
      // 20 bits sample rate, 3 bits channels, 5 bits bits_per_sample
      // bytes 10-12 (3 bytes): 
      // byte 10: sample rate high 8 bits
      // byte 11: sample rate mid 8 bits
      // byte 12: sample rate low 4 bits, channels 3 bits, bits_per_sample high 1 bit
      // byte 13: bits_per_sample low 4 bits, total samples high 4 bits
      final b12 = streamInfo[12];
      final b13 = streamInfo[13];
      
      final bitsPerSample = (((b12 & 0x01) << 4) | ((b13 & 0xF0) >> 4)) + 1;
      raf.closeSync();
      return bitsPerSample;
    }
    
    raf.closeSync();
    return null;
  } catch (e) {
    return null;
  }
}

void main() {
  print(getFlacBitDepth("dummy.flac"));
}
