/// Whether a pet is male, female, or not recorded.
enum PetSex { unknown, male, female }

/// A cat (or other pet) the owner is tracking care for.
class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.photoPath,
    this.birthday,
    this.breed,
    this.sex = PetSex.unknown,
    this.neutered,
    this.archivedAt,
  });

  final String id;
  final String name;

  /// Path to a copy of the photo inside the app's documents directory. The
  /// picker's own temporary file is not durable, so it is never stored here.
  final String? photoPath;

  /// Date-only, stored as UTC midnight. Null when the owner does not know it.
  final DateTime? birthday;

  final String? breed;
  final PetSex sex;

  /// Null means "not recorded" — a real state before the first vet visit.
  final bool? neutered;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the pet is archived; archived pets stay out of Today.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  Pet copyWith({
    String? name,
    String? photoPath,
    DateTime? birthday,
    String? breed,
    PetSex? sex,
    bool? neutered,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) => Pet(
    id: id,
    name: name ?? this.name,
    photoPath: photoPath ?? this.photoPath,
    birthday: birthday ?? this.birthday,
    breed: breed ?? this.breed,
    sex: sex ?? this.sex,
    neutered: neutered ?? this.neutered,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt ?? this.archivedAt,
  );
}
