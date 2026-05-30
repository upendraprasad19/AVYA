part of 'screen.dart';

extension _PlanHeader on _TrainScreenState {
  // ── 1. Plan Header with Progress Bar ──────────────────────────

  Widget _buildPlanHeader(
      CurrentPlanData plan, int selectedWeek, List<WorkoutDayData> weekDays) {
    // Calculate week completion
    int totalWorkoutDays = 0;
    int completedDays = 0;
    for (final day in weekDays) {
      if (!day.isRest) {
        totalWorkoutDays++;
        if (day.isDone) completedDays++;
      }
    }
    final progress =
        totalWorkoutDays > 0 ? completedDays / totalWorkoutDays : 0.0;
    final progressPercent = (progress * 100).round();

    // F9 · Test #9 — Train header compacted to 3 rows + 1 hairline.
    // Eyebrow gains PHASE meta. Title bumped 28sp -> 32sp. Subtitle inlined.
    final progressPhase = UserRepository.instance.getProgress() ?? {};
    final currentPhase = (progressPhase['current_phase'] as int?) ?? 1;

    return Container(
      // diagnose b1f4d2 (2026-05-30): a Container cannot take BOTH `color:`
      // and `decoration:` — the container.dart:277 assert throws in debug
      // (caught by TrainScreen._buildContent → "Failed to load workouts" — the
      // whole tab dies in debug/web). The decoration already paints bgDeep, so
      // the redundant top-level color is removed.
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ROW 1 — eyebrow with WK + PHASE meta
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnchorGlyph(size: 12),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'TRAIN \u00B7 WK $selectedWeek OF ${plan.weeks.length} '
                  '\u00B7 PHASE $currentPhase',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ROW 2 — title (32sp standardized) + streak right
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  plan.phaseName,
                  style: AppTypography.h1.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                    height: 1.05,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                // H-2 sibling (audit-2026-05-11) — read the reactive
                // subscription provider rather than the cached snapshot.
                // Same stale-pro class as `onSelect` above.
                onTap: () => StreakExplainerSheet.show(
                  context,
                  freezesAvailable: ref.read(streakFreezeProvider),
                  isPro: ref.read(subscriptionInfoProvider).isPro,
                ),
                child: WardStatusStrip(
                  streakDays: ref.watch(streakProvider),
                  freezesAvailable: ref.watch(streakFreezeProvider),
                  freezesMax: ref.watch(streakFreezeMaxProvider),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ROW 3 — compact subtitle + progress bar inline
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$completedDays / $totalWorkoutDays',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WardBar(
                  pct: progress,
                  height: 4,
                  trailingLabel: '$progressPercent%',
                  trailingColor: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
