import 'package:drift/drift.dart';

import '../../../domain/models/pet.dart';

/// The pets the owner tracks.
@DataClassName('PetRow')
class Pets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get photoPath => text().nullable()();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get birthday => dateTime().nullable()();

  TextColumn get breed => text().nullable()();

  /// Free text, not an enum: the app is built for cats, but an owner who
  /// keeps a rabbit should not be told their pet is not a kind of pet.
  TextColumn get species => text().nullable()();

  TextColumn get microchip => text().nullable()();

  /// The pet's own vet. A prescription carries whoever wrote it; this is the
  /// practice the owner would ring.
  TextColumn get vetName => text().nullable()();
  TextColumn get vetPhone => text().nullable()();
  TextColumn get sex => textEnum<PetSex>()();

  /// Null means "not recorded".
  BoolColumn get neutered => boolean().nullable()();

  /// What grooming intervals hang off. Null until the owner says.
  TextColumn get coatLength => textEnum<CoatLength>().nullable()();

  TextColumn get origin => textEnum<PetOrigin>().nullable()();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get originDate => dateTime().nullable()();

  TextColumn get originNotes => text().nullable()();
  TextColumn get motherInfo => text().nullable()();
  TextColumn get fatherInfo => text().nullable()();

  TextColumn get dietType => textEnum<DietType>().nullable()();
  TextColumn get foodBrand => text().nullable()();
  TextColumn get feedingNotes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
