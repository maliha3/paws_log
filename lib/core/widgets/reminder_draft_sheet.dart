import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../../data/providers.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_draft.dart';
import '../../domain/repeat_rule.dart';
import '../../domain/shedding_season.dart';

/// Edits one reminder draft. Returns the edited draft, or null if dismissed.
///
/// In `core/` rather than beside either caller: onboarding fills in drafts it
/// saves all at once, the reminders screen edits reminders that already
/// exist, and both want the same fields. Shared code goes down a layer rather
/// than sideways between features.
Future<ReminderDraft?> showReminderDraftSheet(
  BuildContext context, {
  ReminderDraft? draft,
}) => showModalBottomSheet<ReminderDraft>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _ReminderDraftSheet(draft: draft),
);

class _ReminderDraftSheet extends ConsumerStatefulWidget {
  const _ReminderDraftSheet({this.draft});

  final ReminderDraft? draft;

  @override
  ConsumerState<_ReminderDraftSheet> createState() =>
      _ReminderDraftSheetState();
}

class _ReminderDraftSheetState extends ConsumerState<_ReminderDraftSheet> {
  late final TextEditingController _title;
  late final TextEditingController _interval;
  late ReminderCategory _category;
  late RepeatUnit _unit;
  late DateTime _firstDue;
  late int _timeOfDayMinutes;
  late bool _seasonal;
  bool _showTitleError = false;

  /// Shedding only means anything for a short interval. On a monthly or
  /// yearly rule there is nothing to halve, so the switch is not offered.
  bool get _canBeSeasonal =>
      _unit == RepeatUnit.days || _unit == RepeatUnit.weeks;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    final today = DateTime.now();

    _title = TextEditingController(text: draft?.title ?? '');
    _interval = TextEditingController(
      text: (draft?.repeat.interval ?? 1).toString(),
    );
    _category = draft?.category ?? ReminderCategory.other;
    _unit = draft?.repeat.unit ?? RepeatUnit.months;
    _firstDue =
        draft?.firstDue ?? DateTime.utc(today.year, today.month, today.day);
    _timeOfDayMinutes =
        draft?.timeOfDayMinutes ?? AppConstants.defaultReminderTimeMinutes;
    _seasonal = draft?.repeat.seasonal ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _pickFirstDue() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_firstDue.year, _firstDue.month, _firstDue.day),
      // A past date is allowed: it means the care is already overdue.
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 10),
      helpText: 'First due',
    );
    if (picked != null) {
      setState(
        () => _firstDue = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _timeOfDayMinutes ~/ 60,
        minute: _timeOfDayMinutes % 60,
      ),
    );
    if (picked != null) {
      setState(() => _timeOfDayMinutes = picked.hour * 60 + picked.minute);
    }
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _showTitleError = true);
      return;
    }
    final interval = int.tryParse(_interval.text) ?? 1;
    Navigator.of(context).pop(
      ReminderDraft(
        title: _title.text.trim(),
        category: _category,
        repeat: RepeatRule(
          unit: _unit,
          interval: interval < 1 ? 1 : interval,
          // Never stored on a rule it cannot apply to: a monthly reminder
          // carrying a dormant flag would read as a promise it does not keep.
          seasonal: _seasonal && _canBeSeasonal,
        ),
        firstDue: _firstDue,
        timeOfDayMinutes: _timeOfDayMinutes,
        enabled: widget.draft?.enabled ?? true,
        notes: widget.draft?.notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = TimeOfDay(
      hour: _timeOfDayMinutes ~/ 60,
      minute: _timeOfDayMinutes % 60,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.draft == null ? 'Add a reminder' : 'Edit reminder',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'What is it',
                errorText: _showTitleError ? 'A title is needed' : null,
              ),
              onChanged: (value) {
                if (_showTitleError && value.trim().isNotEmpty) {
                  setState(() => _showTitleError = false);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ReminderCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kind of care'),
              items: [
                for (final category in ReminderCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _interval,
                    keyboardType: TextInputType.number,
                    enabled: _unit != RepeatUnit.none,
                    decoration: const InputDecoration(labelText: 'Every'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<RepeatUnit>(
                    initialValue: _unit,
                    // Without this the longest item overflows the field.
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Repeat'),
                    items: const [
                      DropdownMenuItem(
                        value: RepeatUnit.days,
                        child: Text('days'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.weeks,
                        child: Text('weeks'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.months,
                        child: Text('months'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.years,
                        child: Text('years'),
                      ),
                      DropdownMenuItem(
                        value: RepeatUnit.none,
                        child: Text('never — one off'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _unit = value ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFirstDue,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(DateFormat.yMMMd().format(_firstDue)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(time.format(context)),
                  ),
                ),
              ],
            ),
            if (_canBeSeasonal) ...[
              const SizedBox(height: 8),
              _SheddingSwitch(
                value: _seasonal,
                onChanged: (value) => setState(() => _seasonal = value),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns the shedding-season halving on, and says what that means.
class _SheddingSwitch extends ConsumerWidget {
  const _SheddingSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stored = ref.watch(hemisphereProvider);
    final hemisphere = stored.hasValue
        ? stored.requireValue
        : Hemisphere.northern;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          title: const Text('Shedding season'),
          subtitle: const Text(
            'Comes round twice as often from March to May and September to '
            'November, when cats shed most.',
          ),
          isThreeLine: true,
        ),
        if (value) ...[
          const SizedBox(height: 4),
          Text(
            'Where you are',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            // Worth saying plainly, because the obvious expectation is that
            // the southern setting moves the months.
            'Cats shed in the same two months either way \u2014 it turns with '
            'the equinox. This only changes what each spell is called.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in Hemisphere.values)
                ChoiceChip(
                  label: Text('${option.label} hemisphere'),
                  selected: hemisphere == option,
                  onSelected: (_) => ref
                      .read(settingsRepositoryProvider)
                      .setHemisphere(option),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Right now: '
            '${sheddingWindowLabel(DateTime.now(), hemisphere) ?? 'not shedding'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
