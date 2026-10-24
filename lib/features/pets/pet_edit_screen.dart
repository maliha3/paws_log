import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../data/providers.dart';
import '../../domain/models/pet.dart';
import '../../services/photo_store.dart';

/// Adds another pet, or edits one that exists.
///
/// Separate from onboarding's add-cat screen on purpose: that one fills in a
/// draft that is saved all at once at the end of the flow, this one writes
/// straight to the database. Same fields, different destination.
class PetEditScreen extends ConsumerStatefulWidget {
  const PetEditScreen({this.pet, super.key});

  final Pet? pet;

  @override
  ConsumerState<PetEditScreen> createState() => _PetEditScreenState();
}

class _PetEditScreenState extends ConsumerState<PetEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  late final TextEditingController _originNotes;
  late final TextEditingController _motherInfo;
  late final TextEditingController _fatherInfo;
  late final TextEditingController _foodBrand;
  late final TextEditingController _feedingNotes;
  late PetSex _sex;
  late bool? _neutered;
  CoatLength? _coatLength;
  PetOrigin? _origin;
  DateTime? _originDate;
  DietType? _dietType;
  DateTime? _birthday;
  String? _photoPath;
  bool _showNameError = false;

  bool get _isEditing => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final pet = widget.pet;
    _name = TextEditingController(text: pet?.name ?? '');
    _breed = TextEditingController(text: pet?.breed ?? '');
    _originNotes = TextEditingController(text: pet?.originNotes ?? '');
    _motherInfo = TextEditingController(text: pet?.motherInfo ?? '');
    _fatherInfo = TextEditingController(text: pet?.fatherInfo ?? '');
    _foodBrand = TextEditingController(text: pet?.foodBrand ?? '');
    _feedingNotes = TextEditingController(text: pet?.feedingNotes ?? '');
    _sex = pet?.sex ?? PetSex.unknown;
    _neutered = pet?.neutered;
    _coatLength = pet?.coatLength;
    _origin = pet?.origin;
    _originDate = pet?.originDate;
    _dietType = pet?.dietType;
    _birthday = pet?.birthday;
    _photoPath = pet?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _originNotes.dispose();
    _motherInfo.dispose();
    _fatherInfo.dispose();
    _foodBrand.dispose();
    _feedingNotes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final path = await ref.read(photoStoreProvider).pick(ImageSource.gallery);
    if (path != null && mounted) {
      setState(() => _photoPath = path);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final existing = _birthday;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing == null
          ? DateTime(now.year - 1, now.month, now.day)
          : DateTime(existing.year, existing.month, existing.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(
        () => _birthday = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  Future<void> _pickOriginDate() async {
    final now = DateTime.now();
    final existing = _originDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing == null
          ? now
          : DateTime(existing.year, existing.month, existing.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      helpText: 'When did they arrive?',
    );
    if (picked != null) {
      setState(
        () => _originDate = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  static String? _blank(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    final repository = ref.read(petRepositoryProvider);
    final pet = widget.pet;

    if (pet == null) {
      await repository.create(
        name: _name.text,
        breed: _breed.text,
        sex: _sex,
        neutered: _neutered,
        birthday: _birthday,
        photoPath: _photoPath,
        coatLength: _coatLength,
        origin: _origin,
        originDate: _originDate,
        originNotes: _originNotes.text,
        motherInfo: _motherInfo.text,
        fatherInfo: _fatherInfo.text,
        dietType: _dietType,
        foodBrand: _foodBrand.text,
        feedingNotes: _feedingNotes.text,
      );
    } else {
      // Built rather than copied: `copyWith` reads a null as "leave it
      // alone", so a field the owner has just emptied would survive the save.
      await repository.update(
        Pet(
          id: pet.id,
          name: _name.text.trim(),
          photoPath: _photoPath,
          birthday: _birthday,
          breed: _blank(_breed),
          sex: _sex,
          neutered: _neutered,
          coatLength: _coatLength,
          origin: _origin,
          originDate: _originDate,
          originNotes: _blank(_originNotes),
          motherInfo: _blank(_motherInfo),
          fatherInfo: _blank(_fatherInfo),
          dietType: _dietType,
          foodBrand: _blank(_foodBrand),
          feedingNotes: _blank(_feedingNotes),
          createdAt: pet.createdAt,
          updatedAt: pet.updatedAt,
          archivedAt: pet.archivedAt,
        ),
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
      appBar: AppBar(title: Text(_isEditing ? 'Edit pet' : 'Add a pet')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  PetAvatar(
                    name: _name.text,
                    photoPath: _photoPath,
                    radius: 52,
                  ),
                  Tooltip(
                    message: 'Change photo',
                    child: IconButton.filled(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.edit, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _showNameError ? 'A name is needed' : null,
              ),
              onChanged: (value) => setState(() {
                if (_showNameError && value.trim().isNotEmpty) {
                  _showNameError = false;
                }
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _breed,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Breed',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 20),
            Text('Date of birth', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickBirthday,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _birthday == null
                          ? 'Not sure'
                          : DateFormat.yMMMd().format(_birthday!),
                    ),
                  ),
                  if (_birthday != null)
                    IconButton(
                      onPressed: () => setState(() => _birthday = null),
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear',
                    )
                  else
                    const Icon(Icons.calendar_today_outlined, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Sex', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<PetSex>(
              segments: const [
                ButtonSegment(value: PetSex.female, label: Text('Female')),
                ButtonSegment(value: PetSex.male, label: Text('Male')),
                ButtonSegment(value: PetSex.unknown, label: Text('Not sure')),
              ],
              selected: {_sex},
              onSelectionChanged: (selected) =>
                  setState(() => _sex = selected.first),
            ),
            const SizedBox(height: 20),
            Text('Neutered or spayed', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Yes')),
                ButtonSegment(value: 0, label: Text('No')),
                ButtonSegment(value: -1, label: Text('Not sure')),
              ],
              selected: {
                switch (_neutered) {
                  true => 1,
                  false => 0,
                  null => -1,
                },
              },
              onSelectionChanged: (selected) => setState(
                () => _neutered = switch (selected.first) {
                  1 => true,
                  0 => false,
                  _ => null,
                },
              ),
            ),
            const SizedBox(height: 20),
            Text('Coat', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Grooming suggestions use this.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Short')),
                ButtonSegment(value: 1, label: Text('Long')),
                ButtonSegment(value: -1, label: Text('Not sure')),
              ],
              selected: {
                switch (_coatLength) {
                  CoatLength.short => 0,
                  CoatLength.long => 1,
                  null => -1,
                },
              },
              onSelectionChanged: (selected) => setState(
                () => _coatLength = switch (selected.first) {
                  0 => CoatLength.short,
                  1 => CoatLength.long,
                  _ => null,
                },
              ),
            ),
            const SizedBox(height: 24),
            // Collapsed by default: these are the fields an owner fills in
            // once, if ever, and expanding the form for everyone would bury
            // the ones they actually came for.
            _Section(
              title: 'Where they came from',
              icon: Icons.home_outlined,
              children: [
                _ChipPicker<PetOrigin>(
                  label: 'How they arrived',
                  values: PetOrigin.values,
                  selected: _origin,
                  labelOf: (origin) => origin.label,
                  onChanged: (origin) => setState(() => _origin = origin),
                ),
                const SizedBox(height: 16),
                _ValueRow(
                  label: 'Arrived or born',
                  value: _originDate == null
                      ? 'Not recorded'
                      : DateFormat.yMMMd().format(_originDate!),
                  onTap: _pickOriginDate,
                  onClear: _originDate == null
                      ? null
                      : () => setState(() => _originDate = null),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _originNotes,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Where from, who from, anything worth keeping',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _motherInfo,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Mother'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _fatherInfo,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Father'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Food',
              icon: Icons.restaurant_outlined,
              children: [
                _ChipPicker<DietType>(
                  label: 'What they eat',
                  values: DietType.values,
                  selected: _dietType,
                  labelOf: (diet) => diet.label,
                  onChanged: (diet) => setState(() => _dietType = diet),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _foodBrand,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Brand'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _feedingNotes,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Feeding notes',
                    hintText: 'How much, how often, what to avoid',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save' : 'Add pet'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsed group of optional fields.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: children,
    ),
  );
}

/// One optional choice out of an enum, with a way back to "not recorded".
class _ChipPicker<T> extends StatelessWidget {
  const _ChipPicker({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      // Wrapped, not a row: five labels at the largest text sizes do not fit
      // across a phone.
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(labelOf(value)),
              selected: selected == value,
              // Tapping the chosen one again clears it, which is the only way
              // back to "not recorded" once something has been picked.
              onSelected: (isSelected) =>
                  onChanged(isSelected ? value : null),
            ),
        ],
      ),
    ],
  );
}

/// A tappable value, with a way to empty it.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
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
