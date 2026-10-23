import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../data/providers.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/pet.dart';
import '../health/visit_edit_screen.dart';
import '../medicines/medicine_edit_screen.dart';
import '../weight/weight_section.dart';
import 'pet_edit_screen.dart';

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
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          IconButton(
            tooltip: 'Edit pet',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => PetEditScreen(pet: pet),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Pet options',
            onSelected: (action) async {
              final repository = ref.read(petRepositoryProvider);
              final navigator = Navigator.of(context);
              if (action == 'archive') {
                await repository.archive(pet.id);
              } else {
                await repository.delete(pet.id);
              }
              navigator.pop();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'archive',
                child: Text('Archive'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete everything'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(pet: pet),
          const SizedBox(height: 24),
          WeightSection(petId: petId),
          const SizedBox(height: 24),
          _MedicinesSection(petId: petId),
          const SizedBox(height: 24),
          _VaccinationsSection(petId: petId),
          const SizedBox(height: 24),
          _VisitsSection(petId: petId),
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
    final medicines = ref.watch(medicinesForPetProvider(petId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Medicines',
          addTooltip: 'Add a medicine',
          onAdd: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => MedicineEditScreen(petId: petId),
            ),
          ),
        ),
        const SizedBox(height: 4),
        medicines.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Something went wrong.\n$error'),
          data: (medicines) => medicines.isEmpty
              ? const _EmptySection('No medicines on record.')
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


/// A heading with an "Add" affordance, shared by the profile's sections.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAdd, this.addTooltip});

  final String title;
  final VoidCallback? onAdd;

  /// Several sections offer an "Add", so the button says which it is for —
  /// for a screen reader, and for anything else trying to tell them apart.
  final String? addTooltip;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (onAdd != null)
        Tooltip(
          message: addTooltip ?? 'Add',
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
    ],
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _VaccinationsSection extends ConsumerWidget {
  const _VaccinationsSection({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(vaccinationsForPetProvider(petId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Vaccinations'),
        const SizedBox(height: 4),
        records.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text('$error'),
          data: (records) => records.isEmpty
              ? const _EmptySection(
                  'Nothing yet. Marking a vaccine reminder done records it '
                  'here.',
                )
              : Column(
                  children: [
                    for (final record in records)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.vaccines_outlined),
                          title: Text(record.name),
                          subtitle: Text(
                            [
                              'Given ${DateFormat.yMMMd().format(record.administeredOn)}',
                              if (record.nextDueOn != null)
                                'next ${DateFormat.yMMMd().format(record.nextDueOn!)}',
                            ].join(' · '),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _VisitsSection extends ConsumerWidget {
  const _VisitsSection({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visits = ref.watch(visitsForPetProvider(petId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Vet visits',
          addTooltip: 'Add a vet visit',
          onAdd: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => VisitEditScreen(petId: petId),
            ),
          ),
        ),
        const SizedBox(height: 4),
        visits.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Text('$error'),
          data: (visits) => visits.isEmpty
              ? const _EmptySection('No visits recorded.')
              : Column(
                  children: [
                    for (final visit in visits)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.local_hospital_outlined),
                          title: Text(visit.reason),
                          subtitle: Text(
                            [
                              DateFormat.yMMMd().format(visit.visitedOn),
                              if (visit.clinic != null) visit.clinic!,
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) =>
                                  VisitEditScreen(petId: petId, visit: visit),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
