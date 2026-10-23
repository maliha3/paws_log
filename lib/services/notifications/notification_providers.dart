import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/dose_log_repository.dart';
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
    doses: DoseLogRepository(ref.watch(appDatabaseProvider)),
  ),
);

/// Applies notification button presses while the app is running.
final notificationActionHandlerProvider = Provider<NotificationActionHandler>(
  (ref) => NotificationActionHandler(
    events: ref.watch(reminderEventRepositoryProvider),
    doses: ref.watch(doseLogRepositoryProvider),
  ),
);

/// Sets up the plugin, without asking for permission.
///
/// Permission is deliberately not requested here. `DarwinInitializationSettings`
/// defaults its three `request*Permission` flags to true, and `initialize`
/// then waits for the owner to answer a system dialog — which on a cold first
/// launch happens *before* `runApp`, so they are left looking at their home
/// screen with a prompt over it. The flags are off and
/// [requestNotificationPermission] is called later, from inside the app.
Future<void> initializeNotifications(
  ProviderContainer container, {
  required void Function(NotificationResponse) onForegroundResponse,
}) async {
  final plugin = container.read(notificationPluginProvider);

  await plugin.initialize(
    settings: InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: NotificationActions.allDarwinCategories,
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
  await android?.createNotificationChannel(PluginNotificationGateway.channel);
}

/// Asks the owner to allow notifications.
///
/// Called once the first schedule has been set up, so the prompt arrives with
/// some context rather than over a home screen. Returns false when they
/// decline, in which case reminders are still recorded and still show on
/// Today — they just will not arrive on their own.
Future<bool> requestNotificationPermission(
  FlutterLocalNotificationsPlugin plugin,
) async {
  try {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  } on Object catch (error) {
    // Asking is a courtesy, not a step onboarding depends on. A platform
    // that cannot answer — a widget test, an unsupported target — must not
    // take the owner's first save down with it.
    debugPrint('Could not request notification permission: $error');
    return false;
  }
}
