import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

import '../models/local_song_item.dart';
import 'tables/app_preferences.dart';
import 'tables/cached_streams.dart';
import 'tables/liked_songs.dart';
import 'tables/local_tracks.dart';
import 'tables/recently_played.dart';

part 'app_database.g.dart';

/// Lightweight SQL-aggregated artist summary for scalable artist browsing.
class LocalArtistSummary {
  final String artist;
  final int trackCount;
  final String? samplePath;

  const LocalArtistSummary({
    required this.artist,
    required this.trackCount,
    this.samplePath,
  });
}

/// Lightweight SQL-aggregated album summary for scalable album browsing.
class LocalAlbumSummary {
  final String album;
  final String artist;
  final int trackCount;
  final String? samplePath;

  const LocalAlbumSummary({
    required this.album,
    required this.artist,
    required this.trackCount,
    this.samplePath,
  });
}

@DriftDatabase(tables: [
  AppPreferences,
  LikedSongEntries,
  RecentlyPlayedEntries,
  CachedStreamEntries,
  LocalTrackEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  static final AppDatabase instance = AppDatabase();

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(localTrackEntries);
            await m.createIndex(idxLocalTracksTitle);
            await m.createIndex(idxLocalTracksArtist);
            await m.createIndex(idxLocalTracksAlbum);
            await m.createIndex(idxLocalTracksModified);
            await m.createIndex(idxLocalTracksSize);
            await m.createIndex(idxLocalTracksExt);
            await m.createIndex(idxLocalTracksRealPath);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

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

  // ─── Local Tracks (Indexed Windowed Library) ──────────────────────────────
  static LocalSongItem toLocalSongItem(LocalTrackEntry row) {
    return LocalSongItem(
      path: row.path,
      title: row.title,
      artist: row.artist,
      album: row.album,
      genre: row.genre,
      sizeBytes: row.sizeBytes,
      lastModified: DateTime.fromMillisecondsSinceEpoch(row.lastModifiedMs),
      fileHash: row.fileHash,
      startMs: row.startMs,
      endMs: row.endMs,
      trackNumber: row.trackNumber,
      cueFilePath: row.cueFilePath,
      year: row.year,
    );
  }

  static LocalTrackEntriesCompanion toLocalTrackCompanion(LocalSongItem item) {
    final realPath = CueVirtualPath.strip(item.path);
    return LocalTrackEntriesCompanion(
      path: Value(item.path),
      realFilePath: Value(realPath),
      folderName: Value(p.basename(p.dirname(realPath))),
      title: Value(item.title),
      artist: Value(item.artist),
      album: Value(item.album),
      genre: Value(item.genre),
      extension: Value(p.extension(realPath).toLowerCase()),
      sizeBytes: Value(item.sizeBytes),
      lastModifiedMs: Value(item.lastModified.millisecondsSinceEpoch),
      fileHash: Value(item.fileHash),
      startMs: Value(item.startMs),
      endMs: Value(item.endMs),
      trackNumber: Value(item.trackNumber),
      cueFilePath: Value(item.cueFilePath),
      year: Value(item.year),
    );
  }

  Future<void> replaceAllLocalTracks(List<LocalSongItem> tracks) async {
    await transaction(() async {
      await delete(localTrackEntries).go();
      if (tracks.isEmpty) return;
      const chunkSize = 500;
      for (int i = 0; i < tracks.length; i += chunkSize) {
        final end = (i + chunkSize < tracks.length) ? i + chunkSize : tracks.length;
        final companions =
            tracks.sublist(i, end).map(toLocalTrackCompanion).toList();
        await batch((b) {
          b.insertAllOnConflictUpdate(localTrackEntries, companions);
        });
      }
    });
  }

  Future<void> upsertLocalTrack(LocalSongItem track) async {
    await into(localTrackEntries)
        .insertOnConflictUpdate(toLocalTrackCompanion(track));
  }

  Future<void> deleteLocalTracksByPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    await (delete(localTrackEntries)..where((t) => t.path.isIn(paths))).go();
  }

  Future<void> deleteLocalTracksByRealPath(String realPath) async {
    await (delete(localTrackEntries)
          ..where((t) => t.realFilePath.equals(realPath)))
        .go();
  }

  Future<List<LocalSongItem>> getAllLocalTracks() async {
    final rows = await select(localTrackEntries).get();
    return rows.map(toLocalSongItem).toList();
  }

  SimpleSelectStatement<$LocalTrackEntriesTable, LocalTrackEntry>
      _buildLocalTracksQuery({
    String query = '',
    String sort = 'Name (A-Z)',
  }) {
    final stmt = select(localTrackEntries);
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isNotEmpty) {
      final pattern = '%$trimmed%';
      stmt.where((t) =>
          t.title.lower().like(pattern) |
          t.artist.lower().like(pattern) |
          t.album.lower().like(pattern));
    }

    switch (sort) {
      case 'Name (Z-A)':
        stmt.orderBy([(t) => OrderingTerm.desc(t.title), (t) => OrderingTerm.asc(t.path)]);
        break;
      case 'Date Added (New-Old)':
        stmt.orderBy([(t) => OrderingTerm.desc(t.lastModifiedMs), (t) => OrderingTerm.asc(t.path)]);
        break;
      case 'Date Added (Old-New)':
        stmt.orderBy([(t) => OrderingTerm.asc(t.lastModifiedMs), (t) => OrderingTerm.asc(t.path)]);
        break;
      case 'Size (Largest)':
        stmt.orderBy([(t) => OrderingTerm.desc(t.sizeBytes), (t) => OrderingTerm.asc(t.path)]);
        break;
      case 'Size (Smallest)':
        stmt.orderBy([(t) => OrderingTerm.asc(t.sizeBytes), (t) => OrderingTerm.asc(t.path)]);
        break;
      case 'File Extension (A-Z)':
        stmt.orderBy([(t) => OrderingTerm.asc(t.extension), (t) => OrderingTerm.asc(t.title)]);
        break;
      case 'File Extension (Z-A)':
        stmt.orderBy([(t) => OrderingTerm.desc(t.extension), (t) => OrderingTerm.asc(t.title)]);
        break;
      case 'Name (A-Z)':
      default:
        stmt.orderBy([(t) => OrderingTerm.asc(t.title), (t) => OrderingTerm.asc(t.path)]);
        break;
    }
    return stmt;
  }

  Future<int> countLocalTracks({String query = ''}) async {
    final trimmed = query.trim().toLowerCase();
    final countExp = localTrackEntries.path.count();
    final q = selectOnly(localTrackEntries)..addColumns([countExp]);
    if (trimmed.isNotEmpty) {
      final pattern = '%$trimmed%';
      q.where(localTrackEntries.title.lower().like(pattern) |
          localTrackEntries.artist.lower().like(pattern) |
          localTrackEntries.album.lower().like(pattern));
    }
    final row = await q.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<List<LocalSongItem>> fetchLocalTracksWindow({
    required int offset,
    required int limit,
    String query = '',
    String sort = 'Name (A-Z)',
  }) async {
    final stmt = _buildLocalTracksQuery(query: query, sort: sort)
      ..limit(limit, offset: offset);
    final rows = await stmt.get();
    return rows.map(toLocalSongItem).toList();
  }

  Future<List<String>> fetchLocalTrackPaths({
    String query = '',
    String sort = 'Name (A-Z)',
  }) async {
    final stmt = _buildLocalTracksQuery(query: query, sort: sort);
    final rows = await stmt.get();
    return rows.map((r) => r.path).toList();
  }

  Future<int> findLocalTrackIndex(
    String path, {
    String query = '',
    String sort = 'Name (A-Z)',
  }) async {
    final paths = await fetchLocalTrackPaths(query: query, sort: sort);
    return paths.indexOf(path);
  }

  Future<List<LocalArtistSummary>> fetchArtistSummaries({
    String query = '',
  }) async {
    final trimmed = query.trim().toLowerCase();
    final hasQuery = trimmed.isNotEmpty;
    final sql = StringBuffer('''
      SELECT TRIM(artist) AS artist_name,
             COUNT(*) AS track_count,
             MIN(path) AS sample_path
      FROM local_tracks
      WHERE artist IS NOT NULL
        AND TRIM(artist) != ''
        AND LOWER(TRIM(artist)) != 'unknown artist'
        AND LOWER(TRIM(artist)) != '<unknown>'
    ''');
    final variables = <Variable<Object>>[];
    if (hasQuery) {
      sql.write(' AND LOWER(TRIM(artist)) LIKE ?');
      variables.add(Variable.withString('%$trimmed%'));
    }
    sql.write(' GROUP BY TRIM(artist) ORDER BY LOWER(TRIM(artist)) ASC');

    final rows = await customSelect(
      sql.toString(),
      variables: variables,
      readsFrom: {localTrackEntries},
    ).get();

    return rows
        .map((r) => LocalArtistSummary(
              artist: r.read<String>('artist_name'),
              trackCount: r.read<int>('track_count'),
              samplePath: r.readNullable<String>('sample_path'),
            ))
        .toList();
  }

  Future<List<LocalSongItem>> fetchTracksForArtist(String artist) async {
    final rows = await (select(localTrackEntries)
          ..where((t) => t.artist.trim().equals(artist.trim()))
          ..orderBy([(t) => OrderingTerm.asc(t.album), (t) => OrderingTerm.asc(t.trackNumber), (t) => OrderingTerm.asc(t.title)]))
        .get();
    return rows.map(toLocalSongItem).toList();
  }

  Future<List<LocalAlbumSummary>> fetchAlbumSummaries({
    String query = '',
  }) async {
    final trimmed = query.trim().toLowerCase();
    final hasQuery = trimmed.isNotEmpty;
    final sql = StringBuffer('''
      SELECT TRIM(album) AS album_name,
             COALESCE(NULLIF(TRIM(MIN(artist)), ''), 'Unknown Artist') AS artist_name,
             COUNT(*) AS track_count,
             MIN(path) AS sample_path
      FROM local_tracks
      WHERE album IS NOT NULL
        AND TRIM(album) != ''
        AND LOWER(TRIM(album)) != 'unknown album'
        AND LOWER(TRIM(album)) != '<unknown>'
    ''');
    final variables = <Variable<Object>>[];
    if (hasQuery) {
      sql.write(' AND (LOWER(TRIM(album)) LIKE ? OR LOWER(TRIM(artist)) LIKE ?)');
      final pat = '%$trimmed%';
      variables.add(Variable.withString(pat));
      variables.add(Variable.withString(pat));
    }
    sql.write(' GROUP BY TRIM(album) ORDER BY LOWER(TRIM(album)) ASC');

    final rows = await customSelect(
      sql.toString(),
      variables: variables,
      readsFrom: {localTrackEntries},
    ).get();

    return rows
        .map((r) => LocalAlbumSummary(
              album: r.read<String>('album_name'),
              artist: r.read<String>('artist_name'),
              trackCount: r.read<int>('track_count'),
              samplePath: r.readNullable<String>('sample_path'),
            ))
        .toList();
  }

  Future<List<LocalSongItem>> fetchTracksForAlbum(String album) async {
    final rows = await (select(localTrackEntries)
          ..where((t) => t.album.trim().equals(album.trim()))
          ..orderBy([(t) => OrderingTerm.asc(t.trackNumber), (t) => OrderingTerm.asc(t.title)]))
        .get();
    return rows.map(toLocalSongItem).toList();
  }
}
