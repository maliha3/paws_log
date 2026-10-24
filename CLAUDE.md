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
- **cunning_document_scanner** for multi-page scanning (Apple VisionKit).
- OCR is **Apple Vision** through a method channel, not a package — see the
  Medical section for why.
- **image_picker** + **path_provider** for pet photos.
- `uuid` for ids, `intl` for date formatting.
- dev: `drift_dev`, `build_runner`, `mocktail`.

No backend, no accounts, no analytics in v1. All data is local.

## The premium gate

Entitlements come from RevenueCat. Every product — monthly, yearly and
lifetime — grants one entitlement (`premium`), so the app only ever asks
whether that is active and never which plan paid for it. Upgrading from
monthly to lifetime is therefore a non-event in the code.

`docs/monetisation-setup.md` is the App Store Connect and RevenueCat
checklist.

- Keys arrive by `--dart-define` and are never committed. A build with **no
  key falls back to a stub that sells nothing**, so development, CI and the
  tests work without credentials and a missing key can never be mistaken for
  a working store. A debug-only button flips the stub.
- `EntitlementService` mirrors every answer into the settings table. That
  cache is the point: a paying owner opening the app on a train must not be
  told they have lost access because RevenueCat is unreachable. The store
  stays the source of truth; the cache only covers the gap.
- Prices are **always** the store's own localised strings. The app has no
  idea about the owner's currency, tax or regional pricing, and must never
  format a price itself.
- The paywall carries what Apple requires before a purchase: title, duration
  and price per plan, that a subscription renews until cancelled, Restore
  Purchases, and links to the terms and privacy policy.
- Backing out of the store sheet is the commonest outcome there is. It is
  never reported as an error.

Gated: a second pet, photos on a visit, the vet summary.

- **Gates are on doing, never on seeing.** An owner whose access lapsed, or
  who restored a backup made on a paid install, keeps every pet, photo and
  record they already have; the app just stops letting them add more. Hiding
  data someone entered would be taking it away.
- The free pet comes through onboarding, which is never gated. With no pets
  the app is in onboarding, so there is no Pets tab to add a first pet from.
- The gate **fails closed**: an unreadable flag reads as locked, and so does
  a first run with no network.
- Read the flag through `EntitlementService`, not `isPremiumProvider`.
  Nothing watches that provider, so reading it starts its subscription and
  hands back `loading` — which locks out a paying owner on every tap.

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

### Shedding season is the one exception to the anchor rule

`occurrence(anchor, index)` is otherwise a pure function of the anchor and
the index, which is what the promise above rests on. A grooming reminder with
`seasonal` set breaks that: its interval halves inside a shedding window, so
occurrence *n* depends on where in the year occurrence *n-1* fell.

It is still deterministic — it walks one occurrence at a time from the anchor
instead of jumping — and the cost is confined:

- `halvesInSeason` is true only for **day and week** rules. A month cannot
  sensibly halve, and stepping month to month would reintroduce exactly the
  backwards month-end walk that computing from the anchor prevents. Months
  and years keep the anchor path untouched.
- The halving is computed **in days**, not in the rule's own unit. Half of
  "every week" is every three days; halving the interval would leave
  `weeks(1)` at a full week, because one halves to zero and clamps back up.
- Never below a day. "Twice as often" has to stop somewhere.
- `nextAfter` skips its index estimate for these rules, since the estimate
  assumes a fixed interval. The overdue policy is unchanged: the first
  occurrence strictly after the given instant is what comes back.
- Non-seasonal rules take the original O(1) path, byte for byte. A test pins
  that down, because it is the thing most at risk here.

**The shedding windows are the same months in both hemispheres**: March–May
and September–November. Shedding turns at the equinoxes, which fall in March
and September everywhere, so a southern cat sheds in the same two windows —
they are simply its autumn and its spring. The `Hemisphere` setting therefore
decides what each window is *called* and nothing else, which is why
`inSheddingSeason` takes no hemisphere.

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

## Reminders after onboarding

A **Reminders** card on the pet's profile opens that pet's recurring care,
where it can be added to, edited, paused and deleted. Before it existed
reminders could only be created during onboarding, so a second pet got none at
all and nobody could change a schedule after the first run.

