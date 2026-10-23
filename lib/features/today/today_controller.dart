import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_x.dart';
import '../../data/providers.dart';
import '../../domain/models/due_dose.dart';
import '../../domain/models/due_item.dart';
import '../../domain/models/pet.dart';

/// One pet's day: care that is due, and the day's doses.
class PetDayGroup {
  const PetDayGroup({
    required this.pet,
    required this.overdue,
    required this.dueToday,
    required this.doses,
  });

  final Pet pet;

  /// Reminder occurrences from an earlier day, oldest first.
  final List<DueItem> overdue;

  /// Reminder occurrences due today.
  final List<DueItem> dueToday;

  /// Every dose of the day, including ones whose time has not come.
  final List<DueDose> doses;

  bool get isEmpty => overdue.isEmpty && dueToday.isEmpty && doses.isEmpty;

  /// Where this pet sorts: the earliest thing they have outstanding.
  DateTime get soonest => [
    ...overdue.map((item) => item.event.scheduledFor),
    ...dueToday.map((item) => item.event.scheduledFor),
    ...doses.map((dose) => dose.dose.scheduledFor),
  ].reduce((a, b) => a.isBefore(b) ? a : b);
}

final todayRemindersProvider = StreamProvider<List<DueItem>>(
  (ref) => ref.watch(reminderEventRepositoryProvider).watchDueAndOverdue(),
);

final todayDosesProvider = StreamProvider<List<DueDose>>(
  (ref) => ref.watch(doseLogRepositoryProvider).watchToday(),
);

/// Everything on today's plate, grouped by pet.
///
/// Combined here rather than in a stream combinator: Riverpod already tracks
/// both sources, and `AsyncValue` carries the loading and error states that a
/// hand-rolled combineLatest would have to reinvent.
final todayProvider = Provider<AsyncValue<List<PetDayGroup>>>((ref) {
  final reminders = ref.watch(todayRemindersProvider);
  final doses = ref.watch(todayDosesProvider);

  if (reminders.hasError) {
    return AsyncError(reminders.error!, reminders.stackTrace!);
  }
  if (doses.hasError) {
    return AsyncError(doses.error!, doses.stackTrace!);
  }
  if (!reminders.hasValue || !doses.hasValue) {
    return const AsyncLoading();
  }

  return AsyncData(
    groupByPet(
      reminders: reminders.requireValue,
      doses: doses.requireValue,
      startOfToday: dateOnly(DateTime.now()),
    ),
  );
});

/// Groups both sources by pet, most pressing pet first.
List<PetDayGroup> groupByPet({
  required List<DueItem> reminders,
  required List<DueDose> doses,
  required DateTime startOfToday,
}) {
  final pets = <String, Pet>{};
  final remindersByPet = <String, List<DueItem>>{};
  final dosesByPet = <String, List<DueDose>>{};

  for (final item in reminders) {
    pets[item.pet.id] = item.pet;
    remindersByPet.putIfAbsent(item.pet.id, () => []).add(item);
  }
  for (final dose in doses) {
    pets[dose.pet.id] = dose.pet;
    dosesByPet.putIfAbsent(dose.pet.id, () => []).add(dose);
  }

  final groups = [
    for (final entry in pets.entries)
      PetDayGroup(
        pet: entry.value,
        overdue: [
          for (final item in remindersByPet[entry.key] ?? const <DueItem>[])
            if (item.isOverdue(startOfToday)) item,
        ],
        dueToday: [
          for (final item in remindersByPet[entry.key] ?? const <DueItem>[])
            if (!item.isOverdue(startOfToday)) item,
        ],
        doses: dosesByPet[entry.key] ?? const [],
      ),
  ]..sort((a, b) => a.soonest.compareTo(b.soonest));

  return groups;
}
