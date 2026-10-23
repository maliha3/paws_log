import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medicine_repository.dart';
import '../domain/schedule_sync.dart';

/// Work that has to happen on launch and on every resume.
///
/// All three steps depend on how much time has passed since the app was last
/// open, which is exactly what it cannot observe while closed. Order matters:
/// doses are marked missed before new ones are generated, and the
/// notification window is rebuilt last so it reflects both.
Future<void> runMaintenanceWith({
  required DoseLogRepository doses,
  required MedicineRepository medicines,
  required ScheduleSync scheduleSync,
  DateTime? now,
}) async {
  await doses.markOverdueMissed(now: now);
  await medicines.topUpDoses(now: now);
  await scheduleSync.syncAll();
}

/// From `main`, which holds a container rather than a ref.
Future<void> runMaintenance(ProviderContainer container, {DateTime? now}) =>
    runMaintenanceWith(
      doses: container.read(doseLogRepositoryProvider),
      medicines: container.read(medicineRepositoryProvider),
      scheduleSync: container.read(scheduleSyncProvider),
      now: now,
    );

/// From inside a widget. `WidgetRef` and `Ref` are separate types in
/// Riverpod 3, which is why this is not one function.
Future<void> runMaintenanceForWidget(WidgetRef ref, {DateTime? now}) =>
    runMaintenanceWith(
      doses: ref.read(doseLogRepositoryProvider),
      medicines: ref.read(medicineRepositoryProvider),
      scheduleSync: ref.read(scheduleSyncProvider),
      now: now,
    );
