import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/prescription_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/services/photo_store.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

/// Records deletions and really removes the files.
class _RecordingPhotoStore extends PhotoStore {
  _RecordingPhotoStore() : super(picker: ImagePicker());

  final List<String> deleted = [];

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late PrescriptionRepository prescriptions;
  late _RecordingPhotoStore photos;
  late Directory scratch;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    db = memoryDatabase();
    pets = PetRepository(db);
    photos = _RecordingPhotoStore();
    prescriptions = PrescriptionRepository(db, photoStore: photos);
    scratch = Directory.systemTemp.createTempSync('paws_log_rx');
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  String writePage(String name) {
    final file = File('${scratch.path}/$name')..writeAsBytesSync([1, 2, 3]);
    return file.path;
  }

  test('a prescription round-trips with its pages in order', () async {
    final pages = [writePage('p1.jpg'), writePage('p2.jpg')];

    final created = await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: pages,
      vetName: 'Dr Okafor',
      clinic: 'Riverside Vets',
      extractedText: 'Amoxicillin 50mg twice daily for 7 days',
      now: now,
    );

    final loaded = await prescriptions.findById(created.id);
    expect(loaded!.imagePaths, pages, reason: 'page order is data');
    expect(loaded.vetName, 'Dr Okafor');
    expect(loaded.pageCount, 2);
    expect(loaded.wasRead, isTrue);
  });

  test('pages saved without extraction read as unread', () async {
    final created = await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: [writePage('p1.jpg')],
      now: now,
    );

    final loaded = await prescriptions.findById(created.id);
    expect(loaded!.wasRead, isFalse);
    expect(loaded.extractedText, isNull);
  });

  test('blank vet details are stored as absent, not as empty', () async {
    final created = await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const [],
      vetName: '  ',
      clinic: '',
      now: now,
    );

    final loaded = await prescriptions.findById(created.id);
    expect(loaded!.vetName, isNull);
    expect(loaded.clinic, isNull);
  });

  test('prescriptions read back most recent first', () async {
    for (final day in [1, 20, 10]) {
      await prescriptions.create(
        petId: petId,
        date: DateTime.utc(2026, 5, day),
        imagePaths: const [],
        notes: 'Visit $day',
        now: now,
      );
    }

    expect(
      (await prescriptions.watchForPet(petId).first).map((rx) => rx.notes),
      ['Visit 20', 'Visit 10', 'Visit 1'],
    );
  });

  test('deleting a prescription removes its page files', () async {
    final pages = [writePage('p1.jpg'), writePage('p2.jpg')];
    final created = await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: pages,
      now: now,
    );

    await prescriptions.delete(created.id);

    expect(await prescriptions.findById(created.id), isNull);
    expect(photos.deleted, unorderedEquals(pages));
    for (final path in pages) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('deleting a prescription keeps the medicines it produced', () async {
    // The cat is still on them. Losing a course because a scan was tidied
    // away would be the app destroying the owner's schedule.
    final created = await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: [writePage('p1.jpg')],
      now: now,
    );
    final medicines = MedicineRepository(db);
    final medicine = await medicines.create(
      petId: petId,
      name: 'Amoxicillin',
      now: now,
      schedule: DoseSchedule(
        timesOfDayMinutes: const [8 * 60, 20 * 60],
        startDate: DateTime.utc(2026, 5, 4),
        endDate: DateTime.utc(2026, 5, 10),
      ),
    );
    await (db.update(db.medicines)..where((m) => m.id.equals(medicine.id)))
        .write(MedicinesCompanion(prescriptionId: Value(created.id)));

    expect(await prescriptions.watchMedicines(created.id).first, hasLength(1));

    await prescriptions.delete(created.id);

    final survivor = await medicines.findById(medicine.id);
    expect(survivor, isNotNull);
    expect(survivor!.name, 'Amoxicillin');
    expect(await db.select(db.doseLogs).get(), isNotEmpty);
  });

  test('deleting the pet does take its prescriptions', () async {
    await prescriptions.create(
      petId: petId,
      date: DateTime.utc(2026, 5, 4),
      imagePaths: const [],
      now: now,
    );

    await pets.delete(petId);

    expect(await db.select(db.prescriptions).get(), isEmpty);
  });
}
