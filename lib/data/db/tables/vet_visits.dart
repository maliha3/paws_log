import 'package:drift/drift.dart';

import 'pets.dart';

/// The health log.
@DataClassName('VetVisitRow')
class VetVisits extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get visitedOn => dateTime()();

  TextColumn get reason => text().withLength(min: 1, max: 200)();
  TextColumn get clinic => text().nullable()();
  TextColumn get vetName => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Photos attached to a visit.
@DataClassName('VisitAttachmentRow')
class VisitAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get visitId =>
      text().references(VetVisits, #id, onDelete: KeyAction.cascade)();

  /// Path inside the app's documents directory.
  TextColumn get filePath => text()();

  TextColumn get caption => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
