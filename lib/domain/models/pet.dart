/// Whether a pet is male, female, or not recorded.
enum PetSex { unknown, male, female }

/// How the pet came to be with their owner.
enum PetOrigin {
  rescued('Rescued'),
  homeBorn('Born at home'),
  adopted('Adopted'),
  bought('Bought'),
  other('Other');

  const PetOrigin(this.label);

  final String label;
}

/// What the pet eats. Recorded, never advised on.
enum DietType {
  dry('Dry food'),
  wet('Wet food'),
  mixed('Dry and wet'),
  raw('Raw'),
  other('Other');

  const DietType(this.label);

  final String label;
}

/// Coat length, which is what grooming intervals hang off.
enum CoatLength {
  short('Short'),
  long('Long');

  const CoatLength(this.label);

  final String label;
}

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
    this.species,
    this.microchip,
    this.vetName,
    this.vetPhone,
    this.coatLength,
    this.origin,
    this.originDate,
    this.originNotes,
    this.motherInfo,
    this.fatherInfo,
    this.dietType,
    this.foodBrand,
    this.feedingNotes,
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

  /// Free text. The app is built for cats; an owner who keeps a rabbit
  /// should not be told their pet is not a kind of pet.
  final String? species;

  final String? microchip;

  /// The pet's own vet. A prescription carries whoever wrote it; this is the
  /// practice the owner would ring.
  final String? vetName;
  final String? vetPhone;

  /// Null until the owner says. Grooming suggestions read it, and a guess
  /// would put a long-haired cat on a short-haired brushing schedule.
  final CoatLength? coatLength;

  final PetOrigin? origin;

  /// When they arrived, or were born. Date-only, held at UTC midnight.
  final DateTime? originDate;

  final String? originNotes;

  /// Free text about the parents: a breeder's note, a litter, a name.
  final String? motherInfo;
  final String? fatherInfo;

  final DietType? dietType;
  final String? foodBrand;
  final String? feedingNotes;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the pet is archived; archived pets stay out of Today.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Whether anything beyond the basics has been filled in.
  bool get hasBackground =>
      origin != null ||
      originDate != null ||
      originNotes != null ||
      motherInfo != null ||
      fatherInfo != null;

  bool get hasDiet =>
      dietType != null || foodBrand != null || feedingNotes != null;

  /// Copies with changes. Like the rest of the app's models it cannot *clear*
  /// a field — a null argument means "leave it" — so a screen that lets the
  /// owner empty something builds a new [Pet] instead.
  Pet copyWith({
    String? name,
    String? photoPath,
    DateTime? birthday,
    String? breed,
    PetSex? sex,
    bool? neutered,
    String? species,
    String? microchip,
    String? vetName,
    String? vetPhone,
    CoatLength? coatLength,
    PetOrigin? origin,
    DateTime? originDate,
    String? originNotes,
    String? motherInfo,
    String? fatherInfo,
    DietType? dietType,
    String? foodBrand,
    String? feedingNotes,
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
    species: species ?? this.species,
    microchip: microchip ?? this.microchip,
    vetName: vetName ?? this.vetName,
    vetPhone: vetPhone ?? this.vetPhone,
    coatLength: coatLength ?? this.coatLength,
    origin: origin ?? this.origin,
    originDate: originDate ?? this.originDate,
    originNotes: originNotes ?? this.originNotes,
    motherInfo: motherInfo ?? this.motherInfo,
    fatherInfo: fatherInfo ?? this.fatherInfo,
    dietType: dietType ?? this.dietType,
    foodBrand: foodBrand ?? this.foodBrand,
    feedingNotes: feedingNotes ?? this.feedingNotes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt ?? this.archivedAt,
  );
}
