part of 'screen.dart';

extension _NutritionTargets on _ProfileScreenState {

  Widget _buildNutritionTargetsInner(
    Map<String, double> targets, {
    double? currentKg,
    double? targetKg,
    required String goal,
    required String pacePreference,
  }) {
    // Bug #24 — compute projection only when we have a real target delta
    // and a non-maintenance goal. Otherwise hide the subtitle entirely.
    String? projectionLine;
    if ((goal == 'lose_fat' || goal == 'build_muscle') &&
        currentKg != null &&
        targetKg != null &&
        (currentKg - targetKg).abs() > 0.1) {
      final p = BmrCalculator.projectGoalDate(
        currentKg: currentKg,
        targetKg: targetKg,
        pacePreference: pacePreference,
      );
      if (p.weeks > 104) {
        projectionLine =
            "At this pace, you'll reach ${targetKg.toStringAsFixed(0)} kg in >2 years";
      } else if (p.weeks > 0) {
        final dateStr = '${_monthAbbr(p.date.month)} ${p.date.day}';
        projectionLine =
            "At this pace, you'll reach ${targetKg.toStringAsFixed(0)} kg on $dateStr (~${p.weeks.round()} weeks)";
      }
    }

    // Theme C · Test #8 — inner-only: caller wraps with `_buildFlushCard`
    // and threads the projection-tap onTap via `_nutritionTargetsOnTap`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'MY TARGETS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 12),
            _targetChip('${targets['tdee']?.round()} kcal', 'TDEE'),
            const SizedBox(width: 8),
            _targetChip('${targets['calories']?.round()} kcal', 'TARGET'),
            const SizedBox(width: 8),
            _targetChip('${targets['protein']?.round()}g', 'PROTEIN'),
          ],
        ),
        if (projectionLine != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  projectionLine,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 14, color: AppColors.textMute),
            ],
          ),
        ],
      ],
    );
  }

  static String _monthAbbr(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(m - 1).clamp(0, 11)];
  }
}
