import 'package:flutter_test/flutter_test.dart';
import 'package:paws_log/services/notifications/notification_payload.dart';
import 'package:paws_log/services/notifications/notification_window.dart';

void main() {
  final epoch = DateTime.utc(2026, 5, 4, 9);

  PendingNotification item(NotificationKind kind, int minutesFromEpoch) =>
      PendingNotification(
        id: '${kind.name}-$minutesFromEpoch',
        kind: kind,
        fireAt: epoch.add(Duration(minutes: minutesFromEpoch)),
        title: kind.name,
        body: 'body',
      );

  List<PendingNotification> series(NotificationKind kind, int count, int step) =>
      [for (var i = 1; i <= count; i++) item(kind, i * step)];

  int countOf(List<PendingNotification> window, NotificationKind kind) =>
      window.where((n) => n.kind == kind).length;

  test('with room to spare everything is scheduled', () {
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 3, 10000),
      doses: series(NotificationKind.dose, 5, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(window, hasLength(8));
  });

  test('the result never exceeds the budget', () {
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 100, 10000),
      doses: series(NotificationKind.dose, 200, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(window, hasLength(56));
  });

  test('the result is in time order', () {
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 40, 5000),
      doses: series(NotificationKind.dose, 200, 720),
      budget: 56,
      reminderFloor: 14,
    );

    final times = window.map((n) => n.fireAt).toList();
    expect(times, equals(List.of(times)..sort()));
  });

  test('doses cannot crowd reminders out of the window', () {
    // Twice a day for months, against reminders that are months apart. By
    // time order alone the window would be doses only.
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 20, 60 * 24 * 60),
      doses: series(NotificationKind.dose, 300, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(countOf(window, NotificationKind.reminder), 14);
    expect(countOf(window, NotificationKind.dose), 42);
  });

  test('the held slots go to the soonest reminders', () {
    final reminders = series(NotificationKind.reminder, 20, 60 * 24 * 60);
    final window = selectNotificationWindow(
      reminders: reminders,
      doses: series(NotificationKind.dose, 300, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(
      window.where((n) => n.kind == NotificationKind.reminder).map((n) => n.id),
      reminders.take(14).map((n) => n.id),
    );
  });

  test('unused held slots go back to doses', () {
    // Only three reminders exist, so the other eleven held slots are not
    // wasted.
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 3, 60 * 24 * 60),
      doses: series(NotificationKind.dose, 300, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(window, hasLength(56));
    expect(countOf(window, NotificationKind.reminder), 3);
    expect(countOf(window, NotificationKind.dose), 53);
  });

  test('reminders beyond the floor still compete on time', () {
    // Twenty reminders, all sooner than any dose: all twenty get in.
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 20, 10),
      doses: series(NotificationKind.dose, 300, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(countOf(window, NotificationKind.reminder), 20);
  });

  test('with no doses the window is just reminders', () {
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 80, 1000),
      doses: const [],
      budget: 56,
      reminderFloor: 14,
    );

    expect(window, hasLength(56));
    expect(countOf(window, NotificationKind.dose), 0);
  });

  test('with no reminders the window is just doses', () {
    final window = selectNotificationWindow(
      reminders: const [],
      doses: series(NotificationKind.dose, 80, 720),
      budget: 56,
      reminderFloor: 14,
    );

    expect(window, hasLength(56));
    expect(countOf(window, NotificationKind.reminder), 0);
  });

  test('a floor larger than the budget is clamped', () {
    final window = selectNotificationWindow(
      reminders: series(NotificationKind.reminder, 20, 1000),
      doses: series(NotificationKind.dose, 20, 10),
      budget: 5,
      reminderFloor: 99,
    );

    expect(window, hasLength(5));
    expect(countOf(window, NotificationKind.reminder), 5);
  });

  test('a budget of zero schedules nothing', () {
    expect(
      selectNotificationWindow(
        reminders: series(NotificationKind.reminder, 5, 10),
        doses: series(NotificationKind.dose, 5, 10),
        budget: 0,
        reminderFloor: 14,
      ),
      isEmpty,
    );
  });

  group('payloads', () {
    test('a payload round-trips with its kind', () {
      for (final kind in NotificationKind.values) {
        final decoded = NotificationKind.decode(kind.payloadFor('abc-123'));
        expect(decoded!.kind, kind);
        expect(decoded.id, 'abc-123');
      }
    });

    test('an id containing the separator survives', () {
      final decoded = NotificationKind.decode(
        NotificationKind.dose.payloadFor('med-1@177789600'),
      );
      expect(decoded!.id, 'med-1@177789600');
    });

    test('an unprefixed payload is read as a reminder event', () {
      // Notifications scheduled before doses existed are still out there.
      final decoded = NotificationKind.decode('bare-event-id');
      expect(decoded!.kind, NotificationKind.reminder);
      expect(decoded.id, 'bare-event-id');
    });

    test('empty and unknown payloads decode to nothing', () {
      expect(NotificationKind.decode(null), isNull);
      expect(NotificationKind.decode(''), isNull);
      expect(NotificationKind.decode('nonsense:'), isNull);
    });
  });
}
