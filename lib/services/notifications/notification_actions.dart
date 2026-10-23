import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/time_zone.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/reminder_event_repository.dart';
import 'notification_payload.dart';

/// Identifiers for the buttons on a reminder notification.
///
/// These strings cross a process boundary — a notification scheduled by an
/// old build can be acted on by a new one — so they are never renamed.
abstract final class NotificationActions {
  static const String categoryId = 'reminder';
  static const String doseCategoryId = 'dose';

  static const String done = 'done';
  static const String snoozeHour = 'snooze_hour';
  static const String snoozeTomorrow = 'snooze_tomorrow';
  static const String taken = 'taken';
  static const String skip = 'skip';

  static String categoryIdFor(NotificationKind kind) => switch (kind) {
    NotificationKind.reminder => categoryId,
    NotificationKind.dose => doseCategoryId,
  };

  /// The iOS categories. Not const: `DarwinNotificationAction.plain` is a
  /// factory.
  static final DarwinNotificationCategory darwinCategory =
      DarwinNotificationCategory(
        categoryId,
        actions: [
          DarwinNotificationAction.plain(done, 'Done'),
          DarwinNotificationAction.plain(snoozeHour, 'Snooze 1 hour'),
          DarwinNotificationAction.plain(snoozeTomorrow, 'Tomorrow'),
        ],
      );

  /// A dose is taken or it is not. Snoozing it to tomorrow would mean
  /// skipping it, which is a different answer and has its own button.
  static final DarwinNotificationCategory doseDarwinCategory =
      DarwinNotificationCategory(
        doseCategoryId,
        actions: [
          DarwinNotificationAction.plain(taken, 'Taken'),
          DarwinNotificationAction.plain(skip, 'Skip'),
        ],
      );

  static List<DarwinNotificationCategory> get allDarwinCategories => [
    darwinCategory,
    doseDarwinCategory,
  ];

  static List<AndroidNotificationAction> androidActionsFor(
    NotificationKind kind,
  ) => switch (kind) {
    NotificationKind.reminder => const [
      AndroidNotificationAction(done, 'Done', showsUserInterface: false),
      AndroidNotificationAction(
        snoozeHour,
        'Snooze 1 hour',
        showsUserInterface: false,
      ),
      AndroidNotificationAction(
        snoozeTomorrow,
        'Tomorrow',
        showsUserInterface: false,
      ),
    ],
    NotificationKind.dose => const [
      AndroidNotificationAction(taken, 'Taken', showsUserInterface: false),
      AndroidNotificationAction(skip, 'Skip', showsUserInterface: false),
    ],
  };
}

/// Applies a notification button press to the database.
///
/// Shared by the foreground and background handlers so an action means the
/// same thing whether or not the app happened to be open.
class NotificationActionHandler {
  const NotificationActionHandler({required this.events, required this.doses});

  final ReminderEventRepository events;
  final DoseLogRepository doses;

  /// [now] is injectable so this is testable at a fixed instant; production
  /// leaves it unset and the repositories use the wall clock.
  Future<void> apply(NotificationResponse response, {DateTime? now}) async {
    final target = NotificationKind.decode(response.payload);
    if (target == null) {
      return;
    }
    switch ((target.kind, response.actionId)) {
      case (NotificationKind.reminder, NotificationActions.done):
        await events.markDone(target.id, now: now);
      case (NotificationKind.reminder, NotificationActions.snoozeHour):
        await events.snoozeOneHour(target.id, now: now);
      case (NotificationKind.reminder, NotificationActions.snoozeTomorrow):
        await events.snoozeToTomorrow(target.id, now: now);
      case (NotificationKind.dose, NotificationActions.taken):
        await doses.logTaken(target.id, now: now);
      case (NotificationKind.dose, NotificationActions.skip):
        await doses.skip(target.id, now: now);
      default:
        // A plain tap on the notification body just opens the app, and an
        // action that does not belong to its kind is ignored.
        break;
    }
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
    await NotificationActionHandler(
      events: ReminderEventRepository(db),
      doses: DoseLogRepository(db),
    ).apply(response);
  } finally {
    await db.close();
  }
}
