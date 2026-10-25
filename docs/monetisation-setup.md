# Setting up purchases

The code is done and tested, but it cannot sell anything until the two
dashboards below are configured. Nothing here can be done from the repo.

Until a build is given a RevenueCat key it falls back to a stub that sells
nothing, so the app, CI and the whole test suite keep working meanwhile.

---

## 1. App Store Connect

### Before anything else

**Agreements, Tax, and Banking → Paid Applications.** The agreement must show
**Active**, with banking and tax details complete. Until it does, products
stay in "Missing Metadata", the SDK returns no offerings, and the paywall
will correctly say purchases are unavailable. This is the single most common
reason a paywall comes up empty.

### The app record

Create the app with the bundle identifier `com.malihazaman.pawsLog` — it must
match `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project exactly.

### The products

**Ship one: the lifetime unlock at $9.99.**

| Product | Type | Suggested ID | Price |
|---|---|---|---|
| Lifetime | **Non-consumable** | `com.malihazaman.pawsLog.premium.lifetime` | $9.99 |

A non-consumable, not a subscription, so it lives outside any subscription
group. The app already treats it differently: it never claims to renew.

Why one price and why that price:

- **No subscription.** The app is deliberately low-engagement — it exists so
  nobody has to think about it — and it has no servers to fund. Monthly
  billing for that invites churn, refund requests and resentment, and users
  increasingly know when there is no recurring cost behind a recurring
  charge.
- **$9.99.** Apple keeps 15% under the Small Business Program, so you net
  about $8.49. Against the $99/year developer fee that is **twelve sales a
  year to break even** — one a month, which is a number you can believe in
  from a first release with no reviews. $24.99 would need five, but each one
  asks a stranger for $25 on an app they found yesterday.
- **Raise it later, not lower.** Buyers of a non-consumable keep what they
  bought, so a price rise is easy once there are reviews to justify it.
  Going down is the move you cannot take back.
- Use **per-territory pricing** to come down in South Asia and Latin America.
  $10 is a different proposition in Dhaka than in Munich.

You may still want to create the monthly and yearly subscriptions in App
Store Connect without putting them in the offering. RevenueCat offerings are
server-side, so they could be tested later without shipping a release. That
is an experiment, not the launch.

The product needs a price and a localised display name and description for
every language you ship.

### What the money is for

Three things, and they hang off one idea: **one cat free, the whole household
paid.**

| Paid | |
|---|---|
| A second pet and beyond | The gate owners find fairest, and multi-cat households get the most value |
| Scanning past the first 3 prescriptions | The headline feature. Let them feel it work, then charge |
| The vet summary PDF | A discrete thing you hand over at the appointment |

Everything else is free, including all reminders and notifications, medicines
and doses, the photo album, vet visits **and their photos**, weight, the
health record, and backup export and import.

Photos on a visit used to be paid. That stopped making sense the day the
photo album became free and unlimited: an owner who can keep five hundred
pictures of their cat but not attach one to the visit it belongs to reads
that as arbitrary, and is right to.

### Privacy and terms

- **Privacy Policy URL** is required for any app that sells anything.
  `docs/privacy-policy.md` is written to match what the app actually does —
  fill in the support email, then publish it. GitHub Pages costs nothing:
  turn it on for this repo and the URL is
  `https://<user>.github.io/<repo>/privacy-policy`. Pass the same URL to the
  build as `--dart-define=PRIVACY_URL=...`, since the paywall links to it.

- **App Privacy** (the nutrition label) has to be filled in by hand. What the
  app does:

  | Question | Answer |
  |---|---|
  | Data used to track you | **None.** No ads, no advertising identifier, no data shared with brokers |
  | Data linked to you | **None.** There is no account, so nothing is linked to an identity |
  | Data *not* linked to you | **Purchases → Purchase History**, for app functionality. That is RevenueCat validating a receipt |

  Everything the owner enters — pets, photos, prescriptions, weights — never
  leaves the device, so none of it is "collected" in Apple's sense and none
  of it is declared. Photos and camera are *permissions*, not collection.

  RevenueCat publishes its own App Privacy guidance for the exact boxes its
  SDK requires; follow theirs over this table if the two disagree, because
  it changes when their SDK does.
