import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/prescription_repository.dart';
import 'package:paws_log/domain/models/prescription.dart';
import 'package:paws_log/services/prescriptions/ocr_service.dart';
import 'package:paws_log/services/prescriptions/scan_service.dart';

import '../helpers/harness.dart';

const String _page = '''
1. Amoxicillin 50 mg tablets
Give one tablet twice daily for 7 days
''';

void main() {
  late AppDatabase db;
  late PrescriptionRepository prescriptions;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    prescriptions = PrescriptionRepository(db);
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  Future<Prescription> save({String? text}) => prescriptions.create(
    petId: petId,
    date: DateTime.utc(2026, 5, 4),
    imagePaths: const ['/pages/one.jpg'],
    vetName: 'Dr Okafor',
    clinic: 'Riverside Vets',
    extractedText: text,
  );

  /// Opens the saved prescription, with OCR stubbed to [ocr].
  Future<void> openDetail(WidgetTester tester, {String ocr = _page}) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ocrServiceProvider.overrideWithValue(FixedOcrService(ocr)),
          scanServiceProvider.overrideWithValue(const FixedScanService()),
        ],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    await scrollAndTap(tester, find.text('Medical record'));
    await tapAndSettle(tester, find.text('May 4, 2026'));
  }

  testWidgets('it shows the vet details that were typed on review', (
    tester,
  ) async {
    await save(text: _page);
    await openDetail(tester);

    expect(find.text('Dr Okafor'), findsOneWidget);
    expect(find.text('Riverside Vets'), findsOneWidget);
    expect(find.text('1 page'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the text read off the page is reachable again', (tester) async {
    // It was stored on the row all along and shown nowhere.
    await save(text: _page);
    await openDetail(tester);

    await scrollAndTap(tester, find.text('What was read off the page'));

    expect(find.textContaining('Amoxicillin 50 mg tablets'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a page saved without text offers to read it', (tester) async {
    await save();
    await openDetail(tester);

    expect(find.text('Read this page'), findsOneWidget);
    expect(find.text('What was read off the page'), findsNothing);
    expect(
      find.textContaining('Nothing has been read off these pages yet'),
      findsOneWidget,
    );

    await disposeTree(tester);
  });

  testWidgets('"Save photos only" is no longer a one-way door', (
    tester,
  ) async {
    // The gap this screen closes: keep the page now, extract from it later,
    // without scanning a page you already have.
    await save();
    await openDetail(tester);

    await scrollAndTap(tester, find.text('Read this page'));

    expect(find.text('Check the prescription'), findsOneWidget);
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Amoxicillin'));
    expect(find.widgetWithText(TextField, 'Amoxicillin'), findsOneWidget);

    await scrollAndTap(tester, find.text('Confirm'));

    final medicine = (await db.select(db.medicines).get()).single;
    expect(medicine.name, 'Amoxicillin');
    expect(
      medicine.prescriptionId,
      (await db.select(db.prescriptions).get()).single.id,
    );
    expect(
      (await db.select(db.prescriptions).get()).single.extractedText,
      contains('Amoxicillin'),
      reason: 'what was read is kept, so it need not be read twice',
    );

    await disposeTree(tester);
  });

  testWidgets('a page already read is not read again', (tester) async {
    await save(text: _page);
    // An OCR engine that would return something different if it ran.
    await openDetail(tester, ocr: 'Meloxicam 0.5 mg once daily for 3 days');

    await scrollAndTap(tester, find.text('Check the details again'));

    await scrollIntoView(tester, find.widgetWithText(TextField, 'Amoxicillin'));
    expect(
      find.widgetWithText(TextField, 'Meloxicam'),
      findsNothing,
      reason: 'the stored text is parsed, not the pages re-read',
    );

    await disposeTree(tester);
  });

  testWidgets('the medicines it produced are listed and open', (tester) async {
    await save(text: _page);
    await openDetail(tester);
    await scrollAndTap(tester, find.text('Check the details again'));
    await scrollAndTap(tester, find.text('Confirm'));

    expect(find.text('Medicines from this page'), findsOneWidget);
    await scrollIntoView(tester, find.text('Amoxicillin'));
    await tapAndSettle(tester, find.text('Amoxicillin'));

    expect(find.text('Edit medicine'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('with nothing extracted it says so plainly', (tester) async {
    await save(text: _page);
    await openDetail(tester);

    expect(find.text('None yet.'), findsOneWidget);

    await disposeTree(tester);
  });

  group('deleting', () {
    testWidgets('asks first, and keeping it changes nothing', (tester) async {
      await save(text: _page);
      await openDetail(tester);

      await tapAndSettle(tester, find.byTooltip('Prescription options'));
      await tapAndSettle(tester, find.text('Delete'));
      await tapAndSettle(tester, find.text('Keep'));

      expect(await db.select(db.prescriptions).get(), hasLength(1));

      await disposeTree(tester);
    });

    testWidgets('removes it and closes the screen', (tester) async {
      await save(text: _page);
      await openDetail(tester);

      await tapAndSettle(tester, find.byTooltip('Prescription options'));
      await tapAndSettle(tester, find.text('Delete'));
      await tapAndSettle(tester, find.text('Delete').last);

      expect(await db.select(db.prescriptions).get(), isEmpty);
      expect(
        find.textContaining('No prescriptions yet'),
        findsOneWidget,
        reason: 'back on the list, which is now empty',
      );

      await disposeTree(tester);
    });

    testWidgets('leaves the medicines it produced standing', (tester) async {
      await save(text: _page);
      await openDetail(tester);
      await scrollAndTap(tester, find.text('Check the details again'));
      await scrollAndTap(tester, find.text('Confirm'));

      // Confirm pops back to the detail screen it was opened from.
      await tapAndSettle(tester, find.byTooltip('Prescription options'));
      await tapAndSettle(tester, find.text('Delete'));
      await tapAndSettle(tester, find.text('Delete').last);

      final medicine = (await db.select(db.medicines).get()).single;
      expect(medicine.name, 'Amoxicillin');
      expect(medicine.prescriptionId, isNull);

      await disposeTree(tester);
    });
  });
}
