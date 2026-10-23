import 'package:timezone/timezone.dart' as tz;

import 'models/medicine.dart';
import 'repeat_rule.dart';

/// Every dose instant for [schedule] falling within [from]..[until], as UTC.
///
/// Like reminder occurrences, each instant is built from calendar fields in
/// the local zone rather than by adding durations, so an 08:00 dose stays at
/// 08:00 across a clock change.
List<DateTime> doseOccurrences(
  DoseSchedule schedule, {
  required DateTime from,
  required DateTime until,
  tz.Location? location,
}) {
  final zone = location ?? tz.local;
  if (schedule.timesOfDayMinutes.isEmpty || !until.isAfter(from)) {
    return const [];
  }

  final startDay = _dateOnly(schedule.startDate);
  final fromDay = _localDateOnly(from, zone);

  var lastDay = _localDateOnly(until, zone);
  final end = schedule.endDate;
  if (end != null && _dateOnly(end).isBefore(lastDay)) {
    lastDay = _dateOnly(end);
  }

  // Jump straight to the first dosing day inside the window. A course that
  // began two years ago must not be walked a day at a time to reach today.
  var day = startDay;
  if (day.isBefore(fromDay)) {
    final elapsed = fromDay.difference(startDay).inDays;
    final steps = elapsed ~/ schedule.intervalDays;
    day = startDay.add(Duration(days: steps * schedule.intervalDays));
  }

  final occurrences = <DateTime>[];
  while (!day.isAfter(lastDay)) {
    for (final minutes in schedule.timesOfDayMinutes) {
      final instant = wallClock(day, minutes, location: zone).toPlainUtc();
      if (!instant.isBefore(from) && !instant.isAfter(until)) {
        occurrences.add(instant);
      }
    }
    day = day.add(Duration(days: schedule.intervalDays));
  }

  occurrences.sort();
  return occurrences;
}

/// Local midnight on the day [instant] falls on, as a date-only value.
DateTime startOfLocalDay(DateTime instant, {tz.Location? location}) {
  final zone = location ?? tz.local;
  final date = _localDateOnly(instant, zone);
  return wallClock(date, 0, location: zone).toPlainUtc();
}

DateTime _dateOnly(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _localDateOnly(DateTime instant, tz.Location zone) {
  final local = tz.TZDateTime.from(instant, zone);
  return DateTime.utc(local.year, local.month, local.day);
}
