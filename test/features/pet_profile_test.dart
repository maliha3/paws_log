import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/pet.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() {
    db = memoryDatabase();
    pets = PetRepository(db);
  });

  Future<void> openPets(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
  }

  testWidgets('the profile gathers everything about one pet', (tester) async {
    final pet = await pets.create(
      name: 'Mochi',
      breed: 'Ragdoll',
      sex: PetSex.female,
      neutered: true,
      birthday: DateTime.utc(DateTime.now().year - 3, 1, 1),
    );
    await WeightRepository(db).create(
      petId: pet.id,
      measuredOn: DateTime.utc(2026, 5, 4),
      grams: 4200,
    );
    await MedicineRepository(db).create(
      petId: pet.id,
      name: 'Amoxicillin',
      schedule: DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: DateTime.utc(2026, 5, 4),
        endDate: DateTime.utc(2026, 5, 6),
      ),
    );

    await openPets(tester);
    await tapAndSettle(tester, find.text('Mochi'));

    expect(find.textContaining('Ragdoll'), findsOneWidget);
    expect(find.textContaining('Female'), findsOneWidget);
    expect(find.textContaining('3 yrs'), findsOneWidget);

    // The profile holds who the cat is and the weight trend; the four kinds
    // of medical record sit one tap behind it.
    for (final section in ['Medical record', 'Weight']) {
      await scrollIntoView(tester, find.text(section));
      expect(find.text(section), findsOneWidget, reason: section);
    }
    await scrollIntoView(tester, find.text('4.20'));
    expect(find.text('4.20'), findsOneWidget);

    await openMedicalSegment(tester, 'Medicines');
    expect(find.text('Amoxicillin'), findsOneWidget);
    // The course ran for two days in May 2026, so it is over.
    expect(find.text('Past'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a second pet can be added', (tester) async {
    await pets.create(name: 'Mochi');
    // Past the first pet this is a paid feature; the gate itself is covered
    // in premium_gate_test.dart.
    await SettingsRepository(db).setPremium(value: true);
    await openPets(tester);

    await tapAndSettle(tester, find.text('Add a pet'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Luna');
    await tester.enterText(find.widgetWithText(TextField, 'Breed'), 'Tabby');
    await tapAndSettle(tester, find.text('Add pet'));

    expect(find.text('Mochi'), findsOneWidget);
    expect(find.text('Luna'), findsOneWidget);
    expect(await db.select(db.pets).get(), hasLength(2));

    await disposeTree(tester);
  });

  testWidgets('a name is required to add a pet', (tester) async {
    await pets.create(name: 'Mochi');
    await SettingsRepository(db).setPremium(value: true);
    await openPets(tester);

    await tapAndSettle(tester, find.text('Add a pet'));
    await tapAndSettle(tester, find.text('Add pet'));

    expect(find.text('A name is needed'), findsOneWidget);
    expect(await db.select(db.pets).get(), hasLength(1));

    await disposeTree(tester);
  });

  testWidgets('a pet can be edited', (tester) async {
    await pets.create(name: 'Mochi', breed: 'Ragdoll');
    await openPets(tester);
    await tapAndSettle(tester, find.text('Mochi'));

    await tapAndSettle(tester, find.byTooltip('Edit pet'));
    await tester.enterText(find.widgetWithText(TextField, 'Breed'), 'Birman');
    await tapAndSettle(tester, find.text('Save'));

    expect(find.textContaining('Birman'), findsOneWidget);
    expect((await db.select(db.pets).get()).single.breed, 'Birman');

    await disposeTree(tester);
  });

  testWidgets('archiving takes a pet off the list but keeps the data', (
    tester,
  ) async {
    final pet = await pets.create(name: 'Mochi');
    await WeightRepository(db).create(
      petId: pet.id,
      measuredOn: DateTime.utc(2026, 5, 4),
      grams: 4200,
    );
    await openPets(tester);
    await tapAndSettle(tester, find.text('Mochi'));

    await tapAndSettle(tester, find.byTooltip('Pet options'));
    await tapAndSettle(tester, find.text('Archive'));

    expect(find.text('Mochi'), findsNothing);
    expect(
      (await db.select(db.pets).get()).single.archivedAt,
      isNotNull,
      reason: 'the row stays',
    );
    expect(
      await db.select(db.weightEntries).get(),
      hasLength(1),
      reason: 'and so does the history',
    );

    await disposeTree(tester);
  });

  testWidgets('deleting a pet takes everything with it', (tester) async {
    final pet = await pets.create(name: 'Mochi');
    await WeightRepository(db).create(
      petId: pet.id,
      measuredOn: DateTime.utc(2026, 5, 4),
      grams: 4200,
    );
    await openPets(tester);
    await tapAndSettle(tester, find.text('Mochi'));

    await tapAndSettle(tester, find.byTooltip('Pet options'));
    await tapAndSettle(tester, find.text('Delete everything'));

    expect(await db.select(db.pets).get(), isEmpty);
    expect(await db.select(db.weightEntries).get(), isEmpty);

    await disposeTree(tester);
  });
}
