import 'dart:async';

import '../../data/repositories/settings_repository.dart';
import 'entitlement_source.dart';

/// Stands in for a store.
///
/// Used by a build with no RevenueCat key — development, CI, the whole test
/// suite — and it never claims to sell anything: [plans] is empty and
/// [purchase] fails, so a missing key cannot be mistaken for a working store.
/// Only the debug unlock flips it.
class StubEntitlements implements EntitlementSource {
  StubEntitlements(this._settings);

  final SettingsRepository _settings;

  @override
  Stream<bool> watchActive() => _settings.watchIsPremium();

  @override
  Future<bool> isActive() => _settings.isPremium();

  @override
  Future<List<PremiumPlan>> plans() async => const [];

  @override
  Future<PurchaseOutcome> purchase(PremiumPlan plan) async =>
      PurchaseOutcome.failed;

  @override
  Future<PurchaseOutcome> restore() async => PurchaseOutcome.nothingToRestore;

  /// The debug-only unlock behind the paywall.
  Future<void> setUnlocked({required bool value}) =>
      _settings.setPremium(value: value);
}
