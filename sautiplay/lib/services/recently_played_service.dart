import 'package:shared_preferences/shared_preferences.dart';
import '../models/recently_played_track.dart';

class RecentlyPlayedService {
  static const String _prefsKey = 'sautiplay_recently_played';
  static const int _maxHistoryItems = 100;

  /// Private constructor
  RecentlyPlayedService._();

  /// Singleton instance
  static final RecentlyPlayedService instance = RecentlyPlayedService._();

  /// Fetch all recently played tracks, sorted by most recent first.
  Future<List<RecentlyPlayedTrack>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey) ?? [];

    final tracks = jsonList
        .map((str) {
          try {
            return RecentlyPlayedTrack.fromJson(str);
          } catch (e) {
            return null;
          }
        })
        .where((t) => t != null)
        .cast<RecentlyPlayedTrack>()
        .toList();

    // Sort descending by playedAt just in case
    tracks.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return tracks;
  }

  /// Add a track to the history. If it already exists, it will be moved to the top
  /// with an updated timestamp. Limits the history to [_maxHistoryItems].
  Future<void> addTrack(RecentlyPlayedTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    List<RecentlyPlayedTrack> currentHistory = await getHistory();

    // Remove if it already exists to avoid duplicates, we'll put it at the top
    currentHistory.removeWhere((t) => t.videoId == track.videoId);

    // Insert at the beginning
    currentHistory.insert(0, track);

    // Enforce limit
    if (currentHistory.length > _maxHistoryItems) {
      currentHistory = currentHistory.sublist(0, _maxHistoryItems);
    }

    // Save back to prefs
    final jsonList = currentHistory.map((t) => t.toJson()).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  /// Clears all execution history.
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
