import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../domain/models/pet.dart';
import '../../services/photo_store.dart';
import 'onboarding_controller.dart';
import 'starter_reminders_screen.dart';

/// Second screen of onboarding: the owner's first cat.
///
/// Only the name is required — a new owner may not know the birthday or
/// whether the cat is neutered yet, and "not sure" is a real answer.
class AddPetScreen extends ConsumerStatefulWidget {
  const AddPetScreen({super.key});

  @override
  ConsumerState<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends ConsumerState<AddPetScreen> {
  late final TextEditingController _name;
  late final TextEditingController _breed;
  bool _showNameError = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingControllerProvider);
    _name = TextEditingController(text: draft.name);
    _breed = TextEditingController(text: draft.breed);
  }

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(context).pop(_PhotoAction.gallery),
            ),
            if (ref.read(onboardingControllerProvider).photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(context).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    if (action == _PhotoAction.remove) {
      ref.read(onboardingControllerProvider.notifier).setPhoto(null);
      return;
    }
    final path = await ref.read(photoStoreProvider).pick(
      action == _PhotoAction.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (path != null) {
      ref.read(onboardingControllerProvider.notifier).setPhoto(path);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final existing = ref.read(onboardingControllerProvider).birthday;
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
      // Date-only values are held at UTC midnight.
      ref
          .read(onboardingControllerProvider.notifier)
          .setBirthday(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  void _continue() {
    final controller = ref.read(onboardingControllerProvider.notifier);
    controller.setName(_name.text);
    controller.setBreed(_breed.text);

    if (!ref.read(onboardingControllerProvider).canContinue) {
      setState(() => _showNameError = true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const StarterRemindersScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Add your cat')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  PetAvatar(
                    name: draft.name,
                    photoPath: draft.photoPath,
                    radius: 52,
                  ),
                  IconButton.filled(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Add a photo',
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
              onChanged: (value) {
                controller.setName(value);
                if (_showNameError && value.trim().isNotEmpty) {
                  setState(() => _showNameError = false);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _breed,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Breed',
                hintText: 'Optional',
              ),
              onChanged: controller.setBreed,
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Date of birth',
              child: OutlinedButton(
                onPressed: _pickBirthday,
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        draft.birthday == null
                            ? 'Not sure'
                            : DateFormat.yMMMd().format(draft.birthday!),
                      ),
                    ),
                    if (draft.birthday != null)
                      IconButton(
                        onPressed: () => controller.setBirthday(null),
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear',
                      )
                    else
                      const Icon(Icons.calendar_today_outlined, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Sex',
              child: SegmentedButton<PetSex>(
                segments: const [
                  ButtonSegment(value: PetSex.female, label: Text('Female')),
                  ButtonSegment(value: PetSex.male, label: Text('Male')),
                  ButtonSegment(value: PetSex.unknown, label: Text('Not sure')),
                ],
                selected: {draft.sex},
                onSelectionChanged: (selected) =>
                    controller.setSex(selected.first),
              ),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Neutered or spayed',
              child: SegmentedButton<_Neutered>(
                segments: const [
                  ButtonSegment(value: _Neutered.yes, label: Text('Yes')),
                  ButtonSegment(value: _Neutered.no, label: Text('No')),
                  ButtonSegment(
                    value: _Neutered.unknown,
                    label: Text('Not sure'),
                  ),
                ],
                selected: {_Neutered.from(draft.neutered)},
                onSelectionChanged: (selected) =>
                    controller.setNeutered(selected.first.value),
              ),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Coat',
              child: SegmentedButton<_Coat>(
                segments: const [
                  ButtonSegment(value: _Coat.short, label: Text('Short')),
                  ButtonSegment(value: _Coat.long, label: Text('Long')),
                  ButtonSegment(
                    value: _Coat.unknown,
                    label: Text('Not sure'),
                  ),
                ],
                selected: {_Coat.from(draft.coatLength)},
                onSelectionChanged: (selected) =>
                    controller.setCoatLength(selected.first.value),
              ),
            ),
            const SizedBox(height: 36),
            FilledButton(onPressed: _continue, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}

/// Coat length as three buttons, because "not sure" is a real answer and the
/// grooming suggestion has to cope with it.
enum _Coat {
  short(CoatLength.short),
  long(CoatLength.long),
  unknown(null);

  const _Coat(this.value);

  final CoatLength? value;

  static _Coat from(CoatLength? value) => switch (value) {
    CoatLength.short => _Coat.short,
    CoatLength.long => _Coat.long,
    null => _Coat.unknown,
  };
}

/// A labelled row in the form.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: child),
    ],
  );
}

enum _PhotoAction { camera, gallery, remove }

/// Three-way answer for a nullable bool, so "not sure" is selectable rather
/// than merely the absence of an answer.
enum _Neutered {
  yes(true),
  no(false),
  unknown(null);

  const _Neutered(this.value);

  final bool? value;

  static _Neutered from(bool? value) => switch (value) {
    true => _Neutered.yes,
    false => _Neutered.no,
    null => _Neutered.unknown,
  };
}