- **Terms of Use (EULA).** Apple's standard EULA is the default in the app.
  If you use your own, set `TERMS_URL` at build time and also paste it into
  App Store Connect.

### Credentials RevenueCat needs

- **App-Specific Shared Secret** — App Information → App-Specific Shared
  Secret.
- **In-App Purchase Key** — Users and Access → Integrations → In-App
  Purchase. Download the `.p8` once (you cannot download it again) and note
  the Key ID and Issuer ID.
- **App Store Server Notifications V2** — set the Production and Sandbox URLs
  to the ones RevenueCat gives you. Without this, renewals, cancellations and
  refunds reach the app late or not at all.

### Testing accounts

Users and Access → **Sandbox Testers**. Use an email you do not already use
for an Apple Account. On the device, sign out of the App Store first;
purchases will then prompt for the sandbox account.

---

## 2. RevenueCat

1. **Create a project**, then add an **App Store** app with the same bundle
   identifier.
2. Upload the **shared secret** and the **In-App Purchase key** (`.p8`, Key
   ID, Issuer ID).
3. Copy RevenueCat's **server notification URL** back into App Store Connect
   (above).
4. **Products** — import the three product IDs from App Store Connect.
5. **Entitlements** — create one called **`premium`** and attach *all three*
   products to it.

   This matters: the app asks one question — is `premium` active — and never
   which plan paid for it. That is what makes upgrading from monthly to
   lifetime a non-event in the code. If you name it something else, pass
   `--dart-define=REVENUECAT_ENTITLEMENT=<name>`.

6. **Offerings** — create one (`default` is fine) and mark it **Current**,
   with three packages using the **standard identifiers**:

   | Package | Attach |
   |---|---|
   | `$rc_monthly` | the monthly subscription |
   | `$rc_annual` | the yearly subscription |
   | `$rc_lifetime` | the lifetime non-consumable |

   The app maps those three package types to the plans it shows. A custom
   package identifier will be ignored rather than shown as something the
   owner cannot understand — so if you use custom ones, update `_kindOf` in
   `lib/services/entitlements/revenuecat_entitlements.dart`.

7. **API keys** — copy the **public** Apple SDK key (starts with `appl_`).
   It is safe in a client. Never put a secret key in the app.

---

## 3. Building with the keys

Keys are passed at build time and never committed:

```sh
flutter run \
  --dart-define=REVENUECAT_IOS_KEY=appl_xxxxxxxxxxxx \
  --dart-define=PRIVACY_URL=https://example.com/privacy
```

Optional: `REVENUECAT_ENTITLEMENT` (default `premium`),
`REVENUECAT_OFFERING` (default: whichever is Current), `TERMS_URL` (default:
Apple's standard EULA), `REVENUECAT_ANDROID_KEY`.

For CI and release builds, put these in your build configuration — an Xcode
scheme, a Codemagic/Fastlane environment, or whatever you use — not in the
repo.

---

## 4. What to check before submitting

The paywall already carries everything Apple requires, but it is worth
reading it on a device once the real products load:

- [ ] Each plan shows its **title, duration and price**, in the store's own
      localised currency.
- [ ] Subscriptions say they **renew automatically until cancelled**;
      lifetime says it does not.
- [ ] **Restore purchases** is reachable without buying anything.
- [ ] **Terms of Use** and **Privacy Policy** links open.
- [ ] Buying, then deleting and reinstalling the app, then **Restore**, gets
      access back.
- [ ] With the device in airplane mode, a paying owner is still unlocked —
      the entitlement is cached for exactly this.

---

## 5. Android, if you go there

The code already supports it: pass `REVENUECAT_ANDROID_KEY` and configure a
Play Console app in the same RevenueCat project, with its own products
attached to the same `premium` entitlement. Play requires its own service
account credentials, which RevenueCat's dashboard walks through.
