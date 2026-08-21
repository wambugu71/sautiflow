import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:mime/mime.dart';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/date_parser.dart';

// https://xhelmboyx.tripod.com/formats/mp4-layout.txt

///
/// Contains the data of a box header
///
/// The size is the sum of the box header size and the box data
class BoxHeader {
  /// Total box size in bytes (header + payload).
  int size;

  /// Four-character box type.
  String type;

  /// Build a box header.
  BoxHeader(this.size, this.type);
}

/// MP4 box types this parser understands and recursively explores.
final supportedBox = [
  "moov",
  "mvhd",
  "meta",
  "mdat",
  "udta",
  "ilst",
  "gnre",
  "trkn",
  "disk",
  "tmpo",
  "cpil",
  "covr",
  "pgap",
  "©nam",
  "©ART",
  "©alb",
  "©cmt",
  "©day",
  "©too",
  "©trk",
  "©lyr",
  "©gen",
  "----",
  "chpl",
  "trak",
  "mdia",
  "minf",
  "stbl",
  "stsd",
  "mp4a",
];

///
/// The parser for the MP4 files
///
/// The mp4 metadata format uses boxes (also called atoms) to format its data
/// In our case, we only need the metadata and some additional information like
/// bitrate and duration.
///
/// In short, the metadata are stored there:
/// `moov` -> `udta` - `meta` -> `ilst`
///
/// Information about the bitrate and duration are stored in `mvhd`
///
class MP4Parser extends TagParser<Mp4Metadata> {
  /// Parsed MP4 metadata.
  Mp4Metadata tags = Mp4Metadata();

  /// Reader helper bound to the current file.
  late final Buffer buffer;

