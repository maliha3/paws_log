import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/domain/starter_reminders.dart';
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

  /// Scrolls a lazy list until [finder] matches, if it does not already.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
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

    // 3 — Starter reminders, including the two grooming ones.
    expect(find.text('Starter reminders'), findsOneWidget);
    expect(find.text(AppConstants.vetDisclaimer), findsOneWidget);
    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Flea & tick treatment'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Brushing'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nail trim'), findsOneWidget);

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
    expect(
      rowsBefore,
      starterReminderDrafts().length,
      reason: 'every suggestion opens due today',
    );

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

    // 6 — The Phase 2 screens, on the real stack: a second tab, a profile
    // that gathers everything, and a weighing written through the real
    // sqlite file.
    await tapAndPump(tester, find.text('Pets'));
    expect(find.text('Mochi'), findsWidgets);
    await tapAndPump(tester, find.text('Mochi').last);

    // The profile is the way in to everything else.
    for (final card in ['Reminders', 'Medical record', 'Photos', 'Weight']) {
      await scrollTo(tester, find.text(card));
      expect(find.text(card), findsOneWidget, reason: card);
    }

    await scrollTo(tester, find.byTooltip('Add a weighing'));
    await tapAndPump(tester, find.byTooltip('Add a weighing'));
    await tester.enterText(find.widgetWithText(TextField, 'Weight'), '4.2');
    await tapAndPump(tester, find.text('Save'));
    expect(find.text('4.20'), findsOneWidget);

    // 7 — The medical record, five segments behind one card.
    await scrollTo(tester, find.text('Medical record'));
    await tapAndPump(tester, find.text('Medical record'));
    expect(find.textContaining('No prescriptions yet'), findsOneWidget);

    await tapAndPump(tester, find.text('Vaccines'));
    expect(
      find.text('Yearly vaccine'),
      findsOneWidget,
      reason: 'completing it earlier filled in the vaccination history',
    );

    await tapAndPump(tester, find.text('Health'));
    await tapAndPump(tester, find.byTooltip('Add to the health record'));
    await tapAndPump(tester, find.text('Add an allergy'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Reacts to'),
      'Chicken',
    );
    await scrollTo(tester, find.text('Add allergy'));
    await tapAndPump(tester, find.text('Add allergy'));
    expect(find.text('Chicken'), findsOneWidget);

    await tapAndPump(tester, find.byTooltip('Back'));

    // The allergy shows on the profile, which is the point of recording it.
    await pumpUntil(
      tester,
      'the allergy banner',
      () => find.text('Allergy').evaluate().isNotEmpty,
    );

    // 8 — Reminders, which before this could only be made in onboarding.
    await scrollTo(tester, find.text('Reminders'));
    await tapAndPump(tester, find.text('Reminders'));
    expect(find.text('Brushing'), findsOneWidget);
    expect(find.text('Nail trim'), findsOneWidget);

    await tapAndPump(tester, find.byTooltip('Add a reminder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Ear check',
    );
    await scrollTo(tester, find.text('Save'));
    await tapAndPump(tester, find.text('Save'));
    expect(find.text('Ear check'), findsOneWidget);

    // Pausing it takes it off Today, through the real database.
    await tapAndPump(tester, find.byTooltip('Reminder options').first);
    await tapAndPump(tester, find.text('Pause'));
    expect(find.text('Paused'), findsOneWidget);

    // Optionally hold the final frame so a screenshot can be taken from
    // outside; the test tears the app down as soon as it returns.
    const holdSeconds = int.fromEnvironment('PAWSLOG_HOLD_SECONDS');
    for (var tick = 0; tick < holdSeconds * 10; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
