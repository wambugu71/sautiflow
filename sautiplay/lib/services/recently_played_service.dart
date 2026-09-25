import 'dart:async';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/recently_played_track.dart';

class RecentlyPlayedService {
  static const int _maxHistoryItems = 100;

  /// Private constructor
  RecentlyPlayedService._();

  /// Singleton instance
  static final RecentlyPlayedService instance = RecentlyPlayedService._();

  /// Reactive stream of recently played tracks directly from Drift.
  Stream<List<RecentlyPlayedTrack>> watchHistory({int limit = _maxHistoryItems}) {
    return AppDatabase.instance
        .watchRecentlyPlayed(limit: limit)
        .map((entries) => entries.map(_entryToModel).toList());
  }

  /// Fetch all recently played tracks, sorted by most recent first.
  Future<List<RecentlyPlayedTrack>> getHistory({int limit = _maxHistoryItems}) async {
    final entries = await AppDatabase.instance.getRecentlyPlayed(limit: limit);
    return entries.map(_entryToModel).toList();
  }

  /// Add a track to the history. If it already exists, it will be moved to the top
  /// with an updated timestamp. Limits the history to [_maxHistoryItems].
  Future<void> addTrack(RecentlyPlayedTrack track) async {
    await AppDatabase.instance.addRecentlyPlayed(
      RecentlyPlayedEntriesCompanion(
        videoId: Value(track.videoId),
        title: Value(track.title),
        artist: Value(track.artist),
        artistId: Value(track.artistId),
        thumbnailUrl: Value(track.thumbnailUrl),
        durationSeconds: Value(track.durationSeconds),
        playedAt: Value(track.playedAt),
      ),
      maxHistory: _maxHistoryItems,
    );
  }

  /// Clears all execution history.
  Future<void> clearHistory() async {
    await AppDatabase.instance.clearRecentlyPlayed();
  }

  static RecentlyPlayedTrack _entryToModel(RecentlyPlayedEntry entry) {
    return RecentlyPlayedTrack(
      videoId: entry.videoId,
      title: entry.title,
      artist: entry.artist,
      artistId: entry.artistId,
      thumbnailUrl: entry.thumbnailUrl,
      durationSeconds: entry.durationSeconds,
      playedAt: entry.playedAt,
    );
  }
}
