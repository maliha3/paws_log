import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/dose_schedule.dart';
import '../../core/widgets/pet_avatar.dart';
import '../../data/providers.dart';
import '../../domain/models/due_dose.dart';
import '../../domain/models/due_item.dart';
import '../../domain/models/dose_log.dart';
import '../../domain/models/reminder.dart';
import 'today_controller.dart';

/// What is due today or already overdue, across every pet, grouped by pet.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(todayProvider);
    final now = DateTime.now();
    // Overdue means "due on an earlier day", so the comparison is against
    // the start of today rather than the current moment — in the app's zone,
    // which is the same one the dates were built in.
    final startOfToday = startOfLocalDay(now);

    return Scaffold(
      // The date sits in the list rather than under the title: an AppBar
      // bottom has a fixed height, which cannot hold the text once someone
      // turns their type size up.
      appBar: AppBar(title: const Text('Today')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong.\n$error')),
        data: (groups) => groups.isEmpty
            ? const _NothingDue()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text(
                      DateFormat.yMMMMEEEEd().format(now),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final group in groups)
                    _PetSection(group: group, startOfToday: startOfToday),
                ],
              ),
      ),
    );
  }
}

class _NothingDue extends StatelessWidget {
  const _NothingDue();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Nothing due today', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Reminders and doses turn up here on the day they are due.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pet's heading and their due items, overdue ones first.
class _PetSection extends StatelessWidget {
  const _PetSection({required this.group, required this.startOfToday});

  final PetDayGroup group;
  final DateTime startOfToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = group.overdue;
    final dueToday = group.dueToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              PetAvatar(name: group.pet.name, photoPath: group.pet.photoPath),
              const SizedBox(width: 12),
              // The badge takes the width it needs and the name gives way:
              // at large text sizes "3 overdue" is wider than the name.
              Expanded(
                child: Text(
                  group.pet.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (overdue.isNotEmpty)
                _Badge(
                  label: '${overdue.length} overdue',
                  color: theme.colorScheme.errorContainer,
                  onColor: theme.colorScheme.onErrorContainer,
                ),
            ],
          ),
        ),
        for (final item in overdue) _DueRow(item: item, isOverdue: true),
        for (final item in dueToday) _DueRow(item: item, isOverdue: false),
        if (group.doses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              'Medicines',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final dose in group.doses) _DoseRow(dose: dose),
        ],
      ],
    );
  }
}

/// One dose of the day. Unlike a reminder, a dose whose time has not come is
/// still shown — the owner wants the whole day's course in front of them.
class _DoseRow extends ConsumerWidget {
  const _DoseRow({required this.dose});

  final DueDose dose;

  Future<void> _log(BuildContext context, WidgetRef ref, bool taken) async {
    final doses = ref.read(doseLogRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = taken
        ? await doses.logTaken(dose.dose.id)
        : await doses.skip(dose.dose.id);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${dose.medicine.name} ${taken ? 'logged' : 'skipped'}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          // Holds the repository, not `ref`: logging rebuilds this row away,
          // so by the time the action fires its ref is disposed.
          onPressed: () => doses.undo(outcome),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = TimeOfDay.fromDateTime(
      dose.dose.scheduledFor.toLocal(),
    ).format(context);
    final isMissed = dose.dose.status == DoseStatus.missed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(
              Icons.medication_liquid_outlined,
              color: isMissed ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dose.medicine.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    [
                      time,
                      if (dose.medicine.dosage != null) dose.medicine.dosage!,
                      if (!dose.dose.isPending) dose.dose.status.label,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isMissed ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight: isMissed ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (dose.dose.status == DoseStatus.taken)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.check_circle, color: scheme.primary),
              )
            else
              FilledButton.tonal(
                onPressed: () => _log(context, ref, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: const Text('Take'),
              ),
            PopupMenuButton<bool>(
              tooltip: 'Dose options',
              onSelected: (taken) => _log(context, ref, taken),
              itemBuilder: (context) => const [
                PopupMenuItem(value: true, child: Text('Mark taken')),
                PopupMenuItem(value: false, child: Text('Skip')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: onColor,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// One due item, with Done as a single tap.
class _DueRow extends ConsumerWidget {
  const _DueRow({required this.item, required this.isOverdue});

  final DueItem item;
  final bool isOverdue;

  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    final events = ref.read(reminderEventRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await events.markDone(item.event.id);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${item.reminder.title} done'),
        action: SnackBarAction(
          label: 'Undo',
          // Holds the repository, not `ref`: completing removes this row from
          // the tree, so by the time the action fires its ref is disposed.
          // Fire-and-forget — the stream puts the row back on screen.
          onPressed: () => events.undo(outcome),
        ),
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    _RowAction action,
  ) async {
    final events = ref.read(reminderEventRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    switch (action) {
      case _RowAction.snoozeHour:
        await events.snoozeOneHour(item.event.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Snoozed for an hour')),
        );
      case _RowAction.snoozeTomorrow:
        await events.snoozeToTomorrow(item.event.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Snoozed to tomorrow')),
        );
      case _RowAction.skip:
        final outcome = await events.skip(item.event.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text('${item.reminder.title} skipped'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => events.undo(outcome),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(
              _iconFor(item.reminder.category),
              color: isOverdue ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.reminder.title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dueLabel(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isOverdue
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontWeight: isOverdue ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () => _markDone(context, ref),
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: theme.textTheme.labelLarge,
              ),
              child: const Text('Done'),
            ),
            PopupMenuButton<_RowAction>(
              tooltip: 'More',
              onSelected: (action) => _handleMenu(context, ref, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _RowAction.snoozeHour,
                  child: Text('Snooze 1 hour'),
                ),
                PopupMenuItem(
                  value: _RowAction.snoozeTomorrow,
                  child: Text('Snooze to tomorrow'),
                ),
                PopupMenuItem(value: _RowAction.skip, child: Text('Skip')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(BuildContext context) {
    final scheduled = item.event.scheduledFor.toLocal();
    final snoozed = item.event.snoozedUntil;

    if (isOverdue) {
      final days = localDateOnly(DateTime.now())
          .difference(localDateOnly(item.event.scheduledFor))
          .inDays;
      final overdueText = days <= 1
          ? 'Overdue since yesterday'
          : 'Overdue by $days days';
      return snoozed == null ? overdueText : '$overdueText · snoozed';
    }
    final time = TimeOfDay.fromDateTime(scheduled).format(context);
    return snoozed == null ? 'Due today at $time' : 'Due today · snoozed';
  }

  IconData _iconFor(ReminderCategory category) => switch (category) {
    ReminderCategory.vaccine => Icons.vaccines_outlined,
    ReminderCategory.deworming => Icons.medication_outlined,
    ReminderCategory.fleaTick => Icons.bug_report_outlined,
    ReminderCategory.other => Icons.event_note_outlined,
  };
}

enum _RowAction { snoozeHour, snoozeTomorrow, skip }
