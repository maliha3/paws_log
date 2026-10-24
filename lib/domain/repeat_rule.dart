import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../core/date_x.dart';
import 'shedding_season.dart';

/// The unit a [RepeatRule] counts in.
enum RepeatUnit {
  none,
  days,
  weeks,
  months,
  years;

  /// The stored name, used by drift's `textEnum`.
  static RepeatUnit fromName(String name) =>
      RepeatUnit.values.firstWhere((unit) => unit.name == name);
}

/// How often a reminder comes round: every [interval] [unit].
///
/// A rule on its own says nothing about *when* — occurrences are always
/// computed from an anchor, so a long-dormant reminder lands on the same days
/// of the month it always did instead of drifting.
class RepeatRule {
  const RepeatRule({
    required this.unit,
    required this.interval,
    this.seasonal = false,
  }) : assert(interval >= 1, 'interval must be at least 1');

  /// A one-off: it happens on the anchor date and never again.
  const RepeatRule.once()
    : unit = RepeatUnit.none,
      interval = 1,
      seasonal = false;

  const RepeatRule.days(this.interval, {this.seasonal = false})
    : unit = RepeatUnit.days;
  const RepeatRule.weeks(this.interval, {this.seasonal = false})
    : unit = RepeatUnit.weeks;
  const RepeatRule.months(this.interval) : unit = RepeatUnit.months,
      seasonal = false;
  const RepeatRule.years(this.interval) : unit = RepeatUnit.years,
      seasonal = false;

  final RepeatUnit unit;
  final int interval;

  /// Whether the interval halves during shedding season.
  ///
  /// Only grooming reminders set it. It is the one thing that makes an
  /// occurrence depend on *where in the year* the previous one fell, which
  /// is why it has to be opt-in — see `occurrence`.
  final bool seasonal;

  bool get repeats => unit != RepeatUnit.none;

  /// Whether the seasonal halving actually applies.
  ///
  /// Only to day and week rules. A monthly or yearly interval cannot sensibly
  /// halve, and more importantly the stepping path below walks from one
  /// occurrence to the next — which for months would reintroduce exactly the
  /// backwards month-end walk that computing from the anchor exists to
  /// prevent. So those units keep the anchor-based path, untouched.
  bool get halvesInSeason =>
      seasonal &&
      repeats &&
      (unit == RepeatUnit.days || unit == RepeatUnit.weeks);

  /// A safety valve, not a limit anyone should reach: the shortest possible
  /// step is one day, so this is over fifty years of walking.
  static const int _maxSeasonalSteps = 20000;

  /// The [index]th occurrence counted from [anchor]; index 0 is the anchor.
  ///
  /// Always computed from the anchor rather than from the previous occurrence,
  /// so a month-end clamp never walks the series backwards: anchored on the
  /// 31st, a monthly rule gives Jan 31, Feb 28, Mar 31 — not Feb 28, Mar 28.
  ///
  /// Dates are rebuilt from calendar fields rather than advanced by a
  /// [Duration], which keeps the wall-clock time across a DST boundary.
  tz.TZDateTime occurrence(tz.TZDateTime anchor, int index) {
    if (index == 0 || !repeats) {
      return anchor;
    }
    if (halvesInSeason) {
      // One step at a time, because each interval depends on where in the
      // year the *previous* occurrence fell. That makes this O(index) rather
      // than O(1), which is why it is opt-in and confined to day and week
      // rules: a couple of thousand integer date additions is nothing, and
      // every other rule keeps the jump.
      var current = anchor;
      for (var step = 0; step < index; step++) {
        current = _stepOnce(current, _daysFrom(current));
      }
      return current;
    }
    final steps = interval * index;
    switch (unit) {
      case RepeatUnit.none:
        return anchor;
      case RepeatUnit.days:
      case RepeatUnit.weeks:
        final days = unit == RepeatUnit.weeks ? steps * 7 : steps;
        // Day arithmetic in UTC, where every day is exactly 24 hours.
        final shifted = DateTime.utc(
          anchor.year,
          anchor.month,
          anchor.day,
        ).add(Duration(days: days));
        return _at(anchor, shifted.year, shifted.month, shifted.day);
      case RepeatUnit.months:
        final monthsFromYearZero = anchor.year * 12 + anchor.month - 1 + steps;
        final year = monthsFromYearZero ~/ 12;
        final month = monthsFromYearZero % 12 + 1;
        return _at(anchor, year, month, anchor.day);
      case RepeatUnit.years:
        return _at(anchor, anchor.year + steps, anchor.month, anchor.day);
    }
  }

  /// The first occurrence strictly after [after], or null if there is none.
  ///
  /// This is the "skip ahead" overdue policy from CLAUDE.md: a quarterly
  /// reminder five months late returns its next future date, and the four
  /// missed cycles are not replayed.
  tz.TZDateTime? nextAfter({
    required tz.TZDateTime anchor,
    required tz.TZDateTime after,
  }) {
    if (anchor.isAfter(after)) {
      return anchor;
    }
    if (!repeats) {
      return null;
    }
    if (halvesInSeason) {
      // No jumping: the index estimate assumes a fixed interval, and this
      // rule does not have one. Walking is still cheap, and the overdue
      // policy is unchanged — the first occurrence strictly after [after] is
      // what comes back, so missed cycles are skipped exactly as before.
      var current = anchor;
      for (var step = 0; step < _maxSeasonalSteps; step++) {
        current = _stepOnce(current, _daysFrom(current));
        if (current.isAfter(after)) {
          return current;
        }
      }
      return current;
    }

    // Jump roughly to the right place, then close the gap exactly. The
    // estimate can land on either side of the answer, so both directions are
    // walked; each loop runs a couple of iterations at most.
    var index = _estimateIndex(anchor, after);
    while (index > 0 && occurrence(anchor, index - 1).isAfter(after)) {
      index--;
    }
    while (!occurrence(anchor, index).isAfter(after)) {
      index++;
    }
    return occurrence(anchor, index);
  }

