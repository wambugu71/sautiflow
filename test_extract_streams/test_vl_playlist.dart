import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  final id = "VLRDCLAK5uy_lnm4v4arFrmL63NUzIdoXJe-E7G4_sriU";

  print('Testing getPlaylist with $id:');
  final playlist = await ytmusic.getPlaylist(id);
  print('Playlist: ${playlist.name} by ${playlist.artist.name} (Tracks: ${playlist.videoCount})');

  print('\nTesting getPlaylistVideos with $id:');
  try {
    final videos = await ytmusic.getPlaylistVideos(id);
    print('Successfully extracted ${videos.length} videos:');
    for (var i = 0; i < videos.length && i < 5; i++) {
      print('  [$i] ${videos[i].name} by ${videos[i].artist.name} (VideoID: ${videos[i].videoId})');
    }
  } catch (e, st) {
    print('getPlaylistVideos error: $e');
    print(st);
  }
}
