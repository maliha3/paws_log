import 'package:drift/drift.dart';

import 'pets.dart';

/// Weighings, stored in grams whatever unit the owner reads them in.
@DataClassName('WeightEntryRow')
class WeightEntries extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get measuredOn => dateTime()();

  IntColumn get grams => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
