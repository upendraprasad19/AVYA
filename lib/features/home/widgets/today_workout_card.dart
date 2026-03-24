import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';

/// Today's workout split card with workout info on left, fuel + steps on right.
class TodayWorkoutCard extends StatelessWidget {
  final String? workoutTag;
  final String workoutName;
  final int durationMin;
  final int exerciseCount;
  final VoidCallback onStart;

  // Fuel mini card
  final double caloriesCurrent;
  final double caloriesTarget;

  // Protein mini card
  final double proteinCurrent;
  final double proteinTarget;

  // Steps mini card
  final int steps;
  final int stepsGoal;

  // Rest day mode
  final bool isRestDay;

  const TodayWorkoutCard({
    super.key,
    this.workoutTag,
    required this.workoutName,
    this.durationMin = 55,
    this.exerciseCount = 6,
    required this.onStart,
    this.caloriesCurrent = 0,
    this.caloriesTarget = 2400,
    this.proteinCurrent = 0,
    this.proteinTarget = 184,
    this.steps = 0,
    this.stepsGoal = 10000,
    this.isRestDay = false,
  });

  @override
  Widget build(BuildContext context) {
    final fuelProgress = caloriesTarget > 0
        ? (caloriesCurrent / caloriesTarget).clamp(0.0, 1.0)
        : 0.0;
    final proteinProgress = proteinTarget > 0
        ? (proteinCurrent / proteinTarget).clamp(0.0, 1.0)
        : 0.0;
    final stepsProgress = stepsGoal > 0
        ? (steps / stepsGoal).clamp(0.0, 1.0)
        : 0.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Workout card (60%)
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.cardM),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (workoutTag != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            workoutTag!,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      Text(
                        workoutName,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '\u23F1 $durationMin MIN',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\u{1F4AA} $exerciseCount EX',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isRestDay)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\u{1F4A4}',
                            style: GoogleFonts.getFont('DM Sans', fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'REST DAY',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                  TapScale(
                    onTap: onStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow,
                              size: 12, color: Colors.black),
                          const SizedBox(width: 4),
                          Text(
                            'START',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Right: Combined Fuel+Protein + Steps (stretch to match workout card)
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Combined Fuel + Protein card
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Fuel row
                        _StatRow(
                          icon: Icons.local_gas_station,
                          iconColor: AppColors.accent,
                          label: 'FUEL',
                          value: '${caloriesCurrent.round()}',
                          suffix: 'kcal',
                          valueColor: AppColors.accent,
                          progress: fuelProgress,
                          progressColor: AppColors.accent,
                        ),
                        const SizedBox(height: 8),
                        // Protein row
                        _StatRow(
                          icon: Icons.fitness_center,
                          iconColor: AppColors.orange,
                          label: 'PROTEIN',
                          value: '${proteinCurrent.round()}',
                          suffix: 'g',
                          valueColor: AppColors.orange,
                          progress: proteinProgress,
                          progressColor: AppColors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Steps card
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Single-line: icon + label + animated value
                        Row(
                          children: [
                            const Icon(Icons.directions_walk,
                                size: 10, color: AppColors.green),
                            const SizedBox(width: 3),
                            Text(
                              'STEPS',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: steps.toDouble()),
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOut,
                                builder: (context, animSteps, _) {
                                  return Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: _formatNumber(animSteps.round()),
                                          style: GoogleFonts.getFont(
                                            'DM Sans',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.green,
                                            height: 1,
                                          ),
                                        ),
                                        TextSpan(
                                          text: ' / ${_formatNumber(stepsGoal)}',
                                          style: GoogleFonts.getFont(
                                            'DM Sans',
                                            fontSize: 9,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    textAlign: TextAlign.right,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: stepsProgress),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          builder: (context, animProgress, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: animProgress,
                                minHeight: 3,
                                backgroundColor: AppColors.input,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.green),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return n.toString();
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String suffix;
  final Color valueColor;
  final double progress;
  final Color progressColor;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.suffix,
    required this.valueColor,
    required this.progress,
    required this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final numericValue = double.tryParse(value) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Single-line: icon + label + animated value + suffix
        Row(
          children: [
            Icon(icon, size: 10, color: iconColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: numericValue),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (context, animValue, _) {
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${animValue.round()}',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: valueColor,
                            height: 1,
                          ),
                        ),
                        TextSpan(
                          text: ' $suffix',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 9,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.right,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, animProgress, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: animProgress,
                minHeight: 3,
                backgroundColor: AppColors.input,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            );
          },
        ),
      ],
    );
  }
}
