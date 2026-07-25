part of 'screen.dart';

extension _HeroCards on _TrainScreenState {
  // ── 2. Today's Workout Hero Card ──────────────────────────────

  /// [holdDay] / [isHolding] — the free-tier hold-week branch. During a hold,
  /// the by-week lookup below CANNOT find today: `holdWeek()` stamps hold rows
  /// `week = 4 + ordinal`, but `plan.weeks` only ever holds the phase's 4 weeks,
  /// so `getWeek(plan.currentWeek)` is the ORIGINAL week 4 (last month's dates)
  /// and no row matches today. [holdDay] is the date-keyed row for today —
  /// the same `schedule_<date>` source Home's Today card reads — and becomes
  /// the source of truth for the card when [isHolding]. Null [holdDay] while
  /// holding means today is a rest day (or has no exercises), which falls
  /// through to the same rest / empty handling as any other day.
  Widget _buildTodayHeroCard(BuildContext context, CurrentPlanData plan,
      WorkoutDayData? todayWorkout,
      {WorkoutDayData? holdDay, bool isHolding = false}) {
    // Always use current week data for today lookup (W2 fix).
    final currentWeekDays = plan.getWeek(plan.currentWeek);
    final todayStr = istTodayStr();

    WorkoutDayData? todayDay;
    for (final day in currentWeekDays) {
      if (day.date != null) {
        final dayStr = istDateStr(day.date!);
        if (dayStr == todayStr) {
          todayDay = day;
          break;
        }
      }
    }

    if (isHolding) {
      todayDay = holdDay;
      todayWorkout = holdDay;
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
            isHolding ? 'TODAY · HOLD WEEK' : "TODAY'S WORKOUT",
            style: AppTypography.mono.copyWith(
              color: isHolding ? AppColors.accent : AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          if (isDoneToday && todayDay != null)
            _buildDoneHeroCard(todayDay)
          else if (isRestDay)
            _buildRestHeroCard()
          else if (todayWorkout != null && todayWorkout.exercises.isNotEmpty)
            _buildWorkoutHeroCard(context, todayWorkout)
          else
            // Content-less today (plan gap / unhealed restore) — NEVER offer a
            // dead START button (review P1 2026-06-06; the founder's "i cant
            // start the workout" was this surface). Show a refresh hint instead.
            _buildEmptyWorkoutHeroCard(),
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
            onPressed: () async {
              // ⑥ Batch 6 (W2.3) — readiness check-in (flag-gated) before start.
              await beginWorkoutWithReadiness(context, ref, workout);
              if (context.mounted) context.go('/train/active-workout');
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

  /// Today is a workout day but has NO exercises (a plan gap / unhealed
  /// restore). Renders an informative card with a refresh tap instead of a
  /// START button that can't start anything (review P1 2026-06-06).
  Widget _buildEmptyWorkoutHeroCard() {
    return WardCard(
      onTap: () {
        ref.invalidate(currentPlanProvider);
        ref.invalidate(selectedWeekProvider);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NO WORKOUT SCHEDULED',
            style: AppTypography.mono.copyWith(
              fontSize: 12,
              color: AppColors.textDim,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Today's plan is still syncing \u2014 tap to refresh.",
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
