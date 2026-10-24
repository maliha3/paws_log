import 'package:drift/drift.dart';

import 'pets.dart';

/// One pet's photo album.
///
/// Separate from [Pets.photoPath], which is the single portrait shown beside
/// their name. A vault photo can be promoted to the portrait, but by copy:
/// deleting it from the album must never leave the portrait pointing at
/// nothing.
///
/// There is no thumbnail column. `Image.file(path, cacheWidth: ...)` decodes
/// at grid size, which costs one decode instead of a second file to write,
/// keep in sync, back up and clean up.
@DataClassName('PetPhotoRow')
class PetPhotos extends Table {
  TextColumn get id => text()();

  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  /// Absolute path to the stored copy, inside the app's documents directory.
  TextColumn get path => text()();

  /// When the photo was taken, as far as the app can tell. Falls back to when
  /// it was added, because an owner sorts an album by when things happened.
  DateTimeColumn get takenAt => dateTime()();

  TextColumn get caption => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
