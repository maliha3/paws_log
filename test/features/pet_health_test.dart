import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_health_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/domain/models/pet_condition.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetHealthRepository health;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    health = PetHealthRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  Future<void> openPet(WidgetTester tester) async {
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
  }

  Future<void> openHealth(WidgetTester tester) =>
      openMedicalSegment(tester, 'Health');

  testWidgets('an empty health record says what it is for', (tester) async {
    await openPet(tester);
    await openHealth(tester);

    expect(find.textContaining('Nothing recorded'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a condition can be added, with the vet framing shown', (
    tester,
  ) async {
    await openPet(tester);
    await openHealth(tester);

    await tapAndSettle(tester, find.byTooltip('Add to the health record'));
    await tapAndSettle(tester, find.text('Add a condition'));

    expect(find.text('What has your vet diagnosed?'), findsOneWidget);
    expect(
      find.textContaining('never works out a diagnosis of its own'),
      findsOneWidget,
    );
    expect(find.textContaining('Confirm the schedule with your vet'),
        findsOneWidget);

    // The suggestion list fills the field rather than being the only option.
    await scrollAndTap(tester, find.widgetWithText(ActionChip, 'CKD'));
    await scrollAndTap(tester, find.text('Add condition'));

    final saved = (await db.select(db.petConditions).get()).single;
    expect(saved.name, 'CKD');
    expect(saved.status, ConditionStatus.ongoing);
    expect(find.text('CKD'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a condition typed by hand is kept as typed', (tester) async {
    await openPet(tester);
    await openHealth(tester);
    await tapAndSettle(tester, find.byTooltip('Add to the health record'));
    await tapAndSettle(tester, find.text('Add a condition'));

    await tester.enterText(
      find.widgetWithText(TextField, 'Condition'),
      'Megacolon',
    );
    await scrollAndTap(tester, find.text('Add condition'));

    expect((await db.select(db.petConditions).get()).single.name, 'Megacolon');

    await disposeTree(tester);
  });

  testWidgets('a name is required', (tester) async {
    await openPet(tester);
    await openHealth(tester);
    await tapAndSettle(tester, find.byTooltip('Add to the health record'));
    await tapAndSettle(tester, find.text('Add a condition'));

    await scrollAndTap(tester, find.text('Add condition'));

    expect(find.text('A name is needed'), findsOneWidget);
    expect(await db.select(db.petConditions).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('ongoing conditions are listed above past ones', (tester) async {
    await health.addCondition(
      petId: petId,
      name: 'Cat flu',
      status: ConditionStatus.past,
    );
    await health.addCondition(petId: petId, name: 'CKD');

    await openPet(tester);
    await openHealth(tester);

    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
    final ongoing = tester.getTopLeft(find.text('Ongoing')).dy;
    final past = tester.getTopLeft(find.text('Past')).dy;
    expect(ongoing, lessThan(past));

    await disposeTree(tester);
  });

  testWidgets('a condition can be moved to the past and deleted', (
    tester,
  ) async {
    await health.addCondition(petId: petId, name: 'Cat flu');
    await openPet(tester);
    await openHealth(tester);

    await tapAndSettle(tester, find.byTooltip('Condition options'));
    await tapAndSettle(tester, find.text('Move to past'));

    expect(
      (await db.select(db.petConditions).get()).single.status,
      ConditionStatus.past,
    );
    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Ongoing'), findsNothing);

    await tapAndSettle(tester, find.byTooltip('Condition options'));
    await tapAndSettle(tester, find.text('Delete'));

    expect(await db.select(db.petConditions).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('an allergy can be added with its reaction', (tester) async {
    await openPet(tester);
    await openHealth(tester);

    await tapAndSettle(tester, find.byTooltip('Add to the health record'));
    await tapAndSettle(tester, find.text('Add an allergy'));

    await tester.enterText(
      find.widgetWithText(TextField, 'Reacts to'),
      'Chicken',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What happens'),
      'Itching round the ears',
    );
    await scrollAndTap(tester, find.text('Add allergy'));

    final saved = (await db.select(db.petAllergies).get()).single;
    expect(saved.allergen, 'Chicken');
    expect(saved.reaction, 'Itching round the ears');
    expect(find.text('Allergies'), findsWidgets);

    await disposeTree(tester);
  });

  group('the allergy banner', () {
    testWidgets('is absent when there is nothing to say', (tester) async {
      await health.addCondition(petId: petId, name: 'CKD');
      await openPet(tester);

      expect(find.text('Allergy'), findsNothing);
      expect(find.text('Allergies'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('shows every allergen and reaction on the profile', (
      tester,
    ) async {
      await health.addAllergy(
        petId: petId,
        allergen: 'Chicken',
        reaction: 'Itching',
      );
      await health.addAllergy(petId: petId, allergen: 'Fipronil');

      await openPet(tester);

      expect(find.text('Allergies'), findsOneWidget);
      expect(find.text('Chicken (Itching), Fipronil'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('one allergy reads as "Allergy"', (tester) async {
      await health.addAllergy(petId: petId, allergen: 'Chicken');
      await openPet(tester);

      expect(find.text('Allergy'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('tapping it opens the health segment', (tester) async {
      await health.addAllergy(
        petId: petId,
        allergen: 'Chicken',
        reaction: 'Itching',
      );
      await openPet(tester);

      await tapAndSettle(tester, find.text('Chicken (Itching)'));

      expect(find.byTooltip('Add to the health record'), findsOneWidget);
      expect(find.text('Chicken'), findsOneWidget);

      await disposeTree(tester);
    });
  });

  testWidgets('one pet’s health record is not another’s', (
    tester,
  ) async {
    final other = await PetRepository(db).create(name: 'Luna');
    await health.addCondition(petId: other.id, name: 'FIV');
    await health.addAllergy(petId: other.id, allergen: 'Fish');

    await openPet(tester);
    expect(find.text('Allergies'), findsNothing);

    await openHealth(tester);
    expect(find.textContaining('Nothing recorded'), findsOneWidget);
    expect(find.text('FIV'), findsNothing);

    await disposeTree(tester);
  });
}
