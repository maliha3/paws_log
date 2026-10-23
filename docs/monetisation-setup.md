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

### The three products

Create a **subscription group** (name it something like "PawsLog Premium"),
then inside it:

| Product | Type | Suggested ID | Duration |
|---|---|---|---|
| Monthly | Auto-renewable subscription | `com.malihazaman.pawsLog.premium.monthly` | 1 month |
| Yearly | Auto-renewable subscription | `com.malihazaman.pawsLog.premium.yearly` | 1 year |
| Lifetime | **Non-consumable** | `com.malihazaman.pawsLog.premium.lifetime` | — |

Lifetime is a non-consumable, not a subscription, and lives outside the
subscription group. The app already treats it differently: it never claims to
renew.

Each product needs a price, and a localised display name and description for
every language you ship. Each subscription also needs a review screenshot.

### Privacy and terms

- **App Privacy** must be filled in, and the **Privacy Policy URL** is
  required for any app that sells a subscription. You need a real URL; there
  is no sensible default and the app does not ship one.
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
