import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/purchase_config.dart';
import 'entitlement_source.dart';

/// The real entitlement source.
///
/// Every product grants one entitlement, so the app only ever asks a single
/// question — is it active — and never has to know which plan paid for it.
/// That is also what makes an upgrade from monthly to lifetime a non-event
/// here.
class RevenueCatEntitlements implements EntitlementSource {
  RevenueCatEntitlements({this.entitlementId = PurchaseConfig.entitlementId}) {
    // RevenueCat pushes a new CustomerInfo whenever the entitlement changes:
    // a renewal, a refund, a restore on another device. The app follows that
    // rather than polling.
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
  }

  final String entitlementId;

  final StreamController<bool> _active = StreamController<bool>.broadcast();

  bool? _latest;

  /// Starts the SDK. Safe to call once, from `main`.
  static Future<void> configure({required String apiKey}) async {
    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.error);
    }
    await Purchases.configure(PurchasesConfiguration(apiKey));
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = _isActive(info);
    _latest = active;
    if (!_active.isClosed) {
      _active.add(active);
    }
  }

  bool _isActive(CustomerInfo info) =>
      info.entitlements.active.containsKey(entitlementId);

  @override
  Stream<bool> watchActive() async* {
    yield await isActive();
    yield* _active.stream;
  }

  @override
  Future<bool> isActive() async {
    if (_latest != null) {
      return _latest!;
    }
    try {
      final info = await Purchases.getCustomerInfo();
      return _latest = _isActive(info);
    } on Object catch (error) {
      // Offline, or the store is having a bad day. The caller falls back to
      // the last known state rather than treating a network blip as a
      // cancellation.
      debugPrint('Could not read entitlements: $error');
      return false;
    }
  }

  @override
  Future<List<PremiumPlan>> plans() async {
    try {
      final offerings = await Purchases.getOfferings();
      final offering = PurchaseConfig.offeringId.isEmpty
          ? offerings.current
          : offerings.all[PurchaseConfig.offeringId];
      if (offering == null) {
        return const [];
      }

      final plans = <PremiumPlan>[];
      for (final package in offering.availablePackages) {
        final kind = _kindOf(package.packageType);
        if (kind == null) {
          // A package type the paywall does not sell. Ignored rather than
          // shown as something the owner cannot understand.
          continue;
        }
        plans.add(
          PremiumPlan(
            id: package.identifier,
            kind: kind,
            price: package.storeProduct.priceString,
          ),
        );
      }

      plans.sort((a, b) => a.kind.index.compareTo(b.kind.index));
      return _withYearlySaving(plans, offering);
    } on Object catch (error) {
      debugPrint('Could not load offerings: $error');
      return const [];
    }
  }

  /// Adds "save N%" to the yearly plan, worked out from the real prices
  /// rather than written into the copy, so it cannot drift from what the
  /// store charges or be wrong in another currency.
  List<PremiumPlan> _withYearlySaving(
    List<PremiumPlan> plans,
    Offering offering,
  ) {
    double? priceFor(PlanKind kind) {
      for (final package in offering.availablePackages) {
        if (_kindOf(package.packageType) == kind) {
          return package.storeProduct.price;
        }
      }
      return null;
    }

    final monthly = priceFor(PlanKind.monthly);
    final yearly = priceFor(PlanKind.yearly);
    if (monthly == null || yearly == null || monthly <= 0) {
      return plans;
    }
    final saving = (1 - (yearly / (monthly * 12))) * 100;
    if (saving < 1) {
      return plans;
    }

    return [
      for (final plan in plans)
        if (plan.kind == PlanKind.yearly)
          PremiumPlan(
            id: plan.id,
            kind: plan.kind,
            price: plan.price,
            highlight: 'Save ${saving.round()}%',
          )
        else
          plan,
    ];
  }

  static PlanKind? _kindOf(PackageType type) => switch (type) {
    PackageType.monthly => PlanKind.monthly,
    PackageType.annual => PlanKind.yearly,
    PackageType.lifetime => PlanKind.lifetime,
    _ => null,
  };

  @override
  Future<PurchaseOutcome> purchase(PremiumPlan plan) async {
    try {
      final offerings = await Purchases.getOfferings();
      final offering = PurchaseConfig.offeringId.isEmpty
          ? offerings.current
          : offerings.all[PurchaseConfig.offeringId];
      final package = offering?.availablePackages
          .where((candidate) => candidate.identifier == plan.id)
          .firstOrNull;
      if (package == null) {
        return PurchaseOutcome.failed;
      }

      final result = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      final active = _isActive(result.customerInfo);
      _latest = active;
      return active ? PurchaseOutcome.unlocked : PurchaseOutcome.failed;
    } on PlatformException catch (error) {
      // Backing out of the sheet is the most common outcome of all and is
      // not a failure, so it never reaches the owner as an error.
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      debugPrint('Purchase failed: $error');
      return PurchaseOutcome.failed;
    } on Object catch (error) {
      debugPrint('Purchase failed: $error');
      return PurchaseOutcome.failed;
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      final active = _isActive(info);
      _latest = active;
      return active
          ? PurchaseOutcome.unlocked
          : PurchaseOutcome.nothingToRestore;
    } on Object catch (error) {
      debugPrint('Restore failed: $error');
      return PurchaseOutcome.failed;
    }
  }
}
