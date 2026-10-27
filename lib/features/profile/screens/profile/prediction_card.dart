part of 'screen.dart';

extension _PredictionCard on _ProfileScreenState {

  // ── Bug #14 Prediction Card (moved from home_screen) ────────────

  Widget _buildPredictionCard() {
    final prediction = ref.watch(predictionProvider);
    // APK Test #12 / Task C-2 — watch subscriptionInfoProvider so the
    // prediction-card refresh affordance updates reactively after PRO upgrade.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    // audit-2026-05-16 reader-side / R7 — surface real onboarding state
    // so the empty-state copy stops blaming the user when their account
    // IS onboarded but `prediction_text` simply hasn't been generated
    // (e.g. fresh install on a returning account where prediction was
    // never restored from cloud). userProfileProvider is the canonical
    // Hive source; cloud sync writes back to the same map.
    final profile = ref.watch(userProfileProvider);
    final onboardingCompleted =
        profile['onboarding_completed_at'] != null;
    // First prediction is free per CLAUDE.md section 14. Surface UPDATE
    // affordance for onboarded users with no prediction yet regardless
    // of tier.
    final hasPrediction = (prediction.predictionText ?? '').isNotEmpty;
    final emptyCtaEnabled = !hasPrediction && onboardingCompleted;
    return PredictionCard(
      predictionText: prediction.predictionText,
      generatedAt: prediction.generatedAt,
      isPro: isPro,
      canRefresh: prediction.canRefresh,
      isStale: prediction.isStale,
      onboardingCompleted: onboardingCompleted,
      onRefreshTap: (isPro || emptyCtaEnabled)
          ? _refreshPrediction
          : () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  'Prediction refresh is a PRO feature. Upgrade in Profile \u2192 Subscription',
                  style: AppTypography.bodyM,
                ),
                backgroundColor: AppColors.proGold,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ));
            },
    );
  }
}
