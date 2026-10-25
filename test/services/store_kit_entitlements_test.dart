import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:paws_log/services/entitlements/entitlement_source.dart';
import 'package:paws_log/services/entitlements/store_kit_entitlements.dart';

const String _productId = 'com.malihazaman.pawsLog.premium.lifetime';

/// A store that does what it is told, so the paths that only ever ran on a
/// phone can be exercised here.
class _FakeStore implements InAppPurchase {
  _FakeStore({this.available = true, List<ProductDetails>? products})
    : products = products ?? [_product];

  /// `InAppPurchase` is a wide surface and this fake needs five of it.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);

  final bool available;
  final List<ProductDetails> products;

  final StreamController<List<PurchaseDetails>> _stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  int restoreCalls = 0;
  int buyCalls = 0;
  final List<String> completed = [];

  static final ProductDetails _product = ProductDetails(
    id: _productId,
    title: 'Paws Log Unlocked',
    description: 'Every cat, once.',
    price: r'$9.99',
    rawPrice: 9.99,
    currencyCode: 'USD',
  );

  void deliver(PurchaseDetails purchase) => _stream.add([purchase]);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: products.where((p) => ids.contains(p.id)).toList(),
        notFoundIDs: ids.where((id) => !products.any((p) => p.id == id)).toList(),
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.productID);
  }

  Future<void> close() => _stream.close();
}

PurchaseDetails _purchase(
  PurchaseStatus status, {
  String id = _productId,
  bool needsCompleting = true,
}) {
  final details = PurchaseDetails(
    productID: id,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'app_store',
    ),
    transactionDate: null,
    status: status,
  );
  details.pendingCompletePurchase = needsCompleting;
  return details;
}

void main() {
  late _FakeStore store;
  late StoreKitEntitlements source;

  setUp(() {
    store = _FakeStore();
    source = StoreKitEntitlements(store: store, productId: _productId);
  });

  tearDown(() async {
    await source.dispose();
    await store.close();
  });

  group('what the store is asked for', () {
    test('the one product, at the price Apple gives it', () async {
      final plans = await source.plans();

      expect(plans, hasLength(1));
      expect(plans.single.id, _productId);
      expect(plans.single.kind, PlanKind.lifetime);
      expect(
        plans.single.price,
        r'$9.99',
        reason: "Apple's own localised string; the app never formats money",
      );
    });

    test('nothing, when the store is unreachable', () async {
      final offline = StoreKitEntitlements(
        store: _FakeStore(available: false),
        productId: _productId,
      );

      expect(await offline.plans(), isEmpty);
      expect(await offline.isActive(), isFalse, reason: 'the gate fails closed');
      await offline.dispose();
    });

    test('nothing, when the product is not configured', () async {
      final empty = _FakeStore(products: []);
      final unconfigured = StoreKitEntitlements(
        store: empty,
        productId: _productId,
      );

      expect(await unconfigured.plans(), isEmpty);
      await unconfigured.dispose();
      await empty.close();
    });
  });

  group('buying', () {
    test('a completed purchase unlocks and is acknowledged', () async {
      final outcome = source.purchase(
        const PremiumPlan(
          id: _productId,
          kind: PlanKind.lifetime,
          price: r'$9.99',
        ),
      );
      await pumpEventQueue();
      store.deliver(_purchase(PurchaseStatus.purchased));

      expect(await outcome, PurchaseOutcome.unlocked);
      expect(await source.isActive(), isTrue);
      await pumpEventQueue();
      expect(
        store.completed,
        [_productId],
        reason: 'Apple redelivers a transaction until it is acknowledged',
      );
    });

    test('backing out is cancelled, not an error', () async {
      final outcome = source.purchase(
        const PremiumPlan(
          id: _productId,
          kind: PlanKind.lifetime,
          price: r'$9.99',
        ),
      );
      await pumpEventQueue();
      store.deliver(_purchase(PurchaseStatus.canceled));

      expect(await outcome, PurchaseOutcome.cancelled);
      expect(await source.isActive(), isFalse);
    });

    test('a failure is reported, and still acknowledged', () async {
      final outcome = source.purchase(
        const PremiumPlan(
          id: _productId,
          kind: PlanKind.lifetime,
          price: r'$9.99',
        ),
      );
      await pumpEventQueue();
      store.deliver(_purchase(PurchaseStatus.error));

      expect(await outcome, PurchaseOutcome.failed);
      await pumpEventQueue();
      expect(store.completed, [_productId]);
    });

    test('a pending purchase is not an answer yet', () async {
      source.purchase(
        const PremiumPlan(
          id: _productId,
          kind: PlanKind.lifetime,
          price: r'$9.99',
        ),
      );
      await pumpEventQueue();
      store.deliver(_purchase(PurchaseStatus.pending));
      await pumpEventQueue();

      expect(
        await source.isActive(),
        isFalse,
        reason: 'ask-to-buy is waiting on a parent, not a purchase',
      );
    });

    test('someone else’s product is ignored', () async {
      store.deliver(
        _purchase(PurchaseStatus.purchased, id: 'com.example.other'),
      );
      await pumpEventQueue();

      expect(await source.isActive(), isFalse);
      expect(store.completed, isEmpty);
    });
  });

  group('restoring', () {
    test('a past purchase unlocks again', () async {
      final outcome = source.restore();
      await pumpEventQueue();
      store.deliver(_purchase(PurchaseStatus.restored));

      expect(await outcome, PurchaseOutcome.unlocked);
      expect(await source.isActive(), isTrue);
      expect(store.restoreCalls, 1);
    });

    test('silence means there was nothing to restore', () async {
      // Apple replays what exists and says nothing when that is nothing, so
      // the absence of an answer has to become one.
      final outcome = await source.restore().timeout(
        const Duration(seconds: 10),
      );

      expect(outcome, PurchaseOutcome.nothingToRestore);
      expect(await source.isActive(), isFalse);
    });
  });

  group('what the app watches', () {
    test('the stream carries every change', () async {
      final seen = <bool>[];
      final listening = source.watchActive().listen(seen.add);

      store.deliver(_purchase(PurchaseStatus.purchased));
      await pumpEventQueue();

      expect(seen, contains(true));
      await listening.cancel();
    });

    test('start replays what Apple already knows', () async {
      await source.start();

      expect(store.restoreCalls, 1);
    });

    test('start on an unreachable store settles as locked', () async {
      final offline = _FakeStore(available: false);
      final source = StoreKitEntitlements(
        store: offline,
        productId: _productId,
      );

      await source.start();

      expect(offline.restoreCalls, 0);
      expect(await source.isActive(), isFalse);
      await source.dispose();
      await offline.close();
    });
  });
}
