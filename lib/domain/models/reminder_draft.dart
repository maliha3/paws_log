import '../repeat_rule.dart';
import 'reminder.dart';

/// An unsaved reminder, as edited on the starter-reminders screen.
///
/// Onboarding needs rows the owner can toggle, retitle and re-time before
/// anything touches the database.
class ReminderDraft {
  const ReminderDraft({
    required this.title,
    required this.category,
    required this.repeat,
    required this.firstDue,
    required this.timeOfDayMinutes,
    this.enabled = true,
    this.notes,
  });

  final String title;
  final ReminderCategory category;
  final RepeatRule repeat;

  /// The date this first comes due, which becomes the reminder's anchor.
  /// Date-only, held at UTC midnight.
  final DateTime firstDue;

  final int timeOfDayMinutes;

  /// Whether the owner kept this suggestion.
  final bool enabled;

  final String? notes;

  ReminderDraft copyWith({
    String? title,
    ReminderCategory? category,
    RepeatRule? repeat,
    DateTime? firstDue,
    int? timeOfDayMinutes,
    bool? enabled,
    String? notes,
  }) => ReminderDraft(
    title: title ?? this.title,
    category: category ?? this.category,
    repeat: repeat ?? this.repeat,
    firstDue: firstDue ?? this.firstDue,
    timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
    enabled: enabled ?? this.enabled,
    notes: notes ?? this.notes,
  );
}
