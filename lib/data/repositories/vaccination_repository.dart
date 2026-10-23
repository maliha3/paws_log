import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/vaccination_record.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes the record of vaccines actually given.
///
/// Most rows arrive by themselves, written when a vaccine reminder is marked
/// done; the rest the owner adds for shots given before they started using
/// the app.
class VaccinationRepository {
  VaccinationRepository(this._db, {this.uuid = const Uuid()});

  final AppDatabase _db;
  final Uuid uuid;

  /// One pet's history, most recent first.
  Stream<List<VaccinationRecord>> watchForPet(String petId) {
    final query = _db.select(_db.vaccinationRecords)
      ..where((record) => record.petId.equals(petId))
      ..orderBy([(record) => OrderingTerm.desc(record.administeredOn)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<VaccinationRecord> create({
    required String petId,
    required String name,
    required DateTime administeredOn,
    DateTime? nextDueOn,
    String? notes,
    DateTime? now,
  }) async {
    final record = VaccinationRecord(
      id: uuid.v4(),
      petId: petId,
      name: name.trim(),
      administeredOn: administeredOn,
      nextDueOn: nextDueOn,
      notes: notes,
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _db
        .into(_db.vaccinationRecords)
        .insert(record.toInsertable());
    return record;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.vaccinationRecords)
          ..where((record) => record.id.equals(id)))
        .go();
  }
}

extension VaccinationRecordInsertable on VaccinationRecord {
  VaccinationRecordRow toInsertable() => VaccinationRecordRow(
    id: id,
    petId: petId,
    name: name,
    administeredOn: administeredOn,
    nextDueOn: nextDueOn,
    sourceEventId: sourceEventId,
    notes: notes,
    createdAt: createdAt,
  );
}
