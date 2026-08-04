import 'package:path/path.dart' as p;

class LocalSongItem {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int sizeBytes;
  final DateTime lastModified;

  const LocalSongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    this.genre = 'Unknown Genre',
    required this.sizeBytes,
    required this.lastModified,
  });

  factory LocalSongItem.fallback(
    String path,
    int size,
    DateTime modified, {
    String? title,
    String? artist,
    String? album,
    String? genre,
  }) {
    return LocalSongItem(
      path: path,
      title: (title != null && title.isNotEmpty) ? title : p.basenameWithoutExtension(path),
      artist: (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist',
      album: (album != null && album.isNotEmpty) ? album : 'Unknown Album',
      genre: (genre != null && genre.isNotEmpty) ? genre : 'Unknown Genre',
      sizeBytes: size,
      lastModified: modified,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'sizeBytes': sizeBytes,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory LocalSongItem.fromJson(Map<String, dynamic> json) {
    return LocalSongItem(
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      genre: json['genre'] as String? ?? 'Unknown Genre',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      lastModified: json['lastModified'] != null
          ? (DateTime.tryParse(json['lastModified'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}
