import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/core/constants.dart';
import 'package:paws_log/data/db/app_database.dart';
import 'package:paws_log/data/repositories/pet_repository.dart';
import 'package:paws_log/data/repositories/reminder_event_repository.dart';
import 'package:paws_log/data/repositories/reminder_repository.dart';
import 'package:paws_log/domain/models/reminder.dart';
import 'package:paws_log/domain/repeat_rule.dart';
import 'package:paws_log/services/notifications/notification_actions.dart';
import 'package:paws_log/services/notifications/notification_gateway.dart';
import 'package:paws_log/services/notifications/notification_ids.dart';
import 'package:paws_log/services/notifications/notification_scheduler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late AppDatabase db;
  late PetRepository pets;
  late ReminderRepository reminders;
  late ReminderEventRepository events;
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
    events = ReminderEventRepository(db);
    scheduler = NotificationScheduler(
      gateway: gateway,
      events: events,
      clock: () => now,
    );
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
    final scheduledIds = gateway.scheduled.map((e) => e.eventId).toSet();
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
    final first = gateway.scheduled.map((e) => (e.id, e.eventId)).toList();

    await scheduler.syncAll();
    final second = gateway.scheduled.map((e) => (e.id, e.eventId)).toList();

    expect(second, equals(first));
    for (final entry in gateway.scheduled) {
      expect(entry.id, notificationIdFor(entry.eventId));
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
      target.eventId,
      until: now.add(const Duration(days: 10)),
    );
    await scheduler.syncAll();

    expect(gateway.scheduled, hasLength(3), reason: 'nothing was evicted');
    final moved = gateway.scheduled
        .firstWhere((entry) => entry.eventId == target.eventId);
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
    expect(gateway.scheduled.single.eventId, isNot(pending.id));
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
    NotificationResponse response(String eventId, String actionId) =>
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: notificationIdFor(eventId),
          actionId: actionId,
          payload: eventId,
        );

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

      await applyNotificationAction(
        events,
        response(eventId, NotificationActions.done),
        now: now,
      );

      final all = await db.select(db.reminderEvents).get();
      expect(all, hasLength(2));
      expect((await events.findById(eventId))!.status.name, 'done');
    });

    test('Snooze 1 hour keeps it pending and moves when it fires', () async {
      final eventId = await seedOne();

      await applyNotificationAction(
        events,
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

      await applyNotificationAction(
        events,
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

      await applyNotificationAction(
        events,
        NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: eventId,
        ),
      );

      expect((await events.findById(eventId))!.isPending, isTrue);
      expect(await db.select(db.reminderEvents).get(), hasLength(1));
    });

    test('an action without a payload is ignored', () async {
      await seedOne();

      await applyNotificationAction(
        events,
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: NotificationActions.done,
        ),
      );

      expect(await db.select(db.reminderEvents).get(), hasLength(1));
    });
  });
}
