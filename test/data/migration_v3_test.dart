import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/domain/models/pet.dart';

import '../helpers/harness.dart';

/// The v2 schema, exactly as drift emitted it before prescriptions existed.
///
/// Written out rather than generated so the test fails loudly if a v2 table
/// is ever changed in place instead of migrated.
const List<String> _v2Schema = [
  'CREATE TABLE "pets" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"photo_path" TEXT NULL, "birthday" TEXT NULL, "breed" TEXT NULL, '
      '"sex" TEXT NOT NULL, "neutered" INTEGER NULL CHECK ("neutered" IN '
      '(0, 1)), "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"archived_at" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "reminders" ("id" TEXT NOT NULL, "pet_id" TEXT NOT '
      'NULL REFERENCES pets (id) ON DELETE CASCADE, "title" TEXT NOT '
      'NULL, "category" TEXT NOT NULL, "repeat_unit" TEXT NOT NULL, '
      '"repeat_interval" INTEGER NOT NULL DEFAULT 1, "anchor_date" TEXT '
      'NOT NULL, "time_of_day_minutes" INTEGER NOT NULL, "next_due_at" '
      'TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK '
      '("is_active" IN (0, 1)), "notes" TEXT NULL, "created_at" TEXT NOT '
      'NULL, "updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "reminder_events" ("id" TEXT NOT NULL, "reminder_id" '
      'TEXT NOT NULL REFERENCES reminders (id) ON DELETE CASCADE, '
      '"scheduled_for" TEXT NOT NULL, "status" TEXT NOT NULL, '
      '"completed_at" TEXT NULL, "snoozed_until" TEXT NULL, "notes" TEXT '
      'NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "medicines" ("id" TEXT NOT NULL, "pet_id" TEXT NOT '
      'NULL REFERENCES pets (id) ON DELETE CASCADE, "name" TEXT NOT NULL, '
      '"dosage" TEXT NULL, "times_of_day_minutes" TEXT NOT NULL, '
      '"interval_days" INTEGER NOT NULL DEFAULT 1, "start_date" TEXT NOT '
      'NULL, "end_date" TEXT NULL, "notes" TEXT NULL, "is_active" INTEGER '
      'NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "created_at" '
      'TEXT NOT NULL, "updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "dose_logs" ("id" TEXT NOT NULL, "medicine_id" TEXT '
      'NOT NULL REFERENCES medicines (id) ON DELETE CASCADE, '
      '"scheduled_for" TEXT NOT NULL, "status" TEXT NOT NULL, "taken_at" '
      'TEXT NULL, "notes" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "vet_visits" ("id" TEXT NOT NULL, "pet_id" TEXT NOT '
      'NULL REFERENCES pets (id) ON DELETE CASCADE, "visited_on" TEXT NOT '
      'NULL, "reason" TEXT NOT NULL, "clinic" TEXT NULL, "vet_name" TEXT '
      'NULL, "notes" TEXT NULL, "created_at" TEXT NOT NULL, "updated_at" '
      'TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "visit_attachments" ("id" TEXT NOT NULL, "visit_id" '
      'TEXT NOT NULL REFERENCES vet_visits (id) ON DELETE CASCADE, '
      '"file_path" TEXT NOT NULL, "caption" TEXT NULL, "added_at" TEXT '
      'NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "vaccination_records" ("id" TEXT NOT NULL, "pet_id" '
      'TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "name" TEXT '
      'NOT NULL, "administered_on" TEXT NOT NULL, "next_due_on" TEXT '
      'NULL, "source_event_id" TEXT NULL, "notes" TEXT NULL, "created_at" '
      'TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "weight_entries" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "measured_on" '
      'TEXT NOT NULL, "grams" INTEGER NOT NULL, "note" TEXT NULL, '
      '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT '
      'NULL, PRIMARY KEY ("key"))',
];

