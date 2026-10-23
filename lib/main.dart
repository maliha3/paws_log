import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/time_zone.dart';
import 'data/providers.dart';
import 'services/maintenance.dart';
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
      container.read(notificationActionHandlerProvider).apply(response);
    },
  );

  // Catch up on everything that moved while the app was closed: doses whose
  // day passed, courses needing more doses generated, and the notification
  // window. Not awaited — nothing on screen depends on it, and it should not
  // hold up first paint.
  unawaited(runMaintenance(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PawsLogApp(),
    ),
  );
}
