import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/category_palette.dart';
import '../../core/widgets/pet_avatar.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/providers.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/pet_condition.dart';
import '../medical/medical_screen.dart';
import '../photos/photos_screen.dart';
import '../reminders/reminders_screen.dart';
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
          const SizedBox(height: 16),
          _AllergyBanner(petId: petId),
          _RemindersCard(petId: petId),
          const SizedBox(height: 12),
          _MedicalCard(petId: petId),
          const SizedBox(height: 12),
          _PhotosCard(petId: petId),
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

/// The way into the pet's album.
class _PhotosCard extends ConsumerWidget {
  const _PhotosCard({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(photosForPetProvider(petId));
    final count = album.hasValue ? album.requireValue.length : 0;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text('Photos'),
        subtitle: Text(
          switch (count) {
            0 => 'Nothing yet \u2014 add the first one',
            1 => '1 photo',
            _ => '$count photos',
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => PhotosScreen(petId: petId),
          ),
        ),
      ),
    );
  }
}

/// What this cat reacts to, on the profile rather than only in the record.
///
/// An allergy is safety information, and the moment it matters — a new food,
/// a locum vet, someone else feeding the cat — is rarely the moment anyone
/// goes looking for it. Absent entirely when there is nothing to say, so it
/// never becomes furniture people stop reading.
class _AllergyBanner extends ConsumerWidget {
  const _AllergyBanner({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final warn = context.categories.fleaTick;
    final allergies = ref.watch(allergiesForPetProvider(petId));
    final reactions = allergies.hasValue
        ? allergies.requireValue
        : const <PetAllergy>[];

    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => MedicalScreen(
                petId: petId,
                initialSegment: MedicalSegment.health,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: warn),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reactions.length == 1 ? 'Allergy' : 'Allergies',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reactions
                            .map(
                              (allergy) => allergy.reaction == null
                                  ? allergy.allergen
                                  : '${allergy.allergen} '
                                        '(${allergy.reaction})',
                            )
                            .join(', '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way into the pet's recurring care.
class _RemindersCard extends ConsumerWidget {
  const _RemindersCard({required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersForPetProvider(petId));
    final all = reminders.hasValue ? reminders.requireValue : const [];
    final active = all.where((reminder) => reminder.isActive).length;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.notifications_none),
        title: const Text('Reminders'),
        subtitle: Text(
          switch (active) {
            0 when all.isEmpty => 'Nothing scheduled yet',
            0 => 'All paused',
            1 => '1 reminder',
            _ => '$active reminders',
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => RemindersScreen(petId: petId),
          ),
        ),
      ),
    );
  }
}
