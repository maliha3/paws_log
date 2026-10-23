import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/data/repositories/vaccination_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/weight_entry.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/services/vet_summary/vet_summary_pdf.dart';
import 'package:paws_log/services/vet_summary/vet_summary_service.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late VetSummaryService service;
  late tz.TZDateTime now;
  late Pet mochi;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    db = memoryDatabase();
    pets = PetRepository(db);
    service = VetSummaryService(
      vaccinations: VaccinationRepository(db),
      medicines: MedicineRepository(db),
      weights: WeightRepository(db),
      visits: VetVisitRepository(db),
      settings: SettingsRepository(db),
    );
    mochi = await pets.create(
      name: 'Mochi',
      breed: 'Ragdoll',
      sex: PetSex.female,
      neutered: true,
      birthday: DateTime.utc(2022, 6, 1),
      now: now,
    );
  });

  tearDown(() => db.close());

  Future<void> addVaccine() async {
    final reminders = ReminderRepository(db);
    await reminders.create(
      petId: mochi.id,
      title: 'Yearly vaccine',
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.years(1),
      anchorDate: DateTime.utc(2026, 5, 4),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    final event = await db.select(db.reminderEvents).getSingle();
    await ReminderEventRepository(db).markDone(event.id, now: now);
  }

  Future<void> addMedicine({required bool active, String name = 'Amoxicillin'}) async {
    final medicines = MedicineRepository(db);
    final medicine = await medicines.create(
      petId: mochi.id,
      name: name,
      dosage: '1 tablet',
      now: now,
      schedule: DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: DateTime.utc(2026, 5, 4),
        endDate: DateTime.utc(2026, 5, 11),
      ),
    );
    if (!active) {
      await medicines.setActive(medicine.id, isActive: false, now: now);
    }
  }

  Future<void> addVisits(int count) async {
    final visits = VetVisitRepository(db);
    for (var index = 1; index <= count; index++) {
      await visits.create(
        petId: mochi.id,
        visitedOn: DateTime.utc(2026, index, 10),
        reason: 'Visit $index',
        clinic: 'Riverside Vets',
        now: now,
      );
    }
  }

  Future<void> addWeights(List<int> grams) async {
    final weights = WeightRepository(db);
    for (var index = 0; index < grams.length; index++) {
      await weights.create(
        petId: mochi.id,
        measuredOn: DateTime.utc(2026, index + 1, 1),
        grams: grams[index],
        now: now,
      );
    }
  }

  group('gathering', () {
    test('it carries only the last three visits, newest first', () async {
      await addVisits(5);

      final summary = await service.gather(mochi, now: now);

      expect(summary.visits, hasLength(3));
      expect(
        summary.visits.map((visit) => visit.reason),
        ['Visit 5', 'Visit 4', 'Visit 3'],
      );
    });

    test('it carries current medicines, not finished courses', () async {
      await addMedicine(active: true);
      await addMedicine(active: false, name: 'Stopped course');

      final summary = await service.gather(mochi, now: now);

      expect(summary.medicines, hasLength(1));
      expect(summary.medicines.single.name, 'Amoxicillin');
    });

    test('vaccinations come through, most recent first', () async {
      await addVaccine();

      final summary = await service.gather(mochi, now: now);

      expect(summary.vaccinations, hasLength(1));
      expect(summary.vaccinations.single.name, 'Yearly vaccine');
      expect(summary.vaccinations.single.nextDueOn, isNotNull);
    });

    test('weights come oldest first, as a trend reads', () async {
      await addWeights([4200, 4300, 4450]);

      final summary = await service.gather(mochi, now: now);

      expect(summary.weights.map((entry) => entry.grams), [4200, 4300, 4450]);
      expect(summary.latestWeight!.grams, 4450);
      expect(summary.weightChange, closeTo(0.25, 0.001));
    });

    test('it uses the owner\'s chosen unit', () async {
      await SettingsRepository(db).setWeightUnit(WeightUnit.pounds);
      await addWeights([4200, 4450]);

      final summary = await service.gather(mochi, now: now);

      expect(summary.unit, WeightUnit.pounds);
      expect(summary.weightChange, closeTo(0.55, 0.01));
    });

    test('a single weighing has no change to report', () async {
      await addWeights([4200]);

      final summary = await service.gather(mochi, now: now);

      expect(summary.latestWeight, isNotNull);
      expect(summary.weightChange, isNull);
    });
  });

  group('the PDF', () {
    Future<List<int>> buildPdf() async {
      final summary = await service.gather(mochi, now: now);
      return const VetSummaryPdf().build(summary);
    }

    test('a full summary produces a readable PDF', () async {
      await addVaccine();
      await addMedicine(active: true);
      await addVisits(4);
      await addWeights([4200, 4300, 4450]);

      final bytes = await buildPdf();

      expect(bytes, isNotEmpty);
      expect(
        String.fromCharCodes(bytes.take(5)),
        '%PDF-',
        reason: 'the magic number every reader looks for',
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('an empty record still produces a page', () async {
      // A cat added five minutes ago has none of this, and the owner may
      // still be taking them to the vet today.
      final bytes = await buildPdf();

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('one weighing produces a page without a chart', () async {
      await addWeights([4200]);

      final bytes = await buildPdf();

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a flat weight series does not collapse the chart', () async {
      await addWeights([4200, 4200, 4200]);

      final bytes = await buildPdf();

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('it is written for the pet it was asked about', () async {
      await addVaccine();
      final summary = await service.gather(mochi, now: now);

      expect(summary.pet.name, 'Mochi');
      expect(summary.generatedAt, now);
    });

    test('the file can be written and reopened', () async {
      await addVaccine();
      await addWeights([4200, 4450]);
      final bytes = await buildPdf();

      final directory = Directory.systemTemp.createTempSync('paws_log_pdf');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/summary.pdf')
        ..writeAsBytesSync(bytes);

      expect(file.lengthSync(), bytes.length);
      expect(String.fromCharCodes(file.readAsBytesSync().take(5)), '%PDF-');
    });
  });
}
