/// Dose times for a course written as "n times a day".
///
/// A prescription says how *often*; `Medicine` stores *when*, because actual
/// times are what generate doses and notifications. The conversion lives here
/// so the review screen and its tests agree on one answer.
///
/// Once a day is 09:00: part of breakfast, and late enough not to need an
/// alarm. More than once spreads evenly across the waking day, 08:00 to
/// 20:00 — two at 08:00 and 20:00, three at 08:00, 14:00 and 20:00, four at
/// 08:00, 12:00, 16:00 and 20:00. These are a starting point, not a
/// prescription: the owner can move them afterwards like any medicine.
library;

/// Minutes past midnight, ascending, one per dose.
List<int> doseTimesFor(int timesPerDay) {
  if (timesPerDay <= 1) {
    return const [9 * 60];
  }
  const first = 8 * 60;
  const last = 20 * 60;
  final doses = timesPerDay > maxTimesPerDay ? maxTimesPerDay : timesPerDay;
  final gap = (last - first) / (doses - 1);
  return [for (var dose = 0; dose < doses; dose++) first + (gap * dose).round()];
}

/// Six is every two hours or so across the waking day. Past that a schedule
/// stops being something an owner can keep to, and the parser never offers
/// more.
const int maxTimesPerDay = 6;
