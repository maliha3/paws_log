import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/dose_log_repository.dart';
import 'package:paws_log/data/repositories/medicine_repository.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/medicine.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/services/notifications/notification_actions.dart';
import 'package:paws_log/services/notifications/notification_gateway.dart';
import 'package:paws_log/services/notifications/notification_ids.dart';
import 'package:paws_log/services/notifications/notification_payload.dart';
import 'package:paws_log/services/notifications/notification_scheduler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late ReminderRepository reminders;
  late ReminderEventRepository events;
  late DoseLogRepository doses;
  late MedicineRepository medicines;
  late RecordingNotificationGateway gateway;
  late NotificationScheduler scheduler;
  late DateTime now;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));
  });

  setUp(() {
    now = tz.TZDateTime(tz.local, 2026, 3, 15, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pets = PetRepository(db);
    gateway = RecordingNotificationGateway();
    // Wired exactly as the app wires it: the scheduler reads through its own
    // repositories with no sync hook, because the writing ones depend on it.
    scheduler = NotificationScheduler(
      gateway: gateway,
      events: ReminderEventRepository(db),
      doses: DoseLogRepository(db),
      clock: () => now,
    );
    events = ReminderEventRepository(db, scheduleSync: scheduler);
    doses = DoseLogRepository(db, scheduleSync: scheduler);
    medicines = MedicineRepository(db, scheduleSync: scheduler);
    // The writing repository resyncs through the scheduler, exactly as the
    // app wires it.
    reminders = ReminderRepository(db, scheduleSync: scheduler);
  });

  tearDown(() => db.close());

  DateTime dateUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  Future<String> addPet([String name = 'Mochi']) async =>
      (await pets.create(name: name, now: now)).id;

  /// Creates [count] one-off reminders, one per day starting tomorrow.
  Future<void> seedDailyOneOffs(String petId, int count) async {
    for (var day = 1; day <= count; day++) {
      await reminders.create(
        petId: petId,
        title: 'Reminder $day',
        category: ReminderCategory.other,
        repeat: const RepeatRule.once(),
        anchorDate: dateUtc(now.add(Duration(days: day))),
        timeOfDayMinutes: 9 * 60,
        now: now,
      );
    }
  }

  test('the window never exceeds the budget', () async {
    final petId = await addPet();
    await seedDailyOneOffs(petId, 200);

    await scheduler.syncAll();

    expect(gateway.scheduled, hasLength(AppConstants.scheduledNotificationBudget));
    expect(AppConstants.scheduledNotificationBudget, 56);
    expect(
      gateway.scheduled.length +
          AppConstants.snoozeNotificationReserve,
      AppConstants.iosPendingNotificationLimit,
      reason: 'the reserve keeps the total inside the iOS cap of 64',
    );
  });

  test('the window holds the earliest occurrences, in order', () async {
    final petId = await addPet();
    await seedDailyOneOffs(petId, 100);

    await scheduler.syncAll();

    final times = gateway.scheduled.map((entry) => entry.when).toList();
    expect(times, equals(List.of(times)..sort()), reason: 'earliest first');

    // Day 1 is in, day 57 is past the budget and so is not.
    final all = await db.select(db.reminderEvents).get();
    final scheduledIds = gateway.scheduled
        .map((e) => NotificationKind.decode(e.payload)!.id)
        .toSet();
    final byDay = {
      for (final event in all) event.scheduledFor: event.id,
    };
    final ordered = byDay.keys.toList()..sort();
    expect(scheduledIds, contains(byDay[ordered.first]));
    expect(scheduledIds, contains(byDay[ordered[55]]));
    expect(scheduledIds, isNot(contains(byDay[ordered[56]])));
  });

  test('occurrences already past are not scheduled', () async {
    final petId = await addPet();
    await reminders.create(
      petId: petId,
      title: 'Overdue',
      category: ReminderCategory.other,
      repeat: const RepeatRule.once(),
      anchorDate: dateUtc(now.subtract(const Duration(days: 30))),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    await reminders.create(
      petId: petId,
      title: 'Coming up',
      category: ReminderCategory.other,
      repeat: const RepeatRule.once(),
      anchorDate: dateUtc(now.add(const Duration(days: 3))),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    await scheduler.syncAll();

    expect(gateway.scheduled, hasLength(1));
  });

  test('ids are derived from the event, so a resync is idempotent', () async {
    final petId = await addPet();
    await seedDailyOneOffs(petId, 3);

    await scheduler.syncAll();
    final first = gateway.scheduled.map((e) => (e.id, e.payload)).toList();

    await scheduler.syncAll();
    final second = gateway.scheduled.map((e) => (e.id, e.payload)).toList();

    expect(second, equals(first));
    for (final entry in gateway.scheduled) {
      expect(entry.id, notificationIdFor(entry.payload));
      expect(entry.id, greaterThanOrEqualTo(0));
    }
  });

  test('a write rebuilds the window on its own', () async {
    final petId = await addPet();
    expect(gateway.scheduled, isEmpty);

    // No explicit syncAll: creating the reminder has to trigger it.
    await reminders.create(
      petId: petId,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateUtc(now.add(const Duration(days: 2))),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.cancelAllCount, greaterThan(0));
  });

  test('a snooze moves the notification without evicting anything', () async {
    final petId = await addPet();
    await seedDailyOneOffs(petId, 3);
    await scheduler.syncAll();
    expect(gateway.scheduled, hasLength(3));

    final target = gateway.scheduled.first;
    await events.snooze(
      NotificationKind.decode(target.payload)!.id,
      until: now.add(const Duration(days: 10)),
    );
    await scheduler.syncAll();

    expect(gateway.scheduled, hasLength(3), reason: 'nothing was evicted');
    final moved = gateway.scheduled
        .firstWhere((entry) => entry.payload == target.payload);
    expect(moved.when.isAfter(target.when), isTrue);
    expect(moved.id, target.id, reason: 'same occurrence, same id');
  });

  test('completing an occurrence schedules the next one instead', () async {
    final petId = await addPet();
    await reminders.create(
      petId: petId,
      title: 'Deworming',
      category: ReminderCategory.deworming,
      repeat: const RepeatRule.months(3),
      anchorDate: dateUtc(now),
      timeOfDayMinutes: 9 * 60,
      now: now,
    );
    final pending = await db.select(db.reminderEvents).getSingle();

    await events.markDone(pending.id, now: now);
    await scheduler.syncAll();

    expect(gateway.scheduled, hasLength(1));
    expect(
      NotificationKind.decode(gateway.scheduled.single.payload)!.id,
      isNot(pending.id),
    );
    expect(tz.TZDateTime.from(gateway.scheduled.single.when, tz.local).month, 6);
  });

  test('overlapping syncs coalesce into one more run', () async {
    final petId = await addPet();
    await seedDailyOneOffs(petId, 2);

    await Future.wait([
      scheduler.syncAll(),
      scheduler.syncAll(),
      scheduler.syncAll(),
    ]);

    expect(gateway.scheduled, hasLength(2), reason: 'no duplicates');
  });

  group('actions', () {
    NotificationResponse response(
      String id,
      String actionId, {
      NotificationKind kind = NotificationKind.reminder,
    }) {
      final payload = kind.payloadFor(id);
      return NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: notificationIdFor(payload),
        actionId: actionId,
        payload: payload,
      );
    }

    NotificationActionHandler handler() =>
        NotificationActionHandler(events: events, doses: doses);

    Future<String> seedOne() async {
      final petId = await addPet();
      await reminders.create(
        petId: petId,
        title: 'Deworming',
        category: ReminderCategory.deworming,
        repeat: const RepeatRule.months(3),
        anchorDate: dateUtc(now),
        timeOfDayMinutes: 9 * 60,
        now: now,
      );
      return (await db.select(db.reminderEvents).getSingle()).id;
    }

    test('Done closes the occurrence and opens the next', () async {
      final eventId = await seedOne();

      await handler().apply(
        response(eventId, NotificationActions.done),
        now: now,
      );

      final all = await db.select(db.reminderEvents).get();
      expect(all, hasLength(2));
      expect((await events.findById(eventId))!.status.name, 'done');
    });

    test('Snooze 1 hour keeps it pending and moves when it fires', () async {
      final eventId = await seedOne();

      await handler().apply(
        response(eventId, NotificationActions.snoozeHour),
        now: now,
      );

      final event = await events.findById(eventId);
      expect(event!.isPending, isTrue);
      expect(event.snoozedUntil, isNotNull);
      expect(
        event.notifyAt.difference(event.scheduledFor).inMinutes,
        closeTo(60, 2),
      );
    });

    test('Snooze to tomorrow uses the reminder\'s own time of day', () async {
      final eventId = await seedOne();

      await handler().apply(
        response(eventId, NotificationActions.snoozeTomorrow),
        now: now,
      );

      final event = await events.findById(eventId);
      final fires = tz.TZDateTime.from(event!.notifyAt, tz.local);
      expect(event.isPending, isTrue);
      expect(fires.day, 16);
      expect(fires.hour, 9);
    });

    test('a plain tap changes nothing', () async {
      final eventId = await seedOne();

      await handler().apply(NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: eventId,
        ));

      expect((await events.findById(eventId))!.isPending, isTrue);
      expect(await db.select(db.reminderEvents).get(), hasLength(1));
    });

    test('an action without a payload is ignored', () async {
      await seedOne();

      await handler().apply(NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.done,
        ));

      expect(await db.select(db.reminderEvents).get(), hasLength(1));
    });
  });

  group('medicines share the window', () {
    Future<String> addCourse({
      required List<int> times,
      int days = 30,
    }) async {
      final petId = await addPet('Luna');
      final medicine = await medicines.create(
        petId: petId,
        name: 'Amoxicillin',
        dosage: '1 tablet',
        now: now,
        schedule: DoseSchedule(
          timesOfDayMinutes: times,
          startDate: dateUtc(now),
          endDate: dateUtc(now.add(Duration(days: days))),
        ),
      );
      return medicine.id;
    }

    test('a dose is scheduled with its own kind and payload', () async {
      await addCourse(times: [20 * 60], days: 0);
      await scheduler.syncAll();

      final entry = gateway.scheduled.single;
      expect(entry.kind, NotificationKind.dose);
      expect(entry.title, 'Amoxicillin');

      final decoded = NotificationKind.decode(entry.payload)!;
      expect(decoded.kind, NotificationKind.dose);
      expect(await doses.findById(decoded.id), isNotNull);
    });

    test('doses and reminders merge into one time-ordered window', () async {
      final petId = await addPet();
      await reminders.create(
        petId: petId,
        title: 'Deworming',
        category: ReminderCategory.deworming,
        repeat: const RepeatRule.months(3),
        anchorDate: dateUtc(now.add(const Duration(days: 1))),
        timeOfDayMinutes: 9 * 60,
        now: now,
      );
      await addCourse(times: [20 * 60], days: 2);

      await scheduler.syncAll();

      final times = gateway.scheduled.map((e) => e.when).toList();
      expect(times, equals(List.of(times)..sort()));
      expect(
        gateway.scheduled.map((e) => e.kind),
        containsAll([NotificationKind.dose, NotificationKind.reminder]),
      );
    });

    test('a twice-daily course cannot crowd out the yearly vaccine', () async {
      final petId = await addPet();
      // A vaccine a long way off — by time order alone it would never be
      // scheduled once a medicine is running.
      await reminders.create(
        petId: petId,
        title: 'Yearly vaccine',
        category: ReminderCategory.vaccine,
        repeat: const RepeatRule.years(1),
        anchorDate: dateUtc(now.add(const Duration(days: 300))),
        timeOfDayMinutes: 9 * 60,
        now: now,
      );
      await addCourse(times: [8 * 60, 20 * 60], days: 60);

      await scheduler.syncAll();

      expect(gateway.scheduled, hasLength(56));
      final kinds = gateway.scheduled.map((e) => e.kind).toList();
      expect(
        kinds.where((kind) => kind == NotificationKind.reminder),
        hasLength(1),
        reason: 'the only reminder there is keeps its slot',
      );
      expect(
        gateway.scheduled.firstWhere((e) => e.kind == NotificationKind.reminder)
            .title,
        'Yearly vaccine',
      );
    });

    test('logging a dose rebuilds the window without it', () async {
      await addCourse(times: [20 * 60], days: 2);
      await scheduler.syncAll();
      final before = gateway.scheduled.length;

      final next = gateway.scheduled.first;
      await doses.logTaken(
        NotificationKind.decode(next.payload)!.id,
        now: now,
      );

      expect(gateway.scheduled, hasLength(before - 1));
      expect(
        gateway.scheduled.map((e) => e.payload),
        isNot(contains(next.payload)),
      );
    });

    test('a dose action logs it taken', () async {
      await addCourse(times: [20 * 60], days: 2);
      await scheduler.syncAll();
      final doseId = NotificationKind.decode(
        gateway.scheduled.first.payload,
      )!.id;

      await NotificationActionHandler(events: events, doses: doses).apply(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.taken,
          payload: NotificationKind.dose.payloadFor(doseId),
        ),
        now: now,
      );

      expect((await doses.findById(doseId))!.status.name, 'taken');
    });

    test('a dose action can skip it', () async {
      await addCourse(times: [20 * 60], days: 2);
      await scheduler.syncAll();
      final doseId = NotificationKind.decode(
        gateway.scheduled.first.payload,
      )!.id;

      await NotificationActionHandler(events: events, doses: doses).apply(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.skip,
          payload: NotificationKind.dose.payloadFor(doseId),
        ),
        now: now,
      );

      expect((await doses.findById(doseId))!.status.name, 'skipped');
    });

    test('a reminder action aimed at a dose does nothing', () async {
      await addCourse(times: [20 * 60], days: 2);
      await scheduler.syncAll();
      final doseId = NotificationKind.decode(
        gateway.scheduled.first.payload,
      )!.id;

      await NotificationActionHandler(events: events, doses: doses).apply(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.snoozeTomorrow,
          payload: NotificationKind.dose.payloadFor(doseId),
        ),
        now: now,
      );

      expect((await doses.findById(doseId))!.status.name, 'pending');
    });
  });
}
