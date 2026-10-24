import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/vaccination_repository.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late VaccinationRepository records;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    records = VaccinationRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  Future<void> openVaccines(WidgetTester tester) async {
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
    await openMedicalSegment(tester, 'Vaccines');
  }

  testWidgets('one given elsewhere can be recorded by hand', (tester) async {
    // The gap: a shot given at a clinic the app knew nothing about had no
    // way in at all.
    await openVaccines(tester);

    await tapAndSettle(tester, find.byTooltip('Record a vaccination'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Vaccine'),
      'Rabies',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Given at the shelter',
    );
    await scrollAndTap(tester, find.text('Record it'));

    final saved = (await db.select(db.vaccinationRecords).get()).single;
    expect(saved.name, 'Rabies');
    expect(saved.notes, 'Given at the shelter');
    expect(saved.petId, petId);
    expect(
      saved.sourceEventId,
      isNull,
      reason: 'nothing produced it, so nothing can undo it',
    );
    expect(find.text('Rabies'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a name is required', (tester) async {
    await openVaccines(tester);
    await tapAndSettle(tester, find.byTooltip('Record a vaccination'));

    await scrollAndTap(tester, find.text('Record it'));

    expect(find.text('A name is needed'), findsOneWidget);
    expect(await db.select(db.vaccinationRecords).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('a wrong date can be corrected', (tester) async {
    await records.create(
      petId: petId,
      name: 'Yearly vaccine',
      administeredOn: DateTime.utc(2026, 5, 4),
    );
    await openVaccines(tester);

    await tapAndSettle(tester, find.byTooltip('Vaccination options'));
    await tapAndSettle(tester, find.text('Edit'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Vaccine'),
      'Rabies booster',
    );
    await scrollAndTap(tester, find.text('Save'));

    expect(
      (await db.select(db.vaccinationRecords).get()).single.name,
      'Rabies booster',
    );
    expect(find.text('Rabies booster'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('editing an auto-filled record keeps what produced it', (
    tester,
  ) async {
    // Undo of the completion has to be able to find it afterwards.
    await db.into(db.vaccinationRecords).insert(
      VaccinationRecordRow(
        id: 'vax-1',
        petId: petId,
        name: 'Yearly vaccine',
        administeredOn: DateTime.utc(2026, 5, 4),
        sourceEventId: 'event-1',
        createdAt: DateTime.utc(2026, 5, 4, 9),
      ),
    );
    await openVaccines(tester);

    await tapAndSettle(tester, find.byTooltip('Vaccination options'));
    await tapAndSettle(tester, find.text('Edit'));
    expect(
      find.textContaining('Recorded when you marked a reminder done'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Vaccine'),
      'Tricat',
    );
    await scrollAndTap(tester, find.text('Save'));

    final saved = (await db.select(db.vaccinationRecords).get()).single;
    expect(saved.name, 'Tricat');
    expect(saved.sourceEventId, 'event-1');

    await disposeTree(tester);
  });

  testWidgets('a next-due date can be emptied', (tester) async {
    await records.create(
      petId: petId,
      name: 'Yearly vaccine',
      administeredOn: DateTime.utc(2026, 5, 4),
      nextDueOn: DateTime.utc(2027, 5, 4),
    );
    await openVaccines(tester);

    await tapAndSettle(tester, find.byTooltip('Vaccination options'));
    await tapAndSettle(tester, find.text('Edit'));
    await scrollAndTap(tester, find.byTooltip('Clear Next due'));
    await scrollAndTap(tester, find.text('Save'));

    expect(
      (await db.select(db.vaccinationRecords).get()).single.nextDueOn,
      isNull,
      reason: 'copyWith would have read the empty field as "leave it"',
    );

    await disposeTree(tester);
  });

  testWidgets('one recorded in error can be removed', (tester) async {
    await records.create(
      petId: petId,
      name: 'Yearly vaccine',
      administeredOn: DateTime.utc(2026, 5, 4),
    );
    await openVaccines(tester);

    await tapAndSettle(tester, find.byTooltip('Vaccination options'));
    await tapAndSettle(tester, find.text('Delete'));

    expect(await db.select(db.vaccinationRecords).get(), isEmpty);
    expect(find.textContaining('No vaccinations yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the automatic path still works', (tester) async {
    // Adding a button must not have replaced the thing it supplements.
    await openVaccines(tester);
    expect(
      find.textContaining('Marking a vaccine reminder done records it here'),
      findsOneWidget,
    );

    await disposeTree(tester);
  });
}
