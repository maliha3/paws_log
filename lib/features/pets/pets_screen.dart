import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../domain/models/pet.dart';
import '../../data/providers.dart';
import '../backup/backup_screen.dart';
import '../premium/premium_gate.dart';
import 'pet_detail_screen.dart';
import 'pet_edit_screen.dart';

/// The pets the owner is tracking.
class PetsScreen extends ConsumerWidget {
  const PetsScreen({super.key});

  /// The first pet is free; the rest are not.
  ///
  /// The count comes from the pets actually on screen, so restoring a backup
  /// made on a paid install leaves every pet visible and merely stops another
  /// being added.
  Future<void> _addPet(
    BuildContext context,
    WidgetRef ref,
    List<Pet> existing,
  ) async {
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const PetEditScreen()),
    );

    if (existing.length < freePetLimit) {
      open();
      return;
    }
    await runIfUnlocked(
      context,
      ref,
      feature: PremiumFeature.extraPets,
      action: open,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pets'),
        actions: [
          IconButton(
            tooltip: 'Backup',
            icon: const Icon(Icons.settings_backup_restore),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const BackupScreen(),
              ),
            ),
          ),
        ],
      ),
      // Lifted clear of the floating navigation bar, which otherwise sits
      // on top of it and swallows the tap.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _addPet(context, ref, pets.value ?? const []),
          icon: const Icon(Icons.add),
          label: const Text('Add a pet'),
        ),
      ),
      body: pets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong.\n$error')),
        data: (pets) => ListView(
          // Room at the bottom for the floating bar and the button above it.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
          children: [
            for (final pet in pets)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: Hero(
                    tag: 'pet-avatar-${pet.id}',
                    child: PetAvatar(
                      name: pet.name,
                      photoPath: pet.photoPath,
                      radius: 24,
                    ),
                  ),
                  title: Text(pet.name),
                  subtitle: pet.breed == null ? null : Text(pet.breed!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => PetDetailScreen(petId: pet.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
