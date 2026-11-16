import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

class LocalSongItem {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int sizeBytes;
  final DateTime lastModified;
  final String? fileHash;
  final int? startMs;
  final int? endMs;
  final int? trackNumber;
  final String? cueFilePath;
  final int? year;

  const LocalSongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    this.genre = 'Unknown Genre',
    required this.sizeBytes,
    required this.lastModified,
    this.fileHash,
    this.startMs,
    this.endMs,
    this.trackNumber,
    this.cueFilePath,
    this.year,
  });

  String get realFilePath => CueVirtualPath.strip(path);

  bool get isCueTrack =>
      startMs != null || cueFilePath != null || CueVirtualPath.isVirtual(path);

  int? get durationMs =>
      (endMs != null && startMs != null && endMs! > startMs!)
          ? (endMs! - startMs!)
          : null;

  factory LocalSongItem.fallback(
    String path,
    int size,
    DateTime modified, {
    String? title,
    String? artist,
    String? album,
    String? genre,
    String? fileHash,
    int? startMs,
    int? endMs,
    int? trackNumber,
    String? cueFilePath,
    int? year,
  }) {
    final cue = CueVirtualPath.parse(path);
    return LocalSongItem(
      path: path,
      title: (title != null && title.isNotEmpty)
          ? title
          : (cue?.title ?? p.basenameWithoutExtension(CueVirtualPath.strip(path))),
      artist: (artist != null && artist.isNotEmpty)
          ? artist
          : (cue?.artist ?? 'Unknown Artist'),
      album: (album != null && album.isNotEmpty)
          ? album
          : (cue?.album ?? 'Unknown Album'),
      genre: (genre != null && genre.isNotEmpty)
          ? genre
          : (cue?.genre ?? 'Unknown Genre'),
      sizeBytes: size,
      lastModified: modified,
      fileHash: fileHash,
      startMs: startMs ?? cue?.startMs,
      endMs: endMs ?? cue?.endMs,
      trackNumber: trackNumber ?? cue?.trackNumber,
      cueFilePath: cueFilePath ?? cue?.cueFilePath,
      year: year ?? cue?.year,
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
      'fileHash': fileHash,
      if (startMs != null) 'startMs': startMs,
      if (endMs != null) 'endMs': endMs,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (cueFilePath != null) 'cueFilePath': cueFilePath,
      if (year != null) 'year': year,
    };
  }

  factory LocalSongItem.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    final cue = CueVirtualPath.parse(path);
    return LocalSongItem(
      path: path,
      title: json['title'] as String? ?? cue?.title ?? '',
      artist: json['artist'] as String? ?? cue?.artist ?? 'Unknown Artist',
      album: json['album'] as String? ?? cue?.album ?? 'Unknown Album',
      genre: json['genre'] as String? ?? cue?.genre ?? 'Unknown Genre',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      lastModified: json['lastModified'] != null
          ? (DateTime.tryParse(json['lastModified'] as String) ?? DateTime.now())
          : DateTime.now(),
      fileHash: json['fileHash'] as String?,
      startMs: json['startMs'] as int? ?? cue?.startMs,
      endMs: json['endMs'] as int? ?? cue?.endMs,
      trackNumber: json['trackNumber'] as int? ?? cue?.trackNumber,
      cueFilePath: json['cueFilePath'] as String? ?? cue?.cueFilePath,
      year: json['year'] as int? ?? cue?.year,
    );
  }
}
