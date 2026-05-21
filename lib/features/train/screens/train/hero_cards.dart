part of 'screen.dart';

extension _HeroCards on _TrainScreenState {
  // ── 2. Today's Workout Hero Card ──────────────────────────────

  Widget _buildTodayHeroCard(BuildContext context, CurrentPlanData plan,
      WorkoutDayData? todayWorkout) {
    // Always use current week data for today lookup (W2 fix).
    final currentWeekDays = plan.getWeek(plan.currentWeek);
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    WorkoutDayData? todayDay;
    for (final day in currentWeekDays) {
      if (day.date != null) {
        final dayStr =
            '${day.date!.year}-${day.date!.month.toString().padLeft(2, '0')}-${day.date!.day.toString().padLeft(2, '0')}';
        if (dayStr == todayStr) {
          todayDay = day;
          break;
        }
      }
    }

    final isRestDay = todayDay?.isRest ?? (todayWorkout == null);
    final isDoneToday = todayDay?.isDone ?? false;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S WORKOUT",
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          if (isDoneToday && todayDay != null)
            _buildDoneHeroCard(todayDay)
          else if (isRestDay)
            _buildRestHeroCard()
          else if (todayWorkout != null)
            _buildWorkoutHeroCard(context, todayWorkout),
        ],
      ),
    );
  }

  Widget _buildWorkoutHeroCard(
      BuildContext context, WorkoutDayData workout) {
    // Extract focus/muscles from subtitle
    final subtitleParts = workout.subtitle.split('\u00b7');
    final focusText =
        subtitleParts.isNotEmpty ? subtitleParts[0].trim() : '';

    // Split workout.name so the mode label (e.g. "Relaxed", "Focused")
    // renders as an italic-gold second run under the title. Phase-driven
    // same as Home — matches handoff "Leg Day / _Relaxed_" pattern.
    final plan = ref.read(currentPlanProvider);
    final phaseMode = {
      1: 'Relaxed',
      2: 'Focused',
      3: 'Capacity',
      4: 'Peak',
    };
    final modeLabel = phaseMode[plan.phase] ?? 'Focused';

    return WardCard(
      variant: WardCardVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: AppTypography.h2.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
                height: 1.1,
              ),
              children: [
                TextSpan(text: workout.name),
                const TextSpan(text: ' '),
                TextSpan(
                  text: modeLabel,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          if (focusText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              focusText,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${workout.exerciseCount} EXERCISES \u00B7 ~${workout.estimatedDuration.toString().toUpperCase()}',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          WardButton(
            label: 'START WORKOUT',
            trailing: const Icon(Icons.arrow_forward,
                size: 14, color: AppColors.bgDeep),
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).startWorkout(workout);
              context.go('/train/active-workout');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRestHeroCard() {
    return WardCard(
      onTap: () => _showRestDaySheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REST DAY',
            style: AppTypography.mono.copyWith(
              fontSize: 12,
              color: AppColors.textDim,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Recovery & mobility \u2014 tap for recovery tips',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneHeroCard(WorkoutDayData workout) {
    return WardCard(
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.ok, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.name,
                  style: AppTypography.h3,
                ),
                const SizedBox(height: 2),
                Text(
                  'Completed today \u2014 great work!',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.ok,
                  ),
                ),
              ],
            ),
          ),
          const WardChip(label: 'DONE', tone: WardChipTone.ok),
        ],
      ),
    );
  }
}
