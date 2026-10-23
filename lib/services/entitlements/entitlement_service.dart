import 'dart:async';

import '../../data/repositories/settings_repository.dart';
import 'entitlement_source.dart';

/// The app's single answer to "is this unlocked".
///
/// Wraps a source and mirrors every answer into the settings table. That
/// cache is the point: the store is a network call, and a paying owner
/// opening the app on a train must not be told they have lost access while
/// RevenueCat is unreachable. The store stays the source of truth; the cache
/// only covers the gap before it answers.
class EntitlementService {
  EntitlementService({required this.source, required this.settings});

  final EntitlementSource source;
  final SettingsRepository settings;

  /// Live state, starting from the cached value so the first frame is right.
  Stream<bool> watchActive() async* {
    yield await settings.isPremium();
    await for (final active in source.watchActive()) {
      await _remember(active);
      yield active;
    }
  }

  /// The gate's question. Answers from the cache when the source cannot.
  Future<bool> isActive() async {
    final cached = await settings.isPremium();
    try {
      final active = await source.isActive();
      await _remember(active);
      return active;
    } on Object {
      return cached;
    }
  }

  Future<List<PremiumPlan>> plans() => source.plans();

  Future<PurchaseOutcome> purchase(PremiumPlan plan) async {
    final outcome = await source.purchase(plan);
    if (outcome == PurchaseOutcome.unlocked) {
      await _remember(true);
    }
    return outcome;
  }

  Future<PurchaseOutcome> restore() async {
    final outcome = await source.restore();
    if (outcome == PurchaseOutcome.unlocked) {
      await _remember(true);
    }
    return outcome;
  }

  Future<void> _remember(bool active) async {
    if (await settings.isPremium() != active) {
      await settings.setPremium(value: active);
    }
  }
}
