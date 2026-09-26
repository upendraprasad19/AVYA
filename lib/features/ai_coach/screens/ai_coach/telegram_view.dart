part of 'screen.dart';

extension _TelegramView on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // TELEGRAM VIEW
  // ────────────────────────────────────────────────────────────────

  Widget _buildTelegramView(bool telegramConnected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send,
                color: AppColors.info,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              telegramConnected
                  ? 'Telegram Connected'
                  : 'Telegram — Coming Soon',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 8),
            Text(
              telegramConnected
                  ? 'Your AI coach is available on Telegram. Open the app to continue your conversation.'
                  // OI-227 — connect flow removed 2026-09-21: no working
                  // account-linking handshake yet. Revisit in phase 2.
                  : 'We\'re rebuilding Telegram sign-in. Check back soon.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textDim,
                height: 1.5,
              ),
            ),
            if (telegramConnected) ...[
              const SizedBox(height: 24),
              // Sharp 2-px slab CTA
              GestureDetector(
                onTap: () => _openTelegramBot(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                    border: Border.all(color: AppColors.info, width: 2),
                  ),
                  child: Text(
                    'OPEN TELEGRAM',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.info,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
