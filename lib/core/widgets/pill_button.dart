import 'package:flutter/material.dart';

import 'paw_mark.dart';

/// The app's main call to action: a long pill with a dark disc on the left
/// holding an icon, and the label centred in the remaining space.
///
/// The disc is what stops a full-width amber bar looking like a plain slab,
/// and it gives the paw somewhere to live outside the welcome screen.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Defaults to the paw mark.
  final IconData? icon;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null && !busy;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSecondary,
                          ),
                        )
                      : icon == null
                      ? PawMark(size: 22, color: scheme.onSecondary)
                      : Icon(icon, size: 20, color: scheme.onSecondary),
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                // Balances the disc, so the label sits truly centred.
                const SizedBox(width: 46),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small fact on a pastel tile: the value above, what it is below.
///
/// Facts about a pet are short and unrelated to each other, which is exactly
/// what a row of tiles reads better than a paragraph.
class FactChip extends StatelessWidget {
  const FactChip({
    required this.value,
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String value;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
