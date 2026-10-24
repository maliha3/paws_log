import 'package:drift/drift.dart' show QueryExecutor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';

import '../helpers/harness.dart';

/// The v5 schema, exactly as drift emitted it before grooming.
///
/// Written out rather than generated so the test fails loudly if a v5 table
/// is ever changed in place instead of migrated.
const List<String> _v5Schema = [
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
  'CREATE TABLE "pet_allergies" ("id" TEXT NOT NULL, "pet_id" '
      'TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, '
      '"allergen" TEXT NOT NULL, "reaction" TEXT NULL, "notes" TEXT '
      'NULL, "created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pet_conditions" ("id" TEXT NOT NULL, "pet_id" '
      'TEXT NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "name" '
      'TEXT NOT NULL, "status" TEXT NOT NULL, "date" TEXT NULL, '
      '"notes" TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY KEY '
      '("id"))',
  'CREATE TABLE "pet_photos" ("id" TEXT NOT NULL, "pet_id" TEXT '
      'NOT NULL REFERENCES pets (id) ON DELETE CASCADE, "path" TEXT '
      'NOT NULL, "taken_at" TEXT NOT NULL, "caption" TEXT NULL, '
      '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pets" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"photo_path" TEXT NULL, "birthday" TEXT NULL, "breed" TEXT '
      'NULL, "sex" TEXT NOT NULL, "neutered" INTEGER NULL CHECK '
      '("neutered" IN (0, 1)), "coat_length" TEXT NULL, "origin" TEXT '
      'NULL, "origin_date" TEXT NULL, "origin_notes" TEXT NULL, '
      '"mother_info" TEXT NULL, "father_info" TEXT NULL, "diet_type" '
      'TEXT NULL, "food_brand" TEXT NULL, "feeding_notes" TEXT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"archived_at" TEXT NULL, PRIMARY KEY ("id"))',
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

  /// An executor holding a populated v5 database.
  QueryExecutor v5WithData() => NativeDatabase.memory(
    setup: (raw) {
      for (final statement in _v5Schema) {
        raw.execute(statement);
      }
      raw
        ..execute('PRAGMA user_version = 5')
        ..execute(
          'INSERT INTO pets (id, name, sex, created_at, updated_at) '
          "VALUES ('pet-1', 'Mochi', 'female', "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        )
        ..execute(
          'INSERT INTO reminders (id, pet_id, title, category, repeat_unit, '
          'repeat_interval, anchor_date, time_of_day_minutes, created_at, '
          "updated_at) VALUES ('rem-1', 'pet-1', 'Yearly vaccine', "
          "'vaccine', 'years', 1, '2026-03-15T00:00:00.000Z', 540, "
          "'2026-03-15T09:00:00.000Z', '2026-03-15T09:00:00.000Z')",
        );
    },
  );

  test('a v5 database upgrades to v6 with its data intact', () async {
    final db = AppDatabase.forTesting(v5WithData());
    addTearDown(db.close);

    final reminder = (await db.select(db.reminders).get()).single;
    expect(reminder.title, 'Yearly vaccine');
    expect(reminder.category, ReminderCategory.vaccine);
    expect(reminder.repeatUnit, RepeatUnit.years);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });

  test('a reminder that predates grooming is not seasonal', () async {
    final db = AppDatabase.forTesting(v5WithData());
    addTearDown(db.close);

    expect(
      (await db.select(db.reminders).get()).single.seasonal,
      isFalse,
      reason: 'the default must not quietly double anyone\u2019s schedule',
    );
  });

  test('the new categories can be written after the upgrade', () async {
    final db = AppDatabase.forTesting(v5WithData());
    addTearDown(db.close);

    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: 'rem-2',
            petId: 'pet-1',
            title: 'Brushing',
            category: ReminderCategory.brushing,
            repeatUnit: RepeatUnit.days,
            repeatInterval: const Value(2),
            anchorDate: DateTime.utc(2026, 3, 15),
            timeOfDayMinutes: 540,
            seasonal: const Value(true),
            createdAt: DateTime.utc(2026, 3, 15, 9),
            updatedAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: 'rem-3',
            petId: 'pet-1',
            title: 'Nail trim',
            category: ReminderCategory.nailTrim,
            repeatUnit: RepeatUnit.weeks,
            repeatInterval: const Value(3),
            anchorDate: DateTime.utc(2026, 3, 15),
            timeOfDayMinutes: 540,
            createdAt: DateTime.utc(2026, 3, 15, 9),
            updatedAt: DateTime.utc(2026, 3, 15, 9),
          ),
        );

    final brushing = await (db.select(
      db.reminders,
    )..where((r) => r.id.equals('rem-2'))).getSingle();
    expect(brushing.category, ReminderCategory.brushing);
    expect(brushing.seasonal, isTrue);

    final nails = await (db.select(
      db.reminders,
    )..where((r) => r.id.equals('rem-3'))).getSingle();
    expect(nails.category, ReminderCategory.nailTrim);
    expect(nails.seasonal, isFalse, reason: 'nails do not shed');
  });

  test('a fresh database starts at the current schema', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });
}
