import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/ai_coach_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/prompt_chip.dart';
import '../widgets/voice_notes_button.dart';
import '../widgets/log_confirm_card.dart';
import '../widgets/workout_log_confirm_card.dart';
import '../widgets/coach_insight_section.dart';
import '../widgets/coach_suggested_actions.dart';
import '../widgets/coach_patterns_card.dart';
import '../widgets/coach_deep_analysis_card.dart';
import '../providers/pending_tool_intents_provider.dart';
import '../models/tool_intent.dart';
import '../widgets/tool_confirm_card.dart';
import '../widgets/tool_confirm_sheet.dart';
import '../widgets/diff_preview/swap_exercise_diff.dart';
import '../widgets/diff_preview/injury_modify_diff.dart';
import '../widgets/diff_preview/hotel_workout_diff.dart';
import '../widgets/diff_preview/pause_plan_diff.dart';
import '../widgets/diff_preview/regenerate_plan_diff.dart';
import '../widgets/diff_preview/reschedule_week_diff.dart';
import '../widgets/diff_preview/custom_template_diff.dart';
import '../widgets/diff_preview/schedule_template_diff.dart';
import '../widgets/diff_preview/switch_goal_diff.dart';
import '../widgets/diff_preview/prelog_diff.dart';

class AiCoachScreen extends ConsumerStatefulWidget {
  const AiCoachScreen({super.key});

  @override
  ConsumerState<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends ConsumerState<AiCoachScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  bool _isRecording = false;
  bool _localSending = false; // Synchronous debounce flag to prevent double-tap

  // Media attachment state
  final _imagePicker = ImagePicker();
  bool _isUploadingMedia = false;
  double _uploadProgress = 0.0;

