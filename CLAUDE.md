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
- Date math lives in `domain/` and nowhere else: `repeat_rule.dart` for
  reminder recurrence, `dose_schedule.dart` for medicine courses.

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

## Medicines

Medicines do not reuse `Reminder`'s recurrence. "Every 3 months" cannot
express "08:00 and 20:00, for ten days", and a reminder has no notion of a
dose being *missed*.

- `timesOfDayMinutes` holds one entry per dose, `intervalDays` the gap
  between dosing days, and a course runs from `startDate` to an inclusive
  `endDate`, or open-endedly when that is null.
- A finite course has its whole run generated up front; an open-ended one is
  generated to a 14-day horizon and topped up on launch and resume.
- Dose ids are derived from the medicine and the instant, so regenerating is
  idempotent and never disturbs a dose already logged.
- The end date is a *date*. Its UTC midnight is not the end of that day in
  the owner's zone, so a generation window built from it clips the final
  day's doses.
- Editing a schedule replaces only *pending future* doses. Taken, missed and
  skipped doses are adherence history and are never rewritten.
- A dose is missed once its day is over, not the moment it passes. Only
  `markOverdueMissed` decides that; `pending` elsewhere means exactly
  "not yet logged".
- Today shows the whole day's course, including doses whose time has not come
  — unlike reminders, where only what is due shows up.

## Notifications

iOS silently drops pending local notifications past **64**. The scheduler
therefore never schedules the whole future — it maintains a rolling window:

- **56** earliest pending items scheduled at any time, drawn from *both*
  sources: reminder occurrences and medicine doses.
- **8** slots reserved for snoozes fired at runtime.
- **14** of the 56 are held for reminder occurrences. Time order alone does
  not work once medicines exist: a twice-daily course produces sixty
  notifications a month, so filling by date covers about three weeks and a
  yearly vaccine is never scheduled again. The floor may promote a reminder
  months out over a dose tomorrow — that is the point. Held slots nobody
  claims go back to doses.
- A notification's payload is `<kind>:<id>`, and the notification id is a
  hash of the payload rather than the bare row id, so a reminder occurrence
  and a dose can never collide. A payload with no prefix is read as a
  reminder event, covering notifications scheduled before doses existed.
- Reminder notifications carry Done / Snooze 1 hour / Tomorrow; dose
  notifications carry Taken / Skip. Snoozing a dose to tomorrow would mean
  skipping it, which is a different answer with its own button.
- **The window cannot refill itself.** Neither platform runs Dart when a local
  notification is merely *delivered*, so there is no way to top the window up
  from the background. It is rebuilt on launch, on resume, after any write
  that moves a due date, and when a notification action is pressed — that
  last one does run Dart, on a background isolate, even with the app closed.
  56 slots is years of cover for a few reminders per pet at monthly to yearly
  cadence, so this is a non-issue in practice. A genuine background refill
  would need WorkManager and BGTaskScheduler, which v1 does not carry.
- Notification ids are a stable hash of the event id, making cancel and
  reschedule idempotent.
- Actions on every reminder: **Done**, **Snooze 1 hour**, **Snooze to
  tomorrow** (tomorrow at the reminder's own time of day).
- `syncAll()` runs on launch, on `AppLifecycleState.resumed`, and after any
  mutation that moves a due date.
- Android uses `inexactAllowWhileIdle`. Exact alarms would need a user-facing
  permission flow on Android 14+; a care reminder does not need minute
  precision.

## Running on a device

`flutter test integration_test/app_test.dart -d <device>` drives the real app:
the native sqlite build, path_provider's documents directory, the device
timezone lookup, and notifications actually reaching the OS. Nothing else
covers those.

Two flags it needs:

- `--dart-define=PAWSLOG_SUPPRESS_PERMISSION_PROMPT=true`. An integration test
  drives the Flutter view directly and cannot answer a system dialog, and iOS
  makes the app inactive while one is up, so pumped frames stop arriving and
  the test simply stalls.
- The test grants itself *provisional* notification authorisation, which iOS
  gives without a dialog. Without it `zonedSchedule` is rejected and nothing
  shows up pending, whether or not the scheduler worked.

Starter reminders are due at 09:00 on the day they are created, so after
midday there is nothing in the future to schedule and a pending count of zero
is correct. Completing one opens the next occurrence, which is what the test
checks reaches the OS.

## Launch and resume

`runMaintenance` catches up everything that depends on elapsed time, which is
exactly what the app cannot observe while closed. Order matters: doses are
marked missed first, then courses are topped up, then the notification window
is rebuilt so it reflects both.

Anything wired through `scheduleSyncProvider` must not be read by the
scheduler itself — that is circular, since the writing repositories depend on
the scheduler. The scheduler builds its own read-only repositories. Tests
wire it the same way; getting that wrong makes a write silently fail to
rebuild the window.

## Working agreements

- Run `flutter analyze` and `flutter test` before every commit. Both clean.
- Recurrence and scheduler-window logic are pure Dart and must stay unit
  testable without an emulator.
- Repository tests use `NativeDatabase.memory()`.
- A `group` body runs at collection time, before `setUpAll`, so anything
  needing the timezone database must be a function rather than a group-level
  `final`.
- Widget tests that touch the database go through `test/helpers/harness.dart`.
  Two drift-under-`testWidgets` traps live there, both of which present as a
  hang rather than a failure: a cancelled query stream schedules a timer that
  needs the fake clock still running, and `AppDatabase.close()` deadlocks
  inside a test body. Never use `pumpAndSettle` on a screen showing an
  indeterminate progress indicator.
