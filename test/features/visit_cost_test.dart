import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/core/money.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late VetVisitRepository visits;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    visits = VetVisitRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  Future<void> openVisits(WidgetTester tester) async {
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
    await openMedicalSegment(tester, 'Vet visits');
  }

  group('what it costs', () {
    test('an amount round-trips through the smallest unit', () {
      final units = Money.minorUnits('en_GB');
      expect(Money.parse('42.50', 'en_GB'), 42.5 * units);
      expect(Money.format(4250, 'en_GB'), contains('42.50'));
      expect(Money.edit(4250, 'en_GB'), '42.50');
    });

    test('a comma is read as a decimal point', () {
      // A field prefixed with a currency symbol is obviously money, and
      // refusing "42,50" from a comma keyboard would be pedantry.
      expect(Money.parse('42,50', 'en_GB'), Money.parse('42.50', 'en_GB'));
    });

    test('a currency with no minor unit is not forced to have one', () {
      expect(Money.minorUnits('ja_JP'), 1);
      expect(Money.edit(4250, 'ja_JP'), '4250');
    });

    test('nonsense is not an amount', () {
      expect(Money.parse('', 'en_GB'), isNull);
      expect(Money.parse('free', 'en_GB'), isNull);
      expect(Money.parse('-5', 'en_GB'), isNull);
    });
  });

  testWidgets('a cost can be recorded with a visit', (tester) async {
    await openVisits(tester);

    await tapAndSettle(tester, find.byTooltip('Add a vet visit'));
    await tester.enterText(
      find.widgetWithText(TextField, 'What was it for'),
      'Annual checkup',
    );
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Cost'));
    await tester.enterText(find.widgetWithText(TextField, 'Cost'), '42.50');
    await scrollAndTap(tester, find.text('Add visit'));

    final saved = (await db.select(db.vetVisits).get()).single;
    expect(saved.cost, isNotNull);
    expect(Money.edit(saved.cost!), '42.50');
    expect(find.textContaining('42.50'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a visit with no cost recorded shows none', (tester) async {
    await visits.create(
      petId: petId,
      visitedOn: DateTime.utc(2026, 5, 4),
      reason: 'Annual checkup',
    );
    await openVisits(tester);

    expect((await db.select(db.vetVisits).get()).single.cost, isNull);
    expect(
      find.textContaining(Money.symbol()),
      findsNothing,
      reason: 'not recorded is not the same as free',
    );

    await disposeTree(tester);
  });

  testWidgets('a cost can be cleared again', (tester) async {
    await visits.create(
      petId: petId,
      visitedOn: DateTime.utc(2026, 5, 4),
      reason: 'Annual checkup',
      cost: 4250,
    );
    await openVisits(tester);

    await tapAndSettle(tester, find.text('Annual checkup'));
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Cost'));
    await tester.enterText(find.widgetWithText(TextField, 'Cost'), '');
    await scrollAndTap(tester, find.text('Save'));

    expect(
      (await db.select(db.vetVisits).get()).single.cost,
      isNull,
      reason: 'copyWith would have read the empty field as "leave it"',
    );

    await disposeTree(tester);
  });

  testWidgets('the vet practice is on the profile, with a way to ring it', (
    tester,
  ) async {
    await PetRepository(db).update(
      (await PetRepository(db).findById(petId))!.copyWith(
        vetName: 'Riverside Vets',
        vetPhone: '01234 567890',
      ),
    );

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

    await scrollIntoView(tester, find.text('Riverside Vets'));
    expect(find.text('01234 567890'), findsOneWidget);
    expect(find.byTooltip('Call the vet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a pet with no vet recorded gets no card', (tester) async {
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

    expect(find.byTooltip('Call the vet'), findsNothing);

    await disposeTree(tester);
  });
}
