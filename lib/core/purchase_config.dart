import 'package:flutter/foundation.dart';

/// What the app sells, and the links Apple requires beside it.
///
/// There is no store key here any more. The app sells one non-consumable
/// straight through StoreKit, so Apple is the only party involved: no
/// receipt server, no SDK key, nothing to configure but the product id —
/// which is public by nature, since the store needs it to show a price.
abstract final class PurchaseConfig {
  /// The one thing on sale, as created in App Store Connect.
  ///
  /// Overridable at build time only so a test build can point at a different
  /// product; there is no secret here and no reason to keep it out of the
  /// repository.
  static const String unlockProductId = String.fromEnvironment(
    'UNLOCK_PRODUCT_ID',
    defaultValue: 'com.malihazaman.pawsLog.premium.lifetime',
  );

  /// Apple requires a link to the terms the purchase is made under.
  ///
  /// Apple's standard EULA is the default, and is acceptable when you have
  /// not written your own. Replace it if you have.
  static const String termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue:
        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
  );

  /// Apple requires a privacy policy link on the paywall and in App Store
  /// Connect. There is no sensible default: this one must be your own.
  static const String privacyUrl = String.fromEnvironment('PRIVACY_URL');

  /// Whether this build talks to Apple's store at all.
  ///
  /// **Release builds sell; debug builds do not.** Under RevenueCat this was
  /// decided by whether an API key had been passed, which gave the useful
  /// property that a missing key could never be mistaken for a working
  /// store. StoreKit needs no key, so the build mode carries that instead —
  /// and the result is one fewer thing to remember, because the builds that
  /// should sell are exactly the ones that are released.
  ///
  /// Tests and CI run in debug and get the stub, which sells nothing. A
  /// debug build on a real device can opt in with
  /// `--dart-define=PAWSLOG_STORE_ENABLED=true`, though sandbox purchases
  /// are better tested against a release build anyway.
  static bool get sellsThroughStore => kReleaseMode || _storeOverride;

  static const bool _storeOverride = bool.fromEnvironment(
    'PAWSLOG_STORE_ENABLED',
  );
}
