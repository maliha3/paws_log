import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/medicine.dart';
import '../../domain/models/prescription.dart';
import '../../services/photo_store.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes prescriptions and their page images.
///
/// Like visit attachments, the *files* are this repository's business as much
/// as the rows are: a row without its pages is a prescription nobody can
/// check a dose against.
class PrescriptionRepository {
  PrescriptionRepository(
    this._db, {
    PhotoStore? photoStore,
    this.uuid = const Uuid(),
  }) : _photos = photoStore;

  final AppDatabase _db;
  final PhotoStore? _photos;
  final Uuid uuid;

  /// One pet's prescriptions, most recent first.
  Stream<List<Prescription>> watchForPet(String petId) {
    final query = _db.select(_db.prescriptions)
      ..where((row) => row.petId.equals(petId))
      ..orderBy([(row) => OrderingTerm.desc(row.date)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<Prescription?> findById(String id) async {
    final row = await (_db.select(_db.prescriptions)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  /// The medicines this prescription produced.
  Stream<List<Medicine>> watchMedicines(String prescriptionId) {
    final query = _db.select(_db.medicines)
      ..where((row) => row.prescriptionId.equals(prescriptionId))
      ..orderBy([(row) => OrderingTerm.desc(row.startDate)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<Prescription> create({
    required String petId,
    required DateTime date,
    required List<String> imagePaths,
    String? vetVisitId,
    String? vetName,
    String? clinic,
    String? extractedText,
    String? notes,
    DateTime? now,
  }) async {
    final prescription = Prescription(
      id: uuid.v4(),
      petId: petId,
      vetVisitId: vetVisitId,
      date: date,
      vetName: _trimmed(vetName),
      clinic: _trimmed(clinic),
      imagePaths: imagePaths,
      extractedText: extractedText,
      notes: _trimmed(notes),
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _db.into(_db.prescriptions).insert(prescription.toInsertable());
    return prescription;
  }

  Future<void> update(Prescription prescription) =>
      _db.update(_db.prescriptions).replace(prescription.toInsertable());

  /// Removes a prescription, its pages and the files behind them.
  ///
  /// The medicines it produced are left standing — the cat is still on them.
  /// The foreign key clears their link.
  Future<void> delete(String id) async {
    final existing = await findById(id);
    await (_db.delete(_db.prescriptions)..where((row) => row.id.equals(id)))
        .go();

    for (final path in existing?.imagePaths ?? const <String>[]) {
      await _photos?.delete(path);
    }
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

extension PrescriptionInsertable on Prescription {
  PrescriptionRow toInsertable() => PrescriptionRow(
    id: id,
    petId: petId,
    vetVisitId: vetVisitId,
    date: date,
    vetName: vetName,
    clinic: clinic,
    imagePaths: imagePaths,
    extractedText: extractedText,
    notes: notes,
    createdAt: createdAt,
  );
}
