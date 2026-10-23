import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/dose_schedule.dart';
import '../../domain/models/due_item.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_event.dart';
import '../../domain/models/vaccination_record.dart';
import '../../domain/repeat_rule.dart';
import '../../domain/schedule_sync.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';
import 'vaccination_repository.dart';

/// What a completion changed, so it can be undone.
///
/// Marking something done also creates the next occurrence and moves the
/// reminder's `nextDueAt`; undo has to put all three back.
class CompletionOutcome {
  const CompletionOutcome({
    required this.eventId,
    required this.reminderId,
    required this.previousStatus,
    this.createdEventId,
    this.createdVaccinationId,
    this.previousNextDueAt,
    this.previousSnoozedUntil,
  });

  final String eventId;
  final String reminderId;
  final ReminderEventStatus previousStatus;

  /// The follow-on occurrence, if the reminder repeats.
  final String? createdEventId;

  /// The vaccination record written for this completion, if any.
  ///
  /// Completing a vaccine reminder is what puts a shot in the health log, so
  /// undoing it has to take the record back out again.
  final String? createdVaccinationId;

  final DateTime? previousNextDueAt;
  final DateTime? previousSnoozedUntil;
}

/// Reads and writes reminder occurrences: what is due, completion, and snooze.
class ReminderEventRepository {
  ReminderEventRepository(
    this._db, {
    this.scheduleSync = const NoopScheduleSync(),
    this.uuid = const Uuid(),
  });

  final AppDatabase _db;
  final ScheduleSync scheduleSync;
  final Uuid uuid;

  /// When a pending occurrence should fire: its snooze if it has one.
  Expression<DateTime> get _notifyAt => coalesce([
    _db.reminderEvents.snoozedUntil,
    _db.reminderEvents.scheduledFor,
  ]);

  /// Everything due today or earlier, across all pets, oldest first.
  ///
  /// Archived pets and inactive reminders drop out. [now] is injected so
  /// tests and widget previews can pin "today".
  Stream<List<DueItem>> watchDueAndOverdue({DateTime? now}) {
    final today = now ?? DateTime.now();
    // Local end of today, so an evening reminder still counts as due today.
    final endExclusive = DateTime(today.year, today.month, today.day + 1);

    final query = _dueItemQuery()
      ..where(
        _db.reminderEvents.status.equalsValue(ReminderEventStatus.pending) &
            _db.reminderEvents.scheduledFor.isSmallerThanValue(
              endExclusive.toUtc(),
            ),
      )
      ..orderBy([OrderingTerm.asc(_db.reminderEvents.scheduledFor)]);

    return query.watch().map(_toDueItems);
  }

  /// The [limit] soonest pending occurrences that are still in the future.
  ///
  /// This is the scheduler's source for the rolling notification window; past
  /// occurrences are left out because they cannot be scheduled any more.
  Future<List<DueItem>> upcomingForScheduling({
    required int limit,
    DateTime? from,
  }) async {
    final query = _dueItemQuery()
      ..where(
        _db.reminderEvents.status.equalsValue(ReminderEventStatus.pending) &
            _notifyAt.isBiggerThanValue((from ?? DateTime.now()).toUtc()),
      )
      ..orderBy([OrderingTerm.asc(_notifyAt)])
      ..limit(limit);

    return _toDueItems(await query.get());
  }

