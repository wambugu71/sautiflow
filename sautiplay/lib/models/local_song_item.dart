import 'package:path/path.dart' as p;

class LocalSongItem {
  final String path;
  final String title;
  final String artist;
  final int sizeBytes;
  final DateTime lastModified;

  const LocalSongItem({
    required this.path,
    required this.title,
    required this.artist,
    required this.sizeBytes,
    required this.lastModified,
  });

  factory LocalSongItem.fallback(String path, int size, DateTime modified) {
    return LocalSongItem(
      path: path,
      title: p.basenameWithoutExtension(path),
      artist: 'Unknown Artist',
      sizeBytes: size,
      lastModified: modified,
    );
  }
}
