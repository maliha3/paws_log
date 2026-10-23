import 'package:timezone/timezone.dart' as tz;

import '../../core/constants.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/reminder_event_repository.dart';
import '../../domain/schedule_sync.dart';
import 'notification_gateway.dart';
import 'notification_ids.dart';
import 'notification_payload.dart';
import 'notification_window.dart';

/// Keeps the OS's pending notifications in step with the database.
///
/// iOS silently drops pending local notifications past 64, so the whole
/// future is never scheduled. This holds a rolling window of the soonest
/// [budget] items across *both* sources — reminder occurrences and medicine
/// doses — leaving the rest of the cap free for snoozes fired at runtime, and
/// rebuilds it whenever the data moves.
class NotificationScheduler implements ScheduleSync {
  NotificationScheduler({
    required this.gateway,
    required this.events,
    required this.doses,
    this.budget = AppConstants.scheduledNotificationBudget,
    this.reminderFloor = AppConstants.reminderNotificationFloor,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NotificationGateway gateway;
  final ReminderEventRepository events;
  final DoseLogRepository doses;
  final DateTime Function() _clock;

  /// How many of the OS's slots this scheduler will fill.
  final int budget;

  /// How many of those are held for reminder occurrences.
  final int reminderFloor;

  bool _running = false;
  bool _rerunWanted = false;

  /// Rebuilds the whole window.
  ///
  /// Called on launch, on resume, and after any write that moves a due date.
  /// Overlapping calls are coalesced into one more run, so a transaction that
  /// touches several reminders does not rebuild the window several times.
  @override
  Future<void> syncAll() async {
    if (_running) {
      _rerunWanted = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerunWanted = false;
        await _rebuild();
      } while (_rerunWanted);
    } finally {
      _running = false;
    }
  }

  Future<void> _rebuild() async {
    final now = _clock();

    // Each source is asked for a full budget's worth; the window decides how
    // many of each actually make it.
    final upcomingReminders = await events.upcomingForScheduling(
      limit: budget,
      from: now,
    );
    final upcomingDoses = await doses.upcomingForScheduling(
      limit: budget,
      from: now,
    );

    final chosen = selectNotificationWindow(
      budget: budget,
      reminderFloor: reminderFloor,
      reminders: [
        for (final item in upcomingReminders)
          PendingNotification(
            id: item.event.id,
            kind: NotificationKind.reminder,
            fireAt: item.event.notifyAt,
            title: item.reminder.title,
            body: 'Due for ${item.pet.name}',
          ),
      ],
      doses: [
        for (final item in upcomingDoses)
          PendingNotification(
            id: item.dose.id,
            kind: NotificationKind.dose,
            fireAt: item.dose.scheduledFor,
            title: item.medicine.name,
            body: _doseBody(item.medicine.dosage, item.pet.name),
          ),
      ],
    );

    // Cancel everything first: ids are derived from the row they belong to,
    // so there is no list of "what we scheduled last time" to diff against,
    // and a stale notification for a completed occurrence must not survive.
    await gateway.cancelAll();

    for (final item in chosen) {
      await gateway.schedule(
        id: notificationIdFor(item.payload),
        title: item.title,
        body: item.body,
        when: tz.TZDateTime.from(item.fireAt, tz.local),
        payload: item.payload,
        kind: item.kind,
      );
    }
  }

  String _doseBody(String? dosage, String petName) =>
      dosage == null ? 'Dose for $petName' : '$dosage for $petName';
}
