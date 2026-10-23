import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/services/entitlements/entitlement_service.dart';
import 'package:paws_log/services/entitlements/entitlement_source.dart';
import 'package:paws_log/services/entitlements/stub_entitlements.dart';

import '../helpers/harness.dart';

/// A store under the test's control.
class FakeEntitlementSource implements EntitlementSource {
  FakeEntitlementSource({this.active = false, this.plansOnOffer = const []});

  bool active;
  List<PremiumPlan> plansOnOffer;

  /// Set to simulate being offline.
  bool throwOnRead = false;

  PurchaseOutcome purchaseResult = PurchaseOutcome.unlocked;
  PurchaseOutcome restoreResult = PurchaseOutcome.nothingToRestore;

  final _controller = StreamController<bool>.broadcast();

  void emit(bool value) {
    active = value;
    _controller.add(value);
  }

  @override
  Stream<bool> watchActive() async* {
    yield active;
    yield* _controller.stream;
  }

  @override
  Future<bool> isActive() async {
    if (throwOnRead) {
      throw StateError('offline');
    }
    return active;
  }

  @override
  Future<List<PremiumPlan>> plans() async => plansOnOffer;

  @override
  Future<PurchaseOutcome> purchase(PremiumPlan plan) async {
    if (purchaseResult == PurchaseOutcome.unlocked) {
      active = true;
    }
    return purchaseResult;
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (restoreResult == PurchaseOutcome.unlocked) {
      active = true;
    }
    return restoreResult;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeEntitlementSource source;
  late EntitlementService service;

  setUpAll(initializeTestTimeZone);

  setUp(() {
    db = memoryDatabase();
    settings = SettingsRepository(db);
    source = FakeEntitlementSource();
    service = EntitlementService(source: source, settings: settings);
  });

  tearDown(() => db.close());

  group('the cache', () {
    test('a locked store reads as locked', () async {
      expect(await service.isActive(), isFalse);
    });

    test('an active entitlement is written to the cache', () async {
      source.active = true;

      expect(await service.isActive(), isTrue);
      expect(
        await settings.isPremium(),
        isTrue,
        reason: 'so the next cold start knows before the store answers',
      );
    });

    test('an unreachable store falls back to the last known state', () async {
      // A paying owner opening the app on a train must not be told they have
      // lost access because the network is down.
      source.active = true;
      await service.isActive();

      source.throwOnRead = true;
      expect(await service.isActive(), isTrue);
    });

    test('an unreachable store on a first run reads as locked', () async {
      source.throwOnRead = true;

      expect(await service.isActive(), isFalse);
    });

    test('access being revoked is written through', () async {
      source.active = true;
      await service.isActive();
      expect(await settings.isPremium(), isTrue);

      source
        ..active = false
        ..throwOnRead = false;

      expect(await service.isActive(), isFalse);
      expect(
        await settings.isPremium(),
        isFalse,
        reason: 'a refund or lapse is not cached as still paid',
      );
    });

    test('the stream starts from the cache, then follows the store', () async {
      await settings.setPremium(value: true);
      final seen = <bool>[];
      final subscription = service.watchActive().listen(seen.add);
      addTearDown(subscription.cancel);

      /// Waits for the stream to have produced [count] values.
      ///
      /// The source is a broadcast stream, so emitting before the `async*`
      /// has got as far as subscribing would simply drop the event.
      Future<void> waitFor(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (seen.length < count && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      await waitFor(1);
      expect(seen.first, isTrue, reason: 'the cached value, immediately');

      source.emit(false);
      await waitFor(2);
      expect(seen.last, isFalse);
    });
  });

  group('buying and restoring', () {
    final monthly = PremiumPlan(
      id: 'monthly',
      kind: PlanKind.monthly,
      price: '£2.99',
    );

    test('a purchase unlocks and is cached', () async {
      final outcome = await service.purchase(monthly);

      expect(outcome, PurchaseOutcome.unlocked);
      expect(await settings.isPremium(), isTrue);
    });

    test('a cancelled purchase changes nothing', () async {
      source.purchaseResult = PurchaseOutcome.cancelled;

      expect(await service.purchase(monthly), PurchaseOutcome.cancelled);
      expect(await settings.isPremium(), isFalse);
    });

    test('a failed purchase changes nothing', () async {
      source.purchaseResult = PurchaseOutcome.failed;

      expect(await service.purchase(monthly), PurchaseOutcome.failed);
      expect(await settings.isPremium(), isFalse);
    });

    test('a restore with a purchase behind it unlocks', () async {
      source.restoreResult = PurchaseOutcome.unlocked;

      expect(await service.restore(), PurchaseOutcome.unlocked);
      expect(await settings.isPremium(), isTrue);
    });

    test('a restore with nothing behind it does not unlock', () async {
      expect(await service.restore(), PurchaseOutcome.nothingToRestore);
      expect(await settings.isPremium(), isFalse);
    });
  });

  group('the plans', () {
    test('terms say what each plan actually is', () {
      expect(
        PlanKind.monthly.terms('£2.99'),
        '£2.99 per month. Renews automatically until cancelled.',
      );
      expect(
        PlanKind.yearly.terms('£19.99'),
        '£19.99 per year. Renews automatically until cancelled.',
      );
      expect(
        PlanKind.lifetime.terms('£49.99'),
        '£49.99 once. No subscription.',
        reason: 'a one-off must not claim to renew',
      );
    });

    test('only subscriptions renew', () {
      expect(PlanKind.monthly.renews, isTrue);
      expect(PlanKind.yearly.renews, isTrue);
      expect(PlanKind.lifetime.renews, isFalse);
    });
  });

  group('the stub, used when a build has no store keys', () {
    late StubEntitlements stub;

    setUp(() => stub = StubEntitlements(settings));

    test('it sells nothing, so a missing key cannot look like a store', () async {
      expect(await stub.plans(), isEmpty);
      expect(
        await stub.purchase(
          PremiumPlan(id: 'x', kind: PlanKind.monthly, price: '£1'),
        ),
        PurchaseOutcome.failed,
      );
      expect(await stub.restore(), PurchaseOutcome.nothingToRestore);
    });

    test('the debug unlock flips it', () async {
      expect(await stub.isActive(), isFalse);

      await stub.setUnlocked(value: true);

      expect(await stub.isActive(), isTrue);
    });
  });
}
