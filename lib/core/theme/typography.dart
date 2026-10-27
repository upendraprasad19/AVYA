import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

/// Wardroom type system — three families, three voices.
///
/// * **Fraunces** (serif, variable opsz) — display / numeric. All screen
///   headers, big numbers, section leads. Tabular numerals where numbers
///   appear (weights, macros, calories, reps).
/// * **DM Sans** (neo-grotesque sans) — body / UI / paragraph copy.
/// * **JetBrains Mono** (monospace) — eyebrows, status caps, timestamps.
///
/// Legacy field names (`displayXL`, `titleM`, etc.) are preserved and
/// remapped onto the Wardroom scale so existing widgets inherit the new
/// look without touching every callsite. New Wardroom-named fields
/// (`display`, `h1`, `h2`, `h3`, `body`, `bodySm`, `mono`, `monoXs`,
/// `numeric`) are exposed for screens ported to the new system.
///
/// Source of truth: `Knowledgebase/Avya App redesign/
/// design_handoff_wardroom/readme.md` (§Design Tokens · Typography).
class AppTypography {
  AppTypography._();

  // ── Family builders ──────────────────────────────────────────────────
  static TextStyle _fraunces({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    Color color = AppColors.textPrimary,
    FontStyle? fontStyle,
    double? height,
  }) {
    return GoogleFonts.getFont(
      'Fraunces',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      fontStyle: fontStyle,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle _dmSans({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    Color color = AppColors.textPrimary,
    double? height,
  }) {
    return GoogleFonts.getFont(
      'DM Sans',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  static TextStyle _mono({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 2.0,
    Color color = AppColors.textMute,
    double? height,
  }) {
    return GoogleFonts.getFont(
      'JetBrains Mono',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  // ── Wardroom styles ──────────────────────────────────────────────────
  /// Cover headline, screen hero. Fraunces 44 / w500 / −1.2.
  static TextStyle display = _fraunces(
    fontSize: 44,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.2,
  );

  /// Screen titles. Fraunces 30 / w500 / −0.5.
  static TextStyle h1 = _fraunces(
    fontSize: 30,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.5,
  );

  /// Card titles, section leads. Fraunces 22 / w600 / −0.3.
  static TextStyle h2 = _fraunces(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  /// List item titles. Fraunces 16 / w600 / −0.2.
  static TextStyle h3 = _fraunces(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Paragraph copy. DM Sans 14 / w400.
  static TextStyle body = _dmSans(fontSize: 14, fontWeight: FontWeight.w400);

  /// Captions, meta. DM Sans 12 / w400.
  static TextStyle bodySm = _dmSans(fontSize: 12, fontWeight: FontWeight.w400);

  /// Eyebrows, status caps. JetBrains Mono 10 / w600 / +2.0.
  static TextStyle mono = _mono(fontSize: 10, fontWeight: FontWeight.w600);

  /// Timestamps, codes. JetBrains Mono 9 / w600 / +2.0.
  static TextStyle monoXs = _mono(fontSize: 9, fontWeight: FontWeight.w600);

  /// Big numbers (tabular). Fraunces 54 / w700 / −1.5.
  static TextStyle numeric = _fraunces(
    fontSize: 54,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
  );

  /// Elevated/Outlined button labels (Wardroom mono-uppercase voice).
  /// Fraunces 12 / w600 / +2.5. Used by [AppTheme] global button themes.
  static TextStyle buttonLabel = _fraunces(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.5,
  );

  /// Italic emphasis in hero headlines — gold, Fraunces italic w500.
  static TextStyle displayItalicAccent = _fraunces(
    fontSize: 44,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.2,
    color: AppColors.accent,
    fontStyle: FontStyle.italic,
  );

  // ── Legacy aliases (kept so existing screens compile; mapped to the
  //    nearest Wardroom style so the look updates in-place) ─────────────
  /// Legacy `displayXL` → Wardroom Display (Fraunces 44 / w500).
  static TextStyle displayXL = display;

  /// Legacy `displayL` → Wardroom H1 (Fraunces 30 / w500).
  static TextStyle displayL = h1;

  /// Legacy `displayM` → Wardroom H2 (Fraunces 22 / w600).
  static TextStyle displayM = h2;

  /// Legacy `titleL` → Wardroom H2.
  static TextStyle titleL = h2;

  /// Legacy `titleM` → Wardroom H3 bumped slightly for 18-px callsites.
  static TextStyle titleM = _fraunces(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Legacy `titleS` → DM Sans 15 / w600 (sits between H3 and body).
  static TextStyle titleS = _dmSans(fontSize: 15, fontWeight: FontWeight.w600);

  /// Legacy `bodyL` → DM Sans 15 / w400.
  static TextStyle bodyL = _dmSans(fontSize: 15, fontWeight: FontWeight.w400);

  /// Legacy `bodyM` → DM Sans 13 / w400.
  static TextStyle bodyM = _dmSans(fontSize: 13, fontWeight: FontWeight.w400);

  /// Legacy `bodyS` → Wardroom Body SM (DM Sans 12 / w400).
  static TextStyle bodyS = bodySm;

  /// Legacy `label` → Wardroom Mono (JB Mono 10 / w600 / +2.0).
  static TextStyle label = mono;

  /// Legacy `micro` → Wardroom Mono XS (JB Mono 9 / w600 / +2.0).
  static TextStyle micro = monoXs;

  // ── Family seed helpers (for Theme.textTheme bootstrap only) ──────────
  /// Family-only DM Sans style — no fontSize / fontWeight opinions, used
  /// when seeding [TextTheme] slots that inherit Material's default sizes.
  /// Production code should use [body] / [bodyM] / etc. instead.
  static TextStyle dmSansFamily({Color color = AppColors.textPrimary}) =>
      GoogleFonts.getFont('DM Sans', color: color);

  /// Family-only Fraunces style — display / headline TextTheme seed.
  static TextStyle frauncesFamily({Color color = AppColors.textPrimary}) =>
      GoogleFonts.getFont('Fraunces', color: color);
}
