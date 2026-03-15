import 'dart:convert';

/// Represents a track that has been played recently.
/// It can be a local file or an online stream.
class RecentlyPlayedTrack {
  final String
      videoId; // Use videoId to store either the YT ID or local file path
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationSeconds;
  final DateTime playedAt;

  RecentlyPlayedTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.durationSeconds,
    required this.playedAt,
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
      'playedAt': playedAt.toIso8601String(),
    };
  }

  factory RecentlyPlayedTrack.fromMap(Map<String, dynamic> map) {
    return RecentlyPlayedTrack(
      videoId: map['videoId'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      durationSeconds: map['durationSeconds'] as int? ?? 0,
      playedAt: DateTime.parse(map['playedAt'] as String),
    );
  }

  String toJson() => json.encode(toMap());

  factory RecentlyPlayedTrack.fromJson(String source) =>
      RecentlyPlayedTrack.fromMap(json.decode(source) as Map<String, dynamic>);
}
