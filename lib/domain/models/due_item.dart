import 'pet.dart';
import 'reminder.dart';
import 'reminder_event.dart';

/// A pending occurrence joined with the reminder and pet it belongs to.
///
/// Today needs all three to render a row, and asking the repository for them
/// together keeps the screen from fanning out into per-row queries.
class DueItem {
  const DueItem({
    required this.event,
    required this.reminder,
    required this.pet,
  });

  final ReminderEvent event;
  final Reminder reminder;
  final Pet pet;

  /// Whether this was due before today.
  bool isOverdue(DateTime today) =>
      event.scheduledFor.toLocal().isBefore(today);
}
