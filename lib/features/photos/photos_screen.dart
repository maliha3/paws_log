import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/empty_section.dart';
import '../../data/providers.dart';
import '../../domain/models/pet_photo.dart';
import 'photo_viewer_screen.dart';

/// One pet's album as a grid, newest first.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({required this.petId, super.key});

  final String petId;

  /// Columns in the grid. Three is a cat-sized thumbnail on a phone.
  static const int columns = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);
    final pet = pets.hasValue
        ? pets.requireValue.where((pet) => pet.id == petId).firstOrNull
        : null;
    final album = ref.watch(photosForPetProvider(petId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pet == null ? 'Photos' : '${pet.name}’s photos',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a photo',
        onPressed: () => showAddPhotoSheet(context, ref, petId: petId),
        child: const Icon(Icons.add),
      ),
      body: album.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Something went wrong.\n$error'),
        ),
        data: (photos) => photos.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
                child: EmptySection(
                  icon: Icons.photo_library_outlined,
                  message:
                      'No photos yet. Everything you add stays on this phone, '
                      'and travels with your backup.',
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 96),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                itemCount: photos.length,
                itemBuilder: (context, index) => _Tile(
                  photo: photos[index],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => PhotoViewerScreen(
                        petId: petId,
                        initialPhotoId: photos[index].id,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Offers the camera or the library.
Future<void> showAddPhotoSheet(
  BuildContext context,
  WidgetRef ref, {
  required String petId,
}) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) => SafeArea(
    // Scrollable: at the largest text sizes two tiles and their subtitles are
    // taller than a sheet is allowed to be.
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (source, icon, title, subtitle) in [
            (
              ImageSource.camera,
              Icons.photo_camera_outlined,
              'Take a photo',
              'One shot, straight into the album',
            ),
            (
              ImageSource.gallery,
              Icons.photo_library_outlined,
              'Choose from Photos',
              'Pick as many as you like',
            ),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () {
                Navigator.of(sheet).pop();
                ref
                    .read(petPhotoRepositoryProvider)
                    .addFrom(source, petId: petId);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  ),
);

/// One square thumbnail.
///
/// Decoded at grid size through [cacheWidth] rather than read from a stored
/// thumbnail file: one decode, and nothing extra on disk to keep in step.
class _Tile extends StatelessWidget {
  const _Tile({required this.photo, required this.onTap});

  final PetPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width / PhotosScreen.columns;
    final pixels = (width * MediaQuery.devicePixelRatioOf(context)).round();

    return InkWell(
      onTap: onTap,
      child: Semantics(
        label: photo.hasCaption ? photo.caption : 'Photo',
        image: true,
        child: Image.file(
          File(photo.path),
          fit: BoxFit.cover,
          // Null, not zero: a surface with no width yet is a hint we cannot
          // give, and `Image` asserts on a non-positive one.
          cacheWidth: pixels > 0 ? pixels : null,
          errorBuilder: (context, _, _) => ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}
