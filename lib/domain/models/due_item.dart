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

  /// Whether this was due on an earlier day than [startOfToday].
  ///
  /// Takes the start of the day, not "now": something due today at 09:00 is
  /// not overdue at 14:00, it is still today's.
  bool isOverdue(DateTime startOfToday) =>
      event.scheduledFor.toLocal().isBefore(startOfToday);
}
