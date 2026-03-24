import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Compact AI Coach insight card — title merged inside, no avatar/header row,
/// no protein bar. Minimal vertical footprint.
class AiInsightCard extends StatelessWidget {
  final String? insight;
  final String userName;
  final double proteinCurrent;
  final double proteinTarget;

  const AiInsightCard({
    super.key,
    this.insight,
    this.userName = 'there',
    this.proteinCurrent = 0,
    this.proteinTarget = 184,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Merged header: label + live dot in one row
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'AI COACH INSIGHTS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Insight text
          if (insight != null)
            Text(
              insight!,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              'Start a conversation with your AI coach for personalised tips!',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '\u{1F4A1} Quick wins: 3 eggs = 18g \u00B7 100g chicken = 31g \u00B7 1 scoop whey = 25g \u00B7 200g paneer = 36g',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
