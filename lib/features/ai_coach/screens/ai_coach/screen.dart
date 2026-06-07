import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../../providers/ai_coach_provider.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/prompt_chip.dart';
import '../../widgets/log_confirm_card.dart';
import '../../widgets/workout_log_confirm_card.dart';
import '../../widgets/coach_insight_section.dart';
import '../../widgets/coach_suggested_actions.dart';
import '../../widgets/coach_patterns_card.dart';
import '../../widgets/coach_deep_analysis_card.dart';
import '../../providers/pending_tool_intents_provider.dart';
import '../../models/tool_intent.dart';
import '../../widgets/tool_confirm_card.dart';
import '../../widgets/tool_confirm_sheet.dart';
import '../../widgets/diff_preview/swap_exercise_diff.dart';
import '../../widgets/compass_tools_sheet.dart';
import '../../widgets/diff_preview/injury_modify_diff.dart';
import '../../widgets/diff_preview/hotel_workout_diff.dart';
import '../../widgets/diff_preview/pause_plan_diff.dart';
import '../../widgets/diff_preview/regenerate_plan_diff.dart';
import '../../widgets/diff_preview/reschedule_week_diff.dart';
import '../../widgets/diff_preview/custom_template_diff.dart';
import '../../widgets/diff_preview/schedule_template_diff.dart';
import '../../widgets/diff_preview/switch_goal_diff.dart';


part 'compact_header.dart';
part 'status_pill.dart';
part 'chat_area.dart';
part 'destructive_intent.dart';
part 'welcome_view.dart';
part 'quick_prompts.dart';
part 'telegram_view.dart';
part 'input_bar.dart';
part 'attach_button.dart';
part 'media_picker.dart';
part 'recording_body.dart';

class AiCoachScreen extends ConsumerStatefulWidget {
  const AiCoachScreen({super.key});

  @override
  ConsumerState<AiCoachScreen> createState() => _AiCoachScreenState();

  /// B-4 / B-5: filter the pending-intents list down to those that should
  /// render in the chat thread. Drops intents whose Hive
  /// `intent_<id>_dispatched_at` marker is set (the dispatcher already ran)
  /// and intents that have been dismissed or rejected. Pure / static so
  /// `dispatched_card_filter_test.dart` can pin the contract without
  /// spinning up the screen widget tree.
  static List<ToolIntent> filterVisibleIntents(List<ToolIntent> intents) {
    final coachBox = HiveService.instance.coachBox;
    return intents.where((i) {
      if (i.status == ToolIntentStatus.pending ||
          i.status == ToolIntentStatus.executing ||
          i.status == ToolIntentStatus.failed) {
        // Defensive: drop if Hive marker says we already dispatched.
        if (coachBox.get('intent_${i.id}_dispatched_at') != null) return false;
        // Drop dismissals — terminal pill renders elsewhere if needed.
        if (coachBox.get('intent_${i.id}_dismissed_at') != null) return false;
        return true;
      }
      return i.status == ToolIntentStatus.executed ||
          i.status == ToolIntentStatus.rejected ||
          i.status == ToolIntentStatus.expired;
    }).toList();
  }
}

class _AiCoachScreenState extends ConsumerState<AiCoachScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  bool _isRecording = false;
  bool _localSending = false; // Synchronous debounce flag to prevent double-tap

  // F12 · Push-to-talk recording UX state (Test #9 batch)
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTicker;
  Offset? _recordingStartOffset;
  bool _slideToCancel = false;

  // Media attachment state
  final _imagePicker = ImagePicker();
  bool _isUploadingMedia = false;
  double _uploadProgress = 0.0;

  // Speech-to-text — null on web (plugin not supported)
  SpeechToText? _speech;
  bool _speechAvailable = false;
  String _recognizedText = '';

  // APK Test #15 / Bug E — gates the one-time initial-scroll-to-bottom on
  // first paint of the AI coach screen. Without this gate, opening the
  // screen leaves the scroll position at 0 (top), forcing the user to
  // scroll down through history just to see the latest exchange and the
  // input row. Set true after the first non-empty message frame triggers
  // a `jumpTo(maxScrollExtent)` so subsequent rebuilds (which already
  // call `_scrollToBottom` via ref.listen) don't re-fire it on every
  // build.
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _speech = SpeechToText();
      _initSpeech();
    }
    // F12 · rebuild on text change so mic↔send morph fires
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
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
    _recordingTicker?.cancel();
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

  /// APK Test #15 / Bug E — instant (no animation) jump used ONLY by the
  /// first-paint initial scroll. `_scrollToBottom`'s 300 ms animation is
  /// fine for "new message arrived, ease into view" but for the initial
  /// landing there's nothing to ease from — the user just opened the
  /// screen and expects the latest exchange + input row already in view.
  /// `jumpTo` removes the visible scroll-from-top animation that would
  /// otherwise flash on every open.
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    // 2026-04-18 · Chat/Reasoning toggle removed. Single coach experience.
    // PRO users bypass limits; free users hit the paywall when the daily
    // message cap is reached. Server (ai-proxy) enforces the same gate.
    final isPro = SubscriptionService.instance.isPro();
    final messageCount = ref.read(messageLimitProvider);

    if (isPro) {
      _doSend(text);
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

    // Scroll when messages change or log actions appear
    ref.listen(chatHistoryProvider, (_, _) => _scrollToBottom());
    ref.listen(pendingLogActionsProvider, (_, _) => _scrollToBottom());
    ref.listen(pendingToolIntentsProvider, (_, _) => _scrollToBottom());
    ref.listen(workoutDraftProvider, (_, next) {
      if (next != null) _scrollToBottom();
    });

    // APK Test #15 / Bug E — first-paint scroll-to-bottom. Fires once,
    // when chatHistoryProvider has loaded its first non-empty value. The
    // ref.listen calls above only fire on VALUE CHANGES, never on the
    // initial mount — so without this guard a user opening the AI coach
    // screen lands at scroll position 0 (oldest message at top) and has
    // to manually scroll down past history to see the latest reply and
    // reach the input row. closes-diagnose: 2026-05-10-coach-scroll-init
    if (!_initialScrollDone && messages.isNotEmpty) {
      _initialScrollDone = true;
      _jumpToBottom();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // Plan D D-8 — AI Coach uses _buildCompactHeader as its
                // letterhead (THE BRIDGE · 24/7 eyebrow + Aye Captain
                // Fraunces title). No unified WardTabHeader.
                _buildCompactHeader(isPro, channel, telegramConnected),

                // F11 · Test #9 — status strip + message count + trial
                // countdown all consolidated INTO _buildCompactHeader. The
                // header now owns its own meta (counter glued under UPGRADE).

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
                  _buildInputBar(isSending, messageCount, isPro),
              ],
            ),
          ),
        ),
      ),
    );
  }
}