`showReminderDraftSheet` lives in `core/widgets/` rather than beside either
caller. Onboarding fills in drafts it saves all at once; this screen edits
reminders that already exist; both want the same fields, and shared code goes
down a layer rather than sideways between features. `ReminderDraft.fromReminder`
and `applyTo` are the two ends of that conversion.

- Editing is the repository's `update`, which **moves the existing pending
  occurrence** when the schedule changes rather than replacing it, so Today
  and the notification window cannot disagree with the reminder. Editing only
  the title leaves the occurrence where it was.
- **Pausing** keeps the reminder and its history and takes it off Today, which
  it gets for free: `_dueItemQuery` already filters on `isActive`, and so does
  the scheduler's source.
- A paused reminder reads as "paused", not "overdue". Its stored due date is
  whatever it was when it stopped, and calling that overdue would reproach the
  owner for something they switched off on purpose.
- Every write resyncs notifications, because the repository does it. There is
  a test counting resyncs for exactly the failure CLAUDE.md warns about: a
  write that forgets one fails silently, and the owner finds out when a
  notification never arrives.

## Grooming

`nailTrim` and `brushing` are reminder categories like any other, with their
own palette colour and icon. What makes them different is cadence: grooming is
care the owner does themselves, so it repeats every few days where medical
care repeats every few months. `ReminderCategory.isGrooming` marks them.

Starter suggestions: **nail trim every three weeks**, and **brushing weekly,
or every two days for a long coat** — a long coat mats. A coat nobody has
recorded takes the weekly suggestion, the lighter of the two: guessing "long"
would put a short-haired cat on a chore its owner does not need. The coat is
asked for during onboarding, on the screen before the reminders, and choosing
it retunes the brushing suggestion — only that one interval, so anything else
the owner has already changed survives going back a screen.

The **shedding-season switch** is off in the suggestion. It is opt-in, and the
app should not open by proposing a daily job. It only appears in the reminder
sheet for day and week rules, and the flag is never stored on a rule it cannot
apply to, since a dormant flag reads as a promise the schedule does not keep.
See "Shedding season is the one exception to the anchor rule" above for what
it does.

One thing the scheduler does *not* need: a reminder only ever has one pending
event, so a brushing reminder every two days costs **one** notification slot,
not thirty. The 56-slot window and the 14-slot reminder floor are unchanged by
grooming.

## The Medical section

Per pet, in five segments: **Prescriptions · Medicines (active/past) ·
Vaccines · Vet visits · Health**.

A `Prescription` holds its page images in order, the raw OCR text, and the
vet details. `Medicine.prescriptionId` links each medicine back to the
prescription it came from, so a course always has its source.

The record is its own screen, reached from one card on the pet's profile. The
profile answers "who is this cat" — facts, photo, weight trend — and the
segments sit behind it, because stacking them meant scrolling past every
medicine to reach the vaccines. The segments are chips in a row that scrolls
sideways rather than squeezing, so the labels survive the largest text sizes.

Medicines split into **Active** and **Past**. A course is past once it has been
stopped by hand *or* its end date has gone by — a course that has simply run
out is over, whether or not anyone pressed stop.

### The OCR engine is Apple Vision, not ML Kit

The spec named `google_mlkit_text_recognition`. It was added, and removed
again: **ML Kit's frameworks ship without an arm64-simulator slice**, so with
it in the project the app cannot build for the Simulator at all — not the
prescription screens, the whole app. That would have cost every integration
test and every screenshot in exchange for one feature.

Apple's Vision framework does the same job, is part of iOS so it adds nothing
to the download, and builds for the simulator. `ios/Runner/TextRecognition.swift`
is the channel; `OcrService` is the interface above it.

Vision is iOS-only. When Android arrives, ML Kit goes behind that same
interface and nothing above it changes — which is the reason the interface
exists.

Images are read off the main thread, and a `UIImage`'s orientation is passed
through: Vision works on raw pixels, so a photo taken in portrait is read
sideways without it.

### Prescriptions are never trusted automatically

This is the rule the whole flow is built around. OCR misreads things, and
handwriting most of all. A misread dose is not a cosmetic bug.

- **Nothing becomes a `Medicine` or a dose until the owner taps Confirm.**
  Scanning, saving pages and running OCR change no schedule.
