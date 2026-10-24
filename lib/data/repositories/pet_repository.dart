import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/pet.dart';
import '../../services/photo_store.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes pets.
class PetRepository {
  PetRepository(this._db, {PhotoStore? photoStore, this.uuid = const Uuid()})
    : _photos = photoStore;

  final AppDatabase _db;
  final PhotoStore? _photos;
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
    CoatLength? coatLength,
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
      coatLength: coatLength,
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

  /// Points the pet's portrait at a copy of [sourcePath].
  ///
  /// A copy, so promoting an album photo and then deleting it from the album
  /// cannot leave the portrait pointing at nothing. The portrait it replaces
  /// is deleted, since nothing else refers to it and an owner changing their
  /// mind a few times should not accumulate files.
  Future<void> setPortrait(
    String petId, {
    required String sourcePath,
    DateTime? now,
  }) async {
    final store = _photos;
    if (store == null) {
      return;
    }
    final pet = await findById(petId);
    if (pet == null) {
      return;
    }
    final copy = await store.copyInto(sourcePath, folder: PhotoStore.petPhotos);
    await update(pet.copyWith(photoPath: copy), now: now);

    final superseded = pet.photoPath;
    if (superseded != null && superseded != copy) {
      await store.delete(superseded);
    }
  }

  /// Deletes a pet, everything recorded about them, and their photo files.
  ///
  /// Foreign keys cascade the rows. Nothing cascades the *files*, so they are
  /// collected first — which is why this one repository reads across tables:
  /// it is the only place that knows what "everything belonging to this pet"
  /// means. Without it a deleted cat left their whole album on disk, and an
  /// owner who deletes a pet to reclaim space would have reclaimed none.
  Future<void> delete(String id) async {
    final files = await _filesOf(id);
    await (_db.delete(_db.pets)..where((pet) => pet.id.equals(id))).go();
    for (final path in files) {
      await _photos?.delete(path);
    }
  }

  /// Every file on disk that belongs to [petId].
  Future<List<String>> _filesOf(String petId) async {
    final paths = <String>[];

    final pet = await findById(petId);
    if (pet?.photoPath != null) {
      paths.add(pet!.photoPath!);
    }

    for (final photo in await (_db.select(_db.petPhotos)
          ..where((row) => row.petId.equals(petId)))
        .get()) {
      paths.add(photo.path);
    }

    for (final prescription in await (_db.select(_db.prescriptions)
          ..where((row) => row.petId.equals(petId)))
        .get()) {
      paths.addAll(prescription.imagePaths);
    }

    // Attachments hang off visits, which hang off the pet.
    final attachments = _db.select(_db.visitAttachments).join([
      innerJoin(
        _db.vetVisits,
        _db.vetVisits.id.equalsExp(_db.visitAttachments.visitId),
      ),
    ])..where(_db.vetVisits.petId.equals(petId));
    for (final row in await attachments.get()) {
      paths.add(row.readTable(_db.visitAttachments).filePath);
    }

    return paths;
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
    coatLength: coatLength,
    origin: origin,
    originDate: originDate,
    originNotes: originNotes,
    motherInfo: motherInfo,
    fatherInfo: fatherInfo,
    dietType: dietType,
    foodBrand: foodBrand,
    feedingNotes: feedingNotes,
    createdAt: createdAt,
    updatedAt: updatedAt,
    archivedAt: archivedAt,
  );
}
