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
                  : 'Connect to Telegram',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 8),
            Text(
              telegramConnected
                  ? 'Your AI coach is available on Telegram. Open the app to continue your conversation.'
                  : 'Chat with your AI coach on Telegram for quick access anytime.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textDim,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Sharp 2-px slab CTA
            GestureDetector(
              onTap: () => _openTelegramBot(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                decoration: BoxDecoration(
                  color: telegramConnected
                      ? AppColors.info.withValues(alpha: 0.14)
                      : AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  border: telegramConnected
                      ? Border.all(color: AppColors.info, width: 2)
                      : null,
                ),
                child: Text(
                  telegramConnected
                      ? 'OPEN TELEGRAM'
                      : 'CONNECT @AVYACOACHBOT',
                  style: AppTypography.mono.copyWith(
                    color: telegramConnected
                        ? AppColors.info
                        : AppColors.bgDeep,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
