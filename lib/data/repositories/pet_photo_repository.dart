import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/pet_photo.dart';
import '../../services/photo_store.dart';
import '../db/app_database.dart';
import '../db/mappers.dart';

/// Reads and writes a pet's photo album, and the files behind it.
///
/// Like prescription pages, the *files* are this repository's business as
/// much as the rows: a row whose file has gone is an album entry nobody can
/// look at.
class PetPhotoRepository {
  PetPhotoRepository(
    this._db, {
    PhotoStore? photoStore,
    this.uuid = const Uuid(),
  }) : _photos = photoStore;

  final AppDatabase _db;
  final PhotoStore? _photos;
  final Uuid uuid;

  /// One pet's album, newest first.
  ///
  /// By `takenAt` rather than `createdAt`: an album of a cat's life reads by
  /// when things happened, not by the order they were imported.
  Stream<List<PetPhoto>> watchForPet(String petId) {
    final query = _db.select(_db.petPhotos)
      ..where((row) => row.petId.equals(petId))
      ..orderBy([
        (row) => OrderingTerm.desc(row.takenAt),
        (row) => OrderingTerm.desc(row.createdAt),
      ]);
    return query.watch().map(
      (rows) => rows.map((row) => row.toDomain()).toList(),
    );
  }

  Future<PetPhoto?> findById(String id) async {
    final row = await (_db.select(_db.petPhotos)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  Future<int> countForPet(String petId) async {
    final count = _db.petPhotos.id.count();
    final query = _db.selectOnly(_db.petPhotos)
      ..addColumns([count])
      ..where(_db.petPhotos.petId.equals(petId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Records a photo already stored on disk.
  Future<PetPhoto> add({
    required String petId,
    required String path,
    DateTime? takenAt,
    String? caption,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final photo = PetPhoto(
      id: uuid.v4(),
      petId: petId,
      path: path,
      takenAt: (takenAt ?? timestamp).toUtc(),
      caption: _trimmed(caption),
      createdAt: timestamp,
    );
    await _db.into(_db.petPhotos).insert(photo.toInsertable());
    return photo;
  }

  /// Asks for photos and records every one the owner picked.
  Future<List<PetPhoto>> addFrom(
    ImageSource source, {
    required String petId,
    DateTime? now,
  }) async {
    final store = _photos;
    if (store == null) {
      return const [];
    }
    final paths = source == ImageSource.camera
        ? [
            ?await store.pick(ImageSource.camera, folder: PhotoStore.petVault),
          ]
        : await store.pickMany(folder: PhotoStore.petVault);

    return [
      for (final path in paths) await add(petId: petId, path: path, now: now),
    ];
  }

  /// Captions are the only thing about a stored photo that can change.
  Future<void> setCaption(String id, String? caption) async {
    await (_db.update(_db.petPhotos)..where((row) => row.id.equals(id))).write(
      PetPhotosCompanion(caption: Value(_trimmed(caption))),
    );
  }

  Future<void> delete(String id) async {
    final existing = await findById(id);
    await (_db.delete(_db.petPhotos)..where((row) => row.id.equals(id))).go();
    if (existing != null) {
      await _photos?.delete(existing.path);
    }
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

extension PetPhotoInsertable on PetPhoto {
  PetPhotoRow toInsertable() => PetPhotoRow(
    id: id,
    petId: petId,
    path: path,
    takenAt: takenAt,
    caption: caption,
    createdAt: createdAt,
  );
}
