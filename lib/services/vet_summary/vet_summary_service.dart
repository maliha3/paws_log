import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/pet_health_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/vaccination_repository.dart';
import '../../data/repositories/vet_visit_repository.dart';
import '../../data/repositories/weight_repository.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/vet_summary.dart';

/// Gathers what the vet summary needs.
class VetSummaryService {
  const VetSummaryService({
    required this.vaccinations,
    required this.medicines,
    required this.weights,
    required this.visits,
    required this.settings,
    required this.health,
  });

  final VaccinationRepository vaccinations;
  final MedicineRepository medicines;
  final WeightRepository weights;
  final VetVisitRepository visits;
  final SettingsRepository settings;
  final PetHealthRepository health;

  Future<VetSummary> gather(Pet pet, {DateTime? now}) async {
    final allMedicines = await medicines.watchForPet(pet.id).first;
    final allVisits = await visits.watchForPet(pet.id).first;

    return VetSummary(
      pet: pet,
      vaccinations: await vaccinations.watchForPet(pet.id).first,
      // Only what the cat is on now. A finished course is history, and a
      // vet reading this wants the current picture.
      medicines: [
        for (final medicine in allMedicines)
          if (medicine.isActive) medicine,
      ],
      conditions: await health.watchConditions(pet.id).first,
      allergies: await health.watchAllergies(pet.id).first,
      weights: await weights.watchForPet(pet.id).first,
      visits: allVisits.take(VetSummary.visitCount).toList(),
      unit: await settings.weightUnit(),
      generatedAt: now ?? DateTime.now(),
    );
  }
}
