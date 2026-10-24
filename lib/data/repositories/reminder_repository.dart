import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_draft.dart';
import '../../domain/models/reminder_event.dart';
import '../../domain/repeat_rule.dart';
import '../../domain/schedule_sync.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes reminders, keeping each active reminder's single pending
/// event and denormalised `nextDueAt` in step.
class ReminderRepository {
  ReminderRepository(
    this._db, {
    this.scheduleSync = const NoopScheduleSync(),
    this.uuid = const Uuid(),
  });

  final AppDatabase _db;
  final ScheduleSync scheduleSync;
  final Uuid uuid;

  Stream<List<Reminder>> watchForPet(String petId) {
    final query = _db.select(_db.reminders)
      ..where((reminder) => reminder.petId.equals(petId))
      ..orderBy([(reminder) => OrderingTerm.asc(reminder.nextDueAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<Reminder?> findById(String id) async {
    final row = await (_db.select(_db.reminders)
          ..where((reminder) => reminder.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// Saves [drafts] for [petId], each with its first pending event.
  ///
  /// Disabled drafts are skipped. Everything lands in one transaction so a
  /// half-saved schedule is impossible, and notifications resync once at the
  /// end rather than per reminder.
  Future<List<Reminder>> createFromDrafts({
    required String petId,
    required List<ReminderDraft> drafts,
    DateTime? now,
  }) async {
    final kept = drafts.where((draft) => draft.enabled).toList();
    if (kept.isEmpty) {
      return const [];
    }
    final timestamp = (now ?? DateTime.now()).toUtc();

    final created = await _db.transaction(() async {
      final reminders = <Reminder>[];
      for (final draft in kept) {
        reminders.add(
          await _insert(
            petId: petId,
            title: draft.title,
            category: draft.category,
            repeat: draft.repeat,
            anchorDate: draft.firstDue,
            timeOfDayMinutes: draft.timeOfDayMinutes,
            notes: draft.notes,
            timestamp: timestamp,
          ),
        );
      }
      return reminders;
    });

    await scheduleSync.syncAll();
    return created;
  }

  /// Saves a single reminder with its first pending event.
  Future<Reminder> create({
    required String petId,
    required String title,
    required ReminderCategory category,
    required RepeatRule repeat,
    required DateTime anchorDate,
    required int timeOfDayMinutes,
    String? notes,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final reminder = await _db.transaction(
      () => _insert(
        petId: petId,
        title: title,
        category: category,
        repeat: repeat,
        anchorDate: anchorDate,
        timeOfDayMinutes: timeOfDayMinutes,
        notes: notes,
        timestamp: timestamp,
      ),
    );
    await scheduleSync.syncAll();
    return reminder;
  }

  /// Inserts the reminder and its first event. Caller supplies the
  /// transaction; this does not resync on its own.
  Future<Reminder> _insert({
    required String petId,
    required String title,
    required ReminderCategory category,
    required RepeatRule repeat,
    required DateTime anchorDate,
    required int timeOfDayMinutes,
    required DateTime timestamp,
    String? notes,
  }) async {
    // The first occurrence is the anchor itself, even when the owner picked a
    // date in the past — "the vaccine was due last week" should show up as
    // overdue, not silently skip to next year.
    final firstDue = wallClock(anchorDate, timeOfDayMinutes).toPlainUtc();

    final reminder = Reminder(
      id: uuid.v4(),
      petId: petId,
      title: title.trim(),
      category: category,
      repeat: repeat,
      anchorDate: anchorDate,
      timeOfDayMinutes: timeOfDayMinutes,
      nextDueAt: firstDue,
      notes: notes,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await _db.into(_db.reminders).insert(reminder.toInsertable());
    await _db.into(_db.reminderEvents).insert(
      ReminderEventRow(
        id: uuid.v4(),
        reminderId: reminder.id,
        scheduledFor: firstDue,
        status: ReminderEventStatus.pending,
      ),
    );
    return reminder;
  }

  /// Applies edits to a reminder.
  ///
  /// When the schedule itself moved, the pending event moves with it so Today
  /// and the notification window cannot disagree with the reminder.
  Future<void> update(Reminder reminder, {DateTime? now}) async {
    final existing = await findById(reminder.id);
    if (existing == null) {
      return;
    }
    final scheduleMoved =
        existing.anchorDate != reminder.anchorDate ||
        existing.timeOfDayMinutes != reminder.timeOfDayMinutes ||
        existing.repeat != reminder.repeat;

    await _db.transaction(() async {
      var updated = reminder.copyWith(
        updatedAt: (now ?? DateTime.now()).toUtc(),
      );

      if (scheduleMoved) {
        final due = wallClock(
          reminder.anchorDate,
          reminder.timeOfDayMinutes,
        ).toPlainUtc();
        updated = updated.copyWith(nextDueAt: due);
        await (_db.update(_db.reminderEvents)..where(
              (event) =>
                  event.reminderId.equals(reminder.id) &
                  event.status.equalsValue(ReminderEventStatus.pending),
            ))
            .write(
              ReminderEventsCompanion(
                scheduledFor: Value(due),
                snoozedUntil: const Value(null),
              ),
            );
      }

      await _db.update(_db.reminders).replace(updated.toInsertable());
    });

    await scheduleSync.syncAll();
  }

  /// Turns a reminder off (keeping its history) or back on.
  Future<void> setActive(
    String id, {
    required bool isActive,
    DateTime? now,
  }) async {
    await (_db.update(_db.reminders)..where((r) => r.id.equals(id))).write(
      RemindersCompanion(
        isActive: Value(isActive),
        updatedAt: Value((now ?? DateTime.now()).toUtc()),
      ),
    );
    await scheduleSync.syncAll();
  }

  /// Deletes a reminder and, by cascade, all of its events.
  Future<void> delete(String id) async {
    await (_db.delete(_db.reminders)..where((r) => r.id.equals(id))).go();
    await scheduleSync.syncAll();
  }
}

extension on Reminder {
  ReminderRow toInsertable() => ReminderRow(
    id: id,
    petId: petId,
    title: title,
    category: category,
    repeatUnit: repeat.unit,
    repeatInterval: repeat.interval,
    seasonal: repeat.seasonal,
    anchorDate: anchorDate,
    timeOfDayMinutes: timeOfDayMinutes,
    nextDueAt: nextDueAt,
    isActive: isActive,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
