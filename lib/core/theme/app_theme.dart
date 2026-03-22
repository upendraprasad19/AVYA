import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.bg,
      primary: AppColors.accent,
      secondary: AppColors.accentDark,
      error: AppColors.red,
      onPrimary: Colors.black,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: _buildTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.header,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.input,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: GoogleFonts.getFont(
          'Switzer',
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3), width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: GoogleFonts.getFont(
          'Switzer',
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.header,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textSecondary,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
    ),
  );

  static TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      displayMedium: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      displaySmall: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      headlineLarge: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      headlineMedium: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      headlineSmall: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      titleLarge: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      titleMedium: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      titleSmall: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      bodyLarge: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      bodyMedium: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      bodySmall: GoogleFonts.getFont('Switzer', color: AppColors.textSecondary),
      labelLarge: GoogleFonts.getFont('Switzer', color: AppColors.textPrimary),
      labelMedium: GoogleFonts.getFont('Switzer', color: AppColors.textSecondary),
      labelSmall: GoogleFonts.getFont('Switzer', color: AppColors.textSecondary),
    );
  }
}
