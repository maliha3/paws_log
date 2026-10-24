import 'package:drift/drift.dart';

import '../converters/minutes_list_converter.dart';
import 'pets.dart';
import 'prescriptions.dart';

/// Courses of medication.
@DataClassName('MedicineRow')
class Medicines extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get dosage => text().nullable()();

  /// Minutes past local midnight, ascending, one per dose.
  TextColumn get timesOfDayMinutes =>
      text().map(const MinutesListConverter())();

  IntColumn get intervalDays => integer().withDefault(const Constant(1))();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get startDate => dateTime()();

  /// Date-only, held at UTC midnight, inclusive. Null for an open-ended
  /// course.
  DateTimeColumn get endDate => dateTime().nullable()();

  /// The prescription this course came from, when it came from one.
  ///
  /// `setNull` rather than `cascade`: deleting a prescription must not delete
  /// the medicine the owner is still giving their cat.
  TextColumn get prescriptionId => text()
      .nullable()
      .references(Prescriptions, #id, onDelete: KeyAction.setNull)();

  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
