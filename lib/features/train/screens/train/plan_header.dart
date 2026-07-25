part of 'screen.dart';

extension _PlanHeader on _TrainScreenState {
  // ── 1. Plan Header with Progress Bar ──────────────────────────

  Widget _buildPlanHeader(
      CurrentPlanData plan, int selectedWeek, List<WorkoutDayData> weekDays) {
    final holdStatus = ref.watch(holdStatusProvider);

    // Calculate week completion
    int totalWorkoutDays = 0;
    int completedDays = 0;
    for (final day in weekDays) {
      if (!day.isRest) {
        totalWorkoutDays++;
        if (day.isDone) completedDays++;
      }
    }
    // During a hold, `weekDays` is the phase's ORIGINAL week 4 (the selected
    // week is clamped to 1-4 and hold rows live at week 5+), so its tallies
    // describe a month-old week. The hold week's own session count is the only
    // honest progress readout. Flag OFF ⇒ never holding ⇒ untouched.
    if (holdStatus.isHolding) {
      completedDays = holdStatus.sessionsCompleted;
      totalWorkoutDays = holdStatus.sessionsTotal;
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
                  // A hold week has no honest "WK n OF m" \u2014 it sits OUTSIDE the
                  // phase's m weeks. The HOLDING \u00B7 Hn pill carries the identity
                  // instead (locked mockup).
                  holdStatus.isHolding
                      ? 'TRAIN \u00B7 DEPLOYMENT 01 \u00B7 PHASE $currentPhase'
                      : 'TRAIN \u00B7 WK $selectedWeek OF ${plan.weeks.length} '
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
                // Obs 2 (2026-06-02) — phase names vary in length
                // ("Foundation" → "Intensification" → "Deployment 13"); a
                // fixed 32sp + maxLines:1 + ellipsis clipped the longer ones
                // ("Intensificati…"). FittedBox(scaleDown) shrinks the title to
                // fit the available width instead of truncating, so the full
                // name is always readable. left-aligned to keep the eyebrow
                // baseline.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
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
                    softWrap: false,
                  ),
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
          // HOLDING · Hn pill — the hold week's identity, replacing the week
          // counter the eyebrow drops while holding.
          if (holdStatus.isHolding) ...[
            const SizedBox(height: 10),
            _buildHoldingPill(holdStatus),
          ],
          const SizedBox(height: 10),
          // ROW 3 — compact subtitle + progress bar inline
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                holdStatus.isHolding
                    ? '$completedDays / $totalWorkoutDays SESSIONS'
                    : '$completedDays / $totalWorkoutDays',
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

  /// "● HOLDING · H3" — gold-on-gold-tint pill announcing the active hold week
  /// (locked mockup). Only ever built when `holdStatus.isHolding`.
  Widget _buildHoldingPill(HoldStatusData holdStatus) {
    final ordinal = holdStatus.todayHoldOrdinal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            ordinal == null ? 'HOLDING' : 'HOLDING · H$ordinal',
            style: AppTypography.monoXs.copyWith(
              fontSize: 11,
              letterSpacing: 1,
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