- The review screen shows the **page images above the fields**, so the owner
  is reading the prescription while they check what was extracted.
- A field the parser is unsure of is **marked low-confidence**, and a field
  it cannot read is left **blank** rather than guessed.
- Every review screen carries *"Check every dose against the original
  prescription."*
- **Save photos only** is always available. An owner who just wants the page
  kept never has to go near the extracted fields.
- The prescription row is written the moment the pages are on the device, so
  **backing out of the review keeps the page**. What it never does is touch the
  schedule.
- Tapping a page opens it full screen, pinch and double-tap to zoom. Reading
  the small print is why the photo exists. Visit attachments use the same
  viewer.
- **Save photos only is not a one-way door.** A saved prescription opens its
  own screen — pages, vet details, the text that was read, and the courses it
  produced — and `reviewAgain` opens the review screen from there. A page
  that was never read is read *now*; one that was is parsed from the stored
  text, so nothing is read twice and nobody has to scan a page they already
  have.

### Times per day

The parser and the review screen work in *times per day*, which is how a
prescription is written. `Medicine` stores **actual dose times**, because
that is what generates doses. The review screen converts on Confirm: 1/day →
09:00, 2 → 08:00 and 20:00, 3 → 08:00, 14:00 and 20:00, 4 → 08:00, 12:00,
16:00 and 20:00. The owner can edit the times afterwards like any medicine.

### What has your vet diagnosed?

Conditions and allergies live in the **Health** segment, not on the profile:
they are medical records, and the profile answers "who is this cat". The one
exception is the **allergy banner**, which sits at the top of the profile
whenever the pet has an allergy recorded. An allergy is safety information,
and the moment it matters — a new food, a locum vet, someone else feeding the
cat — is rarely the moment anyone goes looking for it. The banner is absent
entirely when there is nothing to say, so it never becomes furniture people
stop reading.

The condition editor offers a pick-list — CKD, FIP, cat flu, FIV, FeLV,
diabetes, hyperthyroidism — and free text alongside it. **This is not the app
offering an opinion**, which is why the screen asks *"What has your vet
diagnosed?"* and says in as many words that Paws Log never works out a
diagnosis of its own. The suggestions exist so an owner types less, not so
they pick from a shortlist of guesses. The screen carries
[AppConstants.vetDisclaimer] like every other screen that proposes anything.

Conditions sort **ongoing first, then most recently diagnosed**, undated ones
last. That sort happens in Dart, not SQL: "ongoing before past" is an order
over an enum's meaning, and a text column sorts alphabetically — `ongoing`
happens to sort before `past`, which would make the right answer a
coincidence waiting to break.

## Vaccination history

Marking a `vaccine`-category reminder **done** also writes a
`VaccinationRecord` — that completion is the moment a shot is known to have
been given. Skipping one writes nothing: a skipped vaccine was not given.

`CompletionOutcome` carries the record's id so undo removes it along with the
follow-on occurrence and the restored `nextDueAt`. All three go back or none
do.

`source_event_id` is not a foreign key, so deleting a reminder leaves the
history standing. Deleting the *pet* does cascade.

Records can also be **added and corrected by hand**. The automatic path is
the point of the feature and is unchanged, but it only covers shots the app
knew to remind about: one given at a clinic it knew nothing about, or from
before the owner installed it, had no way in at all, and a wrong date had no
way out. Editing keeps `source_event_id` untouched, so undoing the completion
that wrote a record can still find it afterwards.

## Notifications

iOS silently drops pending local notifications past **64**. The scheduler
therefore never schedules the whole future — it maintains a rolling window.

Scheduling only the *next* occurrence of each reminder would also stay inside
the cap and is simpler, but it was weighed and rejected: it leaves the app
with nothing queued beyond the next due date, so a yearly vaccine has one
notification and no cover at all if the owner does not open the app. The
window is the design:

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

iOS deployment target is **14.0**, raised from Flutter's default 13.0 because
file_picker requires it. This only shows up as a build failure on a device —
`flutter analyze` and the unit tests are blind to it.

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

## The photo vault

