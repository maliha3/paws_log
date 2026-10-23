import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/features/weight/weight_chart.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late WeightRepository weights;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    pets = PetRepository(db);
    weights = WeightRepository(db);
    petId = (await pets.create(name: 'Mochi')).id;
  });

  Future<void> addWeighing(int day, int grams) => weights.create(
    petId: petId,
    measuredOn: DateTime.utc(2026, 5, day),
    grams: grams,
  );

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

  testWidgets('with nothing recorded it says so', (tester) async {
    await openPet(tester);

    expect(find.text('Weight'), findsOneWidget);
    expect(find.textContaining('No weighings yet'), findsOneWidget);
    expect(find.byType(WeightChart), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('one weighing shows the number but no trend yet', (tester) async {
    await addWeighing(4, 4200);
    await openPet(tester);

    expect(find.text('4.20'), findsOneWidget);
    expect(find.text('kg'), findsWidgets);
    expect(
      find.textContaining('One more weighing'),
      findsOneWidget,
      reason: 'a line through a single point is not a trend',
    );
    expect(find.byType(WeightChart), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('two weighings draw the chart and the change', (tester) async {
    await addWeighing(4, 4200);
    await addWeighing(20, 4450);
    await openPet(tester);

    expect(find.byType(WeightChart), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget, reason: 'the latest');
    expect(find.textContaining('+0.25 kg'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('switching to pounds reinterprets without rewriting', (
    tester,
  ) async {
    await addWeighing(4, 4200);
    await openPet(tester);
    expect(find.text('4.20'), findsOneWidget);

    await tapAndSettle(tester, find.text('lb'));

    expect(find.text('9.3'), findsOneWidget);
    expect(find.text('4.20'), findsNothing);
    expect(
      (await db.select(db.weightEntries).get()).single.grams,
      4200,
      reason: 'the record is grams either way',
    );

    await disposeTree(tester);
  });

  testWidgets('the chosen unit sticks', (tester) async {
    await addWeighing(4, 4200);
    await openPet(tester);
    await tapAndSettle(tester, find.text('lb'));

    final stored = await db.select(db.appSettings).getSingle();
    expect(stored.key, 'weight_unit');
    expect(stored.value, 'pounds');

    await disposeTree(tester);
  });

  testWidgets('a weighing can be added, in the selected unit', (tester) async {
    await openPet(tester);

    await tapAndSettle(tester, find.byTooltip('Add a weighing'));
    await tester.enterText(find.widgetWithText(TextField, 'Weight'), '4.2');
    await tapAndSettle(tester, find.text('Save'));

    final entry = (await db.select(db.weightEntries).get()).single;
    expect(entry.grams, 4200);
    expect(find.text('4.20'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a weight is required', (tester) async {
    await openPet(tester);

    await tapAndSettle(tester, find.byTooltip('Add a weighing'));
    await tapAndSettle(tester, find.text('Save'));

    expect(find.text('Enter a weight'), findsOneWidget);
    expect(await db.select(db.weightEntries).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('history lists every weighing, newest first', (tester) async {
    await addWeighing(4, 4200);
    await addWeighing(20, 4450);
    await openPet(tester);

    await tapAndSettle(tester, find.text('All 2 weighings'));

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, '4.45 kg');
    expect((tiles.last.title! as Text).data, '4.20 kg');

    await disposeTree(tester);
  });

  test('entries read back oldest first, which is chart order', () async {
    await addWeighing(20, 4450);
    await addWeighing(4, 4200);
    await addWeighing(12, 4300);

    final entries = await weights.watchForPet(petId).first;

    expect(entries.map((e) => e.grams), [4200, 4300, 4450]);
    await db.close();
  });

  test('a weighing can be deleted', () async {
    await addWeighing(4, 4200);
    final entry = (await weights.watchForPet(petId).first).single;

    await weights.delete(entry.id);

    expect(await weights.watchForPet(petId).first, isEmpty);
    await db.close();
  });

  test('deleting a pet cascades to its weighings', () async {
    await addWeighing(4, 4200);

    await pets.delete(petId);

    expect(await db.select(db.weightEntries).get(), isEmpty);
    await db.close();
  });
}
