import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/copy/speech_input_copy.dart';
import 'package:icanbefitter/core/services/speech_input_controller.dart';
import 'package:icanbefitter/core/services/speech_input_lifecycle.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';

/// What an analyse call leaves behind (pure, so a test can pin it).
///
/// A FAILED call (`state.error` set: a service error, a 429, the retry circuit
/// breaker, a non-200) keeps the typed or spoken text, so a retry is one tap and
/// nothing said is lost, and does NOT tick the client counter: the server
/// counts a call itself (`trg_food_text_rate_limit`) and its 429 is the
/// authority, so under-counting here is the safe direction. A success clears the
/// field and counts one unit. `null` (no state at all) is treated as a failure.
({bool clearField, bool count}) analyseOutcome(AiBreakdownData? result) {
  final succeeded = result != null && result.error == null;
  return (clearField: succeeded, count: succeeded);
}

/// The shortest text the AI call accepts (`_analyse`'s own floor).
const int kFoodTextMinChars = 3;

/// Food logger input field with AI analysis button and usage counter.
class FoodLoggerSection extends ConsumerStatefulWidget {
  const FoodLoggerSection({super.key});

  @override
  ConsumerState<FoodLoggerSection> createState() => _FoodLoggerSectionState();
}

class _FoodLoggerSectionState extends ConsumerState<FoodLoggerSection> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;

  /// One dictation session for this field (plan `docs/plans/voice-input-unified.md`, D5).
  late final SpeechInputController _speech;

  /// What was typed before the mic was tapped; the spoken words follow it.
  String _speechPrefix = '';

  /// The last thing to tell the user (a refused microphone, no words heard, a
  /// message too short, the daily cap). Shown INLINE: this widget lives in a
  /// modal bottom sheet with no Scaffold of its own, so a snackbar would be
  /// drawn on the page behind the sheet and never seen (B-pass 2026-11-14).
  String? _notice;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
    final service = ref.read(speechInputServiceProvider);
    _speech = SpeechInputController(service: service, onEnd: _onSpeechEnd);
    _speech.addListener(_onSpeechChanged);
    // Web: ask the browser whether a recognizer exists (no permission prompt).
    if (service.isWeb) unawaited(_speech.probeSupport());
  }

  @override
  void dispose() {
    _speech.removeListener(_onSpeechChanged);
    _speech.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _joinSpeech(String words) {
    final spoken = words.trim();
    if (_speechPrefix.isEmpty) return spoken;
    if (spoken.isEmpty) return _speechPrefix;
    return '$_speechPrefix $spoken';
  }

  void _setFieldText(String text) {
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The words form live in the field while the session runs. Written only when
  /// they CHANGE, never on an unrelated rebuild.
  void _onSpeechChanged() {
    if (!mounted) return;
    if (_speech.isBusy) _setFieldText(_joinSpeech(_speech.liveText));
    setState(() {});
  }

  void _onSpeechEnd(SpeechSessionEnd end) {
    if (!mounted) return;
    final combined = _joinSpeech(end.transcript);
    final action = decideSpeechEnd(
      SpeechSessionEnd(
        transcript: combined,
        reason: end.reason,
        failure: end.failure,
        empty: end.empty,
      ),
      minChars: kFoodTextMinChars,
    );
    switch (action) {
      case SpeechEndAction.commit:
        _setFieldText(combined);
        // Stop keeps the words so they can be edited or rephrased.
        if (speechEndWantsFocus(end)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusNode.requestFocus();
          });
        }
      case SpeechEndAction.send:
        _setFieldText(combined);
        unawaited(_analyse());
      case SpeechEndAction.tooShort:
        _setFieldText(combined);
        _showMessage(SpeechInputCopy.tooShort);
      case SpeechEndAction.discard:
        _setFieldText(_speechPrefix);
      case SpeechEndAction.none:
        break;
    }
    final message = SpeechInputCopy.messageFor(end);
    if (message != null) _showMessage(message);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    setState(() => _notice = text);
  }

  /// True when the daily AI text-log limit leaves room for one more call. At the
  /// cap a free user sees the paywall and a PRO user a snackbar; the caller
  /// stops. The mic runs this BEFORE listening, so nobody speaks a whole meal
  /// into a limit.
  Future<bool> _passesUsageGate(bool isPro) async {
    final usage = UsageCounterService.instance;
    if (usage.canUse(AppConstants.featureAiTextLogPro, isPro)) return true;
    if (!mounted) return false;
    // Free user exhausted daily limit -> show paywall
    await SubscriptionService.instance.gateAndVerify(
      AppConstants.featureAiTextLogPro,
      onPro: () {
        // PRO user exhausted daily limit -> inform them
        _showMessage('Daily AI text log limit reached. Try again tomorrow.');
      },
      onFree: () => showPaywallSheet(context, feature: 'AI Food Analysis'),
    );
    return false;
  }

  Future<void> _onMicTap() async {
    if (ref.read(aiAnalysingProvider)) return;
    if (_speech.isBusy) {
      await _speech.toggle(); // listening: Stop (words kept); starting: ignored
      return;
    }
    if (_notice != null) setState(() => _notice = null);
    final isPro = SubscriptionService.instance.isPro();
    if (!await _passesUsageGate(isPro)) return;
    if (!mounted || _speech.isBusy) return;
    _speechPrefix = _controller.text.trim();
    _focusNode.unfocus();
    await _speech.toggle();
  }

  Future<void> _analyse() async {
    // `onSubmitted` bypasses `canAnalyse`: never run while the mic is on.
    if (_speech.isBusy) return;
    final text = _controller.text.trim();
    if (text.length < kFoodTextMinChars) return;
    if (_notice != null) setState(() => _notice = null);

    final isPro = SubscriptionService.instance.isPro();
    if (!await _passesUsageGate(isPro)) return;
    if (!mounted) return;

    // Captured BEFORE the first await below: the sheet can be closed while the
    // call runs (up to ~20 s with the 500-retry budget), and `ref` throws once
    // the widget is gone, which used to leave the GLOBAL `aiAnalysingProvider`
    // stuck on true until the app restarted (and with it the mic inert).
    final container = ProviderScope.containerOf(context, listen: false);
    final analysing = container.read(aiAnalysingProvider.notifier);
    final breakdown = container.read(aiBreakdownProvider.notifier);

    analysing.set(true);
    try {
      await breakdown.analyse(text);
      final outcome = analyseOutcome(container.read(aiBreakdownProvider));

      // Test #11 M1: the client counter ticks HERE, at the API-call site, not at
      // NutritionWriteService.logMeal (the save site): whether the user taps
      // SAVE MEAL or dismisses is irrelevant, the call is made. Since the speech
      // batch it ticks only for a call that SUCCEEDED (`analyseOutcome`): the
      // server counts every call itself and its 429 is the authority (it also
      // refunds a transport failure), so a failed call must not move the local
      // paywall closer, and its text stays for a one-tap retry.
      if (outcome.count) {
        unawaited(
          UsageCounterService.instance.increment(
            AppConstants.featureAiTextLogPro,
            isPro,
          ),
        );
      }
      // Refresh the "remaining today" chip immediately: the provider is a plain
      // Provider otherwise invalidated only at midnight, so without this the
      // chip stays stale until the next day.
      container.invalidate(aiTextLogRemainingProvider);

      if (outcome.clearField && mounted) _controller.clear();
    } finally {
      analysing.set(false);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAnalysing = ref.watch(aiAnalysingProvider);
    final listening = _speech.state == SpeechInputState.listening;
    final speechBusy = _speech.isBusy;
    // While the mic is on the button is SEND: live only once the words reach the
    // analyse floor (and only while listening: in `starting` only Cancel works).
    final canAnalyse = speechBusy
        ? listening && _controller.text.trim().length >= kFoodTextMinChars
        : _controller.text.trim().length >= kFoodTextMinChars && !isAnalysing;
    final remaining = ref.watch(aiTextLogRemainingProvider);
    // Provider watch (not direct service call) so this tile rebuilds
    // immediately when Razorpay success invalidates subscriptionInfoProvider.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final limit = AppConstants.freeAiTextLogsPerDay;

    return WardCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Ends the dictation when the sheet or its tab goes out of sight, or
          // the app goes to the background (it draws nothing).
          SpeechInputLifecycle(
            controller: _speech,
            child: const SizedBox.shrink(),
          ),
          // Input field
          GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: _isFocused
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.line2,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // AI spark icon
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      // The words form in the field while the mic is on.
                      readOnly: speechBusy,
                      onChanged: (_) => setState(() => _notice = null),
                      onSubmitted: (_) => _analyse(),
                      style: AppTypography.body,
                      decoration: InputDecoration(
                        hintText:
                            'Type what you ate (e.g. 2 rotis with dal)...',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textDim,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_speech.supported) ...[
                    const SizedBox(width: 10),
                    _MicTile(
                      listening: speechBusy,
                      enabled: !isAnalysing,
                      onTap: _onMicTap,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (speechBusy) _ListeningLine(controller: _speech),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _notice!,
                  key: const ValueKey('speech_notice'),
                  style: AppTypography.body.copyWith(color: AppColors.textDim),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.stackS),

          // Analyse button + usage counter
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: !canAnalyse
                      ? null
                      : (speechBusy ? _speech.send : _analyse),
                  child: AnimatedOpacity(
                    opacity: canAnalyse ? 1.0 : 0.35,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                      ),
                      alignment: Alignment.center,
                      child: isAnalysing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.bgDeep,
                              ),
                            )
                          : Text(
                              speechBusy
                                  ? SpeechInputCopy.send.toUpperCase()
                                  : 'ANALYSE & LOG',
                              style: AppTypography.mono.copyWith(
                                color: AppColors.bgDeep,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (!isPro) ...[
                const SizedBox(width: 8),
                // Usage counter chip (free users only — PRO is unlimited)
                WardChip(
                  label: '${limit - remaining}/$limit USED',
                  tone: remaining > 0
                      ? WardChipTone.gold
                      : WardChipTone.bad,
                ),
              ],
            ],
          ),

          // Usage label (free users only)
          if (!isPro)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$remaining log${remaining == 1 ? '' : 's'} left today'
                      .toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The mic at the end of the field row: Wardroom square (2 px), gold while idle,
/// red (and a Stop square) while the session runs. Tapping it while listening
/// is Stop: the words stay in the field to edit or rephrase.
class _MicTile extends StatelessWidget {
  const _MicTile({
    required this.listening,
    required this.enabled,
    required this.onTap,
  });

  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = listening ? AppColors.bad : AppColors.accent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: listening
          ? SpeechInputCopy.semanticsStop
          : SpeechInputCopy.semanticsStart,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: listening
                  ? AppColors.bad.withValues(alpha: 0.14)
                  : AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(
              listening ? Icons.stop : Icons.mic,
              color: color,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// `LISTENING m:ss` under the field, with Cancel (the one control that works in
/// every state, including while the session is still starting).
class _ListeningLine extends StatelessWidget {
  const _ListeningLine({required this.controller});

  final SpeechInputController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.bad,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<Duration>(
            valueListenable: controller.elapsed,
            builder: (context, elapsed, _) {
              final secs = elapsed.inSeconds;
              final clock =
                  '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
              return Text(
                '${SpeechInputCopy.listening} $clock',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textDim,
                  letterSpacing: 1.2,
                ),
              );
            },
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: SpeechInputCopy.semanticsCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.cancel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  SpeechInputCopy.cancel.toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