One album per pet, free — it is the cat's memory book, not a pro feature, and
the paywall already has three triggers. A `Photos` card on the profile opens a
three-column grid, newest first by `takenAt`, because an album reads by when
things happened rather than by import order.

**There is no thumbnail column.** `Image.file(path, cacheWidth: ...)` decodes
at grid size, which costs one decode instead of a second file to write, keep
in sync, back up and clean up. `cacheWidth` asserts on a non-positive value,
so a surface that has no width yet gets no hint rather than zero.

**Set as profile photo copies the file** into `pet_photos/` instead of
pointing `Pet.photoPath` at the album path. Deleting the photo from the album
afterwards must not leave the portrait pointing at nothing. Replacing a
portrait deletes the one it replaced, so changing your mind does not
accumulate files.

**Deleting a pet deletes their files.** Foreign keys cascade the rows and
nothing cascades the files, so `PetRepository.delete` collects every path the
pet owns — portrait, album, prescription pages, visit attachments — and
removes them after the row. It is the one repository that reads across tables,
because it is the only place that knows what "everything belonging to this
pet" means. Archiving keeps everything.

## Backup

A backup is a zip: `backup.json` plus `photos/`. Not bare JSON — attachments
and pet portraits are files on disk, and a backup that silently drops them is
worse than none, because the owner only finds out when they restore.

- Photo paths inside the archive are relative to the documents directory and
  rewritten to absolute paths on import, since they differ between installs.
  A path that would escape with `..` falls back to its basename.
- A row whose file has vanished keeps the row and drops the reference, so a
  restore shows a placeholder rather than a path to nothing.
- Import **replaces**, it does not merge. Two installs that have both moved
  on share no notion of which version of a row is right, and silently keeping
  the wrong one is worse than being told.
- Rows are serialised through drift's `toJson`/`fromJson` with a custom
  `ValueSerializer`: DateTimes as ISO-8601 so the UTC flag survives, and the
  two list columns — medicine dosing times (`List<int>`) and prescription
  pages (`List<String>`) — converted by hand, because `jsonDecode` returns
  `List<dynamic>` and drift's default casts it straight through.
- `BackupService` touches no plugins, which is what lets the round trip be
  tested. `BackupSharing` is the thin layer over the share sheet and file
  picker.

**Include photo vault** is a toggle on the export screen, defaulting on, with
the album's size measured off disk beside it. Turning it off leaves the album
out *entirely* — rows as well as files. Keeping the rows without the files
would restore an album full of entries pointing at nothing, which is worse
than an empty one.

A prescription's pages are a *list* of paths in one column, so the archive
packs them with `_packFileLists`. A page whose file has gone is dropped from
the list rather than nulled in place: pages are read in order, and a hole in
the middle would be worse than a shorter list.

Insert order on import follows the foreign keys: visits before prescriptions,
prescriptions before medicines. A medicine carries `prescriptionId`, so an
import that put medicines back first would fail on the key.

## Vet summary

One PDF page per pet: profile, allergies, conditions, vaccinations with
dates, the medicines they are on *now*, the weight trend, and the last three
visits. It carries the same standing note the app does — a record of what the
owner entered, not a clinical document.

**Allergies print above the vaccination table**, in a box rather than a row of
a table: a vet who has not met this cat needs them before anything else on
the page, and a warning should not look like a record. Conditions follow as a
table, ongoing before past.

`VetSummaryPdf` is a pure function of a `VetSummary`: no repositories, no
plugins, no clock. `VetSummaryService` gathers the data and
`VetSummarySharing` holds the share sheet, which is what lets the layout be
exercised in a plain test.

A finished course is history and is left off. A cat added five minutes ago
has none of this and still gets a page — their owner may be taking them to
the vet today.

## Appearance and accessibility

`test/features/accessibility_test.dart` pumps every screen in both themes at
1x and 2x text. A RenderFlex overflow throws in a widget test, so "no
exception" is a real assertion: these fail the moment a layout stops coping
with someone's type size. Add a screen there when you add a screen.

What 2x text breaks, from the four that it caught:

- A `Spacer` cannot give ground, so a centred column overflows. Wrap it in
  `SingleChildScrollView` + `ConstrainedBox(minHeight:)` + `IntrinsicHeight`
  — the last one is what gives the Spacer a bounded height again.
