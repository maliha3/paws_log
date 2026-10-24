import 'package:drift/drift.dart';

import '../converters/string_list_converter.dart';
import 'pets.dart';
import 'vet_visits.dart';

/// A prescription as the owner received it: the pages, and whatever could be
/// read off them.
///
/// The pages are the record. The extracted text and anything derived from it
/// are a convenience laid over them, and never replace them.
@DataClassName('PrescriptionRow')
class Prescriptions extends Table {
  TextColumn get id => text()();
  TextColumn get petId =>
      text().references(Pets, #id, onDelete: KeyAction.cascade)();

  /// The visit it came from, when the owner recorded one.
  TextColumn get vetVisitId => text()
      .nullable()
      .references(VetVisits, #id, onDelete: KeyAction.setNull)();

  /// Date-only, held at UTC midnight.
  DateTimeColumn get date => dateTime()();

  TextColumn get vetName => text().nullable()();
  TextColumn get clinic => text().nullable()();

  /// Page images in order, as paths inside the app's documents directory.
  TextColumn get imagePaths => text().map(const StringListConverter())();

  /// Raw OCR output, kept exactly as recognised. Null when the owner saved
  /// the photos without extracting anything.
  TextColumn get extractedText => text().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
