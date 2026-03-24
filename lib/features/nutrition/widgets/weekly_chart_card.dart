import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            '$emoji  $title',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
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
                              decoration: BoxDecoration(
                                color: AppColors.input,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                              child: FractionallySizedBox(
                                heightFactor: 1.0,
                                alignment: Alignment.bottomCenter,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: fraction.clamp(0.05, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: barColor.withValues(
                                          alpha: 0.7 + (fraction * 0.3),
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
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
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),

          // Bottom row: avg and target
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                avgLabel,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                targetLabel,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
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
