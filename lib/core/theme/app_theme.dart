import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';
import 'spacing.dart';

/// Wardroom ThemeData — wired to the navy / parchment / Campaign-Gold
/// tokens in [AppColors], the 3-font system in [AppTypography], and the
/// sharp-corner [AppRadius] scale.
///
/// Buttons adopt Wardroom's mono uppercase voice (Fraunces w600, +2.5
/// letter-spacing, sharp 2-px radius). The global TextTheme routes
/// display / headline styles to Fraunces (serif) while body and label
/// slots remain DM Sans — callers expecting the old DM-Sans display get
/// a serif instead, which is the intended personality shift.
class AppTheme {
  AppTheme._();

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.bg,
      primary: AppColors.accent,
      secondary: AppColors.accentDeep,
      error: AppColors.bad,
      onPrimary: AppColors.bgDeep,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: _buildTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgDeep,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.line2, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgRaise,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.soft),
        borderSide: const BorderSide(color: AppColors.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.soft),
        borderSide: const BorderSide(color: AppColors.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.soft),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bgDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.getFont(
          'Fraunces',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.accent, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.getFont(
          'Fraunces',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.5,
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bgDeep,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textMute,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line2,
      thickness: 1,
    ),
  );

  /// Global text theme. Display / headline slots use Fraunces (serif);
  /// body / label slots use DM Sans. Widgets that read `Theme.of(context)
  /// .textTheme.headlineMedium` etc. now inherit the new serif voice.
  static TextTheme _buildTextTheme() {
    TextStyle fraunces({Color color = AppColors.textPrimary}) =>
        GoogleFonts.getFont('Fraunces', color: color);
    TextStyle dmSans({Color color = AppColors.textPrimary}) =>
        GoogleFonts.getFont('DM Sans', color: color);

    return TextTheme(
      displayLarge: fraunces(),
      displayMedium: fraunces(),
      displaySmall: fraunces(),
      headlineLarge: fraunces(),
      headlineMedium: fraunces(),
      headlineSmall: fraunces(),
      titleLarge: fraunces(),
      titleMedium: fraunces(),
      titleSmall: dmSans(),
      bodyLarge: dmSans(),
      bodyMedium: dmSans(),
      bodySmall: dmSans(color: AppColors.textDim),
      labelLarge: dmSans(),
      labelMedium: dmSans(color: AppColors.textDim),
      labelSmall: dmSans(color: AppColors.textMute),
    );
  }
}
