import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/app_preferences.dart';
import 'tables/cached_streams.dart';
import 'tables/liked_songs.dart';
import 'tables/recently_played.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  AppPreferences,
  LikedSongEntries,
  RecentlyPlayedEntries,
  CachedStreamEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  static final AppDatabase instance = AppDatabase();

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'sautiplay_db');
  }

  // ─── Liked Songs Queries ──────────────────────────────────────────────────
  Stream<List<LikedSongEntry>> watchLikedSongs() {
    return (select(likedSongEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.likedAt)]))
        .watch();
  }

  Future<List<LikedSongEntry>> getLikedSongs() {
    return (select(likedSongEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.likedAt)]))
        .get();
  }

  Future<bool> isSongLiked(String videoId) async {
    final item = await (select(likedSongEntries)
          ..where((t) => t.videoId.equals(videoId)))
        .getSingleOrNull();
    return item != null;
  }

  Future<void> upsertLikedSong(LikedSongEntriesCompanion entry) async {
    await into(likedSongEntries).insertOnConflictUpdate(entry);
  }

  Future<void> deleteLikedSong(String videoId) async {
    await (delete(likedSongEntries)..where((t) => t.videoId.equals(videoId))).go();
  }

  // ─── Recently Played Queries ──────────────────────────────────────────────
  Stream<List<RecentlyPlayedEntry>> watchRecentlyPlayed({int limit = 100}) {
    return (select(recentlyPlayedEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<RecentlyPlayedEntry>> getRecentlyPlayed({int limit = 100}) {
    return (select(recentlyPlayedEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
          ..limit(limit))
        .get();
  }

  Future<void> addRecentlyPlayed(
    RecentlyPlayedEntriesCompanion entry, {
    int maxHistory = 100,
  }) async {
    await transaction(() async {
      await into(recentlyPlayedEntries).insertOnConflictUpdate(entry);

      // Prune history to maxHistory items
      final all = await (select(recentlyPlayedEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.playedAt)]))
          .get();

      if (all.length > maxHistory) {
        final toDelete = all.sublist(maxHistory);
        final idsToDelete = toDelete.map((e) => e.videoId).toList();
        await (delete(recentlyPlayedEntries)
              ..where((t) => t.videoId.isIn(idsToDelete)))
            .go();
      }
    });
  }

  Future<void> clearRecentlyPlayed() async {
    await delete(recentlyPlayedEntries).go();
  }

  // ─── App Preferences (Key-Value) Queries ──────────────────────────────────
  Stream<String?> watchPreference(String key) {
    return (select(appPreferences)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Future<String?> getPreference(String key) async {
    final row = await (select(appPreferences)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<Map<String, String>> getAllPreferences() async {
    final rows = await select(appPreferences).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> setPreference(String key, String value) async {
    await into(appPreferences).insertOnConflictUpdate(
      AppPreferencesCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  Future<void> deletePreference(String key) async {
    await (delete(appPreferences)..where((t) => t.key.equals(key))).go();
  }
}
