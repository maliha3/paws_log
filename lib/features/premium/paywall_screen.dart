import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/purchase_config.dart';
import '../../data/providers.dart';
import '../../services/entitlements/entitlement_source.dart';
import '../../services/entitlements/stub_entitlements.dart';
import 'premium_gate.dart';

/// Shows what unlocking buys, for the feature that was just reached for.
Future<void> showPaywall(
  BuildContext context, {
  required PremiumFeature feature,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => PaywallScreen(feature: feature),
);

/// The paywall.
///
/// Everything Apple requires before a purchase is on this one sheet: the
/// title and length of each plan, its price in the owner's own currency
/// straight from the store, that a subscription renews until cancelled,
/// Restore Purchases, and links to the terms and the privacy policy. None of
/// the prices are written into the app — it has no idea about the owner's
/// currency, tax, or regional pricing.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({required this.feature, super.key});

  final PremiumFeature feature;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// What unlocking buys, under the one line that explains it.
  ///
  /// A list of three unrelated unlocks reads as thin whatever the price. One
  /// idea — the household rather than the cat — reads as a product, and the
  /// other two become things that come with it.
  static const List<({IconData icon, String title, String detail})> _benefits =
      [
        (
          icon: Icons.pets_outlined,
          title: 'Every cat you have',
          detail: 'Reminders, medicines and records for all of them.',
        ),
        (
          icon: Icons.document_scanner_outlined,
          title: 'Every prescription',
          detail: 'Scan and read as many as you are given.',
        ),
        (
          icon: Icons.description_outlined,
          title: 'The vet summary',
          detail: 'One page to hand over at the appointment.',
        ),
      ];

  String? _busyPlanId;
  bool _restoring = false;

  Future<void> _buy(PremiumPlan plan) async {
    setState(() => _busyPlanId = plan.id);
    final outcome = await ref.read(entitlementServiceProvider).purchase(plan);
    if (!mounted) {
      return;
    }
    setState(() => _busyPlanId = null);
    _report(outcome, bought: true);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final outcome = await ref.read(entitlementServiceProvider).restore();
    if (!mounted) {
      return;
    }
    setState(() => _restoring = false);
    _report(outcome, bought: false);
  }

  void _report(PurchaseOutcome outcome, {required bool bought}) {
    // Backing out of the store sheet is the commonest outcome there is, and
    // is not a failure. Saying nothing is the right response to it.
    if (outcome == PurchaseOutcome.cancelled) {
      return;
    }
    if (outcome == PurchaseOutcome.unlocked) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(bought ? 'Paws Log is unlocked.' : 'Purchases restored.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          PurchaseOutcome.nothingToRestore =>
            'No previous purchase found on this Apple Account.',
          _ => 'That did not go through. Nothing has been charged.',
        }),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open that.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plans = ref.watch(premiumPlansProvider);
    final busy = _busyPlanId != null || _restoring;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.feature.headline, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              widget.feature.explanation,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // The whole offer in one line, above the list rather than
            // assembled from it.
            Text(
              'One cat free. The whole household, once.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            for (final benefit in _benefits) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(benefit.icon, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(benefit.title, style: theme.textTheme.titleMedium),
                        Text(
                          benefit.detail,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _Unavailable(onRetry: () => ref.invalidate(premiumPlansProvider)),
              data: (plans) => plans.isEmpty
                  ? _Unavailable(
                      onRetry: () => ref.invalidate(premiumPlansProvider),
                    )
                  : Column(
                      children: [
                        for (final plan in plans)
                          _PlanTile(
                            plan: plan,
                            busy: busy,
                            working: _busyPlanId == plan.id,
                            onTap: () => _buy(plan),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            // Apple requires this to be reachable without buying anything.
            TextButton(
              onPressed: busy ? null : _restore,
              child: _restoring
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Restore purchases'),
            ),
            const SizedBox(height: 8),
            _LegalFooter(
              onOpen: _open,
              // Only describe renewal when something on screen renews.
              renews: plans.hasValue &&
                  plans.requireValue.any((plan) => plan.kind.renews),
            ),
            // Debug *and* no real store behind it. A build that can take
            // money must never offer a button that skips paying, not even
            // one a reviewer would have to go looking for.
            if (kDebugMode && !PurchaseConfig.sellsThroughStore) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                // Debug only. Without it the paid half of the app would be
                // unreachable on a build with no store keys.
                onPressed: () async {
                  final source = ref.read(entitlementSourceProvider);
                  if (source is StubEntitlements) {
                    await source.setUnlocked(value: true);
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Simulate unlock (debug)'),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.busy,
    required this.working,
    required this.onTap,
  });

  final PremiumPlan plan;
  final bool busy;
  final bool working;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        plan.kind.title,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (plan.highlight != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            plan.highlight!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // The price and the renewal terms, together, in the words
                  // Apple expects to see before a purchase.
                  Text(
                    plan.terms,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (working)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(plan.price, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Shown when the store has nothing to sell — no keys in this build, no
/// network, or no products approved yet.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Purchases are not available right now.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.onOpen, required this.renews});

  final Future<void> Function(String url) onOpen;

  /// Whether anything on offer actually renews.
  final bool renews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // A build with store keys is a build that can take money, and Apple
    // requires a policy link before it does. Shipping without one used to
    // hide the link and say nothing.
    final missingPolicy =
        PurchaseConfig.sellsThroughStore && PurchaseConfig.privacyUrl.isEmpty;

    return Column(
      children: [
        Text(
          renews
              ? 'Payment is charged to your Apple Account. A subscription '
                    'renews automatically unless it is cancelled at least 24 '
                    'hours before the period ends. Manage or cancel it in '
                    'your Apple Account settings.'
              : 'Payment is charged to your Apple Account. This is a '
                    'one-off purchase, not a subscription \u2014 there is '
                    'nothing to renew or cancel.',
          textAlign: TextAlign.center,
          style: style,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => onOpen(PurchaseConfig.termsUrl),
              child: const Text('Terms of Use'),
            ),
            if (PurchaseConfig.privacyUrl.isNotEmpty)
              TextButton(
                onPressed: () => onOpen(PurchaseConfig.privacyUrl),
                child: const Text('Privacy Policy'),
              ),
          ],
        ),
        if (missingPolicy) ...[
          const SizedBox(height: 4),
          Text(
            'This build has store keys but no PRIVACY_URL. Apple requires '
            'the policy link on the paywall \u2014 rebuild with '
            '--dart-define=PRIVACY_URL=...',
            textAlign: TextAlign.center,
            style: style?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
