import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/models/due_item.dart';
import '../../domain/models/pet.dart';

/// One pet's due items, as Today groups them.
class PetDueGroup {
  const PetDueGroup({required this.pet, required this.items});

  final Pet pet;
  final List<DueItem> items;

  /// Items that were due on an earlier day, oldest first.
  List<DueItem> overdue(DateTime startOfToday) =>
      items.where((item) => item.isOverdue(startOfToday)).toList();

  /// Items due today.
  List<DueItem> dueToday(DateTime startOfToday) =>
      items.where((item) => !item.isOverdue(startOfToday)).toList();
}

/// Everything due today or earlier, grouped by pet.
///
/// The repository already returns one ordered list across all pets; grouping
/// happens here so the screen stays a pure rendering of it.
final todayProvider = StreamProvider<List<PetDueGroup>>((ref) {
  final events = ref.watch(reminderEventRepositoryProvider);
  return events.watchDueAndOverdue().map(_groupByPet);
});

List<PetDueGroup> _groupByPet(List<DueItem> items) {
  final byPet = <String, List<DueItem>>{};
  final pets = <String, Pet>{};

  for (final item in items) {
    pets[item.pet.id] = item.pet;
    byPet.putIfAbsent(item.pet.id, () => []).add(item);
  }

  // Pets in the order their soonest item appears, which keeps the most
  // overdue cat at the top.
  return [
    for (final entry in byPet.entries)
      PetDueGroup(pet: pets[entry.key]!, items: entry.value),
  ];
}
