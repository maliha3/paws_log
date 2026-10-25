# Device QA — the things no test can reach

593 automated tests cover the logic, every screen at double text size, and
one end-to-end run on a simulator. What none of them touch is the plugin
boundary: the camera, the scanner, the OCR, the share sheet, notifications
actually arriving, and money actually moving.

That is what this list is for. It is about an hour, on your own iPhone, and
it is the only testing those paths will ever get before a stranger does it
for you.

Build it with your real keys first:

```
flutter run --release -d <your-iphone> \
  --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
  --dart-define=PRIVACY_URL=https://your-policy-url
```

Release, not debug: debug builds are slow enough to hide a stutter, and the
debug-only "Simulate unlock" button would let you skip the purchase you are
trying to test.

Tick each line. Where something is wrong, note **what you did** before it,
not just what you saw — that is the part that is hard to reconstruct later.

---

## 1 · First run

- [ ] Delete the app first, so this is a genuine first launch
- [ ] Welcome screen appears; the cat is drawn, not a broken image
- [ ] "Get started" → add a cat. Tap **Choose a photo** and pick one
- [ ] The photo permission prompt appears **the first time only**
- [ ] Decline it once on purpose. The app should carry on without a photo,
      not get stuck
- [ ] Reopen, allow it, pick a photo. It appears as the portrait
- [ ] Continue to starter reminders. All five are there, including Nail trim
      and Brushing
- [ ] Finish. The notification permission prompt appears **here**, not at
      launch
- [ ] **Decline it.** The app must still work — reminders just will not
      notify

> If the notification prompt appears before the welcome screen, something
> regressed: it is deliberately asked at the end of onboarding, with a
> schedule on screen to explain what it is for.

## 2 · Notifications actually arriving

This is the whole point of the app and cannot be tested any other way.

- [ ] Settings → Paws Log → Notifications → allow
- [ ] Add a reminder due **in about three minutes** (Pets → your cat →
      Reminders → + → set the time)
- [ ] **Close the app completely** — swipe it away from the app switcher
- [ ] Lock the phone and wait
- [ ] The notification arrives, with the cat's name in it
- [ ] Long-press it. **Done**, **Snooze 1 hour** and **Tomorrow** are there
- [ ] Tap **Done** without opening the app
- [ ] Open the app. The reminder is gone from Today and the next occurrence
      is scheduled

> That last step is the one most likely to be broken, and the hardest to
> notice: the action runs Dart on a background isolate with the app closed.

- [ ] Repeat with **Snooze 1 hour** — the row stays on Today and says it is
      snoozed
- [ ] Set the phone's clock forward a day, reopen, and check overdue items
      read as overdue rather than vanishing. **Set it back afterwards.**

## 3 · The camera and the scanner

Never run on hardware. Budget the most time here.

- [ ] Pets → your cat → Photos → + → **Take a photo**. It saves and appears
      in the grid
- [ ] Medical record → Prescriptions → + → **Scan the pages**
- [ ] The document scanner opens, finds the page edges, and lets you crop
- [ ] Scan **two pages** in one go. Both are kept, in order
- [ ] Scan a **real prescription**, printed, in ordinary indoor light
- [ ] Check the review screen: is the medicine name right? the dose? the
      "twice daily"? the number of days?
- [ ] Anything the parser was unsure of is marked, not silently wrong
- [ ] **Confirm.** The medicine appears with the right dose times
- [ ] Now scan a **handwritten** prescription. Expect it to do badly — the
      question is whether it leaves fields blank or fills them with
      nonsense. Blank is correct
- [ ] Back out of the scanner without taking anything. Nothing is saved
- [ ] Deny the camera permission in Settings, then try to scan. It should
      fail quietly and still offer Photos

## 4 · Money

Use a **sandbox tester** account (App Store Connect → Users and Access →
Sandbox). Sign in at the purchase sheet, **not** in iOS Settings.

- [ ] Add a second pet → the paywall appears
- [ ] It shows a **real price in your currency**, not "Purchases are not
      available"
- [ ] It names what you get, and has Restore, Terms and Privacy links
- [ ] Tap **Privacy** — your policy page opens and actually loads
- [ ] Start the purchase and **cancel** it. No error message, nothing
      charged, paywall still there
- [ ] Buy it. The second pet is added
- [ ] Scan a fourth prescription — no paywall now
- [ ] Vet summary → it generates and the share sheet opens
- [ ] **Delete the app. Reinstall.** Open the paywall → **Restore
      purchases** → unlocked again
- [ ] Turn on airplane mode and reopen. A paid owner must **stay** unlocked
      — that is what the settings cache is for

> If it locks you out in airplane mode, stop and tell me. That is the one
> failure here that would cost you refunds.

## 5 · Sharing and files

- [ ] Backup → **Include photo vault** on → Export. The sheet opens, the
      size looks plausible
- [ ] Save it to Files. Open Files and confirm the zip is really there
- [ ] Toggle the vault **off** and export again — noticeably smaller
- [ ] Vet summary → share → Mail. The PDF opens and is readable
- [ ] Share a single photo from the album
- [ ] **Restore** the backup you saved. Everything comes back: pets, photos,
      prescriptions, weights
- [ ] A photo you took earlier still displays after the restore

## 6 · Being a real phone

- [ ] Rotate the phone on a few screens. Nothing overlaps or clips
- [ ] Settings → Display → **Larger Text**, drag it to maximum, reopen the
      app. Walk Today, the pet profile, the medical record and the paywall
- [ ] Settings → **Dark mode**. Walk the same screens
- [ ] Take a call, or set a timer, mid-task. Come back — nothing is lost
- [ ] Add 30+ photos to the album and scroll fast. Smooth, no blank tiles
- [ ] Leave the app overnight and reopen. Yesterday's doses read as missed,
      not pending

## 7 · The things that only break when it matters

- [ ] Type a 60-character cat name. It truncates, not overflows
- [ ] Put emoji in a note and a caption. They survive a restart
- [ ] Delete a pet that has photos, prescriptions and visits. Everything
      goes, and the app does not crash on the now-empty list
- [ ] Delete your only pet. The app returns to onboarding rather than an
      empty shell
- [ ] Add a weighing of `0`, and one of `999`. Neither breaks the chart

---

## What to do with a failure

Note the screen, what you tapped, and what you expected. Then send me the
note — most of these are reproducible in a test once I know the shape of
them, and a test is how it stays fixed.

For a crash: Settings → Privacy & Security → Analytics & Improvements →
Analytics Data, find the `PawsLog-…` file, and send that too.
