import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants.dart';
// The generated part file resolves the textEnum column types through this
// library's imports, so the domain enums have to be in scope here.
import '../../domain/models/pet.dart';
import '../../domain/models/pet_condition.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_event.dart';
import '../../domain/models/dose_log.dart';
import '../../domain/repeat_rule.dart';
import 'converters/minutes_list_converter.dart';
import 'converters/string_list_converter.dart';
import 'tables/app_settings.dart';
import 'tables/dose_logs.dart';
import 'tables/medicines.dart';
import 'tables/pet_conditions.dart';
import 'tables/pet_photos.dart';
import 'tables/pets.dart';
import 'tables/prescriptions.dart';
import 'tables/vaccination_records.dart';
import 'tables/vet_visits.dart';
import 'tables/weight_entries.dart';
import 'tables/reminder_events.dart';
import 'tables/reminders.dart';

part 'app_database.g.dart';

/// The app's single sqlite database.
///
/// Only repositories talk to this; see the rules in CLAUDE.md.
@DriftDatabase(
  tables: [
    Pets,
    Reminders,
    ReminderEvents,
    Medicines,
    DoseLogs,
    VetVisits,
    VisitAttachments,
    VaccinationRecords,
    WeightEntries,
    AppSettings,
    Prescriptions,
    PetPhotos,
    PetConditions,
    PetAllergies,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: AppConstants.databaseName));

  /// For tests: an isolated in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Phase 2: medicines, the health log, vaccination history, weights
        // and settings. All additive — nothing in v1 changes shape, so
        // existing pets, reminders and their history carry straight over.
        await m.createTable(medicines);
        await m.createTable(doseLogs);
        await m.createTable(vetVisits);
        await m.createTable(visitAttachments);
        await m.createTable(vaccinationRecords);
        await m.createTable(weightEntries);
        await m.createTable(appSettings);
      }
      if (from < 3) {
        // Phase 5: prescriptions, and the link from a medicine back to the
        // one it came from.
        await m.createTable(prescriptions);

        // Only when `medicines` already existed. `createTable` builds from
        // *today's* definition, not the historical one, so a database coming
        // from v1 had the column created with the table in the step above —
        // and adding it again is an error, not a no-op.
        if (from >= 2) {
          await m.addColumn(medicines, medicines.prescriptionId);
        }
      }
      if (from < 4) {
        // The photo vault. Additive: a new table and nothing else, so every
        // existing pet simply starts with an empty album.
        await m.createTable(petPhotos);
      }
      if (from < 5) {
        // Profile details: diagnosed conditions, allergies, and the
        // background and feeding fields on the pet itself. Every new pet
        // column is nullable, so an existing pet reads as "not recorded"
        // rather than as a guess.
        await m.createTable(petConditions);
        await m.createTable(petAllergies);
        await m.addColumn(pets, pets.coatLength);
        await m.addColumn(pets, pets.origin);
        await m.addColumn(pets, pets.originDate);
        await m.addColumn(pets, pets.originNotes);
        await m.addColumn(pets, pets.motherInfo);
        await m.addColumn(pets, pets.fatherInfo);
        await m.addColumn(pets, pets.dietType);
        await m.addColumn(pets, pets.foodBrand);
        await m.addColumn(pets, pets.feedingNotes);
      }
    },
    beforeOpen: (details) async {
      // The cascades on reminders and events are only honoured with foreign
      // keys switched on, and sqlite defaults them off per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
