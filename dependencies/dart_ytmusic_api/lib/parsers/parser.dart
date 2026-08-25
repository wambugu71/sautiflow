import 'package:dart_ytmusic_api/parsers/album_parser.dart';
import 'package:dart_ytmusic_api/parsers/playlist_parser.dart';
import 'package:dart_ytmusic_api/parsers/song_parser.dart';
import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';

class Parser {
  static int? parseDuration(String? time) {
    if (time == null) return null;

    // Extract only the time portion using regex (format: H:MM:SS or MM:SS or M:SS)
    final timeMatch = RegExp(r'(\d+):(\d+)(?::(\d+))?').firstMatch(time);
    if (timeMatch == null) return null;

    // Parse the matched groups
    final parts = <int>[];
    for (int i = 1; i <= timeMatch.groupCount; i++) {
      final group = timeMatch.group(i);
      if (group != null) {
        parts.add(int.parse(group));
      }
    }

    if (parts.isEmpty) return null;

    // Handle different time formats
    if (parts.length == 2) {
      // MM:SS format
      final minutes = parts[0];
      final seconds = parts[1];
      return seconds + minutes * 60;
    } else if (parts.length == 3) {
      // H:MM:SS format
      final hours = parts[0];
      final minutes = parts[1];
      final seconds = parts[2];
      return seconds + minutes * 60 + hours * 60 * 60;
    }

    return null;
  }

  static double parseNumber(String string) {
    if (string.endsWith("K") ||
        string.endsWith("M") ||
        string.endsWith("B") ||
        string.endsWith("T")) {
      final number = double.parse(string.substring(0, string.length - 1));
      final multiplier = string.substring(string.length - 1);

      return {
            "K": number * 1000,
            "M": number * 1000 * 1000,
            "B": number * 1000 * 1000 * 1000,
            "T": number * 1000 * 1000 * 1000 * 1000,
          }[multiplier] ??
          double.nan;
    } else {
      return double.parse(string);
    }
  }

  static HomeSection parseHomeSection(dynamic data) {
    final title = traverseString(data, ["header", "title", "text"]) ??
        traverseString(data, [
          "musicCarouselShelfRenderer",
          "header",
          "musicCarouselShelfBasicHeaderRenderer",
          "title",
          "runs",
          "text"
        ]) ??
        '';

    return HomeSection(
      title: title,
      contents: traverseList(data, ["contents"])
          .map((item) {
            if (item == null) return null;

            // Check if it's a responsive list item (Song / Track)
            if (item is Map && item.containsKey('musicResponsiveListItemRenderer')) {
              return SongParser.parseSearchResult(item['musicResponsiveListItemRenderer']);
            }

            final itemData = item is Map && item.containsKey('musicTwoRowItemRenderer')
                ? item['musicTwoRowItemRenderer']
                : item;

            final pageType = traverseString(itemData, ["title", "browseEndpoint", "pageType"]) ??
                traverseString(itemData, ["navigationEndpoint", "browseEndpoint", "pageType"]);

            if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
              return AlbumParser.parseHomeSection(itemData);
            }

            if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
              return PlaylistParser.parseHomeSection(itemData);
            }

            final playlistId = traverseString(itemData, [
                  "navigationEndpoint",
                  "watchPlaylistEndpoint",
                  "playlistId"
                ]) ??
                traverseString(itemData, ["thumbnailOverlay", "playlistId"]) ??
                traverseString(itemData, ["overlay", "playlistId"]);

            if (playlistId != null && playlistId.isNotEmpty) {
              return PlaylistParser.parseHomeSection(itemData);
            }

            final browseId = traverseString(
                itemData, ["navigationEndpoint", "browseEndpoint", "browseId"]);
            if (browseId != null) {
              if (browseId.startsWith('MPREb_') || browseId.startsWith('OLAK5uy_')) {
                return AlbumParser.parseHomeSection(itemData);
              }
              if (browseId.startsWith('RDCLAK') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL')) {
                return PlaylistParser.parseHomeSection(itemData);
              }
            }

            final videoId = traverseString(
                itemData, ["navigationEndpoint", "watchEndpoint", "videoId"]);
            if (videoId != null && videoId.isNotEmpty) {
              return SongParser.parseSearchResult(itemData);
            }

            return PlaylistParser.parseHomeSection(itemData);
          })
          .where((element) => element != null)
          .cast<dynamic>()
          .toList(),
    );
  }
}
