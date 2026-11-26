import 'package:drift/drift.dart';

/// Persistent, versioned cache of extracted album-artwork perceptual palettes.
@TableIndex(
  name: 'idx_artwork_palettes_accessed',
  columns: {#lastAccessedAtMs},
)
class ArtworkPaletteEntries extends Table {
  @override
  String get tableName => 'artwork_palettes';

  /// SHA-256 content hash of the artwork bytes.
  TextColumn get artworkHash => text()();

  /// Extraction / theme-generation version for automatic cache invalidation.
  IntColumn get algorithmVersion => integer()();

  /// Serialized JSON payload for [ArtworkPaletteAnalysis].
  TextColumn get payloadJson => text()();

  IntColumn get createdAtMs => integer()();
  IntColumn get lastAccessedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {artworkHash};
}
