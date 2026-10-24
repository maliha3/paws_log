import '../core/constants.dart';
import '../core/date_x.dart';
import 'models/pet.dart';
import 'models/reminder.dart';
import 'models/reminder_draft.dart';
import 'repeat_rule.dart';

/// How often a cat of this coat gets brushed.
///
/// A long coat mats, so it is brushed every couple of days rather than
/// weekly. A coat nobody has recorded gets the weekly suggestion: it is the
/// lighter of the two, and guessing "long" would put a short-haired cat on a
/// chore its owner does not need.
///
/// Shedding doubling is **off** in the suggestion. The switch is right there
/// in the editor, but the app should not open by proposing a daily job.
RepeatRule brushingRepeatFor(CoatLength? coat) => coat == CoatLength.long
    ? const RepeatRule.days(2)
    : const RepeatRule.weeks(1);

/// The suggestions onboarding pre-fills on the starter-reminders screen.
///
/// These are common intervals, not medical advice — the screen carries
/// [AppConstants.vetDisclaimer] and every field stays editable.
List<ReminderDraft> starterReminderDrafts({
  DateTime? today,
  CoatLength? coatLength,
}) {
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
    ReminderDraft(
      title: 'Nail trim',
      category: ReminderCategory.nailTrim,
      repeat: const RepeatRule.weeks(3),
      firstDue: anchor,
      timeOfDayMinutes: AppConstants.defaultReminderTimeMinutes,
    ),
    ReminderDraft(
      title: 'Brushing',
      category: ReminderCategory.brushing,
      repeat: brushingRepeatFor(coatLength),
      firstDue: anchor,
      timeOfDayMinutes: AppConstants.defaultReminderTimeMinutes,
    ),
  ];
}
