/// A vaccine that was actually given.
///
/// Written automatically when a vaccine reminder is marked done, and kept
/// even if that reminder is later deleted — health history outlives the
/// schedule that produced it.
class VaccinationRecord {
  const VaccinationRecord({
    required this.id,
    required this.petId,
    required this.name,
    required this.administeredOn,
    required this.createdAt,
    this.nextDueOn,
    this.sourceEventId,
    this.notes,
  });

  final String id;
  final String petId;

  /// Taken from the reminder's title when auto-filled.
  final String name;

  /// Date-only, held at UTC midnight.
  final DateTime administeredOn;

  /// Date-only, held at UTC midnight. The occurrence that followed.
  final DateTime? nextDueOn;

  /// The reminder occurrence this came from, if any.
  ///
  /// Deliberately not a foreign key: deleting a reminder must not erase the
  /// record that the vaccine was given. It is here so that undoing a
  /// completion can find and remove the record it created.
  final String? sourceEventId;

  final String? notes;
  final DateTime createdAt;

  bool get wasAutoFilled => sourceEventId != null;
}
