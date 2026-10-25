# Shipping Paws Log — everything only you can do

The repo side is finished. What is left is dashboards, a web page and a real
phone, in the order they unblock each other.

Tick these off top to bottom. Where a step has detail, it is in
`monetisation-setup.md` rather than repeated here.

---

## 1 · Apply for the Small Business Program

**App Store Connect → Business → Small Business Program.**

Apple keeps 15% instead of 30% for anyone under $1M a year. On a $9.99
unlock that is $8.49 to you instead of $6.99 — the difference between
twelve sales a year to cover your developer fee and fifteen.

Approval is not instant, so start it now and carry on with the rest. It
applies from the start of the following month, so applying before you have
any sales means you never pay 30%.

---

## 2 · Publish the privacy policy

Apple will not approve an app that sells anything without a working policy
URL, and it checks the link.

1. Open `docs/privacy-policy.md` and replace **`[your support email]`** with
   a real address you will read. A free Gmail is fine.
2. Publish it. GitHub Pages costs nothing:
   - push this repo to GitHub (private is fine for the code — Pages needs
     the repo public, or a Pro account; if you would rather not, a free
     Notion page or a Google Site works just as well)
   - **Settings → Pages → Source: Deploy from a branch**, branch `main`,
     folder `/docs`
   - wait a minute, then check
     `https://<your-user>.github.io/paws_log/privacy-policy` actually loads
3. Keep that URL. Three later steps need it.

**Do not skip the "actually loads" check.** A policy URL that 404s is one of
the more common first-submission rejections.

---

## 3 · Create the app in App Store Connect

**My Apps → + → New App.**

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `Paws Log` (this is what shows on the Store; it must be unique across the Store) |
| Primary language | English (UK) or (US) — your choice, be consistent |
| Bundle ID | `com.malihazaman.pawsLog` — must match exactly |
| SKU | anything private, e.g. `pawslog-001` |

If the bundle ID is not in the dropdown, create it first at
**developer.apple.com → Certificates, Identifiers & Profiles → Identifiers**.

Then fill in, under the app:

- **Category**: Primary *Lifestyle*. Secondary *Health & Fitness* if offered.
  (Not *Medical* — that category invites a much harder review, and this app
  deliberately gives no medical advice.)
- **Age rating**: answer the questionnaire honestly; every answer is None.
  You will get 4+.
- **Privacy Policy URL**: the one from step 2.
- **App Privacy**: the nutrition label. The answers are in
  `monetisation-setup.md` — tracking *none*, linked to you *none*, not
  linked to you *purchase history*.

---

## 4 · Create the product

**Your app → Monetization → In-App Purchases → +**

| Field | Value |
|---|---|
| Type | **Non-Consumable** — not a subscription |
| Reference Name | `PawsLog Lifetime` |
| Product ID | `com.malihazaman.pawsLog.premium.lifetime` |
| Price | **$9.99** (USD; Apple converts the rest) |

Then add, for your primary language:

- **Display Name**: `Paws Log Unlocked`
- **Description**: `Every cat in the household, every prescription scanned,
  and the vet summary. One payment, yours for good.`

A non-consumable needs **no review screenshot** — that requirement is for
subscriptions, which is one of several reasons not to sell one.

**Per-territory pricing.** Click through to the price schedule and bring
South Asia and Latin America down a few steps. $9.99 is a different ask in
Dhaka than in Munich, and Apple will otherwise just convert it.

The product will sit in **Missing Metadata** until it is attached to a build
you submit. That is normal and not a mistake you have made.

---

## 5 · Set up RevenueCat

Full detail is in `monetisation-setup.md` §2. The short version:

1. Create a project and add an **App Store** app with the bundle ID.
2. Give it the credentials from App Store Connect: the **In-App Purchase
   Key** (`.p8` — downloadable once, keep it), the **Shared Secret**, and
   the **Server Notifications V2** URLs.
3. Create a product with the same product ID as step 4.
4. Create an entitlement with the identifier **`premium`** — this exact
   string is what the app checks — and attach the product to it.
