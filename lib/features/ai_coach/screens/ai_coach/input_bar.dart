part of 'screen.dart';

extension _InputBar on _AiCoachScreenState {

  // ────────────────────────────────────────────────────────────────
  // INPUT BAR — with inline message counter
  // ────────────────────────────────────────────────────────────────

  Widget _buildInputBar(
      bool isSending, int messageCount, bool isPro, TrialInfoData trialInfo) {
    final isLimitReached = !isPro &&
        (messageCount >= AppConstants.freeAiMessagesPerDay ||
            trialInfo.isTrialExpired);

    final isWarning =
        !isPro && messageCount >= AppConstants.freeAiMessagesPerDay - 3;

    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // F12 · Single 48dp rounded bubble — TextField + paperclip + morph button
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: _isRecording
                  ? AppColors.bad.withValues(alpha: 0.08)
                  : AppColors.input,
              border: Border.all(
                color: _isRecording ? AppColors.bad : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Test #10 obs 5 — compass-rose button left of input.
                // Tap → segregated bottom sheet with 4 family groups.
                // Selecting a command prefills the composer; user edits
                // before sending. Hidden during voice recording so the
                // bubble doesn't get crowded with 3 controls + slider.
                if (!_isRecording)
                  IconButton(
                    icon: const Icon(
                      Icons.explore_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    tooltip: 'Compass · tools',
                    onPressed: isSending
                        ? null
                        : () => CompassToolsSheet.show(
                              context,
                              onSelect: (prefill) {
                                _messageController.text = prefill;
                                _messageController.selection =
                                    TextSelection.collapsed(
                                  offset: prefill.length,
                                );
                                _inputFocusNode.requestFocus();
                              },
                            ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                Expanded(
                  child: _isRecording
                      ? _buildRecordingBody()
                      : TextField(
                          controller: _messageController,
                          focusNode: _inputFocusNode,
                          enabled: !isLimitReached && !isSending,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: isLimitReached
                                ? 'Daily limit reached \u2014 Go PRO'
                                : 'Ask your coach\u2026',
                            hintStyle: AppTypography.body.copyWith(
                              fontSize: 14,
                              color: isLimitReached
                                  ? AppColors.proGold
                                  : AppColors.textDim,
                            ),
                            contentPadding: EdgeInsets.zero,
                            isCollapsed: true,
                          ),
                          style: AppTypography.body.copyWith(fontSize: 14),
                          onSubmitted: (_) => _maybeSendText(isPro),
                        ),
                ),
                if (!_isRecording)
                  IconButton(
                    icon: const Icon(Icons.attach_file,
                        color: AppColors.accent, size: 20),
                    onPressed:
                        isSending ? null : () => _onTapAttach(isPro),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                GestureDetector(
                  onTap: () {
                    if (_isRecording) return;
                    if (isSending || isLimitReached) return;
                    if (hasText) {
                      _maybeSendText(isPro);
                    } else {
                      _showHoldToTalkTooltip();
                    }
                  },
                  onLongPressStart: hasText || isSending || isLimitReached
                      ? null
                      : (details) {
                          _startRecordingPushToTalk(details.globalPosition);
                        },
                  onLongPressMoveUpdate:
                      hasText || isSending || isLimitReached
                          ? null
                          : (details) {
                              _updateRecording(details.globalPosition);
                            },
                  onLongPressEnd: hasText || isSending || isLimitReached
                      ? null
                      : (details) {
                          _stopRecordingPushToTalk(
                              send: !_slideToCancel, isPro: isPro);
                        },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Container(
                      key: ValueKey(_isRecording
                          ? 'recording'
                          : (hasText ? 'send' : 'mic')),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            _isRecording ? AppColors.bad : AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isRecording
                            ? Icons.mic
                            : (hasText ? Icons.arrow_upward : Icons.mic),
                        color: AppColors.bg,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Inline message counter — only when top trial banner is NOT shown
          // (trial active users already see the counter in the banner above)
          if (!isPro && !trialInfo.isTrialActive) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$messageCount/${AppConstants.freeAiMessagesPerDay} TODAY',
                  style: AppTypography.monoXs.copyWith(
                    color: isWarning
                        ? AppColors.warn
                        : AppColors.textMute,
                    letterSpacing: 1.4,
                  ),
                ),
                if (trialInfo.isTrialActive &&
                    !trialInfo.isTrialExpired &&
                    trialInfo.daysRemaining <= 7) ...[
                  Text(
                    '  \u00B7  ${trialInfo.daysRemaining}D TRIAL LEFT',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.warn,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
                if (isWarning && !isLimitReached) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => showPaywallSheet(context,
                        feature: 'Unlimited AI Coach'),
                    child: Text(
                      'GO PRO',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.proGold,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
