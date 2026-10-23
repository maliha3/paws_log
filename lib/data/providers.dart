import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/medicine.dart';
import '../domain/models/pet.dart';
import '../domain/models/vaccination_record.dart';
import '../domain/models/vet_visit.dart';
import '../services/backup/backup_service.dart';
import '../services/backup/backup_sharing.dart';
import '../core/purchase_config.dart';
import '../services/entitlements/entitlement_service.dart';
import '../services/entitlements/entitlement_source.dart';
import '../services/entitlements/revenuecat_entitlements.dart';
import '../services/entitlements/stub_entitlements.dart';
import '../services/photo_store.dart';
import '../services/vet_summary/vet_summary_service.dart';
import '../services/vet_summary/vet_summary_sharing.dart';
import '../domain/models/weight_entry.dart';
import '../domain/schedule_sync.dart';
import 'db/app_database.dart';
import 'repositories/dose_log_repository.dart';
import 'repositories/medicine_repository.dart';
import 'repositories/pet_repository.dart';
import 'repositories/reminder_event_repository.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/vaccination_repository.dart';
import 'repositories/vet_visit_repository.dart';
import 'repositories/weight_repository.dart';

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

final medicineRepositoryProvider = Provider<MedicineRepository>(
  (ref) => MedicineRepository(
    ref.watch(appDatabaseProvider),
    scheduleSync: ref.watch(scheduleSyncProvider),
  ),
);

final doseLogRepositoryProvider = Provider<DoseLogRepository>(
  (ref) => DoseLogRepository(
    ref.watch(appDatabaseProvider),
    scheduleSync: ref.watch(scheduleSyncProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Where the entitlement comes from.
///
/// RevenueCat when the build has a key, and a local stub otherwise — so
/// development, CI and the tests work without credentials, and a missing key
/// can never look like a working store.
final entitlementSourceProvider = Provider<EntitlementSource>((ref) {
  if (!PurchaseConfig.hasStoreKeys) {
    return StubEntitlements(ref.watch(settingsRepositoryProvider));
  }
  return RevenueCatEntitlements();
});

final entitlementServiceProvider = Provider<EntitlementService>(
  (ref) => EntitlementService(
    source: ref.watch(entitlementSourceProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

/// Whether the paid features are unlocked, as it changes.
final isPremiumProvider = StreamProvider<bool>(
  (ref) => ref.watch(entitlementServiceProvider).watchActive(),
);

/// The plans the store is offering. Empty when nothing is configured.
final premiumPlansProvider = FutureProvider<List<PremiumPlan>>(
  (ref) => ref.watch(entitlementServiceProvider).plans(),
);

/// The unit weights are shown in. Storage is always grams.
final weightUnitProvider = StreamProvider<WeightUnit>(
  (ref) => ref.watch(settingsRepositoryProvider).watchWeightUnit(),
);

/// Active pets, live.
final petsProvider = StreamProvider<List<Pet>>(
  (ref) => ref.watch(petRepositoryProvider).watchPets(),
);

final vaccinationRepositoryProvider = Provider<VaccinationRepository>(
  (ref) => VaccinationRepository(ref.watch(appDatabaseProvider)),
);

/// One pet's vaccination history, live.
final vaccinationsForPetProvider =
    StreamProvider.family<List<VaccinationRecord>, String>(
      (ref, petId) =>
          ref.watch(vaccinationRepositoryProvider).watchForPet(petId),
    );

final weightRepositoryProvider = Provider<WeightRepository>(
  (ref) => WeightRepository(ref.watch(appDatabaseProvider)),
);

/// One pet's weighings, oldest first.
final weightsForPetProvider =
    StreamProvider.family<List<WeightEntry>, String>(
      (ref, petId) => ref.watch(weightRepositoryProvider).watchForPet(petId),
    );

final vetVisitRepositoryProvider = Provider<VetVisitRepository>(
  (ref) => VetVisitRepository(
    ref.watch(appDatabaseProvider),
    photoStore: ref.watch(photoStoreProvider),
  ),
);

/// One pet's visits, live.
final visitsForPetProvider = StreamProvider.family<List<VetVisit>, String>(
  (ref, petId) => ref.watch(vetVisitRepositoryProvider).watchForPet(petId),
);

/// One visit's attachments, live.
final attachmentsForVisitProvider =
    StreamProvider.family<List<VisitAttachment>, String>(
      (ref, visitId) =>
          ref.watch(vetVisitRepositoryProvider).watchAttachments(visitId),
    );

/// One pet's medicines, live.
final medicinesForPetProvider =
    StreamProvider.family<List<Medicine>, String>(
      (ref, petId) =>
          ref.watch(medicineRepositoryProvider).watchForPet(petId),
    );

/// Whether onboarding is still needed.
///
/// Having a pet *is* the completion flag — there is nothing to show on Today
/// without one, so no separate stored flag can drift out of step with it.
final needsOnboardingProvider = Provider<bool?>((ref) {
  final pets = ref.watch(petsProvider);
  return pets.hasValue ? pets.requireValue.isEmpty : null;
});


/// Where photo files live, resolved once.
final photosRootProvider = FutureProvider<Directory>(
  (ref) => getApplicationDocumentsDirectory(),
);

final backupServiceProvider = Provider<BackupService>((ref) {
  // The documents directory is resolved asynchronously, but every backup
  // action is user-initiated and the directory is read by then.
  final root = ref.watch(photosRootProvider).value;
  return BackupService(
    ref.watch(appDatabaseProvider),
    photosRoot: root ?? Directory.current,
  );
});

final backupSharingProvider = Provider<BackupSharing>(
  (ref) => BackupSharing(ref.watch(backupServiceProvider)),
);


final vetSummaryServiceProvider = Provider<VetSummaryService>(
  (ref) => VetSummaryService(
    vaccinations: ref.watch(vaccinationRepositoryProvider),
    medicines: ref.watch(medicineRepositoryProvider),
    weights: ref.watch(weightRepositoryProvider),
    visits: ref.watch(vetVisitRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

final vetSummarySharingProvider = Provider<VetSummarySharing>(
  (ref) => VetSummarySharing(ref.watch(vetSummaryServiceProvider)),
);
