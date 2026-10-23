/// Shared setup for widget tests that touch the database.
///
/// Two things about drift under `testWidgets` are worth knowing before
/// writing one of these, because both present as a hang rather than a
/// failure:
///
/// 1. Cancelling a drift query stream schedules a zero-duration timer. The
///    cancel happens when `ProviderScope` is disposed, which for a widget
///    test is during teardown — after the fake clock has stopped. The test
///    then fails with "a Timer is still pending". Call [disposeTree] at the
///    end of the test body so the cancel, and the timer it schedules, both
///    happen while the clock is still running.
///
/// 2. `AppDatabase.close()` waits on work that also needs the fake clock to
///    advance, so awaiting it inside a test body deadlocks. Don't close an
///    in-memory database in a widget test; it goes away with the process.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The zone widget tests run in. It has DST, so wall-clock handling is
/// exercised rather than assumed.
const String testZoneName = 'America/New_York';

/// Loads the timezone database and pins the app's zone.
void initializeTestTimeZone() {
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(testZoneName));

  // Each test builds its own database and never closes it (see above), so
  // drift's "created multiple times" warning is expected here. The instances
  // have separate in-memory executors, so there is no race to warn about.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// Sizes the test surface like a phone.
///
/// The 800x600 default is shorter than a real device, which pushes the bottom
/// of a form off-screen and makes buttons unfindable for reasons that have
/// nothing to do with the code under test.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Scrolls a lazy list until [finder] exists, then taps it.
///
/// `tapAndSettle` alone is not enough for anything below the fold: a
/// `ListView` does not build its off-screen children, so the finder matches
/// nothing and there is no widget for `ensureVisible` to scroll to. At large
/// text sizes much more of a screen sits below the fold.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await scrollIntoView(tester, finder);
  await tapAndSettle(tester, finder);
}

/// Scrolls a lazy list until [finder] matches something, if it does not
/// already. Safe to call when the widget is on screen, or has no scrollable.
Future<void> scrollIntoView(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

/// Scrolls [finder] into view if needed, then taps it.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// A fresh, empty database for one test.
AppDatabase memoryDatabase() => AppDatabase.forTesting(NativeDatabase.memory());

/// Pumps a fixed number of frames.
///
/// `pumpAndSettle` is unusable on screens that show a
/// [CircularProgressIndicator] — an indeterminate spinner never settles — and
/// the root shows one while the first database read is in flight.
Future<void> settle(WidgetTester tester, {int frames = 20}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the widget tree and lets drift's stream cleanup finish.
///
/// Call this at the end of any widget test that watched a query stream.
Future<void> disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
}
