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
      // No "TODAY'S WORKOUT" eyebrow any more (founder call 2026-11-01 — it cost a
      // row, and the highlighted day below already says "today"). A hold week keeps
      // its accent identity as a small HOLD WEEK tag INSIDE each compact card.
      child: isDoneToday && todayDay != null
          ? _buildDoneHeroCard(todayDay, isHolding: isHolding)
          : isRestDay
              ? _buildRestHeroCard(isHolding: isHolding)
              : (todayWorkout != null && todayWorkout.exercises.isNotEmpty)
                  ? _buildWorkoutHeroCard(context, todayWorkout,
                      isHolding: isHolding)
                  // Content-less today (plan gap / unhealed restore) — NEVER offer
                  // a dead START button (review P1 2026-06-06; the founder's "i
                  // cant start the workout" was this surface). Show a refresh
                  // hint instead.
                  : _buildEmptyWorkoutHeroCard(isHolding: isHolding),
    );
  }

  /// Accent "HOLD WEEK · " lead-in span for the free-tier hold week (null when
  /// not holding). Shared by all four compact hero states.
  TextSpan? _holdLead(bool isHolding) => isHolding
      ? TextSpan(
          text: 'HOLD WEEK \u00B7 ',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.accent,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        )
      : null;

  Widget _buildWorkoutHeroCard(BuildContext context, WorkoutDayData workout,
      {bool isHolding = false}) {
    // Split workout.name so the mode label (e.g. "Relaxed", "Focused")
    // renders as an italic-gold second run after the title. Phase-driven
    // same as Home — matches handoff "Leg Day / _Relaxed_" pattern.
    final plan = ref.read(currentPlanProvider);
    final phaseMode = {
      1: 'Relaxed',
      2: 'Focused',
      3: 'Capacity',
      4: 'Peak',
    };
    final modeLabel = phaseMode[plan.phase] ?? 'Focused';
    // Obs 5 follow-up (diagnose 6c2f91) — surface that a live session already
    // exists so the user isn't tempted to re-tap START and silently discard
    // it via beginWorkoutWithReadiness's guard.
    final isResuming = ref.watch(activeWorkoutProvider).hasInProgressSession;

    // ONE compact row (founder call 2026-11-01): title + mode on top, a single
    // meta line under it, a small START / RESUME button on the right. The old
    // card was five rows (title, focus line, meta, gap, full-width button).
    return WardCard(
      variant: WardCardVariant.hero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: AppTypography.h2.copyWith(
                      fontSize: 18,
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
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textDim,
                      letterSpacing: 1,
                    ),
                    children: [
                      if (_holdLead(isHolding) != null) _holdLead(isHolding)!,
                      TextSpan(
                        text:
                            '${workout.exerciseCount} EX \u00B7 ~${workout.estimatedDuration.toString().toUpperCase()}',
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          WardButton(
            label: isResuming ? 'RESUME' : 'START',
            size: WardButtonSize.small,
            fullWidth: false,
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

  /// One line: `REST DAY · Recovery & mobility` + chevron (founder call
  /// 2026-11-01 — was a two-row card). Whole card taps to the recovery sheet.
  Widget _buildRestHeroCard({bool isHolding = false}) {
    return WardCard(
      onTap: () => _showRestDaySheet(context),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (_holdLead(isHolding) != null) _holdLead(isHolding)!,
                  TextSpan(
                    text: 'REST DAY',
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.textDim,
                      letterSpacing: 2.5,
                    ),
                  ),
                  TextSpan(
                    text: '  \u00B7  Recovery & mobility',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
        ],
      ),
    );
  }

  /// Today is a workout day but has NO exercises (a plan gap / unhealed
  /// restore). Renders an informative card with a refresh tap instead of a
  /// START button that can't start anything (review P1 2026-06-06).
  Widget _buildEmptyWorkoutHeroCard({bool isHolding = false}) {
    return WardCard(
      onTap: () {
        ref.invalidate(currentPlanProvider);
        ref.invalidate(selectedWeekProvider);
      },
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (_holdLead(isHolding) != null) _holdLead(isHolding)!,
                  TextSpan(
                    text: 'NO WORKOUT SCHEDULED',
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.textDim,
                      letterSpacing: 2.5,
                    ),
                  ),
                  TextSpan(
                    text: "\nToday's plan is still syncing \u2014 tap to refresh.",
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.refresh, size: 18, color: AppColors.textDim),
        ],
      ),
    );
  }

  Widget _buildDoneHeroCard(WorkoutDayData workout, {bool isHolding = false}) {
    return WardCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                Text.rich(
                  TextSpan(
                    children: [
                      if (_holdLead(isHolding) != null) _holdLead(isHolding)!,
                      TextSpan(
                        text: 'Completed today \u2014 great work!',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.ok,
                        ),
                      ),
                    ],
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
