import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import '../providers/ai_coach_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_chip.dart';
import '../widgets/deep_analysis_card.dart';
import '../widgets/telegram_card.dart';
import '../widgets/prompt_chip.dart';
import '../widgets/voice_notes_button.dart';
import '../widgets/prediction_card.dart';

class AiCoachScreen extends ConsumerStatefulWidget {
  const AiCoachScreen({super.key});

  @override
  ConsumerState<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends ConsumerState<AiCoachScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  int _selectedChipIndex = 0;
  bool _isRecording = false;

  // Speech-to-text
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  String _recognizedText = '';

  static const _contextChips = [
    'Current Plan',
    'Injuries',
    'Diet Plan',
    'Progress',
    'Goals',
  ];

  // Quick prompts now come from contextualPromptsProvider (dynamic)

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) => setState(() => _isRecording = false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isRecording = false);
          if (_recognizedText.isNotEmpty) {
            _sendMessage(_recognizedText);
            _recognizedText = '';
          }
        }
      },
    );
    setState(() {});
  }

  void _startListening() {
    if (!_speechAvailable) return;
    setState(() {
      _isRecording = true;
      _recognizedText = '';
    });
    _speech.listen(
      onResult: (result) {
        setState(() => _recognizedText = result.recognizedWords);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_IN',
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isRecording = false);
    if (_recognizedText.isNotEmpty) {
      _sendMessage(_recognizedText);
      _recognizedText = '';
    }
  }

  @override
  void dispose() {
    _speech.stop();
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

    final isPro = SubscriptionService.instance.isPro();
    final trialInfo = ref.read(trialInfoProvider);
    final messageCount = ref.read(messageLimitProvider);
    final reasoningMode = ref.read(reasoningModeProvider);

    // If trial expired and not PRO, gate
    if (!isPro && trialInfo.isTrialExpired) {
      SubscriptionService.instance.gate(
        AppConstants.featureAiCoachUnlimited,
        onPro: () => _doSend(text, mode: reasoningMode),
        onFree: () =>
            showPaywallSheet(context, feature: 'Unlimited AI Coach'),
      );
      return;
    }

    // If daily limit reached and not PRO
    if (!isPro &&
        messageCount >= AppConstants.freeAiMessagesPerDay) {
      SubscriptionService.instance.gate(
        AppConstants.featureAiCoachUnlimited,
        onPro: () => _doSend(text, mode: reasoningMode),
        onFree: () =>
            showPaywallSheet(context, feature: 'Unlimited AI Coach'),
      );
      return;
    }

    // Deep mode requires PRO
    if (reasoningMode == 'deep') {
      SubscriptionService.instance.gate(
        AppConstants.featureReasoningTab,
        onPro: () => _doSend(text, mode: 'deep'),
        onFree: () =>
            showPaywallSheet(context, feature: 'Deep Analysis'),
      );
      return;
    }

    _doSend(text, mode: reasoningMode);
  }

  void _doSend(String text, {String mode = 'quick'}) {
    ref.read(sendMessageProvider.notifier).send(text, mode: mode);
    _messageController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    final isSending = ref.watch(sendMessageProvider);
    final messageCount = ref.watch(messageLimitProvider);
    final isPro = SubscriptionService.instance.isPro();
    final telegramConnected = ref.watch(telegramConnectionProvider);
    final channel = ref.watch(channelProvider);
    final reasoningMode = ref.watch(reasoningModeProvider);
    final trialInfo = ref.watch(trialInfoProvider);
    final prediction = ref.watch(predictionProvider);

    // Scroll when messages change
    ref.listen(chatHistoryProvider, (_, _) => _scrollToBottom());

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                // ── Header ──
                _buildHeader(isPro),

                // ── Channel Toggle ──
                _buildChannelToggle(channel),

                // ── Reasoning Mode Toggle ──
                if (channel == 'in_app') _buildReasoningToggle(reasoningMode, isPro),

                // ── Context Chips ──
                if (channel == 'in_app') _buildContextChips(),

                // ── Message limit bar + trial info (free users) ──
                if (!isPro && channel == 'in_app')
                  _buildMessageLimitBar(messageCount, trialInfo),

                // ── Chat Area or Telegram View ──
                Expanded(
                  child: channel == 'in_app'
                      ? _buildChatArea(
                          messages,
                          isSending,
                          isPro,
                          telegramConnected,
                          prediction,
                        )
                      : _buildTelegramView(telegramConnected),
                ),

                // ── Quick Prompt Chips ──
                if (channel == 'in_app' && !isSending)
                  _buildQuickPrompts(),

                // ── Input Bar ──
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
  // HEADER
  // ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isPro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 11),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Coach avatar with live dot
          Stack(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                ),
                child: Center(
                  child: Text(
                    'AI',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.header, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ICANBEFITTER COACH',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  isPro ? 'LIVE \u00B7 PRO' : 'LIVE \u00B7 FREE TIER',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Menu icon
          GestureDetector(
            onTap: () {
              // TODO: Show coach menu (clear chat, export, etc.)
            },
            child: const Icon(
              Icons.more_horiz,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // CHANNEL TOGGLE
  // ────────────────────────────────────────────────────────────────

  Widget _buildChannelToggle(String channel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(channelProvider.notifier).setChannel('in_app'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: channel == 'in_app'
                      ? AppColors.accentTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: channel == 'in_app'
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    'In-App Chat',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: channel == 'in_app'
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(channelProvider.notifier).setChannel('telegram'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: channel == 'telegram'
                      ? AppColors.accentTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: channel == 'telegram'
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.send, size: 13, color: AppColors.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Telegram',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: channel == 'telegram'
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
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
  // REASONING MODE TOGGLE
  // ────────────────────────────────────────────────────────────────

  Widget _buildReasoningToggle(String mode, bool isPro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(reasoningModeProvider.notifier).setMode('quick'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: mode == 'quick'
                      ? AppColors.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    'Quick',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: mode == 'quick'
                          ? Colors.black
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isPro) {
                  SubscriptionService.instance.gate(
                    AppConstants.featureReasoningTab,
                    onPro: () => ref
                        .read(reasoningModeProvider.notifier)
                        .setMode('deep'),
                    onFree: () => showPaywallSheet(context,
                        feature: 'Deep Analysis'),
                  );
                  return;
                }
                ref.read(reasoningModeProvider.notifier).setMode('deep');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: mode == 'deep'
                      ? AppColors.proGold
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Deep Analyse',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: mode == 'deep'
                              ? Colors.black
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (!isPro) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.proGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PRO',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.proGold,
                            ),
                          ),
                        ),
                      ],
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
  // CONTEXT CHIPS
  // ────────────────────────────────────────────────────────────────

  Widget _buildContextChips() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 10),
        child: Row(
          children: List.generate(_contextChips.length, (index) {
            final isActive = _selectedChipIndex == index;
            return Padding(
              padding: EdgeInsets.only(
                right: index < _contextChips.length - 1 ? 6 : 0,
              ),
              child: ContextChip(
                label: _contextChips[index],
                isActive: isActive,
                onTap: () {
                  setState(() {
                    // Toggle off if same chip tapped again
                    if (_selectedChipIndex == index) {
                      _selectedChipIndex = -1;
                      ref.read(sendMessageProvider.notifier).setContextFilter(null);
                    } else {
                      _selectedChipIndex = index;
                      ref.read(sendMessageProvider.notifier).setContextFilter(_contextChips[index]);
                    }
                  });
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // MESSAGE LIMIT BAR + TRIAL INFO
  // ────────────────────────────────────────────────────────────────

  Widget _buildMessageLimitBar(int messageCount, TrialInfoData trialInfo) {
    final isWarning =
        messageCount >= AppConstants.freeAiMessagesPerDay - 3;
    final isLimitReached =
        messageCount >= AppConstants.freeAiMessagesPerDay;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      color: AppColors.card,
      child: Column(
        children: [
          // Daily message counter
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLimitReached
                    ? Icons.warning_amber
                    : Icons.chat_bubble_outline,
                size: 14,
                color: isWarning ? AppColors.orange : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                '$messageCount of ${AppConstants.freeAiMessagesPerDay} messages used today',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      isWarning ? AppColors.orange : AppColors.textSecondary,
                ),
              ),
              if (isWarning) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => showPaywallSheet(context,
                      feature: 'Unlimited AI Coach'),
                  child: Text(
                    'Go PRO',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.proGold,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Trial expiry info
          if (trialInfo.isTrialActive && !trialInfo.isTrialExpired) ...[
            const SizedBox(height: 2),
            Text(
              '${trialInfo.daysRemaining} days remaining in your AI trial',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: trialInfo.daysRemaining <= 7
                    ? AppColors.orange
                    : AppColors.textSecondary,
              ),
            ),
          ],
          if (trialInfo.isTrialExpired) ...[
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => showPaywallSheet(context,
                  feature: 'Unlimited AI Coach'),
              child: Text(
                'Trial expired \u2014 Upgrade to PRO for unlimited access',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.proGold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // CHAT AREA
  // ────────────────────────────────────────────────────────────────

  Widget _buildChatArea(
    List<ChatMessage> messages,
    bool isSending,
    bool isPro,
    bool telegramConnected,
    PredictionData prediction,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      itemCount: _chatItemCount(messages, telegramConnected),
      itemBuilder: (context, index) {
        // Chat messages
        if (index < messages.length) {
          final message = messages[index];
          final time =
              '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChatBubble(
              text: message.text,
              isUser: message.isUser,
              isLoading: message.isLoading,
              isError: message.isError,
              timestamp: time,
            ),
          );
        }

        // Items after messages
        final extraIndex = index - messages.length;

        // Action buttons (after first AI response, only if not sending)
        if (extraIndex == 0 && messages.isNotEmpty && !isSending) {
          return _buildActionButtons();
        }

        // Coach Insight card
        if (extraIndex == 1) {
          return _buildCoachInsight();
        }

        // Deep Analysis PRO card
        if (extraIndex == 2) {
          return DeepAnalysisCard(
            isPro: isPro,
            onUpgradeTap: () {
              SubscriptionService.instance.gate(
                AppConstants.featureReasoningTab,
                onPro: () {
                  // PRO user — show deep analysis content
                  ref.read(reasoningModeProvider.notifier).setMode('deep');
                },
                onFree: () =>
                    showPaywallSheet(context, feature: 'Deep Analysis'),
              );
            },
          );
        }

        // Prediction card
        if (extraIndex == 3) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PredictionCard(
              predictionText: prediction.predictionText,
              generatedAt: prediction.generatedAt,
              isPro: isPro,
              canRefresh: prediction.canRefresh,
              onRefreshTap: () {
                SubscriptionService.instance.gate(
                  AppConstants.featurePredictionMonthly,
                  onPro: () {
                    // TODO: Call AI to generate updated prediction
                  },
                  onFree: () => showPaywallSheet(context,
                      feature: 'Monthly Prediction'),
                );
              },
            ),
          );
        }

        // Telegram link section
        if (extraIndex == 4) {
          return TelegramCard(
            isConnected: telegramConnected,
            onConnect: () => _openTelegramBot(),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  int _chatItemCount(List<ChatMessage> messages, bool telegramConnected) {
    // messages + action buttons + coach insight + deep analysis + prediction + telegram
    return messages.length + 5;
  }

  // ────────────────────────────────────────────────────────────────
  // ACTION BUTTONS
  // ────────────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _sendMessage('Sounds good, update my session!'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'SOUNDS GOOD',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  _sendMessage('Not today, keep the original session.'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    'NOT TODAY',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
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
  // COACH INSIGHT
  // ────────────────────────────────────────────────────────────────

  Widget _buildCoachInsight() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COACH INSIGHT',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            Consumer(
              builder: (context, ref, _) {
                final insight = ref.watch(coachInsightProvider);
                return Text(
                  insight,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                    height: 1.65,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  // QUICK PROMPT CHIPS
  // ────────────────────────────────────────────────────────────────

  Widget _buildQuickPrompts() {
    final prompts = ref.watch(contextualPromptsProvider);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 8),
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
                color: AppColors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send,
                color: AppColors.blue,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              telegramConnected
                  ? 'Telegram Connected'
                  : 'Connect to Telegram',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              telegramConnected
                  ? 'Your AI coach is available on Telegram. Open the app to continue your conversation.'
                  : 'Chat with your AI coach on Telegram for quick access anytime.',
              textAlign: TextAlign.center,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => _openTelegramBot(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: telegramConnected
                      ? AppColors.blue.withValues(alpha: 0.1)
                      : AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: telegramConnected
                      ? Border.all(
                          color: AppColors.blue.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  telegramConnected
                      ? 'Open Telegram'
                      : 'Connect @AVYACoachBot',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color:
                        telegramConnected ? AppColors.blue : Colors.black,
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
  // INPUT BAR
  // ────────────────────────────────────────────────────────────────

  Widget _buildInputBar(
      bool isSending, int messageCount, bool isPro, TrialInfoData trialInfo) {
    final isLimitReached = !isPro &&
        (messageCount >= AppConstants.freeAiMessagesPerDay ||
            trialInfo.isTrialExpired);

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 10, AppSpacing.screenPadding, 10),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Voice notes button
          VoiceNotesButton(
            isPro: isPro,
            isRecording: _isRecording,
            onLockedTap: () {
              SubscriptionService.instance.gate(
                AppConstants.featureVoiceNotes,
                onPro: () {
                  // Should not reach here since isPro is false
                },
                onFree: () =>
                    showPaywallSheet(context, feature: 'Voice Notes'),
              );
            },
            onStartRecording: () => _startListening(),
            onStopRecording: () => _stopListening(),
          ),
          const SizedBox(width: 8),

          // Text input
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _inputFocusNode,
              enabled: !isLimitReached && !isSending,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: _isRecording && _recognizedText.isNotEmpty
                    ? _recognizedText
                    : _isRecording
                        ? 'Listening...'
                        : isLimitReached
                            ? 'Daily limit reached. Upgrade to PRO!'
                            : 'Ask your coach...',
                hintStyle: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  color: _isRecording
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.input,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.5),
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onSubmitted: (text) => _sendMessage(text),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: isSending || isLimitReached
                ? null
                : () => _sendMessage(_messageController.text),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSending || isLimitReached
                    ? AppColors.textDisabled
                    : AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  isSending ? Icons.hourglass_top : Icons.send,
                  color: isSending || isLimitReached
                      ? AppColors.textSecondary
                      : Colors.black,
                  size: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<void> _openTelegramBot() async {
    final uri = Uri.parse('https://t.me/AVYACoachBot');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
