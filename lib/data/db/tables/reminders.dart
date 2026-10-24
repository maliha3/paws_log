import 'package:drift/drift.dart';

import '../../../domain/models/reminder.dart';
import '../../../domain/repeat_rule.dart';
import 'pets.dart';

/// Recurring care items, one row per reminder per pet.
@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get category => textEnum<ReminderCategory>()();

  TextColumn get repeatUnit => textEnum<RepeatUnit>()();
  IntColumn get repeatInterval => integer().withDefault(const Constant(1))();

  /// The date the cycle counts from. Date-only, held at UTC midnight.
  DateTimeColumn get anchorDate => dateTime()();

  /// Minutes past local midnight.
  IntColumn get timeOfDayMinutes => integer()();

  /// Denormalised from the pending event so reminder lists can sort without
  /// joining. Kept in step by [ReminderRepository].
  DateTimeColumn get nextDueAt => dateTime().nullable()();

  /// Whether the interval halves during shedding season. Only meaningful for
  /// a grooming reminder; every other reminder leaves it false.
  BoolColumn get seasonal => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
