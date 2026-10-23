import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/dose_log_repository.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/dose_log.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late MedicineRepository medicines;
  late DoseLogRepository doses;
  late ReminderRepository reminders;
  final petIds = <String, String>{};

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() {
    db = memoryDatabase();
    pets = PetRepository(db);
    medicines = MedicineRepository(db);
    doses = DoseLogRepository(db);
    reminders = ReminderRepository(db);
    petIds.clear();
  });

  Future<String> petId(String name) async =>
      petIds[name] ??= (await pets.create(name: name)).id;

  /// A course whose doses all fall today, at minutes past midnight.
  Future<void> addCourse(
    String petName, {
    required List<int> times,
    String name = 'Amoxicillin',
    String? dosage = '1 tablet',
  }) async {
    await medicines.create(
      petId: await petId(petName),
      name: name,
      dosage: dosage,
      schedule: DoseSchedule(
        timesOfDayMinutes: times,
        startDate: todayInTestZone(),
        endDate: todayInTestZone(),
      ),
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

  testWidgets("Today shows the whole day's course", (tester) async {
    await addCourse('Mochi', times: [1 * 60, 23 * 60]);
    await pumpApp(tester);

    expect(find.text('Medicines'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsNWidgets(2));
    expect(
      find.text('Take'),
      findsNWidgets(2),
      reason: 'including the dose whose time has not come',
    );
    expect(find.textContaining('1 tablet'), findsNWidgets(2));

    await disposeTree(tester);
  });

  testWidgets('a dose and a reminder sit under the same pet', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await reminders.create(
      petId: await petId('Mochi'),
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: todayInTestZone(),
      timeOfDayMinutes: 9 * 60,
    );
    await pumpApp(tester);

    expect(find.text('Mochi'), findsOneWidget, reason: 'one heading');
    expect(find.text('Deworming'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget, reason: 'the reminder');
    expect(find.text('Take'), findsOneWidget, reason: 'the dose');

    await disposeTree(tester);
  });

  testWidgets('tapping Take logs the dose', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Take'));

    expect(find.text('Amoxicillin logged'), findsOneWidget);
    expect(find.text('Take'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    final dose = (await db.select(db.doseLogs).get()).single;
    expect(dose.status, DoseStatus.taken);
    expect(dose.takenAt, isNotNull);

    await disposeTree(tester);
  });

  testWidgets('undo puts a logged dose back', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Take'));
    await tapAndSettle(tester, find.text('Undo'));

    expect(find.text('Take'), findsOneWidget);
    final dose = (await db.select(db.doseLogs).get()).single;
    expect(dose.status, DoseStatus.pending);
    expect(dose.takenAt, isNull);

    await disposeTree(tester);
  });

  testWidgets('a dose can be skipped from the menu', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await pumpApp(tester);

    await tapAndSettle(tester, find.byTooltip('Dose options'));
    await tapAndSettle(tester, find.text('Skip'));

    expect(find.text('Amoxicillin skipped'), findsOneWidget);
    expect(
      (await db.select(db.doseLogs).get()).single.status,
      DoseStatus.skipped,
    );

    await disposeTree(tester);
  });

  testWidgets('a missed dose is called out', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    // Pretend the day is over.
    await doses.markOverdueMissed(
      now: DateTime.now().add(const Duration(days: 1)),
    );
    await pumpApp(tester);

    expect(find.textContaining('Missed'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a stopped course leaves Today', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await pumpApp(tester);
    expect(find.text('Amoxicillin'), findsOneWidget);

    final medicine = (await db.select(db.medicines).get()).single;
    await medicines.setActive(medicine.id, isActive: false);
    await settle(tester);

    expect(find.text('Amoxicillin'), findsNothing);
    expect(find.text('All clear today'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('medicines can be added from a pet', (tester) async {
    await petId('Mochi');
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    expect(find.textContaining('No medicines'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Add a medicine'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Medicine'),
      'Amoxicillin',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Dose'), '1 tablet');
    await tapAndSettle(tester, find.text('Add medicine'));

    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.textContaining('1 tablet'), findsOneWidget);

    final saved = (await db.select(db.medicines).get()).single;
    expect(saved.name, 'Amoxicillin');
    expect(saved.timesOfDayMinutes, [480, 1200], reason: 'the 08:00/20:00 default');
    expect(await db.select(db.doseLogs).get(), isNotEmpty);

    await disposeTree(tester);
  });

  testWidgets('a course can be stopped from the pet screen', (tester) async {
    await addCourse('Mochi', times: [9 * 60]);
    await pumpApp(tester);

    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    await tapAndSettle(tester, find.byTooltip('Medicine options'));
    await tapAndSettle(tester, find.text('Stop course'));

    expect(
      (await db.select(db.medicines).get()).single.isActive,
      isFalse,
    );

    await disposeTree(tester);
  });
}
