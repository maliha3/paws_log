import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/features/premium/paywall_screen.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late SettingsRepository settings;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() {
    db = memoryDatabase();
    pets = PetRepository(db);
    settings = SettingsRepository(db);
  });

  Future<void> openPets(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
  }

  group('a second pet', () {
    testWidgets('the first pet comes through onboarding, ungated', (
      tester,
    ) async {
      // With no pets the app is in onboarding, so the free pet is never
      // added from the Pets tab at all — there is no Pets tab to add it
      // from. The gate must not appear anywhere in that flow.
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
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Finish'));

      expect(find.byType(PaywallScreen), findsNothing);
      expect(await db.select(db.pets).get(), hasLength(1));

      await disposeTree(tester);
    });

    testWidgets('a second one hits the paywall', (tester) async {
      await pets.create(name: 'Mochi');
      await openPets(tester);

      await tapAndSettle(tester, find.text('Add a pet'));

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('Add another pet'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Name'),
        findsNothing,
        reason: 'the form did not open',
      );

      await disposeTree(tester);
    });

    testWidgets('unlocked, it goes straight through', (tester) async {
      await pets.create(name: 'Mochi');
      await settings.setPremium(value: true);
      await openPets(tester);

      await tapAndSettle(tester, find.text('Add a pet'));

      expect(find.byType(PaywallScreen), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Luna');
      await scrollAndTap(tester, find.text('Add pet'));
      expect(await db.select(db.pets).get(), hasLength(2));

      await disposeTree(tester);
    });

    testWidgets('pets already on file stay visible when locked', (
      tester,
    ) async {
      // As after restoring a backup made on a paid install, or after access
      // lapsed. The gate stops additions; it never hides what is there.
      for (final name in ['Mochi', 'Luna', 'Pepper']) {
        await pets.create(name: name);
      }
      await openPets(tester);

      expect(find.text('Mochi'), findsOneWidget);
      expect(find.text('Luna'), findsOneWidget);
      expect(find.text('Pepper'), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('visit photos', () {
    Future<void> openVisit(WidgetTester tester) async {
      final pet = await pets.create(name: 'Mochi');
      await VetVisitRepository(db).create(
        petId: pet.id,
        visitedOn: DateTime.utc(2026, 5, 4),
        reason: 'Annual checkup',
      );
      await openPets(tester);
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Vet visits');
      await tapAndSettle(tester, find.text('Annual checkup'));
    }

    testWidgets('adding one hits the paywall when locked', (tester) async {
      await openVisit(tester);

      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Add'));

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('Attach photos to a visit'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('photos already attached stay visible when locked', (
      tester,
    ) async {
      final pet = await pets.create(name: 'Mochi');
      await VetVisitRepository(db).create(
        petId: pet.id,
        visitedOn: DateTime.utc(2026, 5, 4),
        reason: 'Annual checkup',
        attachmentPaths: const ['/tmp/paws-log-not-real.jpg'],
      );
      await openPets(tester);
      await tapAndSettle(tester, find.text('Mochi'));
      await openMedicalSegment(tester, 'Vet visits');
      await tapAndSettle(tester, find.text('Annual checkup'));

      expect(
        find.textContaining('No photos attached'),
        findsNothing,
        reason: 'the attachment is still listed',
      );

      await disposeTree(tester);
    });
  });

  group('the flag itself', () {
    test('it defaults to locked', () async {
      expect(await settings.isPremium(), isFalse);
      await db.close();
    });

    test('it round-trips and can be revoked', () async {
      await settings.setPremium(value: true);
      expect(await settings.isPremium(), isTrue);

      await settings.setPremium(value: false);
      expect(await settings.isPremium(), isFalse);
      await db.close();
    });

    test('an unreadable value reads as locked, never as unlocked', () async {
      await settings.setWeightUnit(await settings.weightUnit());
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingRow(key: 'is_premium', value: 'perhaps'),
          );

      expect(
        await settings.isPremium(),
        isFalse,
        reason: 'a gate must fail closed',
      );
      await db.close();
    });

    test('it travels in a backup, like every other setting', () async {
      await settings.setPremium(value: true);
      final rows = await db.select(db.appSettings).get();

      expect(
        rows.map((row) => row.key),
        contains('is_premium'),
        reason: 'stored in the settings table, so backup covers it',
      );
      await db.close();
    });
  });
}
