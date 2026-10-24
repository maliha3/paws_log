import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/pet_condition.dart';

import '../helpers/harness.dart';

/// The v4 schema, exactly as drift emitted it before profile details.
///
/// Written out rather than generated so the test fails loudly if a v4 table
/// is ever changed in place instead of migrated.
const List<String> _v4Schema = [
  'CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT '
      'NOT NULL, PRIMARY KEY ("key"))',
  'CREATE TABLE "dose_logs" ("id" TEXT NOT NULL, "medicine_id" '
      'TEXT NOT NULL REFERENCES medicines (id) ON DELETE CASCADE, '
      '"scheduled_for" TEXT NOT NULL, "status" TEXT NOT NULL, '
      '"taken_at" TEXT NULL, "notes" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "medicines" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "name" TEXT '
      'NOT NULL, "dosage" TEXT NULL, "times_of_day_minutes" TEXT NOT '
      'NULL, "interval_days" INTEGER NOT NULL DEFAULT 1, "start_date" '
      'TEXT NOT NULL, "end_date" TEXT NULL, "prescription_id" TEXT '
      'NULL REFERENCES prescriptions (id) ON DELETE SET NULL, "notes" '
      'TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK '
      '("is_active" IN (0, 1)), "created_at" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pet_photos" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "path" TEXT '
      'NOT NULL, "taken_at" TEXT NOT NULL, "caption" TEXT NULL, '
      '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pets" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"photo_path" TEXT NULL, "birthday" TEXT NULL, "breed" TEXT '
      'NULL, "sex" TEXT NOT NULL, "neutered" INTEGER NULL CHECK '
      '("neutered" IN (0, 1)), "created_at" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, "archived_at" TEXT NULL, PRIMARY '
      'KEY ("id"))',
  'CREATE TABLE "prescriptions" ("id" TEXT NOT NULL, "pet_id" '
      'TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, '
      '"vet_visit_id" TEXT NULL REFERENCES vet_visits (id) ON DELETE '
      'SET NULL, "date" TEXT NOT NULL, "vet_name" TEXT NULL, "clinic" '
      'TEXT NULL, "image_paths" TEXT NOT NULL, "extracted_text" TEXT '
      'NULL, "notes" TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY '
      'KEY ("id"))',
  'CREATE TABLE "reminder_events" ("id" TEXT NOT NULL, '
      '"reminder_id" TEXT NOT NULL REFERENCES reminders (id) ON '
      'DELETE CASCADE, "scheduled_for" TEXT NOT NULL, "status" TEXT '
      'NOT NULL, "completed_at" TEXT NULL, "snoozed_until" TEXT NULL, '
      '"notes" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "reminders" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "title" TEXT '
      'NOT NULL, "category" TEXT NOT NULL, "repeat_unit" TEXT NOT '
      'NULL, "repeat_interval" INTEGER NOT NULL DEFAULT 1, '
      '"anchor_date" TEXT NOT NULL, "time_of_day_minutes" INTEGER NOT '
      'NULL, "next_due_at" TEXT NULL, "is_active" INTEGER NOT NULL '
      'DEFAULT 1 CHECK ("is_active" IN (0, 1)), "notes" TEXT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE TABLE "vaccination_records" ("id" TEXT NOT NULL, '
      '"pet_id" TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, '
      '"name" TEXT NOT NULL, "administered_on" TEXT NOT NULL, '
      '"next_due_on" TEXT NULL, "source_event_id" TEXT NULL, "notes" '
      'TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "vet_visits" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "visited_on" '
      'TEXT NOT NULL, "reason" TEXT NOT NULL, "clinic" TEXT NULL, '
      '"vet_name" TEXT NULL, "notes" TEXT NULL, "created_at" TEXT NOT '
      'NULL, "updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "visit_attachments" ("id" TEXT NOT NULL, '
      '"visit_id" TEXT NOT NULL REFERENCES vet_visits (id) ON DELETE '
      'CASCADE, "file_path" TEXT NOT NULL, "caption" TEXT NULL, '
      '"added_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "weight_entries" ("id" TEXT NOT NULL, "pet_id" '
      'TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, '
      '"measured_on" TEXT NOT NULL, "grams" INTEGER NOT NULL, "note" '
      'TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
];

