import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/category_palette.dart';
import '../../data/providers.dart';
import '../../domain/dose_schedule.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/prescription.dart';
import '../../domain/prescriptions/dose_times.dart';
import '../../domain/prescriptions/prescription_parser.dart';

/// Checking what was read off a prescription, before any of it counts.
///
/// The pages sit above the fields, so the owner is reading the prescription
/// while they check it. Nothing here has changed the schedule yet: the pages
/// are already saved, and only Confirm creates medicines and their doses.
class PrescriptionReviewScreen extends ConsumerStatefulWidget {
  const PrescriptionReviewScreen({
    required this.prescription,
    required this.parsed,
    super.key,
  });

  final Prescription prescription;
  final ParsedPrescription parsed;

  @override
  ConsumerState<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState
    extends ConsumerState<PrescriptionReviewScreen> {
  late DateTime _date = widget.prescription.date;
  final TextEditingController _vetName = TextEditingController();
  final TextEditingController _clinic = TextEditingController();
  late final List<_Draft> _drafts = [
    for (final medicine in widget.parsed.medicines) _Draft.from(medicine),
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _vetName.text = widget.prescription.vetName ?? '';
    _clinic.text = widget.prescription.clinic ?? '';
  }

  @override
  void dispose() {
    _vetName.dispose();
    _clinic.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Check the prescription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _PageStrip(paths: widget.prescription.imagePaths),
          const SizedBox(height: 16),
          const _CheckEveryDose(),
          const SizedBox(height: 20),
          Text('The prescription', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Date'),
                  subtitle: Text(DateFormat.yMMMd().format(_date)),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Change'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _vetName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Vet'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clinic,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Clinic'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Medicines', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_drafts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.prescription.wasRead
                    ? 'Nothing on the page looked like a course of medicine. '
                          'Add one by hand if there is one.'
                    : 'No text could be read off the pages. The pages are '
                          'saved either way; add a medicine by hand if there '
                          'is one.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final (index, draft) in _drafts.indexed)
            _DraftCard(
              draft: draft,
              number: index + 1,
              onChanged: () => setState(() {}),
              onRemove: () => setState(() {
                _drafts.removeAt(index).dispose();
              }),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => setState(() => _drafts.add(_Draft.blank())),
            icon: const Icon(Icons.add),
            label: const Text('Add another medicine'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // Stacked, not side by side: at the largest text sizes two buttons
          // in a row run off the screen.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _confirm,
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _saving ? null : _savePhotosOnly,
                  child: const Text('Save photos only'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  /// Keeps the pages and the vet details, and touches no schedule.
  Future<void> _savePhotosOnly() async {
    await _savePrescription();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _savePrescription() async {
    final existing = widget.prescription;
    await ref
        .read(prescriptionRepositoryProvider)
        .update(
          Prescription(
            id: existing.id,
            petId: existing.petId,
            vetVisitId: existing.vetVisitId,
            date: _date,
            vetName: _trimmed(_vetName.text),
            clinic: _trimmed(_clinic.text),
            imagePaths: existing.imagePaths,
            extractedText: existing.extractedText,
            notes: existing.notes,
            createdAt: existing.createdAt,
          ),
        );
  }

  /// Creates a medicine, and its doses, for every draft that is filled in.
  Future<void> _confirm() async {
    if (!_validate()) {
      return;
    }
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final today = localDateOnly(DateTime.now());
    final medicines = ref.read(medicineRepositoryProvider);

    await _savePrescription();

    var created = 0;
    for (final draft in _drafts) {
      if (draft.isBlank) {
        continue;
      }
      final days = int.tryParse(draft.days.text.trim());
      await medicines.create(
        petId: widget.prescription.petId,
        name: draft.name.text,
        dosage: draft.dose.text,
        prescriptionId: widget.prescription.id,
        schedule: DoseSchedule(
          timesOfDayMinutes: doseTimesFor(draft.timesPerDay!),
          startDate: today,
          // No length on the page means a course with no end, which is a
          // real answer — "continue long term" — and not a missing one.
          endDate: days == null ? null : today.add(Duration(days: days - 1)),
        ),
      );
      created++;
    }

    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          created == 0
              ? 'Pages saved. Nothing was added to the schedule.'
              : created == 1
              ? '1 medicine added, with its doses.'
              : '$created medicines added, with their doses.',
        ),
      ),
    );
  }

  /// Every started draft needs a name and a frequency. Neither is guessed:
  /// an invented dose time is exactly what this screen exists to prevent.
  bool _validate() {
    var valid = true;
    for (final draft in _drafts) {
      draft.error = null;
      if (draft.isBlank) {
        continue;
      }
      if (draft.name.text.trim().isEmpty) {
        draft.error = 'A name is needed';
        valid = false;
      } else if (draft.timesPerDay == null) {
        draft.error = 'How often is it given?';
        valid = false;
      }
    }
    setState(() {});
    return valid;
  }

  static String? _trimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// One medicine as the owner is editing it.
class _Draft {
  _Draft({
    required this.name,
    required this.dose,
    required this.days,
    this.timesPerDay,
    this.nameNeedsCheck = false,
    this.doseNeedsCheck = false,
    this.timesNeedsCheck = false,
    this.daysNeedsCheck = false,
    this.isAsNeeded = false,
  });

  factory _Draft.from(ParsedMedicine medicine) => _Draft(
    name: TextEditingController(text: medicine.name.value ?? ''),
    dose: TextEditingController(text: medicine.dose.value ?? ''),
    days: TextEditingController(
      text: medicine.durationDays.value?.toString() ?? '',
    ),
    timesPerDay: medicine.timesPerDay.value,
    nameNeedsCheck: medicine.name.needsCheck,
    doseNeedsCheck: medicine.dose.needsCheck,
    timesNeedsCheck: medicine.timesPerDay.needsCheck,
    daysNeedsCheck: medicine.durationDays.needsCheck,
    isAsNeeded: medicine.isAsNeeded,
  );

  factory _Draft.blank() => _Draft(
    name: TextEditingController(),
    dose: TextEditingController(),
    days: TextEditingController(),
  );

  final TextEditingController name;
  final TextEditingController dose;
  final TextEditingController days;
  int? timesPerDay;

  final bool nameNeedsCheck;
  final bool doseNeedsCheck;
  final bool timesNeedsCheck;
  final bool daysNeedsCheck;
  final bool isAsNeeded;

  String? error;

  /// An untouched card is ignored rather than complained about.
  bool get isBlank =>
      name.text.trim().isEmpty &&
      dose.text.trim().isEmpty &&
      days.text.trim().isEmpty &&
      timesPerDay == null;

  void dispose() {
    name.dispose();
    dose.dispose();
    days.dispose();
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.number,
    required this.onChanged,
    required this.onRemove,
  });

  final _Draft draft;
  final int number;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Medicine $number',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove this medicine',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            _Field(
              controller: draft.name,
              label: 'Medicine',
              needsCheck: draft.nameNeedsCheck,
              capitalise: true,
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: draft.dose,
              label: 'Dose',
              hint: '1 tablet, 0.5 ml',
              needsCheck: draft.doseNeedsCheck,
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: draft.timesPerDay,
              // Expanded, so "3 times a day" ellipsizes at the largest text
              // sizes instead of running off the side.
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'How often',
                helperText: draft.timesNeedsCheck ? _checkIt : null,
                helperStyle: draft.timesNeedsCheck
                    ? TextStyle(color: context.categories.fleaTick)
                    : null,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (var perDay = 1; perDay <= maxTimesPerDay; perDay++)
                  DropdownMenuItem(
                    value: perDay,
                    child: Text(_howOften(perDay)),
                  ),
              ],
              onChanged: (value) {
                draft.timesPerDay = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            _Field(
              controller: draft.days,
              label: 'For how many days',
              hint: 'Leave empty for an ongoing course',
              needsCheck: draft.daysNeedsCheck,
              numeric: true,
              onChanged: onChanged,
            ),
            if (draft.isAsNeeded) ...[
              const SizedBox(height: 12),
              Text(
                'The page says this one is given as needed, so there may be '
                'no schedule to keep.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _summary(context, draft),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (draft.error != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Exactly what Confirm will create, in words.
  static String _summary(BuildContext context, _Draft draft) {
    final perDay = draft.timesPerDay;
    if (perDay == null) {
      return 'Choose how often and the dose times appear here.';
    }
    final times = doseTimesFor(perDay)
        .map(
          (minutes) => TimeOfDay(
            hour: minutes ~/ 60,
            minute: minutes % 60,
          ).format(context),
        )
        .join(', ');
    final days = int.tryParse(draft.days.text.trim());
    return days == null
        ? '$times, from today, ongoing'
        : '$times, from today for $days days';
  }

  static String _howOften(int perDay) => switch (perDay) {
    1 => 'Once a day',
    2 => 'Twice a day',
    _ => '$perDay times a day',
  };
}

const String _checkIt = 'Check this against the page';

/// A text field that says when the parser was unsure of what is in it.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.needsCheck = false,
    this.numeric = false,
    this.capitalise = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool needsCheck;
  final bool numeric;
  final bool capitalise;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final warn = context.categories.fleaTick;

    return TextField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textCapitalization: capitalise
          ? TextCapitalization.words
          : TextCapitalization.none,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: needsCheck ? _checkIt : null,
        helperStyle: needsCheck ? TextStyle(color: warn) : null,
        helperMaxLines: 2,
        suffixIcon: needsCheck
            ? Icon(Icons.error_outline, color: warn, size: 20)
            : null,
      ),
    );
  }
}

/// The line every review screen carries.
class _CheckEveryDose extends StatelessWidget {
  const _CheckEveryDose();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = context.categories.fleaTick;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: warn),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Check every dose against the original prescription. Nothing '
              'here is saved to the schedule until you confirm it.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pages, swipeable, above the fields they were read from.
class _PageStrip extends StatefulWidget {
  const _PageStrip({required this.paths});

  final List<String> paths;

  @override
  State<_PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<_PageStrip> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.paths.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 240,
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHigh,
              child: PageView.builder(
                itemCount: widget.paths.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => Image.file(
                  File(widget.paths[index]),
                  fit: BoxFit.contain,
                  // A page whose file has gone is still a row worth showing;
                  // the fields below it are the point.
                  errorBuilder: (context, _, _) => Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.paths.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Page ${_page + 1} of ${widget.paths.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
