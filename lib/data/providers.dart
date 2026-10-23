import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/pet.dart';
import '../domain/models/weight_entry.dart';
import '../domain/schedule_sync.dart';
import 'db/app_database.dart';
import 'repositories/pet_repository.dart';
import 'repositories/reminder_event_repository.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/settings_repository.dart';

/// The database, opened once for the app's lifetime.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Resyncs scheduled notifications after a write.
///
/// Overridden in `main.dart` with the real scheduler; the no-op keeps tests
/// and widget previews from needing the plugin.
final scheduleSyncProvider = Provider<ScheduleSync>(
  (ref) => const NoopScheduleSync(),
);

final petRepositoryProvider = Provider<PetRepository>(
  (ref) => PetRepository(ref.watch(appDatabaseProvider)),
);

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(
    ref.watch(appDatabaseProvider),
    scheduleSync: ref.watch(scheduleSyncProvider),
  ),
);

final reminderEventRepositoryProvider = Provider<ReminderEventRepository>(
  (ref) => ReminderEventRepository(
    ref.watch(appDatabaseProvider),
    scheduleSync: ref.watch(scheduleSyncProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// The unit weights are shown in. Storage is always grams.
final weightUnitProvider = StreamProvider<WeightUnit>(
  (ref) => ref.watch(settingsRepositoryProvider).watchWeightUnit(),
);

/// Active pets, live.
final petsProvider = StreamProvider<List<Pet>>(
  (ref) => ref.watch(petRepositoryProvider).watchPets(),
);

/// Whether onboarding is still needed.
///
/// Having a pet *is* the completion flag — there is nothing to show on Today
/// without one, so no separate stored flag can drift out of step with it.
final needsOnboardingProvider = Provider<bool?>((ref) {
  final pets = ref.watch(petsProvider);
  return pets.hasValue ? pets.requireValue.isEmpty : null;
});
