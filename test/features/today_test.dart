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

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late ReminderRepository reminders;

  /// Pet ids by name, so a second reminder reuses the same cat.
  ///
  /// Deliberately not a `watchPets()` lookup: awaiting a drift stream inside
  /// a widget-test body deadlocks, because the emission needs the fake clock
  /// to advance and nothing is pumping it.
  final petIds = <String, String>{};

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() {
    db = memoryDatabase();
    pets = PetRepository(db);
    reminders = ReminderRepository(db);
    petIds.clear();
  });

  Future<void> seed({
    required String petName,
    required String title,
    required int dueInDays,
    ReminderCategory category = ReminderCategory.deworming,
  }) async {
    final petId =
        petIds[petName] ??= (await pets.create(name: petName)).id;
    await reminders.create(
      petId: petId,
      title: title,
      category: category,
      repeat: const RepeatRule.months(3),
      anchorDate: daysFromTodayInTestZone(dueInDays),
      timeOfDayMinutes: 9 * 60,
    );
  }

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

  testWidgets('with nothing due it says so', (tester) async {
    await pets.create(name: 'Mochi');
    await pumpApp(tester);

    expect(find.text('Nothing due today'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a reminder due later is not on Today', (tester) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 5);
    await pumpApp(tester);

    expect(find.text('Nothing due today'), findsOneWidget);
    expect(find.text('Deworming'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('due today and overdue show, grouped by pet', (tester) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await seed(
      petName: 'Mochi',
      title: 'Yearly vaccine',
      dueInDays: -10,
      category: ReminderCategory.vaccine,
    );
    await seed(petName: 'Luna', title: 'Flea & tick', dueInDays: 0);
    await pumpApp(tester);

    // One heading per pet.
    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Luna'), findsOneWidget);

    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.text('Flea & tick'), findsOneWidget);

    expect(find.text('1 overdue'), findsOneWidget, reason: 'only Mochi');
    expect(find.textContaining('Overdue by 10 days'), findsOneWidget);
    expect(find.textContaining('Due today at'), findsNWidgets(2));

    await disposeTree(tester);
  });

  testWidgets('overdue items sit above items due today', (tester) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await seed(petName: 'Mochi', title: 'Yearly vaccine', dueInDays: -10);
    await pumpApp(tester);

    final overdue = tester.getTopLeft(find.text('Yearly vaccine')).dy;
    final dueToday = tester.getTopLeft(find.text('Deworming')).dy;
    expect(overdue, lessThan(dueToday));

    await disposeTree(tester);
  });

  testWidgets('one tap on Done clears the row and opens the next', (
    tester,
  ) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await pumpApp(tester);
    expect(find.text('Deworming'), findsOneWidget);

    await tapAndSettle(tester, find.text('Done'));

    expect(find.text('Nothing due today'), findsOneWidget);
    expect(find.text('Deworming done'), findsOneWidget, reason: 'the snackbar');

    final events = await db.select(db.reminderEvents).get();
    expect(events, hasLength(2), reason: 'the closed one and the next');
    expect(
      events.where((e) => e.status == ReminderEventStatus.done),
      hasLength(1),
    );
    expect(
      events.where((e) => e.status == ReminderEventStatus.pending),
      hasLength(1),
    );

    await disposeTree(tester);
  });

  testWidgets('undo puts the row back', (tester) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Done'));
    expect(find.text('Nothing due today'), findsOneWidget);

    await tapAndSettle(tester, find.text('Undo'));

    expect(find.text('Deworming'), findsOneWidget);
    expect(await db.select(db.reminderEvents).get(), hasLength(1));

    await disposeTree(tester);
  });

  testWidgets('snoozing to tomorrow keeps the row on Today', (tester) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await pumpApp(tester);

    await tapAndSettle(tester, find.byTooltip('More'));
    await tapAndSettle(tester, find.text('Snooze to tomorrow'));

    expect(find.text('Deworming'), findsOneWidget);
    expect(find.textContaining('snoozed'), findsOneWidget);

    final event = await db.select(db.reminderEvents).getSingle();
    expect(event.status, ReminderEventStatus.pending);
    expect(event.snoozedUntil, isNotNull);

    await disposeTree(tester);
  });

  testWidgets('skipping clears the row without marking it done', (
    tester,
  ) async {
    await seed(petName: 'Mochi', title: 'Deworming', dueInDays: 0);
    await pumpApp(tester);

    await tapAndSettle(tester, find.byTooltip('More'));
    await tapAndSettle(tester, find.text('Skip'));

    expect(find.text('Nothing due today'), findsOneWidget);
    final events = await db.select(db.reminderEvents).get();
    expect(
      events.where((e) => e.status == ReminderEventStatus.skipped),
      hasLength(1),
    );
    expect(
      events.where((e) => e.status == ReminderEventStatus.done),
      isEmpty,
    );

    await disposeTree(tester);
  });
}
