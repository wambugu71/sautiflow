import 'package:drift/drift.dart';

/// Structured, indexed table for playback history.
class RecentlyPlayedEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get artistId => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get playedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {videoId};
}
