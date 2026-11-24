import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum NfUiStyle { natural, glass }

class NfColors {
  static const Color green = Color(0xFF7CB342);
  static const Color greenDark = Color(0xFF558B2F);
  static const Color brown = Color(0xFF936C38);
  static const Color lightBg = Color(0xFFF4F9F1);
  static const Color naturalSurface = Color(0xFFF4F7F5);
  static const Color glassBg = Color(0xFFE4EFE8);
  static const Color darkBg = Color(0xFF0B1120);
  static const Color darkCard = Color(0xFF111827);
  static const Color amber = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
}

class NfTheme {
  static ThemeData light({NfUiStyle style = NfUiStyle.glass}) {
    final isGlass = style == NfUiStyle.glass;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NfColors.green,
      primary: NfColors.green,
      secondary: NfColors.brown,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isGlass ? Colors.white.withAlpha(220) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isGlass ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isGlass ? const Color(0xFFCBD5E1).withAlpha(170) : const Color(0xFFD5E0D9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NfColors.green, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NfColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NfColors.darkBg,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: NfColors.darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
