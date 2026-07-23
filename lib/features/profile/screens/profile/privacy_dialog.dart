part of 'screen.dart';

extension _PrivacyDialog on _ProfileScreenState {

  // ── Privacy Dialog ──────────────────────────────────────────────

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Privacy & Permissions',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your data is stored locally on your device. Supabase is used only for backups, AI, and community features.',
              style: AppTypography.body
                  .copyWith(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'PERMISSIONS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '\u2022 Camera: Meal scanning\n\u2022 Health Connect: Steps & sleep\n\u2022 Storage: Progress photos',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _launchUrl('https://icanbefitter.com/privacy'),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Read our Privacy Policy',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _launchUrl('https://icanbefitter.com/terms'),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Terms of Service',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CLOSE',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
