/// Whether a condition is current or behind them.
enum ConditionStatus {
  ongoing('Ongoing'),
  past('Past');

  const ConditionStatus(this.label);

  final String label;
}

/// Something a vet has diagnosed.
///
/// A record of what the owner was told, never something the app worked out.
/// The suggestion list on the editor is a pick-list, not a shortlist of
/// guesses — see "What has your vet diagnosed?" in CLAUDE.md.
class PetCondition {
  const PetCondition({
    required this.id,
    required this.petId,
    required this.name,
    required this.status,
    required this.createdAt,
    this.date,
    this.notes,
  });

  final String id;
  final String petId;
  final String name;
  final ConditionStatus status;

  /// When it was diagnosed, if the owner knows. Date-only at UTC midnight.
  final DateTime? date;

  final String? notes;
  final DateTime createdAt;

  bool get isOngoing => status == ConditionStatus.ongoing;

  PetCondition copyWith({
    String? name,
    ConditionStatus? status,
    DateTime? date,
    String? notes,
  }) => PetCondition(
    id: id,
    petId: petId,
    name: name ?? this.name,
    status: status ?? this.status,
    date: date ?? this.date,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );
}

/// Something the pet reacts to.
///
/// Shown on the profile rather than only in the record: an allergy is safety
/// information, and the moment it matters is rarely the moment someone goes
/// looking for it.
class PetAllergy {
  const PetAllergy({
    required this.id,
    required this.petId,
    required this.allergen,
    required this.createdAt,
    this.reaction,
    this.notes,
  });

  final String id;
  final String petId;

  /// What they react to: a food, a drug, a flea treatment.
  final String allergen;

  /// What happens: "vomiting", "itching round the ears".
  final String? reaction;

  final String? notes;
  final DateTime createdAt;

  PetAllergy copyWith({String? allergen, String? reaction, String? notes}) =>
      PetAllergy(
        id: id,
        petId: petId,
        allergen: allergen ?? this.allergen,
        reaction: reaction ?? this.reaction,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );
}
