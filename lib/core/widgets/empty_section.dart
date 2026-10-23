import 'package:flutter/material.dart';

/// What a section shows before anything is in it.
///
/// An empty section is the first thing most owners see, so it says what the
/// section is for and how something gets into it, rather than only that it is
/// empty.
class EmptySection extends StatelessWidget {
  const EmptySection({required this.icon, required this.message, super.key});

  final IconData icon;

  /// One sentence: what this holds, and how it gets filled.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
