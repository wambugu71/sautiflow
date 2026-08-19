import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  final homeSections = await ytmusic.getHomeSections();
  print('Total Home Sections: ${homeSections.length}');

  for (var i = 0; i < homeSections.length; i++) {
    final section = homeSections[i];
    print('\n================ Section [$i]: "${section.title}" ================');
    for (var j = 0; j < section.contents.length; j++) {
      final item = section.contents[j];
      if (item is PlaylistDetailed) {
        print('  Item [$j]: Name="${item.name}", PlaylistId="${item.playlistId}", Artist="${item.artist.name}" (ArtistId="${item.artist.artistId}")');
        
        // Try calling getPlaylistVideos or getPlaylist
        if (item.playlistId.isEmpty) {
          print('    ⚠️ WARNING: PlaylistId is EMPTY!');
        } else {
          try {
            print('    Testing getPlaylistVideos("${item.playlistId}")...');
            final videos = await ytmusic.getPlaylistVideos(item.playlistId);
            print('    ✅ Success: Got ${videos.length} videos.');
          } catch (e) {
            print('    ❌ ERROR on getPlaylistVideos: $e');
          }
        }
      }
    }
  }
}
