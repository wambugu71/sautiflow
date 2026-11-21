import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

import '../models/local_song_item.dart';
import 'tables/app_preferences.dart';
import 'tables/cached_streams.dart';
import 'tables/liked_songs.dart';
import 'tables/local_tracks.dart';
import 'tables/playlists.dart';
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
  PlaylistEntries,
  PlaylistItemEntries,
  TagEditHistoryEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  static final AppDatabase instance = AppDatabase();

  @override
  int get schemaVersion => 3;

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
          if (from < 3) {
            await m.addColumn(localTrackEntries, localTrackEntries.albumArtist);
            await m.addColumn(localTrackEntries, localTrackEntries.discNumber);
            await m.addColumn(localTrackEntries, localTrackEntries.composer);
            await m.addColumn(localTrackEntries, localTrackEntries.bpm);
            await m.addColumn(localTrackEntries, localTrackEntries.musicalKey);
            await m.addColumn(localTrackEntries, localTrackEntries.camelotKey);
            await m.addColumn(localTrackEntries, localTrackEntries.replayGainDb);
            await m.addColumn(localTrackEntries, localTrackEntries.durationMs);
            await m.addColumn(localTrackEntries, localTrackEntries.sampleRate);
            await m.addColumn(localTrackEntries, localTrackEntries.bitDepth);
            await m.addColumn(localTrackEntries, localTrackEntries.playCount);
            await m.addColumn(localTrackEntries, localTrackEntries.rating);
            await m.addColumn(localTrackEntries, localTrackEntries.lastPlayedAtMs);
            await m.addColumn(localTrackEntries, localTrackEntries.tagsUpdatedAtMs);

            await m.createIndex(idxLocalTracksGenre);
            await m.createIndex(idxLocalTracksBpm);
            await m.createIndex(idxLocalTracksCamelot);
            await m.createIndex(idxLocalTracksYear);

            await m.createTable(playlistEntries);
            await m.createIndex(idxPlaylistsPinnedUpdated);
            await m.createTable(playlistItemEntries);
            await m.createIndex(idxPlaylistItemsOrder);
            await m.createIndex(idxPlaylistItemsTrack);
            await m.createTable(tagEditHistoryEntries);
            await m.createIndex(idxTagHistoryPath);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
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
      albumArtist: row.albumArtist,
      discNumber: row.discNumber,
      composer: row.composer,
      bpm: row.bpm,
      musicalKey: row.musicalKey,
      camelotKey: row.camelotKey,
      replayGainDb: row.replayGainDb,
      trackDurationMs: row.durationMs,
      sampleRate: row.sampleRate,
      bitDepth: row.bitDepth,
      playCount: row.playCount,
      rating: row.rating,
      lastPlayedAtMs: row.lastPlayedAtMs,
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
      albumArtist: Value(item.albumArtist),
      discNumber: Value(item.discNumber),
      composer: Value(item.composer),
      bpm: Value(item.bpm),
      musicalKey: Value(item.musicalKey),
      camelotKey: Value(item.camelotKey),
      replayGainDb: Value(item.replayGainDb),
      durationMs: Value(item.trackDurationMs),
      sampleRate: Value(item.sampleRate),
      bitDepth: Value(item.bitDepth),
      playCount: Value(item.playCount),
      rating: Value(item.rating),
      lastPlayedAtMs: Value(item.lastPlayedAtMs),
    );
  }

  /// Replaces the scanned local track index while preserving user-edited or
  /// audio-derived fields (`playCount`, `rating`, `bpm`, `camelotKey`, etc.)
  /// for tracks whose `path` remains in the library.
  Future<void> replaceAllLocalTracks(List<LocalSongItem> tracks) async {
    await transaction(() async {
      final existingRows = await select(localTrackEntries).get();
      final existingByPath = <String, LocalTrackEntry>{
        for (final row in existingRows) row.path: row,
      };

      await delete(localTrackEntries).go();
      if (tracks.isEmpty) return;

      final merged = tracks.map((item) {
        final prev = existingByPath[item.path];
        if (prev == null) return item;
        return item.copyWith(
          albumArtist: item.albumArtist ?? prev.albumArtist,
          discNumber: item.discNumber ?? prev.discNumber,
          composer: item.composer ?? prev.composer,
          bpm: item.bpm ?? prev.bpm,
          musicalKey: item.musicalKey ?? prev.musicalKey,
          camelotKey: item.camelotKey ?? prev.camelotKey,
          replayGainDb: item.replayGainDb ?? prev.replayGainDb,
          trackDurationMs: item.trackDurationMs ?? prev.durationMs,
          sampleRate: item.sampleRate ?? prev.sampleRate,
          bitDepth: item.bitDepth ?? prev.bitDepth,
          playCount: item.playCount > 0 ? item.playCount : prev.playCount,
          rating: item.rating > 0 ? item.rating : prev.rating,
          lastPlayedAtMs: item.lastPlayedAtMs ?? prev.lastPlayedAtMs,
        );
      }).toList();

      const chunkSize = 500;
      for (int i = 0; i < merged.length; i += chunkSize) {
        final end = (i + chunkSize < merged.length) ? i + chunkSize : merged.length;
        final companions =
            merged.sublist(i, end).map(toLocalTrackCompanion).toList();
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
    final target = await (select(localTrackEntries)
          ..where((t) => t.path.equals(path)))
        .getSingleOrNull();
    if (target == null) return -1;

    final trimmed = query.trim().toLowerCase();
    final filterClauses = <String>[];
    final vars = <Variable<Object>>[];
    if (trimmed.isNotEmpty) {
      filterClauses.add(
          '(LOWER(title) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ?)');
      final pat = '%$trimmed%';
      vars.addAll([
        Variable.withString(pat),
        Variable.withString(pat),
        Variable.withString(pat),
      ]);
    }

    String orderCond;
    switch (sort) {
      case 'Name (Z-A)':
        orderCond = '(title > ? OR (title = ? AND path < ?))';
        vars.addAll([
          Variable.withString(target.title),
          Variable.withString(target.title),
          Variable.withString(target.path),
        ]);
        break;
      case 'Date Added (New-Old)':
        orderCond = '(last_modified_ms > ? OR (last_modified_ms = ? AND path < ?))';
        vars.addAll([
          Variable.withInt(target.lastModifiedMs),
          Variable.withInt(target.lastModifiedMs),
          Variable.withString(target.path),
        ]);
        break;
      case 'Date Added (Old-New)':
        orderCond = '(last_modified_ms < ? OR (last_modified_ms = ? AND path < ?))';
        vars.addAll([
          Variable.withInt(target.lastModifiedMs),
          Variable.withInt(target.lastModifiedMs),
          Variable.withString(target.path),
        ]);
        break;
      case 'Size (Largest)':
        orderCond = '(size_bytes > ? OR (size_bytes = ? AND path < ?))';
        vars.addAll([
          Variable.withInt(target.sizeBytes),
          Variable.withInt(target.sizeBytes),
          Variable.withString(target.path),
        ]);
        break;
      case 'Size (Smallest)':
        orderCond = '(size_bytes < ? OR (size_bytes = ? AND path < ?))';
        vars.addAll([
          Variable.withInt(target.sizeBytes),
          Variable.withInt(target.sizeBytes),
          Variable.withString(target.path),
        ]);
        break;
      case 'File Extension (A-Z)':
        orderCond = '(extension < ? OR (extension = ? AND title < ?))';
        vars.addAll([
          Variable.withString(target.extension),
          Variable.withString(target.extension),
          Variable.withString(target.title),
        ]);
        break;
      case 'File Extension (Z-A)':
        orderCond = '(extension > ? OR (extension = ? AND title < ?))';
        vars.addAll([
          Variable.withString(target.extension),
          Variable.withString(target.extension),
          Variable.withString(target.title),
        ]);
        break;
      case 'Name (A-Z)':
      default:
        orderCond = '(title < ? OR (title = ? AND path < ?))';
        vars.addAll([
          Variable.withString(target.title),
          Variable.withString(target.title),
          Variable.withString(target.path),
        ]);
        break;
    }

    filterClauses.add(orderCond);
    final sql =
        'SELECT COUNT(*) AS idx FROM local_tracks WHERE ${filterClauses.join(' AND ')}';
    final row = await customSelect(
      sql,
      variables: vars,
      readsFrom: {localTrackEntries},
    ).getSingle();
    return row.read<int>('idx');
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

  // ─── Tag Editing, Health & Undo History ───────────────────────────────────
  Future<void> recordAndApplyTagEdit(LocalSongItem updated) async {
    await transaction(() async {
      final prev = await (select(localTrackEntries)
            ..where((t) => t.path.equals(updated.path)))
          .getSingleOrNull();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (prev != null) {
        await into(tagEditHistoryEntries).insert(
          TagEditHistoryEntriesCompanion.insert(
            trackPath: prev.path,
            previousTitle: prev.title,
            previousArtist: prev.artist,
            previousAlbum: prev.album,
            previousGenre: prev.genre,
            previousYear: Value(prev.year),
            previousTrackNumber: Value(prev.trackNumber),
            previousAlbumArtist: Value(prev.albumArtist),
            previousDiscNumber: Value(prev.discNumber),
            previousComposer: Value(prev.composer),
            previousBpm: Value(prev.bpm),
            previousMusicalKey: Value(prev.musicalKey),
            editedAtMs: nowMs,
          ),
        );
      }

      final companion = toLocalTrackCompanion(updated).copyWith(
        tagsUpdatedAtMs: Value(nowMs),
      );
      await into(localTrackEntries).insertOnConflictUpdate(companion);
    });
  }

  Future<LocalSongItem?> undoLastTagEdit(String trackPath) async {
    return transaction(() async {
      final last = await (select(tagEditHistoryEntries)
            ..where((t) => t.trackPath.equals(trackPath))
            ..orderBy([(t) => OrderingTerm.desc(t.editedAtMs), (t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
      if (last == null) return null;

      final current = await (select(localTrackEntries)
            ..where((t) => t.path.equals(trackPath)))
          .getSingleOrNull();
      if (current == null) return null;

      final restored = toLocalSongItem(current).copyWith(
        title: last.previousTitle,
        artist: last.previousArtist,
        album: last.previousAlbum,
        genre: last.previousGenre,
        year: last.previousYear,
        trackNumber: last.previousTrackNumber,
        albumArtist: last.previousAlbumArtist,
        discNumber: last.previousDiscNumber,
        composer: last.previousComposer,
        bpm: last.previousBpm,
        musicalKey: last.previousMusicalKey,
      );

      await into(localTrackEntries).insertOnConflictUpdate(
        toLocalTrackCompanion(restored).copyWith(
          tagsUpdatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await (delete(tagEditHistoryEntries)..where((t) => t.id.equals(last.id))).go();
      return restored;
    });
  }

  Future<bool> hasTagEditHistory(String trackPath) async {
    final row = await (select(tagEditHistoryEntries)
          ..where((t) => t.trackPath.equals(trackPath))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> incrementPlayCount(String trackPath) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'UPDATE local_tracks SET play_count = play_count + 1, last_played_at_ms = ? WHERE path = ?',
      [nowMs, trackPath],
    );
  }

  Future<void> setTrackRating(String trackPath, int rating) async {
    final clamped = rating.clamp(0, 5);
    await (update(localTrackEntries)..where((t) => t.path.equals(trackPath)))
        .write(LocalTrackEntriesCompanion(rating: Value(clamped)));
  }

  Future<List<LocalSongItem>> fetchTracksNeedingMetadata({int limit = 200}) async {
    final rows = await (select(localTrackEntries)
          ..where((t) =>
              t.artist.lower().equals('unknown artist') |
              t.album.lower().equals('unknown album') |
              t.genre.lower().equals('unknown genre') |
              t.year.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.title)])
          ..limit(limit))
        .get();
    return rows.map(toLocalSongItem).toList();
  }

  // ─── Relational Playlists & Smart Playlists ───────────────────────────────
  Stream<List<PlaylistEntry>> watchAllPlaylists() {
    return (select(playlistEntries)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.desc(t.updatedAtMs),
          ]))
        .watch();
  }

  Future<List<PlaylistEntry>> getAllPlaylists() {
    return (select(playlistEntries)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.desc(t.updatedAtMs),
          ]))
        .get();
  }

  Future<PlaylistEntry?> getPlaylistById(String id) {
    return (select(playlistEntries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertPlaylist(PlaylistEntriesCompanion entry) async {
    await into(playlistEntries).insertOnConflictUpdate(entry);
  }

  Future<void> deletePlaylistById(String id) async {
    await transaction(() async {
      await (delete(playlistItemEntries)..where((t) => t.playlistId.equals(id))).go();
      await (delete(playlistEntries)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<PlaylistItemEntry>> getPlaylistItemRows(String playlistId) {
    return (select(playlistItemEntries)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Stream<List<PlaylistItemEntry>> watchPlaylistItemRows(String playlistId) {
    return (select(playlistItemEntries)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  Future<Map<String, LocalSongItem>> getLocalTracksByPaths(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final map = <String, LocalSongItem>{};
    const chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final end = (i + chunkSize < paths.length) ? i + chunkSize : paths.length;
      final sub = paths.sublist(i, end);
      final rows = await (select(localTrackEntries)..where((t) => t.path.isIn(sub))).get();
      for (final row in rows) {
        map[row.path] = toLocalSongItem(row);
      }
    }
    return map;
  }

  Future<List<LocalSongItem>> queryCustomLocalTracks({
    required String whereSql,
    required List<Variable<Object>> variables,
    required String orderBySql,
    int? limit,
  }) async {
    final sql = StringBuffer('SELECT * FROM local_tracks');
    if (whereSql.isNotEmpty) {
      sql.write(' WHERE $whereSql');
    }
    if (orderBySql.isNotEmpty) {
      sql.write(' ORDER BY $orderBySql');
    }
    if (limit != null && limit > 0) {
      sql.write(' LIMIT $limit');
    }
    final rows = await customSelect(
      sql.toString(),
      variables: variables,
      readsFrom: {localTrackEntries},
    ).get();

    return rows.map((r) {
      final entry = localTrackEntries.map(r.data);
      return toLocalSongItem(entry);
    }).toList();
  }
}
