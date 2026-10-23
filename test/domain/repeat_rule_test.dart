import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/core/date_x.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location zone;

  setUpAll(() {
    tz_data.initializeTimeZones();
    // New York has DST, so wall-clock handling is exercised rather than
    // assumed. In 2026 it springs forward on 8 March and falls back on
    // 1 November.
    zone = tz.getLocation('America/New_York');
    tz.setLocalLocation(zone);
  });

  tz.TZDateTime at(int year, int month, int day, [int hour = 9]) =>
      tz.TZDateTime(zone, year, month, day, hour);

  /// The calendar dates of the first [count] occurrences from [anchor].
  List<String> series(RepeatRule rule, tz.TZDateTime anchor, int count) => [
    for (var index = 0; index < count; index++)
      _ymd(rule.occurrence(anchor, index)),
  ];

  group('occurrence', () {
    test('index 0 is always the anchor', () {
      final anchor = at(2026, 3, 15);
      for (final rule in [
        const RepeatRule.once(),
        const RepeatRule.days(1),
        const RepeatRule.weeks(2),
        const RepeatRule.months(3),
        const RepeatRule.years(1),
      ]) {
        expect(rule.occurrence(anchor, 0), anchor, reason: '$rule');
      }
    });

    test('a one-off never moves', () {
      final anchor = at(2026, 3, 15);
      expect(const RepeatRule.once().occurrence(anchor, 5), anchor);
    });

    test('days', () {
      expect(
        series(const RepeatRule.days(1), at(2026, 3, 15), 4),
        ['2026-03-15', '2026-03-16', '2026-03-17', '2026-03-18'],
      );
      expect(
        series(const RepeatRule.days(10), at(2026, 3, 15), 4),
        ['2026-03-15', '2026-03-25', '2026-04-04', '2026-04-14'],
      );
    });

    test('weeks', () {
      expect(
        series(const RepeatRule.weeks(1), at(2026, 3, 15), 3),
        ['2026-03-15', '2026-03-22', '2026-03-29'],
      );
      expect(
        series(const RepeatRule.weeks(2), at(2026, 3, 15), 3),
        ['2026-03-15', '2026-03-29', '2026-04-12'],
      );
    });

    test('months', () {
      expect(
        series(const RepeatRule.months(1), at(2026, 1, 15), 4),
        ['2026-01-15', '2026-02-15', '2026-03-15', '2026-04-15'],
      );
      expect(
        series(const RepeatRule.months(3), at(2026, 1, 15), 5),
        [
          '2026-01-15',
          '2026-04-15',
          '2026-07-15',
          '2026-10-15',
          '2027-01-15',
        ],
        reason: 'the year rolls over',
      );
    });

    test('years', () {
      expect(
        series(const RepeatRule.years(1), at(2026, 6, 1), 3),
        ['2026-06-01', '2027-06-01', '2028-06-01'],
      );
      expect(
        series(const RepeatRule.years(2), at(2026, 6, 1), 3),
        ['2026-06-01', '2028-06-01', '2030-06-01'],
      );
    });

    test('the time of day is carried through', () {
      final anchor = at(2026, 3, 15, 18);
      final next = const RepeatRule.months(3).occurrence(anchor, 1);
      expect(next.hour, 18);
      expect(next.minute, 0);
    });

    test('minutes are carried through', () {
      final anchor = tz.TZDateTime(zone, 2026, 3, 15, 7, 45);
      final next = const RepeatRule.weeks(1).occurrence(anchor, 1);
      expect(next.hour, 7);
      expect(next.minute, 45);
    });
  });

  group('month-end clamping', () {
    test('a clamp never walks the series backwards', () {
      // The anchor stays on the 31st, so March returns the 31st even though
      // February had to clamp. Computing each step from the previous one
      // would have pinned the whole series to the 28th.
      expect(
        series(const RepeatRule.months(1), at(2026, 1, 31), 6),
        [
          '2026-01-31',
          '2026-02-28',
          '2026-03-31',
          '2026-04-30',
          '2026-05-31',
          '2026-06-30',
        ],
      );
    });

    test('clamps to 29 in a leap February', () {
      expect(
        series(const RepeatRule.months(1), at(2028, 1, 31), 3),
        ['2028-01-31', '2028-02-29', '2028-03-31'],
      );
    });

    test('a 30th anchor clamps only in February', () {
      expect(
        series(const RepeatRule.months(1), at(2026, 1, 30), 4),
        ['2026-01-30', '2026-02-28', '2026-03-30', '2026-04-30'],
      );
    });

    test('quarterly from the 31st clamps per target month', () {
      expect(
        series(const RepeatRule.months(3), at(2026, 1, 31), 5),
        [
          '2026-01-31',
          '2026-04-30',
          '2026-07-31',
          '2026-10-31',
          '2027-01-31',
        ],
      );
    });

    test('a yearly 29 February falls to the 28th in common years', () {
      expect(
        series(const RepeatRule.years(1), at(2028, 2, 29), 5),
        [
          '2028-02-29',
          '2029-02-28',
          '2030-02-28',
          '2031-02-28',
          '2032-02-29',
        ],
        reason: 'the anchor is unchanged, so 2032 returns the 29th',
      );
    });

    test('a four-yearly 29 February always lands on the 29th', () {
      expect(
        series(const RepeatRule.years(4), at(2028, 2, 29), 3),
        ['2028-02-29', '2032-02-29', '2036-02-29'],
      );
    });
  });

  group('daylight saving', () {
    test('a daily reminder keeps its wall-clock time across spring forward', () {
      // 8 March 2026 is when New York loses an hour. Adding 24-hour
      // durations would have pushed the time to 10:00 from then on.
      final occurrences = [
        for (var index = 0; index < 4; index++)
          const RepeatRule.days(1).occurrence(at(2026, 3, 6), index),
      ];
      expect(occurrences.map(_ymd).toList(), [
        '2026-03-06',
        '2026-03-07',
        '2026-03-08',
        '2026-03-09',
      ]);
      expect(occurrences.map((o) => o.hour), everyElement(9));

      // The underlying instants really do shift, which is the point.
      expect(occurrences[1].timeZoneOffset.inHours, -5);
      expect(occurrences[3].timeZoneOffset.inHours, -4);
    });

    test('and across falling back', () {
      final occurrences = [
        for (var index = 0; index < 4; index++)
          const RepeatRule.days(1).occurrence(at(2026, 10, 30), index),
      ];
      expect(occurrences.map(_ymd).toList(), [
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
      ]);
      expect(occurrences.map((o) => o.hour), everyElement(9));
      expect(occurrences.first.timeZoneOffset.inHours, -4);
      expect(occurrences.last.timeZoneOffset.inHours, -5);
    });

    test('a monthly reminder keeps its time across a DST boundary', () {
      final occurrences = [
        for (var index = 0; index < 3; index++)
          const RepeatRule.months(1).occurrence(at(2026, 2, 20, 21), index),
      ];
      expect(occurrences.map((o) => o.hour), everyElement(21));
      expect(occurrences.map(_ymd).toList(), [
        '2026-02-20',
        '2026-03-20',
        '2026-04-20',
      ]);
    });

    test('a time that does not exist on the day still lands on that day', () {
      // 02:30 on 8 March 2026 is skipped by the clock change. The zone
      // normalises it rather than throwing, and it must not slide onto the
      // wrong date.
      final anchor = tz.TZDateTime(zone, 2026, 3, 7, 2, 30);
      final next = const RepeatRule.days(1).occurrence(anchor, 1);
      expect(next.month, 3);
      expect(next.day, 8);
    });
  });

  group('nextAfter', () {
    // A function, not a field: group bodies run at collection time, before
    // setUpAll has loaded the zone.
    tz.TZDateTime anchor() => at(2026, 1, 15);

    test('an anchor still ahead is itself the next occurrence', () {
      expect(
        const RepeatRule.months(3).nextAfter(
          anchor: anchor(),
          after: at(2026, 1, 1),
        ),
        anchor(),
      );
    });

    test('a one-off that has passed has no next occurrence', () {
      expect(
        const RepeatRule.once().nextAfter(
          anchor: anchor(),
          after: at(2026, 2, 1),
        ),
        isNull,
      );
    });

    test('a one-off still ahead returns its single occurrence', () {
      expect(
        const RepeatRule.once().nextAfter(
          anchor: anchor(),
          after: at(2026, 1, 1),
        ),
        anchor(),
      );
    });

    test('it is strictly after, so landing on an occurrence advances', () {
      expect(
        _ymd(
          const RepeatRule.months(3).nextAfter(anchor: anchor(), after: anchor())!,
        ),
        '2026-04-15',
      );
    });

    test('a moment just before an occurrence returns it', () {
      final justBefore = at(2026, 4, 15, 8);
      expect(
        _ymd(
          const RepeatRule.months(3)
              .nextAfter(anchor: anchor(), after: justBefore)!,
        ),
        '2026-04-15',
      );
    });

    test('five months late skips ahead instead of replaying', () {
      // Occurrences are 15 Jan, 15 Apr, 15 Jul. Overdue since April, asked
      // in June: the answer is July, and April is not revisited.
      expect(
        _ymd(
          const RepeatRule.months(3)
              .nextAfter(anchor: anchor(), after: at(2026, 6, 20))!,
        ),
        '2026-07-15',
      );
    });

    test('years late still gives one future date', () {
      expect(
        _ymd(
          const RepeatRule.months(3)
              .nextAfter(anchor: anchor(), after: at(2031, 2, 3))!,
        ),
        '2031-04-15',
      );
    });

    test('it converges a long way out', () {
      final far = const RepeatRule.days(1)
          .nextAfter(anchor: anchor(), after: at(2050, 6, 1))!;
      expect(_ymd(far), '2050-06-02');
    });

    test('a clamped month is reachable as a next occurrence', () {
      expect(
        _ymd(
          const RepeatRule.months(1)
              .nextAfter(anchor: at(2026, 1, 31), after: at(2026, 2, 1))!,
        ),
        '2026-02-28',
      );
    });

    test('weekly and yearly both advance', () {
      expect(
        _ymd(
          const RepeatRule.weeks(2)
              .nextAfter(anchor: anchor(), after: at(2026, 2, 1))!,
        ),
        '2026-02-12',
      );
      expect(
        _ymd(
          const RepeatRule.years(1)
              .nextAfter(anchor: anchor(), after: at(2026, 2, 1))!,
        ),
        '2027-01-15',
      );
    });
  });

  group('nextDueAfter', () {
    // Date-only values are held at UTC midnight.
    final anchorDate = DateTime.utc(2026, 3, 15);
    const nineAm = 9 * 60;
    const quarterly = RepeatRule.months(3);

    tz.TZDateTime inZone(DateTime value) => tz.TZDateTime.from(value, zone);

    test('it returns a plain UTC DateTime, not a TZDateTime', () {
      final next = nextDueAfter(
        anchorDate: anchorDate,
        timeOfDayMinutes: nineAm,
        repeat: quarterly,
        after: at(2026, 3, 15),
        location: zone,
      )!;

      expect(next.isUtc, isTrue);
      expect(next, isNot(isA<tz.TZDateTime>()));
      // And it compares equal to an ordinary DateTime, which is what the
      // database hands back.
      expect(next, DateTime.fromMicrosecondsSinceEpoch(
        next.microsecondsSinceEpoch,
        isUtc: true,
      ));
    });

    test('completed on the day it was due', () {
      final next = inZone(
        nextDueAfter(
          anchorDate: anchorDate,
          timeOfDayMinutes: nineAm,
          repeat: quarterly,
          after: at(2026, 3, 15),
          location: zone,
        )!,
      );
      expect(_ymd(next), '2026-06-15');
      expect(next.hour, 9);
    });

    test('completed early returns the occurrence not yet reached', () {
      // This is why the repository asks from the later of now and the
      // scheduled date: on its own, "completed five days early" would hand
      // back the very occurrence just closed.
      final next = inZone(
        nextDueAfter(
          anchorDate: anchorDate,
          timeOfDayMinutes: nineAm,
          repeat: quarterly,
          after: at(2026, 3, 10),
          location: zone,
        )!,
      );
      expect(_ymd(next), '2026-03-15');
    });

    test('completed months late skips the missed cycles', () {
      final next = inZone(
        nextDueAfter(
          anchorDate: anchorDate,
          timeOfDayMinutes: nineAm,
          repeat: quarterly,
          after: at(2026, 8, 20),
          location: zone,
        )!,
      );
      expect(_ymd(next), '2026-09-15');
    });

    test('a one-off has nothing after it', () {
      expect(
        nextDueAfter(
          anchorDate: anchorDate,
          timeOfDayMinutes: nineAm,
          repeat: const RepeatRule.once(),
          after: at(2026, 3, 15),
          location: zone,
        ),
        isNull,
      );
    });

    test('the time of day survives the round trip', () {
      final next = inZone(
        nextDueAfter(
          anchorDate: anchorDate,
          timeOfDayMinutes: 18 * 60 + 30,
          repeat: quarterly,
          after: at(2026, 3, 16),
          location: zone,
        )!,
      );
      expect(next.hour, 18);
      expect(next.minute, 30);
    });
  });

  group('wallClock', () {
    test('it reads a date-only value in the given zone', () {
      final instant = wallClock(
        DateTime.utc(2026, 3, 15),
        9 * 60,
        location: zone,
      );
      expect(_ymd(instant), '2026-03-15');
      expect(instant.hour, 9);
      expect(instant.location, zone);
    });

    test('midnight and the end of the day both work', () {
      expect(wallClock(DateTime.utc(2026, 3, 15), 0, location: zone).hour, 0);
      final late = wallClock(
        DateTime.utc(2026, 3, 15),
        23 * 60 + 59,
        location: zone,
      );
      expect(late.hour, 23);
      expect(late.minute, 59);
      expect(_ymd(late), '2026-03-15', reason: 'it does not spill over');
    });
  });

  group('describe', () {
    test('singular, plural and one-off', () {
      expect(const RepeatRule.once().describe(), 'Once');
      expect(const RepeatRule.days(1).describe(), 'Every day');
      expect(const RepeatRule.days(10).describe(), 'Every 10 days');
      expect(const RepeatRule.weeks(1).describe(), 'Every week');
      expect(const RepeatRule.months(1).describe(), 'Every month');
      expect(const RepeatRule.months(3).describe(), 'Every 3 months');
      expect(const RepeatRule.years(1).describe(), 'Every year');
    });
  });

  group('the rule itself', () {
    test('equality is by unit and interval', () {
      expect(const RepeatRule.months(3), const RepeatRule.months(3));
      expect(
        const RepeatRule.months(3).hashCode,
        const RepeatRule.months(3).hashCode,
      );
      expect(
        const RepeatRule.months(3),
        isNot(const RepeatRule.months(1)),
      );
      expect(
        const RepeatRule.months(1),
        isNot(const RepeatRule.weeks(1)),
      );
    });

    test('an interval below 1 is rejected', () {
      expect(
        () => RepeatRule(unit: RepeatUnit.days, interval: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('repeats is false only for a one-off', () {
      expect(const RepeatRule.once().repeats, isFalse);
      expect(const RepeatRule.days(1).repeats, isTrue);
    });

    test('copyWith changes one part at a time', () {
      const rule = RepeatRule.months(3);
      expect(rule.copyWith(interval: 6), const RepeatRule.months(6));
      expect(
        rule.copyWith(unit: RepeatUnit.weeks),
        const RepeatRule.weeks(3),
      );
    });

    test('a name round-trips through storage', () {
      for (final unit in RepeatUnit.values) {
        expect(RepeatUnit.fromName(unit.name), unit);
      }
    });
  });

  group('date helpers', () {
    test('daysInMonth covers leap years and December', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });

    test('dateOnly drops the time', () {
      expect(
        dateOnly(DateTime(2026, 3, 15, 18, 42)),
        DateTime(2026, 3, 15),
      );
    });

    test('isSameDay ignores the time', () {
      expect(
        isSameDay(DateTime(2026, 3, 15, 1), DateTime(2026, 3, 15, 23)),
        isTrue,
      );
      expect(
        isSameDay(DateTime(2026, 3, 15, 23), DateTime(2026, 3, 16)),
        isFalse,
      );
    });
  });
}

String _ymd(tz.TZDateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
