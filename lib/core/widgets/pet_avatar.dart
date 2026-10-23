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

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.alphaBlend(
              scheme.tertiary.withValues(alpha: 0.35),
              scheme.primaryContainer,
            ),
          ],
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        foregroundImage: hasPhoto ? FileImage(File(path)) : null,
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontSize: radius * 0.78,
            fontWeight: FontWeight.w800,
            fontVariations: const [FontVariation('wght', 800)],
          ),
        ),
      ),
    );
  }
}
