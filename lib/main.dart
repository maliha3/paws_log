import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/purchase_config.dart';
import 'core/time_zone.dart';
import 'data/providers.dart';
import 'services/entitlements/revenuecat_entitlements.dart';
import 'services/maintenance.dart';
import 'services/notifications/notification_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Recurrence maths and scheduling both run in the device's zone, so this
  // has to settle before the first database read.
  await initializeAppTimeZone();

  // Before the first entitlement read. A build with no key skips this and
  // falls back to the stub source, which sells nothing.
  if (PurchaseConfig.hasStoreKeys) {
    await _configurePurchases();
  }

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

/// Starts the purchases SDK, tolerating failure.
///
/// A store that will not configure must not stop the app opening: every
/// feature except buying still works, and the entitlement falls back to the
/// last known state.
Future<void> _configurePurchases() async {
  try {
    await RevenueCatEntitlements.configure(
      apiKey: defaultTargetPlatform == TargetPlatform.android
          ? PurchaseConfig.androidApiKey
          : PurchaseConfig.iosApiKey,
    );
  } on Object catch (error) {
    debugPrint('Could not configure purchases: $error');
  }
}
