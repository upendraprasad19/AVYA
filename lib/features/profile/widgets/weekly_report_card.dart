import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

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
    final needsPaywall = !isPro && hasFirstReport;

    return WardCard(
      variant: WardCardVariant.hero,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Letterhead header: eyebrow + title + optional PRO chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WEEKLY REPORT',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      usageWeeks < 1
                          ? 'Available after Week 1'
                          : needsPaywall
                              ? 'Upgrade for weekly reports'
                              : 'Nutrition insights',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (needsPaywall)
                const WardChip(label: 'PRO', tone: WardChipTone.gold),
            ],
          ),

          // Report content
          if (usageWeeks >= 1) ...[
            const SizedBox(height: 14),
            const WardRule(gold: true, margin: EdgeInsets.zero),
            const SizedBox(height: 4),

            WardKvRow(
              label: 'Avg Calories',
              value: _combine(
                reportData['avgCalories'] ?? '--',
                'vs target',
                reportData['calTarget'] ?? '--',
              ),
            ),
            WardKvRow(
              label: 'Protein Consistency',
              value: '${reportData['proteinDays'] ?? '0/7'} days',
            ),
            WardKvRow(
              label: 'Best Day',
              value: reportData['bestDay'] ?? '--',
              showDivider: false,
            ),

            const SizedBox(height: 12),

            // Sharp 2-px CTA slab
            WardButton(
              label: needsPaywall
                  ? 'Upgrade for Reports'
                  : 'View Full Report',
              variant: needsPaywall
                  ? WardButtonVariant.primary
                  : WardButtonVariant.outline,
              onPressed: () {
                if (isPro || !hasFirstReport) {
                  onViewReport();
                } else {
                  onUpgradeTap();
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  String _combine(String value, String suffix, String extra) {
    final buf = StringBuffer(value);
    if (suffix.isNotEmpty) buf.write(' $suffix');
    if (extra.isNotEmpty) buf.write(' $extra');
    return buf.toString();
  }

  Map<String, String> _computeReportData() {
    return NutritionRepository.instance.computeWeeklyReportData();
  }
}
