import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/pet_avatar.dart';
import '../../data/providers.dart';
import 'pet_detail_screen.dart';
import 'pet_edit_screen.dart';

/// The pets the owner is tracking.
class PetsScreen extends ConsumerWidget {
  const PetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (context) => const PetEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add a pet'),
      ),
      body: pets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong.\n$error')),
        data: (pets) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final pet in pets)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: PetAvatar(
                    name: pet.name,
                    photoPath: pet.photoPath,
                    radius: 24,
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
