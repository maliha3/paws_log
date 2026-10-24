import 'package:drift/drift.dart';

import '../../domain/dose_schedule.dart';
import '../../domain/models/dose_log.dart';
import '../../domain/models/due_dose.dart';
import '../../domain/schedule_sync.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// What logging a dose changed, so it can be undone.
class DoseOutcome {
  const DoseOutcome({required this.doseId, required this.previousStatus});

  final String doseId;
  final DoseStatus previousStatus;
}

/// Reads and writes individual doses.
class DoseLogRepository {
  DoseLogRepository(this._db, {this.scheduleSync = const NoopScheduleSync()});

  final AppDatabase _db;
  final ScheduleSync scheduleSync;

  /// Today's doses across all pets, earliest first.
  ///
  /// Unlike reminders, a dose that has not come round yet still belongs on
  /// Today: the owner wants to see the day's course, not just the part of it
  /// that has already arrived.
  Stream<List<DueDose>> watchToday({DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = startOfLocalDay(today);
    final end = start.add(const Duration(days: 1));

    final query = _dueDoseQuery()
      ..where(
        _db.doseLogs.scheduledFor.isBiggerOrEqualValue(start) &
            _db.doseLogs.scheduledFor.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.asc(_db.doseLogs.scheduledFor)]);

    return query.watch().map(_toDueDoses);
  }

  Stream<List<DoseLog>> watchForMedicine(String medicineId, {int limit = 200}) {
    final query = _db.select(_db.doseLogs)
      ..where((dose) => dose.medicineId.equals(medicineId))
      ..orderBy([(dose) => OrderingTerm.desc(dose.scheduledFor)])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  /// The [limit] soonest pending doses that are still in the future.
  Future<List<DueDose>> upcomingForScheduling({
    required int limit,
    DateTime? from,
  }) async {
    final query = _dueDoseQuery()
      ..where(
        _db.doseLogs.status.equalsValue(DoseStatus.pending) &
            _db.doseLogs.scheduledFor.isBiggerThanValue(
              (from ?? DateTime.now()).toUtc(),
            ),
      )
      ..orderBy([OrderingTerm.asc(_db.doseLogs.scheduledFor)])
      ..limit(limit);

    return _toDueDoses(await query.get());
  }

  Future<DoseLog?> findById(String id) async {
    final row = await (_db.select(_db.doseLogs)
          ..where((dose) => dose.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// Logs a dose as taken.
  Future<DoseOutcome> logTaken(String id, {DateTime? now}) =>
      _setStatus(id, DoseStatus.taken, now: now);

  /// Records that the owner deliberately passed on a dose.
  Future<DoseOutcome> skip(String id, {DateTime? now}) =>
      _setStatus(id, DoseStatus.skipped, now: now);

  Future<DoseOutcome> _setStatus(
    String id,
    DoseStatus status, {
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final existing = await findById(id);

    await (_db.update(_db.doseLogs)..where((dose) => dose.id.equals(id))).write(
      DoseLogsCompanion(
        status: Value(status),
        takenAt: Value(status == DoseStatus.taken ? timestamp : null),
      ),
    );
    await scheduleSync.syncAll();

    return DoseOutcome(
      doseId: id,
      previousStatus: existing?.status ?? DoseStatus.pending,
    );
  }

  /// Puts a dose back the way it was.
  Future<void> undo(DoseOutcome outcome) async {
    await (_db.update(_db.doseLogs)
          ..where((dose) => dose.id.equals(outcome.doseId)))
        .write(
          DoseLogsCompanion(
            status: Value(outcome.previousStatus),
            takenAt: const Value(null),
          ),
        );
    await scheduleSync.syncAll();
  }

  /// Marks doses whose day has passed without being logged.
  ///
  /// The grace period is the rest of the scheduled day: a dose due at 08:00
  /// is not missed at 08:05, but it is once that day is over. Run on launch
  /// and resume.
  ///
  /// Returns how many were marked.
  Future<int> markOverdueMissed({DateTime? now}) async {
    final startOfToday = startOfLocalDay(now ?? DateTime.now());

    return (_db.update(_db.doseLogs)..where(
          (dose) =>
              dose.status.equalsValue(DoseStatus.pending) &
              dose.scheduledFor.isSmallerThanValue(startOfToday),
        ))
        .write(const DoseLogsCompanion(status: Value(DoseStatus.missed)));
  }

  /// How a course is going, as a partition of every dose generated for it.
  ///
  /// The counting itself is [adherenceOf], so the screen and this agree by
  /// construction rather than by both being written carefully.
  Future<Adherence> adherence(String medicineId) async {
    final rows = await (_db.select(_db.doseLogs)
          ..where((dose) => dose.medicineId.equals(medicineId)))
        .get();
    return adherenceOf(rows.map((row) => row.toDomain()));
  }

  /// The same, live.
  ///
  /// Every dose, not the capped window [watchForMedicine] returns: a count
  /// taken over the most recent two hundred would quietly understate a long
  /// course.
  Stream<Adherence> watchAdherence(String medicineId) {
    final query = _db.select(_db.doseLogs)
      ..where((dose) => dose.medicineId.equals(medicineId));
    return query.watch().map(
      (rows) => adherenceOf(rows.map((row) => row.toDomain())),
    );
  }

  /// Doses joined to their medicine and pet, with stopped courses and
  /// archived pets excluded.
  JoinedSelectStatement<HasResultSet, dynamic> _dueDoseQuery() =>
      _db.select(_db.doseLogs).join([
        innerJoin(
          _db.medicines,
          _db.medicines.id.equalsExp(_db.doseLogs.medicineId),
        ),
        innerJoin(_db.pets, _db.pets.id.equalsExp(_db.medicines.petId)),
      ])..where(
        _db.medicines.isActive.equals(true) & _db.pets.archivedAt.isNull(),
      );

  List<DueDose> _toDueDoses(List<TypedResult> rows) => rows
      .map(
        (row) => DueDose(
          dose: row.readTable(_db.doseLogs).toDomain(),
          medicine: row.readTable(_db.medicines).toDomain(),
          pet: row.readTable(_db.pets).toDomain(),
        ),
      )
      .toList();
}