5. Create an **Offering**, mark it *Current*, and put the product in it as a
   package. The paywall shows whatever is in the current offering, so this
   is where the "one product only" decision actually lives.
6. Copy the **public SDK key** (starts `appl_`). It is not a secret, but it
   is not in the repo either.

---

## 6 · Test the purchase on a real iPhone

Nothing so far has run on hardware. The camera, the document scanner and the
on-device OCR have only ever been exercised on a simulator.

1. **Create a sandbox tester**: App Store Connect → Users and Access →
   Sandbox → Testers. Use an email you control that is **not** your Apple
   Account.
2. Build to your own iPhone with the key:

   ```
   flutter run --release -d <your-iphone> \
     --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
     --dart-define=PRIVACY_URL=https://your-policy-url
   ```

3. Walk the whole app and check, in this order:
   - onboarding, and a notification actually arriving
   - **scan a real prescription** — this is the one feature that has never
     touched a camera
   - the paywall shows a price, not "Purchases are not available"
   - buy it. **You sign in with the sandbox account at the purchase sheet**,
     not in Settings. A sandbox purchase charges nothing.
   - delete the app, reinstall, and **Restore purchases** brings it back

**If the paywall says purchases are unavailable**, the cause is almost
always one of: no `--dart-define` key, the Paid Applications agreement not
Active, or the product not yet attached to the offering. The app is telling
you the truth, not failing.

---

## 7 · Screenshots and store copy

Required: **6.7"** (iPhone 15/16 Pro Max) and **6.5"**. Five each is plenty.

I can generate these — ask, and I will drive the app and capture at the exact
sizes. You will need to write or approve:

- **Subtitle** (30 characters)
- **Description**
- **Keywords** (100 characters, comma separated, no spaces)
- **Promotional text** (170 characters — changeable without a new review,
  so it is the place for "new this version")

---

## 8 · Upload and submit

1. Bump the build number in `pubspec.yaml` if you have uploaded before —
   `1.0.0+1` becomes `1.0.0+2`. Apple rejects a duplicate build number.
2. ```
   flutter build ipa --release \
     --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
     --dart-define=PRIVACY_URL=https://your-policy-url
   ```
3. Upload `build/ios/ipa/*.ipa` with **Transporter** (free, Mac App Store),
   or open the Xcode archive and distribute from there.
4. Back in App Store Connect, attach the build, the screenshots and the
   metadata, and tick the in-app purchase so it is reviewed with the app.
   **A first in-app purchase is only reviewed alongside a build** — submit
   them together or the product stays in limbo.
5. **App Review notes.** Write something like:

   > Paws Log keeps one cat free, with all reminders, medicines and records.
   > The unlock covers additional cats, prescription scanning past three,
   > and the vet summary PDF. No account is needed — please tap "Get
   > started" to create a cat. The app gives no medical advice and every
   > screen that proposes a schedule says to confirm it with a vet.

   This matters: without it a reviewer may think the app is broken because
   nothing asks them to log in.

6. Submit.

---

## What tends to go wrong first time

| Rejection | Cause |
|---|---|
| Privacy policy URL unreachable | Step 2's check skipped |
| "In-app purchase not submitted" | The product was not ticked alongside the build |
| Paywall shows no price to the reviewer | Agreement not Active, or offering not marked Current |
| Guideline 2.1 — "we could not find the feature" | No review notes explaining the free tier |

Expect one rejection. It is normal, the reply is usually specific, and the
turnaround after a fix is a day or two.

---

## Already done for you

- `ITSAppUsesNonExemptEncryption` is declared `false` in `Info.plist`, so
  uploads skip the export-compliance question. The app adds no encryption of
  its own and RevenueCat uses standard HTTPS, which is exempt.
- Camera and photo permission strings are written and say what they are for.
- Deployment target is iOS 14.0.
- App icons: all twenty, correct sizes, no alpha channel.
- The paywall already carries everything Apple requires before a purchase:
  price from the store in local currency, what it buys, Restore Purchases,
  and links to terms and privacy.
