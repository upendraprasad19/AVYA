import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTypography {
  AppTypography._();

  static TextStyle _font({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.getFont(
      'DM Sans',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // Display
  static TextStyle displayXL = _font(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1);
  static TextStyle displayL = _font(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 0.5);
  static TextStyle displayM = _font(fontSize: 28, fontWeight: FontWeight.w900);

  // Title
  static TextStyle titleL = _font(fontSize: 22, fontWeight: FontWeight.w800);
  static TextStyle titleM = _font(fontSize: 18, fontWeight: FontWeight.w800);
  static TextStyle titleS = _font(fontSize: 15, fontWeight: FontWeight.w700);

  // Body
  static TextStyle bodyL = _font(fontSize: 15, fontWeight: FontWeight.w400);
  static TextStyle bodyM = _font(fontSize: 13, fontWeight: FontWeight.w400);
  static TextStyle bodyS = _font(fontSize: 12, fontWeight: FontWeight.w400);

  // Label & Micro
  static TextStyle label = _font(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textSecondary);
  static TextStyle micro = _font(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary);
}
