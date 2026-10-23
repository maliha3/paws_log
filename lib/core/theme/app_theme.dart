import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'category_palette.dart';

/// The app's look: one warm green brand, a friendly rounded face, and
/// surfaces soft enough that a list of medical reminders does not read like a
/// hospital form.
abstract final class AppTheme {
  /// The brand green. Warm rather than clinical.
  static const Color _brand = Color(0xFF2E7D63);

  /// A warm accent, for highlights and anything worth drawing the eye to.
  static const Color _accent = Color(0xFFE09B4A);

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
          // Keep Material's harmony, but make the accent the one it reaches
          // for rather than a hue derived from the green.
          tertiary: _accent,
          onTertiary: isLight ? Colors.white : const Color(0xFF2A1A05),
          // A hint of green in the background, so the app never looks like
          // plain white paper.
          surface: isLight ? const Color(0xFFF7FAF8) : const Color(0xFF101614),
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
