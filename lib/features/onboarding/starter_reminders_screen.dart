import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../domain/models/reminder_draft.dart';
import 'onboarding_controller.dart';
import 'widgets/reminder_draft_sheet.dart';

/// Third screen of onboarding: the starting schedule.
///
/// The three suggestions are common intervals, not medical advice, so every
/// row is editable, removable, and the vet disclaimer stays on screen.
class StarterRemindersScreen extends ConsumerWidget {
  const StarterRemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Starter reminders')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'We have suggested a few common ones for '
                      '${draft.name.trim()}. Change anything that does not fit.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _VetDisclaimer(),
                  const SizedBox(height: 16),
                  for (var index = 0; index < draft.reminders.length; index++)
                    _ReminderRow(
                      draft: draft.reminders[index],
                      onToggle: (enabled) =>
                          controller.toggleReminder(index, enabled: enabled),
                      onEdit: () async {
                        final edited = await showReminderDraftSheet(
                          context,
                          draft: draft.reminders[index],
                        );
                        if (edited != null) {
                          controller.updateReminder(index, edited);
                        }
                      },
                      onRemove: () => controller.removeReminder(index),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final added = await showReminderDraftSheet(context);
                      if (added != null) {
                        controller.addReminder(added);
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add a reminder'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: draft.isSaving
                    ? null
                    : () async {
                        await controller.finish();
                        if (!context.mounted) {
                          return;
                        }
                        // The root rebuilds to Today once a pet exists, but
                        // the onboarding routes are still stacked above it.
                        Navigator.of(context).popUntil(
                          (route) => route.isFirst,
                        );
                      },
                child: draft.isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        draft.keptReminderCount == 0
                            ? 'Finish without reminders'
                            : 'Finish',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The standing note that none of this is veterinary advice.
class _VetDisclaimer extends StatelessWidget {
  const _VetDisclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppConstants.vetDisclaimer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.draft,
    required this.onToggle,
    required this.onEdit,
    required this.onRemove,
  });

  final ReminderDraft draft;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = TimeOfDay(
      hour: draft.timeOfDayMinutes ~/ 60,
      minute: draft.timeOfDayMinutes % 60,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Switch(value: draft.enabled, onChanged: onToggle),
            const SizedBox(width: 8),
            Expanded(
              child: Opacity(
                opacity: draft.enabled ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.repeat.describe()} · from '
                      '${DateFormat.yMMMd().format(draft.firstDue)} at '
                      '${time.format(context)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}