  Future<ReminderEvent?> findById(String id) async {
    final row = await (_db.select(_db.reminderEvents)
          ..where((event) => event.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// Marks an occurrence done and opens the next one.
  Future<CompletionOutcome> markDone(String eventId, {DateTime? now}) =>
      _close(eventId, ReminderEventStatus.done, now: now);

  /// Dismisses an occurrence without doing it, and opens the next one.
  Future<CompletionOutcome> skip(String eventId, {DateTime? now}) =>
      _close(eventId, ReminderEventStatus.skipped, now: now);

  Future<CompletionOutcome> _close(
    String eventId,
    ReminderEventStatus status, {
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();

    final outcome = await _db.transaction(() async {
      final event = await (_db.select(_db.reminderEvents)
            ..where((e) => e.id.equals(eventId)))
          .getSingle();
      final reminder = await (_db.select(_db.reminders)
            ..where((r) => r.id.equals(event.reminderId)))
          .getSingle();

      await (_db.update(_db.reminderEvents)..where((e) => e.id.equals(eventId)))
          .write(
            ReminderEventsCompanion(
              status: Value(status),
              completedAt: Value(
                status == ReminderEventStatus.done ? timestamp : null,
              ),
              snoozedUntil: const Value(null),
            ),
          );

      // Completing early must not re-open the occurrence just closed, and
      // completing late skips the missed cycles rather than replaying them.
      final after = event.scheduledFor.isAfter(timestamp)
          ? event.scheduledFor
          : timestamp;
      final next = nextDueAfter(
        anchorDate: reminder.anchorDate,
        timeOfDayMinutes: reminder.timeOfDayMinutes,
        repeat: RepeatRule(
          unit: reminder.repeatUnit,
          interval: reminder.repeatInterval,
        ),
        after: after,
      );

      String? createdEventId;
      if (next != null && reminder.isActive) {
        createdEventId = uuid.v4();
        await _db.into(_db.reminderEvents).insert(
          ReminderEventRow(
            id: createdEventId,
            reminderId: reminder.id,
            scheduledFor: next,
            status: ReminderEventStatus.pending,
          ),
        );
      }

      await (_db.update(_db.reminders)..where((r) => r.id.equals(reminder.id)))
          .write(
            RemindersCompanion(
              nextDueAt: Value(createdEventId == null ? null : next),
              updatedAt: Value(timestamp),
            ),
          );

      // A vaccine that was given belongs in the health log. Only on `done`:
      // skipping a vaccine reminder means it was not given.
      String? createdVaccinationId;
      if (status == ReminderEventStatus.done &&
          reminder.category == ReminderCategory.vaccine) {
        createdVaccinationId = uuid.v4();
        await _db.into(_db.vaccinationRecords).insert(
          VaccinationRecord(
            id: createdVaccinationId,
            petId: reminder.petId,
            name: reminder.title,
            administeredOn: localDateOnly(timestamp),
            nextDueOn: next == null ? null : localDateOnly(next),
            sourceEventId: eventId,
            createdAt: timestamp,
          ).toInsertable(),
        );
      }

      return CompletionOutcome(
        eventId: eventId,
        reminderId: reminder.id,
        previousStatus: event.status,
        createdEventId: createdEventId,
        createdVaccinationId: createdVaccinationId,
        previousNextDueAt: reminder.nextDueAt,
        previousSnoozedUntil: event.snoozedUntil,
      );
    });

    await scheduleSync.syncAll();
    return outcome;
  }

  /// Reverses a [markDone] or [skip]: removes the follow-on occurrence and
  /// restores the event and the reminder's next due date.
  Future<void> undo(CompletionOutcome outcome) async {
    await _db.transaction(() async {
      if (outcome.createdVaccinationId != null) {
        await (_db.delete(_db.vaccinationRecords)
              ..where((r) => r.id.equals(outcome.createdVaccinationId!)))
            .go();
      }
      if (outcome.createdEventId != null) {
        await (_db.delete(_db.reminderEvents)
              ..where((e) => e.id.equals(outcome.createdEventId!)))
            .go();
      }
      await (_db.update(_db.reminderEvents)
            ..where((e) => e.id.equals(outcome.eventId)))
          .write(
            ReminderEventsCompanion(
              status: Value(outcome.previousStatus),
              completedAt: const Value(null),
              snoozedUntil: Value(outcome.previousSnoozedUntil),
            ),
          );
      await (_db.update(_db.reminders)
            ..where((r) => r.id.equals(outcome.reminderId)))
          .write(RemindersCompanion(nextDueAt: Value(outcome.previousNextDueAt)));
    });

    await scheduleSync.syncAll();
  }

  /// Pushes an occurrence out to [until]. The event stays pending; only the
  /// instant it fires at moves.
  Future<void> snooze(String eventId, {required DateTime until}) async {
    await (_db.update(_db.reminderEvents)..where((e) => e.id.equals(eventId)))
        .write(ReminderEventsCompanion(snoozedUntil: Value(until.toUtc())));
    await scheduleSync.syncAll();
  }

  /// Snoozes by an hour from [now].
  Future<DateTime> snoozeOneHour(String eventId, {DateTime? now}) async {
    final until = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 1));
    await snooze(eventId, until: until);
    return until;
  }

  /// Snoozes to tomorrow at the reminder's own time of day.
  Future<DateTime> snoozeToTomorrow(String eventId, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final event = await (_db.select(_db.reminderEvents)
          ..where((e) => e.id.equals(eventId)))
        .getSingle();
    final reminder = await (_db.select(_db.reminders)
          ..where((r) => r.id.equals(event.reminderId)))
        .getSingle();

    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final until = wallClock(
      DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day),
      reminder.timeOfDayMinutes,
    ).toPlainUtc();

    await snooze(eventId, until: until);
    return until;
  }

  /// Events joined to their reminder and pet, with archived pets and inactive
  /// reminders excluded.
  JoinedSelectStatement<HasResultSet, dynamic> _dueItemQuery() =>
      _db.select(_db.reminderEvents).join([
        innerJoin(
          _db.reminders,
          _db.reminders.id.equalsExp(_db.reminderEvents.reminderId),
        ),
        innerJoin(_db.pets, _db.pets.id.equalsExp(_db.reminders.petId)),
      ])..where(
        _db.reminders.isActive.equals(true) & _db.pets.archivedAt.isNull(),
      );

  List<DueItem> _toDueItems(List<TypedResult> rows) => rows
      .map(
        (row) => DueItem(
          event: row.readTable(_db.reminderEvents).toDomain(),
          reminder: row.readTable(_db.reminders).toDomain(),
          pet: row.readTable(_db.pets).toDomain(),
        ),
      )
      .toList();
}
