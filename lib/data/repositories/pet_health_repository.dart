import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/pet_condition.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes diagnosed conditions and allergies.
///
/// One repository for two tables because they are never read apart: the
/// Health segment shows conditions above allergies, and the vet summary
/// carries both or neither.
class PetHealthRepository {
  PetHealthRepository(this._db, {this.uuid = const Uuid()});

  final AppDatabase _db;
  final Uuid uuid;

  /// Conditions for one pet: ongoing first, then most recently diagnosed.
  ///
  /// Ordered in Dart rather than SQL. "Ongoing before past" is an order over
  /// an enum's *meaning*, which a text column sorts alphabetically — and
  /// `ongoing` happens to sort before `past`, which would make the right
  /// answer a coincidence waiting to break.
  Stream<List<PetCondition>> watchConditions(String petId) {
    final query = _db.select(_db.petConditions)
      ..where((row) => row.petId.equals(petId));
    return query.watch().map((rows) {
      final conditions = rows.map((row) => row.toDomain()).toList()
        ..sort(_byStatusThenDate);
      return conditions;
    });
  }

  Stream<List<PetAllergy>> watchAllergies(String petId) {
    final query = _db.select(_db.petAllergies)
      ..where((row) => row.petId.equals(petId))
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<PetCondition> addCondition({
    required String petId,
    required String name,
    ConditionStatus status = ConditionStatus.ongoing,
    DateTime? date,
    String? notes,
    DateTime? now,
  }) async {
    final condition = PetCondition(
      id: uuid.v4(),
      petId: petId,
      name: name.trim(),
      status: status,
      date: date,
      notes: _trimmed(notes),
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _db.into(_db.petConditions).insert(condition.toInsertable());
    return condition;
  }

  Future<void> updateCondition(PetCondition condition) =>
      _db.update(_db.petConditions).replace(condition.toInsertable());

  Future<void> setConditionStatus(String id, ConditionStatus status) async {
    await (_db.update(_db.petConditions)..where((row) => row.id.equals(id)))
        .write(PetConditionsCompanion(status: Value(status)));
  }

  Future<void> deleteCondition(String id) async {
    await (_db.delete(_db.petConditions)..where((row) => row.id.equals(id)))
        .go();
  }

  Future<PetAllergy> addAllergy({
    required String petId,
    required String allergen,
    String? reaction,
    String? notes,
    DateTime? now,
  }) async {
    final allergy = PetAllergy(
      id: uuid.v4(),
      petId: petId,
      allergen: allergen.trim(),
      reaction: _trimmed(reaction),
      notes: _trimmed(notes),
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _db.into(_db.petAllergies).insert(allergy.toInsertable());
    return allergy;
  }

  Future<void> updateAllergy(PetAllergy allergy) =>
      _db.update(_db.petAllergies).replace(allergy.toInsertable());

  Future<void> deleteAllergy(String id) async {
    await (_db.delete(_db.petAllergies)..where((row) => row.id.equals(id)))
        .go();
  }

  /// Ongoing before past; within each, the most recent diagnosis first, and a
  /// condition with no date after the ones that have one.
  static int _byStatusThenDate(PetCondition a, PetCondition b) {
    if (a.isOngoing != b.isOngoing) {
      return a.isOngoing ? -1 : 1;
    }
    if (a.date == null || b.date == null) {
      if (a.date != b.date) {
        return a.date == null ? 1 : -1;
      }
      return b.createdAt.compareTo(a.createdAt);
    }
    final byDate = b.date!.compareTo(a.date!);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

extension PetConditionInsertable on PetCondition {
  PetConditionRow toInsertable() => PetConditionRow(
    id: id,
    petId: petId,
    name: name,
    status: status,
    date: date,
    notes: notes,
    createdAt: createdAt,
  );
}

extension PetAllergyInsertable on PetAllergy {
  PetAllergyRow toInsertable() => PetAllergyRow(
    id: id,
    petId: petId,
    allergen: allergen,
    reaction: reaction,
    notes: notes,
    createdAt: createdAt,
  );
}
