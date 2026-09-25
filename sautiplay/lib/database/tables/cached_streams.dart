import 'package:drift/drift.dart';

/// Structured, indexed table for offline cached stream metadata.
class CachedStreamEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get filePath => text()();
  TextColumn get streamUrl => text().nullable()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get cachedAt => dateTime()();
  BoolColumn get isUserDownload => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {videoId};
}
