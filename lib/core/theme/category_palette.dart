import 'package:flutter/material.dart';

import '../../domain/models/reminder.dart';

/// Colours that identify a kind of care.
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
    required this.other,
    required this.medicine,
    required this.onCategory,
  });

  /// Lighter, warmer steps: these sit on a dark surface.
  static const CategoryPalette dark = CategoryPalette(
    vaccine: Color(0xFF7FB3F5),
    deworming: Color(0xFF6ED3B5),
    fleaTick: Color(0xFFF2B263),
    other: Color(0xFFB8C4BE),
    medicine: Color(0xFFC3A6F0),
    onCategory: Color(0xFF10201A),
  );

  /// Deeper steps, for contrast against a light surface.
  static const CategoryPalette light = CategoryPalette(
    vaccine: Color(0xFF2C6DB5),
    deworming: Color(0xFF1C8268),
    fleaTick: Color(0xFFB9742A),
    other: Color(0xFF5C6B64),
    medicine: Color(0xFF6E4BA8),
    onCategory: Color(0xFFFFFFFF),
  );

  final Color vaccine;
  final Color deworming;
  final Color fleaTick;
  final Color other;

  /// Medicines are not a reminder category, but they share the row language.
  final Color medicine;

  /// Readable on any of the above.
  final Color onCategory;

  Color of(ReminderCategory category) => switch (category) {
    ReminderCategory.vaccine => vaccine,
    ReminderCategory.deworming => deworming,
    ReminderCategory.fleaTick => fleaTick,
    ReminderCategory.other => other,
  };

  @override
  CategoryPalette copyWith({
    Color? vaccine,
    Color? deworming,
    Color? fleaTick,
    Color? other,
    Color? medicine,
    Color? onCategory,
  }) => CategoryPalette(
    vaccine: vaccine ?? this.vaccine,
    deworming: deworming ?? this.deworming,
    fleaTick: fleaTick ?? this.fleaTick,
    other: other ?? this.other,
    medicine: medicine ?? this.medicine,
    onCategory: onCategory ?? this.onCategory,
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
      other: Color.lerp(this.other, other.other, t)!,
      medicine: Color.lerp(medicine, other.medicine, t)!,
      onCategory: Color.lerp(onCategory, other.onCategory, t)!,
    );
  }
}

/// Reads the category colours off the current theme.
extension CategoryPaletteOf on BuildContext {
  CategoryPalette get categories =>
      Theme.of(this).extension<CategoryPalette>() ?? CategoryPalette.light;
}
