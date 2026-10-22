import 'package:timezone/timezone.dart' as tz;

import '../../core/constants.dart';
import '../../data/repositories/reminder_event_repository.dart';
import '../../domain/schedule_sync.dart';
import 'notification_gateway.dart';
import 'notification_ids.dart';

/// Keeps the OS's pending notifications in step with the database.
///
/// iOS silently drops pending local notifications past 64, so the whole
/// future is never scheduled. Instead this holds a rolling window of the
/// soonest [budget] occurrences, leaving the rest of the cap free for snoozes
/// fired at runtime, and rebuilds that window whenever the data moves.
class NotificationScheduler implements ScheduleSync {
  NotificationScheduler({
    required this.gateway,
    required this.events,
    this.budget = AppConstants.scheduledNotificationBudget,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NotificationGateway gateway;
  final ReminderEventRepository events;
  final DateTime Function() _clock;

  /// How many of the OS's slots this scheduler will fill.
  final int budget;

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
    final upcoming = await events.upcomingForScheduling(
      limit: budget,
      from: now,
    );

    // Cancel everything first: ids are derived from event ids, so there is no
    // list of "what we scheduled last time" to diff against, and a stale
    // notification for a completed occurrence must not survive.
    await gateway.cancelAll();

    for (final item in upcoming) {
      await gateway.scheduleReminder(
        id: notificationIdFor(item.event.id),
        title: item.reminder.title,
        body: 'Due for ${item.pet.name}',
        when: tz.TZDateTime.from(item.event.notifyAt, tz.local),
        eventId: item.event.id,
      );
    }
  }
}
