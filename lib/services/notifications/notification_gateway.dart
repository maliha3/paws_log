import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_actions.dart';
import 'notification_payload.dart';

/// The slice of flutter_local_notifications the scheduler depends on.
///
/// Keeping it this narrow is what lets the rolling-window logic be unit
/// tested without the plugin or a device.
abstract interface class NotificationGateway {
  Future<void> cancelAll();

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String payload,
    required NotificationKind kind,
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
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String payload,
    required NotificationKind kind,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: when,
    payload: payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        actions: NotificationActions.androidActionsFor(kind),
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: NotificationActions.categoryIdFor(kind),
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
  final List<
    ({
      int id,
      String payload,
      NotificationKind kind,
      tz.TZDateTime when,
      String title,
    })
  >
  scheduled = [];
  int cancelAllCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required String payload,
    required NotificationKind kind,
  }) async {
    scheduled.add((
      id: id,
      payload: payload,
      kind: kind,
      when: when,
      title: title,
    ));
  }

  @override
  Future<int> pendingCount() async => scheduled.length;
}
