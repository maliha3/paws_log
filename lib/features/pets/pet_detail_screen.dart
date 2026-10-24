import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/category_palette.dart';
import '../../core/widgets/pet_avatar.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/providers.dart';
import '../../domain/models/pet.dart';
import '../medical/medical_screen.dart';
import '../premium/premium_gate.dart';
import '../weight/weight_section.dart';
import 'pet_edit_screen.dart';

/// Who one pet is, and the way into their record.
///
/// The profile answers "who is this cat" — the facts, the photo, the weight
/// trend. The four kinds of medical record sit behind [MedicalScreen], so
/// reaching the vaccines does not mean scrolling past every medicine.
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          IconButton(
            tooltip: 'Vet summary',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => runIfUnlocked(
              context,
              ref,
              feature: PremiumFeature.vetSummary,
              action: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(vetSummarySharingProvider).shareFor(pet);
                } on Object catch (error) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Could not build the summary: $error'),
                    ),
                  );
                }
              },
            ),
          ),
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
              PopupMenuItem(value: 'archive', child: Text('Archive')),
              PopupMenuItem(value: 'delete', child: Text('Delete everything')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _Header(pet: pet),
          const SizedBox(height: 20),
          _MedicalCard(petId: petId),
          const SizedBox(height: 24),
          WeightSection(petId: petId),
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
    final palette = context.categories;

    // Short, unrelated facts read better as tiles than as a sentence.
    final facts = <(String, String)>[
      if (pet.sex != PetSex.unknown)
        (pet.sex == PetSex.female ? 'Female' : 'Male', 'Sex'),
      if (pet.birthday != null) (_age(pet.birthday!), 'Age'),
      if (pet.breed != null) (pet.breed!, 'Breed'),
      if (pet.neutered != null) (pet.neutered! ? 'Yes' : 'No', 'Neutered'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Hero(
              tag: 'pet-avatar-${pet.id}',
              child: PetAvatar(
                name: pet.name,
                photoPath: pet.photoPath,
                radius: 40,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(pet.name, style: theme.textTheme.headlineMedium),
            ),
          ],
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (index, fact) in facts.indexed)
                FactChip(
                  value: fact.$1,
                  label: fact.$2,
                  background: palette.pastel(index),
                  foreground: palette.onPastel,
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Approximate, in whole years or months. Owners do not want a day count.
  static String _age(DateTime birthday) {
    final now = DateTime.now();
    final months = (now.year - birthday.year) * 12 + now.month - birthday.month;
    if (months < 1) {
      return 'Newborn';
    }
    if (months < 24) {
      return '$months mo';
    }
    final years = months ~/ 12;
    return '$years yrs';
  }
}

/// The way into the pet's medical record.
class _MedicalCard extends StatelessWidget {
  const _MedicalCard({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.medical_services_outlined),
      title: const Text('Medical record'),
      subtitle: const Text(
        'Prescriptions, medicines, vaccines and vet visits',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MedicalScreen(petId: petId),
        ),
      ),
    ),
  );
}
