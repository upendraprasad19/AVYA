part of 'screen.dart';

// ────────────────────────────────────────────────────────────────
// COACH COMPOSER: the input bar with its mic / send morph and the speech
// session (plan `docs/plans/voice-input-unified.md`, D4).
//
// A PUBLIC widget (the first in a part file), extracted from the screen so
// Stop and Send can be tested alone: nothing can pump `AiCoachScreen`, and
// "Stop sends nothing, Send sends once" had no seam before. It lives in this
// file (same library as the screen) so the source pins that read the screen
// folder keep reading it.
//
// Tap the mic to start; tap Stop to keep the words in the field (edit,
// rephrase); tap Send to stop and send in one tap; tap X to discard. Stop never
// calls `onSend`; Send calls it once with the words, after writing them into
// the controller exactly as typing would have.
// ────────────────────────────────────────────────────────────────

class CoachComposer extends ConsumerStatefulWidget {
  const CoachComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.messageCount,
    required this.isPro,
    required this.onSend,
    required this.onAttach,
    required this.onListeningChanged,
  });

  /// The message field's controller (the screen owns it, so a Compass prefill
  /// and the send path see the same text).
  final TextEditingController controller;

  /// The SAME node `MeasurementChipSlot` gets: the chip hides while it has focus.
  final FocusNode focusNode;
  final bool isSending;
  final int messageCount;
  final bool isPro;

  /// The screen's gated send path (daily limit, paywall, then the send).
  final void Function(String text) onSend;
  final VoidCallback onAttach;

  /// True while a speech session is starting or listening. The field is not
  /// mounted then, so the screen hides the measurement chip through this.
  final ValueChanged<bool> onListeningChanged;

  @override
  ConsumerState<CoachComposer> createState() => _CoachComposerState();
}

class _CoachComposerState extends ConsumerState<CoachComposer> {
  late final SpeechInputController _speech;

  /// The shortest message the coach sends: typing "ok" sends today.
  static const int _minChars = 1;

  bool get _isLimitReached =>
      !widget.isPro && widget.messageCount >= AppConstants.freeAiMessagesPerDay;

  @override
  void initState() {
    super.initState();
    final service = ref.read(speechInputServiceProvider);
    _speech = SpeechInputController(
      service: service,
      onEnd: _onSpeechEnd,
      onBusyChanged: (busy) => widget.onListeningChanged(busy),
    );
    widget.controller.addListener(_onTextChanged);
    // Web: ask the browser whether a recognizer exists (no permission prompt).
    if (service.isWeb) unawaited(_speech.probeSupport());
  }

  @override
  void didUpdateWidget(CoachComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    // A turn started while the mic was on (a quick prompt, say): keep the words
    // in the field and leave the bar. Deferred: this runs during build, and the
    // end notifies the screen.
    if (!old.isSending && widget.isSending && _speech.isBusy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isSending) _speech.endForHidden();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    final wasBusy = _speech.isBusy;
    final onListeningChanged = widget.onListeningChanged;
    _speech.dispose(); // no host callback for `disposed`: tell the screen after
    if (wasBusy) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onListeningChanged(false));
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  // -- speech ---------------------------------------------------------------

  Future<void> _onMicTap() async {
    if (_isLimitReached || widget.isSending) return; // inert, as today
    await _speech.toggle();
  }

  /// The prefix is read at COMMIT time, never at start: `_doSend` can clear the
  /// controller while the field is unmounted, and a prefix captured at start
  /// would resurrect text that was already sent.
  String _join(String words) {
    final typed = widget.controller.text.trim();
    final spoken = words.trim();
    if (typed.isEmpty) return spoken;
    if (spoken.isEmpty) return typed;
    return '$typed $spoken';
  }

