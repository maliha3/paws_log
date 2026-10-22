import 'package:drift/drift.dart';

import '../../../domain/models/reminder_event.dart';
import 'reminders.dart';

/// One row per occurrence of a reminder: what is due, what was done, and the
/// history behind both.
@DataClassName('ReminderEventRow')
class ReminderEvents extends Table {
  TextColumn get id => text()();
  TextColumn get reminderId =>
      text().references(Reminders, #id, onDelete: KeyAction.cascade)();

  /// When the occurrence is due, as UTC.
  DateTimeColumn get scheduledFor => dateTime()();

  TextColumn get status => textEnum<ReminderEventStatus>()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
