import 'package:path/path.dart' as p;

class LocalSongItem {
  final String path;
  final String title;
  final String artist;
  final String album;
  final int sizeBytes;
  final DateTime lastModified;

  const LocalSongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    required this.sizeBytes,
    required this.lastModified,
  });

  factory LocalSongItem.fallback(String path, int size, DateTime modified, {String? title, String? artist, String? album}) {
    return LocalSongItem(
      path: path,
      title: (title != null && title.isNotEmpty) ? title : p.basenameWithoutExtension(path),
      artist: (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist',
      album: (album != null && album.isNotEmpty) ? album : 'Unknown Album',
      sizeBytes: size,
      lastModified: modified,
    );
  }
}
