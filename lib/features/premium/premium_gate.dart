import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'paywall_screen.dart';

/// The things the free tier does not include.
///
/// Three, and they hang off one idea: **one cat free, the household paid**.
/// Photos on a visit used to be a fourth, which stopped making sense the day
/// the photo album became free and unlimited — an owner who could keep five
/// hundred pictures of their cat but not attach one to the visit it belonged
/// to would rightly read that as arbitrary.
enum PremiumFeature {
  /// Keeping more than one pet.
  extraPets,

  /// Scanning a prescription, past the first few.
  prescriptionScans,

  /// The vet summary PDF.
  vetSummary;

  String get headline => switch (this) {
    PremiumFeature.extraPets => 'Add another pet',
    PremiumFeature.prescriptionScans => 'Scan another prescription',
    PremiumFeature.vetSummary => 'Take a summary to the vet',
  };

  String get explanation => switch (this) {
    PremiumFeature.extraPets =>
      'The free version keeps one cat. Unlock PawsLog once and it covers the '
          'whole household.',
    PremiumFeature.prescriptionScans =>
      'The free version reads $freeScanLimit prescriptions. Unlock PawsLog '
          'and it reads every one — the pages you have already scanned stay '
          'where they are.',
    PremiumFeature.vetSummary =>
      'One page with everything your vet asks for: vaccines and their dates, '
          'current medicines, how the weight is moving, and recent visits.',
  };
}

/// How many pets the free tier covers.
const int freePetLimit = 1;

/// How many prescriptions the free tier reads.
///
/// Enough to feel what the scanner does — which is the whole argument for
/// charging for it — and few enough that an owner whose cat is on a course
/// of anything will reach the end of them.
const int freeScanLimit = 3;

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
