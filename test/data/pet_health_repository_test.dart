import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_health_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/domain/models/pet_condition.dart';
import 'package:timezone/timezone.dart' as tz;

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late PetHealthRepository health;
  late tz.TZDateTime now;
  late String petId;

  setUpAll(initializeTestTimeZone);

  setUp(() async {
    now = tz.TZDateTime(tz.local, 2026, 5, 4, 9);
    db = memoryDatabase();
    pets = PetRepository(db);
    health = PetHealthRepository(db);
    petId = (await pets.create(name: 'Mochi', now: now)).id;
  });

  tearDown(() => db.close());

  group('conditions', () {
    test('round-trip with their diagnosis date and notes', () async {
      final created = await health.addCondition(
        petId: petId,
        name: 'CKD',
        date: DateTime.utc(2026, 1, 10),
        notes: 'Stage 2, bloods every six months',
        now: now,
      );

      final loaded = (await health.watchConditions(petId).first).single;
      expect(loaded.id, created.id);
      expect(loaded.name, 'CKD');
      expect(loaded.status, ConditionStatus.ongoing);
      expect(loaded.date, DateTime.utc(2026, 1, 10));
      expect(loaded.notes, 'Stage 2, bloods every six months');
    });

    test('a name is trimmed and blank notes are stored as absent', () async {
      await health.addCondition(
        petId: petId,
        name: '  Hyperthyroidism  ',
        notes: '   ',
        now: now,
      );

      final loaded = (await health.watchConditions(petId).first).single;
      expect(loaded.name, 'Hyperthyroidism');
      expect(loaded.notes, isNull);
    });

    test('ongoing come before past, whatever their dates', () async {
      await health.addCondition(
        petId: petId,
        name: 'Cat flu',
        status: ConditionStatus.past,
        date: DateTime.utc(2026, 4, 1),
        now: now,
      );
      await health.addCondition(
        petId: petId,
        name: 'CKD',
        date: DateTime.utc(2025, 1, 1),
        now: now,
      );

      expect(
        (await health.watchConditions(petId).first).map((c) => c.name),
        ['CKD', 'Cat flu'],
        reason: 'what the cat has now matters more than what it had',
      );
    });

    test('within a status, the most recent diagnosis comes first', () async {
      for (final (name, day) in [('CKD', 1), ('Diabetes', 20), ('FIV', 10)]) {
        await health.addCondition(
          petId: petId,
          name: name,
          date: DateTime.utc(2026, 3, day),
          now: now,
        );
      }

      expect(
        (await health.watchConditions(petId).first).map((c) => c.name),
        ['Diabetes', 'FIV', 'CKD'],
      );
    });

    test('a condition with no date sorts after the ones that have one', () async {
      await health.addCondition(petId: petId, name: 'Unknown date', now: now);
      await health.addCondition(
        petId: petId,
        name: 'Dated',
        date: DateTime.utc(2020, 1, 1),
        now: now,
      );

      expect(
        (await health.watchConditions(petId).first).map((c) => c.name),
        ['Dated', 'Unknown date'],
      );
    });

    test('two undated conditions keep a stable order', () async {
      await health.addCondition(
        petId: petId,
        name: 'First',
        now: now,
      );
      await health.addCondition(
        petId: petId,
        name: 'Second',
        now: now.add(const Duration(minutes: 1)),
      );

      expect(
        (await health.watchConditions(petId).first).map((c) => c.name),
        ['Second', 'First'],
        reason: 'newest first, rather than whatever order sqlite felt like',
      );
    });

    test('a condition can be moved to the past, edited and removed', () async {
      final created = await health.addCondition(
        petId: petId,
        name: 'Cat flu',
        now: now,
      );

      await health.setConditionStatus(created.id, ConditionStatus.past);
      expect(
        (await health.watchConditions(petId).first).single.status,
        ConditionStatus.past,
      );

      await health.updateCondition(
        created.copyWith(name: 'Upper respiratory infection'),
      );
      expect(
        (await health.watchConditions(petId).first).single.name,
        'Upper respiratory infection',
      );

      await health.deleteCondition(created.id);
      expect(await health.watchConditions(petId).first, isEmpty);
    });
  });

  group('allergies', () {
    test('round-trip with their reaction', () async {
      await health.addAllergy(
        petId: petId,
        allergen: 'Chicken',
        reaction: 'Itching round the ears',
        now: now,
      );

      final loaded = (await health.watchAllergies(petId).first).single;
      expect(loaded.allergen, 'Chicken');
      expect(loaded.reaction, 'Itching round the ears');
      expect(loaded.notes, isNull);
    });

    test('a reaction nobody recorded is absent, not empty', () async {
      await health.addAllergy(
        petId: petId,
        allergen: 'Fipronil',
        reaction: '  ',
        now: now,
      );

      expect((await health.watchAllergies(petId).first).single.reaction, isNull);
    });

    test('they read back in the order they were added', () async {
      for (final name in ['Chicken', 'Fish', 'Fipronil']) {
        await health.addAllergy(
          petId: petId,
          allergen: name,
          now: now.add(Duration(minutes: name.length)),
        );
      }

      expect(
        (await health.watchAllergies(petId).first).map((a) => a.allergen),
        ['Fish', 'Chicken', 'Fipronil'],
      );
    });

    test('an allergy can be edited and removed', () async {
      final created = await health.addAllergy(
        petId: petId,
        allergen: 'Chicken',
        now: now,
      );

      await health.updateAllergy(created.copyWith(reaction: 'Vomiting'));
      expect(
        (await health.watchAllergies(petId).first).single.reaction,
        'Vomiting',
      );

      await health.deleteAllergy(created.id);
      expect(await health.watchAllergies(petId).first, isEmpty);
    });
  });

  test('one pet’s health record is not another’s', () async {
    final other = await pets.create(name: 'Luna', now: now);
    await health.addCondition(petId: other.id, name: 'FIV', now: now);
    await health.addAllergy(petId: other.id, allergen: 'Fish', now: now);

    expect(await health.watchConditions(petId).first, isEmpty);
    expect(await health.watchAllergies(petId).first, isEmpty);
    expect(await health.watchConditions(other.id).first, hasLength(1));
  });

  test('deleting a pet takes their conditions and allergies', () async {
    await health.addCondition(petId: petId, name: 'CKD', now: now);
    await health.addAllergy(petId: petId, allergen: 'Chicken', now: now);

    await pets.delete(petId);

    expect(await db.select(db.petConditions).get(), isEmpty);
    expect(await db.select(db.petAllergies).get(), isEmpty);
  });
}
