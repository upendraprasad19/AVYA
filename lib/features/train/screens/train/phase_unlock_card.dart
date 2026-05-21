part of 'screen.dart';

extension _PhaseUnlockCard on _TrainScreenState {
  // ── Phase Unlock Card ─────────────────────────────────────────

  Widget _buildPhaseUnlockCard(
      BuildContext context, CurrentPlanData plan, WidgetRef ref) {
    // Only show if user has reached week 4
    if (plan.currentWeek < 4) return const SizedBox.shrink();

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

  /// Compute Phase 1 completion rate across all 4 weeks.
  double _computePhaseCompletionRate(CurrentPlanData plan) {
    int totalWorkoutDays = 0;
    int completedDays = 0;

    for (int w = 1; w <= plan.weeks.length; w++) {
      final weekDays = plan.getWeek(w);
      for (final day in weekDays) {
        if (!day.isRest) {
          totalWorkoutDays++;
          if (day.isDone) completedDays++;
        }
      }
    }

    if (totalWorkoutDays == 0) return 0.0;
    return completedDays / totalWorkoutDays;
  }
}
