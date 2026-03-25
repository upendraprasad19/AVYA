import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

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
    'pull': AppColors.purple,
    'legs': AppColors.green,
    'core': AppColors.orange,
    'cardio': AppColors.blue,
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.cardM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'THIS WEEK\'S VOLUME',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${_formatKg(total)} kg',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
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
                              cat[0].toUpperCase() + cat.substring(1),
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              _formatKg(value),
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: AppColors.input,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
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
