import 'package:drift/drift.dart';

/// App preferences, as key/value rows.
///
/// A table rather than shared_preferences: the settings then live in the same
/// file as everything else, so a backup captures them without a second export
/// path, and there is no extra dependency.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
