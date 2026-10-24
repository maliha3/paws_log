import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  setUpAll(initializeTestTimeZone);

  tz.TZDateTime at(int year, int month, int day) =>
      tz.TZDateTime(tz.local, year, month, day, 9);

  group('a rule that is not seasonal', () {
    test('is unchanged by the flag existing', () {
      // The seasonal path must not touch anything that does not ask for it.
      const plain = RepeatRule.days(2);
      final anchor = at(2026, 4, 1);

      expect(plain.seasonal, isFalse);
      expect(plain.halvesInSeason, isFalse);
      expect(
        [for (var i = 0; i < 5; i++) plain.occurrence(anchor, i)],
        [
          at(2026, 4, 1),
          at(2026, 4, 3),
          at(2026, 4, 5),
          at(2026, 4, 7),
          at(2026, 4, 9),
        ],
        reason: 'inside a shedding window, and still every two days',
      );
    });

    test('keeps its description', () {
      expect(const RepeatRule.weeks(1).describe(), 'Every week');
      expect(const RepeatRule.days(3).describe(), 'Every 3 days');
    });
  });

  group('a seasonal rule', () {
    test('halves its interval inside a shedding window', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 4, 1);

      expect(
        [for (var i = 0; i < 4; i++) brushing.occurrence(anchor, i)],
        [
          at(2026, 4, 1),
          at(2026, 4, 4),
          at(2026, 4, 7),
          at(2026, 4, 10),
        ],
        reason: 'seven days becomes three while the cat is shedding',
      );
    });

    test('keeps its full interval outside one', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 7, 1);

      expect(
        [for (var i = 0; i < 4; i++) brushing.occurrence(anchor, i)],
        [
          at(2026, 7, 1),
          at(2026, 7, 8),
          at(2026, 7, 15),
          at(2026, 7, 22),
        ],
      );
    });

    test('changes pace as it crosses into a window', () {
      // Anchored in February, weekly, stepping into March.
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 2, 20);

      expect(brushing.occurrence(anchor, 1), at(2026, 2, 27));
      expect(
        brushing.occurrence(anchor, 2),
        at(2026, 3, 6),
        reason: 'Feb 27 is outside the window, so that step is still 7 days',
      );
      expect(
        brushing.occurrence(anchor, 3),
        at(2026, 3, 9),
        reason: 'March 6 is inside it, so the next step is 3',
      );
    });

    test('changes pace as it leaves one', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 5, 28);

      expect(brushing.occurrence(anchor, 1), at(2026, 5, 31));
      expect(
        brushing.occurrence(anchor, 2),
        at(2026, 6, 3),
        reason: 'May 31 is the last day of the window',
      );
      expect(
        brushing.occurrence(anchor, 3),
        at(2026, 6, 10),
        reason: 'June 3 is outside it, so the full week is back',
      );
    });

    test('halves a weekly rule to three days, not half a week', () {
      const brushing = RepeatRule.weeks(1, seasonal: true);
      final anchor = at(2026, 4, 1);

      expect(
        brushing.occurrence(anchor, 1),
        at(2026, 4, 4),
        reason: 'a week is seven days, and half of that is three',
      );
    });

    test('never comes round more than once a day', () {
      const daily = RepeatRule.days(1, seasonal: true);
      final anchor = at(2026, 4, 1);

      expect(daily.occurrence(anchor, 1), at(2026, 4, 2));
      expect(
        daily.occurrence(anchor, 2),
        at(2026, 4, 3),
        reason: '"twice as often" has to stop somewhere',
      );
    });

    test('says so when it describes itself', () {
      expect(
        const RepeatRule.days(2, seasonal: true).describe(),
        'Every 2 days, twice as often while shedding',
      );
      expect(
        const RepeatRule.weeks(1, seasonal: true).describe(),
        'Every week, twice as often while shedding',
      );
    });

    test('has no effect on a monthly or yearly rule', () {
      // Halving a month is meaningless, and stepping month to month would
      // reintroduce the backwards month-end walk the anchor path prevents.
      const monthly = RepeatRule(
        unit: RepeatUnit.months,
        interval: 1,
        seasonal: true,
      );
      expect(monthly.halvesInSeason, isFalse);

      final anchor = at(2026, 3, 31);
      expect(monthly.occurrence(anchor, 1), at(2026, 4, 30));
      expect(
        monthly.occurrence(anchor, 2),
        at(2026, 5, 31),
        reason: 'the clamp must not walk the series backwards',
      );
    });
  });

  group('the next occurrence after a date', () {
    test('is the first one strictly after it, inside a window', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 4, 1);

      expect(
        brushing.nextAfter(anchor: anchor, after: at(2026, 4, 5)),
        at(2026, 4, 7),
      );
    });

    test('still skips ahead rather than replaying missed cycles', () {
      // The overdue policy: months late, it returns the next future date.
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 2, 1);
      final late = at(2026, 10, 14);

      final next = brushing.nextAfter(anchor: anchor, after: late);

      expect(next, isNotNull);
      expect(next!.isAfter(late), isTrue);
      expect(
        next.difference(late).inDays,
        lessThanOrEqualTo(7),
        reason: 'the very next occurrence, not the first of many missed ones',
      );
    });

    test('skipping ahead across a window boundary lands on the walked date', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 4, 1);

      // Walked by hand: Apr 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, May 1 ...
      final next = brushing.nextAfter(anchor: anchor, after: at(2026, 4, 25));
      expect(next, at(2026, 4, 28));
    });

    test('an anchor in the future is itself', () {
      const brushing = RepeatRule.days(7, seasonal: true);
      final anchor = at(2026, 4, 10);

      expect(
        brushing.nextAfter(anchor: anchor, after: at(2026, 4, 1)),
        anchor,
      );
    });

    test('a years-stale reminder still answers', () {
      // The stepping path is O(index); this is the shape of the worst case.
      const brushing = RepeatRule.days(2, seasonal: true);
      final anchor = at(2016, 1, 1);
      final now = at(2026, 10, 14);

      final next = brushing.nextAfter(anchor: anchor, after: now);

      expect(next, isNotNull);
      expect(next!.isAfter(now), isTrue);
      expect(next.difference(now).inDays, lessThanOrEqualTo(2));
    });
  });

  test('equality and hashing notice the flag', () {
    expect(
      const RepeatRule.days(2, seasonal: true),
      isNot(const RepeatRule.days(2)),
    );
    expect(
      const RepeatRule.days(2, seasonal: true).hashCode,
      isNot(const RepeatRule.days(2).hashCode),
    );
    expect(
      const RepeatRule.days(2, seasonal: true),
      const RepeatRule.days(2, seasonal: true),
    );
  });

  test('copyWith carries the flag, and can turn it off', () {
    const brushing = RepeatRule.days(2, seasonal: true);

    expect(brushing.copyWith(interval: 3).seasonal, isTrue);
    expect(brushing.copyWith(seasonal: false).seasonal, isFalse);
  });
}
