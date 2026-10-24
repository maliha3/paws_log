import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';

import '../helpers/harness.dart';

/// The v3 schema, exactly as drift emitted it before the photo vault.
///
/// Written out rather than generated so the test fails loudly if a v3 table
/// is ever changed in place instead of migrated.
const List<String> _v3Schema = [
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

  /// An executor holding a populated v3 database.
  QueryExecutor v3WithData() => NativeDatabase.memory(
    setup: (raw) {
      for (final statement in _v3Schema) {
        raw.execute(statement);
      }
      raw
        ..execute('PRAGMA user_version = 3')
        ..execute(
          'INSERT INTO pets (id, name, sex, photo_path, created_at, '
          "updated_at) VALUES ('pet-1', 'Mochi', 'female', "
          "'/docs/pet_photos/mochi.jpg', '2026-03-15T09:00:00.000Z', "
          "'2026-03-15T09:00:00.000Z')",
        )
        ..execute(
          'INSERT INTO prescriptions (id, pet_id, date, image_paths, '
          "created_at) VALUES ('rx-1', 'pet-1', '2026-03-15T00:00:00.000Z', "
          '\'["/docs/rx/page-1.jpg"]\', \'2026-03-15T09:00:00.000Z\')',
        );
    },
  );

  test('a v3 database upgrades to v4 with its data intact', () async {
    final db = AppDatabase.forTesting(v3WithData());
    addTearDown(db.close);

    final pet = (await db.select(db.pets).get()).single;
    expect(pet.name, 'Mochi');
    expect(pet.photoPath, '/docs/pet_photos/mochi.jpg');
    expect((await db.select(db.prescriptions).get()).single.id, 'rx-1');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });

  test(
    'every pet that predates the vault starts with an empty album',
    () async {
      final db = AppDatabase.forTesting(v3WithData());
      addTearDown(db.close);

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        contains('pet_photos'),
      );
      expect(await db.select(db.petPhotos).get(), isEmpty);
    },
  );

  test('a photo can be written and read back after the upgrade', () async {
    final db = AppDatabase.forTesting(v3WithData());
    addTearDown(db.close);

    await db
        .into(db.petPhotos)
        .insert(
          PetPhotoRow(
            id: 'photo-1',
            petId: 'pet-1',
            path: '/docs/pet_vault/one.jpg',
            takenAt: DateTime.utc(2026, 3, 1, 14, 30),
            caption: 'Asleep in the sink',
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    final saved = (await db.select(db.petPhotos).get()).single;
    expect(saved.path, '/docs/pet_vault/one.jpg');
    expect(saved.caption, 'Asleep in the sink');
    expect(saved.takenAt, DateTime.utc(2026, 3, 1, 14, 30));
    expect(saved.takenAt.isUtc, isTrue);
  });

  test('a photo with no caption is allowed', () async {
    final db = AppDatabase.forTesting(v3WithData());
    addTearDown(db.close);

    await db
        .into(db.petPhotos)
        .insert(
          PetPhotosCompanion.insert(
            id: 'photo-1',
            petId: 'pet-1',
            path: '/docs/pet_vault/one.jpg',
            takenAt: DateTime.utc(2026, 3, 1),
            createdAt: DateTime.utc(2026, 3, 15, 9),
            caption: const Value(null),
          ),
        );

    expect((await db.select(db.petPhotos).get()).single.caption, isNull);
  });

  test('deleting the pet takes their album with it', () async {
    final db = AppDatabase.forTesting(v3WithData());
    addTearDown(db.close);

    await db
        .into(db.petPhotos)
        .insert(
          PetPhotoRow(
            id: 'photo-1',
            petId: 'pet-1',
            path: '/docs/pet_vault/one.jpg',
            takenAt: DateTime.utc(2026, 3, 1),
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    await (db.delete(db.pets)..where((p) => p.id.equals('pet-1'))).go();

    expect(await db.select(db.petPhotos).get(), isEmpty);
  });
}
