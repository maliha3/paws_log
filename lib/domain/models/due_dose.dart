import 'dose_log.dart';
import 'medicine.dart';
import 'pet.dart';

/// A dose joined with the medicine and pet it belongs to.
///
/// Today needs all three to render a row, and asking the repository for them
/// together keeps the screen from fanning out into per-row queries.
class DueDose {
  const DueDose({
    required this.dose,
    required this.medicine,
    required this.pet,
  });

  final DoseLog dose;
  final Medicine medicine;
  final Pet pet;

  /// Whether this dose's time has come round.
  bool isDue(DateTime now) => !dose.scheduledFor.isAfter(now);
}
