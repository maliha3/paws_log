import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/dose_log_repository.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/domain/models/dose_log.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/schedule_sync.dart';
import 'package:paws_log/services/maintenance.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

/// Records what the database looked like *at the moment* the window was
/// rebuilt.
///
/// That is the one piece of ordering the three steps actually have to get
/// right: the window has to reflect both the doses just marked missed and
/// the ones just generated. A sync that ran first would snapshot neither.
class _SnapshottingScheduleSync implements ScheduleSync {
  _SnapshottingScheduleSync(this.db);

  final AppDatabase db;
  int calls = 0;
  int missedWhenSynced = 0;
  int totalWhenSynced = 0;

  @override
  Future<void> syncAll() async {
    calls++;
    final rows = await db.select(db.doseLogs).get();
    totalWhenSynced = rows.length;
    missedWhenSynced =
        rows.where((dose) => dose.status == DoseStatus.missed).length;
  }
}

void main() {
  late AppDatabase db;
  late DoseLogRepository doses;
  late MedicineRepository medicines;
  late _SnapshottingScheduleSync sync;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 20, 11);
    db = memoryDatabase();
    sync = _SnapshottingScheduleSync(db);
    doses = DoseLogRepository(db);
    medicines = MedicineRepository(db, scheduleSync: sync);
    petId = (await PetRepository(db).create(name: 'Mochi', now: now)).id;
  });

  tearDown(() => db.close());

  Future<void> run() => runMaintenanceWith(
    doses: doses,
    medicines: medicines,
    scheduleSync: sync,
    now: now,
  );

  /// An open-ended course created [startedDaysAgo] days ago.
  ///
  /// The age matters. A course created *now* already has its doses generated
  /// to the horizon, so the top-up has nothing to do and cannot be observed;
  /// one created a week ago has a horizon a week out of date, which is
  /// exactly the state an app that has been closed comes back to.
  Future<Medicine> openEndedCourse({int startedDaysAgo = 0}) {
    final created = now.subtract(Duration(days: startedDaysAgo));
    return medicines.create(
      petId: petId,
      name: 'Thyroxine',
      now: created,
      schedule: DoseSchedule(
        timesOfDayMinutes: const [8 * 60],
        startDate: DateTime.utc(2026, 5, 20 - startedDaysAgo),
      ),
    );
  }

  Future<List<DoseLogRow>> allDoses() => (db.select(db.doseLogs)
        ..orderBy([(dose) => OrderingTerm.asc(dose.scheduledFor)]))
      .get();

  test('a dose whose day has passed is marked missed', () async {
    final medicine = await openEndedCourse();
    // Back-dated by hand: nothing is generated for days already gone.
    await db.into(db.doseLogs).insert(
      DoseLogRow(
        id: 'yesterday',
        medicineId: medicine.id,
        scheduledFor: DateTime.utc(2026, 5, 19, 12),
        status: DoseStatus.pending,
      ),
    );

    await run();

    final yesterday = (await allDoses()).firstWhere(
      (dose) => dose.id == 'yesterday',
    );
    expect(yesterday.status, DoseStatus.missed);
  });

  test('an open-ended course is topped up to the horizon', () async {
    await openEndedCourse(startedDaysAgo: 7);
    final before = (await allDoses()).length;

    await run();

    final after = await allDoses();
    expect(after.length, greaterThan(before));
    expect(
      after.last.scheduledFor.difference(now.toUtc()).inDays,
      greaterThanOrEqualTo(AppConstants.doseHorizonDays - 1),
      reason: 'generated out to the horizon, not just to today',
    );
  });

  test('the window is rebuilt, and rebuilt last', () async {
    // The whole reason the three steps are ordered: a window built before
    // the writes would schedule a notification for a dose already missed,
    // and none at all for the days just generated.
    final medicine = await openEndedCourse(startedDaysAgo: 7);
    await db.into(db.doseLogs).insert(
      DoseLogRow(
        id: 'yesterday',
        medicineId: medicine.id,
        scheduledFor: DateTime.utc(2026, 5, 19, 12),
        status: DoseStatus.pending,
      ),
    );
    final before = (await allDoses()).length;

    await run();

    final after = await allDoses();
    final missed =
        after.where((dose) => dose.status == DoseStatus.missed).length;

    expect(sync.calls, greaterThan(0));
    expect(missed, greaterThan(0), reason: 'there was something to sweep');
    expect(after.length, greaterThan(before), reason: 'and something to add');
    // The invariant: what the window saw is what the writes left behind.
    expect(
      sync.missedWhenSynced,
      missed,
      reason: 'the sweep had already run when the window was built',
    );
    expect(
      sync.totalWhenSynced,
      after.length,
      reason: 'and so had the top-up',
    );
  });

  test('running it again changes nothing', () async {
    // It runs on every resume, which on a phone can be many times an hour.
    await openEndedCourse(startedDaysAgo: 7);
    await run();
    final after = await allDoses();

    await run();

    final again = await allDoses();
    expect(again.length, after.length, reason: 'no duplicate doses');
    expect(again.map((dose) => dose.id), after.map((dose) => dose.id));
  });

  test('a course stopped by hand is not topped up', () async {
    final medicine = await openEndedCourse();
    await medicines.setActive(medicine.id, isActive: false);
    await db.delete(db.doseLogs).go();
    final before = (await allDoses()).length;

    await run();

    expect((await allDoses()).length, before);
  });

  test('a taken dose is never rewritten by the sweep', () async {
    final medicine = await openEndedCourse();
    await db.into(db.doseLogs).insert(
      DoseLogRow(
        id: 'yesterday',
        medicineId: medicine.id,
        scheduledFor: DateTime.utc(2026, 5, 19, 12),
        status: DoseStatus.taken,
        takenAt: DateTime.utc(2026, 5, 19, 12, 30),
      ),
    );

    await run();

    final yesterday = (await allDoses()).firstWhere(
      (dose) => dose.id == 'yesterday',
    );
    expect(yesterday.status, DoseStatus.taken, reason: 'adherence history');
    expect(yesterday.takenAt, isNotNull);
  });

  test('nothing to do is not an error', () async {
    await run();

    expect(await allDoses(), isEmpty);
    expect(sync.calls, greaterThan(0), reason: 'the window is still rebuilt');
  });

  test('it runs through the providers the app actually wires', () async {
    // CLAUDE.md's warning: the scheduler builds its own read-only
    // repositories, and wiring this wrongly makes a write silently fail to
    // rebuild the window.
    await openEndedCourse();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        scheduleSyncProvider.overrideWithValue(sync),
      ],
    );
    addTearDown(container.dispose);

    await runMaintenance(container, now: now);

    expect(sync.calls, greaterThan(0));
    expect(await allDoses(), isNotEmpty);
  });
}
