import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/time_zone.dart';
import 'data/providers.dart';
import 'services/entitlements/store_kit_entitlements.dart';
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

  // Ask Apple what this person already owns. Not awaited: the answer arrives
  // on the purchase stream, and the first frame is drawn from the cached
  // entitlement rather than waiting on the network.
  unawaited(_askTheStore(container));

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PawsLogApp(),
    ),
  );
}

/// Replays past purchases, tolerating failure.
///
/// A store that will not answer must not stop the app opening: every feature
/// except buying still works, and the entitlement falls back to the last
/// known state in the settings cache.
Future<void> _askTheStore(ProviderContainer container) async {
  final source = container.read(entitlementSourceProvider);
  if (source is! StoreKitEntitlements) {
    return;
  }
  try {
    await source.start();
  } on Object catch (error) {
    debugPrint('Could not reach the store: $error');
  }
}
