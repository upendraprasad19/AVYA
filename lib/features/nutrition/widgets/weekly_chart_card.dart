import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// A 7-day bar chart card for weekly insights (calories or protein).
class WeeklyChartCard extends StatelessWidget {
  final String title;
  final String emoji;
  final List<double> data; // 7 values for M-S
  final Color barColor;
  final String avgLabel; // e.g. "Avg: 1821 kcal/day"
  final String targetLabel; // e.g. "Target: 2400"
  final Color targetColor;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  const WeeklyChartCard({
    super.key,
    required this.title,
    required this.emoji,
    required this.data,
    required this.barColor,
    required this.avgLabel,
    required this.targetLabel,
    required this.targetColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.isEmpty ? 1.0 : data.reduce((a, b) => a > b ? a : b);

    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title — Mono eyebrow above Fraunces h3
          Text(
            '$emoji  ${title.toUpperCase()}',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),

          // Bar chart
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final fraction = maxVal > 0 ? (data[i] / maxVal) : 0.0;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 3,
                      right: i == 6 ? 0 : 3,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 30,
                              decoration: const BoxDecoration(
                                color: AppColors.input,
                              ),
                              child: FractionallySizedBox(
                                heightFactor: fraction.clamp(0.05, 1.0),
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: barColor.withValues(
                                      alpha: 0.7 + (fraction * 0.3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dayLabels[i],
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textMute,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          const WardRule(margin: EdgeInsets.zero),
          const SizedBox(height: 10),

          // Bottom row: avg and target
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                avgLabel,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              Text(
                targetLabel,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: targetColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
