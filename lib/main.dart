import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/time_zone.dart';
import 'data/providers.dart';
import 'services/notifications/notification_actions.dart';
import 'services/notifications/notification_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Recurrence maths and scheduling both run in the device's zone, so this
  // has to settle before the first database read.
  await initializeAppTimeZone();

  final container = ProviderContainer(
    overrides: [
      // This is the wire between a repository write and a rebuilt
      // notification window.
      scheduleSyncProvider.overrideWith(
        (ref) => ref.watch(notificationSchedulerProvider),
      ),
    ],
  );

  await initializeNotifications(
    container,
    onForegroundResponse: (response) {
      // Fire and forget: the repository write resyncs the window, and the
      // streams move Today on their own.
      applyNotificationAction(
        container.read(reminderEventRepositoryProvider),
        response,
      );
    },
  );

  // Catch up on anything that moved while the app was closed.
  await container.read(notificationSchedulerProvider).syncAll();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PawsLogApp(),
    ),
  );
}