  void _writeField(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onSpeechEnd(SpeechSessionEnd end) {
    if (!mounted) return;
    final combined = _join(end.transcript);
    final action = decideSpeechEnd(
      SpeechSessionEnd(
        transcript: combined,
        reason: end.reason,
        failure: end.failure,
        empty: end.empty,
      ),
      minChars: _minChars,
    );
    switch (action) {
      case SpeechEndAction.commit:
        // Stop: the words stay in the field to edit or rephrase. Nothing sent.
        _writeField(combined);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.focusNode.requestFocus();
        });
      case SpeechEndAction.send:
        // Write first, then send, exactly as typing; the screen's gate clears
        // the field on a real send and shows the paywall at the limit.
        _writeField(combined);
        widget.onSend(combined);
      case SpeechEndAction.tooShort:
        _writeField(combined);
      case SpeechEndAction.discard:
      case SpeechEndAction.none:
        break;
    }
    final message = SpeechInputCopy.messageFor(end);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
          backgroundColor: AppColors.card,
        ),
      );
    }
  }

  // -- send / prefill ---------------------------------------------------------

  void _maybeSendText() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    // Reuse the screen's gated send path (handles trial + daily cap + paywall).
    widget.onSend(text);
  }

  /// B4 — inserts a composed Compass prefill into the composer and focuses
  /// it (the exact behaviour the compass onSelect previously inlined).
  void _applyPrefill(String prefill) {
    widget.controller.text = prefill;
    widget.controller.selection = TextSelection.collapsed(
      offset: prefill.length,
    );
    widget.focusNode.requestFocus();
  }

  // -- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isLimitReached = _isLimitReached;
    final isWarning = !widget.isPro &&
        widget.messageCount >= AppConstants.freeAiMessagesPerDay - 3;

    return SpeechInputLifecycle(
      controller: _speech,
      child: ListenableBuilder(
        listenable: _speech,
        builder: (context, _) {
          final busy = _speech.isBusy;
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(
              color: AppColors.bg,
              border: Border(top: BorderSide(color: AppColors.line2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // F12 · Single 48dp rounded bubble — field + paperclip + morph button
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: busy
                        ? AppColors.bad.withValues(alpha: 0.08)
                        : AppColors.input,
                    border: Border.all(
                      color: busy ? AppColors.bad : AppColors.border,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                  child: busy ? _buildListeningBar() : _buildIdleRow(isLimitReached),
                ),

                // Inline message counter — free users only.
                if (!widget.isPro) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.messageCount}/${AppConstants.freeAiMessagesPerDay} TODAY',
                        style: AppTypography.monoXs.copyWith(
                          color: isWarning
                              ? AppColors.warn
                              : AppColors.textMute,
                          letterSpacing: 1.4,
                        ),
                      ),
                      // FC8: keep the tappable GO PRO link visible AT the limit too
                      // (isLimitReached implies isWarning). Was `isWarning && !isLimitReached`,
                      // which HID the only reachable paywall CTA at the exact upgrade moment.
                      if (isWarning) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => showPaywallSheet(context,
                              feature: 'Higher daily AI coach limit'),
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
        },
      ),
    );
  }

  Widget _buildIdleRow(bool isLimitReached) {
    final isSending = widget.isSending;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final micAvailable = _speech.supported;
    final canMic = micAvailable && !isLimitReached && !isSending;

    // FC8 — composer field hoisted so the limit-reached state can wrap it in a
    // paywall tap target without duplicating the field.
    final composerField = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: !isLimitReached && !isSending,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: isLimitReached
            ? 'Daily limit reached — Go PRO'
            : 'Ask your coach…',
        hintStyle: AppTypography.body.copyWith(
          fontSize: 14,
          color: isLimitReached ? AppColors.proGold : AppColors.textDim,
        ),
        contentPadding: EdgeInsets.zero,
        isCollapsed: true,
      ),
      style: AppTypography.body.copyWith(fontSize: 14),
      onSubmitted: (_) => _maybeSendText(),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Test #10 obs 5 — compass-rose button left of input.
        // Tap → segregated bottom sheet with 4 family groups.
        // Selecting a command prefills the composer; user edits
        // before sending.
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
                    onSelect: (prefill, action) {
                      switch (action) {
                        case CompassAction.logWorkout:
                          showLogWorkoutSheet(context, ref);
                          break;
                        case CompassAction.swap:
                          showCoachSwapSheet(context, ref);
                          break;
                        case CompassAction.injuryForm:
                        case CompassAction.scheduleForm:
                        case CompassAction.switchForm:
                        case CompassAction.historyForm:
                          showCompassFormSheet(context, action,
                              onCompose: _applyPrefill);
                          break;
                        case CompassAction.logMeal:
                        case CompassAction.prefill:
                          _applyPrefill(prefill);
                          break;
                      }
                    },
                  ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        Expanded(
          // FC8: at the daily limit the composer TextField is disabled;
          // wrap it so a tap opens the paywall (the gold "Go PRO" hint the
          // user actually taps). Below the limit it's the plain field, so
          // typing/focus behave exactly as before.
          child: isLimitReached
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showPaywallSheet(context,
                      feature: 'Higher daily AI coach limit'),
                  child: composerField,
                )
              : composerField,
        ),
        IconButton(
          icon: const Icon(Icons.attach_file,
              color: AppColors.accent, size: 20),
          onPressed: isSending ? null : widget.onAttach,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        // With text already in the field, the mic is a small button BESIDE the
        // send arrow: dictating again appends.
        if (hasText && micAvailable)
          Semantics(
            button: true,
            enabled: canMic,
            label: SpeechInputCopy.semanticsStart,
            child: IconButton(
              icon: const Icon(Icons.mic, color: AppColors.accent, size: 20),
              tooltip: SpeechInputCopy.tapToSpeak,
              onPressed: canMic ? _onMicTap : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        // The morph: mic (empty field) <-> send arrow (text), 200 ms.
        GestureDetector(
          onTap: () {
            if (isSending || isLimitReached) return;
            if (hasText) {
              _maybeSendText();
            } else if (canMic) {
              _onMicTap();
            }
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Container(
              key: ValueKey(hasText
                  ? 'send'
                  : (micAvailable ? 'mic' : 'send-idle')),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent
                    .withValues(alpha: (!hasText && !micAvailable) ? 0.35 : 1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasText || !micAvailable ? Icons.arrow_upward : Icons.mic,
                color: AppColors.bg,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The bar while a session runs: Cancel (X) on the left, the live words with
  /// the NEWEST in view, Stop and Send on the right. In `starting` only Cancel
  /// is live (Stop and Send sit where the mic was, and a double tap on the mic
  /// must not end the session it just started).
  Widget _buildListeningBar() {
    final listening = _speech.state == SpeechInputState.listening;
    final words = _speech.liveText.trim();
    final canSend = listening && words.length >= _minChars;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: SpeechInputCopy.semanticsCancel,
          child: IconButton(
            icon: const Icon(Icons.close, color: AppColors.textDim, size: 20),
            tooltip: SpeechInputCopy.cancel,
            onPressed: _speech.cancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: AppColors.bad,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<Duration>(
          valueListenable: _speech.elapsed,
          builder: (context, elapsed, _) {
            final secs = elapsed.inSeconds;
            final clock =
                '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
            return Text(
              clock,
              style: AppTypography.mono.copyWith(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LiveWords(
            text: words,
            hint: SpeechInputCopy.listeningHint,
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          enabled: listening,
          label: SpeechInputCopy.semanticsStop,
          child: GestureDetector(
            onTap: listening ? _speech.stop : null,
            child: AnimatedOpacity(
              opacity: listening ? 1.0 : 0.35,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bad, width: 2),
                ),
                child: const Icon(Icons.stop, color: AppColors.bad, size: 18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          enabled: canSend,
          label: SpeechInputCopy.semanticsSend,
          child: GestureDetector(
            onTap: canSend ? _speech.send : null,
            child: AnimatedOpacity(
              opacity: canSend ? 1.0 : 0.35,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward,
                    color: AppColors.bg, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of live words, left-aligned while short and scrolled to the END
/// once it overflows, so the newest words stay visible.
class _LiveWords extends StatelessWidget {
  const _LiveWords({required this.text, required this.hint});

  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final empty = text.isEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                empty ? hint : text,
                maxLines: 1,
                softWrap: false,
                style: AppTypography.body.copyWith(
                  fontSize: 14,
                  color: empty ? AppColors.textDim : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
