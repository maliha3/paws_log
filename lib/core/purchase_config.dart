/// Store and RevenueCat configuration.
///
/// Keys come from `--dart-define` and are never committed. A build with no
/// key falls back to the stub entitlement source, so development, CI and the
/// whole test suite keep working without credentials — and so a missing key
/// can never be mistaken for a working store.
abstract final class PurchaseConfig {
  /// RevenueCat public SDK key for Apple platforms.
  ///
  ///     flutter run --dart-define=REVENUECAT_IOS_KEY=appl_xxx
  static const String iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
  );

  /// RevenueCat public SDK key for Google Play.
  static const String androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// The entitlement identifier configured in the RevenueCat dashboard.
  ///
  /// Every product — monthly, yearly and lifetime — must grant this one
  /// entitlement, which is what the app actually checks.
  static const String entitlementId = String.fromEnvironment(
    'REVENUECAT_ENTITLEMENT',
    defaultValue: 'premium',
  );

  /// The offering identifier to show on the paywall. Empty means whichever
  /// offering is marked current in the dashboard, which is the normal case.
  static const String offeringId = String.fromEnvironment(
    'REVENUECAT_OFFERING',
  );

  /// Apple requires a link to the terms the subscription is sold under.
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

  /// Whether this build can actually sell anything.
  static bool get hasStoreKeys =>
      iosApiKey.isNotEmpty || androidApiKey.isNotEmpty;
}
