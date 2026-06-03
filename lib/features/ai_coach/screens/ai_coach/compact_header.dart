part of 'screen.dart';

extension _CompactHeader on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // COMPACT HEADER — single row replaces old header + channel + reasoning
  // ────────────────────────────────────────────────────────────────

  Widget _buildCompactHeader(
      bool isPro, String channel, bool telegramConnected) {
    // F11 · Test #9 — Coach header restructured to 2 rows + counter
    // glued under UPGRADE pill. Captain-cap SVG replaces the "AI" text avatar.
    final messageCount = ref.watch(messageLimitProvider);
    final trialInfo = ref.watch(trialInfoProvider);
    final daysRemaining = trialInfo.daysRemaining;
    final cap = AppConstants.freeAiMessagesPerDay;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.33),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ROW 1 — eyebrow alone, full width
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnchorGlyph(size: 10),
              const SizedBox(width: 8),
              Text(
                'THE BRIDGE · 24/7',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ROW 2 — avatar + 26sp italic title + UPGRADE column (with counter under)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Captain-cap avatar
              Stack(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 1.5),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/coach/captain_cap.svg',
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(
                          AppColors.accent,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.ok,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.header, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                // Obs 2 sweep (2026-06-02) — uniform shrink-to-fit across all
                // tab headers so the title never clips on the narrowest phones.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Aye Captain',
                    style: AppTypography.h3.copyWith(
                      fontSize: 26,
                      height: 1.0,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              // Trailing column — UPGRADE pill on top + counter glued below
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusPill(isPro),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textDim,
                          size: 20,
                        ),
                        color: AppColors.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          side: const BorderSide(color: AppColors.line2),
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'switch_channel':
                              final newChannel =
                                  channel == 'in_app' ? 'telegram' : 'in_app';
                              ref
                                  .read(channelProvider.notifier)
                                  .setChannel(newChannel);
                              break;
                            case 'telegram':
                              _openTelegramBot();
                              break;
                            case 'clear':
                              ref.invalidate(chatHistoryProvider);
                              break;
                            case 'upgrade':
                              showPaywallSheet(context,
                                  feature: 'Unlimited AI Coach');
                              break;
                          }
                        },
                        itemBuilder: (context) => _menuItemsForChannel(
                            channel, telegramConnected, isPro),
                      ),
                    ],
                  ),
                  // Counter glued directly under UPGRADE, no spacing
                  if (!isPro)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 30),
                      child: Text(
                        '$messageCount / $cap MSGS · $daysRemaining D TRIAL',
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 9,
                          color: AppColors.textMute,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // F11 · Test #9 — extracted PopupMenu items so the header body
  // stays readable. Behaviour preserved verbatim from the prior inline list.
  List<PopupMenuEntry<String>> _menuItemsForChannel(
      String channel, bool telegramConnected, bool isPro) {
    return [
      PopupMenuItem(
        value: 'switch_channel',
        child: Row(
          children: [
            Icon(
              channel == 'in_app' ? Icons.send : Icons.chat,
              size: 16,
              color: AppColors.textDim,
            ),
            const SizedBox(width: 10),
            Text(
              channel == 'in_app'
                  ? 'Switch to Telegram'
                  : 'Switch to In-App Chat',
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
      if (!telegramConnected)
        PopupMenuItem(
          value: 'telegram',
          child: Row(
            children: [
              const Icon(Icons.link, size: 16, color: AppColors.info),
              const SizedBox(width: 10),
              Text(
                'Connect @AVYACoachBot',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'clear',
        child: Row(
          children: [
            const Icon(Icons.delete_outline,
                size: 16, color: AppColors.textDim),
            const SizedBox(width: 10),
            Text(
              'Clear conversation',
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
      if (!isPro)
        PopupMenuItem(
          value: 'upgrade',
          child: Row(
            children: [
              const Icon(Icons.star, size: 16, color: AppColors.proGold),
              const SizedBox(width: 10),
              Text(
                'Upgrade to PRO',
                style: AppTypography.body.copyWith(
                  color: AppColors.proGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