void main() {
  setUpAll(initializeTestTimeZone);

  /// An executor holding a populated v2 database.
  QueryExecutor v2WithData() => NativeDatabase.memory(
    setup: (raw) {
      for (final statement in _v2Schema) {
        raw.execute(statement);
      }
      raw
        ..execute('PRAGMA user_version = 2')
        ..execute(
          'INSERT INTO pets (id, name, sex, created_at, updated_at) '
          "VALUES ('pet-1', 'Mochi', 'female', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        )
        ..execute(
          'INSERT INTO medicines (id, pet_id, name, dosage, '
          'times_of_day_minutes, interval_days, start_date, created_at, '
          "updated_at) VALUES ('med-1', 'pet-1', 'Amoxicillin', '1 tablet', "
          "'480,1200', 1, '2026-03-15T00:00:00.000Z', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        )
        ..execute(
          'INSERT INTO vet_visits (id, pet_id, visited_on, reason, '
          "created_at, updated_at) VALUES ('visit-1', 'pet-1', "
          "'2026-03-10T00:00:00.000Z', 'Limping', "
          "'2026-03-10T09:00:00.000Z', '2026-03-10T09:00:00.000Z')",
        );
    },
  );

  test('a v2 database upgrades to v3 with its data intact', () async {
    final db = AppDatabase.forTesting(v2WithData());
    addTearDown(db.close);

    expect((await db.select(db.pets).get()).single.name, 'Mochi');

    final medicine = (await db.select(db.medicines).get()).single;
    expect(medicine.name, 'Amoxicillin');
    expect(medicine.timesOfDayMinutes, [480, 1200]);
    expect(
      medicine.prescriptionId,
      isNull,
      reason: 'a medicine that predates prescriptions has none',
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 3);
  });

  test('the prescriptions table exists after the upgrade', () async {
    final db = AppDatabase.forTesting(v2WithData());
    addTearDown(db.close);

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();

    expect(
      rows.map((row) => row.read<String>('name')),
      contains('prescriptions'),
    );
    expect(await db.select(db.prescriptions).get(), isEmpty);
  });

  test('a prescription can be written and linked to a medicine', () async {
    final db = AppDatabase.forTesting(v2WithData());
    addTearDown(db.close);

    await db.into(db.prescriptions).insert(
      PrescriptionRow(
        id: 'rx-1',
        petId: 'pet-1',
        vetVisitId: 'visit-1',
        date: DateTime.utc(2026, 3, 15),
        vetName: 'Dr Okafor',
        clinic: 'Riverside Vets',
        imagePaths: const ['/docs/rx/page-1.jpg', '/docs/rx/page-2.jpg'],
        extractedText: 'Amoxicillin 50mg twice daily for 7 days',
        createdAt: DateTime.utc(2026, 3, 15, 9),
      ),
    );
    await (db.update(db.medicines)..where((m) => m.id.equals('med-1')))
        .write(const MedicinesCompanion(prescriptionId: Value('rx-1')));

    final saved = (await db.select(db.prescriptions).get()).single;
    expect(saved.imagePaths, [
      '/docs/rx/page-1.jpg',
      '/docs/rx/page-2.jpg',
    ], reason: 'page order is data, not incidental');
    expect(saved.extractedText, contains('twice daily'));
    expect((await db.select(db.medicines).get()).single.prescriptionId, 'rx-1');
  });

  test('deleting a prescription keeps the medicine it produced', () async {
    // The owner is still giving their cat the medicine. Losing it because a
    // scan was tidied away would be the app destroying their schedule.
    final db = AppDatabase.forTesting(v2WithData());
    addTearDown(db.close);

    await db.into(db.prescriptions).insert(
      PrescriptionRow(
        id: 'rx-1',
        petId: 'pet-1',
        date: DateTime.utc(2026, 3, 15),
        imagePaths: const ['/docs/rx/page-1.jpg'],
        createdAt: DateTime.utc(2026, 3, 15, 9),
      ),
    );
    await (db.update(db.medicines)..where((m) => m.id.equals('med-1')))
        .write(const MedicinesCompanion(prescriptionId: Value('rx-1')));

    await (db.delete(db.prescriptions)..where((p) => p.id.equals('rx-1'))).go();

    final medicine = (await db.select(db.medicines).get()).single;
    expect(medicine.name, 'Amoxicillin');
    expect(medicine.prescriptionId, isNull);
  });

  test('deleting the pet does take its prescriptions', () async {
    final db = AppDatabase.forTesting(v2WithData());
    addTearDown(db.close);

    await db.into(db.prescriptions).insert(
      PrescriptionRow(
        id: 'rx-1',
        petId: 'pet-1',
        date: DateTime.utc(2026, 3, 15),
        imagePaths: const ['/docs/rx/page-1.jpg'],
        createdAt: DateTime.utc(2026, 3, 15, 9),
      ),
    );

    await (db.delete(db.pets)..where((p) => p.id.equals('pet-1'))).go();

    expect(await db.select(db.prescriptions).get(), isEmpty);
  });

  test('a fresh database is created at v3 directly', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 3);
  });

  test('an empty page list round-trips as empty, not as null', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.pets).insert(
      PetRow(
        id: 'p',
        name: 'Mochi',
        sex: PetSex.unknown,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    await db.into(db.prescriptions).insert(
      PrescriptionRow(
        id: 'rx',
        petId: 'p',
        date: DateTime.utc(2026),
        imagePaths: const [],
        createdAt: DateTime.utc(2026),
      ),
    );

    expect((await db.select(db.prescriptions).get()).single.imagePaths, isEmpty);
  });
}
