import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../data/providers.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/pet.dart';
import '../medicines/medicine_edit_screen.dart';

/// Everything recorded about one pet.
///
/// Grows through Phase 2: medicines first, then weights, visits and
/// vaccination history.
class PetDetailScreen extends ConsumerWidget {
  const PetDetailScreen({required this.petId, super.key});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);
    final pet = pets.hasValue
        ? pets.requireValue.where((pet) => pet.id == petId).firstOrNull
        : null;

    if (pet == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(pet.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(pet: pet),
          const SizedBox(height: 24),
          _MedicinesSection(petId: petId),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = [
      if (pet.breed != null) pet.breed!,
      if (pet.sex != PetSex.unknown)
        pet.sex == PetSex.female ? 'Female' : 'Male',
      if (pet.neutered == true) 'Neutered',
      if (pet.birthday != null) _age(pet.birthday!),
    ];

    return Row(
      children: [
        PetAvatar(name: pet.name, photoPath: pet.photoPath, radius: 36),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pet.name, style: theme.textTheme.headlineSmall),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  facts.join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Approximate, in whole years or months. Owners do not want a day count.
  static String _age(DateTime birthday) {
    final now = DateTime.now();
    final months =
        (now.year - birthday.year) * 12 + now.month - birthday.month;
    if (months < 1) {
      return 'Newborn';
    }
    if (months < 24) {
      return '$months ${months == 1 ? 'month' : 'months'} old';
    }
    final years = months ~/ 12;
    return '$years years old';
  }
}

class _MedicinesSection extends ConsumerWidget {
  const _MedicinesSection({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final medicines = ref.watch(medicinesForPetProvider(petId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Medicines', style: theme.textTheme.titleLarge),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => MedicineEditScreen(petId: petId),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        medicines.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Something went wrong.\n$error'),
          data: (medicines) => medicines.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No medicines on record.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final medicine in medicines)
                      _MedicineTile(petId: petId, medicine: medicine),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MedicineTile extends ConsumerWidget {
  const _MedicineTile({required this.petId, required this.medicine});

  final String petId;
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final schedule = medicine.schedule;
    final times = schedule.timesOfDayMinutes
        .map(
          (minutes) => TimeOfDay(
            hour: minutes ~/ 60,
            minute: minutes % 60,
          ).format(context),
        )
        .join(', ');

    final run = schedule.isOpenEnded
        ? 'from ${DateFormat.yMMMd().format(schedule.startDate)}, ongoing'
        : '${DateFormat.yMMMd().format(schedule.startDate)} – '
              '${DateFormat.yMMMd().format(schedule.endDate!)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        title: Text(
          medicine.name,
          style: TextStyle(
            decoration: medicine.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          [
            if (medicine.dosage != null) medicine.dosage!,
            times,
            run,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Medicine options',
          onSelected: (action) async {
            final repository = ref.read(medicineRepositoryProvider);
            switch (action) {
              case 'edit':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        MedicineEditScreen(petId: petId, medicine: medicine),
                  ),
                );
              case 'toggle':
                await repository.setActive(
                  medicine.id,
                  isActive: !medicine.isActive,
                );
              case 'delete':
                await repository.delete(medicine.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(medicine.isActive ? 'Stop course' : 'Restart'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
