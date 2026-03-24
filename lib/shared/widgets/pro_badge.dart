import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Small Champion Gold badge that displays "PRO".
///
/// Use next to feature names or user avatars to indicate PRO status.
///
/// ```dart
/// Row(children: [
///   Text('AI Coach'),
///   const SizedBox(width: 6),
///   const ProBadge(),
/// ]);
/// ```
class ProBadge extends StatelessWidget {
  /// Optional custom size multiplier. Defaults to 1.0.
  final double scale;

  const ProBadge({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scale,
        vertical: 3 * scale,
      ),
      decoration: BoxDecoration(
        color: AppColors.proGold,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        boxShadow: [
          BoxShadow(
            color: AppColors.proGold.withValues(alpha: 0.3),
            blurRadius: 6 * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 9 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          color: Colors.black,
          height: 1,
        ),
      ),
    );
  }
}
