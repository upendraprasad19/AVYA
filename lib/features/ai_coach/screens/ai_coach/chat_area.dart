part of 'screen.dart';

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
}
