import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants.dart';
// The generated part file resolves the textEnum column types through this
// library's imports, so the domain enums have to be in scope here.
import '../../domain/models/pet.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_event.dart';
import '../../domain/repeat_rule.dart';
import 'tables/pets.dart';
import 'tables/reminder_events.dart';
import 'tables/reminders.dart';

part 'app_database.g.dart';

/// The app's single sqlite database.
///
/// Only repositories talk to this; see the rules in CLAUDE.md.
@DriftDatabase(tables: [Pets, Reminders, ReminderEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: AppConstants.databaseName));

  /// For tests: an isolated in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // The cascades on reminders and events are only honoured with foreign
      // keys switched on, and sqlite defaults them off per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
