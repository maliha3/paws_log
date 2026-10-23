import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
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
/// There is no purchase flow behind it yet — nothing here talks to a store or
/// checks a receipt. The unlock button says so rather than pretending to
/// charge, which would be the one thing worse than not shipping it.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({required this.feature, super.key});

  final PremiumFeature feature;

  static const List<({IconData icon, String title, String detail})> _benefits =
      [
        (
          icon: Icons.pets_outlined,
          title: 'Every pet',
          detail: 'Track the whole household, not just one.',
        ),
        (
          icon: Icons.photo_library_outlined,
          title: 'Photos on visits',
          detail: 'Lab results and prescriptions, kept with the visit.',
        ),
        (
          icon: Icons.description_outlined,
          title: 'Vet summary',
          detail: 'One page to hand over at the appointment.',
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      // Scrollable: a bottom sheet has only so much room, and at large text
      // sizes this content is taller than any phone.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(feature.headline, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              feature.explanation,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
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
                        Text(
                          benefit.title,
                          style: theme.textTheme.titleMedium,
                        ),
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
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Purchases are not available yet.'),
                ),
              ),
              child: const Text('Unlock PawsLog'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                // Debug only. Without it the paid half of the app would be
                // unreachable, and so untestable, until a store is wired up.
                onPressed: () async {
                  await ref
                      .read(settingsRepositoryProvider)
                      .setPremium(value: true);
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
