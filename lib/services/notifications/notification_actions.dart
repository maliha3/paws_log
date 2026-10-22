import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/time_zone.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/reminder_event_repository.dart';

/// Identifiers for the buttons on a reminder notification.
///
/// These strings cross a process boundary — a notification scheduled by an
/// old build can be acted on by a new one — so they are never renamed.
abstract final class NotificationActions {
  static const String categoryId = 'reminder';
  static const String done = 'done';
  static const String snoozeHour = 'snooze_hour';
  static const String snoozeTomorrow = 'snooze_tomorrow';

  /// The iOS category carrying the three buttons.
  ///
  /// Not const: `DarwinNotificationAction.plain` is a factory.
  static final DarwinNotificationCategory darwinCategory =
      DarwinNotificationCategory(
        categoryId,
        actions: [
          DarwinNotificationAction.plain(done, 'Done'),
          DarwinNotificationAction.plain(snoozeHour, 'Snooze 1 hour'),
          DarwinNotificationAction.plain(snoozeTomorrow, 'Tomorrow'),
        ],
      );
}

/// Applies a notification button press to the database.
///
/// Shared by the foreground and background handlers so an action means the
/// same thing whether or not the app happened to be open.
/// [now] is injectable so this is testable at a fixed instant; production
/// leaves it unset and the repository uses the wall clock.
Future<void> applyNotificationAction(
  ReminderEventRepository events,
  NotificationResponse response, {
  DateTime? now,
}) async {
  final eventId = response.payload;
  if (eventId == null || eventId.isEmpty) {
    return;
  }
  switch (response.actionId) {
    case NotificationActions.done:
      await events.markDone(eventId, now: now);
    case NotificationActions.snoozeHour:
      await events.snoozeOneHour(eventId, now: now);
    case NotificationActions.snoozeTomorrow:
      await events.snoozeToTomorrow(eventId, now: now);
    default:
      // A plain tap on the notification body just opens the app.
      break;
  }
}

/// Handles a button press while the app is not running.
///
/// This runs on a background isolate with nothing set up, so the timezone
/// database, the plugin registrant and a database connection all have to be
/// established here. The connection is separate from the UI isolate's, which
/// is why sqlite is left to arbitrate rather than any in-process lock.
@pragma('vm:entry-point')
Future<void> handleBackgroundNotificationAction(
  NotificationResponse response,
) async {
  if (response.actionId == null) {
    return;
  }
  DartPluginRegistrant.ensureInitialized();
  await initializeAppTimeZone();

  final db = AppDatabase();
  try {
    await applyNotificationAction(ReminderEventRepository(db), response);
  } finally {
    await db.close();
  }
}
