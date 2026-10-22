import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/pet.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes pets.
class PetRepository {
  PetRepository(this._db, {this.uuid = const Uuid()});

  final AppDatabase _db;
  final Uuid uuid;

  /// Active pets, oldest first, as a live stream.
  Stream<List<Pet>> watchPets() {
    final query = _db.select(_db.pets)
      ..where((pet) => pet.archivedAt.isNull())
      ..orderBy([(pet) => OrderingTerm.asc(pet.createdAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<Pet?> findById(String id) async {
    final row = await (_db.select(_db.pets)
          ..where((pet) => pet.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  Future<int> countActive() async {
    final count = _db.pets.id.count();
    final query = _db.selectOnly(_db.pets)
      ..addColumns([count])
      ..where(_db.pets.archivedAt.isNull());
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Inserts a pet and returns it. [now] is injected so onboarding can stamp
  /// the pet and its reminders with the same instant.
  Future<Pet> create({
    required String name,
    String? photoPath,
    DateTime? birthday,
    String? breed,
    PetSex sex = PetSex.unknown,
    bool? neutered,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final pet = Pet(
      id: uuid.v4(),
      name: name.trim(),
      photoPath: photoPath,
      birthday: birthday,
      breed: breed?.trim().isEmpty ?? true ? null : breed!.trim(),
      sex: sex,
      neutered: neutered,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _db.into(_db.pets).insert(pet.toInsertable());
    return pet;
  }

  Future<void> update(Pet pet, {DateTime? now}) async {
    final updated = pet.copyWith(updatedAt: (now ?? DateTime.now()).toUtc());
    await _db.update(_db.pets).replace(updated.toInsertable());
  }

  /// Archives rather than deletes, so completed care history survives.
  Future<void> archive(String id, {DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    await (_db.update(_db.pets)..where((pet) => pet.id.equals(id))).write(
      PetsCompanion(
        archivedAt: Value(timestamp),
        updatedAt: Value(timestamp),
      ),
    );
  }

  /// Deletes a pet and, by cascade, its reminders and their events.
  Future<void> delete(String id) async {
    await (_db.delete(_db.pets)..where((pet) => pet.id.equals(id))).go();
  }
}

extension on Pet {
  PetRow toInsertable() => PetRow(
    id: id,
    name: name,
    photoPath: photoPath,
    birthday: birthday,
    breed: breed,
    sex: sex,
    neutered: neutered,
    createdAt: createdAt,
    updatedAt: updatedAt,
    archivedAt: archivedAt,
  );
}
