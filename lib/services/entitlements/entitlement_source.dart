/// How a plan is sold.
enum PlanKind {
  monthly,
  yearly,
  lifetime;

  bool get renews => this != PlanKind.lifetime;

  String get title => switch (this) {
    PlanKind.monthly => 'Monthly',
    PlanKind.yearly => 'Yearly',
    PlanKind.lifetime => 'Lifetime',
  };

  /// What the owner is actually agreeing to, in the words Apple expects on
  /// the paywall itself.
  String terms(String price) => switch (this) {
    PlanKind.monthly =>
      '$price per month. Renews automatically until cancelled.',
    PlanKind.yearly =>
      '$price per year. Renews automatically until cancelled.',
    PlanKind.lifetime => '$price once. No subscription.',
  };
}

/// A plan as the paywall shows it.
///
/// Prices are always the store's own localised strings — never formatted by
/// the app, which has no idea about the owner's currency, tax or regional
/// pricing.
class PremiumPlan {
  const PremiumPlan({
    required this.id,
    required this.kind,
    required this.price,
    this.highlight,
  });

  final String id;
  final PlanKind kind;

  /// Localised, straight from the store.
  final String price;

  /// Something worth saying about this plan, e.g. a saving against monthly.
  final String? highlight;

  String get terms => kind.terms(price);
}

/// What came of a purchase or restore.
enum PurchaseOutcome {
  unlocked,

  /// The owner backed out. Not an error, and never shown as one.
  cancelled,

  /// Nothing to restore on this account.
  nothingToRestore,

  failed,
}

/// Where the premium entitlement comes from.
///
/// An interface so the paywall and the gate can be exercised without a store:
/// the real source talks to RevenueCat, the stub keeps a flag locally.
abstract interface class EntitlementSource {
  /// Whether the entitlement is active, as it changes.
  Stream<bool> watchActive();

  /// The current value, resolved as quickly as this source can manage.
  Future<bool> isActive();

  /// The plans on offer. Empty when the store has nothing configured, which
  /// the paywall has to handle rather than show an empty list.
  Future<List<PremiumPlan>> plans();

  Future<PurchaseOutcome> purchase(PremiumPlan plan);

  Future<PurchaseOutcome> restore();
}
