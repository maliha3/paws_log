import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants.dart';
import '../../../domain/models/reminder.dart';
import '../../../domain/models/reminder_draft.dart';
import '../../../domain/repeat_rule.dart';

/// Edits one reminder draft. Returns the edited draft, or null if dismissed.
///
/// Used for both the pre-filled suggestions and reminders the owner adds, so
/// the same fields are editable either way.
Future<ReminderDraft?> showReminderDraftSheet(
  BuildContext context, {
  ReminderDraft? draft,
}) => showModalBottomSheet<ReminderDraft>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _ReminderDraftSheet(draft: draft),
);

class _ReminderDraftSheet extends StatefulWidget {
  const _ReminderDraftSheet({this.draft});

  final ReminderDraft? draft;

  @override
  State<_ReminderDraftSheet> createState() => _ReminderDraftSheetState();
}

class _ReminderDraftSheetState extends State<_ReminderDraftSheet> {
  late final TextEditingController _title;
  late final TextEditingController _interval;
  late ReminderCategory _category;
  late RepeatUnit _unit;
  late DateTime _firstDue;
  late int _timeOfDayMinutes;
  bool _showTitleError = false;

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
