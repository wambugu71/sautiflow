import 'package:dart_ytmusic_api/enums.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';
import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  print('Fetching raw browse feMusicHome...');
  final data = await ytmusic.constructRequest("browse", body: {"browseId": feMusicHome});

  final sections = traverseList(data, ["sectionListRenderer", "contents"]);
  print('Raw sections count: ${sections.length}');

  for (var i = 0; i < sections.length; i++) {
    final s = sections[i];
    final title = traverseString(s, ["header", "title", "text"]) ?? '(no title)';
    final pageType = traverseString(s, ["contents", "title", "browseEndpoint", "pageType"]);
    final firstRendererKey = s is Map ? (s.keys.isNotEmpty ? s.keys.first : '') : '';
    print('\n---------------- Section [$i]: "$title" ----------------');
    print('  Container Key: $firstRendererKey');
    print('  Detected pageType: $pageType');
    
    // Check items
    final contents = traverseList(s, ["contents"]);
    print('  Contents count: ${contents.length}');
    if (contents.isNotEmpty) {
      final firstItem = contents.first;
      if (firstItem is Map) {
        print('  First Item Keys: ${firstItem.keys.toList()}');
        final itemPageType = traverseString(firstItem, ["title", "browseEndpoint", "pageType"]) ??
                             traverseString(firstItem, ["navigationEndpoint", "browseEndpoint", "pageType"]);
        final itemBrowseId = traverseString(firstItem, ["title", "browseEndpoint", "browseId"]) ??
                             traverseString(firstItem, ["navigationEndpoint", "browseEndpoint", "browseId"]);
        final itemPlaylistId = traverseString(firstItem, ["navigationEndpoint", "watchPlaylistEndpoint", "playlistId"]) ??
                               traverseString(firstItem, ["overlay", "playlistId"]) ??
                               traverseString(firstItem, ["thumbnailOverlay", "playlistId"]);
        print('  First Item -> itemPageType: $itemPageType | browseId: $itemBrowseId | playlistId: $itemPlaylistId');
      }
    }
  }
}
