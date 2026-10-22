import 'dart:io';

import 'package:flutter/material.dart';

/// A pet's photo, falling back to the first letter of their name.
class PetAvatar extends StatelessWidget {
  const PetAvatar({
    required this.name,
    this.photoPath,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? photoPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = photoPath;
    // A stored photo can go missing if the owner cleared app data, so the
    // initial has to work as a fallback rather than an error state.
    final hasPhoto = path != null && File(path).existsSync();

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
