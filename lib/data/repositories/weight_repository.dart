import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/weight_entry.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes weighings.
class WeightRepository {
  WeightRepository(this._db, {this.uuid = const Uuid()});

  final AppDatabase _db;
  final Uuid uuid;

  /// One pet's weighings, oldest first — the order a chart reads them in.
  Stream<List<WeightEntry>> watchForPet(String petId) {
    final query = _db.select(_db.weightEntries)
      ..where((entry) => entry.petId.equals(petId))
      ..orderBy([(entry) => OrderingTerm.asc(entry.measuredOn)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<WeightEntry> create({
    required String petId,
    required DateTime measuredOn,
    required int grams,
    String? note,
    DateTime? now,
  }) async {
    final entry = WeightEntry(
      id: uuid.v4(),
      petId: petId,
      measuredOn: measuredOn,
      grams: grams,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _db
        .into(_db.weightEntries)
        .insert(
          WeightEntryRow(
            id: entry.id,
            petId: entry.petId,
            measuredOn: entry.measuredOn,
            grams: entry.grams,
            note: entry.note,
            createdAt: entry.createdAt,
          ),
        );
    return entry;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.weightEntries)..where((e) => e.id.equals(id))).go();
  }
}
