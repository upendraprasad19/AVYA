import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import '../repositories/ai_coach_repository.dart';

// ── Chat Message Model ───────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final String? mode; // 'quick' or 'deep' for reasoning tab

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.mode,
  });
}

// ── Chat History ─────────────────────────────────────────────────

class ChatHistoryNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    final coachBox = HiveService.instance.coachBox;
    final messages = <ChatMessage>[];

    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final raw in coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      entries.add(MapEntry(createdAt, interaction));
    }

    entries.sort((a, b) => a.key.compareTo(b.key));

    for (final entry in entries) {
      final interaction = entry.value;
      final userMsg = interaction['user_message'] as String?;
      final aiResponse = interaction['ai_response'] as String?;
      final createdAt = DateTime.tryParse(entry.key) ?? DateTime.now();

      if (userMsg != null && userMsg.isNotEmpty) {
        messages.add(ChatMessage(
          text: userMsg,
          isUser: true,
          timestamp: createdAt,
        ));
      }
      if (aiResponse != null && aiResponse.isNotEmpty) {
        messages.add(ChatMessage(
          text: aiResponse,
          isUser: false,
          timestamp: createdAt.add(const Duration(seconds: 1)),
        ));
      }
    }

    if (messages.isEmpty) {
      messages.add(ChatMessage(
        text:
            'Hey! I\'m your AI fitness coach. Ask me anything about your workouts, nutrition, or fitness goals!',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void replaceLastMessage(ChatMessage message) {
    if (state.isEmpty) return;
    state = [...state.sublist(0, state.length - 1), message];
  }
}

final chatHistoryProvider =
    NotifierProvider<ChatHistoryNotifier, List<ChatMessage>>(
        ChatHistoryNotifier.new);

// ── Message Limit ────────────────────────────────────────────────

class MessageLimitNotifier extends Notifier<int> {
  @override
  int build() {
    // Use repository to count only USER messages (not AI responses)
    return AiCoachRepository.instance.getTodayUserMessageCount();
  }

  void increment() => state = state + 1;
}

final messageLimitProvider =
    NotifierProvider<MessageLimitNotifier, int>(MessageLimitNotifier.new);

// ── Trial Expiry ─────────────────────────────────────────────────

class TrialInfoData {
  final int daysRemaining;
  final bool isTrialActive;
  final bool isTrialExpired;

  const TrialInfoData({
    this.daysRemaining = 0,
    this.isTrialActive = false,
    this.isTrialExpired = false,
  });
}

class TrialInfoNotifier extends Notifier<TrialInfoData> {
  @override
  TrialInfoData build() {
    final configBox = HiveService.instance.configBox;
    final trialStartRaw = configBox.get('ai_trial_start') as String?;

    if (trialStartRaw == null) {
      // First time — start trial now
      final now = DateTime.now();
      configBox.put('ai_trial_start', now.toIso8601String());
      return TrialInfoData(
        daysRemaining: AppConstants.freeAiTrialDays,
        isTrialActive: true,
        isTrialExpired: false,
      );
    }

    final trialStart = DateTime.tryParse(trialStartRaw);
    if (trialStart == null) {
      return const TrialInfoData(
        daysRemaining: 0,
        isTrialActive: false,
        isTrialExpired: true,
      );
    }

    final daysSinceStart = DateTime.now().difference(trialStart).inDays;
    final remaining = AppConstants.freeAiTrialDays - daysSinceStart;

    if (remaining <= 0) {
      return const TrialInfoData(
        daysRemaining: 0,
        isTrialActive: false,
        isTrialExpired: true,
      );
    }

    return TrialInfoData(
      daysRemaining: remaining,
      isTrialActive: true,
      isTrialExpired: false,
    );
  }
}

final trialInfoProvider =
    NotifierProvider<TrialInfoNotifier, TrialInfoData>(TrialInfoNotifier.new);

// ── Send Message ─────────────────────────────────────────────────

class SendMessageNotifier extends Notifier<bool> {
  @override
  bool build() => false; // isLoading

  Future<void> send(String message, {String mode = 'quick'}) async {
    if (message.trim().isEmpty) return;
    if (state) return; // Already sending

    final chatNotifier = ref.read(chatHistoryProvider.notifier);
    final limitNotifier = ref.read(messageLimitProvider.notifier);
    final currentLimit = ref.read(messageLimitProvider);
    final isPro = SubscriptionService.instance.isPro();

    // Free user limit check
    if (!isPro && currentLimit >= AppConstants.freeAiMessagesPerDay) return;

    // Add user message
    chatNotifier.addMessage(ChatMessage(
      text: message,
      isUser: true,
      timestamp: DateTime.now(),
      mode: mode,
    ));

    // Add loading placeholder
    chatNotifier.addMessage(ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isLoading: true,
    ));

    state = true;

    try {
      // Build FULL context from all Hive boxes via repository
      final repo = AiCoachRepository.instance;
      final context = repo.buildAiContext();

      final modelUsed = mode == 'deep'
          ? 'glm-4.7'
          : isPro
              ? 'cerebras-120b'
              : 'llama-3.1-8b';

      String response;
      if (mode == 'deep' && isPro) {
        response = await AiService.instance.reason(message, context);
      } else if (isPro) {
        response = await AiService.instance.chatPro(message, context);
      } else {
        response = await AiService.instance.chat(message, context);
      }

      // Replace loading with actual response
      chatNotifier.replaceLastMessage(ChatMessage(
        text: response,
        isUser: false,
        timestamp: DateTime.now(),
        mode: mode,
      ));

      // Save to coachBox via repository
      await repo.saveInteraction(
        userMessage: message,
        aiResponse: response,
        modelUsed: modelUsed,
        mode: mode,
      );

      // Extract coaching notes after every AI response (C4)
      await repo.extractCoachingNotes();
      ref.invalidate(coachInsightProvider);

      limitNotifier.increment();
    } catch (e) {
      chatNotifier.replaceLastMessage(ChatMessage(
        text: 'Sorry, I couldn\'t process that. Please try again.',
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
      ));
    } finally {
      state = false;
    }
  }
}

final sendMessageProvider =
    NotifierProvider<SendMessageNotifier, bool>(SendMessageNotifier.new);

// ── Telegram Connection ──────────────────────────────────────────

class TelegramConnectionNotifier extends Notifier<bool> {
  @override
  bool build() {
    final configBox = HiveService.instance.configBox;
    return configBox.get('telegram_connected', defaultValue: false) as bool;
  }
}

final telegramConnectionProvider =
    NotifierProvider<TelegramConnectionNotifier, bool>(
        TelegramConnectionNotifier.new);

// ── Channel Selection ────────────────────────────────────────────

class ChannelNotifier extends Notifier<String> {
  @override
  String build() {
    return HiveService.instance.configBox
        .get('coach_channel', defaultValue: 'in_app') as String;
  }

  void setChannel(String channel) {
    HiveService.instance.configBox.put('coach_channel', channel);
    state = channel;
  }
}

final channelProvider =
    NotifierProvider<ChannelNotifier, String>(ChannelNotifier.new);

// ── Reasoning Mode ───────────────────────────────────────────────

class ReasoningModeNotifier extends Notifier<String> {
  @override
  String build() => 'quick'; // 'quick' or 'deep'

  void setMode(String mode) => state = mode;
}

final reasoningModeProvider =
    NotifierProvider<ReasoningModeNotifier, String>(ReasoningModeNotifier.new);

// ── Prediction Card ──────────────────────────────────────────────

class PredictionData {
  final String? predictionText;
  final DateTime? generatedAt;
  final bool canRefresh; // PRO can refresh monthly

  const PredictionData({
    this.predictionText,
    this.generatedAt,
    this.canRefresh = false,
  });
}

class PredictionNotifier extends Notifier<PredictionData> {
  @override
  PredictionData build() {
    final configBox = HiveService.instance.configBox;
    final predText = configBox.get('prediction_text') as String?;
    final predDateRaw = configBox.get('prediction_date') as String?;
    final predDate =
        predDateRaw != null ? DateTime.tryParse(predDateRaw) : null;

    bool canRefresh = false;
    if (SubscriptionService.instance.isPro() && predDate != null) {
      final daysSince = DateTime.now().difference(predDate).inDays;
      canRefresh = daysSince >= 30;
    }

    return PredictionData(
      predictionText: predText,
      generatedAt: predDate,
      canRefresh: canRefresh,
    );
  }
}

final predictionProvider =
    NotifierProvider<PredictionNotifier, PredictionData>(
        PredictionNotifier.new);

// ── Contextual Quick Prompts ────────────────────────────────────

final contextualPromptsProvider = Provider<List<String>>((ref) {
  // Watch chatHistory so prompts refresh after user sends a message (C5)
  ref.watch(chatHistoryProvider);
  return AiCoachRepository.instance.getContextualPrompts();
});

// ── Coach Insight ───────────────────────────────────────────────

final coachInsightProvider = Provider<String>((ref) {
  final insight = AiCoachRepository.instance.getLatestInsight();
  if (insight.isNotEmpty) return insight;
  return 'Start chatting with your AI coach to get personalised fitness insights and tips!';
});
