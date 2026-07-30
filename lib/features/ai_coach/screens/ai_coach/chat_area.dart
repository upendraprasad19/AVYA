part of 'screen.dart';

// Round-2 review (2026-07-30) — same analyzer limitation media_picker.dart
// and recording_body.dart already carry this exact ignore for: `setState`
// is @protected on State, and the analyzer doesn't model "extension on the
// same State subclass" as an allowed access site even though the runtime
// semantics are fine. Needed once _onSaveCoachMedia/_onDeclineCoachMedia
// started calling setState for the isSavingMedia in-flight UI signal.
// ignore_for_file: invalid_use_of_protected_member

extension _ChatArea on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // CHAT AREA — clean, messages only
  // ────────────────────────────────────────────────────────────────

  Widget _buildChatArea(List<ChatMessage> messages, bool isSending) {
    // If no messages yet, show welcome
    if (messages.isEmpty) {
      return _buildWelcomeView();
    }

    // Pending log actions (instant: water, weight, food, sleep, measurement)
    final pendingActions = ref
        .watch(pendingLogActionsProvider)
        .where((a) => !a.isDismissed)
        .toList();
    // Workout draft (multi-turn workout confirmation)
    final hasWorkoutDraft = ref.watch(workoutDraftProvider) != null;

    // Phase A.11 — typed tool intents (pending + recently-settled, kept by prune)
    // C-6: secondary filter on the Hive `intent_<id>_dispatched_at` marker.
    // Routed through static AiCoachScreen.filterVisibleIntents so the contract
    // is unit-testable (B-5 dispatched_card_filter_test). Primary state of
    // truth remains ToolIntent.status.
    final visibleIntents = AiCoachScreen.filterVisibleIntents(
      ref.watch(pendingToolIntentsProvider),
    );

    final totalItems = messages.length +
        pendingActions.length +
        (hasWorkoutDraft ? 1 : 0) +
        visibleIntents.length;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Chat messages first
        if (index < messages.length) {
          final message = messages[index];

          // Unit 1 (coach-completion-tap-card) — a completion-prompt row
          // renders a dedicated two-button coach tile, NOT a chat bubble.
          if (message.kind == 'completion_prompt' &&
              message.promptData != null) {
            final data = message.promptData!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CompletionPromptCard(
                planned: data.planned,
                logged: data.logged,
                isBusy: _completingPromptDate == data.date,
                onComplete: () => _onCompleteWorkoutFromPrompt(data.date),
                onLogMore: () => _onLogMoreFromPrompt(data.date),
              ),
            );
          }

          final time =
              '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

          // Bug #19 — Wire Retry button on failed AI bubbles. The provider
          // will reuse the same coachBox row (via existingCoachKey) so
          // history doesn't duplicate on retry.
          final canRetry = message.isError &&
              !message.isUser &&
              message.retryUserMessage != null &&
              message.retryUserMessage!.isNotEmpty &&
              message.coachKey != null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChatBubble(
              text: message.text,
              isUser: message.isUser,
              isLoading: message.isLoading,
              isError: message.isError,
              timestamp: time,
              mediaUrl: message.mediaUrl,
              mediaType: message.mediaType,
              // Bug 2026-05-16 photo-analysis-500 — wire `mediaFailed` so
              // the bubble swaps the broken-image icon for the explicit
              // "PHOTO FAILED — Tap to retry" tile when upload didn't
              // complete or `ai-media-proxy` returned error_type='storage'.
              mediaFailed: message.mediaFailed,
              // Tapping the failed tile re-opens the gallery picker so the
              // user can pick the photo again without retyping the caption.
              onMediaRetry: message.mediaFailed
                  ? () => _pickImage(ImageSource.gallery)
                  : null,
              onRetry: canRetry
                  ? () {
                      ref.read(sendMessageProvider.notifier).send(
                            message.retryUserMessage!,
                            existingCoachKey: message.coachKey,
                          );
                    }
                  : null,
              // Unit 8 (coach-media-consent, OI-25) — save-consent chip.
              mediaAnalysisComplete: message.mediaAnalysisComplete,
              mediaSaveState: message.mediaSaveState,
              onSaveMedia: (message.isUser &&
                      message.coachKey != null &&
                      message.mediaStoragePath != null)
                  ? () => _onSaveCoachMedia(
                      message.coachKey!, message.mediaStoragePath!)
                  : null,
              onDeclineMedia: (message.isUser && message.coachKey != null)
                  ? () => _onDeclineCoachMedia(message.coachKey!)
                  : null,
              // Round-2 review — in-flight visual state for the chip.
              isSavingMedia: message.coachKey != null &&
                  _savingCoachMediaKeys.contains(message.coachKey),
            ),
          );
        }

        // Pending instant log action cards
        final offset = index - messages.length;
        if (offset < pendingActions.length) {
          return LogConfirmCard(action: pendingActions[offset]);
        }

        // Workout draft confirm card (after legacy log actions)
        var afterActions = offset - pendingActions.length;
        if (hasWorkoutDraft && afterActions == 0) {
          return const WorkoutLogConfirmCard();
        }
        if (hasWorkoutDraft) afterActions -= 1;

        // Phase A.11 — typed tool intent confirmation widgets
        if (afterActions < visibleIntents.length) {
          final intent = visibleIntents[afterActions];
          if (intent.confirmationClass == ConfirmationClass.destructive) {
            return _buildDestructiveIntentTile(context, intent);
          }
          return ToolConfirmCard(intent: intent);
        }

        // Defensive fallback — shouldn't be reached given totalItems math
        return const SizedBox.shrink();
      },
    );
  }

  // Unit 8 (coach-media-consent, OI-25) — consent-chip handlers.

  /// Copies the chat-media photo into coach-media (long-term retention) and
  /// records the decision on the coach_* row. Guards against a rapid
  /// double-tap re-firing the copy while the first attempt is in flight.
  /// On failure, leaves `mediaSaveState` untouched so the chip re-offers a
  /// retry rather than silently pretending the save happened.
  Future<void> _onSaveCoachMedia(
      String coachKey, String mediaStoragePath) async {
    if (_savingCoachMediaKeys.contains(coachKey)) return;
    // Synchronous add, before any await — the check above and this add
    // together form an atomic check-then-act on Dart's single-threaded
    // event loop, so a rapid second tap in the same frame can't slip
    // through. setState so the chip's isSavingMedia spinner renders
    // immediately (round-2 review — the prior version mutated the set
    // with no visual signal, so a slow network read as "did nothing").
    setState(() => _savingCoachMediaKeys.add(coachKey));
    try {
      final saved =
          await CoachMediaRepository.instance.saveForLater(mediaStoragePath);
      if (saved) {
        await AiCoachRepository.instance
            .recordMediaSaveDecision(coachKey, saved: true);
      }
      if (!mounted) return;
      ref.read(chatHistoryProvider.notifier).updateMessageMediaState(
            coachKey,
            mediaSaveState: saved ? 'saved' : null,
          );
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn\'t save that photo — please try again.',
              style: AppTypography.body.copyWith(color: AppColors.bad),
            ),
            backgroundColor: AppColors.card,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingCoachMediaKeys.remove(coachKey));
      } else {
        _savingCoachMediaKeys.remove(coachKey);
      }
    }
  }

  /// Records a decline so the chip doesn't re-prompt on rebuild. No Storage
  /// call — the chat-media source is left exactly as-is (still governed by
  /// the existing 30-day free-tier cleanup / PRO retention).
  ///
  /// Round-1 review (coach-media-consent, 2026-07-30) — guarded against a
  /// race with an in-flight `_onSaveCoachMedia` for the SAME coachKey: if a
  /// user taps SAVE then NO THANKS before the copy resolves, the save's own
  /// completion unconditionally writes `saved` and would silently clobber
  /// an already-recorded decline the user explicitly made. The interactive
  /// chip is only ever visible while `mediaSaveState == null` (ChatBubble's
  /// gate), so this guard's window exactly covers the time a decline tap
  /// could physically land — the save's completion updates
  /// mediaSaveState to 'saved' before releasing this guard, which flips
  /// the UI to the non-interactive badge before any further tap is
  /// possible. No-ops (silently ignores the tap) rather than queuing it —
  /// proportionate for a sub-second network-round-trip window; the chip
  /// remains visible so the user can decline again once the save settles
  /// if they still want to.
  ///
  /// Round-2 review (2026-07-30) — the guard above was one-directional: it
  /// stopped decline-during-save, but nothing stopped the reverse. This
  /// handler's own `recordMediaSaveDecision` write (a sub-millisecond Hive
  /// `put`) plus the state-update `await` left a narrow window where a SAVE
  /// tap landing in between would start a copy that later overwrites the
  /// decline back to `'saved'`. Now takes the SAME `_savingCoachMediaKeys`
  /// lock `_onSaveCoachMedia` does — full mutual exclusion, not one-sided —
  /// and `isSavingMedia` on the chip disables BOTH tap targets during the
  /// (now slightly longer, but still sub-second) window, closing the race
  /// at the UI layer too.
  Future<void> _onDeclineCoachMedia(String coachKey) async {
    if (_savingCoachMediaKeys.contains(coachKey)) return;
    setState(() => _savingCoachMediaKeys.add(coachKey));
    try {
      await AiCoachRepository.instance
          .recordMediaSaveDecision(coachKey, saved: false);
      if (!mounted) return;
      ref
          .read(chatHistoryProvider.notifier)
          .updateMessageMediaState(coachKey, mediaSaveState: 'declined');
    } finally {
      if (mounted) {
        setState(() => _savingCoachMediaKeys.remove(coachKey));
      } else {
        _savingCoachMediaKeys.remove(coachKey);
      }
    }
  }
}
