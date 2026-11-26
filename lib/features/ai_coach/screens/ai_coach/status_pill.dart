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
    return CoachFreeStatusPill(
      onTap: () =>
          showPaywallSheet(context, feature: 'Higher daily AI coach limit'),
    );
  }
}

/// The FREE account's status pill in the coach header (OI-348 walk P4,
/// founder 2026-11-22). A build that sells PRO draws the gold UPGRADE pill. A
/// build that sells nothing (ADR-0022, `showsUpgradeAffordance()` false)
/// draws the same "PRO" word as a dim grey outline, so it no longer reads as
/// a PRO status badge on a free account; the tap (the info sheet) is the same.
class CoachFreeStatusPill extends StatelessWidget {
  const CoachFreeStatusPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sells = showsUpgradeAffordance();
    final ink = sells ? AppColors.accent : AppColors.textDim;
    final pill = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sells ? AppColors.accentSoft : null,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: sells
              ? Border.all(color: AppColors.accent, width: 2)
              : Border.all(color: AppColors.textMute, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The arrow is an upgrade glyph: a no-purchase build omits it.
            if (showsUpgradeAffordance()) ...const [
              Icon(Icons.arrow_upward, size: 12, color: AppColors.accent),
              SizedBox(width: 4),
            ],
            Text(
              showsUpgradeAffordance() ? 'UPGRADE' : PurchaseCopy.proInfo,
              style: AppTypography.mono.copyWith(
                color: ink,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
    if (sells) return pill;
    // The word is the same PRO a PRO account sees; say what it is.
    return Semantics(
      button: true,
      label: PurchaseCopy.proPillFreeLabel,
      excludeSemantics: true,
      child: pill,
    );
  }
}
