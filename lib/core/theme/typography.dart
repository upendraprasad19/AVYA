import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTypography {
  AppTypography._();

  static TextStyle _switzer({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.getFont(
      'Switzer',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // Display
  static TextStyle displayXL = _switzer(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1);
  static TextStyle displayL = _switzer(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 0.5);
  static TextStyle displayM = _switzer(fontSize: 28, fontWeight: FontWeight.w900);

  // Title
  static TextStyle titleL = _switzer(fontSize: 22, fontWeight: FontWeight.w800);
  static TextStyle titleM = _switzer(fontSize: 18, fontWeight: FontWeight.w800);
  static TextStyle titleS = _switzer(fontSize: 15, fontWeight: FontWeight.w700);

  // Body
  static TextStyle bodyL = _switzer(fontSize: 15, fontWeight: FontWeight.w400);
  static TextStyle bodyM = _switzer(fontSize: 13, fontWeight: FontWeight.w400);
  static TextStyle bodyS = _switzer(fontSize: 12, fontWeight: FontWeight.w400);

  // Label & Micro
  static TextStyle label = _switzer(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textSecondary);
  static TextStyle micro = _switzer(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary);
}
