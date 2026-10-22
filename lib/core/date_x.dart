/// Date helpers shared across the app.
///
/// Recurrence arithmetic does not live here — see `domain/repeat_rule.dart`.
library;

/// Strips the time from [value], keeping its calendar day.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Whether [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The number of days in [month] of [year].
int daysInMonth(int year, int month) {
  // Day 0 of the next month is the last day of this one.
  final nextMonth = month == 12
      ? DateTime(year + 1)
      : DateTime(year, month + 1);
  return nextMonth.subtract(const Duration(days: 1)).day;
}
