import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/dose_log_repository.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/domain/models/dose_log.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late MedicineRepository medicines;
  late DoseLogRepository doses;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    // Midday, so "earlier today" and "later today" are both expressible.
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 12);
    db = memoryDatabase();
    pets = PetRepository(db);
    medicines = MedicineRepository(db);
    doses = DoseLogRepository(db);
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() => db.close());

  DateTime date(int year, int month, int day) => DateTime.utc(year, month, day);

  Future<Medicine> addCourse({
    List<int> times = const [8 * 60, 20 * 60],
    DateTime? start,
    DateTime? end,
    int intervalDays = 1,
  }) => medicines.create(
    petId: petId,
    name: 'Amoxicillin',
    dosage: '1 tablet',
    now: now,
    schedule: DoseSchedule(
      timesOfDayMinutes: times,
      startDate: start ?? date(2026, 5, 4),
      endDate: end,
      intervalDays: intervalDays,
    ),
  );

  Future<List<DoseLogRow>> allDoses() async {
    final rows = await db.select(db.doseLogs).get();
    rows.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return rows;
  }

  test('a finite course generates its whole run up front', () async {
    await addCourse(end: date(2026, 5, 6));

    final rows = await allDoses();
    expect(rows, hasLength(6), reason: 'two a day for three days');
    expect(rows.every((dose) => dose.status == DoseStatus.pending), isTrue);
  });

  test('an open-ended course stops at the horizon', () async {
    await addCourse(times: const [9 * 60]);

    // 14 days of cover, counted from today.
    expect(await allDoses(), hasLength(15));
  });

  test('a medicine round-trips with its schedule', () async {
    final created = await addCourse(end: date(2026, 5, 6));
    final loaded = await medicines.findById(created.id);

    expect(loaded!.name, 'Amoxicillin');
    expect(loaded.dosage, '1 tablet');
    expect(loaded.schedule.timesOfDayMinutes, [480, 1200]);
    expect(loaded.schedule.endDate, date(2026, 5, 6));
    expect(loaded.schedule.isOpenEnded, isFalse);
  });

  test('generation is idempotent, so topping up changes nothing', () async {
    await addCourse(end: date(2026, 5, 10));
    final first = await allDoses();

    await medicines.topUpDoses(now: now);
    await medicines.topUpDoses(now: now);

    final second = await allDoses();
    expect(second.map((d) => d.id), first.map((d) => d.id));
  });

  test('topping up never disturbs a dose already logged', () async {
    await addCourse(end: date(2026, 5, 10));
    final evening = (await allDoses()).firstWhere(
      (dose) => tz.TZDateTime.from(dose.scheduledFor, tz.local).hour == 20,
    );
    await doses.logTaken(evening.id, now: now);

    await medicines.topUpDoses(now: now);

    final after = await doses.findById(evening.id);
    expect(after!.status, DoseStatus.taken);
    expect(after.takenAt, isNotNull);
  });

  test('the horizon advances as time passes', () async {
    await addCourse(times: const [9 * 60]);
    expect(await allDoses(), hasLength(15));

    await medicines.topUpDoses(now: now.add(const Duration(days: 7)));

    expect(await allDoses(), hasLength(22), reason: 'seven more days of cover');
  });

  test('logging a dose taken records when', () async {
    await addCourse(end: date(2026, 5, 6));
    final first = (await allDoses()).first;

    final outcome = await doses.logTaken(first.id, now: now);

    final logged = await doses.findById(first.id);
    expect(logged!.status, DoseStatus.taken);
    expect(logged.takenAt, now.toPlainUtc());
    expect(outcome.previousStatus, DoseStatus.pending);
  });

  test('undo puts a logged dose back', () async {
    await addCourse(end: date(2026, 5, 6));
    final first = (await allDoses()).first;

    final outcome = await doses.logTaken(first.id, now: now);
    await doses.undo(outcome);

    final restored = await doses.findById(first.id);
    expect(restored!.status, DoseStatus.pending);
    expect(restored.takenAt, isNull);
  });

  test('skipping is recorded without a taken time', () async {
    await addCourse(end: date(2026, 5, 6));
    final first = (await allDoses()).first;

    await doses.skip(first.id, now: now);

    final skipped = await doses.findById(first.id);
    expect(skipped!.status, DoseStatus.skipped);
    expect(skipped.takenAt, isNull);
  });

  group('missed', () {
    test('a dose earlier today is not missed yet', () async {
      await addCourse(end: date(2026, 5, 6));

      final marked = await doses.markOverdueMissed(now: now);

      expect(marked, 0, reason: 'the grace period is the rest of the day');
      final morning = (await allDoses()).first;
      expect(morning.status, DoseStatus.pending);
    });

    test("once the day is over, the day's unlogged doses are missed", () async {
      await addCourse(end: date(2026, 5, 6));

      final marked = await doses.markOverdueMissed(
        now: now.add(const Duration(days: 1)),
      );

      expect(marked, 2, reason: "both of the 4th's doses");
      final rows = await allDoses();
      expect(rows[0].status, DoseStatus.missed);
      expect(rows[1].status, DoseStatus.missed);
      expect(rows[2].status, DoseStatus.pending, reason: 'the 5th is today');
    });

    test('a dose already logged is left alone', () async {
      await addCourse(end: date(2026, 5, 6));
      final rows = await allDoses();
      await doses.logTaken(rows[0].id, now: now);
      await doses.skip(rows[1].id, now: now);

      final marked = await doses.markOverdueMissed(
        now: now.add(const Duration(days: 1)),
      );

      expect(marked, 0);
      expect((await doses.findById(rows[0].id))!.status, DoseStatus.taken);
      expect((await doses.findById(rows[1].id))!.status, DoseStatus.skipped);
    });
  });

  group('editing a course', () {
    test('changing the schedule replaces only future pending doses', () async {
      final medicine = await addCourse(end: date(2026, 5, 10));
      final rows = await allDoses();
      await doses.logTaken(rows[0].id, now: now);

      await medicines.update(
        medicine.copyWith(
          schedule: medicine.schedule.copyWith(
            timesOfDayMinutes: const [9 * 60],
          ),
        ),
        now: now,
      );

      final after = await allDoses();
      // The logged dose survives as history.
      expect(
        after.where((d) => d.status == DoseStatus.taken),
        hasLength(1),
      );
      // Today's remaining 20:00 dose is gone, replaced by nothing today
      // (09:00 has passed), and the rest of the course is once a day.
      expect(
        after.where((d) => d.status == DoseStatus.pending),
        hasLength(7),
        reason: "the 4th to the 10th at 09:00 — today's 09:00 is regenerated "
            'even though it has passed, so it can still be logged',
      );
    });

    test('an unchanged schedule leaves doses alone', () async {
      final medicine = await addCourse(end: date(2026, 5, 10));
      final before = await allDoses();

      await medicines.update(medicine.copyWith(name: 'Amoxil'), now: now);

      expect((await allDoses()).map((d) => d.id), before.map((d) => d.id));
      expect((await medicines.findById(medicine.id))!.name, 'Amoxil');
    });

    test('stopping a course drops what is still to come', () async {
      final medicine = await addCourse(end: date(2026, 5, 10));
      final rows = await allDoses();
      await doses.logTaken(rows[0].id, now: now);

      await medicines.setActive(medicine.id, isActive: false, now: now);

      final after = await allDoses();
      expect(after.where((d) => d.status == DoseStatus.pending), isEmpty);
      expect(after.where((d) => d.status == DoseStatus.taken), hasLength(1));
    });

    test('restarting a course generates doses again', () async {
      final medicine = await addCourse(end: date(2026, 5, 10));
      await medicines.setActive(medicine.id, isActive: false, now: now);
      expect(await allDoses(), hasLength(1), reason: "only today's 08:00");

      await medicines.setActive(medicine.id, isActive: true, now: now);

      expect(await allDoses(), hasLength(14));
    });

    test('a stopped course drops off Today', () async {
      final medicine = await addCourse(end: date(2026, 5, 10));
      expect(await doses.watchToday(now: now).first, hasLength(2));

      await medicines.setActive(medicine.id, isActive: false, now: now);

      expect(await doses.watchToday(now: now).first, isEmpty);
    });
  });

  test("Today shows the whole day's course, not just what has arrived", () async {
    await addCourse(end: date(2026, 5, 6));

    final today = await doses.watchToday(now: now).first;

    expect(today, hasLength(2));
    expect(today.first.medicine.name, 'Amoxicillin');
    expect(today.first.pet.name, 'Mochi');
    expect(today.first.isDue(now), isTrue, reason: '08:00 has passed');
    expect(today.last.isDue(now), isFalse, reason: '20:00 has not');
  });

  test('scheduling only looks at future pending doses', () async {
    await addCourse(end: date(2026, 5, 6));

    final upcoming = await doses.upcomingForScheduling(limit: 10, from: now);

    expect(upcoming, hasLength(5), reason: 'the 08:00 today has passed');
    expect(upcoming.first.dose.scheduledFor.isAfter(now), isTrue);
  });

  test('adherence partitions every dose in the course', () async {
    final medicine = await addCourse(end: date(2026, 5, 6));
    final rows = await allDoses();
    await doses.logTaken(rows[0].id, now: now);
    await doses.skip(rows[2].id, now: now);
    await doses.markOverdueMissed(now: now.add(const Duration(days: 1)));

    final summary = await doses.adherence(medicine.id);

    expect(summary.taken, 1);
    expect(summary.missed, 1, reason: "the 4th's evening dose");
    expect(summary.skipped, 1);
    expect(summary.pending, 3);
    expect(
      summary.taken + summary.missed + summary.skipped + summary.pending,
      6,
      reason: 'the partition covers the whole course',
    );
  });

  test('deleting a pet cascades to medicines and their doses', () async {
    await addCourse(end: date(2026, 5, 6));

    await pets.delete(petId);

    expect(await db.select(db.medicines).get(), isEmpty);
    expect(await db.select(db.doseLogs).get(), isEmpty);
  });
}
