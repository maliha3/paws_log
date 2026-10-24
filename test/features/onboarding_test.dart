import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';

import 'package:paws_log/domain/starter_reminders.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() => db = memoryDatabase());

  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
  }

  /// Walks to the starter-reminders screen with a named cat.
  Future<void> reachStarterReminders(
    WidgetTester tester, {
    String name = 'Mochi',
  }) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text('Get started'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tapAndSettle(tester, find.text('Continue'));
  }

  testWidgets('onboarding walks welcome to add-cat to starter reminders', (
    tester,
  ) async {
    await pumpApp(tester);

    // 1 — Welcome.
    expect(find.text('PawsLog'), findsOneWidget);
    await tapAndSettle(tester, find.text('Get started'));

    // 2 — Add the first cat.
    expect(find.text('Add your cat'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Breed'), findsOneWidget);
    expect(find.text('Not sure'), findsWidgets, reason: 'unknowns are allowed');

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
    await tapAndSettle(tester, find.text('Continue'));

    // 3 — Starter reminders, pre-filled and carrying the disclaimer.
    expect(find.text('Starter reminders'), findsOneWidget);
    expect(find.text(AppConstants.vetDisclaimer), findsOneWidget);
    expect(find.textContaining('Mochi'), findsOneWidget);
    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Flea & tick treatment'), findsOneWidget);
    expect(find.textContaining('Every year'), findsOneWidget);
    expect(find.textContaining('Every 3 months'), findsOneWidget);
    expect(find.textContaining('Every month'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the name is required to continue', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text('Get started'));

    await tapAndSettle(tester, find.text('Continue'));

    expect(find.text('A name is needed'), findsOneWidget);
    expect(
      find.text('Starter reminders'),
      findsNothing,
      reason: 'the flow does not advance',
    );

    await disposeTree(tester);
  });

  testWidgets('input survives stepping back', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.text('Get started'));

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
    await tester.enterText(find.widgetWithText(TextField, 'Breed'), 'Ragdoll');
    await tapAndSettle(tester, find.text('Continue'));

    await tester.pageBack();
    await settle(tester);

    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Ragdoll'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('suggestions can be switched off, removed and added', (
    tester,
  ) async {
    await reachStarterReminders(tester);

    await tapAndSettle(tester, find.byType(Switch).first);
    expect(
      tester.widget<Switch>(find.byType(Switch).first).value,
      isFalse,
      reason: 'the suggestion is kept on screen but switched off',
    );

    await tapAndSettle(
      tester,
      find.widgetWithIcon(IconButton, Icons.close).first,
    );
    expect(find.text('Yearly vaccine'), findsNothing);

    // With everything removed, finishing is still allowed. Counted off the
    // list rather than hard-coded, so adding a suggestion does not break it.
    while (find.widgetWithIcon(IconButton, Icons.close).evaluate().isNotEmpty) {
      await tapAndSettle(
        tester,
        find.widgetWithIcon(IconButton, Icons.close).first,
      );
    }
    expect(find.text('Finish without reminders'), findsOneWidget);

    // And one can be added back.
    await tapAndSettle(tester, find.text('Add a reminder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Claw check',
    );
    await scrollAndTap(tester, find.text('Save'));
    expect(find.text('Claw check'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('finishing saves the cat and its reminders', (tester) async {
    await reachStarterReminders(tester);

    await tapAndSettle(tester, find.text('Finish'));

    final pets = await db.select(db.pets).get();
    expect(pets, hasLength(1));
    expect(pets.single.name, 'Mochi');

    final suggested = starterReminderDrafts().length;
    final reminders = await db.select(db.reminders).get();
    expect(reminders, hasLength(suggested));
    expect(
      reminders.map((reminder) => reminder.title),
      containsAll(['Yearly vaccine', 'Nail trim', 'Brushing']),
    );
    // Every reminder opens with exactly one pending occurrence.
    expect(await db.select(db.reminderEvents).get(), hasLength(suggested));

    // Onboarding is behind us, so the root shows Today.
    expect(find.text('Today'), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('a suggestion switched off is not saved', (tester) async {
    await reachStarterReminders(tester);

    await tapAndSettle(tester, find.byType(Switch).first);
    await tapAndSettle(tester, find.text('Finish'));

    final reminders = await db.select(db.reminders).get();
    expect(reminders, hasLength(starterReminderDrafts().length - 1));
    expect(
      reminders.map((reminder) => reminder.title),
      isNot(contains('Yearly vaccine')),
    );

    await disposeTree(tester);
  });
}
