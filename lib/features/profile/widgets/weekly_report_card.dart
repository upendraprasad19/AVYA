import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/weekly_report_data_provider.dart';

/// Weekly Nutrition Report card.
///
/// First report is free (after Week 1 of usage).
/// Ongoing weekly reports require PRO (`weekly_ai_report`).
///
/// AH.8 — the KV-row summary (Avg Calories / Protein Consistency /
/// Best Day) is replaced with a 4-up sparkline grid showing the last
/// 7 days of Weight / Calories / Protein / Workouts. Tiles read from
/// [weeklyReportDataProvider], which aggregates Hive boxes directly
/// (no network). The `View Full Report` CTA still opens the full
/// weekly AI report view.
class WeeklyReportCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final needsPaywall = !isPro && hasFirstReport;
    final series = ref.watch(weeklyReportDataProvider);

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
                              : 'Last 7 days at a glance',
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
            const SizedBox(height: 12),

            if (series.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Log a workout, meal, or weight this week to see trends.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              )
            else
              _SparkGrid(series: series),

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
}

/// 2×2 tile grid: Weight · Calories / Protein · Workouts.
class _SparkGrid extends StatelessWidget {
  const _SparkGrid({required this.series});
  final WeeklyReportSeries series;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SparkTile(
                label: 'WEIGHT',
                unit: 'KG',
                series: series.weight,
                latest: series.weight.isEmpty ? 0 : series.weight.last,
                decimals: 1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SparkTile(
                label: 'CALORIES',
                unit: 'KCAL',
                series: series.calories,
                latest:
                    series.calories.isEmpty ? 0 : series.calories.last,
                decimals: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SparkTile(
                label: 'PROTEIN',
                unit: 'G',
                series: series.protein,
                latest: series.protein.isEmpty ? 0 : series.protein.last,
                decimals: 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SparkTile(
                label: 'WORKOUTS',
                unit: '/7',
                series: series.workouts,
                // For the workouts tile, "latest" is really the weekly
                // count — more useful than "today's 0 or 1".
                latest:
                    series.workouts.fold<double>(0, (a, b) => a + b),
                decimals: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SparkTile extends StatelessWidget {
  const _SparkTile({
    required this.label,
    required this.unit,
    required this.series,
    required this.latest,
    required this.decimals,
  });

  final String label;
  final String unit;
  final List<double> series;
  final double latest;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final hasData = series.any((v) => v > 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasData ? latest.toStringAsFixed(decimals) : '—',
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: LayoutBuilder(builder: (context, c) {
              if (!hasData || series.length < 2) {
                return SizedBox(width: c.maxWidth, height: 28);
              }
              return WardSpark(
                data: series,
                width: c.maxWidth,
                height: 28,
                strokeWidth: 1.5,
                fillAlpha: 0.18,
              );
            }),
          ),
        ],
      ),
    );
  }
}
