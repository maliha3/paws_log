import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/reminder_draft.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/domain/starter_reminders.dart';

void main() {
  /// The starter suggestion for one category, for a cat with this coat.
  ReminderDraft draftFor(CoatLength? coat, ReminderCategory category) =>
      starterReminderDrafts(
        coatLength: coat,
      ).firstWhere((draft) => draft.category == category);

  test('grooming joins the starter suggestions', () {
    final suggested = starterReminderDrafts();

    expect(
      suggested.map((draft) => draft.category),
      containsAll([ReminderCategory.nailTrim, ReminderCategory.brushing]),
    );
    expect(
      suggested.every((draft) => draft.enabled),
      isTrue,
      reason: 'suggested means pre-ticked, and every one stays editable',
    );
  });

  test('nail trim is every three weeks, whatever the coat', () {
    for (final coat in [null, CoatLength.short, CoatLength.long]) {
      expect(
        draftFor(coat, ReminderCategory.nailTrim).repeat,
        const RepeatRule.weeks(3),
        reason: '$coat',
      );
    }
  });

  group('brushing', () {
    test('is weekly for a short coat', () {
      expect(
        draftFor(CoatLength.short, ReminderCategory.brushing).repeat,
        const RepeatRule.weeks(1),
      );
    });

    test('is every two days for a long one', () {
      expect(
        draftFor(CoatLength.long, ReminderCategory.brushing).repeat,
        const RepeatRule.days(2),
      );
    });

    test('takes the lighter suggestion when the coat is not recorded', () {
      // Guessing "long" would put a short-haired cat on a chore it does not
      // need.
      expect(
        draftFor(null, ReminderCategory.brushing).repeat,
        const RepeatRule.weeks(1),
      );
    });

    test('does not suggest shedding doubling', () {
      // The switch is in the editor. The app should not open by proposing a
      // daily job.
      for (final coat in [null, CoatLength.short, CoatLength.long]) {
        expect(
          draftFor(coat, ReminderCategory.brushing).repeat.seasonal,
          isFalse,
          reason: '$coat',
        );
      }
    });
  });

  test('brushingRepeatFor is the single answer both paths use', () {
    expect(brushingRepeatFor(CoatLength.long), const RepeatRule.days(2));
    expect(brushingRepeatFor(CoatLength.short), const RepeatRule.weeks(1));
    expect(brushingRepeatFor(null), const RepeatRule.weeks(1));
  });

  test('the medical suggestions are untouched by the coat', () {
    for (final category in [
      ReminderCategory.vaccine,
      ReminderCategory.deworming,
      ReminderCategory.fleaTick,
    ]) {
      expect(
        draftFor(CoatLength.short, category).repeat,
        draftFor(CoatLength.long, category).repeat,
        reason: category.name,
      );
    }
  });
}
