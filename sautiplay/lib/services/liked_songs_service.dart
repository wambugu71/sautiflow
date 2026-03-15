import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/liked_song.dart';

class LikedSongsService {
  static const String _prefsKey = 'sautiplay_liked_songs';

  /// Private constructor
  LikedSongsService._();

  /// Singleton instance
  static final LikedSongsService instance = LikedSongsService._();

  // A ValueNotifier to broadcast changes to liked songs so the UI can update
  final ValueNotifier<List<LikedSong>> likedSongsNotifier = ValueNotifier([]);

  /// Initializes the service and loads the current liked songs.
  Future<void> init() async {
    likedSongsNotifier.value = await getLikedSongs();
  }

  /// Fetch all liked songs, sorted by most recently liked first.
  Future<List<LikedSong>> getLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey) ?? [];

    final tracks = jsonList
        .map((str) {
          try {
            return LikedSong.fromJson(str);
          } catch (e) {
            return null;
          }
        })
        .where((t) => t != null)
        .cast<LikedSong>()
        .toList();

    // Sort descending by likedAt
    tracks.sort((a, b) => b.likedAt.compareTo(a.likedAt));
    return tracks;
  }

  /// Add a track to the liked songs.
  Future<void> addLikedSong(LikedSong track) async {
    final prefs = await SharedPreferences.getInstance();
    List<LikedSong> currentLiked = await getLikedSongs();

    // Remove if it already exists to avoid duplicates
    currentLiked.removeWhere((t) => t.videoId == track.videoId);

    // Insert at the beginning
    currentLiked.insert(0, track);

    // Save back to prefs
    final jsonList = currentLiked.map((t) => t.toJson()).toList();
    await prefs.setStringList(_prefsKey, jsonList);

    likedSongsNotifier.value = currentLiked;
  }

  /// Remove a track from liked songs by videoId (or file path).
  Future<void> removeLikedSong(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    List<LikedSong> currentLiked = await getLikedSongs();

    currentLiked.removeWhere((t) => t.videoId == videoId);

    // Save back to prefs
    final jsonList = currentLiked.map((t) => t.toJson()).toList();
    await prefs.setStringList(_prefsKey, jsonList);

    likedSongsNotifier.value = currentLiked;
  }

  /// Check if a track is liked based on videoId (or file path).
  Future<bool> isLiked(String videoId) async {
    List<LikedSong> currentLiked = await getLikedSongs();
    return currentLiked.any((t) => t.videoId == videoId);
  }

  /// Clears all liked songs.
  Future<void> clearLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    likedSongsNotifier.value = [];
  }
}
