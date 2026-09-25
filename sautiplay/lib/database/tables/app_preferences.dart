import 'package:drift/drift.dart';

/// Universal key-value storage table for reactive preferences and state flags.
class AppPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
