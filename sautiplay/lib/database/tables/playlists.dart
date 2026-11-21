import 'package:drift/drift.dart';

/// Relational playlist definitions (standard & smart dynamic playlists).
@TableIndex(name: 'idx_playlists_pinned_updated', columns: {#isPinned, #updatedAtMs})
class PlaylistEntries extends Table {
  @override
  String get tableName => 'playlists';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get pathOrUrl => text().withDefault(const Constant(''))();
  BoolColumn get isNetwork => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isSmart => boolean().withDefault(const Constant(false))();

  /// JSON-encoded SmartPlaylistRule list when [isSmart] is true.
  TextColumn get rulesJson => text().nullable()();
  BoolColumn get matchAll => boolean().withDefault(const Constant(true))();
  TextColumn get sortBy => text().withDefault(const Constant('title_asc'))();
  IntColumn get limitCount => integer().nullable()();

  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered items belonging to a standard playlist.
@TableIndex(name: 'idx_playlist_items_order', columns: {#playlistId, #sortOrder})
@TableIndex(name: 'idx_playlist_items_track', columns: {#trackPath})
class PlaylistItemEntries extends Table {
  @override
  String get tableName => 'playlist_items';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get playlistId => text().references(
        PlaylistEntries,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get trackPath => text()();

  /// Cached fallback snapshot when a track is not yet in `local_tracks` (e.g. network stream).
  TextColumn get fallbackTitle => text().nullable()();
  TextColumn get fallbackArtist => text().nullable()();
  TextColumn get fallbackAlbum => text().nullable()();
  TextColumn get fallbackJson => text().nullable()();

  /// Fractional sort order for O(1) drag-and-drop reordering.
  RealColumn get sortOrder => real()();
  IntColumn get addedAtMs => integer()();
}

/// Snapshot history of tag edits for instant 1-tap Undo.
@TableIndex(name: 'idx_tag_history_path', columns: {#trackPath, #editedAtMs})
class TagEditHistoryEntries extends Table {
  @override
  String get tableName => 'tag_edit_history';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackPath => text()();
  TextColumn get previousTitle => text()();
  TextColumn get previousArtist => text()();
  TextColumn get previousAlbum => text()();
  TextColumn get previousGenre => text()();
  IntColumn get previousYear => integer().nullable()();
  IntColumn get previousTrackNumber => integer().nullable()();
  TextColumn get previousAlbumArtist => text().nullable()();
  IntColumn get previousDiscNumber => integer().nullable()();
  TextColumn get previousComposer => text().nullable()();
  RealColumn get previousBpm => real().nullable()();
  TextColumn get previousMusicalKey => text().nullable()();
  IntColumn get editedAtMs => integer()();
}
