import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  print('================================================================');
  print('     TESTING SEARCH & ARTIST/ALBUM DISCOVERY FLOW');
  print('================================================================');

  // 1. Search suggestions (autocomplete)
  final suggestions = await ytmusic.getSearchSuggestions('The Week');
  print('1. Search Suggestions for "The Week":');
  print('   $suggestions\n');

  // 2. Search Artists
  print('2. Searching Artist "The Weeknd"...');
  final artists = await ytmusic.searchArtists('The Weeknd');
  if (artists.isEmpty) {
    print('   No artists found.');
    return;
  }
  final artist = artists.first;
  print('   Found Artist: ${artist.name} (ArtistID: ${artist.artistId})\n');

  // 3. Get Artist Full Details
  print('3. Fetching Artist Profile for ${artist.name} (${artist.artistId})...');
  final artistProfile = await ytmusic.getArtist(artist.artistId);
  print('   Artist Name: ${artistProfile.name}');
  print('   Top Songs: ${artistProfile.topSongs.length} songs');
  print('   Top Albums: ${artistProfile.topAlbums.length} albums');
  print('   Top Singles: ${artistProfile.topSingles.length} singles');
  print('   Similar Artists: ${artistProfile.similarArtists.map((a) => a.name).take(3).join(", ")}');
  for (var i = 0; i < artistProfile.topSongs.length && i < 3; i++) {
    final s = artistProfile.topSongs[i];
    print('     - [Top Song $i] ${s.name} (VideoID: ${s.videoId})');
  }

  // 4. Fetch Artist Albums
  print('\n4. Fetching Artist Albums...');
  final albums = await ytmusic.getArtistAlbums(artist.artistId);
  print('   Found ${albums.length} albums for ${artist.name}:');
  for (var i = 0; i < albums.length && i < 3; i++) {
    final alb = albums[i];
    print('     [$i] "${alb.name}" (${alb.year}) | AlbumID: ${alb.albumId}');
  }

  // 5. Get Album Tracklist
  if (albums.isNotEmpty && albums.first.albumId.isNotEmpty) {
    final targetAlbum = albums.first;
    print('\n5. Fetching Tracklist for Album "${targetAlbum.name}" (${targetAlbum.albumId})...');
    final albumFull = await ytmusic.getAlbum(targetAlbum.albumId);
    print('   Album: ${albumFull.name} (${albumFull.year}) | Total Songs: ${albumFull.songs.length}');
    for (var i = 0; i < albumFull.songs.length && i < 5; i++) {
      final s = albumFull.songs[i];
      print('     [$i] ${s.name} - ${s.artist.name} (${s.duration != null ? "${s.duration}s" : "--"}) [VideoID: ${s.videoId}]');
    }
  }
}
