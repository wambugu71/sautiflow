import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class VdcParser {
  static Map<String, List<double>> parse(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    
    if (bytes.length < 4) {
      throw Exception('VDC file is too small');
    }

    // Try parsing as text first
    try {
      final text = utf8.decode(bytes);
      return _parseTextVdc(text);
    } catch (e) {
      // If it fails to decode as UTF-8, it's likely binary
      return _parseBinaryVdc(bytes);
    }
  }

  static Map<String, List<double>> _parseTextVdc(String text) {
    final sections44100 = <double>[];
    final sections48000 = <double>[];

    final lines = text.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('<')) continue;

      if (line.startsWith('SR_44100:')) {
        final parts = line.substring(9).split(RegExp(r'[,;]'));
        for (var p in parts) {
          if (p.trim().isNotEmpty) sections44100.add(double.parse(p.trim()));
        }
      } else if (line.startsWith('SR_48000:')) {
        final parts = line.substring(9).split(RegExp(r'[,;]'));
        for (var p in parts) {
          if (p.trim().isNotEmpty) sections48000.add(double.parse(p.trim()));
        }
      }
    }

    if (sections44100.isEmpty && sections48000.isEmpty) {
      throw Exception('Unsupported VDC text format. Ensure the file contains "SR_44100:" or "SR_48000:" headers.');
    }

    int sectionCount = sections44100.isNotEmpty ? sections44100.length ~/ 5 : sections48000.length ~/ 5;
    
    // Fallback if one sample rate is missing
    if (sections44100.isEmpty) sections44100.addAll(sections48000);
    if (sections48000.isEmpty) sections48000.addAll(sections44100);

    return {
      'sections44100': sections44100,
      'sections48000': sections48000,
      'sectionCount': [sectionCount.toDouble()],
    };
  }

  static Map<String, List<double>> _parseBinaryVdc(Uint8List bytes) {
    final data = ByteData.view(bytes.buffer);
    final floatCount = bytes.length ~/ 4;
    final floatList = <double>[];
    for (int i = 0; i < floatCount; i++) {
      double val = data.getFloat32(i * 4, Endian.little);
      if (val.isNaN || val.isInfinite || val.abs() > 1000.0) {
        throw Exception('Invalid VDC binary data: found NaN or out-of-bounds float at index $i');
      }
      floatList.add(val);
    }
    
    final half = floatList.length ~/ 2;
    final sections44100 = floatList.sublist(0, half);
    final sections48000 = floatList.sublist(half, floatList.length);
    final sectionCount = half ~/ 5;
    
    return {
      'sections44100': sections44100,
      'sections48000': sections48000,
      'sectionCount': [sectionCount.toDouble()],
    };
  }
}
