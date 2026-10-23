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
  late PetSex _sex;
  late bool? _neutered;
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
    _sex = pet?.sex ?? PetSex.unknown;
    _neutered = pet?.neutered;
    _birthday = pet?.birthday;
    _photoPath = pet?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
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
      );
    } else {
      await repository.update(
        Pet(
          id: pet.id,
          name: _name.text.trim(),
          photoPath: _photoPath,
          birthday: _birthday,
          breed: _breed.text.trim().isEmpty ? null : _breed.text.trim(),
          sex: _sex,
          neutered: _neutered,
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
