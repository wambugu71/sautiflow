import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/date_parser.dart';

void parseVorbisComment(
  List<int> bytes,
  VorbisMetadata metadata,
  bool fetchImage,
) {
  int i = 0;
  final commentBytes = <int>[];

  while (bytes[i] != 0x3D) {
    commentBytes.add(bytes[i]);
    i += 1;
  }
  i += 1;

  final commentName = utf8.decode(commentBytes);

  String value;
  value = utf8.decode(bytes.sublist(i));

  switch (commentName.toUpperCase()) {
    case 'METADATA_BLOCK_PICTURE':
      if (!fetchImage) {
        return;
      }

      final imageValue = base64Decode(value);
      final buffer = ByteData.sublistView(imageValue);
      int offset = 0;

      final pictureType = buffer.getUint32(offset);
      offset += 4;
      final mimeLength = buffer.getUint32(offset);
      offset += 4;

      final mime =
          String.fromCharCodes(buffer.buffer.asUint8List(offset, mimeLength));
      offset += mimeLength;

      final descriptionLength = buffer.getUint32(offset);
      offset += 4 + descriptionLength + 16;

      final lengthData = buffer.getUint32(offset);
      offset += 4;

      final data = buffer.buffer.asUint8List(offset, lengthData);

      metadata.pictures
          .add(Picture(data, mime, getPictureTypeEnum(pictureType)));

      break;
    case 'TITLE':
      metadata.title.add(value);
      break;
    case 'VERSION':
      metadata.version.add(value);
      break;
    case 'ALBUM':
      metadata.album.add(value);
      break;
    case 'TRACKNUMBER' || 'ITUNES_CDDB_TRACKNUMBER':
      final trackVal = int.tryParse(value.contains('/') ? value.split('/').first : value);
      if (trackVal != null) {
        metadata.trackNumber.add(trackVal);
      }
      break;
    case 'ARTIST':
      metadata.artist.add(value);
      break;
    case 'PERFORMER':
      metadata.performer.add(value);
      break;
    case 'COPYRIGHT':
      metadata.copyright.add(value);
      break;
    case 'LICENSE':
      metadata.license.add(value);
      break;
    case 'ORGANIZATION' || "PUBLISHER":
      metadata.organization.add(value);
      break;
    case 'DESCRIPTION':
      metadata.description.add(value);
      break;
    case 'GENRE':
      metadata.genres.add(value);
      break;
    case 'DATE':
      final parsedDate = parseDateSafely(value);
      if (parsedDate != null) {
        metadata.date.add(parsedDate);
      }
      break;
    case 'LOCATION':
      metadata.location.add(value);
      break;
    case 'CONTACT':
      metadata.contact.add(value);
      break;
    case 'ISRC':
      metadata.isrc.add(value);
      break;
    case 'ACTOR':
      metadata.actor.add(value);
      break;
    case 'COMPOSER':
      metadata.composer.add(value);
      break;
    case 'COMMENT':
      metadata.comment.add(value);
      break;
    case 'LANGUAGE' || 'LANG':
      metadata.language.add(value);
      break;
    case 'DIRECTOR':
      metadata.director.add(value);
      break;
    case 'ENCODEDBY' || 'ENCODED_BY':
      metadata.encodedBy.add(value);
      break;
    case 'ENCODED_USING':
      metadata.encodedUsing.add(value);
      break;
    case 'ENCODER':
      metadata.encoder.add(value);
      break;
    case 'ENCODER_OPTIONS':
      metadata.encoderOptions.add(value);
      break;
    case 'PRODUCER':
      metadata.producer.add(value);
      break;
    case 'REPLAYGAIN_ALBUM_GAIN':
      metadata.replayGainAlbumGain.add(value);
      break;
    case 'REPLAYGAIN_ALBUM_PEAK':
      metadata.replayGainAlbumPeak.add(value);
      break;
    case 'REPLAYGAIN_TRACK_GAIN':
      metadata.replayGainTrackGain.add(value);
      break;
    case 'REPLAYGAIN_TRACK_PEAK':
      metadata.replayGainTrackPeak.add(value);
      break;
    case 'VENDOR':
      metadata.vendor.add(value);
      break;
    case 'TRACKTOTAL' || 'TOTALTRACKS':
      metadata.trackTotal = int.tryParse(value);
      break;
    case 'DISCNUMBER':
      metadata.discNumber = int.tryParse(value.contains('/') ? value.split('/').first : value);
      break;
    case 'DISCTOTAL' || 'TOTALDISCS':
      metadata.discTotal = int.tryParse(value);
      break;
    case "LYRICS":
      metadata.lyric = value;
      break;
    case "LENGTH":
      final lengthValue = int.tryParse(value);
      if (lengthValue != null) {
        metadata.duration = Duration(milliseconds: lengthValue);
      }
      break;
    default:
      metadata.unknowns[commentName.toUpperCase()] = value;
      break;
  }
}
