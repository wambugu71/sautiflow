import 'dart:convert';
import 'dart:io';

/// Represents an online audio stream cached locally to disk.
class CachedStreamItem {
  final String videoId; // Video ID or unique online stream identifier
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationSeconds;
  final String filePath; // Absolute local cached file path
  final String? streamUrl; // Original stream URL
  final int fileSizeBytes;
  final DateTime cachedAt;
  final bool isUserDownload;

  final String? album; // Album title (e.g. "Abbey Road", "Midnights")
  final String? albumId; // Unique album identifier
  final String? albumArtist; // Album artist
  final int? trackNumber; // Track position in album (1-based index)

  CachedStreamItem({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.durationSeconds,
    required this.filePath,
    this.streamUrl,
    required this.fileSizeBytes,
    required this.cachedAt,
    this.isUserDownload = false,
    this.album,
    this.albumId,
    this.albumArtist,
    this.trackNumber,
  });

  CachedStreamItem copyWith({
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    int? durationSeconds,
    String? filePath,
    String? streamUrl,
    int? fileSizeBytes,
    DateTime? cachedAt,
    bool? isUserDownload,
    String? album,
    String? albumId,
    String? albumArtist,
    int? trackNumber,
  }) {
    return CachedStreamItem(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      filePath: filePath ?? this.filePath,
      streamUrl: streamUrl ?? this.streamUrl,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      cachedAt: cachedAt ?? this.cachedAt,
      isUserDownload: isUserDownload ?? this.isUserDownload,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
    );
  }

  /// Check if the cached file actually exists on the filesystem.
  bool get exists => File(filePath).existsSync();

  /// Formatted file size string (e.g. "4.2 MB" or "850 KB")
  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 B';
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Formatted duration string (e.g. "3:45")
  String get formattedDuration {
    if (durationSeconds <= 0) return 'Unknown';
    final d = Duration(seconds: durationSeconds);
    final min = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Map<String, dynamic> toMap() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'filePath': filePath,
      'streamUrl': streamUrl,
      'fileSizeBytes': fileSizeBytes,
      'cachedAt': cachedAt.toIso8601String(),
      'isUserDownload': isUserDownload,
      if (album != null) 'album': album,
      if (albumId != null) 'albumId': albumId,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (trackNumber != null) 'trackNumber': trackNumber,
    };
  }

  factory CachedStreamItem.fromMap(Map<String, dynamic> map) {
    final path = map['filePath'] as String? ?? '';
    final isExplicit = map['isUserDownload'] as bool?;
    final isDownload = isExplicit ?? path.toLowerCase().contains('downloads');

    return CachedStreamItem(
      videoId: map['videoId'] as String? ?? '',
      title: map['title'] as String? ?? 'Cached Stream',
      artist: map['artist'] as String? ?? 'Online Stream',
      thumbnailUrl: map['thumbnailUrl'] as String?,
      durationSeconds: map['durationSeconds'] as int? ?? 0,
      filePath: path,
      streamUrl: map['streamUrl'] as String?,
      fileSizeBytes: map['fileSizeBytes'] as int? ?? 0,
      cachedAt: map['cachedAt'] != null
          ? DateTime.tryParse(map['cachedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isUserDownload: isDownload,
      album: map['album'] as String?,
      albumId: map['albumId'] as String?,
      albumArtist: map['albumArtist'] as String?,
      trackNumber: map['trackNumber'] as int?,
    );
  }

  String toJson() => json.encode(toMap());

  factory CachedStreamItem.fromJson(String source) =>
      CachedStreamItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
