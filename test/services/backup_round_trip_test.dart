import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_health_repository.dart';
import 'package:paws_log/data/repositories/pet_photo_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/prescription_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/settings_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/data/repositories/weight_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/pet.dart';
import 'package:paws_log/domain/models/pet_condition.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/models/weight_entry.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/services/backup/backup_service.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late Directory photos;
  late tz.TZDateTime now;

  setUpAll(initializeTestTimeZone);

  setUp(() {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    photos = Directory.systemTemp.createTempSync('paws_log_backup');
  });

  tearDown(() {
    if (photos.existsSync()) {
      photos.deleteSync(recursive: true);
    }
  });

  BackupService serviceFor(AppDatabase db) =>
      BackupService(db, photosRoot: photos);

  /// A photo file where a real one would be.
  String writePhoto(String name, List<int> bytes) {
    final file = File('${photos.path}/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// Fills a database with one of everything.
  Future<void> populate(AppDatabase db) async {
    final pets = PetRepository(db);
    final reminders = ReminderRepository(db);
    final events = ReminderEventRepository(db);
    final medicines = MedicineRepository(db);
    final visits = VetVisitRepository(db);
    final weights = WeightRepository(db);

    final mochi = await pets.create(
      name: 'Mochi',
      breed: 'Ragdoll',
      sex: PetSex.female,
      neutered: true,
      birthday: DateTime.utc(2022, 6, 1),
      photoPath: writePhoto('pet_photos/mochi.jpg', [1, 2, 3, 4, 5]),
      coatLength: CoatLength.long,
      now: now,
    );
    await pets.update(
      (await pets.findById(mochi.id))!.copyWith(
        origin: PetOrigin.rescued,
        originDate: DateTime.utc(2024, 7, 1),
        originNotes: 'Found behind the bins',
        motherInfo: 'Unknown',
        dietType: DietType.mixed,
        foodBrand: 'Royal Canin',
        feedingNotes: 'Two small meals, no chicken',
        species: 'Cat',
        microchip: '981098104512345',
        vetName: 'Riverside Vets',
        vetPhone: '01234 567890',
      ),
      now: now,
    );

    final health = PetHealthRepository(db);
    await health.addCondition(
      petId: mochi.id,
      name: 'CKD',
      date: DateTime.utc(2026, 1, 10),
      notes: 'Stage 2',
      now: now,
    );
    await health.addCondition(
      petId: mochi.id,
      name: 'Cat flu',
      status: ConditionStatus.past,
      now: now,
    );
    await health.addAllergy(
      petId: mochi.id,
      allergen: 'Chicken',
      reaction: 'Itching round the ears',
      now: now,
    );
    final luna = await pets.create(name: 'Luna', now: now);

    await reminders.create(
      petId: mochi.id,
      title: 'Yearly vaccine',
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.years(1),
      anchorDate: DateTime.utc(2026, 5, 4),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    await reminders.create(
      petId: luna.id,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: DateTime.utc(2026, 5, 4),
      timeOfDayMinutes: 18 * 60,
      now: now,
    );

    // A completed vaccine, which also writes vaccination history.
    final event = await (db.select(
      db.reminderEvents,
    )..where((e) => e.reminderId.isNotNull())).get();
    await events.markDone(event.first.id, now: now);

    // A scanned prescription, and the course that came off it.
    final prescription = await PrescriptionRepository(db).create(
      petId: mochi.id,
      date: DateTime.utc(2026, 5, 4),
      vetName: 'Dr Okafor',
      clinic: 'Riverside Vets',
      extractedText: 'Amoxicillin 50 mg twice daily for 7 days',
      imagePaths: [
        writePhoto('prescriptions/page1.jpg', [11, 12, 13]),
        writePhoto('prescriptions/page2.jpg', [14, 15]),
      ],
      now: now,
    );

    await medicines.create(
      petId: mochi.id,
      name: 'Amoxicillin',
      dosage: '1 tablet',
      notes: 'With food',
      prescriptionId: prescription.id,
      now: now,
      schedule: DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: DateTime.utc(2026, 5, 4),
        endDate: DateTime.utc(2026, 5, 7),
      ),
    );

    await visits.create(
      petId: mochi.id,
      visitedOn: DateTime.utc(2026, 4, 20),
      reason: 'Limping on back left leg',
      clinic: 'Riverside Vets',
      vetName: 'Dr Okafor',
      notes: 'Rest for a week.',
      cost: 4250,
      attachmentPaths: [
        writePhoto('visit_attachments/xray.jpg', [9, 8, 7]),
        writePhoto('visit_attachments/note.jpg', [6, 5]),
      ],
      now: now,
    );

    final album = PetPhotoRepository(db);
    await album.add(
      petId: mochi.id,
      path: writePhoto('pet_vault/sink.jpg', [21, 22, 23, 24]),
      takenAt: DateTime.utc(2026, 3, 2),
      caption: 'Asleep in the sink',
      now: now,
    );
    await album.add(
      petId: mochi.id,
      path: writePhoto('pet_vault/window.jpg', [25, 26]),
      takenAt: DateTime.utc(2026, 3, 20),
      now: now,
    );

    await weights.create(
      petId: mochi.id,
      measuredOn: DateTime.utc(2026, 4, 1),
      grams: 4200,
      note: 'After breakfast',
      now: now,
    );
    await weights.create(
      petId: mochi.id,
      measuredOn: DateTime.utc(2026, 5, 1),
      grams: 4450,
      now: now,
    );

    await SettingsRepository(db).setWeightUnit(WeightUnit.pounds);
  }

  /// Every row in every table, as comparable JSON.
  Future<Map<String, List<Map<String, dynamic>>>> snapshot(
    AppDatabase db,
  ) async => {
    'pets': [for (final r in await db.select(db.pets).get()) r.toJson()],
    'reminders': [
      for (final r in await db.select(db.reminders).get()) r.toJson(),
    ],
    'reminderEvents': [
      for (final r in await db.select(db.reminderEvents).get()) r.toJson(),
    ],
    'prescriptions': [
      for (final r in await db.select(db.prescriptions).get()) r.toJson(),
    ],
    'medicines': [
      for (final r in await db.select(db.medicines).get()) r.toJson(),
    ],
    'doseLogs': [
      for (final r in await db.select(db.doseLogs).get()) r.toJson(),
    ],
    'vetVisits': [
      for (final r in await db.select(db.vetVisits).get()) r.toJson(),
    ],
    'visitAttachments': [
      for (final r in await db.select(db.visitAttachments).get()) r.toJson(),
    ],
    'vaccinationRecords': [
      for (final r in await db.select(db.vaccinationRecords).get()) r.toJson(),
    ],
    'weightEntries': [
      for (final r in await db.select(db.weightEntries).get()) r.toJson(),
    ],
    'petPhotos': [
      for (final r in await db.select(db.petPhotos).get()) r.toJson(),
    ],
    'petConditions': [
      for (final r in await db.select(db.petConditions).get()) r.toJson(),
    ],
    'petAllergies': [
      for (final r in await db.select(db.petAllergies).get()) r.toJson(),
    ],
    'appSettings': [
      for (final r in await db.select(db.appSettings).get()) r.toJson(),
    ],
  };

  test('a full database survives export and import unchanged', () async {
    final source = memoryDatabase();
    await populate(source);
    final before = await snapshot(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    // A different database, as a fresh install would be.
    final restored = memoryDatabase();
    final summary = await serviceFor(restored).importArchive(bytes);
    final after = await snapshot(restored);

    for (final table in before.keys) {
      expect(
        after[table],
        hasLength(before[table]!.length),
        reason: '$table row count',
      );
    }

    // Photo paths are rewritten on import, so they are compared separately.
    expect(
      _withoutPaths(after),
      equals(_withoutPaths(before)),
      reason: 'every column of every row',
    );

    expect(summary.pets, 2);
    expect(
      summary.photos,
      7,
      reason: 'a portrait, two x-rays, two pages, two album photos',
    );
    expect(summary.albumPhotos, 2);
    await restored.close();
  });

  test('photo files come back with their contents', () async {
    final source = memoryDatabase();
    await populate(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    final originals = {
      for (final pet in await source.select(source.pets).get())
        if (pet.photoPath != null)
          pet.name: File(pet.photoPath!).readAsBytesSync(),
    };
    await source.close();

    // Wipe the photo directory, as a new device would have.
    photos.deleteSync(recursive: true);
    photos.createSync(recursive: true);

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);

    final pet = await (restored.select(
      restored.pets,
    )..where((p) => p.name.equals('Mochi'))).getSingle();
    expect(pet.photoPath, isNotNull);
    expect(File(pet.photoPath!).existsSync(), isTrue);
    expect(File(pet.photoPath!).readAsBytesSync(), originals['Mochi']);

    final attachments = await restored.select(restored.visitAttachments).get();
    expect(attachments, hasLength(2));
    for (final attachment in attachments) {
      expect(
        File(attachment.filePath).existsSync(),
        isTrue,
        reason: attachment.filePath,
      );
    }
    await restored.close();
  });

  test('prescription pages come back, in order, with their contents', () async {
    final source = memoryDatabase();
    await populate(source);
    final before = await source.select(source.prescriptions).getSingle();
    final originals = [
      for (final path in before.imagePaths) File(path).readAsBytesSync(),
    ];
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    // Wipe the photo directory, as a new device would have.
    photos.deleteSync(recursive: true);
    photos.createSync(recursive: true);

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);

    final after = await restored.select(restored.prescriptions).getSingle();
    expect(after.imagePaths, hasLength(2));
    expect(after.vetName, 'Dr Okafor');
    expect(after.extractedText, before.extractedText);
    for (final (index, path) in after.imagePaths.indexed) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(
        File(path).readAsBytesSync(),
        originals[index],
        reason: 'page ${index + 1} is the page it was',
      );
    }
    await restored.close();
  });

  test(
    'a restored course still points at the prescription it came from',
    () async {
      final source = memoryDatabase();
      await populate(source);
      final bytes = await serviceFor(source).exportArchive(now: now);
      await source.close();

      final restored = memoryDatabase();
      await serviceFor(restored).importArchive(bytes);

      final prescription = await restored
          .select(restored.prescriptions)
          .getSingle();
      final medicine = await (restored.select(
        restored.medicines,
      )..where((m) => m.name.equals('Amoxicillin'))).getSingle();
      expect(medicine.prescriptionId, prescription.id);
      await restored.close();
    },
  );

  test(
    'a prescription whose page has vanished keeps the pages it has',
    () async {
      final source = memoryDatabase();
      final pet = await PetRepository(source).create(name: 'Mochi', now: now);
      final kept = writePhoto('prescriptions/kept.jpg', [1, 2, 3]);
      final gone = writePhoto('prescriptions/gone.jpg', [4, 5, 6]);
      await PrescriptionRepository(source).create(
        petId: pet.id,
        date: DateTime.utc(2026, 5, 4),
        imagePaths: [kept, gone],
        now: now,
      );
      File(gone).deleteSync();

      final bytes = await serviceFor(source).exportArchive(now: now);
      await source.close();

      final restored = memoryDatabase();
      await serviceFor(restored).importArchive(bytes);

      final after = await restored.select(restored.prescriptions).getSingle();
      expect(
        after.imagePaths,
        hasLength(1),
        reason: 'the missing page is dropped rather than left as a hole',
      );
      expect(File(after.imagePaths.single).readAsBytesSync(), [1, 2, 3]);
      await restored.close();
    },
  );

  group('the photo album', () {
    test('comes back with its captions, dates and files', () async {
      final source = memoryDatabase();
      await populate(source);
      final before = await source.select(source.petPhotos).get();
      final originals = {
        for (final photo in before)
          photo.id: File(photo.path).readAsBytesSync(),
      };
      final bytes = await serviceFor(source).exportArchive(now: now);
      await source.close();

      // Wipe the photo directory, as a new device would have.
      photos.deleteSync(recursive: true);
      photos.createSync(recursive: true);

      final restored = memoryDatabase();
      await serviceFor(restored).importArchive(bytes);

      final after = await restored.select(restored.petPhotos).get();
      expect(after, hasLength(2));
      for (final photo in after) {
        expect(File(photo.path).existsSync(), isTrue, reason: photo.path);
        expect(File(photo.path).readAsBytesSync(), originals[photo.id]);
      }
      expect(
        after.map((photo) => photo.caption),
        containsAll(<String?>['Asleep in the sink', null]),
      );
      expect(
        after.map((photo) => photo.takenAt),
        containsAll([DateTime.utc(2026, 3, 2), DateTime.utc(2026, 3, 20)]),
      );
      await restored.close();
    });

    test('is left out entirely when the owner says so', () async {
      final source = memoryDatabase();
      await populate(source);
      final bytes = await serviceFor(
        source,
      ).exportArchive(now: now, includeAlbum: false);
      await source.close();

      final restored = memoryDatabase();
      final summary = await serviceFor(restored).importArchive(bytes);

      expect(
        await restored.select(restored.petPhotos).get(),
        isEmpty,
        reason:
            'rows as well as files \u2014 an album of entries pointing at '
            'nothing is worse than an empty one',
      );
      expect(summary.albumPhotos, 0);
      expect(
        await restored.select(restored.pets).get(),
        hasLength(2),
        reason: 'every record still travels',
      );
      expect(
        (await restored.select(restored.pets).get()).where(
          (pet) => pet.photoPath != null,
        ),
        hasLength(1),
        reason: 'the portrait is a record, not an album photo',
      );
      await restored.close();
    });

    test(
      'a backup made without it still restores into a new install',
      () async {
        final source = memoryDatabase();
        await populate(source);
        final bytes = await serviceFor(
          source,
        ).exportArchive(now: now, includeAlbum: false);
        await source.close();

        final restored = memoryDatabase();
        await serviceFor(restored).importArchive(bytes);

        expect(await restored.select(restored.medicines).get(), hasLength(1));
        expect(
          await restored.select(restored.visitAttachments).get(),
          hasLength(2),
        );
        await restored.close();
      },
    );

    test(
      'an import replaces an existing album rather than adding to it',
      () async {
        final source = memoryDatabase();
        await populate(source);
        final bytes = await serviceFor(source).exportArchive(now: now);
        await source.close();

        final target = memoryDatabase();
        final pet = await PetRepository(
          target,
        ).create(name: 'Someone else', now: now);
        await PetPhotoRepository(target).add(
          petId: pet.id,
          path: writePhoto('pet_vault/stale.jpg', [99]),
          now: now,
        );

        await serviceFor(target).importArchive(bytes);

        final after = await target.select(target.petPhotos).get();
        expect(after, hasLength(2));
        expect(after.map((photo) => photo.petId), everyElement(isNot(pet.id)));
        await target.close();
      },
    );

    test('the estimate separates the album from the records', () async {
      final source = memoryDatabase();
      await populate(source);

      final sizes = await serviceFor(source).estimateSize();

      expect(sizes.album, 6, reason: 'four bytes plus two');
      expect(
        sizes.records,
        5 + 3 + 2 + 3 + 2,
        reason: 'a portrait, two x-rays, two prescription pages',
      );
      expect(sizes.total, sizes.album + sizes.records);
      await source.close();
    });

    test('a size reads as a size', () {
      expect(BackupSizes.describeBytes(512), '512 B');
      expect(BackupSizes.describeBytes(2048), '2 KB');
      expect(BackupSizes.describeBytes(1024 * 1024 * 3 + 100000), '3.1 MB');
      expect(BackupSizes.describeBytes(1024 * 1024 * 24), '24 MB');
    });
  });

  test('profile details and the health record survive the round trip', () async {
    final source = memoryDatabase();
    await populate(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);

    final pet = await (restored.select(restored.pets)
          ..where((p) => p.name.equals('Mochi')))
        .getSingle();
    expect(pet.coatLength, CoatLength.long);
    expect(pet.origin, PetOrigin.rescued);
    expect(pet.originDate, DateTime.utc(2024, 7, 1));
    expect(pet.originNotes, 'Found behind the bins');
    expect(pet.dietType, DietType.mixed);
    expect(pet.foodBrand, 'Royal Canin');
    expect(pet.feedingNotes, 'Two small meals, no chicken');
    expect(pet.species, 'Cat');
    expect(pet.microchip, '981098104512345');
    expect(pet.vetName, 'Riverside Vets');
    expect(pet.vetPhone, '01234 567890');
    expect(
      (await restored.select(restored.vetVisits).get()).single.cost,
      4250,
    );

    final conditions = await restored.select(restored.petConditions).get();
    expect(conditions, hasLength(2));
    expect(
      conditions.map((c) => c.status),
      containsAll([ConditionStatus.ongoing, ConditionStatus.past]),
    );
    final allergy = (await restored.select(restored.petAllergies).get()).single;
    expect(allergy.allergen, 'Chicken');
    expect(allergy.reaction, 'Itching round the ears');

    await restored.close();
  });

  test('timestamps keep their instant and their UTC flag', () async {
    final source = memoryDatabase();
    await populate(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    final before = await source.select(source.weightEntries).get();
    await source.close();

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);
    final after = await restored.select(restored.weightEntries).get();

    after.sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
    before.sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
    for (var i = 0; i < before.length; i++) {
      expect(after[i].measuredOn, before[i].measuredOn);
      expect(after[i].measuredOn.isUtc, isTrue);
      expect(after[i].createdAt, before[i].createdAt);
    }
    await restored.close();
  });

  test('importing replaces what was there rather than merging', () async {
    final source = memoryDatabase();
    await populate(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    final target = memoryDatabase();
    await PetRepository(target).create(name: 'Someone else', now: now);
    expect(await target.select(target.pets).get(), hasLength(1));

    await serviceFor(target).importArchive(bytes);

    final names = (await target.select(target.pets).get())
        .map((pet) => pet.name)
        .toSet();
    expect(names, {'Mochi', 'Luna'});
    expect(names, isNot(contains('Someone else')));
    await target.close();
  });

  test('settings travel with the data', () async {
    final source = memoryDatabase();
    await populate(source);
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);

    expect(await SettingsRepository(restored).weightUnit(), WeightUnit.pounds);
    await restored.close();
  });

  test('an empty database exports and imports cleanly', () async {
    final source = memoryDatabase();
    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    final restored = memoryDatabase();
    final summary = await serviceFor(restored).importArchive(bytes);

    expect(summary.pets, 0);
    expect(await restored.select(restored.pets).get(), isEmpty);
    await restored.close();
  });

  test('a row whose photo has vanished still restores', () async {
    final source = memoryDatabase();
    final pets = PetRepository(source);
    final path = writePhoto('pet_photos/gone.jpg', [1, 2, 3]);
    await pets.create(name: 'Mochi', photoPath: path, now: now);
    File(path).deleteSync();

    final bytes = await serviceFor(source).exportArchive(now: now);
    await source.close();

    final restored = memoryDatabase();
    await serviceFor(restored).importArchive(bytes);

    final pet = await restored.select(restored.pets).getSingle();
    expect(pet.name, 'Mochi');
    expect(
      pet.photoPath,
      isNull,
      reason: 'the pet survives; the dangling reference does not',
    );
    await restored.close();
  });

  group('rejecting bad input', () {
    test('a zip that is not a backup', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('notes.txt', 5, [1, 2, 3, 4, 5]));
      final bytes = ZipEncoder().encodeBytes(archive);

      final db = memoryDatabase();
      await expectLater(
        serviceFor(db).importArchive(bytes),
        throwsA(isA<BackupFormatException>()),
      );
      await db.close();
    });

    test('a backup from a newer version of the app', () async {
      final source = memoryDatabase();
      await populate(source);
      final bytes = await serviceFor(source).exportArchive(now: now);
      await source.close();

      // Rewrite the manifest with a future format version.
      final archive = ZipDecoder().decodeBytes(bytes);
      final rebuilt = Archive();
      for (final file in archive.files) {
        if (file.name == 'backup.json') {
          final text = String.fromCharCodes(
            file.readBytes()!,
          ).replaceFirst('"formatVersion":1', '"formatVersion":99');
          rebuilt.addFile(
            ArchiveFile('backup.json', text.length, text.codeUnits),
          );
        } else {
          rebuilt.addFile(file);
        }
      }

      final db = memoryDatabase();
      await expectLater(
        serviceFor(
          db,
        ).importArchive(Uint8List.fromList(ZipEncoder().encodeBytes(rebuilt))),
        throwsA(isA<BackupFormatException>()),
      );
      await db.close();
    });

    test('a failed import leaves the database as it was', () async {
      final db = memoryDatabase();
      await PetRepository(db).create(name: 'Mochi', now: now);

      final archive = Archive()..addFile(ArchiveFile('notes.txt', 1, [1]));
      await expectLater(
        serviceFor(db).importArchive(ZipEncoder().encodeBytes(archive)),
        throwsA(isA<BackupFormatException>()),
      );

      expect(await db.select(db.pets).get(), hasLength(1));
      await db.close();
    });
  });
}

/// Strips the two columns holding absolute file paths, which legitimately
/// differ after a restore.
Map<String, List<Map<String, dynamic>>> _withoutPaths(
  Map<String, List<Map<String, dynamic>>> tables,
) => {
  for (final entry in tables.entries)
    entry.key: [
      for (final row in entry.value)
        {
          for (final column in row.entries)
            if (column.key != 'photoPath' &&
                column.key != 'filePath' &&
                column.key != 'imagePaths' &&
                column.key != 'path')
              column.key: column.value,
        },
    ],
};
