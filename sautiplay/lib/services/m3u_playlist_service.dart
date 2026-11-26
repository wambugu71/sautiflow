import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../database/preferences_store.dart';
import '../models/local_song_item.dart';
import '../models/smart_playlist_rule.dart';
import 'automix_analysis_service.dart';

class SavedM3uPlaylist {
  final String id;
  final String name;
  final String description;
  final String pathOrUrl;
  final bool isNetwork;
  final bool isPinned;
  final bool isSmart;
  final SmartPlaylistSpec? smartSpec;
  final List<LocalSongItem> tracks;
  final DateTime dateAdded;

  const SavedM3uPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    required this.pathOrUrl,
    required this.isNetwork,
    this.isPinned = false,
    this.isSmart = false,
    this.smartSpec,
    required this.tracks,
    required this.dateAdded,
  });

  SavedM3uPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    String? pathOrUrl,
    bool? isNetwork,
    bool? isPinned,
    bool? isSmart,
    SmartPlaylistSpec? smartSpec,
    List<LocalSongItem>? tracks,
    DateTime? dateAdded,
  }) {
    return SavedM3uPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      pathOrUrl: pathOrUrl ?? this.pathOrUrl,
      isNetwork: isNetwork ?? this.isNetwork,
      isPinned: isPinned ?? this.isPinned,
      isSmart: isSmart ?? this.isSmart,
      smartSpec: smartSpec ?? this.smartSpec,
      tracks: tracks ?? this.tracks,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'pathOrUrl': pathOrUrl,
        'isNetwork': isNetwork,
        'isPinned': isPinned,
        'isSmart': isSmart,
        if (smartSpec != null) 'smartRules': smartSpec!.toRulesJson(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'dateAdded': dateAdded.toIso8601String(),
      };

  factory SavedM3uPlaylist.fromJson(Map<String, dynamic> json) =>
      SavedM3uPlaylist(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Untitled Playlist',
        description: json['description'] as String? ?? '',
        pathOrUrl: json['pathOrUrl'] as String? ?? '',
        isNetwork: json['isNetwork'] as bool? ?? false,
        isPinned: json['isPinned'] as bool? ?? false,
        isSmart: json['isSmart'] as bool? ?? false,
        tracks: (json['tracks'] as List<dynamic>?)
                ?.map((t) =>
                    LocalSongItem.fromJson(Map<String, dynamic>.from(t as Map)))
                .toList() ??
            [],
        dateAdded: json['dateAdded'] != null
            ? DateTime.tryParse(json['dateAdded'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

class M3uPlaylistService {
  M3uPlaylistService._();
  static final M3uPlaylistService instance = M3uPlaylistService._();

  static const String _kM3uPlaylistsKey = 'sp_m3u_playlists_json';
  static const String _kMigratedFlagKey = 'sp_playlists_migrated_to_drift_v3';

  final AppDatabase _db = AppDatabase.instance;
  bool _migrationChecked = false;

  Future<void> _ensureMigrated() async {
    if (_migrationChecked) return;
    _migrationChecked = true;
    final prefs = PreferencesStore.instance;
    if (prefs.getBool(_kMigratedFlagKey) == true) return;

    final raw = prefs.getStringList(_kM3uPlaylistsKey) ?? [];
    for (final str in raw) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        final legacy = SavedM3uPlaylist.fromJson(map);
        final existing = await _db.getPlaylistById(legacy.id);
        if (existing == null) {
          await _writePlaylistToDb(legacy);
        }
      } catch (_) {}
    }
    await prefs.setBool(_kMigratedFlagKey, true);
  }

  Future<void> _writePlaylistToDb(SavedM3uPlaylist playlist) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdMs = playlist.dateAdded.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.upsertPlaylist(
        PlaylistEntriesCompanion(
          id: Value(playlist.id),
          name: Value(playlist.name),
          description: Value(playlist.description),
          pathOrUrl: Value(playlist.pathOrUrl),
          isNetwork: Value(playlist.isNetwork),
          isPinned: Value(playlist.isPinned),
          isSmart: Value(playlist.isSmart),
          rulesJson: Value(playlist.smartSpec?.toRulesJson()),
          matchAll: Value(playlist.smartSpec?.matchAll ?? true),
          sortBy: Value(playlist.smartSpec?.sortBy.name ?? 'titleAsc'),
          limitCount: Value(playlist.smartSpec?.limitCount),
          createdAtMs: Value(createdMs),
          updatedAtMs: Value(nowMs),
        ),
      );

      if (!playlist.isSmart) {
        await (_db.delete(_db.playlistItemEntries)
              ..where((t) => t.playlistId.equals(playlist.id)))
            .go();
        if (playlist.tracks.isNotEmpty) {
          await _db.batch((b) {
            for (int i = 0; i < playlist.tracks.length; i++) {
              final track = playlist.tracks[i];
              b.insert(
                _db.playlistItemEntries,
                PlaylistItemEntriesCompanion.insert(
                  playlistId: playlist.id,
                  trackPath: track.path,
                  fallbackTitle: Value(track.title),
                  fallbackArtist: Value(track.artist),
                  fallbackAlbum: Value(track.album),
                  fallbackJson: Value(jsonEncode(track.toJson())),
                  sortOrder: (i + 1) * 1024.0,
                  addedAtMs: nowMs,
                ),
              );
            }
          });
        }
      }
    });
  }

  Future<SavedM3uPlaylist> _hydratePlaylistRow(PlaylistEntry row) async {
    if (row.isSmart) {
      final spec = SmartPlaylistSpec.fromDb(
        rulesJson: row.rulesJson,
        matchAll: row.matchAll,
        sortBy: row.sortBy,
        limitCount: row.limitCount,
      );
      final tracks = await evaluateSmartSpec(spec);
      return SavedM3uPlaylist(
        id: row.id,
        name: row.name,
        description: row.description,
        pathOrUrl: row.pathOrUrl,
        isNetwork: row.isNetwork,
        isPinned: row.isPinned,
        isSmart: true,
        smartSpec: spec,
        tracks: tracks,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
      );
    }

    final itemRows = await _db.getPlaylistItemRows(row.id);
    final tracks = await _resolvePlaylistItemRows(itemRows);
    return SavedM3uPlaylist(
      id: row.id,
      name: row.name,
      description: row.description,
      pathOrUrl: row.pathOrUrl,
      isNetwork: row.isNetwork,
      isPinned: row.isPinned,
      isSmart: false,
      tracks: tracks,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
    );
  }

  Future<List<LocalSongItem>> _resolvePlaylistItemRows(
    List<PlaylistItemEntry> itemRows,
  ) async {
    if (itemRows.isEmpty) return const [];
    final paths = itemRows.map((e) => e.trackPath).toList();
    final dbTracks = await _db.getLocalTracksByPaths(paths);
    final resolved = <LocalSongItem>[];
    for (final item in itemRows) {
      final live = dbTracks[item.trackPath];
      if (live != null) {
        resolved.add(live);
        continue;
      }
      if (item.fallbackJson != null && item.fallbackJson!.isNotEmpty) {
        try {
          resolved.add(LocalSongItem.fromJson(
              jsonDecode(item.fallbackJson!) as Map<String, dynamic>));
          continue;
        } catch (_) {}
      }
      resolved.add(
        LocalSongItem.fallback(
          item.trackPath,
          0,
          DateTime.fromMillisecondsSinceEpoch(item.addedAtMs),
          title: item.fallbackTitle,
          artist: item.fallbackArtist,
          album: item.fallbackAlbum,
        ),
      );
    }
    return resolved;
  }

  // ─── Public API (Backwards-Compatible + Reactive) ─────────────────────────

  Future<void> savePlaylists(List<SavedM3uPlaylist> playlists) async {
    await _ensureMigrated();
    for (final p in playlists) {
      await _writePlaylistToDb(p);
    }
  }

  Future<List<SavedM3uPlaylist>> loadPlaylists() async {
    await _ensureMigrated();
    final rows = await _db.getAllPlaylists();
    final result = <SavedM3uPlaylist>[];
    for (final row in rows) {
      result.add(await _hydratePlaylistRow(row));
    }
    return result;
  }

  Stream<List<SavedM3uPlaylist>> watchPlaylists() async* {
    await _ensureMigrated();
    await for (final rows in _db.watchAllPlaylists()) {
      final list = <SavedM3uPlaylist>[];
      for (final row in rows) {
        list.add(await _hydratePlaylistRow(row));
      }
      yield list;
    }
  }

  Stream<SavedM3uPlaylist?> watchPlaylist(String playlistId) async* {
    await _ensureMigrated();
    await for (final _ in _db.watchPlaylistItemRows(playlistId)) {
      final row = await _db.getPlaylistById(playlistId);
      if (row == null) {
        yield null;
      } else {
        yield await _hydratePlaylistRow(row);
      }
    }
  }

  Future<void> saveSinglePlaylist(SavedM3uPlaylist playlist) async {
    await _ensureMigrated();
    await _writePlaylistToDb(playlist);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _ensureMigrated();
    await _db.deletePlaylistById(playlistId);
  }

  /// Creates a new custom playlist from the provided [tracks].
  Future<SavedM3uPlaylist> createPlaylist({
    required String name,
    required List<LocalSongItem> tracks,
    String description = '',
    bool isPinned = false,
  }) async {
    await _ensureMigrated();
    final newPlaylist = SavedM3uPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isNotEmpty ? name.trim() : 'Untitled Playlist',
      description: description.trim(),
      pathOrUrl: '',
      isNetwork: false,
      isPinned: isPinned,
      tracks: List.from(tracks),
      dateAdded: DateTime.now(),
    );
    await _writePlaylistToDb(newPlaylist);
    return newPlaylist;
  }

  /// Creates a dynamic SQL-backed Smart Playlist.
  Future<SavedM3uPlaylist> createSmartPlaylist({
    required String name,
    required SmartPlaylistSpec spec,
    String description = '',
    bool isPinned = false,
  }) async {
    await _ensureMigrated();
    final tracks = await evaluateSmartSpec(spec);
    final playlist = SavedM3uPlaylist(
      id: 'smart_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isNotEmpty ? name.trim() : 'Smart Playlist',
      description: description.trim(),
      pathOrUrl: '',
      isNetwork: false,
      isPinned: isPinned,
      isSmart: true,
      smartSpec: spec,
      tracks: tracks,
      dateAdded: DateTime.now(),
    );
    await _writePlaylistToDb(playlist);
    return playlist;
  }

  Future<List<LocalSongItem>> evaluateSmartSpec(SmartPlaylistSpec spec) {
    final compiled = spec.compileToSql();
    return _db.queryCustomLocalTracks(
      whereSql: compiled.whereSql,
      variables: compiled.variables,
      orderBySql: compiled.orderBySql,
      limit: compiled.limit,
    );
  }

  Future<void> togglePinPlaylist(String playlistId) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null) return;
    await (_db.update(_db.playlistEntries)
          ..where((t) => t.id.equals(playlistId)))
        .write(
      PlaylistEntriesCompanion(
        isPinned: Value(!row.isPinned),
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Appends [tracks] to an existing playlist, avoiding duplicate file paths.
  Future<SavedM3uPlaylist?> addTracksToPlaylist({
    required String playlistId,
    required List<LocalSongItem> tracks,
  }) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null || row.isSmart) return null;

    final existing = await _db.getPlaylistItemRows(playlistId);
    final existingPaths = existing.map((e) => e.trackPath).toSet();
    double nextOrder =
        existing.isEmpty ? 1024.0 : existing.last.sortOrder + 1024.0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      await _db.batch((b) {
        for (final track in tracks) {
          if (existingPaths.contains(track.path)) continue;
          existingPaths.add(track.path);
          b.insert(
            _db.playlistItemEntries,
            PlaylistItemEntriesCompanion.insert(
              playlistId: playlistId,
              trackPath: track.path,
              fallbackTitle: Value(track.title),
              fallbackArtist: Value(track.artist),
              fallbackAlbum: Value(track.album),
              fallbackJson: Value(jsonEncode(track.toJson())),
              sortOrder: nextOrder,
              addedAtMs: nowMs,
            ),
          );
          nextOrder += 1024.0;
        }
      });
      await (_db.update(_db.playlistEntries)
            ..where((t) => t.id.equals(playlistId)))
          .write(PlaylistEntriesCompanion(updatedAtMs: Value(nowMs)));
    });

    final updatedRow = await _db.getPlaylistById(playlistId);
    return updatedRow == null ? null : _hydratePlaylistRow(updatedRow);
  }

  /// Removes a track by [trackPath] from the specified playlist.
  Future<SavedM3uPlaylist?> removeTrackFromPlaylist({
    required String playlistId,
    required String trackPath,
  }) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null || row.isSmart) return null;

    await _db.transaction(() async {
      await (_db.delete(_db.playlistItemEntries)
            ..where((t) =>
                t.playlistId.equals(playlistId) & t.trackPath.equals(trackPath)))
          .go();
      await (_db.update(_db.playlistEntries)
            ..where((t) => t.id.equals(playlistId)))
          .write(PlaylistEntriesCompanion(
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ));
    });

    final updatedRow = await _db.getPlaylistById(playlistId);
    return updatedRow == null ? null : _hydratePlaylistRow(updatedRow);
  }

  /// Renames an existing playlist.
  Future<SavedM3uPlaylist?> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null) return null;
    final cleanName = newName.trim().isNotEmpty ? newName.trim() : row.name;
    await (_db.update(_db.playlistEntries)
          ..where((t) => t.id.equals(playlistId)))
        .write(
      PlaylistEntriesCompanion(
        name: Value(cleanName),
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    final updatedRow = await _db.getPlaylistById(playlistId);
    return updatedRow == null ? null : _hydratePlaylistRow(updatedRow);
  }

  /// O(1) fractional sort-order update for drag-and-drop track reordering.
  Future<SavedM3uPlaylist?> reorderPlaylistTrack({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    await _ensureMigrated();
    final rows = await _db.getPlaylistItemRows(playlistId);
    if (oldIndex < 0 || oldIndex >= rows.length) return null;
    if (newIndex < 0 || newIndex >= rows.length || newIndex == oldIndex) {
      return null;
    }

    final moved = rows.removeAt(oldIndex);
    rows.insert(newIndex, moved);

    double newSortOrder;
    if (newIndex == 0) {
      newSortOrder = rows[1].sortOrder / 2.0;
    } else if (newIndex == rows.length - 1) {
      newSortOrder = rows[rows.length - 2].sortOrder + 1024.0;
    } else {
      newSortOrder =
          (rows[newIndex - 1].sortOrder + rows[newIndex + 1].sortOrder) / 2.0;
    }

    await _db.transaction(() async {
      await (_db.update(_db.playlistItemEntries)
            ..where((t) => t.id.equals(moved.id)))
          .write(PlaylistItemEntriesCompanion(sortOrder: Value(newSortOrder)));
      await (_db.update(_db.playlistEntries)
            ..where((t) => t.id.equals(playlistId)))
          .write(PlaylistEntriesCompanion(
        updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ));
    });

    final updatedRow = await _db.getPlaylistById(playlistId);
    return updatedRow == null ? null : _hydratePlaylistRow(updatedRow);
  }

  /// Reorders a playlist for harmonic DJ/Automix flow using Camelot Key + BPM.
  Future<SavedM3uPlaylist?> harmonizePlaylistOrder(String playlistId) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null || row.isSmart) return null;
    final current = await _hydratePlaylistRow(row);
    if (current.tracks.length < 3) return current;

    final automix = AutomixAnalysisService.instance;
    final remaining = List<LocalSongItem>.from(current.tracks);
    final ordered = <LocalSongItem>[remaining.removeAt(0)];

    while (remaining.isNotEmpty) {
      final prev = ordered.last;
      final prevKey = (prev.camelotKey != null && prev.camelotKey!.isNotEmpty)
          ? prev.camelotKey!
          : automix.parseCamelotKey(prev.musicalKey);
      final prevBpm = (prev.bpm != null && prev.bpm! >= 40.0) ? prev.bpm! : 120.0;

      int bestIdx = 0;
      double bestScore = double.infinity;

      for (int i = 0; i < remaining.length; i++) {
        final cand = remaining[i];
        final candKey = (cand.camelotKey != null && cand.camelotKey!.isNotEmpty)
            ? cand.camelotKey!
            : automix.parseCamelotKey(cand.musicalKey);
        final candBpm = (cand.bpm != null && cand.bpm! >= 40.0) ? cand.bpm! : 120.0;
        final double harmonicPenalty;
        if (prevKey.isEmpty || candKey.isEmpty) {
          harmonicPenalty = 12.0;
        } else {
          final rel = automix.getHarmonicRelation(prevKey, candKey);
          harmonicPenalty = switch (rel) {
            CamelotHarmonicRelation.exactMatch => 0.0,
            CamelotHarmonicRelation.relativePair => 3.0,
            CamelotHarmonicRelation.subdominant => 5.0,
            CamelotHarmonicRelation.dominant => 5.0,
            CamelotHarmonicRelation.energyBoost => 10.0,
            CamelotHarmonicRelation.nearMiss => 16.0,
            CamelotHarmonicRelation.incompatible => 35.0,
          };
        }
        double bpmRatio = candBpm > 0 ? (prevBpm / candBpm) : 1.0;
        if (bpmRatio > 1.41421356) {
          bpmRatio *= 0.5;
        } else if (bpmRatio < 0.70710678) {
          bpmRatio *= 2.0;
        }
        final bpmPenalty = ((1.0 - bpmRatio).abs()) * 100.0;
        final score = harmonicPenalty + bpmPenalty;
        if (score < bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }
      ordered.add(remaining.removeAt(bestIdx));
    }

    final updated = current.copyWith(tracks: ordered);
    await _writePlaylistToDb(updated);
    return updated;
  }

  /// Returns indices of duplicate tracks (by `fileHash` or normalized `artist|title`).
  Set<String> findDuplicatePaths(List<LocalSongItem> tracks) {
    final seenKeys = <String>{};
    final dupPaths = <String>{};
    for (final t in tracks) {
      final key = (t.fileHash != null && t.fileHash!.isNotEmpty)
          ? 'hash:${t.fileHash}'
          : '${t.artist.trim().toLowerCase()}|${t.title.trim().toLowerCase()}';
      if (!seenKeys.add(key)) {
        dupPaths.add(t.path);
      }
    }
    return dupPaths;
  }

  Future<SavedM3uPlaylist?> removeDuplicates(String playlistId) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null || row.isSmart) return null;
    final current = await _hydratePlaylistRow(row);
    final seenKeys = <String>{};
    final deduped = <LocalSongItem>[];
    for (final t in current.tracks) {
      final key = (t.fileHash != null && t.fileHash!.isNotEmpty)
          ? 'hash:${t.fileHash}'
          : '${t.artist.trim().toLowerCase()}|${t.title.trim().toLowerCase()}';
      if (seenKeys.add(key)) {
        deduped.add(t);
      }
    }
    final updated = current.copyWith(tracks: deduped);
    await _writePlaylistToDb(updated);
    return updated;
  }

  /// Returns track paths whose underlying file no longer exists on disk.
  List<String> findMissingTrackPaths(List<LocalSongItem> tracks) {
    final missing = <String>[];
    for (final t in tracks) {
      if (t.path.startsWith('http://') ||
          t.path.startsWith('https://') ||
          t.path.startsWith('ftp://')) {
        continue;
      }
      if (!File(t.realFilePath).existsSync()) {
        missing.add(t.path);
      }
    }
    return missing;
  }

  /// Attempts to relink missing playlist tracks by matching filename in `local_tracks`.
  Future<({SavedM3uPlaylist? playlist, int relinkedCount})> relinkMissingTracks(
    String playlistId,
  ) async {
    await _ensureMigrated();
    final row = await _db.getPlaylistById(playlistId);
    if (row == null || row.isSmart) {
      return (playlist: null, relinkedCount: 0);
    }
    final current = await _hydratePlaylistRow(row);
    final missingPaths = findMissingTrackPaths(current.tracks).toSet();
    if (missingPaths.isEmpty) {
      return (playlist: current, relinkedCount: 0);
    }

    final allLocal = await _db.getAllLocalTracks();
    final byBasename = <String, LocalSongItem>{};
    for (final item in allLocal) {
      if (File(item.realFilePath).existsSync()) {
        byBasename[p.basename(item.realFilePath).toLowerCase()] = item;
      }
    }

    int relinked = 0;
    final updatedTracks = <LocalSongItem>[];
    for (final t in current.tracks) {
      if (!missingPaths.contains(t.path)) {
        updatedTracks.add(t);
        continue;
      }
      final match = byBasename[p.basename(t.realFilePath).toLowerCase()];
      if (match != null) {
        updatedTracks.add(match);
        relinked++;
      } else {
        updatedTracks.add(t);
      }
    }

    if (relinked == 0) {
      return (playlist: current, relinkedCount: 0);
    }
    final updated = current.copyWith(tracks: updatedTracks);
    await _writePlaylistToDb(updated);
    return (playlist: updated, relinkedCount: relinked);
  }

  /// Generates `.m3u8` string content, optionally using relative paths for portability.
  String generateM3u8Content({
    required String playlistName,
    required List<LocalSongItem> tracks,
    String? baseDirectoryForRelativePaths,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#PLAYLIST:$playlistName');

    for (final song in tracks) {
      final artistTitle =
          song.artist.isNotEmpty && song.artist != 'Unknown Artist'
              ? '${song.artist} - ${song.title}'
              : song.title;
      final durationSec =
          song.durationMs != null ? (song.durationMs! ~/ 1000) : -1;
      buffer.writeln('#EXTINF:$durationSec,$artistTitle');

      String outPath = song.path;
      if (baseDirectoryForRelativePaths != null &&
          baseDirectoryForRelativePaths.isNotEmpty &&
          !song.path.startsWith('http') &&
          !song.path.startsWith('ftp')) {
        try {
          outPath = p.relative(song.path, from: baseDirectoryForRelativePaths);
        } catch (_) {}
      }
      buffer.writeln(outPath);
    }

    return buffer.toString();
  }

  /// Exports a list of [LocalSongItem] tracks to an `.m3u8` file on disk.
  Future<File> exportToM3u8({
    required String targetFilePath,
    required String playlistName,
    required List<LocalSongItem> tracks,
    bool useRelativePaths = false,
  }) async {
    final content = generateM3u8Content(
      playlistName: playlistName,
      tracks: tracks,
      baseDirectoryForRelativePaths:
          useRelativePaths ? p.dirname(targetFilePath) : null,
    );
    final file = File(targetFilePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return await file.writeAsString(content);
  }
}