  /// Create an MP4 parser.
  MP4Parser({bool fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  Mp4Metadata parse(RandomAccessFile reader) {
    try {
      reader.setPositionSync(0);
      buffer = Buffer(randomAccessFile: reader);

      final lengthFile = reader.lengthSync();

      while (buffer.fileCursor < lengthFile && buffer.remainingBytes >= 8) {
        final box = _readBox(buffer);
        if (box.size < 8 && box.size != 0) {
          break;
        }

        // If box.size == 0, it extends to the end of the file
        final effectiveSize =
            box.size == 0 ? (lengthFile - buffer.fileCursor + 8) : box.size;

        if (supportedBox.contains(box.type)) {
          processBox(buffer, BoxHeader(effectiveSize, box.type));
        } else {
          final toSkip = effectiveSize - 8;
          if (toSkip > 0) {
            buffer.skip(toSkip);
          }
        }
      }

      return tags;
    } finally {
      try {
        reader.closeSync();
      } catch (_) {}
    }
  }

  ///
  /// A box (or atom) header uses 8 bytes
  ///
  /// [0...3] -> box size (header + body)
  /// [4...7] -> box name (ASCII)
  ///
  BoxHeader _readBox(Buffer buffer) {
    if (buffer.remainingBytes < 8) {
      return BoxHeader(0, "");
    }
    final headerBytes = buffer.read(8);
    final parser = ByteData.sublistView(headerBytes);

    int boxSize = parser.getUint32(0);
    final boxNameBytes = headerBytes.sublist(4);

    // throw error if we don't have a correct box name
    if (boxNameBytes[0] == 0 &&
        boxNameBytes[1] == 0 &&
        boxNameBytes[2] == 0 &&
        boxNameBytes[3] == 0) {
      throw MetadataParserException(
          track: File(""), message: "Malformed MP4 file");
    }

    if (boxSize == 1) {
      // 64-bit size follows
      if (buffer.remainingBytes >= 8) {
        final extBytes = buffer.read(8);
        boxSize = getUint64BE(extBytes);
      }
    }

    return BoxHeader(boxSize, String.fromCharCodes(boxNameBytes));
  }

  /// Parse a box
  ///
  /// The metadata are inside special boxes. We only read data when we need it
  /// otherwise we skip them
  void processBox(Buffer buffer, BoxHeader box) {
    if (box.size < 8) return;

    if (box.type == "moov") {
      parseRecurvise(buffer, box);
    } else if (box.type == "mvhd") {
      final version = buffer.read(1)[0];

      // version 0 has 100 bytes
      // version 1 has 112 bytes
      final neededBytes = version == 1 ? 111 : 99;
      if (buffer.remainingBytes < neededBytes) return;
      final bytes = buffer.read(neededBytes);

      int timeScale = 0;
      int timeUnit = 0;

      if (version == 0) {
        timeScale = getUint32(bytes.sublist(11, 15));
        timeUnit = getUint32(bytes.sublist(15, 19));
      } else {
        timeScale = getUint32(bytes.sublist(19, 23));
        timeUnit = getUint64BE(bytes.sublist(23, 31));
      }

      if (timeScale > 0) {
        double microseconds = (timeUnit / timeScale) * 1000000;
        tags.duration = Duration(microseconds: microseconds.toInt());
      }
    } else if (box.type == "udta") {
      parseRecurvise(buffer, box);
    } else if (box.type == "ilst") {
      parseRecurvise(buffer, box);
    } else if (["trak", "mdia", "minf", "stbl", "stsd"].contains(box.type)) {
      parseRecurvise(buffer, box);
    } else if (box.type == "meta") {
      if (buffer.remainingBytes >= 4) {
        buffer.read(4);
      }
      parseRecurvise(buffer, box);
    } else if (box.type == "mdat") {
      final toSkip = box.size - 8;
      if (toSkip > 0) {
        buffer.skip(toSkip);
      }
    } else if (box.type == "chpl") {
      final payloadSize = box.size - 8;
      if (payloadSize > 0 && buffer.remainingBytes >= payloadSize) {
        _parseChapterListBox(buffer.read(payloadSize));
      }
    } else if (box.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap", "gen"]
            .contains(box.type)) {
      final boxName = (box.type[0] == "©") ? box.type.substring(1) : box.type;
      final payloadSize = box.size - 8;
      if (payloadSize <= 0) return;

      if (boxName == "covr" && !fetchImage) {
        buffer.skip(payloadSize);
        return;
      }

      if (buffer.remainingBytes < payloadSize) {
        buffer.skip(buffer.remainingBytes);
        return;
      }

      final metadataValue = buffer.read(payloadSize);

      // sometimes the data is stored inside another box called `data`
      // we try to find out if the data contains the box type "data" (0:4 is the box size)
      // otherwise we just skip the Apple's tag of 4 chars
      final data = (metadataValue.length >= 8 &&
              String.fromCharCodes(metadataValue.sublist(4, 8)) == "data")
          ? (metadataValue.length >= 16 ? metadataValue.sublist(16) : Uint8List(0))
          : (metadataValue.length >= 4 ? metadataValue.sublist(4) : Uint8List(0));

      final value = _decodeString(data);

      switch (boxName) {
        case "nam":
          tags.title = value;
          break;
        case "ART":
          tags.artist = value;
          break;
        case "alb":
          tags.album = value;
          break;
        case "cmt":
          break;
        case "lyr":
          tags.lyrics = value;
          break;
        case "gen":
          tags.genre = value;
          break;
        case "day":
          tags.year = parseDateSafely(value);
          break;
        case "too":
          break;
        case "disk":
          if (data.length >= 6) {
            tags.discNumber = getUint16(data.sublist(2, 4));
            tags.totalDiscs = getUint16(data.sublist(4, 6));
          }
          break;

        case "covr":
          if (data.isNotEmpty) {
            final imageData = data;
            tags.picture = Picture(
                imageData,
                lookupMimeType("no path", headerBytes: imageData) ?? "",
                PictureType.coverFront);
          }
          break;
        case "trkn":
          if (data.length >= 6) {
            final a = getUint16(data.sublist(2, 4));
            final totalTracks = getUint16(data.sublist(4, 6));
            tags.totalTracks = totalTracks;
            if (a > 0) {
              tags.trackNumber = a;
            }
          }
          break;
      }
    } else if (box.type == "----") {
      try {
        if (buffer.remainingBytes >= 8) {
          final mean = _readBox(buffer);
          if (mean.size >= 8 && buffer.remainingBytes >= mean.size - 8) {
            buffer.read(mean.size - 8); // mean value
          }

          if (buffer.remainingBytes >= 8) {
            final name = _readBox(buffer);
            if (name.size >= 12 && buffer.remainingBytes >= name.size - 8) {
              final nameBytes = buffer.read(name.size - 8);
              final nameValue = String.fromCharCodes(nameBytes.sublist(4));

              if (buffer.remainingBytes >= 8) {
                final dataBox = _readBox(buffer);
                if (dataBox.size >= 16 &&
                    buffer.remainingBytes >= dataBox.size - 8) {
                  final data = buffer.read(dataBox.size - 8);
                  final finalValue = String.fromCharCodes(data.sublist(8));

                  switch (nameValue) {
                    case "iTunes_CDDB_TrackNumber":
                      tags.trackNumber = int.tryParse(finalValue);
                      break;
                    default:
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    } else if (box.type == "mp4a") {
      final payloadSize = box.size - 8;
      if (payloadSize >= 26 && buffer.remainingBytes >= payloadSize) {
        final bytes = buffer.read(payloadSize);
        tags.sampleRate = getUint32(bytes.sublist(22, 26));
      } else if (payloadSize > 0) {
        buffer.skip(payloadSize);
      }
    } else {
      final toSkip = box.size - 8;
      if (toSkip > 0) {
        buffer.skip(toSkip);
      }
    }
  }

  String _decodeString(Uint8List value) {
    try {
      // Chapter titles and iTunes text metadata are usually UTF-8.
      return utf8.decode(value);
    } catch (_) {
      // Keep latin1 fallback for malformed or legacy tags.
      return latin1.decode(value);
    }
  }

  /// Parse chapter list atom (`chpl`) and append parsed chapters.
  ///
  /// The most common layout is:
  /// - 4 bytes: version + flags (full box)
  /// - 4 bytes: reserved
  /// - 1 byte: chapter count
  /// - N chapters:
  ///   - 8 bytes: start timestamp in 100ns units
  ///   - 1 byte: title size
  ///   - title bytes (UTF-8)
  void _parseChapterListBox(Uint8List value) {
    if (value.length < 5) {
      return;
    }

    // We handle both layouts found in the wild:
    // - [version+flags][reserved][count]...  => count at offset 8
    // - [version+flags][count]...            => count at offset 4
    final chapterFromReserved = _extractChapters(value, chapterCountOffset: 8);
    final chapterWithoutReserved =
        _extractChapters(value, chapterCountOffset: 4);
    final chapters = _pickBestChapterList(
      chapterFromReserved,
      chapterWithoutReserved,
    );

    if (chapters == null) {
      return;
    }

    tags.chapters.addAll(chapters);
  }

  List<Chapter>? _pickBestChapterList(
    List<Chapter>? withReserved,
    List<Chapter>? withoutReserved,
  ) {
    if (withReserved == null) {
      return withoutReserved;
    }

    if (withoutReserved == null) {
      return withReserved;
    }

    if (withoutReserved.length > withReserved.length) {
      // Prefer the parse that produced more complete chapters.
      return withoutReserved;
    }

    return withReserved;
  }

  List<Chapter>? _extractChapters(
    Uint8List value, {
    required int chapterCountOffset,
  }) {
    if (chapterCountOffset >= value.length) {
      return null;
    }

    int offset = chapterCountOffset;
    final chapterCount = value[offset];
    offset += 1;
    final chapters = <Chapter>[];

    for (int i = 0; i < chapterCount; i++) {
      // Each entry needs at least 8 bytes timestamp + 1 byte title length.
      if (offset + 9 > value.length) {
        return null;
      }

      final startIn100Nanoseconds =
          getUint64BE(value.sublist(offset, offset + 8));
      offset += 8;

      final titleLength = value[offset];
      offset += 1;

      // If one entry is truncated, consider this parse strategy invalid.
      if (offset + titleLength > value.length) {
        return null;
      }

      final titleBytes = value.sublist(offset, offset + titleLength);
      offset += titleLength;

      chapters.add(
        Chapter(
          // `chpl` stores timestamps in 100ns ticks, Duration uses microseconds.
          start: Duration(microseconds: (startIn100Nanoseconds / 10).round()),
          title: _decodeString(titleBytes),
        ),
      );
    }

    return chapters;
  }

  /// Parse a box with multiple sub boxes.
  void parseRecurvise(Buffer buffer, BoxHeader box) {
    final limit = box.size - 8;
    if (limit <= 0) return;
    int offset = 0;

    // the `meta` box has 4 additional bytes that are not useful. We skip them
    if ("meta" == box.type) {
      if (limit >= 4 && buffer.remainingBytes >= 4) {
        offset += 4;
        buffer.read(4);
      }
    } else if (box.type == "stsd") {
      if (limit >= 8 && buffer.remainingBytes >= 8) {
        offset += 8;
        buffer.read(8);
      }
    }

    while (offset < limit && buffer.remainingBytes >= 8) {
      final newBox = _readBox(buffer);
      if (newBox.size < 8) {
        break;
      }

      if (supportedBox.contains(newBox.type)) {
        processBox(buffer, newBox);
      } else {
        final toSkip = newBox.size - 8;
        if (toSkip > 0) {
          buffer.skip(toSkip);
        }
      }

      offset += newBox.size;
    }
  }

  /// To detect if this parser can be used to parse this file, we need to detect
  /// the first box. It should be a `ftyp` box
  /// Returns `true` when [reader] looks like an MP4-family file.
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(4);

    final headerBytes = reader.readSync(4);
    final boxName = String.fromCharCodes(headerBytes);

    return boxName == "ftyp";
  }
}
