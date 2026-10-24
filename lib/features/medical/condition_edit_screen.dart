import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/providers.dart';
import '../../domain/models/pet_condition.dart';

/// Records what a vet has diagnosed.
///
/// The suggestions are a pick-list of things owners are commonly *told*, not
/// the app offering an opinion — which is why the screen asks "What has your
/// vet diagnosed?" and carries the same disclaimer as every other screen that
/// proposes anything.
class ConditionEditScreen extends ConsumerStatefulWidget {
  const ConditionEditScreen({required this.petId, this.condition, super.key});

  final String petId;
  final PetCondition? condition;

  /// Common diagnoses, for typing less. Free text is always available, and
  /// nothing here is suggested as likely.
  static const List<String> suggestions = [
    'CKD',
    'FIP',
    'Upper respiratory infection (cat flu)',
    'FIV',
    'FeLV',
    'Diabetes',
    'Hyperthyroidism',
  ];

  @override
  ConsumerState<ConditionEditScreen> createState() =>
      _ConditionEditScreenState();
}

class _ConditionEditScreenState extends ConsumerState<ConditionEditScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.condition?.name ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.condition?.notes ?? '',
  );
  late ConditionStatus _status =
      widget.condition?.status ?? ConditionStatus.ongoing;
  late DateTime? _date = widget.condition?.date;
  bool _showNameError = false;
  bool _saving = false;

  bool get _isEditing => widget.condition != null;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final existing = _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing == null
          ? now
          : DateTime(existing.year, existing.month, existing.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'When was it diagnosed?',
    );
    if (picked != null) {
      setState(
        () => _date = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final health = ref.read(petHealthRepositoryProvider);
    final existing = widget.condition;

    if (existing == null) {
      await health.addCondition(
        petId: widget.petId,
        name: _name.text,
        status: _status,
        date: _date,
        notes: _notes.text,
      );
    } else {
      // Built rather than copied: copyWith cannot clear a date or a note the
      // owner has emptied.
      await health.updateCondition(
        PetCondition(
          id: existing.id,
          petId: existing.petId,
          name: _name.text.trim(),
          status: _status,
          date: _date,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
        title: Text(_isEditing ? 'Edit condition' : 'Add a condition'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              'What has your vet diagnosed?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Paws Log records what you were told. It never works out a '
              'diagnosis of its own.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Condition',
                errorText: _showNameError ? 'A name is needed' : null,
              ),
              onChanged: (_) {
                if (_showNameError) {
                  setState(() => _showNameError = false);
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in ConditionEditScreen.suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => setState(() {
                      _name.text = suggestion;
                      _showNameError = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Where it stands', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // A row of two would run off the side at the largest text sizes.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in ConditionStatus.values)
                  ChoiceChip(
                    label: Text(status.label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _DateRow(
              label: 'Diagnosed',
              value: _date == null
                  ? 'Not recorded'
                  : DateFormat.yMMMd().format(_date!),
              onTap: _pickDate,
              onClear: _date == null ? null : () => setState(() => _date = null),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notes,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'What the vet said, and anything to watch for',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.vetDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? 'Save' : 'Add condition'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Records something the pet reacts to.
class AllergyEditScreen extends ConsumerStatefulWidget {
  const AllergyEditScreen({required this.petId, this.allergy, super.key});

  final String petId;
  final PetAllergy? allergy;

  @override
  ConsumerState<AllergyEditScreen> createState() => _AllergyEditScreenState();
}

class _AllergyEditScreenState extends ConsumerState<AllergyEditScreen> {
  late final TextEditingController _allergen = TextEditingController(
    text: widget.allergy?.allergen ?? '',
  );
  late final TextEditingController _reaction = TextEditingController(
    text: widget.allergy?.reaction ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.allergy?.notes ?? '',
  );
  bool _showNameError = false;
  bool _saving = false;

  bool get _isEditing => widget.allergy != null;

  @override
  void dispose() {
    _allergen.dispose();
    _reaction.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_allergen.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final health = ref.read(petHealthRepositoryProvider);
    final existing = widget.allergy;

    if (existing == null) {
      await health.addAllergy(
        petId: widget.petId,
        allergen: _allergen.text,
        reaction: _reaction.text,
        notes: _notes.text,
      );
    } else {
      await health.updateAllergy(
        PetAllergy(
          id: existing.id,
          petId: existing.petId,
          allergen: _allergen.text.trim(),
          reaction: _blankToNull(_reaction.text),
          notes: _blankToNull(_notes.text),
          createdAt: existing.createdAt,
        ),
      );
    }
    navigator.pop();
  }

  static String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isEditing ? 'Edit allergy' : 'Add an allergy'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          TextField(
            controller: _allergen,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Reacts to',
              hintText: 'Chicken, a flea treatment, a drug',
              errorText: _showNameError ? 'A name is needed' : null,
            ),
            onChanged: (_) {
              if (_showNameError) {
                setState(() => _showNameError = false);
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reaction,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What happens',
              hintText: 'Itching round the ears',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEditing ? 'Save' : 'Add allergy'),
          ),
        ],
      ),
    ),
  );
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
