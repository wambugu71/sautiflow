import 'package:drift/drift.dart';

/// Structured, indexed table for user-liked songs and streams.
class LikedSongEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get artistId => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get likedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {videoId};
}
