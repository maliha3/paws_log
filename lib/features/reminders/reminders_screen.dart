import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/category_palette.dart';
import '../../core/widgets/empty_section.dart';
import '../../core/widgets/reminder_draft_sheet.dart';
import '../../data/providers.dart';
import '../../domain/dose_schedule.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_draft.dart';

/// One pet's recurring care, where it can be added to and changed.
///
/// Until this existed, reminders could only be created during onboarding:
/// a second pet got none at all, and nobody could change a schedule after the
/// first run.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({required this.petId, super.key});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);
    final pet = pets.hasValue
        ? pets.requireValue.where((pet) => pet.id == petId).firstOrNull
        : null;
    final reminders = ref.watch(remindersForPetProvider(petId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pet == null ? 'Reminders' : '${pet.name}’s reminders',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a reminder',
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: reminders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Something went wrong.\n$error'),
        ),
        data: (all) {
          final active = all.where((reminder) => reminder.isActive).toList();
          final paused = all.where((reminder) => !reminder.isActive).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (all.isEmpty)
                const EmptySection(
                  icon: Icons.notifications_none,
                  message:
                      'No reminders yet. Add the care that comes round again '
                      'and it turns up on Today, with a notification when it '
                      'is due.',
                ),
              for (final reminder in active)
                _ReminderTile(reminder: reminder),
              if (paused.isNotEmpty) ...[
                if (active.isNotEmpty) const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Text(
                    'Paused',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final reminder in paused)
                  _ReminderTile(reminder: reminder),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showReminderDraftSheet(context);
    if (draft == null) {
      return;
    }
    await ref.read(reminderRepositoryProvider).create(
      petId: petId,
      title: draft.title,
      category: draft.category,
      repeat: draft.repeat,
      anchorDate: draft.firstDue,
      timeOfDayMinutes: draft.timeOfDayMinutes,
      notes: draft.notes,
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colour = context.categories.of(reminder.category);
    final time = TimeOfDay(
      hour: reminder.timeOfDayMinutes ~/ 60,
      minute: reminder.timeOfDayMinutes % 60,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: Icon(_iconFor(reminder.category), color: colour),
        title: Text(
          reminder.title,
          style: TextStyle(
            decoration: reminder.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        isThreeLine: true,
        subtitle: Text(
          [
            reminder.category.label,
            reminder.repeat.describe(),
            time.format(context),
            _nextDue(reminder),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Reminder options',
          onSelected: (action) => _run(context, ref, action),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(reminder.isActive ? 'Pause' : 'Resume'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repository = ref.read(reminderRepositoryProvider);
    switch (action) {
      case 'edit':
        final draft = await showReminderDraftSheet(
          context,
          draft: ReminderDraft.fromReminder(reminder),
        );
        if (draft != null) {
          await repository.update(draft.applyTo(reminder));
        }
      case 'toggle':
        await repository.setActive(
          reminder.id,
          isActive: !reminder.isActive,
        );
      case 'delete':
        await repository.delete(reminder.id);
    }
  }

  /// When it next comes round, in the words an owner thinks in.
  ///
  /// A paused reminder says so instead: its stored due date is whatever it
  /// was when it stopped, and reading that as "overdue" would be a reproach
  /// for something the owner switched off on purpose.
  static String _nextDue(Reminder reminder) {
    if (!reminder.isActive) {
      return 'paused';
    }
    final due = reminder.nextDueAt;
    if (due == null) {
      return 'done';
    }
    final today = startOfLocalDay(DateTime.now());
    final dueDay = startOfLocalDay(due);

    if (dueDay.isBefore(today)) {
      return 'overdue';
    }
    if (dueDay == today) {
      return 'due today';
    }
    return 'next ${DateFormat.MMMd().format(localDateOnly(due))}';
  }

  static IconData _iconFor(ReminderCategory category) => switch (category) {
    ReminderCategory.vaccine => Icons.vaccines_outlined,
    ReminderCategory.deworming => Icons.medication_outlined,
    ReminderCategory.fleaTick => Icons.bug_report_outlined,
    ReminderCategory.nailTrim => Icons.content_cut_outlined,
    ReminderCategory.brushing => Icons.brush_outlined,
    ReminderCategory.other => Icons.event_note_outlined,
  };
}
