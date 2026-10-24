import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_photo_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/prescription_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/services/photo_store.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

/// Records deletions, and really removes the files.
class _RecordingPhotoStore extends FixedPhotoStore {
  _RecordingPhotoStore(Directory root) : super(root: root);

  final List<String> deleted = [];

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    await super.delete(path);
  }
}

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late PetPhotoRepository album;
  late _RecordingPhotoStore photos;
  late Directory scratch;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    db = memoryDatabase();
    scratch = Directory.systemTemp.createTempSync('paws_log_vault');
    photos = _RecordingPhotoStore(scratch);
    pets = PetRepository(db, photoStore: photos);
    album = PetPhotoRepository(db, photoStore: photos);
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  String writeImage(String name) {
    final file = File('${scratch.path}/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    return file.path;
  }

  test('an album reads back newest first, by when the photo was taken', () async {
    for (final (day, name) in [(1, 'a.jpg'), (20, 'b.jpg'), (10, 'c.jpg')]) {
      await album.add(
        petId: petId,
        path: writeImage(name),
        takenAt: DateTime.utc(2026, 5, day),
        caption: 'Day $day',
        now: now,
      );
    }

    final loaded = await album.watchForPet(petId).first;
    expect(loaded.map((photo) => photo.caption), [
      'Day 20',
      'Day 10',
      'Day 1',
    ], reason: 'an album of a cat reads by when things happened');
  });

  test('a photo with no takenAt falls back to when it was added', () async {
    final photo = await album.add(
      petId: petId,
      path: writeImage('a.jpg'),
      now: now,
    );

    expect(photo.takenAt, now.toUtc());
    expect(photo.takenAt.isUtc, isTrue);
  });

  test('a blank caption is stored as absent, not as empty', () async {
    final photo = await album.add(
      petId: petId,
      path: writeImage('a.jpg'),
      caption: '   ',
      now: now,
    );

    expect((await album.findById(photo.id))!.caption, isNull);
    expect(photo.hasCaption, isFalse);
  });

  test('a caption can be written, changed and cleared', () async {
    final photo = await album.add(
      petId: petId,
      path: writeImage('a.jpg'),
      caption: 'In the sink',
      now: now,
    );

    await album.setCaption(photo.id, '  Asleep in the sink  ');
    expect((await album.findById(photo.id))!.caption, 'Asleep in the sink');

    await album.setCaption(photo.id, '');
    expect((await album.findById(photo.id))!.caption, isNull);
  });

  test('deleting a photo removes its file', () async {
    final path = writeImage('a.jpg');
    final photo = await album.add(petId: petId, path: path, now: now);

    await album.delete(photo.id);

    expect(await album.findById(photo.id), isNull);
    expect(photos.deleted, [path]);
    expect(File(path).existsSync(), isFalse);
  });

  test('photos are counted per pet', () async {
    final other = await pets.create(name: 'Luna', now: now);
    await album.add(petId: petId, path: writeImage('a.jpg'), now: now);
    await album.add(petId: petId, path: writeImage('b.jpg'), now: now);
    await album.add(petId: other.id, path: writeImage('c.jpg'), now: now);

    expect(await album.countForPet(petId), 2);
    expect(await album.countForPet(other.id), 1);
  });

  test('one pet’s album is not another’s', () async {
    final other = await pets.create(name: 'Luna', now: now);
    await album.add(petId: other.id, path: writeImage('c.jpg'), now: now);

    expect(await album.watchForPet(petId).first, isEmpty);
  });

  group('deleting a pet', () {
    test('takes every file they owned, not just their rows', () async {
      // Before this, a deleted cat left their whole album on disk, and an
      // owner deleting a pet to reclaim space reclaimed none of it.
      final portrait = writeImage('pet_photos/mochi.jpg');
      final vaultOne = writeImage('vault/one.jpg');
      final vaultTwo = writeImage('vault/two.jpg');
      final page = writeImage('rx/page.jpg');
      final xray = writeImage('visits/xray.jpg');

      final pet = await pets.findById(petId);
      await pets.update(pet!.copyWith(photoPath: portrait), now: now);
      await album.add(petId: petId, path: vaultOne, now: now);
      await album.add(petId: petId, path: vaultTwo, now: now);
      await PrescriptionRepository(db, photoStore: photos).create(
        petId: petId,
        date: DateTime.utc(2026, 5, 4),
        imagePaths: [page],
        now: now,
      );
      await VetVisitRepository(db).create(
        petId: petId,
        visitedOn: DateTime.utc(2026, 5, 4),
        reason: 'Limping',
        attachmentPaths: [xray],
        now: now,
      );

      await pets.delete(petId);

      for (final path in [portrait, vaultOne, vaultTwo, page, xray]) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(await db.select(db.petPhotos).get(), isEmpty);
      expect(await db.select(db.prescriptions).get(), isEmpty);
      expect(await db.select(db.visitAttachments).get(), isEmpty);
    });

    test('leaves another pet’s files alone', () async {
      final other = await pets.create(name: 'Luna', now: now);
      final mine = writeImage('vault/mine.jpg');
      final theirs = writeImage('vault/theirs.jpg');
      await album.add(petId: petId, path: mine, now: now);
      await album.add(petId: other.id, path: theirs, now: now);

      await pets.delete(petId);

      expect(File(mine).existsSync(), isFalse);
      expect(File(theirs).existsSync(), isTrue);
      expect(await album.countForPet(other.id), 1);
    });

    test('archiving keeps the album and its files', () async {
      final path = writeImage('vault/one.jpg');
      await album.add(petId: petId, path: path, now: now);

      await pets.archive(petId, now: now);

      expect(File(path).existsSync(), isTrue);
      expect(await album.countForPet(petId), 1);
      expect(photos.deleted, isEmpty);
    });
  });

  group('promoting a photo to the portrait', () {
    test('copies the file rather than sharing its path', () async {
      final source = writeImage('vault/one.jpg');
      await album.add(petId: petId, path: source, now: now);

      await pets.setPortrait(petId, sourcePath: source, now: now);

      final portrait = (await pets.findById(petId))!.photoPath;
      expect(portrait, isNotNull);
      expect(portrait, isNot(source));
      expect(File(portrait!).existsSync(), isTrue);
      expect(File(portrait).readAsBytesSync(), File(source).readAsBytesSync());
      expect(
        File(source).existsSync(),
        isTrue,
        reason: 'the album keeps its own copy',
      );
    });

    test('so deleting the album photo leaves the portrait standing', () async {
      final source = writeImage('vault/one.jpg');
      final photo = await album.add(petId: petId, path: source, now: now);
      await pets.setPortrait(petId, sourcePath: source, now: now);
      final portrait = (await pets.findById(petId))!.photoPath!;

      await album.delete(photo.id);

      expect(File(portrait).existsSync(), isTrue);
      expect((await pets.findById(petId))!.photoPath, portrait);
    });

    test('replacing the portrait deletes the one it replaced', () async {
      final first = writeImage('vault/one.jpg');
      final second = writeImage('vault/two.jpg');
      await pets.setPortrait(petId, sourcePath: first, now: now);
      final before = (await pets.findById(petId))!.photoPath!;

      await pets.setPortrait(petId, sourcePath: second, now: now);

      final after = (await pets.findById(petId))!.photoPath!;
      expect(after, isNot(before));
      expect(File(after).existsSync(), isTrue);
      expect(
        File(before).existsSync(),
        isFalse,
        reason: 'changing your mind should not accumulate files',
      );
    });

    test('a pet that is gone is left alone', () async {
      final source = writeImage('vault/one.jpg');
      await pets.delete(petId);

      await pets.setPortrait(petId, sourcePath: source, now: now);

      expect(await pets.findById(petId), isNull);
    });
  });
}
