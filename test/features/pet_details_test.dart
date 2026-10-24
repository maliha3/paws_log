import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
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

  Future<void> openEditor(WidgetTester tester) async {
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
    await tapAndSettle(tester, find.byTooltip('Edit pet'));
  }

  testWidgets('the detail sections start collapsed', (tester) async {
    await pets.create(name: 'Mochi');
    await openEditor(tester);

    await scrollIntoView(tester, find.text('Where they came from'));
    expect(find.text('Where they came from'), findsOneWidget);
    await scrollIntoView(tester, find.text('Food'));
    expect(find.text('Food'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Mother'),
      findsNothing,
      reason: 'expanding the form for everyone would bury the basics',
    );

    await disposeTree(tester);
  });

  testWidgets('background details can be filled in and saved', (tester) async {
    await pets.create(name: 'Mochi');
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Where they came from'));
    await scrollAndTap(tester, find.widgetWithText(ChoiceChip, 'Rescued'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Found behind the bins',
    );
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Mother'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Mother'),
      'Unknown',
    );
    await scrollAndTap(tester, find.text('Save'));

    final pet = (await db.select(db.pets).get()).single;
    expect(pet.origin, PetOrigin.rescued);
    expect(pet.originNotes, 'Found behind the bins');
    expect(pet.motherInfo, 'Unknown');

    await disposeTree(tester);
  });

  testWidgets('food details can be filled in and saved', (tester) async {
    await pets.create(name: 'Mochi');
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Food'));
    await scrollAndTap(tester, find.widgetWithText(ChoiceChip, 'Raw'));
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Brand'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Brand'),
      'Royal Canin',
    );
    await scrollAndTap(tester, find.text('Save'));

    final pet = (await db.select(db.pets).get()).single;
    expect(pet.dietType, DietType.raw);
    expect(pet.foodBrand, 'Royal Canin');

    await disposeTree(tester);
  });

  testWidgets('a chosen chip can be tapped again to clear it', (tester) async {
    await pets.create(name: 'Mochi', origin: PetOrigin.bought);
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Where they came from'));
    await scrollAndTap(tester, find.widgetWithText(ChoiceChip, 'Bought'));
    await scrollAndTap(tester, find.text('Save'));

    expect(
      (await db.select(db.pets).get()).single.origin,
      isNull,
      reason: 'the only way back to "not recorded" once something is picked',
    );

    await disposeTree(tester);
  });

  testWidgets('emptying a detail field clears it', (tester) async {
    await pets.create(
      name: 'Mochi',
      foodBrand: 'Royal Canin',
      feedingNotes: 'Two small meals',
    );
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Food'));
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Brand'));
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), '');
    await scrollAndTap(tester, find.text('Save'));

    final pet = (await db.select(db.pets).get()).single;
    expect(
      pet.foodBrand,
      isNull,
      reason: 'copyWith would have read the empty field as "leave it alone"',
    );
    expect(pet.feedingNotes, 'Two small meals', reason: 'untouched');

    await disposeTree(tester);
  });

  testWidgets('coat length is recorded, and clearable', (tester) async {
    await pets.create(name: 'Mochi');
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Long'));
    await scrollAndTap(tester, find.text('Save'));
    expect((await db.select(db.pets).get()).single.coatLength, CoatLength.long);

    await tapAndSettle(tester, find.byTooltip('Edit pet'));
    await scrollAndTap(tester, find.text('Not sure').last);
    await scrollAndTap(tester, find.text('Save'));
    expect((await db.select(db.pets).get()).single.coatLength, isNull);

    await disposeTree(tester);
  });

  testWidgets('existing details are shown when the editor reopens', (
    tester,
  ) async {
    await pets.create(
      name: 'Mochi',
      origin: PetOrigin.rescued,
      originNotes: 'Found behind the bins',
      dietType: DietType.mixed,
      coatLength: CoatLength.long,
    );
    await openEditor(tester);

    await scrollAndTap(tester, find.text('Where they came from'));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Rescued'))
          .selected,
      isTrue,
    );
    expect(find.text('Found behind the bins'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('onboarding asks for the coat, because grooming needs it', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);

    await tapAndSettle(tester, find.text('Get started'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
    await scrollAndTap(tester, find.text('Long'));
    await scrollAndTap(tester, find.text('Continue'));
    await scrollAndTap(tester, find.textContaining('Finish'));
    await settle(tester);

    expect(
      (await db.select(db.pets).get()).single.coatLength,
      CoatLength.long,
    );

    await disposeTree(tester);
  });
}
