import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/reminder_event.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/domain/shedding_season.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late ReminderRepository reminders;
  late ReminderEventRepository events;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() {
    db = memoryDatabase();
    reminders = ReminderRepository(db);
    events = ReminderEventRepository(db);
  });

  /// Created per test rather than in setUp: a database with no pet opens on
  /// onboarding, which is where the reminder sheet lives.
  Future<void> addPet() async {
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  }

  /// A brushing reminder anchored on [anchor], optionally seasonal.
  Future<Reminder> addBrushing({
    required DateTime anchor,
    required bool seasonal,
    int days = 7,
  }) => reminders.create(
    petId: petId,
    title: 'Brushing',
    category: ReminderCategory.brushing,
    repeat: RepeatRule.days(days, seasonal: seasonal),
    anchorDate: anchor,
    timeOfDayMinutes: 9 * 60,
  );

  group('the flag survives the database', () {
    test('a seasonal reminder reads back seasonal', () async {
      await addPet();
      final created = await addBrushing(
        anchor: DateTime.utc(2026, 4, 1),
        seasonal: true,
      );

      final loaded = await reminders.findById(created.id);
      expect(loaded!.repeat.seasonal, isTrue);
      expect(loaded.repeat.halvesInSeason, isTrue);
      expect(loaded.category, ReminderCategory.brushing);
      await db.close();
    });

    test('a plain reminder reads back plain', () async {
      await addPet();
      final created = await addBrushing(
        anchor: DateTime.utc(2026, 4, 1),
        seasonal: false,
      );

      expect((await reminders.findById(created.id))!.repeat.seasonal, isFalse);
      await db.close();
    });
  });

  group('completing one', () {
    /// Marks the reminder's pending event done at [at], and returns the
    /// scheduled instant of whatever opened next.
    Future<DateTime?> completeAt(tz.TZDateTime at) async {
      final event = await db.select(db.reminderEvents).getSingle();
      await events.markDone(event.id, now: at);
      final next = await (db.select(db.reminderEvents)
            ..where((e) => e.status.equalsValue(ReminderEventStatus.pending)))
          .getSingleOrNull();
      return next?.scheduledFor;
    }

    test('halves the gap when it is done during shedding season', () async {
      // April is a shedding window.
      final inSeason = tz.TZDateTime(tz.local, 2026, 4, 10, 9);
      await addPet();
      await addBrushing(anchor: DateTime.utc(2026, 4, 10), seasonal: true);

      final next = await completeAt(inSeason);

      expect(next, isNotNull);
      expect(
        next!.difference(inSeason.toUtc()).inDays,
        3,
        reason: 'seven days becomes three while the cat is shedding',
      );
      await db.close();
    });

    test('keeps the full gap outside it', () async {
      final outOfSeason = tz.TZDateTime(tz.local, 2026, 7, 10, 9);
      await addPet();
      await addBrushing(anchor: DateTime.utc(2026, 7, 10), seasonal: true);

      final next = await completeAt(outOfSeason);

      expect(next!.difference(outOfSeason.toUtc()).inDays, 7);
      await db.close();
    });

    test('a reminder without the flag is unaffected by the season', () async {
      final inSeason = tz.TZDateTime(tz.local, 2026, 4, 10, 9);
      await addPet();
      await addBrushing(anchor: DateTime.utc(2026, 4, 10), seasonal: false);

      final next = await completeAt(inSeason);

      expect(
        next!.difference(inSeason.toUtc()).inDays,
        7,
        reason: 'nothing doubles unless the owner asked for it',
      );
      await db.close();
    });
  });

  group('on screen', () {
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

    testWidgets('a grooming reminder due today shows on Today', (tester) async {
      await addPet();
      await addBrushing(anchor: todayInTestZone(), seasonal: true);
      await reminders.create(
        petId: petId,
        title: 'Nail trim',
        category: ReminderCategory.nailTrim,
        repeat: const RepeatRule.weeks(3),
        anchorDate: todayInTestZone(),
        timeOfDayMinutes: 9 * 60,
      );

      await pumpApp(tester);

      expect(find.text('Brushing'), findsOneWidget);
      expect(find.text('Nail trim'), findsOneWidget);
      expect(find.byIcon(Icons.brush_outlined), findsOneWidget);
      expect(find.byIcon(Icons.content_cut_outlined), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('it can be ticked off from Today like any other', (
      tester,
    ) async {
      await addPet();
      await addBrushing(anchor: todayInTestZone(), seasonal: true);
      await pumpApp(tester);

      await tapAndSettle(tester, find.text('Done'));

      final done = await (db.select(db.reminderEvents)
            ..where((e) => e.status.equalsValue(ReminderEventStatus.done)))
          .get();
      expect(done, hasLength(1));
      expect(find.text('Brushing'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('the shedding switch is offered, and only where it applies', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapAndSettle(tester, find.text('Get started'));
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
      await scrollAndTap(tester, find.text('Continue'));
      await scrollAndTap(tester, find.text('Add a reminder'));

      // Defaults to months, where there is nothing to halve.
      expect(find.text('Shedding season'), findsNothing);

      await tapAndSettle(tester, find.text('months'));
      await tapAndSettle(tester, find.text('weeks').last);

      expect(find.text('Shedding season'), findsOneWidget);
      expect(find.textContaining('twice as often'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('turning it on explains the hemisphere honestly', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapAndSettle(tester, find.text('Get started'));
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
      await scrollAndTap(tester, find.text('Continue'));
      await scrollAndTap(tester, find.text('Add a reminder'));
      await tapAndSettle(tester, find.text('months'));
      await tapAndSettle(tester, find.text('weeks').last);

      await scrollAndTap(tester, find.byType(Switch).last);

      expect(
        find.textContaining('same two months either way'),
        findsOneWidget,
        reason: 'the obvious expectation is that the setting moves the months',
      );
      await scrollAndTap(
        tester,
        find.widgetWithText(ChoiceChip, 'Southern hemisphere'),
      );

      expect(
        await SettingsRepositoryReader(db).hemisphere(),
        Hemisphere.southern,
      );

      await disposeTree(tester);
    });

    testWidgets('a seasonal reminder saved from the sheet keeps the flag', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapAndSettle(tester, find.text('Get started'));
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
      await scrollAndTap(tester, find.text('Continue'));
      await scrollAndTap(tester, find.text('Add a reminder'));
      await tester.enterText(
        find.widgetWithText(TextField, 'What is it'),
        'Brush the ruff',
      );
      await tapAndSettle(tester, find.text('months'));
      await tapAndSettle(tester, find.text('weeks').last);
      await scrollAndTap(tester, find.byType(Switch).last);
      await scrollAndTap(tester, find.text('Save'));

      await scrollIntoView(tester, find.text('Brush the ruff'));
      expect(find.textContaining('twice as often while shedding'), findsWidgets);

      await scrollAndTap(tester, find.textContaining('Finish'));
      await settle(tester);

      final saved = (await db.select(db.reminders).get()).firstWhere(
        (reminder) => reminder.title == 'Brush the ruff',
      );
      expect(saved.seasonal, isTrue);

      await disposeTree(tester);
    });
  });
}

/// Reads settings straight off the database, for asserting on them.
class SettingsRepositoryReader {
  SettingsRepositoryReader(this.db);

  final AppDatabase db;

  Future<Hemisphere> hemisphere() async {
    final row = await (db.select(db.appSettings)
          ..where((setting) => setting.key.equals('hemisphere')))
        .getSingleOrNull();
    return row == null
        ? Hemisphere.northern
        : Hemisphere.fromName(row.value);
  }
}
