/// Row to domain model mappers.
///
/// Repositories return domain models, never drift rows (see CLAUDE.md), and
/// this is the one place that knows how the two line up.
library;

import '../../domain/models/dose_log.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/pet.dart';
import '../../domain/models/pet_photo.dart';
import '../../domain/models/prescription.dart';
import '../../domain/models/vaccination_record.dart';
import '../../domain/models/vet_visit.dart';
import '../../domain/models/weight_entry.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/reminder_event.dart';
import '../../domain/repeat_rule.dart';
import 'app_database.dart';

extension PetRowMapper on PetRow {
  Pet toDomain() => Pet(
    id: id,
    name: name,
    photoPath: photoPath,
    birthday: birthday,
    breed: breed,
    sex: sex,
    neutered: neutered,
    createdAt: createdAt,
    updatedAt: updatedAt,
    archivedAt: archivedAt,
  );
}

extension ReminderRowMapper on ReminderRow {
  Reminder toDomain() => Reminder(
    id: id,
    petId: petId,
    title: title,
    category: category,
    repeat: RepeatRule(unit: repeatUnit, interval: repeatInterval),
    anchorDate: anchorDate,
    timeOfDayMinutes: timeOfDayMinutes,
    nextDueAt: nextDueAt,
    isActive: isActive,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension ReminderEventRowMapper on ReminderEventRow {
  ReminderEvent toDomain() => ReminderEvent(
    id: id,
    reminderId: reminderId,
    scheduledFor: scheduledFor,
    status: status,
    completedAt: completedAt,
    snoozedUntil: snoozedUntil,
    notes: notes,
  );
}

extension MedicineRowMapper on MedicineRow {
  Medicine toDomain() => Medicine(
    id: id,
    petId: petId,
    name: name,
    dosage: dosage,
    schedule: DoseSchedule(
      timesOfDayMinutes: timesOfDayMinutes,
      startDate: startDate,
      intervalDays: intervalDays,
      endDate: endDate,
    ),
    notes: notes,
    prescriptionId: prescriptionId,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension PetPhotoRowMapper on PetPhotoRow {
  PetPhoto toDomain() => PetPhoto(
    id: id,
    petId: petId,
    path: path,
    takenAt: takenAt,
    caption: caption,
    createdAt: createdAt,
  );
}

extension DoseLogRowMapper on DoseLogRow {
  DoseLog toDomain() => DoseLog(
    id: id,
    medicineId: medicineId,
    scheduledFor: scheduledFor,
    status: status,
    takenAt: takenAt,
    notes: notes,
  );
}

extension VaccinationRecordRowMapper on VaccinationRecordRow {
  VaccinationRecord toDomain() => VaccinationRecord(
    id: id,
    petId: petId,
    name: name,
    administeredOn: administeredOn,
    nextDueOn: nextDueOn,
    sourceEventId: sourceEventId,
    notes: notes,
    createdAt: createdAt,
  );
}

extension VetVisitRowMapper on VetVisitRow {
  VetVisit toDomain() => VetVisit(
    id: id,
    petId: petId,
    visitedOn: visitedOn,
    reason: reason,
    clinic: clinic,
    vetName: vetName,
    notes: notes,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension VisitAttachmentRowMapper on VisitAttachmentRow {
  VisitAttachment toDomain() => VisitAttachment(
    id: id,
    visitId: visitId,
    filePath: filePath,
    caption: caption,
    addedAt: addedAt,
  );
}

extension WeightEntryRowMapper on WeightEntryRow {
  WeightEntry toDomain() => WeightEntry(
    id: id,
    petId: petId,
    measuredOn: measuredOn,
    grams: grams,
    note: note,
    createdAt: createdAt,
  );
}

extension PrescriptionRowMapper on PrescriptionRow {
  Prescription toDomain() => Prescription(
    id: id,
    petId: petId,
    vetVisitId: vetVisitId,
    date: date,
    vetName: vetName,
    clinic: clinic,
    imagePaths: imagePaths,
    extractedText: extractedText,
    notes: notes,
    createdAt: createdAt,
  );
}
