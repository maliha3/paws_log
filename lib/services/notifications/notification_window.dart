import 'notification_payload.dart';

/// Chooses which pending notifications get one of the OS's limited slots.
///
/// Time order alone does not work once medicines exist. A twice-daily course
/// produces sixty notifications a month, so filling 56 slots purely by date
/// covers about three weeks and a yearly vaccine never gets scheduled again.
/// [reminderFloor] slots are therefore held for reminder occurrences, which
/// may promote a reminder months out over a dose tomorrow — that is the
/// point.
///
/// Both lists must already be in ascending time order. The result is in
/// ascending time order too.
List<PendingNotification> selectNotificationWindow({
  required List<PendingNotification> reminders,
  required List<PendingNotification> doses,
  required int budget,
  required int reminderFloor,
}) {
  if (budget <= 0) {
    return const [];
  }

  final floor = reminderFloor.clamp(0, budget);
  final held = reminders.take(floor).toList();

  // Everything else competes for what is left, strictly by time.
  final contenders = [...reminders.skip(held.length), ...doses]
    ..sort(_byFireAt);

  final chosen = [...held, ...contenders.take(budget - held.length)]
    ..sort(_byFireAt);
  return chosen;
}

int _byFireAt(PendingNotification a, PendingNotification b) =>
    a.fireAt.compareTo(b.fireAt);
