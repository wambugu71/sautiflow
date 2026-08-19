import 'package:dart_ytmusic_api/enums.dart';
import 'package:dart_ytmusic_api/parsers/album_parser.dart';
import 'package:dart_ytmusic_api/parsers/playlist_parser.dart';
import 'package:dart_ytmusic_api/parsers/song_parser.dart';
import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';
import 'package:dart_ytmusic_api/yt_music.dart';

dynamic parseItem(dynamic item) {
  if (item == null) return null;

  // Check if it's a responsive list item (Song / Track)
  if (item is Map && item.containsKey('musicResponsiveListItemRenderer')) {
    final renderer = item['musicResponsiveListItemRenderer'];
    return SongParser.parseSearchResult(renderer);
  }

  // Check if it's a two-row item renderer (Album, Playlist, Artist, etc.)
  final twoRow = item is Map && item.containsKey('musicTwoRowItemRenderer')
      ? item['musicTwoRowItemRenderer']
      : item;

  final pageType = traverseString(twoRow, ["title", "browseEndpoint", "pageType"]) ??
                   traverseString(twoRow, ["navigationEndpoint", "browseEndpoint", "pageType"]);
  
  if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
    return AlbumParser.parseHomeSection(twoRow);
  }
  
  if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
    return PlaylistParser.parseHomeSection(twoRow);
  }

  // Check watchPlaylistEndpoint or playlistId
  final playlistId = traverseString(twoRow, ["navigationEndpoint", "watchPlaylistEndpoint", "playlistId"]) ??
                     traverseString(twoRow, ["thumbnailOverlay", "playlistId"]) ??
                     traverseString(twoRow, ["overlay", "playlistId"]);

  if (playlistId != null && playlistId.isNotEmpty) {
    return PlaylistParser.parseHomeSection(twoRow);
  }

  final browseId = traverseString(twoRow, ["navigationEndpoint", "browseEndpoint", "browseId"]);
  if (browseId != null) {
    if (browseId.startsWith('MPREb_') || browseId.startsWith('OLAK5uy_')) {
      return AlbumParser.parseHomeSection(twoRow);
    }
    if (browseId.startsWith('RDCLAK') || browseId.startsWith('VL') || browseId.startsWith('PL')) {
      return PlaylistParser.parseHomeSection(twoRow);
    }
  }

  // Fallback to song or playlist
  final videoId = traverseString(twoRow, ["navigationEndpoint", "watchEndpoint", "videoId"]);
  if (videoId != null && videoId.isNotEmpty) {
    return SongParser.parseSearchResult(twoRow);
  }

  return PlaylistParser.parseHomeSection(twoRow);
}

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  print('Fetching raw browse feMusicHome...');
  final data = await ytmusic.constructRequest("browse", body: {"browseId": feMusicHome});

  final sectionList = traverseList(data, ["sectionListRenderer", "contents"]);
  print('Total raw sections: ${sectionList.length}');

  for (var i = 0; i < sectionList.length; i++) {
    final s = sectionList[i];
    final title = traverseString(s, ["header", "title", "text"]) ??
                  traverseString(s, ["musicCarouselShelfRenderer", "header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs", "text"]) ??
                  '(Untitled Section)';

    final rawItems = traverseList(s, ["contents"]);
    final parsedItems = rawItems.map(parseItem).where((e) => e != null).toList();

    print('\nSection [$i]: "$title" -> Found ${parsedItems.length} items (raw: ${rawItems.length})');
    for (var j = 0; j < parsedItems.length && j < 3; j++) {
      final p = parsedItems[j];
      if (p is SongDetailed) {
        print('  Item [$j]: [SONG] "${p.name}" by ${p.artist.name} (VideoID: ${p.videoId})');
      } else if (p is AlbumDetailed) {
        print('  Item [$j]: [ALBUM] "${p.name}" by ${p.artist.name} (AlbumID: ${p.albumId}, PlaylistID: ${p.playlistId})');
      } else if (p is PlaylistDetailed) {
        print('  Item [$j]: [PLAYLIST] "${p.name}" by ${p.artist.name} (PlaylistID: ${p.playlistId})');
      } else {
        print('  Item [$j]: [UNKNOWN] $p');
      }
    }
  }
}