  // Speech-to-text — null on web (plugin not supported)
  SpeechToText? _speech;
  bool _speechAvailable = false;
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _speech = SpeechToText();
      _initSpeech();
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech!.initialize(
        onError: (error) {
          debugPrint('[STT] error: ${error.errorMsg}');
          setState(() => _isRecording = false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isRecording = false);
            if (_recognizedText.isNotEmpty) {
              _messageController.text = _recognizedText;
              _messageController.selection = TextSelection.fromPosition(
                TextPosition(offset: _recognizedText.length),
              );
              _inputFocusNode.requestFocus();
              _recognizedText = '';
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[STT] initialize() failed: $e');
      _speechAvailable = false;
    }
    setState(() {});
  }

  void _startListening() {
    if (_speech == null) return;
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Microphone not available. Check app permissions in Settings.',
            style: AppTypography.body.copyWith(color: AppColors.bad),
          ),
          backgroundColor: AppColors.card,
        ),
      );
      return;
    }
    setState(() {
      _isRecording = true;
      _recognizedText = '';
    });
    _speech!.listen(
      onResult: (result) {
        setState(() => _recognizedText = result.recognizedWords);
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_IN',
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  void _stopListening() {
    _speech?.stop();
    setState(() => _isRecording = false);
    if (_recognizedText.isNotEmpty) {
      _messageController.text = _recognizedText;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _recognizedText.length),
      );
      _inputFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _speech?.stop();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    // 2026-04-18 · Chat/Reasoning toggle removed. Single coach experience.
    // PRO users bypass limits; free users hit paywall when trial expires
    // or daily cap is reached. Server (ai-proxy) enforces same gates.
    final isPro = SubscriptionService.instance.isPro();
    final trialInfo = ref.read(trialInfoProvider);
    final messageCount = ref.read(messageLimitProvider);

    if (isPro) {
      _doSend(text);
      return;
    }

    if (trialInfo.isTrialExpired) {
      showPaywallSheet(context, feature: 'Unlimited AI Coach');
      return;
    }

    if (messageCount >= AppConstants.freeAiMessagesPerDay) {
      showPaywallSheet(context, feature: 'Unlimited AI Coach');
      return;
    }

    _doSend(text);
  }

  void _doSend(String text) {
    if (_localSending) return; // Block rapid double-taps synchronously
    setState(() => _localSending = true);
    _messageController.clear();
    ref.read(sendMessageProvider.notifier).send(text).whenComplete(() {
      if (mounted) setState(() => _localSending = false);
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    final isSending = ref.watch(sendMessageProvider);
    final messageCount = ref.watch(messageLimitProvider);
    // Watch the provider so this screen rebuilds the instant a Razorpay
    // success invalidates subscriptionInfoProvider. The direct
    // SubscriptionService.instance.isPro() read Hive fresh but didn't
    // trigger a Riverpod rebuild, so the "PRO" pill + trial counter
    // stayed stale until a full app restart. Observed 2026-04-18 on
    // icanbefitter@gmail.com post-PRO-purchase.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final telegramConnected = ref.watch(telegramConnectionProvider);
    final channel = ref.watch(channelProvider);
    final trialInfo = ref.watch(trialInfoProvider);

    // Scroll when messages change or log actions appear
    ref.listen(chatHistoryProvider, (_, _) => _scrollToBottom());
    ref.listen(pendingLogActionsProvider, (_, _) => _scrollToBottom());
    ref.listen(pendingToolIntentsProvider, (_, _) => _scrollToBottom());
    ref.listen(workoutDraftProvider, (_, next) {
      if (next != null) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // ── Compact Header (avatar + title + mode tabs + menu) ──
                _buildCompactHeader(isPro, channel, telegramConnected),

                // D-8 status strip — streak + freeze always; no rank chip
                // on AI Coach (roadmap is source of truth per spec §6.3.3).
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                  child: WardStatusStrip(
                    streakDays: ref.watch(streakProvider),
                    freezesAvailable: ref.watch(streakFreezeProvider),
                  ),
                ),

                // ── Message count indicator ──
                _buildMessageCountIndicator(isPro, messageCount),

                // ── Trial countdown bar (free users only) ──
                if (!isPro && trialInfo.isTrialActive)
                  _buildTrialCountdown(messageCount, trialInfo.daysRemaining),

                // ── Chat Area or Telegram View ──
                Expanded(
                  child: channel == 'in_app'
                      ? _buildChatArea(messages, isSending)
                      : _buildTelegramView(telegramConnected),
                ),

                // ── Quick Prompts (only when chat is empty/welcome only) ──
                if (channel == 'in_app' && !isSending && messages.length <= 1)
                  _buildQuickPrompts(),

                // ── Input Bar with inline message counter ──
                if (channel == 'in_app')
                  _buildInputBar(isSending, messageCount, isPro, trialInfo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // TRIAL COUNTDOWN BAR
  // ────────────────────────────────────────────────────────────────

  Widget _buildTrialCountdown(int messageCount, int daysRemaining) {
    final remaining = AppConstants.freeAiMessagesPerDay - messageCount;
    final isUrgent = daysRemaining <= 3;
    final textColor = isUrgent ? AppColors.bad : AppColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter, vertical: 8),
      color: AppColors.bgDeep,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 12, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$remaining msg${remaining == 1 ? "" : "s"} left today',
                  style: AppTypography.bodySm.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$daysRemaining day${daysRemaining == 1 ? "" : "s"} remaining in free trial',
                  style: AppTypography.monoXs.copyWith(
                    color: textColor.withValues(alpha: 0.71),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () =>
                showPaywallSheet(context, feature: 'Unlimited AI Coach'),
            child: Text(
              'UPGRADE',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // COMPACT HEADER — single row replaces old header + channel + reasoning
  // ────────────────────────────────────────────────────────────────

  Widget _buildCompactHeader(
      bool isPro, String channel, bool telegramConnected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.33),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Coach avatar with live dot
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
                  child: Text(
                    'AI',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 1.2,
                      fontSize: 11,
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

          // Title — Wardroom mono eyebrow + Fraunces name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THE BRIDGE \u00B7 24/7',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                // D-8 (Plan D): Title is the recruit's acknowledgement
                // to the Captain — short, on-brand, no "CAPTAIN" duplicate
                // with the eyebrow.
                Text(
                  'Aye Captain',
                  style: AppTypography.h3.copyWith(
                    height: 1.0,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // Single status pill — PRO users see informational gold badge;
          // free users see a tappable "Upgrade to PRO" pill that opens
          // the paywall sheet. Replaced the old Chat / Reasoning toggle
          // on 2026-04-18 as part of the UI simplification (one AI coach
          // experience, free/PRO differentiation handled server-side by
          // the 15-msg daily cap).
          _buildStatusPill(isPro),
          const SizedBox(width: 8),

          // Overflow menu — channel switch, telegram, clear, upgrade
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
                  showPaywallSheet(context, feature: 'Unlimited AI Coach');
                  break;
              }
            },
            itemBuilder: (context) => [
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
                      const Icon(Icons.star,
                          size: 16, color: AppColors.proGold),
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
            ],
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // STATUS PILL — non-tappable gold "PRO" badge for PRO users,
  // tappable accent "Upgrade to PRO" for free users.
  //
  // 2026-04-18 · Replaced the Chat / Reasoning two-tab toggle. Per user
  // feedback the two backends (ai-proxy + ai-proxy-pro) were merged into
  // a single Gemini-backed endpoint, so there's no user-facing choice to
  // make here any more — free vs PRO differentiation is entirely the
  // 15-msg daily cap enforced server-side.
  // ────────────────────────────────────────────────────────────────

  Widget _buildStatusPill(bool isPro) {
    if (isPro) {
      // Informational badge only — no tap handler. Users manage their
      // subscription from Profile → Subscription.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.proGoldTint,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.proGold, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium,
                size: 12, color: AppColors.proGold),
            const SizedBox(width: 4),
            Text(
              'PRO',
              style: AppTypography.mono.copyWith(
                color: AppColors.proGold,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    // Free user — tap opens paywall.
    return GestureDetector(
      onTap: () =>
          showPaywallSheet(context, feature: 'Unlimited AI Coach'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_upward,
                size: 12, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              'UPGRADE',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // MESSAGE COUNT INDICATOR — below header
  // ────────────────────────────────────────────────────────────────

  Widget _buildMessageCountIndicator(bool isPro, int messageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter, vertical: 6),
      color: AppColors.bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isPro
                ? 'UNLIMITED'
                : '$messageCount/${AppConstants.freeAiMessagesPerDay} MESSAGES TODAY',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

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
    // If the in-memory provider state thinks an intent is still pending but the
    // Hive marker shows it's already been dispatched (hot restart edge case),
    // hide it from the chat thread so cards never pile up. Primary state of
    // truth remains ToolIntent.status.
    final coachBox = HiveService.instance.coachBox;
    final visibleIntents = ref.watch(pendingToolIntentsProvider).where((i) {
      if (i.status == ToolIntentStatus.pending ||
          i.status == ToolIntentStatus.executing ||
          i.status == ToolIntentStatus.failed) {
        // Defensive: drop if Hive marker says we already dispatched.
        if (coachBox.get('intent_${i.id}_dispatched_at') != null) return false;
        return true;
      }
      return i.status == ToolIntentStatus.executed ||
          i.status == ToolIntentStatus.rejected ||
          i.status == ToolIntentStatus.expired;
    }).toList();

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

  // ────────────────────────────────────────────────────────────────
  // Phase A.11 — destructive tool intent tile (opens modal sheet)
  // ────────────────────────────────────────────────────────────────

  Widget _buildDestructiveIntentTile(BuildContext context, ToolIntent intent) {
    // C-6: Terminal states collapse to a small pill so the chat thread
    // doesn't pile up with stale "Review" cards. Mirrors
    // ToolConfirmCard._buildExecutedState / _buildRejectedState.
    if (intent.status == ToolIntentStatus.executed) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Applied',
        color: AppColors.ok,
        icon: Icons.check_circle,
      );
    }
    if (intent.status == ToolIntentStatus.rejected) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Dismissed',
        color: AppColors.textDim,
        icon: Icons.cancel_outlined,
      );
    }
    if (intent.status == ToolIntentStatus.expired) {
      return _buildIntentTerminalPill(
        intent: intent,
        label: 'Expired',
        color: AppColors.textDim,
        icon: Icons.schedule,
      );
    }

    final isExecuting = intent.status == ToolIntentStatus.executing;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Review: ${intent.previewSummary}',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap APPLY to review and confirm changes.',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // C-3: Explicit Apply / Dismiss buttons replace the old chevron
          // tap target — testers were not discovering the row was tappable.
          Row(
            children: [
              Expanded(
                child: WardButton(
                  label: 'APPLY',
                  variant: WardButtonVariant.primary,
                  size: WardButtonSize.small,
                  onPressed: isExecuting
                      ? null
                      : () => _openIntentSheet(context, intent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WardButton(
                  label: 'DISMISS',
                  variant: WardButtonVariant.ghost,
                  size: WardButtonSize.small,
                  onPressed: isExecuting
                      ? null
                      : () {
                          ref
                              .read(pendingToolIntentsProvider.notifier)
                              .reject(intent.id);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntentTerminalPill({
    required ToolIntent intent,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: ${intent.previewSummary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(
                'DM Sans',
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openIntentSheet(BuildContext context, ToolIntent intent) {
    final Widget diffPreview;
    switch (intent.type) {
      case 'swap_exercise':
        diffPreview = SwapExerciseDiff(intent: intent);
        break;
      case 'modify_workout_for_injury':
        diffPreview = InjuryModifyDiff(intent: intent);
        break;
      case 'reschedule_week':
        diffPreview = RescheduleWeekDiff(intent: intent);
        break;
      case 'generate_hotel_workout':
        diffPreview = HotelWorkoutDiff(intent: intent);
        break;
      case 'regenerate_plan_block':
        diffPreview = RegeneratePlanDiff(intent: intent);
        break;
      case 'pause_plan':
        diffPreview = PausePlanDiff(intent: intent);
        break;
      case 'switch_goal':
        diffPreview = SwitchGoalDiff(intent: intent);
        break;
      case 'create_custom_template':
        diffPreview = CustomTemplateDiff(intent: intent);
        break;
      case 'schedule_template':
        diffPreview = ScheduleTemplateDiff(intent: intent);
        break;
      case 'prelog':
        diffPreview = PrelogDiff(intent: intent);
        break;
      default:
        diffPreview = const Text('Confirm this action?');
    }
    ToolConfirmSheet.show(
      context,
      intent: intent,
      diffPreview: diffPreview,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // WELCOME VIEW — shown when chat is empty
  // ────────────────────────────────────────────────────────────────

  Widget _buildWelcomeView() {
    // AG.2 — JSX handoff's full coach "home" layout: Today's Insight
    // quote, 3 Suggested Actions, Patterns I've Noticed, and the
    // Deep Analysis dashed CTA. Shown only while the chat history is
    // empty; as soon as the user sends a message `_buildChatArea`
    // takes over and these sections scroll out of the way naturally.
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: const [
        CoachInsightSection(),
        CoachSuggestedActions(),
        CoachPatternsCard(),
        CoachDeepAnalysisCard(),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // QUICK PROMPT CHIPS — only shown when chat is empty/welcome
  // ────────────────────────────────────────────────────────────────

  Widget _buildQuickPrompts() {
    final prompts = ref.watch(contextualPromptsProvider);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter, vertical: 10),
            child: Row(
              children: prompts.map((prompt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PromptChip(
                    label: prompt,
                    onTap: () => _sendMessage(prompt),
                  ),
                );
              }).toList(),
            ),
          ),
          // Right-edge fade to signal more chips are scrollable
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.0),
                      AppColors.bg.withValues(alpha: 0.90),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 10, AppSpacing.gutter, 8),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main input row
          Row(
            children: [
              // Voice notes button — free for all users
              VoiceNotesButton(
                isPro: true,
                isRecording: _isRecording,
                onLockedTap: () => _startListening(),
                onStartRecording: () => _startListening(),
                onStopRecording: () => _stopListening(),
              ),
              const SizedBox(width: 6),

              // Photo attachment button (PRO only)
              _buildAttachButton(isPro, isSending),
              const SizedBox(width: 6),

              // Text input — sharp 2-px inner border
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _inputFocusNode,
                  enabled: !isLimitReached && !isSending,
                  maxLines: 3,
                  minLines: 1,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: _isRecording && _recognizedText.isNotEmpty
                        ? _recognizedText
                        : _isRecording
                            ? 'Listening...'
                            : isLimitReached
                                ? 'Daily limit reached \u2014 Go PRO'
                                : 'Ask your coach...',
                    hintStyle: AppTypography.body.copyWith(
                      color: _isRecording
                          ? AppColors.accent
                          : isLimitReached
                              ? AppColors.proGold
                              : AppColors.textDim,
                    ),
                    filled: true,
                    fillColor: AppColors.bgRaise,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.line2, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.line2, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      borderSide: const BorderSide(
                          color: AppColors.line2, width: 2),
                    ),
                  ),
                  onSubmitted: (text) => _sendMessage(text),
                ),
              ),
              const SizedBox(width: 8),

              // Send button — sharp 2-px accent slab with glyph
              GestureDetector(
                onTap: isSending || isLimitReached
                    ? null
                    : () => _sendMessage(_messageController.text),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSending || isLimitReached
                        ? AppColors.textDisabled
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Center(
                    child: Icon(
                      isSending
                          ? Icons.hourglass_top
                          : Icons.arrow_upward,
                      color: isSending || isLimitReached
                          ? AppColors.textDim
                          : AppColors.bgDeep,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
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

  // ────────────────────────────────────────────────────────────────
  // PHOTO ATTACHMENT BUTTON + FLOW
  // ────────────────────────────────────────────────────────────────

  /// Builds the attach-photo icon button.
  /// PRO users: opens media source picker.
  /// Free users: gold-locked icon -> paywall.
  Widget _buildAttachButton(bool isPro, bool isSending) {
    if (_isUploadingMedia) {
      // Show upload progress indicator
      return SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const Icon(
              Icons.photo,
              color: AppColors.accent,
              size: 12,
            ),
          ],
        ),
      );
    }

    if (!isPro) {
      // Gold-locked sharp 2-px tile for free users
      return GestureDetector(
        onTap: () => showPaywallSheet(context, feature: 'Photo Analysis'),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.proGoldTint,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: AppColors.proGold, width: 2),
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.attach_file,
                  color: AppColors.proGold,
                  size: 14,
                ),
              ),
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.proGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.header, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.lock,
                    size: 5,
                    color: AppColors.bgDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // PRO user — active sharp 2-px accent tile
    return GestureDetector(
      onTap: isSending ? null : () => _showMediaSourceSheet(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        child: const Icon(
          Icons.attach_file,
          color: AppColors.accent,
          size: 14,
        ),
      ),
    );
  }

  /// Shows a bottom sheet with Camera and Gallery options.
  void _showMediaSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          border: Border(
            top: BorderSide(color: AppColors.line2, width: 1),
            left: BorderSide(color: AppColors.line2, width: 1),
            right: BorderSide(color: AppColors.line2, width: 1),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(AppRadius.soft),
                ),
              ),
              Text(
                'Send a Photo',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 4),
              Text(
                'Your AI coach will analyse the image',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 16),
              // Camera option
              _mediaOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                subtitle: 'Take a photo now',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              // Gallery option
              _mediaOption(
                icon: Icons.photo_library,
                label: 'Gallery',
                subtitle: 'Choose from photos',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(color: AppColors.accent, width: 2),
            ),
            child: Icon(icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.h3.copyWith(fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.textDim,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// Pick an image from camera or gallery, compress it, upload, and send.
  Future<void> _pickImage(ImageSource source) async {
    try {
      // On web, camera is not available
      if (kIsWeb && source == ImageSource.camera) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Camera is not available on web. Use gallery instead.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              backgroundColor: AppColors.card,
            ),
          );
        }
        return;
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isUploadingMedia = true;
        _uploadProgress = 0.0;
      });

      // Read the file bytes
      final Uint8List imageBytes = await pickedFile.readAsBytes();

      // Compress if needed (flutter_image_compress for native, skip on web)
      Uint8List compressedBytes;
      if (!kIsWeb) {
        try {
          // Dynamic import to avoid web compilation issues
          final compressed = await _compressImage(imageBytes);
          compressedBytes = compressed ?? imageBytes;
        } catch (e) {
          debugPrint('[AiCoachScreen._pickAndUploadImage] $e');
          compressedBytes = imageBytes;
        }
      } else {
        compressedBytes = imageBytes;
      }

      // Check size limit (2MB)
      if (compressedBytes.lengthInBytes > 2 * 1024 * 1024) {
        // Try harder compression
        if (!kIsWeb) {
          final recompressed = await _compressImage(imageBytes, quality: 60);
          compressedBytes = recompressed ?? compressedBytes;
        }
      }

      setState(() => _uploadProgress = 0.3);

      // Upload to Supabase Storage
      final supabase = SupabaseService.instance;
      final userId = supabase.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '$userId/$timestamp.jpg';

      await supabase.client.storage.from('chat-media').uploadBinary(
            storagePath,
            compressedBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
                'Upload timed out. Please check your connection and try again.'),
          );

      setState(() => _uploadProgress = 0.7);

      // Get the public URL
      final publicUrl =
          supabase.client.storage.from('chat-media').getPublicUrl(storagePath);

      setState(() => _uploadProgress = 1.0);

      // Track last media request in coachBox (rate limit: max once per 7 days)
      final coachBox = HiveService.instance.coachBox;
      coachBox.put(
          'last_media_request_at', DateTime.now().toIso8601String());

      // Send the message with media URL
      final messageText = _messageController.text.trim();
      _messageController.clear();

      ref.read(sendMessageProvider.notifier).sendWithMedia(
            messageText,
            mediaUrl: publicUrl,
            mediaType: 'image',
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload photo: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}',
              style: AppTypography.body.copyWith(color: AppColors.bad),
            ),
            backgroundColor: AppColors.card,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  /// Compress image bytes using flutter_image_compress (native only).
  Future<Uint8List?> _compressImage(Uint8List bytes,
      {int quality = 85}) async {
    // flutter_image_compress only works on mobile platforms
    if (kIsWeb) return bytes;

    try {
      // Use dynamic import pattern to avoid web compilation issues
      final result =
          await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1920,
        minHeight: 1920,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      return result;
    } catch (e) {
      debugPrint('[AiCoachScreen._compressImage] $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<void> _openTelegramBot() async {
    final uri = Uri.parse('https://t.me/AVYACoachBot');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
