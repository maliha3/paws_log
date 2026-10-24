import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/prescription_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
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

  Future<void> addMedicine(
    String name, {
    required int startsIn,
    int? endsIn,
    bool isActive = true,
  }) async {
    final today = todayInTestZone();
    final medicine = await MedicineRepository(db).create(
      petId: petId,
      name: name,
      schedule: DoseSchedule(
        timesOfDayMinutes: const [9 * 60],
        startDate: today.add(Duration(days: startsIn)),
        endDate: endsIn == null ? null : today.add(Duration(days: endsIn)),
      ),
    );
    if (!isActive) {
      await MedicineRepository(db).setActive(medicine.id, isActive: false);
    }
  }

  testWidgets('the record opens on prescriptions', (tester) async {
    await openPet(tester);
    await scrollAndTap(tester, find.text('Medical record'));

    expect(find.textContaining('No prescriptions yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a prescription is listed with its page count', (tester) async {
    await PrescriptionRepository(db).create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const ['/pages/one.jpg', '/pages/two.jpg'],
      vetName: 'Dr Okafor',
      clinic: 'Riverside Vets',
    );

    await openPet(tester);
    await scrollAndTap(tester, find.text('Medical record'));

    expect(find.text('May 4, 2026'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.textContaining('Dr Okafor'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('one page is not "1 pages"', (tester) async {
    await PrescriptionRepository(db).create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const ['/pages/one.jpg'],
    );

    await openPet(tester);
    await scrollAndTap(tester, find.text('Medical record'));

    expect(find.textContaining('1 page'), findsOneWidget);
    expect(find.textContaining('1 pages'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('medicines split into the ones still being given and the rest', (
    tester,
  ) async {
    await addMedicine('Amoxicillin', startsIn: -2, endsIn: 5);
    await addMedicine('Metacam', startsIn: -20, endsIn: -10);
    await addMedicine('Prednisolone', startsIn: -5, endsIn: 5, isActive: false);

    await openPet(tester);
    await openMedicalSegment(tester, 'Medicines');

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Metacam'), findsOneWidget, reason: 'the course ran out');
    expect(
      find.text('Prednisolone'),
      findsOneWidget,
      reason: 'stopped by hand',
    );

    await disposeTree(tester);
  });

  testWidgets('an open-ended course counts as active', (tester) async {
    await addMedicine('Thyroxine', startsIn: -200);

    await openPet(tester);
    await openMedicalSegment(tester, 'Medicines');

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Past'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('each segment shows only its own records', (tester) async {
    await addMedicine('Amoxicillin', startsIn: -2, endsIn: 5);
    await PrescriptionRepository(db).create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const ['/pages/one.jpg'],
    );

    await openPet(tester);
    await scrollAndTap(tester, find.text('Medical record'));

    expect(find.text('Amoxicillin'), findsNothing);
    await tapAndSettle(tester, find.text('Medicines'));
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('May 4, 2026'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('one pet’s record does not show another’s', (
    tester,
  ) async {
    final other = await PetRepository(db).create(name: 'Luna');
    await PrescriptionRepository(db).create(
      petId: other.id,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const ['/pages/one.jpg'],
      vetName: 'Dr Okafor',
    );

    await openPet(tester);
    await scrollAndTap(tester, find.text('Medical record'));

    expect(find.textContaining('No prescriptions yet'), findsOneWidget);
    expect(find.textContaining('Dr Okafor'), findsNothing);

    await disposeTree(tester);
  });
}
