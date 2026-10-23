import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/weight_entry.dart';
import 'weight_chart.dart';
import 'weight_entry_sheet.dart';

/// The weight part of a pet's profile: the latest reading, how it has moved,
/// and the series behind it.
class WeightSection extends ConsumerWidget {
  const WeightSection({required this.petId, super.key});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(weightsForPetProvider(petId));
    final unit = ref.watch(weightUnitProvider).value ?? WeightUnit.kilograms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Weight', style: theme.textTheme.titleLarge),
            ),
            SegmentedButton<WeightUnit>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                for (final option in WeightUnit.values)
                  ButtonSegment(value: option, label: Text(option.label)),
              ],
              selected: {unit},
              onSelectionChanged: (selected) => ref
                  .read(settingsRepositoryProvider)
                  .setWeightUnit(selected.first),
            ),
            Tooltip(
              message: 'Add a weighing',
              child: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => showWeightEntrySheet(context, petId: petId),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        entries.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text('$error'),
          data: (entries) => _Body(entries: entries, unit: unit),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.entries, required this.unit});

  final List<WeightEntry> entries;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No weighings recorded.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final latest = entries.last;
    final previous = entries.length > 1 ? entries[entries.length - 2] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Latest(latest: latest, previous: previous, unit: unit),
        const SizedBox(height: 16),
        if (entries.length < 2)
          Text(
            'One more weighing and there will be a trend to show.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          SizedBox(
            height: 200,
            child: WeightChart(entries: entries, unit: unit),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _showHistory(context, ref),
          child: Text('All ${entries.length} weighings'),
        ),
      ],
    );
  }

  void _showHistory(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries.reversed)
              ListTile(
                title: Text('${unit.format(entry.grams)} ${unit.label}'),
                subtitle: Text(
                  [
                    DateFormat.yMMMd().format(entry.measuredOn),
                    if (entry.note != null) entry.note!,
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Delete weighing',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref
                        .read(weightRepositoryProvider)
                        .delete(entry.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The number owners actually look for, with the change since last time.
class _Latest extends StatelessWidget {
  const _Latest({
    required this.latest,
    required this.previous,
    required this.unit,
  });

  final WeightEntry latest;
  final WeightEntry? previous;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final earlier = previous;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          unit.format(latest.grams),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            unit.label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (earlier != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _change(earlier.grams, latest.grams),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// Change since the previous weighing, signed.
  ///
  /// Deliberately not coloured red or green: weight going up is not bad news
  /// for a kitten and not good news for an overweight cat, and the app is in
  /// no position to judge which it is looking at.
  String _change(int fromGrams, int toGrams) {
    final difference = unit.fromGrams(toGrams) - unit.fromGrams(fromGrams);
    if (difference.abs() < 0.005) {
      return 'no change';
    }
    final sign = difference > 0 ? '+' : '−';
    final size = difference.abs().toStringAsFixed(
      unit == WeightUnit.kilograms ? 2 : 1,
    );
    return '$sign$size ${unit.label}';
  }
}
