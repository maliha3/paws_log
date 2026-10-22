import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/reminder_event_repository.dart';
import 'notification_actions.dart';
import 'notification_gateway.dart';
import 'notification_scheduler.dart';

/// The plugin instance, shared by the gateway and the launch-time setup.
final notificationPluginProvider = Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => PluginNotificationGateway(ref.watch(notificationPluginProvider)),
);

/// The real scheduler.
///
/// `scheduleSyncProvider` is overridden with this in `main.dart`, which is
/// what connects repository writes to a window rebuild.
final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => NotificationScheduler(
    gateway: ref.watch(notificationGatewayProvider),
    // Its own repository, with no sync hook. Using
    // `reminderEventRepositoryProvider` here would be circular: that one
    // depends on `scheduleSyncProvider`, which resolves to this scheduler.
    // The scheduler only reads, so it does not need the hook.
    events: ReminderEventRepository(ref.watch(appDatabaseProvider)),
  ),
);

/// Initialises the plugin and asks for permission.
///
/// Returns false when the owner declined, in which case reminders are still
/// recorded and still show on Today — they just will not arrive on their own.
Future<bool> initializeNotifications(
  ProviderContainer container, {
  required void Function(NotificationResponse) onForegroundResponse,
}) async {
  final plugin = container.read(notificationPluginProvider);

  await plugin.initialize(
    settings: InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        notificationCategories: [NotificationActions.darwinCategory],
      ),
    ),
    onDidReceiveNotificationResponse: onForegroundResponse,
    onDidReceiveBackgroundNotificationResponse:
        handleBackgroundNotificationAction,
  );

  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android != null) {
    await android.createNotificationChannel(
      PluginNotificationGateway.channel,
    );
    return await android.requestNotificationsPermission() ?? false;
  }

  final ios = plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
      false;
}