void main() {
  setUpAll(initializeTestTimeZone);

  /// An executor holding a populated v4 database.
  QueryExecutor v4WithData() => NativeDatabase.memory(
    setup: (raw) {
      for (final statement in _v4Schema) {
        raw.execute(statement);
      }
      raw
        ..execute('PRAGMA user_version = 4')
        ..execute(
          'INSERT INTO pets (id, name, sex, breed, created_at, updated_at) '
          "VALUES ('pet-1', 'Mochi', 'female', 'Ragdoll', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        )
        ..execute(
          'INSERT INTO pet_photos (id, pet_id, path, taken_at, created_at) '
          "VALUES ('photo-1', 'pet-1', '/docs/pet_vault/one.jpg', "
          "'2026-03-01T00:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        );
    },
  );

  test('a v4 database upgrades to v5 with its data intact', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    final pet = (await db.select(db.pets).get()).single;
    expect(pet.name, 'Mochi');
    expect(pet.breed, 'Ragdoll');
    expect((await db.select(db.petPhotos).get()).single.id, 'photo-1');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });

  test('a pet that predates the new fields reads as "not recorded"', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    final pet = (await db.select(db.pets).get()).single;
    expect(
      pet.coatLength,
      isNull,
      reason: 'a guess would mis-schedule grooming',
    );
    expect(pet.origin, isNull);
    expect(pet.originDate, isNull);
    expect(pet.originNotes, isNull);
    expect(pet.motherInfo, isNull);
    expect(pet.fatherInfo, isNull);
    expect(pet.dietType, isNull);
    expect(pet.foodBrand, isNull);
    expect(pet.feedingNotes, isNull);
  });

  test('the new tables exist and start empty', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((row) => row.read<String>('name'));
    expect(tables, containsAll(['pet_conditions', 'pet_allergies']));
    expect(await db.select(db.petConditions).get(), isEmpty);
    expect(await db.select(db.petAllergies).get(), isEmpty);
  });

  test('the new pet fields can be written after the upgrade', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    await (db.update(db.pets)..where((p) => p.id.equals('pet-1'))).write(
      PetsCompanion.insert(
        id: 'pet-1',
        name: 'Mochi',
        sex: PetSex.female,
        createdAt: DateTime.utc(2026, 3, 15, 9),
        updatedAt: DateTime.utc(2026, 3, 15, 9),
        coatLength: const Value(CoatLength.long),
        origin: const Value(PetOrigin.rescued),
        originDate: Value(DateTime.utc(2024, 7, 1)),
        originNotes: const Value('Found behind the bins'),
        motherInfo: const Value('Unknown'),
        fatherInfo: const Value('Unknown'),
        dietType: const Value(DietType.mixed),
        foodBrand: const Value('Royal Canin'),
        feedingNotes: const Value('Two small meals, no chicken'),
      ),
    );

    final pet = (await db.select(db.pets).get()).single;
    expect(pet.coatLength, CoatLength.long);
    expect(pet.origin, PetOrigin.rescued);
    expect(pet.originDate, DateTime.utc(2024, 7, 1));
    expect(pet.dietType, DietType.mixed);
    expect(pet.foodBrand, 'Royal Canin');
    expect(pet.feedingNotes, 'Two small meals, no chicken');
  });

  test('a condition and an allergy can be written after the upgrade', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    await db
        .into(db.petConditions)
        .insert(
          PetConditionRow(
            id: 'cond-1',
            petId: 'pet-1',
            name: 'CKD',
            status: ConditionStatus.ongoing,
            date: DateTime.utc(2026, 1, 10),
            notes: 'Stage 2, bloods every six months',
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );
    await db
        .into(db.petAllergies)
        .insert(
          PetAllergyRow(
            id: 'allergy-1',
            petId: 'pet-1',
            allergen: 'Chicken',
            reaction: 'Itching round the ears',
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    final condition = (await db.select(db.petConditions).get()).single;
    expect(condition.name, 'CKD');
    expect(condition.status, ConditionStatus.ongoing);
    expect(condition.date, DateTime.utc(2026, 1, 10));

    final allergy = (await db.select(db.petAllergies).get()).single;
    expect(allergy.allergen, 'Chicken');
    expect(allergy.reaction, 'Itching round the ears');
  });

  test('deleting the pet takes their conditions and allergies', () async {
    final db = AppDatabase.forTesting(v4WithData());
    addTearDown(db.close);

    await db
        .into(db.petConditions)
        .insert(
          PetConditionRow(
            id: 'cond-1',
            petId: 'pet-1',
            name: 'CKD',
            status: ConditionStatus.ongoing,
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );
    await db
        .into(db.petAllergies)
        .insert(
          PetAllergyRow(
            id: 'allergy-1',
            petId: 'pet-1',
            allergen: 'Chicken',
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    await (db.delete(db.pets)..where((p) => p.id.equals('pet-1'))).go();

    expect(await db.select(db.petConditions).get(), isEmpty);
    expect(await db.select(db.petAllergies).get(), isEmpty);
  });
}
