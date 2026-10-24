import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_photo_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/services/photo_store.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late String petId;
  late Directory scratch;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    petId = (await PetRepository(db).create(name: 'Mochi')).id;
    scratch = Directory.systemTemp.createTempSync('paws_log_photos');
  });

  tearDown(() {
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

  Future<void> openPet(
    WidgetTester tester, {
    String? taken,
    List<String> picked = const [],
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          photoStoreProvider.overrideWithValue(
            FixedPhotoStore(taken: taken, picked: picked),
          ),
        ],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
  }

  Future<void> openAlbum(WidgetTester tester) =>
      scrollAndTap(tester, find.text('Photos'));

  testWidgets('the profile offers an empty album', (tester) async {
    await openPet(tester);

    await scrollIntoView(tester, find.text('Photos'));
    expect(find.textContaining('add the first one'), findsOneWidget);

    await openAlbum(tester);
    expect(find.textContaining('No photos yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the profile counts the album', (tester) async {
    final album = PetPhotoRepository(db);
    await album.add(petId: petId, path: writeImage('a.jpg'));
    await album.add(petId: petId, path: writeImage('b.jpg'));

    await openPet(tester);

    await scrollIntoView(tester, find.text('2 photos'));
    expect(find.text('2 photos'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('one photo is not "1 photos"', (tester) async {
    await PetPhotoRepository(db).add(petId: petId, path: writeImage('a.jpg'));

    await openPet(tester);

    await scrollIntoView(tester, find.text('1 photo'));
    expect(find.text('1 photo'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('photos chosen from the library land in the album', (
    tester,
  ) async {
    await openPet(
      tester,
      picked: [writeImage('a.jpg'), writeImage('b.jpg')],
    );
    await openAlbum(tester);

    await tapAndSettle(tester, find.byTooltip('Add a photo'));
    await tapAndSettle(tester, find.text('Choose from Photos'));

    expect(await db.select(db.petPhotos).get(), hasLength(2));
    expect(find.textContaining('No photos yet'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('a photo taken with the camera lands in the album', (
    tester,
  ) async {
    await openPet(tester, taken: writeImage('a.jpg'));
    await openAlbum(tester);

    await tapAndSettle(tester, find.byTooltip('Add a photo'));
    await tapAndSettle(tester, find.text('Take a photo'));

    expect(await db.select(db.petPhotos).get(), hasLength(1));

    await disposeTree(tester);
  });

  testWidgets('backing out of the camera adds nothing', (tester) async {
    await openPet(tester);
    await openAlbum(tester);

    await tapAndSettle(tester, find.byTooltip('Add a photo'));
    await tapAndSettle(tester, find.text('Take a photo'));

    expect(await db.select(db.petPhotos).get(), isEmpty);
    expect(find.textContaining('No photos yet'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a photo opens full screen and swipes to the next', (
    tester,
  ) async {
    final album = PetPhotoRepository(db);
    await album.add(
      petId: petId,
      path: writeImage('a.jpg'),
      takenAt: DateTime.utc(2026, 5, 20),
      caption: 'Asleep in the sink',
    );
    await album.add(
      petId: petId,
      path: writeImage('b.jpg'),
      takenAt: DateTime.utc(2026, 5, 1),
      caption: 'On the windowsill',
    );

    await openPet(tester);
    await openAlbum(tester);

    await tapAndSettle(tester, find.byType(Image).first);

    expect(find.text('Photo 1 of 2'), findsOneWidget);
    expect(find.text('Asleep in the sink'), findsOneWidget);
    expect(find.text('May 20, 2026'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await settle(tester);

    expect(find.text('Photo 2 of 2'), findsOneWidget);
    expect(
      find.text('On the windowsill'),
      findsOneWidget,
      reason: 'the album reads newest first, so May 1 comes second',
    );

    await disposeTree(tester);
  });

  testWidgets('a photo with no caption still shows its date', (tester) async {
    await PetPhotoRepository(db).add(
      petId: petId,
      path: writeImage('a.jpg'),
      takenAt: DateTime.utc(2026, 5, 20),
    );

    await openPet(tester);
    await openAlbum(tester);
    await tapAndSettle(tester, find.byType(Image).first);

    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('May 20, 2026'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('one pet’s album is not another’s', (tester) async {
    final other = await PetRepository(db).create(name: 'Luna');
    await PetPhotoRepository(db).add(
      petId: other.id,
      path: writeImage('a.jpg'),
      caption: 'Luna only',
    );

    await openPet(tester);
    await openAlbum(tester);

    expect(find.textContaining('No photos yet'), findsOneWidget);
    expect(find.text('Luna only'), findsNothing);

    await disposeTree(tester);
  });
}
