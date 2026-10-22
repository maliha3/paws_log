# PawsLog

A cat care reminder app. Owners track vaccines, deworming, flea/tick treatment
and other recurring care per pet, and get local notifications when something is
due.

**This app is not veterinary advice.** Any screen that proposes a schedule must
show "Confirm the schedule with your vet."

## Stack

- Flutter 3.44+ / Dart 3.12+
- **drift** for persistence (SQLite). `drift_flutter` supplies the native
  libraries and the database file location.
- **flutter_riverpod** for state. Plain hand-written providers — no
  `riverpod_generator`. Drift already needs `build_runner`; a second codegen
  pass on every provider edit is not worth it.
- **flutter_local_notifications** + **timezone** + **flutter_timezone** for
  scheduled local notifications.
- **image_picker** + **path_provider** for pet photos.
- `uuid` for ids, `intl` for date formatting.
- dev: `drift_dev`, `build_runner`, `mocktail`.

No backend, no accounts, no analytics in v1. All data is local.

## Layout

Feature-first. Shared code goes down a layer, never sideways.

```
lib/
  main.dart                     # bootstrap: tz init, db, ProviderScope
  app.dart                      # MaterialApp + routing
  core/                         # theme, date helpers, constants
  data/
    db/                         # drift tables, converters, AppDatabase
    repositories/               # the only things that touch the db
  domain/                       # models, RepeatRule, starter reminders
  features/<feature>/           # screens + controllers for one feature
  services/notifications/       # NotificationScheduler and friends
```

Rules:

- Widgets never touch `AppDatabase` directly. Repositories only.
- Repositories return domain models, not drift row classes.
- Anything that changes a due date must go through the repository method that
  also triggers a notification resync. No partial writes.
- Date math lives in `domain/repeat_rule.dart`. Nowhere else.

## Ids and time

- Ids are UUID v4 strings, generated in the repository.
- All timestamps stored as UTC `DateTime`. Drift is configured with
  `store_date_time_values_as_text` (see `build.yaml`) because the default
  integer format hands values back as system-local `DateTime`s.
- Zone-aware `TZDateTime` stays inside the date maths. Everything crossing a
  repository boundary is a plain UTC `DateTime` — use `toPlainUtc()`, not
  `toUtc()`, which returns another `TZDateTime` and compares unequal to what
  the database returns.
- Occurrences keep their **wall-clock** time across DST, so recurrence
  arithmetic runs in `tz.TZDateTime` in the device's zone, not raw UTC.
- `timeOfDayMinutes` is minutes past local midnight. Default 09:00.

## Recurrence

A reminder has a `repeatUnit` (none/days/weeks/months/years), a
`repeatInterval`, and an `anchorDate` the cycle counts from.

- Month-end clamps: Jan 31 + 1 month is Feb 28 (or 29), but the anchor stays on
  the 31st, so the following month returns the 31st again. Never let a clamp
  walk the series backwards.
- Yearly rules on Feb 29 fall to Feb 28 in common years, anchor unchanged.
- **Overdue policy: skip ahead.** A 3-month reminder five months late advances
  to the next future date from the anchor. Missed cycles are not replayed.
- A new reminder's first occurrence is its anchor, even if that is in the past,
  so "the vaccine was due last week" shows as overdue instead of jumping a
  year. Skip-ahead applies when completing, not when creating.
- An active reminder has exactly one `pending` event. Completing it closes
  that event and opens the next.
- A snooze moves when a notification fires, not the due date: the event stays
  `pending` and stays on Today.

## Notifications

iOS silently drops pending local notifications past **64**. The scheduler
therefore never schedules the whole future — it maintains a rolling window:

- **56** earliest pending occurrences scheduled at any time.
- **8** slots reserved for snoozes fired at runtime.
- The last scheduled notification doubles as a refill trigger, so the window
  advances even if the app is not opened for months.
- Notification ids are a stable hash of the event id, making cancel and
  reschedule idempotent.
- Actions on every reminder: **Done**, **Snooze 1 hour**, **Snooze to
  tomorrow** (tomorrow at the reminder's own time of day).
- `syncAll()` runs on launch, on `AppLifecycleState.resumed`, and after any
  mutation that moves a due date.
- Android uses `inexactAllowWhileIdle`. Exact alarms would need a user-facing
  permission flow on Android 14+; a care reminder does not need minute
  precision.

## Working agreements

- Run `flutter analyze` and `flutter test` before every commit. Both clean.
- Recurrence and scheduler-window logic are pure Dart and must stay unit
  testable without an emulator.
- Repository tests use `NativeDatabase.memory()`.
