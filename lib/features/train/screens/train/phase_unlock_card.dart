part of 'screen.dart';

extension _PhaseUnlockCard on _TrainScreenState {
  // ── Phase Unlock Card ─────────────────────────────────────────

  Widget _buildPhaseUnlockCard(
      BuildContext context, CurrentPlanData plan, WidgetRef ref) {
    // Theme E (diagnose 2026-05-22 0e7714) — surface only from Thursday
    // of Phase Week 4 onwards. Founder's stated expectation 2026-05-21:
    // "should open up on thursday of the last week". Pre-fix gate was
    // `plan.currentWeek < 4` which surfaced from Monday of Week 4 —
    // too early. Locked Thursday gives users a 4-day runway (Thu, Fri,
    // Sat, Sun) to complete and tap unlock.
    //
    // LOCAL weekday on purpose — `weekday` rollover at local midnight
    // matches when the user perceives "Thursday begins". Applying the
    // IST shift would cause Indian users to see the CTA appear at
    // 05:30 local for no good reason (and Indians outside IST would
    // see it shift further). Different from date-key math (which is
    // IST per CLAUDE.md §4.5) — UI presence is a perceptual concern.
    if (plan.currentWeek != 4 ||
        DateTime.now().weekday < DateTime.thursday) {
      return const SizedBox.shrink();
    }

    // Check completion rate for Phase 1 graduation
    final completionRate = _computePhaseCompletionRate(plan);
    final canGraduate =
        completionRate >= AppConstants.phaseUnlockCompletionRate;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: WardCard(
        variant: WardCardVariant.hero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  canGraduate ? Icons.emoji_events : Icons.lock,
                  size: 16,
                  color: AppColors.proGold,
                ),
                const SizedBox(width: 8),
                Text(
                  canGraduate ? 'PHASE 1 COMPLETE!' : 'PHASE 2 AVAILABLE',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.proGold,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canGraduate
                  ? 'You crushed Phase 1 with ${(completionRate * 100).round()}% completion! View your achievements and unlock Phase 2.'
                  : 'Great progress! Unlock Phase 2 to continue building strength with new exercises and progressive overload.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            WardButton(
              label: canGraduate
                  ? 'VIEW YOUR ACHIEVEMENT'
                  : 'UNLOCK PHASE 2',
              onPressed: () {
                if (canGraduate) {
                  context.go('/train/graduation');
                  return;
                }
                SubscriptionService.instance.gate(
                  AppConstants.featurePhases2To12,
                  onPro: () {
                    context.go('/train/graduation');
                  },
                  onFree: () => showPaywallSheet(
                    context,
                    feature: 'Phases 2-12',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Compute Phase 1 completion rate across all 4 weeks. Byte-identical to the
  /// prior inline loop — delegated to the shared `phaseCompletionRate` primitive
  /// (⑧ 8-A/D1) so the (8-B) advance seam reads the SAME rule (no drift).
  double _computePhaseCompletionRate(CurrentPlanData plan) {
    return phaseCompletionRate([
      for (int w = 1; w <= plan.weeks.length; w++)
        for (final day in plan.getWeek(w))
          (isRest: day.isRest, isDone: day.isDone),
    ]);
  }
}
