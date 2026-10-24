import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/reminder_event.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/domain/schedule_sync.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late ReminderRepository reminders;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    reminders = ReminderRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  Future<Reminder> addReminder({
    String title = 'Yearly vaccine',
    ReminderCategory category = ReminderCategory.vaccine,
    RepeatRule repeat = const RepeatRule.years(1),
    int dueInDays = 0,
  }) => reminders.create(
    petId: petId,
    title: title,
    category: category,
    repeat: repeat,
    anchorDate: daysFromTodayInTestZone(dueInDays),
    timeOfDayMinutes: 9 * 60,
  );

  Future<void> openReminders(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    await scrollAndTap(tester, find.text('Reminders'));
  }

  testWidgets('the profile counts the active reminders', (tester) async {
    await addReminder();
    await addReminder(title: 'Deworming', category: ReminderCategory.deworming);

    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));

    await scrollIntoView(tester, find.text('2 reminders'));
    expect(find.text('2 reminders'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('an empty list says what reminders are for', (tester) async {
    await openReminders(tester);

    expect(find.textContaining('No reminders yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a reminder can be added after onboarding', (tester) async {
    // The gap this screen exists to close: before it, reminders could only
    // be created during onboarding.
    await openReminders(tester);

    await tapAndSettle(tester, find.byTooltip('Add a reminder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Nail trim',
    );
    await tapAndSettle(tester, find.text('months'));
    await tapAndSettle(tester, find.text('weeks').last);
    await tester.enterText(find.widgetWithText(TextField, 'Every'), '3');
    await scrollAndTap(tester, find.text('Save'));

    final saved = (await db.select(db.reminders).get()).single;
    expect(saved.title, 'Nail trim');
    expect(saved.repeatUnit, RepeatUnit.weeks);
    expect(saved.repeatInterval, 3);
    expect(saved.petId, petId);
    expect(
      await db.select(db.reminderEvents).get(),
      hasLength(1),
      reason: 'a new reminder opens with exactly one pending occurrence',
    );
    expect(find.text('Nail trim'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a second pet can be given its own reminders', (tester) async {
    // Onboarding only ever runs once, so this was impossible before.
    final luna = await PetRepository(db).create(name: 'Luna');
    await addReminder();

    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Luna'));
    await scrollAndTap(tester, find.text('Reminders'));

    expect(find.textContaining('No reminders yet'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Add a reminder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Flea & tick',
    );
    await scrollAndTap(tester, find.text('Save'));

    final lunas = await (db.select(db.reminders)
          ..where((r) => r.petId.equals(luna.id)))
        .get();
    expect(lunas.map((r) => r.title), ['Flea & tick']);

    await disposeTree(tester);
  });

  testWidgets('a reminder shows its schedule and when it is next due', (
    tester,
  ) async {
    await addReminder(
      title: 'Brushing',
      category: ReminderCategory.brushing,
      repeat: const RepeatRule.days(2, seasonal: true),
    );
    await openReminders(tester);

    expect(find.text('Brushing'), findsOneWidget);
    expect(
      find.textContaining('twice as often while shedding'),
      findsOneWidget,
    );
    expect(find.textContaining('due today'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('one that is late reads as overdue', (tester) async {
    await addReminder(dueInDays: -10);
    await openReminders(tester);

    expect(find.textContaining('overdue'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('editing the schedule moves the pending occurrence', (
    tester,
  ) async {
    await addReminder(repeat: const RepeatRule.months(3));
    final before = (await db.select(db.reminderEvents).get()).single;

    await openReminders(tester);
    await tapAndSettle(tester, find.byTooltip('Reminder options'));
    await tapAndSettle(tester, find.text('Edit'));

    await tester.enterText(find.widgetWithText(TextField, 'Every'), '6');
    await scrollAndTap(tester, find.text('Save'));

    final saved = (await db.select(db.reminders).get()).single;
    expect(saved.repeatInterval, 6);
    expect(find.textContaining('Every 6 months'), findsOneWidget);

    final after = (await db.select(db.reminderEvents).get()).single;
    expect(
      after.id,
      before.id,
      reason: 'the occurrence moves rather than being replaced',
    );
    expect(after.status, ReminderEventStatus.pending);
    expect(saved.nextDueAt, after.scheduledFor, reason: 'the two agree');

    await disposeTree(tester);
  });

  testWidgets('editing the title leaves the schedule alone', (tester) async {
    await addReminder();
    final before = (await db.select(db.reminderEvents).get()).single;

    await openReminders(tester);
    await tapAndSettle(tester, find.byTooltip('Reminder options'));
    await tapAndSettle(tester, find.text('Edit'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Annual booster',
    );
    await scrollAndTap(tester, find.text('Save'));

    expect((await db.select(db.reminders).get()).single.title,
        'Annual booster');
    expect(
      (await db.select(db.reminderEvents).get()).single.scheduledFor,
      before.scheduledFor,
    );

    await disposeTree(tester);
  });

  group('pausing', () {
    testWidgets('moves it to its own group and off Today', (tester) async {
      await addReminder();
      await openReminders(tester);

      await tapAndSettle(tester, find.byTooltip('Reminder options'));
      await tapAndSettle(tester, find.text('Pause'));

      expect(find.text('Paused'), findsOneWidget);
      expect(find.textContaining('paused'), findsWidgets);
      expect(
        (await db.select(db.reminders).get()).single.isActive,
        isFalse,
      );

      // Back to Today: a paused reminder is not due.
      await tapAndSettle(tester, find.byTooltip('Back'));
      await tapAndSettle(tester, find.byTooltip('Back'));
      await tapAndSettle(tester, find.text('Today'));
      expect(find.text('Yearly vaccine'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('keeps the reminder and its history', (tester) async {
      await addReminder();
      await openReminders(tester);
      await tapAndSettle(tester, find.byTooltip('Reminder options'));
      await tapAndSettle(tester, find.text('Pause'));

      expect(await db.select(db.reminderEvents).get(), hasLength(1));
      expect(find.text('Yearly vaccine'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('resuming puts it back', (tester) async {
      await addReminder();
      await openReminders(tester);
      await tapAndSettle(tester, find.byTooltip('Reminder options'));
      await tapAndSettle(tester, find.text('Pause'));

      await tapAndSettle(tester, find.byTooltip('Reminder options'));
      await tapAndSettle(tester, find.text('Resume'));

      expect(find.text('Paused'), findsNothing);
      expect((await db.select(db.reminders).get()).single.isActive, isTrue);

      await disposeTree(tester);
    });
  });

  testWidgets('deleting takes the reminder and its occurrences', (
    tester,
  ) async {
    await addReminder();
    await openReminders(tester);

    await tapAndSettle(tester, find.byTooltip('Reminder options'));
    await tapAndSettle(tester, find.text('Delete'));

    expect(await db.select(db.reminders).get(), isEmpty);
    expect(await db.select(db.reminderEvents).get(), isEmpty);
    expect(find.textContaining('No reminders yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('every change rebuilds the notification window', (tester) async {
    // CLAUDE.md's warning: a write that forgets to resync fails silently,
    // and the owner only finds out when a notification never arrives.
    final sync = _RecordingScheduleSync();
    await addReminder();

    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduleSyncProvider.overrideWithValue(sync),
        ],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    await scrollAndTap(tester, find.text('Reminders'));

    sync.calls = 0;
    await tapAndSettle(tester, find.byTooltip('Reminder options'));
    await tapAndSettle(tester, find.text('Pause'));
    expect(sync.calls, greaterThan(0), reason: 'pausing');

    sync.calls = 0;
    await tapAndSettle(tester, find.byTooltip('Reminder options'));
    await tapAndSettle(tester, find.text('Delete'));
    expect(sync.calls, greaterThan(0), reason: 'deleting');

    sync.calls = 0;
    await tapAndSettle(tester, find.byTooltip('Add a reminder'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What is it'),
      'Nail trim',
    );
    await scrollAndTap(tester, find.text('Save'));
    expect(sync.calls, greaterThan(0), reason: 'adding');

    await disposeTree(tester);
  });

  testWidgets('one pet’s reminders are not another’s', (
    tester,
  ) async {
    final luna = await PetRepository(db).create(name: 'Luna');
    await reminders.create(
      petId: luna.id,
      title: 'Luna only',
      category: ReminderCategory.other,
      repeat: const RepeatRule.months(1),
      anchorDate: todayInTestZone(),
      timeOfDayMinutes: 9 * 60,
    );

    await openReminders(tester);

    expect(find.textContaining('No reminders yet'), findsOneWidget);
    expect(find.text('Luna only'), findsNothing);

    await disposeTree(tester);
  });
}

/// Counts resyncs, so a write that forgets one is visible.
class _RecordingScheduleSync implements ScheduleSync {
  int calls = 0;

  @override
  Future<void> syncAll() async => calls++;
}
