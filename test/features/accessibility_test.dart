import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';

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
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MediaQuery(
          data: MediaQueryData(
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
      for (final segment in ['Vaccines', 'Vet visits', 'Prescriptions']) {
        await tapAndSettle(tester, find.text(segment));
      }
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
