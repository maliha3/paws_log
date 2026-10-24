import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/vaccination_record.dart';

/// Records a vaccine, or corrects one already recorded.
///
/// Most rows arrive on their own, written when a vaccine reminder is marked
/// done. This is for the rest: a shot given at a clinic the app knew nothing
/// about, one from before the owner started using it, and the date that was
/// wrong.
class VaccinationEditScreen extends ConsumerStatefulWidget {
  const VaccinationEditScreen({required this.petId, this.record, super.key});

  final String petId;
  final VaccinationRecord? record;

  @override
  ConsumerState<VaccinationEditScreen> createState() =>
      _VaccinationEditScreenState();
}

class _VaccinationEditScreenState
    extends ConsumerState<VaccinationEditScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.record?.name ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.record?.notes ?? '',
  );
  late DateTime _givenOn = widget.record?.administeredOn ?? _today();
  late DateTime? _nextDueOn = widget.record?.nextDueOn;
  bool _showNameError = false;
  bool _saving = false;

  bool get _isEditing => widget.record != null;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isGiven}) async {
    final now = DateTime.now();
    final existing = isGiven ? _givenOn : _nextDueOn;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing == null
          ? now
          : DateTime(existing.year, existing.month, existing.day),
      firstDate: DateTime(now.year - 30),
      // A booster is due in the future; a shot was given in the past.
      lastDate: isGiven ? now : DateTime(now.year + 30),
      helpText: isGiven ? 'When was it given?' : 'When is the next one due?',
    );
    if (picked == null) {
      return;
    }
    final date = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (isGiven) {
        _givenOn = date;
      } else {
        _nextDueOn = date;
      }
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final records = ref.read(vaccinationRepositoryProvider);
    final existing = widget.record;
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    if (existing == null) {
      await records.create(
        petId: widget.petId,
        name: _name.text,
        administeredOn: _givenOn,
        nextDueOn: _nextDueOn,
        notes: notes,
      );
    } else {
      // Built rather than copied: a note or a next-due date the owner has
      // just emptied has to survive the save as empty.
      await records.update(
        VaccinationRecord(
          id: existing.id,
          petId: existing.petId,
          name: _name.text.trim(),
          administeredOn: _givenOn,
          nextDueOn: _nextDueOn,
          sourceEventId: existing.sourceEventId,
          notes: notes,
          createdAt: existing.createdAt,
        ),
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit vaccination' : 'Record a vaccination'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            if (widget.record?.wasAutoFilled ?? false) ...[
              Text(
                'Recorded when you marked a reminder done. Correcting it here '
                'changes the record, not the reminder.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Vaccine',
                hintText: 'What your vet called it',
                errorText: _showNameError ? 'A name is needed' : null,
              ),
              onChanged: (_) {
                if (_showNameError) {
                  setState(() => _showNameError = false);
                }
              },
            ),
            const SizedBox(height: 20),
            _DateRow(
              label: 'Given',
              value: DateFormat.yMMMd().format(_givenOn),
              onTap: () => _pickDate(isGiven: true),
            ),
            const SizedBox(height: 16),
            _DateRow(
              label: 'Next due',
              value: _nextDueOn == null
                  ? 'Not recorded'
                  : DateFormat.yMMMd().format(_nextDueOn!),
              onTap: () => _pickDate(isGiven: false),
              onClear: _nextDueOn == null
                  ? null
                  : () => setState(() => _nextDueOn = null),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notes,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Batch number, which clinic, anything worth keeping',
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? 'Save' : 'Record it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable date, with a way to empty it.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Row(
      children: [
        Expanded(child: Text(value)),
        if (onClear != null)
          IconButton(
            tooltip: 'Clear $label',
            icon: const Icon(Icons.clear, size: 18),
            onPressed: onClear,
          ),
        TextButton(onPressed: onTap, child: const Text('Change')),
      ],
    ),
  );
}
