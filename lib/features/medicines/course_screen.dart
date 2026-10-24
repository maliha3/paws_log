import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/category_palette.dart';
import '../../data/providers.dart';
import '../../domain/models/dose_log.dart';
import '../../domain/models/medicine.dart';
import 'medicine_edit_screen.dart';

/// How one course is going, and every dose it has produced.
///
/// The counts were computed in the repository from the start and shown
/// nowhere. "Did the cat actually finish the course" is the question the
/// medicine tracker exists to answer, and until this screen the app could
/// not answer it.
class CourseScreen extends ConsumerWidget {
  const CourseScreen({required this.petId, required this.medicine, super.key});

  final String petId;
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(adherenceForMedicineProvider(medicine.id));
    final doses = ref.watch(dosesForMedicineProvider(medicine.id));
    final schedule = medicine.schedule;

    final times = schedule.timesOfDayMinutes
        .map(
          (minutes) => TimeOfDay(
            hour: minutes ~/ 60,
            minute: minutes % 60,
          ).format(context),
        )
        .join(', ');
    final run = schedule.isOpenEnded
        ? 'from ${DateFormat.yMMMd().format(schedule.startDate)}, ongoing'
        : '${DateFormat.yMMMd().format(schedule.startDate)} – '
              '${DateFormat.yMMMd().format(schedule.endDate!)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(medicine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit medicine',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    MedicineEditScreen(petId: petId, medicine: medicine),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            [if (medicine.dosage != null) medicine.dosage!, times, run]
                .join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text('How it is going', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          counts.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('$error'),
            data: (adherence) => _Summary(adherence: adherence),
          ),
          const SizedBox(height: 24),
          Text('Every dose', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          doses.when(
            loading: () => const SizedBox.shrink(),
            error: (error, _) => Text('$error'),
            data: (all) => all.isEmpty
                ? Text(
                    'No doses yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(children: [for (final dose in all) _DoseRow(dose: dose)]),
          ),
        ],
      ),
    );
  }
}

/// The partition, in words and as a bar.
class _Summary extends StatelessWidget {
  const _Summary({required this.adherence});

  final Adherence adherence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.categories;
    final parts = <(String, int, Color)>[
      ('taken', adherence.taken, palette.deworming),
      ('missed', adherence.missed, theme.colorScheme.error),
      ('skipped', adherence.skipped, palette.other),
      ('still to come', adherence.pending, palette.vaccine),
    ];
    final logged = adherence.taken + adherence.missed + adherence.skipped;
    final total = logged + adherence.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final part in parts)
                    if (part.$2 > 0)
                      Expanded(
                        flex: part.$2,
                        child: ColoredBox(color: part.$3),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        // Wrapped, not a row: four counts do not fit across a phone at the
        // largest text sizes.
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final part in parts)
              if (part.$2 > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: part.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${part.$2} ${part.$1}'),
                  ],
                ),
          ],
        ),
        if (logged == 0) ...[
          const SizedBox(height: 8),
          Text(
            'Nothing logged yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});

  final DoseLog dose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = dose.scheduledFor.toLocal();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(_iconFor(dose.status), size: 20, color: _colourFor(context)),
      title: Text(DateFormat.yMMMEd().format(local)),
      subtitle: Text(
        TimeOfDay.fromDateTime(local).format(context),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(dose.status.label, style: theme.textTheme.bodySmall),
    );
  }

  Color _colourFor(BuildContext context) => switch (dose.status) {
    DoseStatus.taken => context.categories.deworming,
    DoseStatus.missed => Theme.of(context).colorScheme.error,
    DoseStatus.skipped => context.categories.other,
    DoseStatus.pending => context.categories.vaccine,
  };

  static IconData _iconFor(DoseStatus status) => switch (status) {
    DoseStatus.taken => Icons.check_circle_outline,
    DoseStatus.missed => Icons.cancel_outlined,
    DoseStatus.skipped => Icons.remove_circle_outline,
    DoseStatus.pending => Icons.schedule,
  };
}
