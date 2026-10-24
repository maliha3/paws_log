/// A prescription as the owner received it.
///
/// The pages are the record. The extracted text, and anything derived from
/// it, is a convenience laid over them and never replaces them.
class Prescription {
  const Prescription({
    required this.id,
    required this.petId,
    required this.date,
    required this.imagePaths,
    required this.createdAt,
    this.vetVisitId,
    this.vetName,
    this.clinic,
    this.extractedText,
    this.notes,
  });

  final String id;
  final String petId;

  /// The visit it came from, when the owner recorded one.
  final String? vetVisitId;

  /// Date-only, held at UTC midnight.
  final DateTime date;

  final String? vetName;
  final String? clinic;

  /// Page images in order. Page 2 is not interchangeable with page 1.
  final List<String> imagePaths;

  /// Raw OCR output, exactly as recognised. Null when the owner saved the
  /// photos without extracting anything.
  final String? extractedText;

  final String? notes;
  final DateTime createdAt;

  int get pageCount => imagePaths.length;

  /// Whether anything was read off the pages.
  bool get wasRead => extractedText != null && extractedText!.trim().isNotEmpty;

  Prescription copyWith({
    DateTime? date,
    String? vetName,
    String? clinic,
    List<String>? imagePaths,
    String? extractedText,
    String? notes,
    String? vetVisitId,
  }) => Prescription(
    id: id,
    petId: petId,
    vetVisitId: vetVisitId ?? this.vetVisitId,
    date: date ?? this.date,
    vetName: vetName ?? this.vetName,
    clinic: clinic ?? this.clinic,
    imagePaths: imagePaths ?? this.imagePaths,
    extractedText: extractedText ?? this.extractedText,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );
}
