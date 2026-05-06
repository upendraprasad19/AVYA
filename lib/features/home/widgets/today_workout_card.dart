import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/tap_scale.dart';

/// Today's workout split card. Two-column 60/40 layout:
/// * **Left (60):** phase chip + meta eyebrow + Fraunces 24 title (maxLines:2)
///   with italic-gold pace mode separated by a mid-dot. CTA below:
///   START button (active), DONE chip + VIEW CARD button (completed), or
///   REST DAY badge (rest day). Best-lift line below CTA on completion.
/// * **Right (40):** 3 stacked macro tiles (FUEL / PROTEIN / STEPS).
///   Each tile: eyebrow LEFT + inline number RIGHT on row 1, full-width
///   bar on row 2. Number format: `1820/2983` (no spaces), `g` suffix
///   for protein, `k` abbreviation for step targets ≥1000.
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
    // APK Test #12 / Task B-2 — height equalization.
    // Pre-fix the Row had `crossAxisAlignment: CrossAxisAlignment.start`
    // which only top-aligns the children but DOES NOT force them to
    // share the Row's intrinsic height. Combined with `_MacroColumn`'s
    // `mainAxisSize: MainAxisSize.min`, the macro card collapsed to the
    // sum of its 3 rows while the hero card pushed the START CTA via
    // `mainAxisAlignment: spaceBetween` to the row's tallest extent —
    // producing a visible height mismatch (founder feedback 2026-05-06).
    // `CrossAxisAlignment.stretch` makes both children fill the IntrinsicHeight.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left column (60%).
          Expanded(
            flex: 60,
            child: _HeroCard(
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
            ),
          ),
          const SizedBox(width: 8),
          // Right column (40%) — 3 stacked macro tiles.
          Expanded(
            flex: 40,
            child: _MacroColumn(
              caloriesCurrent: caloriesCurrent.round(),
              caloriesTarget: caloriesTarget.round(),
              proteinCurrent: proteinCurrent.round(),
              proteinTarget: proteinTarget.round(),
              stepsCurrent: steps,
              stepsTarget: stepsGoal,
            ),
          ),
        ],
      ),
    );
  }

  /// Abbreviates a number to `Nk` when it is ≥ 1000, otherwise returns the
  /// raw integer string. Used for STEPS target display.
  static String _abbreviateK(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(0)}k' : '$n';
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
              // Workout name — Fraunces 24 w600. maxLines:2 so long names
              // like "Heavy Push · Aggressive" never truncate.
              // When [workoutMode] is set (e.g. "Relaxed"), it follows the
              // workout name on the same line separated by a mid-dot with
              // italic-gold emphasis.
              // APK Test #12 / Task B-1 \u2014 workoutMode label removed from
              // this title row. Pre-fix the mode word ("Relaxed") rendered
              // twice: once in the top mono row alongside PHASE chip,
              // again here as italic-gold. Mono row top-right is the
              // single source of truth now.
              Text(
                workoutName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleL.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
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
          // _HeroCta fills full width so Expanded(VIEW CARD) can stretch.
          // Individual states (START / REST DAY) shrink to content via
          // mainAxisSize: MainAxisSize.min internally.
          _HeroCta(
            isRestDay: isRestDay,
            isDone: isDone,
            totalVolumeKg: totalVolumeKg,
            bestLift: bestLift,
            onStart: onStart,
            onViewCard: onViewCard,
          ),
        ],
      ),
    );
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
      // Completed state: DONE chip (gold fill, black text) + VIEW CARD
      // outlined button occupy the full left-column width as a Row.
      // Best-lift text sits on its own line below -- never inline.
      final bestLiftLine = bestLift ??
          (totalVolumeKg != null
              ? '${totalVolumeKg!.toStringAsFixed(0)} kg vol'
              : null);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // DONE chip -- gold fill, black mono text.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '✓ DONE',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: AppColors.bg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // VIEW CARD outlined button -- takes remaining row width.
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewCard,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accent),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'VIEW CARD →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (bestLiftLine != null) ...[
            const SizedBox(height: 12),
            Text(
              bestLiftLine,
              style: AppTypography.bodyS.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      );
    }

    // START button — full width gold pill (matches the left column width).
    return TapScale(
      onTap: onStart,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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

// ── Right-column macro column (3 stacked tiles: FUEL / PROTEIN / STEPS) ──
class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.caloriesCurrent,
    required this.caloriesTarget,
    required this.proteinCurrent,
    required this.proteinTarget,
    required this.stepsCurrent,
    required this.stepsTarget,
  });

  final int caloriesCurrent;
  final int caloriesTarget;
  final int proteinCurrent;
  final int proteinTarget;
  final int stepsCurrent;
  final int stepsTarget;

  @override
  Widget build(BuildContext context) {
    double safePct(num n, num d) =>
        d > 0 ? (n / d).clamp(0.0, 1.0).toDouble() : 0.0;

    // Test #10 obs 4 — three-tile right column collapsed into ONE
    // bordered container. Rows separated by hairline `--line2` dividers
    // instead of the old 10px gaps. Bullet glyphs (◇ ◆ ▲) carry the
    // gold accent without per-row borders.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.cardS),
      ),
      child: Column(
        // APK Test #12.1 — macro rows distribute evenly through the
        // available height. Pre-fix `mainAxisSize: MainAxisSize.min`
        // kept rows top-stacked, so when B-2's `IntrinsicHeight` +
        // `crossAxisAlignment.stretch` made this card match the hero
        // card's height, the lower half rendered as empty space below
        // the third row. `MainAxisAlignment.spaceEvenly` spreads the
        // 3 rows + 2 dividers across the full vertical extent.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MacroRow(
            bullet: '◇', // ◇
            label: 'FUEL',
            currentLabel: '$caloriesCurrent',
            targetLabel: '/$caloriesTarget',
            progress: safePct(caloriesCurrent, caloriesTarget),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line2),
          _MacroRow(
            bullet: '◆', // ◆
            label: 'PROTEIN',
            currentLabel: '$proteinCurrent',
            targetLabel: '/${proteinTarget}g',
            progress: safePct(proteinCurrent, proteinTarget),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line2),
          _MacroRow(
            bullet: '▲', // ▲
            label: 'STEPS',
            currentLabel: TodayWorkoutCard._abbreviateK(stepsCurrent),
            targetLabel: '/${TodayWorkoutCard._abbreviateK(stepsTarget)}',
            progress: safePct(stepsCurrent, stepsTarget),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.bullet,
    required this.label,
    required this.currentLabel,
    required this.targetLabel,
    required this.progress,
  });

  final String bullet;
  final String label;
  final String currentLabel;
  final String targetLabel;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                bullet,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              RichText(
                text: TextSpan(
                  style: AppTypography.titleL.copyWith(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  children: [
                    TextSpan(text: currentLabel),
                    TextSpan(
                      text: targetLabel,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
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
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
