import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/services/photo_store.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

/// Records which files were asked to be deleted, and really deletes them.
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
  late VetVisitRepository visits;
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
    visits = VetVisitRepository(db, photoStore: photos);
    scratch = Directory.systemTemp.createTempSync('paws_log_visits');
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  /// A stand-in for a photo the picker copied into the documents directory.
  String writeFile(String name) {
    final file = File('${scratch.path}/$name')
      ..writeAsBytesSync([1, 2, 3, 4]);
    return file.path;
  }

  Future<String> addVisit({List<String> attachments = const []}) async {
    final visit = await visits.create(
      petId: petId,
      visitedOn: DateTime.utc(2026, 5, 4),
      reason: 'Limping on back left leg',
      clinic: 'Riverside Vets',
      vetName: 'Dr Okafor',
      notes: 'Rest for a week.',
      attachmentPaths: attachments,
      now: now,
    );
    return visit.id;
  }

  test('a visit round-trips', () async {
    final id = await addVisit();
    final loaded = await visits.findById(id);

    expect(loaded!.reason, 'Limping on back left leg');
    expect(loaded.clinic, 'Riverside Vets');
    expect(loaded.vetName, 'Dr Okafor');
    expect(loaded.notes, 'Rest for a week.');
    expect(loaded.visitedOn, DateTime.utc(2026, 5, 4));
  });

  test('blank optional fields are stored as absent, not as empty', () async {
    final visit = await visits.create(
      petId: petId,
      visitedOn: DateTime.utc(2026, 5, 4),
      reason: 'Checkup',
      clinic: '   ',
      vetName: '',
      now: now,
    );

    final loaded = await visits.findById(visit.id);
    expect(loaded!.clinic, isNull);
    expect(loaded.vetName, isNull);
  });

  test('visits read back most recent first', () async {
    for (final day in [1, 20, 10]) {
      await visits.create(
        petId: petId,
        visitedOn: DateTime.utc(2026, 5, day),
        reason: 'Visit $day',
        now: now,
      );
    }

    expect(
      (await visits.watchForPet(petId).first).map((v) => v.reason),
      ['Visit 20', 'Visit 10', 'Visit 1'],
    );
  });

  test('photos can be attached when the visit is created', () async {
    final id = await addVisit(
      attachments: [writeFile('a.jpg'), writeFile('b.jpg')],
    );

    final attachments = await visits.watchAttachments(id).first;
    expect(attachments, hasLength(2));
    expect(attachments.first.visitId, id);
    expect(File(attachments.first.filePath).existsSync(), isTrue);
  });

  test('photos can be attached later, with a caption', () async {
    final id = await addVisit();

    await visits.addAttachment(
      id,
      writeFile('lab.jpg'),
      caption: 'Blood panel',
      now: now,
    );

    final attachment = (await visits.watchAttachments(id).first).single;
    expect(attachment.caption, 'Blood panel');
  });

  test('deleting an attachment removes its file too', () async {
    final id = await addVisit(attachments: [writeFile('a.jpg')]);
    final attachment = (await visits.watchAttachments(id).first).single;

    await visits.deleteAttachment(attachment.id);

    expect(await visits.watchAttachments(id).first, isEmpty);
    expect(photos.deleted, [attachment.filePath]);
    expect(File(attachment.filePath).existsSync(), isFalse);
  });

  test('deleting a visit takes its attachments and their files', () async {
    final paths = [writeFile('a.jpg'), writeFile('b.jpg')];
    final id = await addVisit(attachments: paths);

    await visits.delete(id);

    expect(await visits.findById(id), isNull);
    expect(await db.select(db.visitAttachments).get(), isEmpty);
    expect(photos.deleted, unorderedEquals(paths));
    for (final path in paths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('deleting a pet cascades to visits and attachments', () async {
    await addVisit(attachments: [writeFile('a.jpg')]);

    await pets.delete(petId);

    expect(await db.select(db.vetVisits).get(), isEmpty);
    expect(await db.select(db.visitAttachments).get(), isEmpty);
  });

  test('a visit can be edited', () async {
    final id = await addVisit();
    final visit = await visits.findById(id);

    await visits.update(
      visit!.copyWith(reason: 'Follow-up', notes: 'All clear'),
      now: now.add(const Duration(days: 1)),
    );

    final updated = await visits.findById(id);
    expect(updated!.reason, 'Follow-up');
    expect(updated.notes, 'All clear');
    expect(updated.updatedAt.isAfter(visit.updatedAt), isTrue);
  });

  test('deleting an attachment that is already gone is harmless', () async {
    await visits.deleteAttachment('no-such-attachment');
    expect(photos.deleted, isEmpty);
  });
}
