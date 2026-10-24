/// When cats shed heavily, and what to call it.
library;

/// Which half of the world the owner lives in.
///
/// It names the seasons; it does not move them — see [inSheddingSeason].
enum Hemisphere {
  northern('Northern'),
  southern('Southern');

  const Hemisphere(this.label);

  final String label;

  static Hemisphere fromName(String name) =>
      Hemisphere.values.firstWhere((hemisphere) => hemisphere.name == name);
}

/// Whether [date] falls in a shedding window: March–May or September–November.
///
/// **The same months in both hemispheres.** Shedding is driven by daylight
/// and turns at the equinoxes, which fall in March and September everywhere.
/// A northern cat sheds its winter coat in spring (March–May) and grows one
/// in autumn (September–November); a southern cat does the same thing in the
/// same two windows, which are simply its autumn and its spring.
///
/// That is why this takes no [Hemisphere]: the setting changes what each
/// window is *called*, nothing else. Pretending otherwise would mean telling
/// a southern owner their cat sheds in December.
bool inSheddingSeason(DateTime date) {
  final month = date.month;
  return (month >= 3 && month <= 5) || (month >= 9 && month <= 11);
}

/// What to call the window [date] falls in, or null outside one.
String? sheddingWindowLabel(DateTime date, Hemisphere hemisphere) {
  if (!inSheddingSeason(date)) {
    return null;
  }
  final isFirstWindow = date.month <= 5;
  final isSpring = hemisphere == Hemisphere.northern
      ? isFirstWindow
      : !isFirstWindow;
  return isSpring ? 'Spring shedding' : 'Autumn shedding';
}
