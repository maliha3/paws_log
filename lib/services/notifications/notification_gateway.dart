import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_actions.dart';

/// The slice of flutter_local_notifications the scheduler depends on.
///
/// Keeping it this narrow is what lets the rolling-window logic be unit
/// tested without the plugin or a device.
abstract interface class NotificationGateway {
  Future<void> cancelAll();

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String eventId,
  });

  /// How many notifications are currently pending with the OS.
  Future<int> pendingCount();
}

/// Talks to the real plugin.
class PluginNotificationGateway implements NotificationGateway {
  PluginNotificationGateway(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'reminders',
    'Care reminders',
    description: 'Vaccines, deworming, flea and tick treatments.',
    importance: Importance.high,
  );

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String eventId,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: when,
    payload: eventId,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        actions: const [
          AndroidNotificationAction(
            NotificationActions.done,
            'Done',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            NotificationActions.snoozeHour,
            'Snooze 1 hour',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            NotificationActions.snoozeTomorrow,
            'Tomorrow',
            showsUserInterface: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        categoryIdentifier: NotificationActions.categoryId,
      ),
    ),
    // Inexact: an exact alarm needs a user-facing permission prompt on
    // Android 14+, and care reminders do not need minute precision.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );

  @override
  Future<int> pendingCount() async =>
      (await _plugin.pendingNotificationRequests()).length;
}

/// Records what would have been scheduled. Used by tests and by any build
/// where notifications are switched off.
@visibleForTesting
class RecordingNotificationGateway implements NotificationGateway {
  final List<({int id, String eventId, tz.TZDateTime when})> scheduled = [];
  int cancelAllCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  @override
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String eventId,
  }) async {
    scheduled.add((id: id, eventId: eventId, when: when));
  }

  @override
  Future<int> pendingCount() async => scheduled.length;
}
