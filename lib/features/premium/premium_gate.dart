import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'paywall_screen.dart';

/// The things the free tier does not include.
enum PremiumFeature {
  /// Keeping more than one pet.
  extraPets,

  /// Attaching photos to a vet visit.
  visitPhotos,

  /// The vet summary PDF.
  vetSummary;

  String get headline => switch (this) {
    PremiumFeature.extraPets => 'Add another pet',
    PremiumFeature.visitPhotos => 'Attach photos to a visit',
    PremiumFeature.vetSummary => 'Take a summary to the vet',
  };

  String get explanation => switch (this) {
    PremiumFeature.extraPets =>
      'The free version keeps one pet. Unlock PawsLog to track the whole '
          'household.',
    PremiumFeature.visitPhotos =>
      'Keep lab results, prescriptions and photos of what you noticed, '
          'attached to the visit they belong to.',
    PremiumFeature.vetSummary =>
      'One page with everything your vet asks for: vaccines and their dates, '
          'current medicines, how the weight is moving, and recent visits.',
  };
}

/// How many pets the free tier covers.
const int freePetLimit = 1;

/// Runs [action] if the feature is unlocked, otherwise shows the paywall.
///
/// Gates are on *doing* a thing, never on seeing one. An owner whose access
/// lapsed, or who restored a backup made on a paid install, keeps every pet,
/// photo and record they already have — the app simply stops letting them
/// add more. Hiding data someone entered would be taking it away.
Future<void> runIfUnlocked(
  BuildContext context,
  WidgetRef ref, {
  required PremiumFeature feature,
  required FutureOr<void> Function() action,
}) async {
  // Read through the service rather than `isPremiumProvider`. Nothing
  // watches that provider, so reading it starts its subscription and hands
  // back `loading` — which would lock out a paying owner on every tap. The
  // service answers from its cache when the store cannot be reached.
  final unlocked = await ref.read(entitlementServiceProvider).isActive();
  if (!context.mounted) {
    return;
  }
  if (unlocked) {
    await action();
    return;
  }
  await showPaywall(context, feature: feature);
}
