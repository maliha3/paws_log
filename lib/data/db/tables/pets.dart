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
