import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/weight_entry.dart';

/// Records a weighing.
Future<void> showWeightEntrySheet(
  BuildContext context, {
  required String petId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _WeightEntrySheet(petId: petId),
);

class _WeightEntrySheet extends ConsumerStatefulWidget {
  const _WeightEntrySheet({required this.petId});

  final String petId;

  @override
  ConsumerState<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends ConsumerState<_WeightEntrySheet> {
  final _value = TextEditingController();
  final _note = TextEditingController();
  late DateTime _measuredOn;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _measuredOn = DateTime.utc(today.year, today.month, today.day);
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _measuredOn.year,
        _measuredOn.month,
        _measuredOn.day,
      ),
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime.now(),
      helpText: 'Date weighed',
    );
    if (picked != null) {
      setState(
        () => _measuredOn = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _save(WeightUnit unit) async {
    final value = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a weight');
      return;
    }
    await ref
        .read(weightRepositoryProvider)
        .create(
          petId: widget.petId,
          measuredOn: _measuredOn,
          // Converted on the way in, so the stored grams never depend on
          // which unit happened to be selected at the time.
          grams: unit.toGrams(value),
          note: _note.text,
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit =
        ref.watch(weightUnitProvider).value ?? WeightUnit.kilograms;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a weighing', style: theme.textTheme.titleLarge),
          const SizedBox(height: 24),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Weight',
              suffixText: unit.label,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(DateFormat.yMMMd().format(_measuredOn)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Optional',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _save(unit),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
