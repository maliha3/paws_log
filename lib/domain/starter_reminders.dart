import '../core/constants.dart';
import '../core/date_x.dart';
import 'models/reminder.dart';
import 'models/reminder_draft.dart';
import 'repeat_rule.dart';

/// The suggestions onboarding pre-fills on the starter-reminders screen.
///
/// These are common intervals, not medical advice — the screen carries
/// [AppConstants.vetDisclaimer] and every field stays editable.
List<ReminderDraft> starterReminderDrafts({DateTime? today}) {
  final from = dateOnly(today ?? DateTime.now());
  // Date-only values are held at UTC midnight.
  final anchor = DateTime.utc(from.year, from.month, from.day);

  return [
    ReminderDraft(
      title: 'Yearly vaccine',
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.years(1),
      firstDue: anchor,
      timeOfDayMinutes: AppConstants.defaultReminderTimeMinutes,
    ),
    ReminderDraft(
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      firstDue: anchor,
      timeOfDayMinutes: AppConstants.defaultReminderTimeMinutes,
    ),
    ReminderDraft(
      title: 'Flea & tick treatment',
      category: ReminderCategory.fleaTick,
      repeat: const RepeatRule.months(1),
      firstDue: anchor,
      timeOfDayMinutes: AppConstants.defaultReminderTimeMinutes,
    ),
  ];
}
