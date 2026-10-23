import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/medicine.dart';

/// Adds or edits a course of medication.
class MedicineEditScreen extends ConsumerStatefulWidget {
  const MedicineEditScreen({required this.petId, this.medicine, super.key});

  final String petId;
  final Medicine? medicine;

  @override
  ConsumerState<MedicineEditScreen> createState() => _MedicineEditScreenState();
}

class _MedicineEditScreenState extends ConsumerState<MedicineEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late List<int> _times;
  late DateTime _startDate;
  DateTime? _endDate;
  int _intervalDays = 1;
  bool _showNameError = false;
  bool _saving = false;

  bool get _isEditing => widget.medicine != null;

  @override
  void initState() {
    super.initState();
    final medicine = widget.medicine;
    final today = DateTime.now();

    _name = TextEditingController(text: medicine?.name ?? '');
    _dosage = TextEditingController(text: medicine?.dosage ?? '');
    _times = [...?medicine?.schedule.timesOfDayMinutes];
    if (_times.isEmpty) {
      _times = [8 * 60, 20 * 60];
    }
    _startDate =
        medicine?.schedule.startDate ??
        DateTime.utc(today.year, today.month, today.day);
    _endDate = medicine?.schedule.endDate;
    _intervalDays = medicine?.schedule.intervalDays ?? 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    super.dispose();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Dose time',
    );
    if (picked != null) {
      final minutes = picked.hour * 60 + picked.minute;
      setState(() {
        if (!_times.contains(minutes)) {
          _times = [..._times, minutes]..sort();
        }
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final anchor = isStart ? _startDate : (_endDate ?? _startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(anchor.year, anchor.month, anchor.day),
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: isStart ? 'First day' : 'Last day',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      final date = DateTime.utc(picked.year, picked.month, picked.day);
      if (isStart) {
        _startDate = date;
      } else {
        _endDate = date;
      }
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    if (_times.isEmpty) {
      return;
    }
    setState(() => _saving = true);

    final schedule = DoseSchedule(
      timesOfDayMinutes: _times,
      startDate: _startDate,
      intervalDays: _intervalDays,
      endDate: _endDate,
    );
    final repository = ref.read(medicineRepositoryProvider);

    if (_isEditing) {
      await repository.update(
        widget.medicine!.copyWith(
          name: _name.text.trim(),
          dosage: _dosage.text.trim(),
          schedule: schedule,
        ),
      );
    } else {
      await repository.create(
        petId: widget.petId,
        name: _name.text,
        dosage: _dosage.text,
        schedule: schedule,
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit medicine' : 'Add a medicine'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Medicine',
                errorText: _showNameError ? 'A name is needed' : null,
              ),
              onChanged: (value) {
                if (_showNameError && value.trim().isNotEmpty) {
                  setState(() => _showNameError = false);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dosage,
              decoration: const InputDecoration(
                labelText: 'Dose',
                hintText: 'e.g. 1 tablet',
                helperText: 'Copy what the label says',
              ),
            ),
            const SizedBox(height: 24),
            Text('Times of day', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in _times)
                  InputChip(
                    label: Text(
                      TimeOfDay(
                        hour: minutes ~/ 60,
                        minute: minutes % 60,
                      ).format(context),
                    ),
                    onDeleted: _times.length == 1
                        ? null
                        : () => setState(
                            () => _times = [..._times]..remove(minutes),
                          ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  onPressed: _addTime,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Every', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('day')),
                ButtonSegment(value: 2, label: Text('2 days')),
                ButtonSegment(value: 3, label: Text('3 days')),
              ],
              selected: {_intervalDays},
              onSelectionChanged: (selected) =>
                  setState(() => _intervalDays = selected.first),
            ),
            const SizedBox(height: 24),
            _DateRow(
              label: 'First day',
              value: DateFormat.yMMMd().format(_startDate),
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 12),
            _DateRow(
              label: 'Last day',
              value: _endDate == null
                  ? 'Ongoing'
                  : DateFormat.yMMMd().format(_endDate!),
              onTap: () => _pickDate(isStart: false),
              onClear: _endDate == null
                  ? null
                  : () => setState(() => _endDate = null),
            ),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? 'Save' : 'Add medicine'),
            ),
          ],
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(52),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value)),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear',
              )
            else
              const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    ],
  );
}
