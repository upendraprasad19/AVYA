part of 'screen.dart';

extension _StatusPill on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // STATUS PILL — non-tappable gold "PRO" badge for PRO users,
  // tappable accent "Upgrade to PRO" for free users.
  //
  // 2026-04-18 · Replaced the Chat / Reasoning two-tab toggle. Per user
  // feedback the two backends (ai-proxy + ai-proxy-pro) were merged into
  // a single Gemini-backed endpoint, so there's no user-facing choice to
  // make here any more — free vs PRO differentiation is entirely the
  // 15-msg daily cap enforced server-side.
  // ────────────────────────────────────────────────────────────────

  Widget _buildStatusPill(bool isPro) {
    if (isPro) {
      // Informational badge only — no tap handler. Users manage their
      // subscription from Profile → Subscription.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.proGoldTint,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.proGold, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium,
                size: 12, color: AppColors.proGold),
            const SizedBox(width: 4),
            Text(
              'PRO',
              style: AppTypography.mono.copyWith(
                color: AppColors.proGold,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    // Free user — tap opens paywall.
    return GestureDetector(
      onTap: () =>
          showPaywallSheet(context, feature: 'Unlimited AI Coach'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward,
                size: 12, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              'UPGRADE',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
