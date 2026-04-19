import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

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

  // Completed mode
  final bool isDone;

  // Completed-state extras
  final double? totalVolumeKg;
  final String? bestLift;
  final VoidCallback? onViewCard;

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
    this.isDone = false,
    this.totalVolumeKg,
    this.bestLift,
    this.onViewCard,
  });

  @override
  Widget build(BuildContext context) {
    final fuelProgress = caloriesTarget > 0
        ? (caloriesCurrent / caloriesTarget).clamp(0.0, 1.0)
        : 0.0;
    final proteinProgress = proteinTarget > 0
        ? (proteinCurrent / proteinTarget).clamp(0.0, 1.0)
        : 0.0;
    final stepsProgress =
        stepsGoal > 0 ? (steps / stepsGoal).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Workout card (60%) — hero variant
          Expanded(
            flex: 6,
            child: WardCard(
              variant: WardCardVariant.hero,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (workoutTag != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: WardChip(
                            label: workoutTag!,
                            tone: WardChipTone.neutral,
                          ),
                        ),
                      Text(
                        workoutName,
                        style: AppTypography.h3.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '\u23F1 $durationMin MIN',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '\u{1F4AA} $exerciseCount EX',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute,
                              letterSpacing: 1.5,
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
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.bgRaise,
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                        border: Border.all(color: AppColors.line2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('\u{1F4A4}', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 6),
                          Text(
                            'REST DAY',
                            style: AppTypography.mono.copyWith(
                              color: AppColors.textMute,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isDone)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const WardChip(
                              label: 'DONE',
                              tone: WardChipTone.ok,
                              leading: Icon(Icons.check_circle,
                                  size: 10, color: AppColors.ok),
                            ),
                            if (onViewCard != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: onViewCard,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSoft,
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.sharp),
                                    border: Border.all(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.33),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'VIEW CARD',
                                        style: AppTypography.monoXs.copyWith(
                                          color: AppColors.accent,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.arrow_forward,
                                          size: 10, color: AppColors.accent),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (bestLift != null || totalVolumeKg != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (bestLift != null) '\u{1F3C6} $bestLift',
                              if (totalVolumeKg != null)
                                '${totalVolumeKg!.toStringAsFixed(0)} kg vol',
                            ].join('  \u00B7  '),
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute,
                              letterSpacing: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    )
                  else
                    TapScale(
                      onTap: onStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.sharp),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_arrow,
                                size: 14, color: Colors.black),
                            const SizedBox(width: 5),
                            Text(
                              'START',
                              style: AppTypography.mono.copyWith(
                                color: Colors.black,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w900,
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
          // Right: Combined Fuel+Protein + Steps
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Combined Fuel + Protein card
                Expanded(
                  flex: 3,
                  child: WardCard(
                    variant: WardCardVariant.standard,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatRow(
                          icon: Icons.local_gas_station,
                          iconColor: AppColors.accent,
                          label: 'FUEL',
                          value: '${caloriesCurrent.round()}',
                          target: '${caloriesTarget.round()}',
                          suffix: 'kcal',
                          valueColor: AppColors.accent,
                          progress: fuelProgress,
                          progressColor: AppColors.accent,
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          icon: Icons.fitness_center,
                          iconColor: AppColors.warn,
                          label: 'PROTEIN',
                          value: '${proteinCurrent.round()}',
                          target: '${proteinTarget.round()}',
                          suffix: 'g',
                          valueColor: AppColors.warn,
                          progress: proteinProgress,
                          progressColor: AppColors.warn,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Steps card
                Expanded(
                  flex: 2,
                  child: WardCard(
                    variant: WardCardVariant.standard,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.directions_walk,
                                size: 10, color: AppColors.ok),
                            const SizedBox(width: 3),
                            Text(
                              'STEPS',
                              style: AppTypography.monoXs.copyWith(
                                color: AppColors.textMute,
                                letterSpacing: 1.5,
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
                                          text: _formatNumber(
                                              animSteps.round()),
                                          style: AppTypography.h3.copyWith(
                                            color: AppColors.ok,
                                            height: 1,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' / ${_formatNumber(stepsGoal)}',
                                          style: AppTypography.monoXs.copyWith(
                                            color: AppColors.textMute,
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
                        WardBar(
                          pct: stepsProgress,
                          height: 3,
                          color: AppColors.ok,
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
  final String target;
  final String suffix;
  final Color valueColor;
  final double progress;
  final Color progressColor;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.target = '',
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
        Row(
          children: [
            Icon(icon, size: 10, color: iconColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.5,
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
                          style: AppTypography.h3.copyWith(
                            color: valueColor,
                            height: 1,
                          ),
                        ),
                        if (target.isNotEmpty)
                          TextSpan(
                            text: '/$target',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute,
                            ),
                          ),
                        TextSpan(
                          text: ' $suffix',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textMute,
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
        WardBar(
          pct: progress,
          height: 3,
          color: progressColor,
        ),
      ],
    );
  }
}
