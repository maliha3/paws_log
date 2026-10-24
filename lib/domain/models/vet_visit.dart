/// A trip to the vet, and what came of it.
class VetVisit {
  const VetVisit({
    required this.id,
    required this.petId,
    required this.visitedOn,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    this.clinic,
    this.vetName,
    this.notes,
    this.cost,
  });

  final String id;
  final String petId;

  /// Date-only, held at UTC midnight.
  final DateTime visitedOn;

  /// What the visit was for, e.g. "Limping on back left leg".
  final String reason;

  final String? clinic;
  final String? vetName;
  final String? notes;

  /// What it cost, in the smallest unit of the owner's currency. Null when
  /// they did not record it, which is not the same as free.
  final int? cost;

  final DateTime createdAt;
  final DateTime updatedAt;

  VetVisit copyWith({
    DateTime? visitedOn,
    String? reason,
    String? clinic,
    String? vetName,
    String? notes,
    int? cost,
    DateTime? updatedAt,
  }) => VetVisit(
    id: id,
    petId: petId,
    visitedOn: visitedOn ?? this.visitedOn,
    reason: reason ?? this.reason,
    clinic: clinic ?? this.clinic,
    vetName: vetName ?? this.vetName,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A photo attached to a visit — a lab result, a prescription, a wound.
class VisitAttachment {
  const VisitAttachment({
    required this.id,
    required this.visitId,
    required this.filePath,
    required this.addedAt,
    this.caption,
  });

  final String id;
  final String visitId;

  /// Path to a copy inside the app's documents directory. The picker's own
  /// temporary file is not durable, so it is never stored here.
  final String filePath;

  final String? caption;
  final DateTime addedAt;
}
