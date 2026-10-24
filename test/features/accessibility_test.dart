import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_health_repository.dart';
import 'package:paws_log/data/repositories/pet_photo_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/services/prescriptions/ocr_service.dart';
import 'package:paws_log/services/prescriptions/scan_service.dart';

import '../helpers/harness.dart';

/// Every screen, in both themes, at the largest text the OS will hand us.
///
/// A RenderFlex overflow throws in a widget test, so "no exception" is a real
/// assertion here: these tests fail the moment a layout stops coping with
/// someone's accessibility settings.
void main() {
  late AppDatabase db;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() => db = memoryDatabase());

  /// A pet with something in every section.
  Future<void> populate() async {
    final pet = await PetRepository(db).create(
      name: 'Mochi',
      breed: 'Ragdoll',
      sex: PetSex.female,
      neutered: true,
      birthday: DateTime.utc(2022, 6, 1),
    );
    await ReminderRepository(db).create(
      petId: pet.id,
      title: 'Flea and tick treatment',
      category: ReminderCategory.fleaTick,
      repeat: const RepeatRule.months(1),
      anchorDate: todayInTestZone(),
      timeOfDayMinutes: 9 * 60,
    );
    await MedicineRepository(db).create(
      petId: pet.id,
      name: 'Amoxicillin clavulanate',
      dosage: '1 tablet twice daily',
      schedule: DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: todayInTestZone(),
        endDate: todayInTestZone(),
      ),
    );
    await WeightRepository(db).create(
      petId: pet.id,
      measuredOn: DateTime.utc(2026, 4, 1),
      grams: 4200,
    );
    await WeightRepository(db).create(
      petId: pet.id,
      measuredOn: DateTime.utc(2026, 5, 1),
      grams: 4450,
    );
    final health = PetHealthRepository(db);
    await health.addCondition(
      petId: pet.id,
      name: 'Chronic kidney disease, stage two',
      date: DateTime.utc(2026, 1, 10),
      notes: 'Bloods every six months, low phosphorus diet',
    );
    await health.addAllergy(
      petId: pet.id,
      allergen: 'Chicken',
      reaction: 'Itching round the ears and over the shoulders',
    );
    await PetPhotoRepository(db).add(
      petId: pet.id,
      path: '/pet_vault/sink.jpg',
      takenAt: DateTime.utc(2026, 4, 2),
      caption: 'Fast asleep in the bathroom sink, again, at four in the '
          'afternoon',
    );
    await VetVisitRepository(db).create(
      petId: pet.id,
      visitedOn: DateTime.utc(2026, 4, 20),
      reason: 'Limping on the back left leg after a fall',
      clinic: 'Riverside Veterinary Practice',
      vetName: 'Dr Okafor',
      notes: 'Rest for a week and come back if it has not settled.',
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required Brightness brightness,
    required double textScale,
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // So the prescription flow can be walked without a camera.
          scanServiceProvider.overrideWithValue(
            const FixedScanService(
              scanned: ['/pages/one.jpg'],
              picked: ['/pages/one.jpg'],
            ),
          ),
          ocrServiceProvider.overrideWithValue(
            const FixedOcrService(
              '1. Amoxicillin clavulanate 50 mg tablets\n'
              'Give one tablet twice daily for 7 days',
            ),
          ),
        ],
        child: MediaQuery(
          // Built from the test surface rather than from scratch, so the
          // phone size and pixel ratio `usePhoneSurface` set are kept. A
          // bare MediaQueryData would hand every screen a zero-sized
          // window.
          data: MediaQueryData.fromView(tester.view).copyWith(
            platformBrightness: brightness,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const PawsLogApp(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Runs [body] against both themes and both text sizes.
  void forEachAppearance(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        final label = '$description — ${brightness.name}, ${scale}x text';
        testWidgets(label, (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          await pump(tester, brightness: brightness, textScale: scale);
          await body(tester);
          await disposeTree(tester);
        });
      }
    }
  }

  group('onboarding', () {
    forEachAppearance('welcome', (tester) async {
      expect(find.text('Get started'), findsOneWidget);
    });

    forEachAppearance('add a cat', (tester) async {
      await tapAndSettle(tester, find.text('Get started'));
      expect(find.text('Add your cat'), findsOneWidget);
    });

    forEachAppearance('starter reminders', (tester) async {
      await tapAndSettle(tester, find.text('Get started'));
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mochi');
      await scrollAndTap(tester, find.text('Continue'));
      expect(find.text('Starter reminders'), findsOneWidget);
    });
  });

  group('with a full record', () {
    setUp(populate);

    forEachAppearance('today', (tester) async {
      expect(find.text('Today'), findsWidgets);
    });

    forEachAppearance('the pet profile', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await scrollIntoView(tester, find.text('Weight'));
      expect(find.text('Weight'), findsOneWidget);
    });

    forEachAppearance('the paywall', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Add a pet'));
      expect(find.text('Add another pet'), findsOneWidget);
    });

    forEachAppearance('backup', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.byTooltip('Backup'));
      await scrollIntoView(tester, find.text('Export a backup'));
      expect(find.text('Export a backup'), findsOneWidget);
    });

    forEachAppearance('the medical record', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Medicines');
      expect(find.text('Amoxicillin clavulanate'), findsOneWidget);

      // Every segment, because each lays out differently.
      for (final segment in [
        'Vaccines',
        'Vet visits',
        'Health',
        'Prescriptions',
      ]) {
        await tapAndSettle(tester, find.text(segment));
      }
    });

    forEachAppearance('the condition editor', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Health');
      await tapAndSettle(tester, find.byTooltip('Add to the health record'));
      await tapAndSettle(tester, find.text('Add a condition'));

      expect(find.text('What has your vet diagnosed?'), findsOneWidget);
      // The suggestion chips wrap, which is the part worth checking at 2x.
      await scrollIntoView(tester, find.text('Add condition'));
    });

    forEachAppearance('the photo album', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await scrollAndTap(tester, find.text('Photos'));
      expect(find.byTooltip('Add a photo'), findsOneWidget);

      await tapAndSettle(tester, find.byType(Image).first);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.textContaining('Fast asleep'), findsOneWidget);
    });

    forEachAppearance('the prescription review', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await scrollAndTap(tester, find.text('Medical record'));
      await tapAndSettle(tester, find.byTooltip('Add a prescription'));
      await tapAndSettle(tester, find.text('Scan the pages'));

      expect(find.text('Check the prescription'), findsOneWidget);
      // The whole form, because it is the densest screen in the app.
      await scrollIntoView(tester, find.text('Add another medicine'));
    });

    forEachAppearance('a vet visit', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Vet visits');
      await scrollAndTap(
        tester,
        find.text('Limping on the back left leg after a fall'),
      );
      expect(find.text('Visit'), findsOneWidget);
    });

    forEachAppearance('the medicine editor', (tester) async {
      await tapAndSettle(tester, find.text('Pets'));
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Medicines');
      await tapAndSettle(tester, find.byTooltip('Add a medicine'));
      expect(find.text('Add a medicine'), findsWidgets);
    });
  });
}
