/// One photo in a pet's album.
class PetPhoto {
  const PetPhoto({
    required this.id,
    required this.petId,
    required this.path,
    required this.takenAt,
    required this.createdAt,
    this.caption,
  });

  final String id;
  final String petId;

  /// Absolute path to the stored copy.
  final String path;

  /// When the photo was taken, falling back to when it was added.
  final DateTime takenAt;

  final String? caption;
  final DateTime createdAt;

  bool get hasCaption => caption != null && caption!.trim().isNotEmpty;

  PetPhoto copyWith({String? caption, DateTime? takenAt}) => PetPhoto(
    id: id,
    petId: petId,
    path: path,
    takenAt: takenAt ?? this.takenAt,
    caption: caption ?? this.caption,
    createdAt: createdAt,
  );
}
