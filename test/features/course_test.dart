import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/dose_log_repository.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/domain/models/dose_log.dart';
import 'package:paws_log/domain/models/medicine.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late MedicineRepository medicines;
  late DoseLogRepository doses;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    medicines = MedicineRepository(db);
    doses = DoseLogRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  /// A four-day course, twice a day, starting today: eight doses.
  ///
  /// Forward rather than backdated, because nothing is generated for days
  /// that have already gone — a course starting last week produces only
  /// today's doses.
  Future<Medicine> addCourse() => medicines.create(
    petId: petId,
    name: 'Amoxicillin',
    dosage: '1 tablet',
    schedule: DoseSchedule(
      timesOfDayMinutes: const [8 * 60, 20 * 60],
      startDate: todayInTestZone(),
      endDate: daysFromTodayInTestZone(3),
    ),
  );

  /// Every dose of the course, oldest first.
  ///
  /// A plain select rather than `watchForMedicine(...).first`: taking the
  /// first element of a drift stream cancels it, and a cancelled query stream
  /// schedules a timer that needs the fake clock still running — which it is
  /// not once the test moves on to pumping widgets. See the note in
  /// test/helpers/harness.dart.
  Future<List<DoseLogRow>> dosesOf(String medicineId) async {
    final rows = await (db.select(db.doseLogs)
          ..where((dose) => dose.medicineId.equals(medicineId))
          ..orderBy([(dose) => OrderingTerm.asc(dose.scheduledFor)]))
        .get();
    return rows;
  }

  Future<void> openCourse(WidgetTester tester) async {
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
    await openMedicalSegment(tester, 'Medicines');
    await tapAndSettle(tester, find.text('Amoxicillin'));
  }

  testWidgets('a course opens from the medicines list', (tester) async {
    await addCourse();
    await openCourse(tester);

    expect(find.text('How it is going'), findsOneWidget);
    expect(find.text('Every dose'), findsOneWidget);
    expect(find.textContaining('1 tablet'), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('with nothing logged it says so', (tester) async {
    await addCourse();
    await openCourse(tester);

    expect(find.text('Nothing logged yet.'), findsOneWidget);
    expect(find.textContaining('still to come'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the partition counts what actually happened', (tester) async {
    final medicine = await addCourse();
    final ordered = await dosesOf(medicine.id);
    await doses.logTaken(ordered[0].id);
    await doses.logTaken(ordered[1].id);
    await doses.skip(ordered[2].id);

    await openCourse(tester);

    expect(find.textContaining('2 taken'), findsOneWidget);
    expect(find.textContaining('1 skipped'), findsOneWidget);
    expect(find.textContaining('5 still to come'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a dose whose day passed shows as missed', (tester) async {
    final medicine = await addCourse();
    // Back-dated by hand: the generator does not produce doses for days that
    // have already gone, so there is no other way to have one to miss.
    await db.into(db.doseLogs).insert(
      DoseLogRow(
        id: 'missed-1',
        medicineId: medicine.id,
        scheduledFor: daysFromTodayInTestZone(-1).add(const Duration(hours: 8)),
        status: DoseStatus.pending,
      ),
    );
    await doses.markOverdueMissed();

    await openCourse(tester);

    expect(find.textContaining('1 missed'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('every dose is listed with its outcome', (tester) async {
    final medicine = await addCourse();
    final all = await dosesOf(medicine.id);
    await doses.logTaken(all.first.id);

    await openCourse(tester);

    expect(find.text('Taken'), findsOneWidget);
    expect(
      find.text('Due'),
      findsWidgets,
      reason: 'the rest of the course has not happened yet',
    );

    await disposeTree(tester);
  });

  testWidgets('the counts follow the doses as they are logged', (
    tester,
  ) async {
    final medicine = await addCourse();
    await openCourse(tester);
    expect(find.text('Nothing logged yet.'), findsOneWidget);

    final all = await dosesOf(medicine.id);
    await doses.logTaken(all.first.id);
    await settle(tester);

    expect(find.text('Nothing logged yet.'), findsNothing);
    expect(find.textContaining('1 taken'), findsOneWidget);

    await disposeTree(tester);
  });

  group('the counting itself', () {
    test('partitions by status', () {
      DoseLog dose(DoseStatus status) => DoseLog(
        id: status.name,
        medicineId: 'med-1',
        scheduledFor: DateTime.utc(2026, 5, 4),
        status: status,
      );

      expect(
        adherenceOf([
          dose(DoseStatus.taken),
          dose(DoseStatus.taken),
          dose(DoseStatus.missed),
          dose(DoseStatus.skipped),
          dose(DoseStatus.pending),
        ]),
        (taken: 2, missed: 1, skipped: 1, pending: 1),
      );
    });

    test('an empty course is all zeroes, not an error', () {
      expect(
        adherenceOf(const []),
        (taken: 0, missed: 0, skipped: 0, pending: 0),
      );
    });

    test('it counts every dose, not the capped window', () async {
      // watchForMedicine stops at 200; a count taken over that would
      // understate a long course.
      // Forward, not backdated: a finite course has its whole run generated
      // when it is created, and nothing is generated for days already gone.
      final medicine = await medicines.create(
        petId: petId,
        name: 'Thyroxine',
        schedule: DoseSchedule(
          timesOfDayMinutes: const [8 * 60, 20 * 60],
          startDate: todayInTestZone(),
          endDate: daysFromTodayInTestZone(150),
        ),
      );

      final windowed = await doses.watchForMedicine(medicine.id).first;
      final counted = await doses.adherence(medicine.id);
      final total =
          counted.taken + counted.missed + counted.skipped + counted.pending;

      expect(windowed, hasLength(200));
      expect(total, greaterThan(200));
      // The database is deliberately not closed; see test/helpers/harness.dart.
    });
  });
}
