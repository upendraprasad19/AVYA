import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Daily quote card — matches the handoff
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 288–305).
///
/// `cardHi` background with a 2-px gold left border and `radSharp`
/// corners. Fraunces 14 italic quote body + mono 9 gold attribution
/// with `— AUTHOR` prefix.
class QuoteCard extends StatelessWidget {
  final String quote;
  final String author;

  const QuoteCard({
    super.key,
    required this.quote,
    required this.author,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.cardHi,
        border: const Border(
          left: BorderSide(color: AppColors.accent, width: 2),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"$quote"',
            style: AppTypography.h3.copyWith(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
              height: 1.45,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: AppSpacing.stackS),
          Text(
            '\u2014 ${author.toUpperCase()}',
            style: AppTypography.monoXs.copyWith(
              fontSize: 9,
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
