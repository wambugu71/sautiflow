import 'package:drift/drift.dart';

/// Indexed local audio track metadata for scalable windowed lazy loading.
@TableIndex(name: 'idx_local_tracks_title', columns: {#title})
@TableIndex(name: 'idx_local_tracks_artist', columns: {#artist})
@TableIndex(name: 'idx_local_tracks_album', columns: {#album})
@TableIndex(name: 'idx_local_tracks_modified', columns: {#lastModifiedMs})
@TableIndex(name: 'idx_local_tracks_size', columns: {#sizeBytes})
@TableIndex(name: 'idx_local_tracks_ext', columns: {#extension})
@TableIndex(name: 'idx_local_tracks_real_path', columns: {#realFilePath})
class LocalTrackEntries extends Table {
  @override
  String get tableName => 'local_tracks';

  /// Canonical path (including CUE virtual path if applicable).
  TextColumn get path => text()();

  /// Physical file path on disk (without CUE virtual suffix).
  TextColumn get realFilePath => text()();

  /// Immediate parent directory name for folder grouping.
  TextColumn get folderName => text()();

  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('Unknown Artist'))();
  TextColumn get album => text().withDefault(const Constant('Unknown Album'))();
  TextColumn get genre => text().withDefault(const Constant('Unknown Genre'))();

  /// Lowercase file extension (e.g. '.flac', '.mp3').
  TextColumn get extension => text().withDefault(const Constant(''))();

  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get lastModifiedMs => integer()();
  TextColumn get fileHash => text().nullable()();

  // Optional CUE sheet virtual sub-track fields
  IntColumn get startMs => integer().nullable()();
  IntColumn get endMs => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  TextColumn get cueFilePath => text().nullable()();
  IntColumn get year => integer().nullable()();

  @override
  Set<Column> get primaryKey => {path};
}
