import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/features/premium/paywall_screen.dart';
import 'package:paws_log/services/entitlements/entitlement_source.dart';

import '../helpers/harness.dart';
import '../services/entitlements_test.dart' show FakeEntitlementSource;

void main() {
  late AppDatabase db;
  late FakeEntitlementSource source;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    source = FakeEntitlementSource(
      plansOnOffer: [
        PremiumPlan(id: 'monthly', kind: PlanKind.monthly, price: '£2.99'),
        PremiumPlan(
          id: 'yearly',
          kind: PlanKind.yearly,
          price: '£19.99',
          highlight: 'Save 44%',
        ),
        PremiumPlan(id: 'lifetime', kind: PlanKind.lifetime, price: '£49.99'),
      ],
    );
    // One pet already, so the Add button reaches the paywall.
    await PetRepository(db).create(name: 'Mochi');
  });

  Future<void> openPaywall(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          entitlementSourceProvider.overrideWithValue(source),
        ],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Add a pet'));
  }

  testWidgets('every plan shows its price and what it commits to', (
    tester,
  ) async {
    await openPaywall(tester);

    expect(find.byType(PaywallScreen), findsOneWidget);

    // Title, price and terms, for each plan — what Apple wants in front of
    // someone before they buy.
    for (final plan in ['Monthly', 'Yearly', 'Lifetime']) {
      expect(find.text(plan), findsOneWidget, reason: plan);
    }
    expect(find.text('£2.99'), findsOneWidget);
    expect(find.text('£19.99'), findsOneWidget);
    expect(find.text('£49.99'), findsOneWidget);
    expect(
      find.textContaining('per month. Renews automatically until cancelled.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('per year. Renews automatically until cancelled.'),
      findsOneWidget,
    );

    await disposeTree(tester);
  });

  testWidgets('the lifetime plan never claims to renew', (tester) async {
    await openPaywall(tester);

    expect(find.textContaining('£49.99 once. No subscription.'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a saving is shown against the yearly plan', (tester) async {
    await openPaywall(tester);

    expect(find.text('Save 44%'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the renewal and billing terms are on the sheet', (tester) async {
    await openPaywall(tester);

    expect(find.textContaining('charged to your Apple Account'), findsOneWidget);
    expect(
      find.textContaining('cancelled at least 24 hours before'),
      findsOneWidget,
    );
    expect(find.text('Terms of Use'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('Restore purchases is reachable without buying', (tester) async {
    await openPaywall(tester);

    expect(find.text('Restore purchases'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('buying unlocks and closes the sheet', (tester) async {
    await openPaywall(tester);

    await tapAndSettle(tester, find.text('Monthly'));

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('PawsLog is unlocked.'), findsOneWidget);
    expect(await cachedPremium(db), isTrue);

    await disposeTree(tester);
  });

  testWidgets('backing out of the store says nothing', (tester) async {
    source.purchaseResult = PurchaseOutcome.cancelled;
    await openPaywall(tester);

    await tapAndSettle(tester, find.text('Monthly'));

    // Still open, and no error: cancelling is the commonest outcome there is.
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.textContaining('did not go through'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('a failed purchase says nothing was charged', (tester) async {
    source.purchaseResult = PurchaseOutcome.failed;
    await openPaywall(tester);

    await tapAndSettle(tester, find.text('Monthly'));

    expect(find.textContaining('Nothing has been charged.'), findsOneWidget);
    expect(await cachedPremium(db), isFalse);

    await disposeTree(tester);
  });

  testWidgets('restoring with a purchase behind it unlocks', (tester) async {
    source.restoreResult = PurchaseOutcome.unlocked;
    await openPaywall(tester);

    await tapAndSettle(tester, find.text('Restore purchases'));

    expect(find.text('Purchases restored.'), findsOneWidget);
    expect(await cachedPremium(db), isTrue);

    await disposeTree(tester);
  });

  testWidgets('restoring with nothing behind it says so plainly', (
    tester,
  ) async {
    await openPaywall(tester);

    await tapAndSettle(tester, find.text('Restore purchases'));

    expect(
      find.textContaining('No previous purchase found'),
      findsOneWidget,
    );

    await disposeTree(tester);
  });

  testWidgets('with nothing on offer it says so rather than showing an empty '
      'list', (tester) async {
    source.plansOnOffer = const [];
    await openPaywall(tester);

    expect(
      find.textContaining('Purchases are not available right now.'),
      findsOneWidget,
    );
    expect(
      find.text('Restore purchases'),
      findsOneWidget,
      reason: 'still reachable — someone may have bought on another device',
    );

    await disposeTree(tester);
  });

  testWidgets('once unlocked, the gated action goes through', (tester) async {
    await openPaywall(tester);
    await tapAndSettle(tester, find.text('Monthly'));
    // Let the confirmation snackbar clear; it sits over the button.
    await settle(tester, frames: 120);

    await tapAndSettle(tester, find.text('Add a pet'));

    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);

    await disposeTree(tester);
  });
}

/// Reads the cached entitlement straight from the database.
Future<bool> cachedPremium(AppDatabase db) async {
  final rows = await db.select(db.appSettings).get();
  return rows
      .where((row) => row.key == 'is_premium')
      .map((row) => row.value == 'true')
      .firstOrNull ??
      false;
}
