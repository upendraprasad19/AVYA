part of 'screen.dart';

extension _DangerZone on _ProfileScreenState {

  // ── #9 Danger Zone ──────────────────────────────────────────────

  Widget _buildDangerZone() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'DANGER ZONE',
          style: AppTypography.mono.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
        iconColor: AppColors.textMute,
        collapsedIconColor: AppColors.textMute,
        children: [
          GestureDetector(
            // Task H1 (APK Test #11): Navigate to the 2-step hard-delete
            // screen instead of the old soft-delete AlertDialog.
            onTap: () => context.push('/profile/delete-account'),
            child: Text(
              'Delete Account',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.bad,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
