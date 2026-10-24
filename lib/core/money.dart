import 'dart:io';

import 'package:intl/intl.dart';

/// Money in the owner's own currency.
///
/// The app stores an amount as an integer of the smallest unit and keeps no
/// currency alongside it. This is one owner's personal log, in whatever money
/// they spend, so the device's locale decides both the symbol and how many
/// decimal places there are — which matters, because a yen has none and a
/// dinar has three.
abstract final class Money {
  static NumberFormat _format([String? locale]) =>
      NumberFormat.simpleCurrency(locale: locale ?? Platform.localeName);

  /// How many minor units make one whole unit here.
  static int minorUnits([String? locale]) {
    final digits = _format(locale).decimalDigits ?? 2;
    var factor = 1;
    for (var step = 0; step < digits; step++) {
      factor *= 10;
    }
    return factor;
  }

  /// "£42.50", for display.
  static String format(int amount, [String? locale]) =>
      _format(locale).format(amount / minorUnits(locale));

  /// The currency symbol on its own, for a field prefix.
  static String symbol([String? locale]) => _format(locale).currencySymbol;

  /// Parses what the owner typed, or null if it is not a number.
  ///
  /// Both separators are accepted: a field prefixed with a currency symbol is
  /// obviously money, and refusing "42,50" from someone whose keyboard gives
  /// a comma would be pedantry.
  static int? parse(String input, [String? locale]) {
    final cleaned = input.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    final value = double.tryParse(cleaned);
    if (value == null || value < 0) {
      return null;
    }
    return (value * minorUnits(locale)).round();
  }

  /// What to put in a text field for an amount already stored.
  static String edit(int amount, [String? locale]) {
    final units = minorUnits(locale);
    final digits = units == 1 ? 0 : units.toString().length - 1;
    return (amount / units).toStringAsFixed(digits);
  }
}
