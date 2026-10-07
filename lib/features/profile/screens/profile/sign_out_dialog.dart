part of 'screen.dart';

extension _SignOutDialog on _ProfileScreenState {

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'CONFIRM SIGN OUT',
          style: AppTypography.mono.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out? Your data is safe locally.',
          style: AppTypography.body.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCEL',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          WardButton(
            label: 'Sign Out',
            variant: WardButtonVariant.danger,
            fullWidth: false,
            size: WardButtonSize.small,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performSignOut();
            },
          ),
        ],
      ),
    );
  }
}
