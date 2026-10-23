import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/vaccination_repository.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/reminder_event.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late ReminderRepository reminders;
  late ReminderEventRepository events;
  late VaccinationRepository vaccinations;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    db = memoryDatabase();
    pets = PetRepository(db);
    reminders = ReminderRepository(db);
    events = ReminderEventRepository(db);
    vaccinations = VaccinationRepository(db);
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() => db.close());

  DateTime dateUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  Future<String> addReminder({
    required ReminderCategory category,
    String title = 'Yearly vaccine',
    RepeatRule repeat = const RepeatRule.years(1),
  }) async {
    await reminders.create(
      petId: petId,
      title: title,
      category: category,
      repeat: repeat,
      anchorDate: dateUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    return (await db.select(db.reminderEvents).getSingle()).id;
  }

  test('completing a vaccine reminder writes it into the history', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);

    await events.markDone(eventId, now: now);

    final history = await vaccinations.watchForPet(petId).first;
    expect(history, hasLength(1));
    expect(history.single.name, 'Yearly vaccine');
    expect(history.single.petId, petId);
    expect(history.single.wasAutoFilled, isTrue);
    expect(history.single.sourceEventId, eventId);
  });

  test('the record carries when it was given and when it is next due', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);

    await events.markDone(eventId, now: now);

    final record = (await vaccinations.watchForPet(petId).first).single;
    expect(record.administeredOn, DateTime.utc(2026, 5, 4));
    expect(
      record.nextDueOn,
      DateTime.utc(2027, 5, 4),
      reason: 'a year on, matching the occurrence that was opened',
    );
  });

  test('a one-off vaccine records no next due date', () async {
    final eventId = await addReminder(
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.once(),
    );

    await events.markDone(eventId, now: now);

    expect(
      (await vaccinations.watchForPet(petId).first).single.nextDueOn,
      isNull,
    );
  });

  test('other kinds of care are not vaccination history', () async {
    for (final category in [
      ReminderCategory.deworming,
      ReminderCategory.fleaTick,
      ReminderCategory.other,
    ]) {
      final eventId = await addReminder(category: category, title: 'Care');
      await events.markDone(eventId, now: now);
      await db.delete(db.reminders).go();
    }

    expect(await vaccinations.watchForPet(petId).first, isEmpty);
  });

  test('skipping a vaccine records nothing — it was not given', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);

    await events.skip(eventId, now: now);

    expect(await vaccinations.watchForPet(petId).first, isEmpty);
  });

  test('undo takes the record back out of the history', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);

    final outcome = await events.markDone(eventId, now: now);
    expect(outcome.createdVaccinationId, isNotNull);
    expect(await vaccinations.watchForPet(petId).first, hasLength(1));

    await events.undo(outcome);

    expect(await vaccinations.watchForPet(petId).first, isEmpty);
  });

  test('undoing a non-vaccine completion has nothing to remove', () async {
    final eventId = await addReminder(category: ReminderCategory.deworming);

    final outcome = await events.markDone(eventId, now: now);

    expect(outcome.createdVaccinationId, isNull);
    await events.undo(outcome);
    expect(await vaccinations.watchForPet(petId).first, isEmpty);
  });

  test('history outlives the reminder that produced it', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);
    await events.markDone(eventId, now: now);

    final reminderId = (await db.select(db.reminders).getSingle()).id;
    await reminders.delete(reminderId);

    expect(
      await vaccinations.watchForPet(petId).first,
      hasLength(1),
      reason: 'source_event_id is deliberately not a foreign key',
    );
  });

  test('history does not outlive the pet', () async {
    final eventId = await addReminder(category: ReminderCategory.vaccine);
    await events.markDone(eventId, now: now);

    await pets.delete(petId);

    expect(await db.select(db.vaccinationRecords).get(), isEmpty);
  });

  test('a shot given before the app can be added by hand', () async {
    await vaccinations.create(
      petId: petId,
      name: 'Rabies',
      administeredOn: DateTime.utc(2025, 9, 1),
      nextDueOn: DateTime.utc(2026, 9, 1),
      now: now,
    );

    final record = (await vaccinations.watchForPet(petId).first).single;
    expect(record.name, 'Rabies');
    expect(record.wasAutoFilled, isFalse);
  });

  test('history reads back most recent first', () async {
    await vaccinations.create(
      petId: petId,
      name: 'Older',
      administeredOn: DateTime.utc(2024, 9, 1),
      now: now,
    );
    await vaccinations.create(
      petId: petId,
      name: 'Newer',
      administeredOn: DateTime.utc(2025, 9, 1),
      now: now,
    );

    expect(
      (await vaccinations.watchForPet(petId).first).map((r) => r.name),
      ['Newer', 'Older'],
    );
  });

  test('completing a vaccine twice records both shots', () async {
    final firstEvent = await addReminder(category: ReminderCategory.vaccine);
    await events.markDone(firstEvent, now: now);

    final nextEvent = await (db.select(db.reminderEvents)
          ..where((e) => e.status.equalsValue(ReminderEventStatus.pending)))
        .getSingle();
    await events.markDone(
      nextEvent.id,
      now: tz.TZDateTime(tz.local, 2027, 5, 4, 9),
    );

    final history = await vaccinations.watchForPet(petId).first;
    expect(history, hasLength(2));
    expect(history.map((r) => r.administeredOn), [
      DateTime.utc(2027, 5, 4),
      DateTime.utc(2026, 5, 4),
    ]);
  });
}
