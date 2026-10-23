import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../domain/dose_schedule.dart';
import '../../core/theme/category_palette.dart';
import '../../core/widgets/paw_mark.dart';
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
      // No AppBar: the greeting is the header, and it scrolls with the list
      // rather than sitting in a fixed-height bar that cannot hold scaled
      // text.
      // Without an AppBar there is nothing holding the top inset, so the
      // greeting would sit under the status bar.
      body: SafeArea(
        bottom: false,
        child: groups.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Something went wrong.\n$error')),
          data: (groups) => groups.isEmpty
              ? _NothingDue(now: now)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  children: [
                    _Greeting(now: now, groups: groups),
                    for (final group in groups)
                      _PetSection(group: group, startOfToday: startOfToday),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NothingDue extends StatelessWidget {
  const _NothingDue({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _Greeting(now: now, groups: const []),
        const SizedBox(height: 60),
        Column(
          children: [
            const AnimatedPawMark(size: 72),
            const SizedBox(height: 20),
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
      ],
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
        for (final (index, item) in overdue.indexed)
          _DueRow(item: item, isOverdue: true, position: index),
        for (final (index, item) in dueToday.indexed)
          _DueRow(
            item: item,
            isOverdue: false,
            position: overdue.length + index,
          ),
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
          for (final (index, dose) in group.doses.indexed)
            _DoseRow(
              dose: dose,
              position: overdue.length + dueToday.length + index,
            ),
        ],
      ],
    );
  }
}

/// One dose of the day. Unlike a reminder, a dose whose time has not come is
/// still shown — the owner wants the whole day's course in front of them.
class _DoseRow extends ConsumerWidget {
  const _DoseRow({required this.dose, this.position = 0});

  final DueDose dose;
  final int position;

  Future<void> _log(BuildContext context, WidgetRef ref, bool taken) async {
    final doses = ref.read(doseLogRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = taken
        ? await doses.logTaken(dose.dose.id)
        : await doses.skip(dose.dose.id);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${dose.medicine.name} ${taken ? 'logged' : 'skipped'}'),
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

    return _Arriving(
      position: position,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              _Glyph(
                icon: Icons.medication_liquid_outlined,
                color: isMissed ? scheme.error : context.categories.medicine,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.medicine.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        time,
                        if (dose.medicine.dosage != null) dose.medicine.dosage!,
                        if (!dose.dose.isPending) dose.dose.status.label,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isMissed
                            ? scheme.error
                            : scheme.onSurfaceVariant,
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
  const _DueRow({
    required this.item,
    required this.isOverdue,
    this.position = 0,
  });

  final DueItem item;
  final bool isOverdue;

  /// Where this row sits in the list, so they arrive in order.
  final int position;

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

    return _Arriving(
      position: position,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              _Glyph(
                icon: _iconFor(item.reminder.category),
                color: isOverdue
                    ? scheme.error
                    : context.categories.of(item.reminder.category),
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
      ),
    );
  }

  String _dueLabel(BuildContext context) {
    final scheduled = item.event.scheduledFor.toLocal();
    final snoozed = item.event.snoozedUntil;

    if (isOverdue) {
      final days = localDateOnly(
        DateTime.now(),
      ).difference(localDateOnly(item.event.scheduledFor)).inDays;
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

/// A row arriving: a short fade and lift, offset by its place in the list so
/// the day appears in order rather than all at once.
///
/// Plays once, briefly. A list that keeps moving is a list nobody can read.
class _Arriving extends StatelessWidget {
  const _Arriving({required this.position, required this.child});

  final int position;
  final Widget child;

  @override
  Widget build(BuildContext context) => child
      .animate(delay: Duration(milliseconds: 40 * position.clamp(0, 8)))
      .fadeIn(duration: 260.ms)
      .slideY(begin: 0.12, curve: Curves.easeOutCubic);
}

/// A category's icon on its own tinted disc.
///
/// The colour is what tells the kinds of care apart at a glance; the icon
/// repeats it so it never rests on colour alone.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, size: 22, color: color),
  );
}

/// A greeting, the date, and how much is still outstanding.
///
/// "Today" in a bar told the owner nothing. What they opened the app to find
/// out is whether anything is waiting, and whether any of it is late.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.now, required this.groups});

  final DateTime now;
  final List<PetDayGroup> groups;

  String get _timeOfDay {
    final hour = now.hour;
    if (hour < 12) {
      return 'Good morning';
    }
    return hour < 18 ? 'Good afternoon' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final outstanding = groups.fold<int>(
      0,
      (total, group) =>
          total +
          group.overdue.length +
          group.dueToday.length +
          group.doses.where((dose) => dose.dose.isPending).length,
    );
    final overdue = groups.fold<int>(
      0,
      (total, group) => total + group.overdue.length,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _timeOfDay,
                        style: theme.textTheme.headlineMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PawMark(size: 20, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat.yMMMMEEEEd().format(now),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (outstanding > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: overdue > 0 ? scheme.errorContainer : scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$outstanding left',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: overdue > 0
                      ? scheme.onErrorContainer
                      : scheme.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 320.ms);
  }
}
