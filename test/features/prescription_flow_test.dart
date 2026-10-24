import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/services/prescriptions/ocr_service.dart';
import 'package:paws_log/services/prescriptions/scan_service.dart';

import '../helpers/harness.dart';

/// A page the way a vet writes one.
const String _scanned = '''
Riverside Veterinary Clinic
Patient: Mochi

1. Amoxicillin 50 mg tablets
Give one tablet twice daily for 7 days
''';

void main() {
  late AppDatabase db;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
  });

  /// Opens the prescriptions segment with the scanner and the reader stubbed.
  Future<void> openPrescriptions(
    WidgetTester tester, {
    String text = _scanned,
    List<String> pages = const ['/pages/one.jpg'],
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scanServiceProvider.overrideWithValue(
            FixedScanService(scanned: pages, picked: pages),
          ),
          ocrServiceProvider.overrideWithValue(FixedOcrService(text)),
        ],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
    await scrollAndTap(tester, find.text('Medical record'));
  }

  Future<void> scan(WidgetTester tester) async {
    await tapAndSettle(tester, find.byTooltip('Add a prescription'));
    await tapAndSettle(tester, find.text('Scan the pages'));
  }

  testWidgets('scanning saves the pages and shows what was read', (
    tester,
  ) async {
    await openPrescriptions(tester);
    await scan(tester);

    expect(find.text('Check the prescription'), findsOneWidget);
    expect(
      find.textContaining('Check every dose against the original'),
      findsOneWidget,
      reason: 'the line CLAUDE.md requires on every review screen',
    );
    // The fields sit below the pages, which is the point of the layout, so
    // the test scrolls to them the way an owner would.
    await scrollIntoView(tester, find.widgetWithText(TextField, 'Amoxicillin'));
    expect(
      find.widgetWithText(TextField, 'Amoxicillin'),
      findsOneWidget,
      reason: 'the name the parser read, in an editable field',
    );
    await scrollIntoView(tester, find.textContaining('from today for 7 days'));
    expect(
      find.textContaining('8:00'),
      findsWidgets,
      reason: 'the dose times Confirm would create, spelled out',
    );

    // The pages are already kept, before anything is confirmed.
    final saved = (await db.select(db.prescriptions).get()).single;
    expect(saved.petId, petId);
    expect(saved.imagePaths, ['/pages/one.jpg']);
    expect(saved.extractedText, contains('Amoxicillin'));
    expect(
      await db.select(db.medicines).get(),
      isEmpty,
      reason: 'reading a page changes no schedule',
    );

    await disposeTree(tester);
  });

  testWidgets('Confirm creates the medicine, its doses and the link', (
    tester,
  ) async {
    await openPrescriptions(tester);
    await scan(tester);

    await scrollAndTap(tester, find.text('Confirm'));

    final prescription = (await db.select(db.prescriptions).get()).single;
    final medicine = (await db.select(db.medicines).get()).single;
    expect(medicine.name, 'Amoxicillin');
    expect(medicine.dosage, '50 mg');
    expect(
      medicine.timesOfDayMinutes,
      [8 * 60, 20 * 60],
      reason: 'twice a day becomes 08:00 and 20:00',
    );
    expect(medicine.startDate, todayInTestZone());
    expect(
      medicine.endDate,
      todayInTestZone().add(const Duration(days: 6)),
      reason: 'seven days counting today',
    );
    expect(
      medicine.prescriptionId,
      prescription.id,
      reason: 'a course always has its source',
    );
    expect(await db.select(db.doseLogs).get(), isNotEmpty);

    // And it is back on the prescriptions list.
    expect(find.text('Check the prescription'), findsNothing);
    expect(find.textContaining('1 page'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('Save photos only keeps the page and nothing else', (
    tester,
  ) async {
    await openPrescriptions(tester);
    await scan(tester);

    await scrollAndTap(tester, find.text('Save photos only'));

    expect(await db.select(db.prescriptions).get(), hasLength(1));
    expect(await db.select(db.medicines).get(), isEmpty);
    expect(find.text('Check the prescription'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('backing out of the review still keeps the page', (tester) async {
    await openPrescriptions(tester);
    await scan(tester);

    await tapAndSettle(tester, find.byTooltip('Back'));

    expect(await db.select(db.prescriptions).get(), hasLength(1));
    expect(await db.select(db.medicines).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('a course with no frequency cannot be confirmed', (tester) async {
    // A name and a dose, but nothing that says how often.
    await openPrescriptions(tester, text: 'Amoxicillin 50 mg tablets');
    await scan(tester);

    await scrollAndTap(tester, find.text('Confirm'));

    await scrollIntoView(tester, find.text('How often is it given?'));
    expect(find.text('How often is it given?'), findsOneWidget);
    expect(
      await db.select(db.medicines).get(),
      isEmpty,
      reason: 'a dose time is never invented',
    );
    expect(
      find.text('Check the prescription'),
      findsOneWidget,
      reason: 'the owner stays on the screen to fix it',
    );

    await disposeTree(tester);
  });

  testWidgets('a frequency chosen by hand is enough to confirm', (
    tester,
  ) async {
    await openPrescriptions(tester, text: 'Amoxicillin 50 mg tablets');
    await scan(tester);

    await scrollAndTap(tester, find.text('Not set'));
    await tapAndSettle(tester, find.text('Once a day').last);
    await scrollAndTap(tester, find.text('Confirm'));

    final medicine = (await db.select(db.medicines).get()).single;
    expect(medicine.timesOfDayMinutes, [9 * 60]);
    expect(
      medicine.endDate,
      isNull,
      reason: 'no length on the page means an ongoing course',
    );

    await disposeTree(tester);
  });

  testWidgets('an unreadable page still saves, and says so', (tester) async {
    await openPrescriptions(tester, text: '');
    await scan(tester);

    await scrollIntoView(tester, find.textContaining('No text could be read'));
    expect(find.textContaining('No text could be read'), findsOneWidget);

    final saved = (await db.select(db.prescriptions).get()).single;
    expect(saved.extractedText, isNull);

    await disposeTree(tester);
  });

  testWidgets('backing out of the picker saves nothing', (tester) async {
    await openPrescriptions(tester, pages: const []);
    await scan(tester);

    expect(find.text('Check the prescription'), findsNothing);
    expect(await db.select(db.prescriptions).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('a page with two medicines offers both', (tester) async {
    await openPrescriptions(
      tester,
      text: '1. Amoxicillin 50 mg tablets\n'
          'Give one tablet twice daily for 7 days\n'
          '2. Meloxicam 0.5 mg/ml suspension\n'
          'Give 0.1 ml once daily for 3 days',
    );
    await scan(tester);

    await scrollIntoView(tester, find.text('Medicine 1'));
    expect(find.text('Medicine 1'), findsOneWidget);
    await scrollIntoView(tester, find.text('Medicine 2'));
    expect(find.text('Medicine 2'), findsOneWidget);

    await scrollAndTap(tester, find.text('Confirm'));

    final medicines = await db.select(db.medicines).get();
    expect(
      medicines.map((m) => m.name),
      unorderedEquals(['Amoxicillin', 'Meloxicam']),
    );

    await disposeTree(tester);
  });
}
