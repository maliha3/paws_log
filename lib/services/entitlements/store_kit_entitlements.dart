import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/purchase_config.dart';
import 'entitlement_source.dart';

/// The real entitlement source: Apple's own store, nothing in between.
///
/// The app sells one non-consumable, which is the case StoreKit handles
/// entirely on its own — Apple records the purchase against the buyer's
/// Apple Account, syncs it across their devices, and hands it back on a
/// restore. There is no receipt server to run and no third party to tell,
/// which is what lets the app claim that nothing it holds ever leaves the
/// phone.
///
/// Ownership is *not* queryable on demand through this plugin. The only way
/// to ask Apple "what does this person own" is [InAppPurchase.restorePurchases],
/// which replays past purchases through [InAppPurchase.purchaseStream]. So
/// the flow is: restore once at launch, listen to the stream, and let
/// `EntitlementService` cache the answer. That cache was always load-bearing;
/// here it is the thing that makes a cold start instant.
class StoreKitEntitlements implements EntitlementSource {
  StoreKitEntitlements({
    InAppPurchase? store,
    this.productId = PurchaseConfig.unlockProductId,
  }) : _store = store ?? InAppPurchase.instance {
    _subscription = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object error) => debugPrint('Purchase stream error: $error'),
    );
  }

  final InAppPurchase _store;
  final String productId;

  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  final StreamController<bool> _active = StreamController<bool>.broadcast();

  /// The last thing Apple said, or null before it has said anything.
  bool? _latest;

  /// Completers waiting on a purchase or restore the stream will finish.
  Completer<PurchaseOutcome>? _pending;

  /// Asks Apple what this person already owns.
  ///
  /// Called once from `main`. Results arrive on the purchase stream rather
  /// than from this future, so nothing waits on it.
  Future<void> start() async {
    if (!await _store.isAvailable()) {
      _publish(false);
      return;
    }
    await _store.restorePurchases();
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.productID != productId) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _publish(true);
          _finish(PurchaseOutcome.unlocked);
        case PurchaseStatus.canceled:
          _finish(PurchaseOutcome.cancelled);
        case PurchaseStatus.error:
          debugPrint('Purchase failed: ${purchase.error}');
          _finish(PurchaseOutcome.failed);
        case PurchaseStatus.pending:
          // Ask-to-buy, or a slow payment sheet. Nothing to report yet.
          break;
      }

      // Apple keeps re-delivering a transaction until it is acknowledged,
      // so this has to happen whatever the outcome was.
      if (purchase.pendingCompletePurchase) {
        unawaited(_store.completePurchase(purchase));
      }
    }
  }

  void _publish(bool active) {
    _latest = active;
    if (!_active.isClosed) {
      _active.add(active);
    }
  }

  void _finish(PurchaseOutcome outcome) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
    _pending = null;
  }

  @override
  Stream<bool> watchActive() async* {
    if (_latest != null) {
      yield _latest!;
    }
    yield* _active.stream;
  }

  @override
  Future<bool> isActive() async => _latest ?? false;

  @override
  Future<List<PremiumPlan>> plans() async {
    if (!await _store.isAvailable()) {
      return const [];
    }
    final response = await _store.queryProductDetails({productId});
    if (response.error != null) {
      debugPrint('Could not load products: ${response.error}');
      return const [];
    }
    return [
      for (final product in response.productDetails)
        PremiumPlan(
          id: product.id,
          kind: PlanKind.lifetime,
          // Apple's own localised string, formatted for the buyer's store
          // front. The app never formats a price itself.
          price: product.price,
        ),
    ];
  }

  @override
  Future<PurchaseOutcome> purchase(PremiumPlan plan) async {
    if (!await _store.isAvailable()) {
      return PurchaseOutcome.failed;
    }
    final response = await _store.queryProductDetails({plan.id});
    final product = response.productDetails.firstOrNull;
    if (product == null) {
      return PurchaseOutcome.failed;
    }

    final waiting = _pending = Completer<PurchaseOutcome>();
    try {
      // A non-consumable, so this is the right call: `buyConsumable` would
      // let it be bought twice.
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        _pending = null;
        return PurchaseOutcome.failed;
      }
    } on Object catch (error) {
      debugPrint('Could not start a purchase: $error');
      _pending = null;
      return PurchaseOutcome.failed;
    }
    return waiting.future;
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (!await _store.isAvailable()) {
      return PurchaseOutcome.nothingToRestore;
    }
    final waiting = _pending = Completer<PurchaseOutcome>();
    await _store.restorePurchases();

    // Nothing to restore is silence, not an answer: Apple replays whatever
    // exists and says nothing when that is nothing. So a short wait, then
    // take the silence as the answer.
    return waiting.future
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => PurchaseOutcome.nothingToRestore,
        )
        .whenComplete(() => _pending = null);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _active.close();
  }
}
