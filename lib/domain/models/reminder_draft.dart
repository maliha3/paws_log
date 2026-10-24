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

  /// A draft of a reminder that already exists, for editing it.
  ///
  /// The anchor becomes [firstDue] because that is what the sheet edits: the
  /// date the cycle counts from, which for an existing reminder is where its
  /// series started and where a changed schedule will restart it.
  factory ReminderDraft.fromReminder(Reminder reminder) => ReminderDraft(
    title: reminder.title,
    category: reminder.category,
    repeat: reminder.repeat,
    firstDue: reminder.anchorDate,
    timeOfDayMinutes: reminder.timeOfDayMinutes,
    enabled: reminder.isActive,
    notes: reminder.notes,
  );

  /// Applies this draft's edits to [reminder].
  ///
  /// `isActive` is deliberately not taken from [enabled]: pausing is its own
  /// action on the reminders screen, and the sheet never offers it.
  Reminder applyTo(Reminder reminder) => reminder.copyWith(
    title: title,
    category: category,
    repeat: repeat,
    anchorDate: firstDue,
    timeOfDayMinutes: timeOfDayMinutes,
    notes: notes,
  );

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
