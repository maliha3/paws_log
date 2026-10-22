import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/reminder_draft.dart';
import 'package:paws_log/domain/models/reminder_event.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late ReminderRepository reminders;
  late ReminderEventRepository events;

  /// 15 March 2026 at 09:00 in the test's zone. Set in [setUpAll], because
  /// the timezone database has to be loaded before a location exists.
  late final tz.TZDateTime now;

  // A zone with DST, so wall-clock handling is exercised rather than assumed.
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));
    now = tz.TZDateTime(tz.local, 2026, 3, 15, 9);
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pets = PetRepository(db);
    reminders = ReminderRepository(db);
    events = ReminderEventRepository(db);
  });

  tearDown(() => db.close());

  /// Reads an instant back in the zone the app is running in.
  tz.TZDateTime inZone(DateTime value) => tz.TZDateTime.from(value, tz.local);
  DateTime dateOnlyUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  Future<Pet> addCat() => pets.create(
    name: 'Mochi',
    breed: 'Ragdoll',
    sex: PetSex.female,
    neutered: true,
    birthday: DateTime.utc(2022, 6, 1),
    now: now,
  );

  test('a pet round-trips through the database', () async {
    final created = await addCat();
    final loaded = await pets.findById(created.id);

    expect(loaded, isNotNull);
    expect(loaded!.name, 'Mochi');
    expect(loaded.breed, 'Ragdoll');
    expect(loaded.sex, PetSex.female);
    expect(loaded.neutered, isTrue);
    expect(await pets.countActive(), 1);
  });

  test('drafts save as reminders, each with one pending event', () async {
    final pet = await addCat();
    final saved = await reminders.createFromDrafts(
      petId: pet.id,
      now: now,
      drafts: [
        ReminderDraft(
          title: 'Deworming',
          category: ReminderCategory.deworming,
          repeat: const RepeatRule.months(3),
          firstDue: dateOnlyUtc(now),
          timeOfDayMinutes: 9 * 60,
        ),
        ReminderDraft(
          title: 'Skipped by the owner',
          category: ReminderCategory.other,
          repeat: const RepeatRule.months(1),
          firstDue: dateOnlyUtc(now),
          timeOfDayMinutes: 9 * 60,
          enabled: false,
        ),
      ],
    );

    expect(saved, hasLength(1), reason: 'disabled drafts are not saved');
    expect(saved.single.nextDueAt, isNotNull);

    final due = await events.watchDueAndOverdue(now: now).first;
    expect(due, hasLength(1));
    expect(due.single.reminder.title, 'Deworming');
    expect(due.single.pet.name, 'Mochi');
    expect(due.single.event.status, ReminderEventStatus.pending);
  });

  test('marking done closes the event and opens the next one', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    final due = await events.watchDueAndOverdue(now: now).first;
    final outcome = await events.markDone(due.single.event.id, now: now);

    final closed = await events.findById(outcome.eventId);
    expect(closed!.status, ReminderEventStatus.done);
    expect(closed.completedAt, isNotNull);

    expect(outcome.createdEventId, isNotNull);
    final next = await events.findById(outcome.createdEventId!);
    expect(next!.status, ReminderEventStatus.pending);
    expect(inZone(next.scheduledFor).month, 6, reason: 'three months on');
    expect(inZone(next.scheduledFor).day, 15);

    final afterwards = await reminders.findById(reminder.id);
    expect(afterwards!.nextDueAt, next.scheduledFor);

    // Nothing is left for today.
    expect(await events.watchDueAndOverdue(now: now).first, isEmpty);
  });

  test('undo puts the event, the follow-on and nextDueAt back', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Flea & tick',
      category: ReminderCategory.fleaTick,
      repeat: const RepeatRule.months(1),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    final before = await reminders.findById(reminder.id);

    final due = await events.watchDueAndOverdue(now: now).first;
    final outcome = await events.markDone(due.single.event.id, now: now);
    await events.undo(outcome);

    final restored = await events.findById(outcome.eventId);
    expect(restored!.status, ReminderEventStatus.pending);
    expect(restored.completedAt, isNull);
    expect(await events.findById(outcome.createdEventId!), isNull);
    expect((await reminders.findById(reminder.id))!.nextDueAt, before!.nextDueAt);
    expect(await events.watchDueAndOverdue(now: now).first, hasLength(1));
  });

  test('a one-off has nothing to follow it', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Post-op check',
      category: ReminderCategory.other,
      repeat: const RepeatRule.once(),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    final due = await events.watchDueAndOverdue(now: now).first;
    final outcome = await events.markDone(due.single.event.id, now: now);

    expect(outcome.createdEventId, isNull);
    expect((await reminders.findById(reminder.id))!.nextDueAt, isNull);
  });

  test('snoozing keeps the event pending and moves when it fires', () async {
    final pet = await addCat();
    await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    final due = await events.watchDueAndOverdue(now: now).first;

    final until = await events.snoozeToTomorrow(due.single.event.id, now: now);
    final snoozed = await events.findById(due.single.event.id);

    expect(snoozed!.status, ReminderEventStatus.pending);
    expect(snoozed.snoozedUntil, until);
    expect(snoozed.notifyAt, until);
    expect(inZone(until).day, 16);
    expect(inZone(until).hour, 9, reason: "the reminder's own time of day");
    // It is still on Today: a snooze moves the notification, not the due date.
    expect(await events.watchDueAndOverdue(now: now).first, hasLength(1));
  });

  test('overdue items from earlier days still show on Today', () async {
    final pet = await addCat();
    await reminders.create(
      petId: pet.id,
      title: 'Yearly vaccine',
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.years(1),
      anchorDate: DateTime.utc(2026, 2, 1),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    final due = await events.watchDueAndOverdue(now: now).first;
    expect(due, hasLength(1));
    expect(due.single.isOverdue(now), isTrue);
  });

  test('scheduling only looks at future pending occurrences', () async {
    final pet = await addCat();
    await reminders.create(
      petId: pet.id,
      title: 'Already overdue',
      category: ReminderCategory.other,
      repeat: const RepeatRule.once(),
      anchorDate: DateTime.utc(2026, 2, 1),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    await reminders.create(
      petId: pet.id,
      title: 'Coming up',
      category: ReminderCategory.other,
      repeat: const RepeatRule.once(),
      anchorDate: DateTime.utc(2026, 4, 1),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    final upcoming = await events.upcomingForScheduling(limit: 10, from: now);
    expect(upcoming, hasLength(1));
    expect(upcoming.single.reminder.title, 'Coming up');
  });

  test('archived pets and inactive reminders drop off Today', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    expect(await events.watchDueAndOverdue(now: now).first, hasLength(1));

    await reminders.setActive(reminder.id, isActive: false, now: now);
    expect(await events.watchDueAndOverdue(now: now).first, isEmpty);

    await reminders.setActive(reminder.id, isActive: true, now: now);
    await pets.archive(pet.id, now: now);
    expect(await events.watchDueAndOverdue(now: now).first, isEmpty);
  });

  test('deleting a pet cascades to its reminders and events', () async {
    final pet = await addCat();
    await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    await pets.delete(pet.id);

    expect(await db.select(db.reminders).get(), isEmpty);
    expect(await db.select(db.reminderEvents).get(), isEmpty);
  });

  test('editing the schedule moves the pending event with it', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    await reminders.update(
      reminder.copyWith(
        anchorDate: DateTime.utc(2026, 4, 20),
        timeOfDayMinutes: 18 * 60,
      ),
      now: now,
    );

    final pending = await db.select(db.reminderEvents).getSingle();
    expect(pending.status, ReminderEventStatus.pending);
    expect(inZone(pending.scheduledFor).month, 4);
    expect(inZone(pending.scheduledFor).day, 20);
    expect(inZone(pending.scheduledFor).hour, 18);
    expect((await reminders.findById(reminder.id))!.nextDueAt, pending.scheduledFor);
  });

  test('a snooze is cleared when the schedule is edited', () async {
    final pet = await addCat();
    final reminder = await reminders.create(
      petId: pet.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateOnlyUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    final due = await events.watchDueAndOverdue(now: now).first;
    await events.snoozeOneHour(due.single.event.id, now: now);

    await reminders.update(
      reminder.copyWith(anchorDate: DateTime.utc(2026, 5, 1)),
      now: now,
    );

    final pending = await db.select(db.reminderEvents).getSingle();
    expect(pending.snoozedUntil, isNull);
  });

  test('foreign keys are enforced', () async {
    await expectLater(
      db.into(db.reminders).insert(
        RemindersCompanion.insert(
          id: 'orphan',
          petId: 'no-such-pet',
          title: 'Orphan',
          category: ReminderCategory.other,
          repeatUnit: RepeatUnit.none,
          anchorDate: DateTime.utc(2026, 3, 15),
          timeOfDayMinutes: 540,
          createdAt: now.toUtc(),
          updatedAt: now.toUtc(),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
