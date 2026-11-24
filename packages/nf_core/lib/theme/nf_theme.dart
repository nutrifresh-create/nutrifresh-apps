import 'package:flutter/material.dart';

enum NfUiStyle { natural, glass }

class NfColors {
  static const Color green = Color(0xFF7CB342);
  static const Color greenDark = Color(0xFF558B2F);
  static const Color brown = Color(0xFF936C38);
  static const Color lightBg = Color(0xFFF4F9F1);
  static const Color naturalSurface = Color(0xFFF1F5F9);
  static const Color glassBg = Color(0xFFE4EFE8);
  static const Color darkBg = Color(0xFF0B1120);
  static const Color darkCard = Color(0xFF111827);
  static const Color amber = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
}

class NfTheme {
  static ThemeData light({NfUiStyle style = NfUiStyle.natural}) {
    final isGlass = style == NfUiStyle.glass;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NfColors.green,
      primary: NfColors.green,
      secondary: NfColors.brown,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isGlass ? NfColors.glassBg : NfColors.naturalSurface,
      appBarTheme: AppBarTheme(
        backgroundColor: isGlass
            ? Colors.white.withAlpha(215)
            : Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NfColors.green, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NfColors.green,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Tema Dark untuk NutriFresh Office (.exe)
  static ThemeData darkOffice() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NfColors.green,
      primary: NfColors.green,
      secondary: NfColors.amber,
      surface: NfColors.darkCard,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NfColors.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: NfColors.darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
