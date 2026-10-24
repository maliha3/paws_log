import 'medicine.dart';
import 'pet.dart';
import 'pet_condition.dart';
import 'vaccination_record.dart';
import 'vet_visit.dart';
import 'weight_entry.dart';

/// Everything the vet summary puts on the page.
///
/// Assembled once and handed to the builder, so what goes on the page is
/// decided in one place and the builder stays a pure function of its input.
class VetSummary {
  const VetSummary({
    required this.pet,
    required this.vaccinations,
    required this.medicines,
    required this.weights,
    required this.visits,
    required this.unit,
    required this.generatedAt,
    this.conditions = const [],
    this.allergies = const [],
  });

  final Pet pet;

  /// Diagnosed conditions, ongoing first.
  final List<PetCondition> conditions;

  /// Allergies, which go near the top of the page: the point of printing
  /// them is that a vet who has not met this cat sees them without looking.
  final List<PetAllergy> allergies;

  /// Most recent first.
  final List<VaccinationRecord> vaccinations;

  /// Courses still running. A finished course is history, not something the
  /// vet needs to know the cat is on right now.
  final List<Medicine> medicines;

  /// Oldest first, as a trend reads.
  final List<WeightEntry> weights;

  /// The most recent visits, newest first.
  final List<VetVisit> visits;

  final WeightUnit unit;
  final DateTime generatedAt;

  /// How many visits the summary carries.
  static const int visitCount = 3;

  /// Conditions the cat has now, which is what a vet reads first.
  List<PetCondition> get ongoingConditions => [
    for (final condition in conditions)
      if (condition.isOngoing) condition,
  ];

  List<PetCondition> get pastConditions => [
    for (final condition in conditions)
      if (!condition.isOngoing) condition,
  ];

  WeightEntry? get latestWeight => weights.isEmpty ? null : weights.last;

  /// Change across the whole recorded series, in the display unit.
  double? get weightChange {
    if (weights.length < 2) {
      return null;
    }
    return unit.fromGrams(weights.last.grams) -
        unit.fromGrams(weights.first.grams);
  }
}
