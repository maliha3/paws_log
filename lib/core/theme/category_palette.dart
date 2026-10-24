import 'package:flutter/material.dart';

import '../../domain/models/reminder.dart';

/// The soft colours that carry information without shouting.
///
/// A theme extension rather than constants scattered through the widgets, so
/// the "colours come from the theme only" rule still holds and dark mode gets
/// its own steps instead of an automatic flip of the light ones.
@immutable
class CategoryPalette extends ThemeExtension<CategoryPalette> {
  const CategoryPalette({
    required this.vaccine,
    required this.deworming,
    required this.fleaTick,
    required this.nailTrim,
    required this.brushing,
    required this.other,
    required this.medicine,
    required this.pastels,
    required this.onPastel,
  });

  /// Light mode: saturated enough to read on cream.
  static const CategoryPalette light = CategoryPalette(
    vaccine: Color(0xFF4F7BC9),
    deworming: Color(0xFF2E9177),
    fleaTick: Color(0xFFE08A2E),
    nailTrim: Color(0xFFC2607A),
    brushing: Color(0xFF3F8EA3),
    other: Color(0xFF8A7868),
    medicine: Color(0xFF8A6BC4),
    pastels: [
      Color(0xFFEDE6FA), // lavender
      Color(0xFFFBF0CE), // butter
      Color(0xFFDFF0E4), // mint
      Color(0xFFFBE2D2), // peach
    ],
    onPastel: Color(0xFF3A2E26),
  );

  /// Dark mode: lifted and desaturated, so nothing glows.
  static const CategoryPalette dark = CategoryPalette(
    vaccine: Color(0xFF8FB2EE),
    deworming: Color(0xFF6DCDAE),
    fleaTick: Color(0xFFF2B263),
    nailTrim: Color(0xFFE79BB0),
    brushing: Color(0xFF7FC3D6),
    other: Color(0xFFC2B2A3),
    medicine: Color(0xFFBCA4EA),
    pastels: [
      Color(0xFF332C45),
      Color(0xFF3B3524),
      Color(0xFF24362C),
      Color(0xFF3E2E25),
    ],
    onPastel: Color(0xFFF3E9E0),
  );

  final Color vaccine;
  final Color deworming;
  final Color fleaTick;
  final Color nailTrim;
  final Color brushing;
  final Color other;

  /// Medicines are not a reminder category, but they share the row language.
  final Color medicine;

  /// Backgrounds for small fact chips, used in a fixed order so the same
  /// fact keeps the same colour rather than shuffling as facts appear.
  final List<Color> pastels;

  /// Readable on any pastel.
  final Color onPastel;

  Color of(ReminderCategory category) => switch (category) {
    ReminderCategory.vaccine => vaccine,
    ReminderCategory.deworming => deworming,
    ReminderCategory.fleaTick => fleaTick,
    ReminderCategory.nailTrim => nailTrim,
    ReminderCategory.brushing => brushing,
    ReminderCategory.other => other,
  };

  Color pastel(int index) => pastels[index % pastels.length];

  @override
  CategoryPalette copyWith({
    Color? vaccine,
    Color? deworming,
    Color? fleaTick,
    Color? nailTrim,
    Color? brushing,
    Color? other,
    Color? medicine,
    List<Color>? pastels,
    Color? onPastel,
  }) => CategoryPalette(
    vaccine: vaccine ?? this.vaccine,
    deworming: deworming ?? this.deworming,
    fleaTick: fleaTick ?? this.fleaTick,
    nailTrim: nailTrim ?? this.nailTrim,
    brushing: brushing ?? this.brushing,
    other: other ?? this.other,
    medicine: medicine ?? this.medicine,
    pastels: pastels ?? this.pastels,
    onPastel: onPastel ?? this.onPastel,
  );

  @override
  CategoryPalette lerp(ThemeExtension<CategoryPalette>? other, double t) {
    if (other is! CategoryPalette) {
      return this;
    }
    return CategoryPalette(
      vaccine: Color.lerp(vaccine, other.vaccine, t)!,
      deworming: Color.lerp(deworming, other.deworming, t)!,
      fleaTick: Color.lerp(fleaTick, other.fleaTick, t)!,
      nailTrim: Color.lerp(nailTrim, other.nailTrim, t)!,
      brushing: Color.lerp(brushing, other.brushing, t)!,
      other: Color.lerp(this.other, other.other, t)!,
      medicine: Color.lerp(medicine, other.medicine, t)!,
      pastels: [
        for (var i = 0; i < pastels.length; i++)
          Color.lerp(pastels[i], other.pastels[i], t)!,
      ],
      onPastel: Color.lerp(onPastel, other.onPastel, t)!,
    );
  }
}

/// Reads the soft palette off the current theme.
extension CategoryPaletteOf on BuildContext {
  CategoryPalette get categories =>
      Theme.of(this).extension<CategoryPalette>() ?? CategoryPalette.light;
}
