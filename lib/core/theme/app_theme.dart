import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'category_palette.dart';

/// The app's look: one warm green brand, a friendly rounded face, and
/// surfaces soft enough that a list of medical reminders does not read like a
/// hospital form.
abstract final class AppTheme {
  /// Warm amber. The app is about a pet, not a patient.
  static const Color _brand = Color(0xFFEE9A3A);

  /// Near-black with a brown cast, for type and the solid controls. The
  /// contrast against cream is what stops the warm palette going mushy.
  static const Color _ink = Color(0xFF2A211B);

  /// Cream, not white. A white screen is what made this look like a form.
  static const Color _cream = Color(0xFFFDF6EE);
  static const Color _creamDeep = Color(0xFF17120F);

  static const String _fontFamily = 'Nunito';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _brand,
          brightness: brightness,
        ).copyWith(
          primary: _brand,
          onPrimary: _ink,
          // The solid, confident control colour — the dark pill in the
          // reference, not the amber.
          secondary: isLight ? _ink : const Color(0xFFF3E7DC),
          onSecondary: isLight ? _cream : _ink,
          surface: isLight ? _cream : _creamDeep,
          onSurface: isLight ? _ink : const Color(0xFFF3E7DC),
          surfaceContainerLow: isLight
              ? const Color(0xFFFFFCF8)
              : const Color(0xFF221A15),
          surfaceContainerHighest: isLight
              ? const Color(0xFFF6EADC)
              : const Color(0xFF2C2219),
          outlineVariant: isLight
              ? const Color(0xFFEADCCB)
              : const Color(0xFF3A2E25),
        );

    final text = _textTheme(scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [isLight ? CategoryPalette.light : CategoryPalette.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: _style(16, 700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: _style(15, 600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: _style(15, 700)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? Colors.white
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.primary, width: 2),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 0.6 : 0.3),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(_style(12, 700)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      // One curve for the whole app, so nothing feels like it belongs to a
      // different product.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );

  /// Nunito is a variable font, so weight is an axis rather than a file.
  /// `fontWeight` alone would be ignored; `fontVariations` is what moves it.
  static TextStyle _style(double size, int weight, {double? height}) =>
      TextStyle(
        fontSize: size,
        height: height,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation('wght', weight.toDouble())],
      );

  static TextTheme _textTheme(ColorScheme scheme) => TextTheme(
    displaySmall: _style(34, 800, height: 1.15),
    headlineMedium: _style(26, 800, height: 1.2),
    headlineSmall: _style(23, 800, height: 1.2),
    titleLarge: _style(20, 700),
    titleMedium: _style(16, 700),
    labelLarge: _style(14, 700),
    labelMedium: _style(12, 700),
    labelSmall: _style(11, 700),
    bodyLarge: _style(16, 400, height: 1.45),
    bodyMedium: _style(14, 400, height: 1.45),
    bodySmall: _style(13, 400, height: 1.35),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}
