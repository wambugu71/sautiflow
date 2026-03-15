import 'dart:convert';

/// Represents a track that has been liked by the user.
/// It can be a local file or an online stream.
class LikedSong {
  final String
      videoId; // Use videoId to store either the YT ID or local file path
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationSeconds;
  final DateTime likedAt;

  LikedSong({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.durationSeconds,
    required this.likedAt,
  });

  /// True if this track represents an online stream (e.g., YouTube video ID usually does not contain slashes)
  /// If it contains path separators, it's likely a local file.
  bool get isLocal => videoId.contains('/') || videoId.contains('\\');

  Map<String, dynamic> toMap() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'likedAt': likedAt.toIso8601String(),
    };
  }

  factory LikedSong.fromMap(Map<String, dynamic> map) {
    return LikedSong(
      videoId: map['videoId'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      durationSeconds: map['durationSeconds'] as int? ?? 0,
      likedAt: DateTime.parse(map['likedAt'] as String),
    );
  }

  String toJson() => json.encode(toMap());

  factory LikedSong.fromJson(String source) =>
      LikedSong.fromMap(json.decode(source) as Map<String, dynamic>);
}
