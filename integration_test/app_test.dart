import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/main.dart' as app;

/// Drives the real app on a device or simulator.
///
/// This is the only place the real plugin stack runs: the native sqlite
/// build, path_provider's documents directory, the device timezone lookup,
/// and flutter_local_notifications actually handing requests to the OS. The
/// unit and widget tests stub or skip all four.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps real frames until [condition] holds, or fails after [timeout].
  ///
  /// `pumpAndSettle` is no use here for the same reason it is no use in the
  /// widget tests: the root shows an indeterminate spinner while the first
  /// database read is in flight, and that never settles.
  Future<void> pumpUntil(
    WidgetTester tester,
    String what,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (condition()) {
        return;
      }
    }
    fail('Timed out waiting for $what');
  }

  Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('onboarding through to Today, on the real stack', (
    tester,
  ) async {
    app.main();

    // 1 — Welcome. Reaching it at all proves the launch sequence works:
    // the timezone database loaded, the notification plugin initialised, and
    // sqlite opened a real file under the documents directory.
    await pumpUntil(
      tester,
      'the welcome screen',
      () => find.text('Get started').evaluate().isNotEmpty,
    );
    expect(find.text('PawsLog'), findsOneWidget);

    // 2 — Add the cat.
    await tapAndPump(tester, find.text('Get started'));
    expect(find.text('Add your cat'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
    await tapAndPump(tester, find.text('Continue'));

    // 3 — Starter reminders.
    expect(find.text('Starter reminders'), findsOneWidget);
    expect(find.text(AppConstants.vetDisclaimer), findsOneWidget);
    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Flea & tick treatment'), findsOneWidget);

    await tapAndPump(tester, find.text('Finish'));

    // 4 — Today, written to and read back from a real sqlite file.
    await pumpUntil(
      tester,
      'the Today screen',
      () => find.text('Today').evaluate().isNotEmpty,
    );
    expect(find.text('Mochi'), findsOneWidget, reason: 'grouped by pet');
    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.text('Flea & tick treatment'), findsOneWidget);

    // 5 — Done, which closes the occurrence and opens the next one three
    // months out. That next one is in the future, so unlike today's
    // already-passed 09:00 items it is something the scheduler can hand to
    // the OS.
    final plugin = FlutterLocalNotificationsPlugin();
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    // Provisional authorisation is granted without a dialog — notifications
    // are delivered quietly to Notification Centre. That is what lets this
    // test verify the OS really accepts the scheduled requests; an
    // unauthorised app has `zonedSchedule` rejected and would show nothing
    // pending whether or not the scheduler worked.
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        provisional: true,
      );
      final permissions = await ios.checkPermissions();
      // `isEnabled` reports full authorisation only, so it stays false under
      // provisional auth. The real check is whether the OS accepts the
      // scheduled requests below.
      debugPrint(
        'NOTIFICATION PERMISSIONS: granted=$granted '
        'isEnabled=${permissions?.isEnabled} '
        'alert=${permissions?.isAlertEnabled}',
      );
    }

    final before = await plugin.pendingNotificationRequests();

    // Rows due at the same time have no guaranteed order, so this counts
    // them rather than naming the one it expects to go.
    final rowsBefore = find.text('Done').evaluate().length;
    expect(rowsBefore, 3);

    await tapAndPump(tester, find.text('Done').first);
    await pumpUntil(
      tester,
      'a row to clear',
      () => find.text('Done').evaluate().length < rowsBefore,
    );
    expect(find.text('Undo'), findsOneWidget, reason: 'the undo snackbar');

    final after = await plugin.pendingNotificationRequests();
    debugPrint('PENDING NOTIFICATIONS: ${before.length} -> ${after.length}');
    for (final request in after) {
      debugPrint('  #${request.id} ${request.title} / ${request.body}');
    }

    expect(
      after.length,
      greaterThan(before.length),
      reason: 'completing one opens a future occurrence, which gets scheduled',
    );
    expect(
      after.length,
      lessThanOrEqualTo(AppConstants.iosPendingNotificationLimit),
    );

    // Optionally hold the final frame so a screenshot can be taken from
    // outside; the test tears the app down as soon as it returns.
    const holdSeconds = int.fromEnvironment('PAWSLOG_HOLD_SECONDS');
    for (var tick = 0; tick < holdSeconds * 10; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
