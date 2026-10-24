import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../domain/dose_schedule.dart';
import '../../domain/models/dose_log.dart';
import '../../domain/models/medicine.dart';
import '../../domain/repeat_rule.dart';
import '../../domain/schedule_sync.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes medicines, keeping their dose logs generated ahead.
class MedicineRepository {
  MedicineRepository(
    this._db, {
    this.scheduleSync = const NoopScheduleSync(),
    this.uuid = const Uuid(),
  });

  final AppDatabase _db;
  final ScheduleSync scheduleSync;
  final Uuid uuid;

  Stream<List<Medicine>> watchForPet(String petId) {
    final query = _db.select(_db.medicines)
      ..where((medicine) => medicine.petId.equals(petId))
      ..orderBy([
        (medicine) => OrderingTerm.desc(medicine.isActive),
        (medicine) => OrderingTerm.desc(medicine.startDate),
      ]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<Medicine?> findById(String id) async {
    final row = await (_db.select(_db.medicines)
          ..where((medicine) => medicine.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  Future<Medicine> create({
    required String petId,
    required String name,
    required DoseSchedule schedule,
    String? dosage,
    String? notes,
    String? prescriptionId,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final medicine = Medicine(
      id: uuid.v4(),
      petId: petId,
      name: name.trim(),
      dosage: dosage?.trim().isEmpty ?? true ? null : dosage!.trim(),
      schedule: schedule,
      notes: notes,
      prescriptionId: prescriptionId,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await _db.transaction(() async {
      await _db.into(_db.medicines).insert(medicine.toInsertable());
      await _generateDoses(medicine, now: timestamp);
    });

    await scheduleSync.syncAll();
    return medicine;
  }

  /// Applies edits, regenerating doses when the schedule itself moved.
  ///
  /// Only *pending future* doses are replaced. Doses already taken, missed or
  /// skipped are adherence history and are never rewritten.
  Future<void> update(Medicine medicine, {DateTime? now}) async {
    final existing = await findById(medicine.id);
    if (existing == null) {
      return;
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final scheduleMoved = existing.schedule != medicine.schedule;

    await _db.transaction(() async {
      await _db
          .update(_db.medicines)
          .replace(medicine.copyWith(updatedAt: timestamp).toInsertable());

      if (scheduleMoved) {
        await (_db.delete(_db.doseLogs)..where(
              (dose) =>
                  dose.medicineId.equals(medicine.id) &
                  dose.status.equalsValue(DoseStatus.pending) &
                  dose.scheduledFor.isBiggerOrEqualValue(timestamp),
            ))
            .go();
        await _generateDoses(medicine, now: timestamp);
      }
    });

    await scheduleSync.syncAll();
  }

  /// Stops or restarts a course.
  ///
  /// Stopping drops the doses still to come — an owner who stops a medicine
  /// does not want to be reminded of it — while keeping what was logged.
  Future<void> setActive(
    String id, {
    required bool isActive,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.medicines)..where((m) => m.id.equals(id))).write(
        MedicinesCompanion(
          isActive: Value(isActive),
          updatedAt: Value(timestamp),
        ),
      );
      if (isActive) {
        final medicine = await findById(id);
        if (medicine != null) {
          await _generateDoses(medicine, now: timestamp);
        }
      } else {
        await (_db.delete(_db.doseLogs)..where(
              (dose) =>
                  dose.medicineId.equals(id) &
                  dose.status.equalsValue(DoseStatus.pending) &
                  dose.scheduledFor.isBiggerOrEqualValue(timestamp),
            ))
            .go();
      }
    });
    await scheduleSync.syncAll();
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.medicines)..where((m) => m.id.equals(id))).go();
    await scheduleSync.syncAll();
  }

  /// Extends open-ended courses up to the horizon.
  ///
  /// Called on launch and resume. Generation is idempotent, so running it
  /// repeatedly costs nothing and cannot disturb logged doses.
  Future<void> topUpDoses({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final active = await (_db.select(_db.medicines)
          ..where((medicine) => medicine.isActive.equals(true)))
        .get();

    if (active.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final row in active) {
        await _generateDoses(row.toDomain(), now: timestamp);
      }
    });
    await scheduleSync.syncAll();
  }

  /// Writes the dose rows for [medicine] between today and the horizon.
  ///
  /// Ids are derived from the medicine and the instant, so re-running this
  /// inserts only what is genuinely new: an existing dose keeps whatever
  /// status it already has.
  Future<void> _generateDoses(Medicine medicine, {required DateTime now}) async {
    final from = startOfLocalDay(now);
    final end = medicine.schedule.endDate;
    // The end date is a date, not an instant. Passing its UTC midnight as the
    // window's upper bound would clip every dose on the final day, so the
    // window runs to the end of that day in the owner's zone.
    final until = end != null
        ? wallClock(end, 24 * 60 - 1).toPlainUtc()
        : now.add(const Duration(days: AppConstants.doseHorizonDays));

    final occurrences = doseOccurrences(
      medicine.schedule,
      from: from,
      until: until,
    );
    if (occurrences.isEmpty) {
      return;
    }

    await _db.batch((batch) {
      batch.insertAll(
        _db.doseLogs,
        [
          for (final instant in occurrences)
            DoseLogRow(
              id: doseIdFor(medicine.id, instant),
              medicineId: medicine.id,
              scheduledFor: instant,
              status: DoseStatus.pending,
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}

/// A dose's id, derived from its medicine and the instant it falls on.
///
/// Deterministic so that regenerating a course is idempotent without having
/// to read back what already exists.
String doseIdFor(String medicineId, DateTime scheduledFor) =>
    '$medicineId@${scheduledFor.toUtc().millisecondsSinceEpoch}';

extension on Medicine {
  MedicineRow toInsertable() => MedicineRow(
    id: id,
    petId: petId,
    name: name,
    dosage: dosage,
    timesOfDayMinutes: schedule.timesOfDayMinutes,
    intervalDays: schedule.intervalDays,
    startDate: schedule.startDate,
    endDate: schedule.endDate,
    notes: notes,
    prescriptionId: prescriptionId,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
