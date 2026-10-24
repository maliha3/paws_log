import 'package:drift/drift.dart';

import '../../../domain/models/pet_condition.dart';
import 'pets.dart';

/// Conditions a vet has diagnosed.
@DataClassName('PetConditionRow')
class PetConditions extends Table {
  TextColumn get id => text()();

  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  TextColumn get status => textEnum<ConditionStatus>()();

  /// When it was diagnosed. Date-only, held at UTC midnight. Null when the
  /// owner does not know, which is common for a cat they took on.
  DateTimeColumn get date => dateTime().nullable()();

  TextColumn get notes => text().nullable()();

  /// Not in the original spec, but ordering needs a tiebreak: two ongoing
  /// conditions with no diagnosis date would otherwise come back in whatever
  /// order sqlite felt like.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Things the pet reacts to.
@DataClassName('PetAllergyRow')
class PetAllergies extends Table {
  TextColumn get id => text()();

  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  TextColumn get allergen => text().withLength(min: 1, max: 120)();

  TextColumn get reaction => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
