import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/domain/dose_schedule.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location zone;

  setUpAll(() {
    tz_data.initializeTimeZones();
    zone = tz.getLocation('America/New_York');
    tz.setLocalLocation(zone);
  });

  tz.TZDateTime at(int year, int month, int day, [int hour = 0]) =>
      tz.TZDateTime(zone, year, month, day, hour);

  DateTime date(int year, int month, int day) => DateTime.utc(year, month, day);

  /// Local "yyyy-MM-dd HH:mm" for each occurrence.
  List<String> stamps(List<DateTime> occurrences) => [
    for (final instant in occurrences) _stamp(tz.TZDateTime.from(instant, zone)),
  ];

  group('generation', () {
    test('twice a day over a three-day course', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: date(2026, 5, 4),
        endDate: date(2026, 5, 6),
      );

      expect(
        stamps(
          doseOccurrences(
            schedule,
            from: at(2026, 5, 4),
            until: at(2026, 5, 20),
            location: zone,
          ),
        ),
        [
          '2026-05-04 08:00',
          '2026-05-04 20:00',
          '2026-05-05 08:00',
          '2026-05-05 20:00',
          '2026-05-06 08:00',
          '2026-05-06 20:00',
        ],
      );
    });

    test('the end date is inclusive', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 5, 4),
        endDate: date(2026, 5, 4),
      );

      expect(
        stamps(
          doseOccurrences(
            schedule,
            from: at(2026, 5, 4),
            until: at(2026, 5, 30),
            location: zone,
          ),
        ),
        ['2026-05-04 09:00'],
      );
    });

    test('every other day skips the days between', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 5, 4),
        intervalDays: 2,
        endDate: date(2026, 5, 10),
      );

      expect(
        stamps(
          doseOccurrences(
            schedule,
            from: at(2026, 5, 4),
            until: at(2026, 5, 30),
            location: zone,
          ),
        ),
        [
          '2026-05-04 09:00',
          '2026-05-06 09:00',
          '2026-05-08 09:00',
          '2026-05-10 09:00',
        ],
      );
    });

    test('an open-ended course runs to the end of the window', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 5, 4),
      );

      final occurrences = doseOccurrences(
        schedule,
        from: at(2026, 5, 4),
        until: at(2026, 5, 7, 23),
        location: zone,
      );
      expect(occurrences, hasLength(4));
    });

    test('the window clips both ends', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: date(2026, 5, 1),
        endDate: date(2026, 5, 31),
      );

      expect(
        stamps(
          doseOccurrences(
            schedule,
            // Starts after the 4th's morning dose, ends before the 5th's
            // evening one.
            from: at(2026, 5, 4, 12),
            until: at(2026, 5, 5, 12),
            location: zone,
          ),
        ),
        ['2026-05-04 20:00', '2026-05-05 08:00'],
      );
    });

    test('a long-running course is not walked a day at a time', () {
      // Started two years ago and still going. Generation has to jump to the
      // window rather than iterate every intervening day.
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2024, 5, 4),
      );

      final occurrences = doseOccurrences(
        schedule,
        from: at(2026, 5, 4),
        until: at(2026, 5, 6, 23),
        location: zone,
      );

      expect(stamps(occurrences), [
        '2026-05-04 09:00',
        '2026-05-05 09:00',
        '2026-05-06 09:00',
      ]);
    });

    test('an every-other-day course keeps its parity across a long gap', () {
      // Started on an odd offset two years back; the jump into the window
      // must not quietly shift which days are dosing days.
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 1, 1),
        intervalDays: 3,
      );

      final occurrences = doseOccurrences(
        schedule,
        from: at(2026, 5, 4),
        until: at(2026, 5, 12, 23),
        location: zone,
      );

      // 1 Jan plus a multiple of three days: 4 May is day 123, divisible by 3.
      expect(stamps(occurrences), [
        '2026-05-04 09:00',
        '2026-05-07 09:00',
        '2026-05-10 09:00',
      ]);
    });

    test('no dosing times means no doses', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [],
        startDate: date(2026, 5, 4),
      );
      expect(
        doseOccurrences(
          schedule,
          from: at(2026, 5, 4),
          until: at(2026, 5, 30),
          location: zone,
        ),
        isEmpty,
      );
    });

    test('a course that has already ended generates nothing', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 1, 1),
        endDate: date(2026, 1, 10),
      );
      expect(
        doseOccurrences(
          schedule,
          from: at(2026, 5, 4),
          until: at(2026, 5, 30),
          location: zone,
        ),
        isEmpty,
      );
    });
  });

  group('daylight saving', () {
    test('doses keep their wall-clock time across spring forward', () {
      // New York springs forward on 8 March 2026.
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: date(2026, 3, 7),
        endDate: date(2026, 3, 9),
      );

      final occurrences = doseOccurrences(
        schedule,
        from: at(2026, 3, 7),
        until: at(2026, 3, 10),
        location: zone,
      );

      expect(stamps(occurrences), [
        '2026-03-07 08:00',
        '2026-03-07 20:00',
        '2026-03-08 08:00',
        '2026-03-08 20:00',
        '2026-03-09 08:00',
        '2026-03-09 20:00',
      ]);

      // The instants really do shift underneath, which is the point.
      final first = tz.TZDateTime.from(occurrences.first, zone);
      final last = tz.TZDateTime.from(occurrences.last, zone);
      expect(first.timeZoneOffset.inHours, -5);
      expect(last.timeZoneOffset.inHours, -4);
    });

    test('and across falling back', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: date(2026, 10, 31),
        endDate: date(2026, 11, 2),
      );

      expect(
        stamps(
          doseOccurrences(
            schedule,
            from: at(2026, 10, 31),
            until: at(2026, 11, 3),
            location: zone,
          ),
        ),
        ['2026-10-31 09:00', '2026-11-01 09:00', '2026-11-02 09:00'],
      );
    });

    test('the day with 25 hours still gets exactly its doses', () {
      final schedule = DoseSchedule(
        timesOfDayMinutes: const [1 * 60, 13 * 60],
        startDate: date(2026, 11, 1),
        endDate: date(2026, 11, 1),
      );

      expect(
        doseOccurrences(
          schedule,
          from: at(2026, 10, 31),
          until: at(2026, 11, 3),
          location: zone,
        ),
        hasLength(2),
      );
    });
  });

  group('startOfLocalDay', () {
    test('it is midnight in the zone, not in UTC', () {
      final start = startOfLocalDay(at(2026, 5, 4, 23), location: zone);
      final local = tz.TZDateTime.from(start, zone);

      expect(local.year, 2026);
      expect(local.month, 5);
      expect(local.day, 4);
      expect(local.hour, 0);
      expect(start.isUtc, isTrue);
    });
  });
}

String _stamp(tz.TZDateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
