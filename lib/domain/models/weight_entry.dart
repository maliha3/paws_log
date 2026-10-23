/// How weights are shown. Storage is always grams.
enum WeightUnit {
  kilograms,
  pounds;

  static const double _gramsPerPound = 453.59237;

  String get label => switch (this) {
    WeightUnit.kilograms => 'kg',
    WeightUnit.pounds => 'lb',
  };

  /// Stored grams as a number in this unit.
  double fromGrams(int grams) => switch (this) {
    WeightUnit.kilograms => grams / 1000,
    WeightUnit.pounds => grams / _gramsPerPound,
  };

  /// A number in this unit as grams to store.
  int toGrams(double value) => switch (this) {
    WeightUnit.kilograms => (value * 1000).round(),
    WeightUnit.pounds => (value * _gramsPerPound).round(),
  };

  /// Formatted for display, without the unit.
  String format(int grams) => fromGrams(grams).toStringAsFixed(
    this == WeightUnit.kilograms ? 2 : 1,
  );

  static WeightUnit fromName(String name) =>
      WeightUnit.values.firstWhere((unit) => unit.name == name);
}

/// One weighing.
class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.petId,
    required this.measuredOn,
    required this.grams,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String petId;

  /// Date-only, held at UTC midnight.
  final DateTime measuredOn;

  /// Canonical storage. The display unit is a preference and never rewrites
  /// what was recorded, so switching between kg and lb is lossless.
  final int grams;

  final String? note;
  final DateTime createdAt;

  WeightEntry copyWith({DateTime? measuredOn, int? grams, String? note}) =>
      WeightEntry(
        id: id,
        petId: petId,
        measuredOn: measuredOn ?? this.measuredOn,
        grams: grams ?? this.grams,
        note: note ?? this.note,
        createdAt: createdAt,
      );
}
