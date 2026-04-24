import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Today's workout split card. Two-column 1.35fr / 1fr grid:
/// * **Left** hero: phase chip + meta eyebrow + one-row Fraunces 20 title
///   with italic-gold pace mode separated by a middot (e.g.
///   `LEG DAY · Relaxed`), meta row, centered primary CTA.
/// * **Right**: one unified stats card with three rows — FUEL / PROTEIN /
///   STEPS. Each row: colored diamond glyph + mono 8 caps label +
///   Fraunces 15 w700 value with mono 9 target suffix + 2-px progress
///   bar tinted to match the metric.
class TodayWorkoutCard extends StatelessWidget {
  final String? workoutTag;
  final String workoutName;
  final String? workoutMode;
  final int durationMin;
  final int exerciseCount;
  final VoidCallback onStart;

  final double caloriesCurrent;
  final double caloriesTarget;
  final double proteinCurrent;
  final double proteinTarget;
  final int steps;
  final int stepsGoal;

  final bool isRestDay;
  final bool isDone;

  final double? totalVolumeKg;
  final String? bestLift;
  final VoidCallback? onViewCard;

  const TodayWorkoutCard({
    super.key,
    this.workoutTag,
    required this.workoutName,
    this.workoutMode,
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left hero (1.35fr).
          Expanded(flex: 135, child: _HeroCard(
            workoutTag: workoutTag,
            workoutName: workoutName,
            workoutMode: workoutMode,
            durationMin: durationMin,
            exerciseCount: exerciseCount,
            isRestDay: isRestDay,
            isDone: isDone,
            totalVolumeKg: totalVolumeKg,
            bestLift: bestLift,
            onStart: onStart,
            onViewCard: onViewCard,
          )),
          const SizedBox(width: 8),
          // Right column (1fr) — one unified stats block with 3 rows.
          Expanded(
            flex: 100,
            child: _StatsBlock(
              caloriesCurrent: caloriesCurrent,
              caloriesTarget: caloriesTarget,
              proteinCurrent: proteinCurrent,
              proteinTarget: proteinTarget,
              steps: steps,
              stepsGoal: stepsGoal,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtK(int n) {
    if (n >= 1000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return n.toString();
  }
}

// ── Left hero card ─────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.workoutTag,
    required this.workoutName,
    required this.workoutMode,
    required this.durationMin,
    required this.exerciseCount,
    required this.isRestDay,
    required this.isDone,
    required this.totalVolumeKg,
    required this.bestLift,
    required this.onStart,
    required this.onViewCard,
  });

  final String? workoutTag;
  final String workoutName;
  final String? workoutMode;
  final int durationMin;
  final int exerciseCount;
  final bool isRestDay;
  final bool isDone;
  final double? totalVolumeKg;
  final String? bestLift;
  final VoidCallback onStart;
  final VoidCallback? onViewCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.33),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Phase chip + meta eyebrow.
              Row(
                children: [
                  if (workoutTag != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.27),
                        ),
                      ),
                      child: Text(
                        workoutTag!,
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 8,
                          color: AppColors.accent,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (workoutMode != null && workoutTag != null)
                    const SizedBox(width: 6),
                  if (workoutMode != null)
                    Flexible(
                      child: Text(
                        workoutMode!,
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 8,
                          color: AppColors.textMute,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Workout name — Fraunces 20 w600. When [workoutMode] is set
              // (e.g. "Relaxed"), it follows the workout name on the SAME
              // line separated by a mid-dot, with italic-gold emphasis.
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: AppTypography.h2.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  children: [
                    TextSpan(text: workoutName),
                    if (workoutMode != null && !isRestDay) ...[
                      const TextSpan(
                        text: ' \u00B7 ',
                        style: TextStyle(color: AppColors.textGhost),
                      ),
                      TextSpan(
                        text: _titleCase(workoutMode!),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isRestDay && exerciseCount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '\u23F1 $durationMin MIN',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textDim,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '\u00B7',
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.textGhost),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$exerciseCount EX',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textDim,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: _HeroCta(
              isRestDay: isRestDay,
              isDone: isDone,
              totalVolumeKg: totalVolumeKg,
              bestLift: bestLift,
              onStart: onStart,
              onViewCard: onViewCard,
            ),
          ),
        ],
      ),
    );
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    final lower = input.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

class _HeroCta extends StatelessWidget {
  const _HeroCta({
    required this.isRestDay,
    required this.isDone,
    required this.totalVolumeKg,
    required this.bestLift,
    required this.onStart,
    required this.onViewCard,
  });
  final bool isRestDay;
  final bool isDone;
  final double? totalVolumeKg;
  final String? bestLift;
  final VoidCallback onStart;
  final VoidCallback? onViewCard;

  @override
  Widget build(BuildContext context) {
    if (isRestDay) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
      );
    }

    if (isDone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const WardChip(
                label: 'DONE',
                tone: WardChipTone.ok,
                leading: Icon(
                  Icons.check_circle,
                  size: 10,
                  color: AppColors.ok,
                ),
              ),
              if (onViewCard != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onViewCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(
                        color:
                            AppColors.accent.withValues(alpha: 0.33),
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
                        const Icon(
                          Icons.arrow_forward,
                          size: 10,
                          color: AppColors.accent,
                        ),
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
      );
    }

    return TapScale(
      onTap: onStart,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_arrow,
              size: 14,
              color: AppColors.bgDeep,
            ),
            const SizedBox(width: 5),
            Text(
              'START',
              style: AppTypography.mono.copyWith(
                color: AppColors.bgDeep,
                letterSpacing: 2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Right-column unified stats block (FUEL / PROTEIN / STEPS) ─────────
class _StatsBlock extends StatelessWidget {
  const _StatsBlock({
    required this.caloriesCurrent,
    required this.caloriesTarget,
    required this.proteinCurrent,
    required this.proteinTarget,
    required this.steps,
    required this.stepsGoal,
  });

  final double caloriesCurrent;
  final double caloriesTarget;
  final double proteinCurrent;
  final double proteinTarget;
  final int steps;
  final int stepsGoal;

  @override
  Widget build(BuildContext context) {
    double safePct(num n, num d) =>
        d > 0 ? (n / d).clamp(0.0, 1.0).toDouble() : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.33),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            glyph: '\u25C7', // ◇
            glyphColor: AppColors.accent,
            label: 'FUEL',
            value: '${caloriesCurrent.round()}',
            suffix: '/${caloriesTarget.round()} kcal',
            valueColor: AppColors.accent,
            progress: safePct(caloriesCurrent, caloriesTarget),
            progressColor: AppColors.accent,
          ),
          _StatRow(
            glyph: '\u25C6', // ◆
            glyphColor: AppColors.ok,
            label: 'PROTEIN',
            value: '${proteinCurrent.round()}',
            suffix: '/${proteinTarget.round()} g',
            valueColor: AppColors.ok,
            progress: safePct(proteinCurrent, proteinTarget),
            progressColor: AppColors.ok,
          ),
          _StatRow(
            glyph: '\u25B2', // ▲
            glyphColor: AppColors.info,
            label: 'STEPS',
            value: TodayWorkoutCard._fmtK(steps),
            suffix: '/${TodayWorkoutCard._fmtK(stepsGoal)}',
            valueColor: AppColors.info,
            progress: safePct(steps, stepsGoal),
            progressColor: AppColors.info,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.glyph,
    required this.glyphColor,
    required this.label,
    required this.value,
    required this.suffix,
    required this.valueColor,
    required this.progress,
    required this.progressColor,
  });

  final String glyph;
  final Color glyphColor;
  final String label;
  final String value;
  final String suffix;
  final Color valueColor;
  final double progress;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              glyph,
              style: TextStyle(
                fontSize: 9,
                color: glyphColor,
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.monoXs.copyWith(
                fontSize: 8,
                color: AppColors.textMute,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: AppTypography.h2.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  letterSpacing: -0.2,
                  height: 1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                suffix,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  color: AppColors.textMute,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 2,
          child: WardBar(
            pct: progress,
            height: 2,
            color: progressColor,
          ),
        ),
      ],
    );
  }
}
