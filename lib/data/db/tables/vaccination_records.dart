import 'package:drift/drift.dart';

import 'pets.dart';

/// Vaccines that were actually given.
@DataClassName('VaccinationRecordRow')
class VaccinationRecords extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get administeredOn => dateTime()();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get nextDueOn => dateTime().nullable()();

  /// The reminder occurrence this was auto-filled from.
  ///
  /// Deliberately *not* a foreign key. Deleting a reminder must not erase the
  /// record that the vaccine was given; this only exists so undoing a
  /// completion can find the record it created.
  TextColumn get sourceEventId => text().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
