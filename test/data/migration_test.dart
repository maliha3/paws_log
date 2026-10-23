import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/domain/models/weight_entry.dart';

import '../helpers/harness.dart';

/// The v1 schema, exactly as drift emitted it before Phase 2.
///
/// Written out rather than generated so the test fails loudly if a v1 table
/// is ever changed in place instead of migrated.
const List<String> _v1Schema = [
  'CREATE TABLE "pets" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"photo_path" TEXT NULL, "birthday" TEXT NULL, "breed" TEXT NULL, '
      '"sex" TEXT NOT NULL, "neutered" INTEGER NULL '
      'CHECK ("neutered" IN (0, 1)), "created_at" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, "archived_at" TEXT NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE TABLE "reminders" ("id" TEXT NOT NULL, "pet_id" TEXT NOT NULL '
      'REFERENCES pets (id) ON DELETE CASCADE, "title" TEXT NOT NULL, '
      '"category" TEXT NOT NULL, "repeat_unit" TEXT NOT NULL, '
      '"repeat_interval" INTEGER NOT NULL DEFAULT 1, '
      '"anchor_date" TEXT NOT NULL, "time_of_day_minutes" INTEGER NOT NULL, '
      '"next_due_at" TEXT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 '
      'CHECK ("is_active" IN (0, 1)), "notes" TEXT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE TABLE "reminder_events" ("id" TEXT NOT NULL, '
      '"reminder_id" TEXT NOT NULL REFERENCES reminders (id) ON DELETE '
      'CASCADE, "scheduled_for" TEXT NOT NULL, "status" TEXT NOT NULL, '
      '"completed_at" TEXT NULL, "snoozed_until" TEXT NULL, '
      '"notes" TEXT NULL, PRIMARY KEY ("id"))',
];

void main() {
  setUpAll(initializeTestTimeZone);

  /// An executor holding a populated v1 database.
  QueryExecutor v1WithData() {
    final database = NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v1Schema) {
          raw.execute(statement);
        }
        raw.execute('PRAGMA user_version = 1');
        raw.execute(
          'INSERT INTO pets (id, name, breed, sex, created_at, updated_at) '
          "VALUES ('pet-1', 'Mochi', 'Ragdoll', 'female', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        );
        raw.execute(
          'INSERT INTO reminders (id, pet_id, title, category, repeat_unit, '
          'repeat_interval, anchor_date, time_of_day_minutes, next_due_at, '
          'created_at, updated_at) VALUES '
          "('rem-1', 'pet-1', 'Deworming', 'deworming', 'months', 3, "
          "'2026-03-15T00:00:00.000Z', 540, '2026-03-15T09:00:00.000Z', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        );
        raw.execute(
          'INSERT INTO reminder_events (id, reminder_id, scheduled_for, '
          "status) VALUES ('evt-1', 'rem-1', '2026-03-15T09:00:00.000Z', "
          "'pending')",
        );
      },
    );
    return database;
  }

  test('a v1 database upgrades to v2 with its data intact', () async {
    final db = AppDatabase.forTesting(v1WithData());
    addTearDown(db.close);

    // Opening runs the migration.
    final pets = await db.select(db.pets).get();

    expect(pets, hasLength(1));
    expect(pets.single.name, 'Mochi');
    expect(pets.single.breed, 'Ragdoll');
    expect(await db.select(db.reminders).get(), hasLength(1));

    final events = await db.select(db.reminderEvents).get();
    expect(events, hasLength(1));
    expect(
      events.single.scheduledFor,
      DateTime.utc(2026, 3, 15, 9),
      reason: 'timestamps survive as UTC',
    );

    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], 2);
  });

  test('every Phase 2 table exists after the upgrade', () async {
    final db = AppDatabase.forTesting(v1WithData());
    addTearDown(db.close);

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final tables = rows.map((row) => row.read<String>('name')).toSet();

    expect(
      tables,
      containsAll([
        'pets',
        'reminders',
        'reminder_events',
        'medicines',
        'dose_logs',
        'vet_visits',
        'visit_attachments',
        'vaccination_records',
        'weight_entries',
        'app_settings',
      ]),
    );
  });

  test('the upgraded database is writable through the new tables', () async {
    final db = AppDatabase.forTesting(v1WithData());
    addTearDown(db.close);

    await db
        .into(db.weightEntries)
        .insert(
          WeightEntryRow(
            id: 'w-1',
            petId: 'pet-1',
            measuredOn: DateTime.utc(2026, 3, 15),
            grams: 4200,
            createdAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    final entries = await db.select(db.weightEntries).get();
    expect(entries.single.grams, 4200);

    // And the foreign key to the migrated pet is live.
    await expectLater(
      db
          .into(db.weightEntries)
          .insert(
            WeightEntryRow(
              id: 'w-2',
              petId: 'no-such-pet',
              measuredOn: DateTime.utc(2026, 3, 15),
              grams: 100,
              createdAt: DateTime.utc(2026, 3, 15, 9),
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test('a fresh database is created at v2 directly', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 2);
    expect(await db.select(db.medicines).get(), isEmpty);
  });

  group('settings', () {
    test('the weight unit defaults to kilograms and round-trips', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);

      expect(await settings.weightUnit(), WeightUnit.kilograms);

      await settings.setWeightUnit(WeightUnit.pounds);
      expect(await settings.weightUnit(), WeightUnit.pounds);

      await settings.setWeightUnit(WeightUnit.kilograms);
      expect(await settings.weightUnit(), WeightUnit.kilograms);
    });

    test('an unreadable stored value falls back instead of throwing', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.appSettings)
          .insert(const AppSettingRow(key: 'weight_unit', value: 'stones'));

      expect(
        await SettingsRepository(db).weightUnit(),
        WeightUnit.kilograms,
      );
    });
  });
}
