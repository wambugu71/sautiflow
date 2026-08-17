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
  });

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
    };
  }

  factory CachedStreamItem.fromMap(Map<String, dynamic> map) {
    return CachedStreamItem(
      videoId: map['videoId'] as String? ?? '',
      title: map['title'] as String? ?? 'Cached Stream',
      artist: map['artist'] as String? ?? 'Online Stream',
      thumbnailUrl: map['thumbnailUrl'] as String?,
      durationSeconds: map['durationSeconds'] as int? ?? 0,
      filePath: map['filePath'] as String? ?? '',
      streamUrl: map['streamUrl'] as String?,
      fileSizeBytes: map['fileSizeBytes'] as int? ?? 0,
      cachedAt: map['cachedAt'] != null
          ? DateTime.tryParse(map['cachedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory CachedStreamItem.fromJson(String source) =>
      CachedStreamItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
