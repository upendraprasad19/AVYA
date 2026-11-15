part of 'screen.dart';

extension _CompactHeader on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // COMPACT HEADER — single row replaces old header + channel + reasoning
  // ────────────────────────────────────────────────────────────────

  Widget _buildCompactHeader(bool isPro) {
    // F11 · Test #9 — Coach header restructured to 2 rows + counter
    // glued under UPGRADE pill. Captain-cap SVG replaces the "AI" text avatar.
    final messageCount = ref.watch(messageLimitProvider);
    final cap = AppConstants.freeAiMessagesPerDay;
    // OI-479 — "Clear conversation" is disabled while a reply is in flight
    // (text `send` and `sendWithMedia` both hold this flag).
    final isSending = ref.watch(sendMessageProvider);

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
                            case 'clear':
                              unawaited(
                                  confirmClearCoachConversation(context, ref));
                              break;
                            case 'upgrade':
                              showPaywallSheet(context,
                                  feature: 'Higher daily AI coach limit');
                              break;
                          }
                        },
                        itemBuilder: (context) =>
                            coachHeaderMenuItems(isPro: isPro, isSending: isSending),
                      ),
                    ],
                  ),
                  // Counter glued directly under UPGRADE, no spacing
                  if (!isPro)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 30),
                      child: Text(
                        '$messageCount / $cap MSGS TODAY',
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
}

/// OI-479 (diagnose 5970aa) — "Clear conversation". HIDES the thread (the
/// marker in `CoachChatClear`); nothing is deleted and the coach keeps its
/// long-term memory. Asks first. A reply that started while the dialog was
/// open (a retry tap, a photo upload finishing into `sendWithMedia`) cancels
/// the clear: that turn's row predates the marker, so its reply would vanish.
/// Pending action cards (meal / workout / tool APPLY) are deliberately left
/// alone (coordinator call C2: they are actions, not conversation).
///
/// A top-level function so a widget test can drive it with a real `ref`.
Future<void> confirmClearCoachConversation(
    BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(
        'Clear this chat?',
        style: AppTypography.body.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        'Messages leave this screen. Your coach still remembers your '
        'goals, injuries and preferences.',
        style: AppTypography.body.copyWith(color: AppColors.textDim),
      ),
      actions: [
        TextButton(
          key: const ValueKey('coach_clear_cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          key: const ValueKey('coach_clear_confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('CLEAR', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  if (ref.read(sendMessageProvider)) return;
  // The header runs this unawaited: a throw here (the user box closed by a
  // sign-out mid-flow) would reach the zone as an uncaught error. Report it
  // and tell the user nothing was cleared (B-pass F2).
  final bool cleared;
  try {
    cleared = await CoachChatClear.clear();
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'coach_chat_clear_failed'));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't clear this chat. Try again.",
            style: AppTypography.body.copyWith(color: AppColors.bad),
          ),
          backgroundColor: AppColors.card,
        ),
      );
    }
    return;
  }
  if (!cleared || !context.mounted) return;
  ref.invalidate(chatHistoryProvider);
}

/// The AI Coach overflow menu (OI-466). A top-level function, not a member of
/// the `_CompactHeader` extension, so a test can pump the exact entries the
/// real header offers: it needs no `ref` and no `context`. The menu holds
/// `Clear conversation` and, on a free account, `Upgrade to PRO`. There is no
/// channel switch: Telegram is dropped, and with it the toggle and the
/// "Coming Soon" view the toggle led to.
///
/// OI-479: `Clear conversation` is disabled while [isSending] (a reply is in
/// flight); it opens a confirmation dialog in the header's handler.
List<PopupMenuEntry<String>> coachHeaderMenuItems({
  required bool isPro,
  bool isSending = false,
}) {
  return [
    PopupMenuItem(
      value: 'clear',
      enabled: !isSending,
      child: Row(
        children: [
          const Icon(Icons.delete_outline, size: 16, color: AppColors.textDim),
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