  /// The gap to the next occurrence, **in days**, counted from [from].
  ///
  /// Days rather than the rule's own unit, because halving has to happen in
  /// the smaller one: half of "every week" is every three days, and halving
  /// the interval instead would leave `weeks(1)` at a full week — one week
  /// halves to zero and clamps straight back up.
  ///
  /// Never below a day. "Twice as often" has to stop somewhere, and a daily
  /// reminder cannot come twice a day.
  int _daysFrom(tz.TZDateTime from) {
    final full = unit == RepeatUnit.weeks ? interval * 7 : interval;
    return inSheddingSeason(from) ? math.max(1, full ~/ 2) : full;
  }

  /// Advances [from] by [days], keeping its wall-clock time of day.
  ///
  /// Only used by the seasonal path, which is restricted to days and weeks,
  /// so there is no month-end clamping to get wrong here.
  tz.TZDateTime _stepOnce(tz.TZDateTime from, int days) {
    // Day arithmetic in UTC, where every day is exactly 24 hours.
    final shifted = DateTime.utc(
      from.year,
      from.month,
      from.day,
    ).add(Duration(days: days));
    return _at(from, shifted.year, shifted.month, shifted.day);
  }

  /// A rough occurrence index for [after], never below zero.
  int _estimateIndex(tz.TZDateTime anchor, tz.TZDateTime after) {
    final elapsed = switch (unit) {
      RepeatUnit.none => 0,
      RepeatUnit.days => after.difference(anchor).inDays,
      RepeatUnit.weeks => after.difference(anchor).inDays ~/ 7,
      RepeatUnit.months =>
        (after.year - anchor.year) * 12 + after.month - anchor.month,
      RepeatUnit.years => after.year - anchor.year,
    };
    final index = elapsed ~/ interval;
    return index < 0 ? 0 : index;
  }

  /// Rebuilds [anchor] on a new calendar date, keeping its time of day.
  ///
  /// The day is clamped to the length of the target month, so Jan 31 plus a
  /// month is Feb 28 (or 29 in a leap year) and Feb 29 plus a year is Feb 28.
  tz.TZDateTime _at(tz.TZDateTime anchor, int year, int month, int day) =>
      tz.TZDateTime(
        anchor.location,
        year,
        month,
        day.clamp(1, daysInMonth(year, month)),
        anchor.hour,
        anchor.minute,
      );

  /// Human-readable summary, e.g. "Every 3 months".
  String describe() {
    if (!repeats) {
      return 'Once';
    }
    final noun = switch (unit) {
      RepeatUnit.none => '',
      RepeatUnit.days => 'day',
      RepeatUnit.weeks => 'week',
      RepeatUnit.months => 'month',
      RepeatUnit.years => 'year',
    };
    final base = interval == 1 ? 'Every $noun' : 'Every $interval ${noun}s';
    return halvesInSeason ? '$base, twice as often while shedding' : base;
  }

  RepeatRule copyWith({RepeatUnit? unit, int? interval, bool? seasonal}) =>
      RepeatRule(
        unit: unit ?? this.unit,
        interval: interval ?? this.interval,
        seasonal: seasonal ?? this.seasonal,
      );

  @override
  bool operator ==(Object other) =>
      other is RepeatRule &&
      other.unit == unit &&
      other.interval == interval &&
      other.seasonal == seasonal;

  @override
  int get hashCode => Object.hash(unit, interval, seasonal);

  @override
  String toString() =>
      'RepeatRule(${unit.name} x $interval'
      '${seasonal ? ', seasonal' : ''})';
}

extension TZDateTimeUtc on tz.TZDateTime {
  /// The same instant as a plain UTC [DateTime].
  ///
  /// `toUtc()` on a [tz.TZDateTime] returns another [tz.TZDateTime], and that
  /// does not compare equal to the plain [DateTime] values the database hands
  /// back. Zone-aware types stay inside the date maths; everything else sees
  /// plain UTC.
  DateTime toPlainUtc() =>
      DateTime.fromMicrosecondsSinceEpoch(microsecondsSinceEpoch, isUtc: true);
}

/// Builds the local instant for [date] (a date-only value) at
/// [timeOfDayMinutes] past local midnight.
///
/// Date-only values are stored as UTC midnight, so the calendar fields are
/// read back in UTC and then reinterpreted in [location].
tz.TZDateTime wallClock(
  DateTime date,
  int timeOfDayMinutes, {
  tz.Location? location,
}) {
  final utcDate = date.toUtc();
  return tz.TZDateTime(
    location ?? tz.local,
    utcDate.year,
    utcDate.month,
    utcDate.day,
    timeOfDayMinutes ~/ 60,
    timeOfDayMinutes % 60,
  );
}

/// The next due instant for a reminder, strictly after [after], as UTC.
///
/// Returns null for a one-off whose single occurrence has already passed.
DateTime? nextDueAfter({
  required DateTime anchorDate,
  required int timeOfDayMinutes,
  required RepeatRule repeat,
  required DateTime after,
  tz.Location? location,
}) {
  final zone = location ?? tz.local;
  final anchor = wallClock(anchorDate, timeOfDayMinutes, location: zone);
  final next = repeat.nextAfter(
    anchor: anchor,
    after: tz.TZDateTime.from(after, zone),
  );
  return next?.toPlainUtc();
}
