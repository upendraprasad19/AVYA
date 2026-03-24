import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';

/// Weekly Nutrition Report card.
///
/// First report is free (after Week 1 of usage).
/// Ongoing weekly reports require PRO (`weekly_ai_report`).
class WeeklyReportCard extends StatelessWidget {
  final bool isPro;
  final int usageWeeks;
  final bool hasFirstReport;
  final VoidCallback onViewReport;
  final VoidCallback onUpgradeTap;

  const WeeklyReportCard({
    super.key,
    required this.isPro,
    required this.usageWeeks,
    required this.hasFirstReport,
    required this.onViewReport,
    required this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    // Compute report data from Hive
    final reportData = _computeReportData();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Weekly Report',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (!isPro && hasFirstReport) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.proGold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PRO',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.proGold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      usageWeeks < 1
                          ? 'Available after Week 1'
                          : hasFirstReport && !isPro
                              ? 'Upgrade for weekly reports'
                              : 'Nutrition insights',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Report content
          if (usageWeeks >= 1) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),

            // Report summary
            _buildReportRow(
              'Avg Calories',
              reportData['avgCalories'] ?? '--',
              'vs target',
              reportData['calTarget'] ?? '--',
            ),
            const SizedBox(height: 8),
            _buildReportRow(
              'Protein Consistency',
              reportData['proteinDays'] ?? '0/7',
              'days on target',
              null,
            ),
            const SizedBox(height: 8),
            _buildReportRow(
              'Best Day',
              reportData['bestDay'] ?? '--',
              null,
              null,
            ),

            const SizedBox(height: 12),

            // CTA
            GestureDetector(
              onTap: () {
                if (isPro || !hasFirstReport) {
                  onViewReport();
                } else {
                  onUpgradeTap();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isPro || !hasFirstReport
                      ? AppColors.accentTint
                      : AppColors.proGoldTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPro || !hasFirstReport
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : AppColors.proGold.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    isPro || !hasFirstReport
                        ? 'View Full Report'
                        : 'Upgrade for Weekly Reports',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isPro || !hasFirstReport
                          ? AppColors.accent
                          : AppColors.proGold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportRow(
      String label, String value, String? suffix, String? extra) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text(
            suffix,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (extra != null) ...[
          const SizedBox(width: 4),
          Text(
            extra,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Map<String, String> _computeReportData() {
    return NutritionRepository.instance.computeWeeklyReportData();
  }
}
