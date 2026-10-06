import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class WeeklyVolumeBar extends StatelessWidget {
  final Map<String, double> weekVolume;
  final double targetVolume;

  const WeeklyVolumeBar({
    super.key,
    required this.weekVolume,
    this.targetVolume = 15000,
  });

  static const _categoryColors = <String, Color>{
    'push': AppColors.accent,
    'pull': AppColors.info,
    'legs': AppColors.ok,
    'core': AppColors.warn,
    'cardio': AppColors.info,
  };

  String _formatKg(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return value.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    final total = weekVolume['total'] ?? 0.0;

    final categories = _categoryColors.keys
        .where((key) => (weekVolume[key] ?? 0) > 0)
        .toList();

    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'THIS WEEK VOLUME',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              Text(
                '${_formatKg(total)} KG',
                style: AppTypography.h2.copyWith(
                  color: AppColors.accent,
                  height: 1,
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Category mini-bars
            Row(
              children: categories.map((cat) {
                final value = weekVolume[cat] ?? 0.0;
                final color = _categoryColors[cat]!;
                final progress = targetVolume > 0
                    ? (value / targetVolume).clamp(0.0, 1.0)
                    : 0.0;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: cat != categories.last ? 10 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              (cat[0].toUpperCase() + cat.substring(1))
                                  .toUpperCase(),
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textMute,
                                letterSpacing: 1.4,
                              ),
                            ),
                            Text(
                              _formatKg(value),
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        WardBar(pct: progress, color: color, height: 4),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
