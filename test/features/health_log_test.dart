import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/app.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/providers.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/data/repositories/vet_visit_repository.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';

import '../helpers/harness.dart';

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late VetVisitRepository visits;
  late String petId;

  setUpAll(initializeTestTimeZone);

  // The database is deliberately not closed; see test/helpers/harness.dart.
  setUp(() async {
    db = memoryDatabase();
    pets = PetRepository(db);
    visits = VetVisitRepository(db);
    petId = (await pets.create(name: 'Mochi')).id;
  });

  Future<void> openPet(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const PawsLogApp(),
      ),
    );
    await settle(tester);
    await tapAndSettle(tester, find.text('Pets'));
    await tapAndSettle(tester, find.text('Mochi'));
  }

  testWidgets('an empty profile explains each section', (tester) async {
    await openPet(tester);

    expect(find.text('Medicines'), findsOneWidget);
    expect(find.text('Vaccinations'), findsOneWidget);
    expect(find.text('Vet visits'), findsOneWidget);
    expect(find.textContaining('No visits yet'), findsOneWidget);
    expect(
      find.textContaining('Marking a vaccine reminder done'),
      findsOneWidget,
    );

    await disposeTree(tester);
  });

  testWidgets('a visit can be recorded and reopened', (tester) async {
    await openPet(tester);

    await tapAndSettle(tester, find.byTooltip('Add a vet visit'));

    await tester.enterText(
      find.widgetWithText(TextField, 'What was it for'),
      'Limping on back left leg',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Clinic'),
      'Riverside Vets',
    );
    await tapAndSettle(tester, find.text('Add visit'));

    expect(find.text('Limping on back left leg'), findsOneWidget);
    expect(find.textContaining('Riverside Vets'), findsOneWidget);

    final saved = (await db.select(db.vetVisits).get()).single;
    expect(saved.reason, 'Limping on back left leg');
    expect(saved.petId, petId);

    // And it reopens for editing.
    await tapAndSettle(tester, find.text('Limping on back left leg'));
    expect(find.text('Visit'), findsOneWidget);
    expect(find.textContaining('No photos attached'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('a reason is required', (tester) async {
    await openPet(tester);
    await tapAndSettle(tester, find.byTooltip('Add a vet visit'));

    await tapAndSettle(tester, find.text('Add visit'));

    expect(find.text('A reason is needed'), findsOneWidget);
    expect(await db.select(db.vetVisits).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('a visit can be deleted from its own screen', (tester) async {
    await visits.create(
      petId: petId,
      visitedOn: DateTime.utc(2026, 5, 4),
      reason: 'Annual checkup',
    );
    await openPet(tester);
    expect(find.text('Annual checkup'), findsOneWidget);

    await tapAndSettle(tester, find.text('Annual checkup'));
    await tapAndSettle(tester, find.byTooltip('Delete visit'));

    expect(find.text('Annual checkup'), findsNothing);
    expect(await db.select(db.vetVisits).get(), isEmpty);

    await disposeTree(tester);
  });

  testWidgets('a completed vaccine turns up in the profile', (tester) async {
    final reminders = ReminderRepository(db);
    final events = ReminderEventRepository(db);
    await reminders.create(
      petId: petId,
      title: 'Yearly vaccine',
      category: ReminderCategory.vaccine,
      repeat: const RepeatRule.years(1),
      anchorDate: DateTime.utc(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      ),
      timeOfDayMinutes: 9 * 60,
    );
    final event = (await db.select(db.reminderEvents).getSingle()).id;
    await events.markDone(event);

    await openPet(tester);

    expect(find.text('Yearly vaccine'), findsOneWidget);
    expect(find.textContaining('Given'), findsOneWidget);
    expect(find.textContaining('next'), findsOneWidget);

    await disposeTree(tester);
  });
}