- An `AppBar` `bottom` has a fixed height and cannot hold scaled text. Put
  the content in the list instead.
- A `Row` of a big number and its trailing detail runs off the side. `Wrap`
  lets the detail drop to its own line.
- A bottom sheet is taller than the phone. Scroll it.

Tests also have to scroll: a `ListView` does not build off-screen children,
so a finder matches nothing and `ensureVisible` has nothing to scroll to.
`scrollAndTap` and `scrollIntoView` in the harness handle it, and far more
sits below the fold at 2x.

One notion of "local". Today, recurrence and doses all work in `tz.local`,
never `DateTime.toLocal()`. On a device they agree, so mixing them hides;
in tests the pinned zone and the system zone differ for part of every day,
which is exactly how this surfaced. Tests build "today" with
`todayInTestZone()` for the same reason.

## Look

- **Brand**: warm amber on cream, with near-black `secondary` carrying the
  solid controls. Cream rather than white is what stops the app reading as a
  form; the dark ink against it is what stops the warm palette going mushy.
- **Signature pieces**: a pill CTA with a dark disc holding the mark
  (`PillButton`), pastel fact tiles (`FactChip`), a greeting header instead
  of a title bar, and a floating pill navigation bar.
- A floating bar means content scrolls *under* it. Anything anchored to the
  bottom needs lifting clear, and lists need bottom padding — otherwise taps
  land on the bar instead of the button, which is how the "Add a pet" button
  stopped working.
- Removing an `AppBar` removes the top inset with it. A screen without one
  needs `SafeArea(bottom: false)` or its header sits under the clock.
- **Type**: Nunito, a *variable* font. One file; weight is an axis, so
  `fontWeight` alone is ignored and `fontVariations` is what moves it. All of
  that lives in `AppTheme._style`.
- **Illustration is drawn, never photographed.** `SleepingCat` and the
  background paw prints are `CustomPainter` work for the same reasons as the
  mark, plus one more: shipping stock photography of someone else's cat is a
  licensing problem the app does not need. `test/preview/cat_preview_test.dart`
  renders the drawing to a PNG so it can be looked at — skipped by default,
  because a golden is tied to the machine that made it and that file is for
  previewing a drawing, not guarding it.
- **The mark** is drawn (`PawMark`), not an image: crisp at any size, takes
  the colour it is given, and can animate. `tool/make_icon.py` draws the app
  icon from the same geometry — change one, change both.
- **Category colours** are a `ThemeExtension` with its own light and dark
  steps, so the "colours come from the theme only" rule still holds. The icon
  always repeats what the colour says; nothing rests on colour alone.
- **Motion plays once and briefly.** Rows arrive staggered, the mark springs
  in, screens use the platform transition. Nothing loops: a looping animation
  keeps a widget test awake and an owner's eye busy for no reason. Keep
  durations under ~700ms or the test harness's bounded pumping will not have
  settled before assertions run.

Colours come from the `ColorScheme` only — there are no hardcoded `Colors.*`
outside `app_theme.dart` and the PDF, which uses fixed inks because it is for
print. Dark mode is its own scheme, not an inverted light one.

The app icon is a placeholder, not a design: it exists so the app does not
ship with the Flutter logo. `tool/make_icon.py` regenerates it.

## Not built yet

Named in the spec, deliberately absent from the code. Not oversights:

- `VetVisit.cost`.
- `Pet.species`, `microchip`, `vetName`, `vetPhone`. A prescription carries
  its own vet name and clinic; the pet does not yet.
- Premium gating for **full weight history**. Weights are currently
  ungated — the gate covers a second pet, photos on a visit, and the vet
  summary.

## Migrations

`createTable` builds from **today's** table definition, not the historical
one. So a database arriving from v1 gets `medicines` *including* the column
v3 adds — and `addColumn` then fails with "duplicate column name".

An `addColumn` must therefore be guarded by the version that already had the
table:

```dart
if (from < 3) {
  await m.createTable(prescriptions);
  if (from >= 2) {
    await m.addColumn(medicines, medicines.prescriptionId);
  }
}
```

The migration tests build a real database at each old version from the DDL
drift emitted at the time, so a jump like v1 to v3 is exercised and not
assumed.

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
