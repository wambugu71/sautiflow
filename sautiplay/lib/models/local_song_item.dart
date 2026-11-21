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

  // Extended intelligent metadata & audio properties
  final String? albumArtist;
  final int? discNumber;
  final String? composer;
  final double? bpm;
  final String? musicalKey;
  final String? camelotKey;
  final double? replayGainDb;
  final int? trackDurationMs;
  final int? sampleRate;
  final int? bitDepth;
  final int playCount;
  final int rating;
  final int? lastPlayedAtMs;

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
    this.albumArtist,
    this.discNumber,
    this.composer,
    this.bpm,
    this.musicalKey,
    this.camelotKey,
    this.replayGainDb,
    this.trackDurationMs,
    this.sampleRate,
    this.bitDepth,
    this.playCount = 0,
    this.rating = 0,
    this.lastPlayedAtMs,
  });

  String get realFilePath => CueVirtualPath.strip(path);

  bool get isCueTrack =>
      startMs != null || cueFilePath != null || CueVirtualPath.isVirtual(path);

  int? get durationMs {
    if (endMs != null && startMs != null && endMs! > startMs!) {
      return endMs! - startMs!;
    }
    return trackDurationMs;
  }

  LocalSongItem copyWith({
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? sizeBytes,
    DateTime? lastModified,
    String? fileHash,
    int? startMs,
    int? endMs,
    int? trackNumber,
    String? cueFilePath,
    int? year,
    String? albumArtist,
    int? discNumber,
    String? composer,
    double? bpm,
    String? musicalKey,
    String? camelotKey,
    double? replayGainDb,
    int? trackDurationMs,
    int? sampleRate,
    int? bitDepth,
    int? playCount,
    int? rating,
    int? lastPlayedAtMs,
  }) {
    return LocalSongItem(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastModified: lastModified ?? this.lastModified,
      fileHash: fileHash ?? this.fileHash,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      trackNumber: trackNumber ?? this.trackNumber,
      cueFilePath: cueFilePath ?? this.cueFilePath,
      year: year ?? this.year,
      albumArtist: albumArtist ?? this.albumArtist,
      discNumber: discNumber ?? this.discNumber,
      composer: composer ?? this.composer,
      bpm: bpm ?? this.bpm,
      musicalKey: musicalKey ?? this.musicalKey,
      camelotKey: camelotKey ?? this.camelotKey,
      replayGainDb: replayGainDb ?? this.replayGainDb,
      trackDurationMs: trackDurationMs ?? this.trackDurationMs,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      playCount: playCount ?? this.playCount,
      rating: rating ?? this.rating,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
    );
  }

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
    String? albumArtist,
    int? discNumber,
    String? composer,
    double? bpm,
    String? musicalKey,
    String? camelotKey,
    double? replayGainDb,
    int? trackDurationMs,
    int? sampleRate,
    int? bitDepth,
    int playCount = 0,
    int rating = 0,
    int? lastPlayedAtMs,
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
      albumArtist: albumArtist,
      discNumber: discNumber,
      composer: composer,
      bpm: bpm,
      musicalKey: musicalKey,
      camelotKey: camelotKey,
      replayGainDb: replayGainDb,
      trackDurationMs: trackDurationMs,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      playCount: playCount,
      rating: rating,
      lastPlayedAtMs: lastPlayedAtMs,
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
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (discNumber != null) 'discNumber': discNumber,
      if (composer != null) 'composer': composer,
      if (bpm != null) 'bpm': bpm,
      if (musicalKey != null) 'musicalKey': musicalKey,
      if (camelotKey != null) 'camelotKey': camelotKey,
      if (replayGainDb != null) 'replayGainDb': replayGainDb,
      if (trackDurationMs != null) 'trackDurationMs': trackDurationMs,
      if (sampleRate != null) 'sampleRate': sampleRate,
      if (bitDepth != null) 'bitDepth': bitDepth,
      if (playCount > 0) 'playCount': playCount,
      if (rating > 0) 'rating': rating,
      if (lastPlayedAtMs != null) 'lastPlayedAtMs': lastPlayedAtMs,
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
      albumArtist: json['albumArtist'] as String?,
      discNumber: json['discNumber'] as int?,
      composer: json['composer'] as String?,
      bpm: (json['bpm'] as num?)?.toDouble(),
      musicalKey: json['musicalKey'] as String?,
      camelotKey: json['camelotKey'] as String?,
      replayGainDb: (json['replayGainDb'] as num?)?.toDouble(),
      trackDurationMs: json['trackDurationMs'] as int?,
      sampleRate: json['sampleRate'] as int?,
      bitDepth: json['bitDepth'] as int?,
      playCount: json['playCount'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      lastPlayedAtMs: json['lastPlayedAtMs'] as int?,
    );
  }
}
