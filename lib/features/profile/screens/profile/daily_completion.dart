part of 'screen.dart';

extension _DailyCompletion on _ProfileScreenState {

  // ── #2 Daily Completion ──────────────────────────────────────────

  Widget _buildDailyCompletionInner(UserStatsData stats) {
    // Read completion states from Hive
    final hive = HiveService.instance;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final workoutSchedule = hive.workoutBox.values.where((raw) {
      if (raw is! Map) return false;
      return raw['date'] == todayStr && raw['status'] == 'completed';
    });
    final workoutDone = workoutSchedule.isNotEmpty;

    final nutritionToday = ref.watch(nutritionSummaryProvider);
    final hasMeals = nutritionToday.calories >= nutritionToday.calorieTarget &&
        nutritionToday.protein >= nutritionToday.proteinTarget;

    final waterMl = ref.watch(waterIntakeProvider);
    final waterDone = waterMl >= 3000;

    final weightDone = hive.healthBox.get('weight_$todayStr') != null;

    final done = [workoutDone, hasMeals, waterDone, weightDone].where((b) => b).length;

    // Theme C · Test #8 — inner-only: caller wraps with `_buildFlushCard`.
    return Row(
      children: [
        // Progress ring
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: done / 4,
                strokeWidth: 4,
                backgroundColor: AppColors.bgRaise,
                valueColor: AlwaysStoppedAnimation(
                    done == 4 ? AppColors.ok : AppColors.accent),
              ),
              Text(
                '$done/4',
                style: AppTypography.monoXs.copyWith(
                  color: done == 4 ? AppColors.ok : AppColors.accent,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DAILY GOALS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _completionDot('Workout', workoutDone),
                  const SizedBox(width: 8),
                  _completionDot('Meals', hasMeals),
                  const SizedBox(width: 8),
                  _completionDot('Water', waterDone),
                  const SizedBox(width: 8),
                  _completionDot('Weight', weightDone),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _completionDot(String label, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: done ? AppColors.ok : AppColors.bgRaise,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.ok : AppColors.line2,
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label.toUpperCase(),
          style: AppTypography.monoXs.copyWith(
            color: done ? AppColors.ok : AppColors.textMute,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
