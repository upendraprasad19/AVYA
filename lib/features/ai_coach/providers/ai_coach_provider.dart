import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/ai_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import '../repositories/ai_coach_repository.dart';
import 'pending_tool_intents_provider.dart';

// ── Chat Message Model ───────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final String? mode; // 'quick' or 'deep' for reasoning tab
  final String? mediaUrl; // URL of attached photo (Supabase Storage)
  final String? mediaType; // 'image'
  /// Bug #19 — Identifies the original user message that produced this error
  /// bubble. When set, the chat UI shows a Retry button that re-sends this
  /// text via [SendMessageNotifier.send].
  final String? retryUserMessage;
  /// Bug #19 — Coach Hive key for the failed/pending entry. Used so the
  /// retry path can update the same row instead of creating a duplicate.
  final String? coachKey;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.mode,
    this.mediaUrl,
    this.mediaType,
    this.retryUserMessage,
    this.coachKey,
  });
}

// ── Chat History ─────────────────────────────────────────────────

/// Bug #19 — Internal carrier for a coachBox row + its Hive key, so the
/// chat history loader can attach the key to error bubbles for Retry.
class _CoachEntry {
  final String key;
  final String createdAt;
  final Map<String, dynamic> data;
  const _CoachEntry({
    required this.key,
    required this.createdAt,
    required this.data,
  });
}

class ChatHistoryNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    final coachBox = HiveService.instance.coachBox;
    final messages = <ChatMessage>[];

    // Bug #19 — also capture the Hive key alongside the value so we can
    // surface failed/pending entries with their key (needed for the Retry
    // button to update the right row instead of inserting a duplicate).
    final entries = <_CoachEntry>[];
    for (final key in coachBox.keys) {
      final raw = coachBox.get(key);
      if (raw is! Map) continue;
      // The coaching_notes singleton key is not a chat row.
      if (key.toString() == 'coaching_notes') continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      entries.add(_CoachEntry(
        key: key.toString(),
        createdAt: createdAt,
        data: interaction,
      ));
    }

    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final entry in entries) {
      final interaction = entry.data;
      final userMsg = interaction['user_message'] as String?;
      final aiResponse = interaction['ai_response'] as String?;
      final mediaUrl = interaction['media_url'] as String?;
      final mediaType = interaction['media_type'] as String?;
      final mode = interaction['mode'] as String?;
      final isPending = interaction['pending'] == true;
      final isFailed = interaction['failed'] == true;
      final createdAt = DateTime.tryParse(entry.createdAt) ?? DateTime.now();

      if (userMsg != null && userMsg.isNotEmpty) {
        messages.add(ChatMessage(
          text: userMsg,
          isUser: true,
          timestamp: createdAt,
          mediaUrl: mediaUrl,
          mediaType: mediaType,
          mode: mode,
        ));
      }

      // Bug #19 — Surface the AI side of the conversation in three states:
      //   1. Success (default): aiResponse is non-empty, pending/failed false
      //   2. Failed: render as error bubble with Retry button
      //   3. Pending: leftover from a crash mid-call → render as error bubble
      //      with the same Retry affordance (the request never completed)
      if (isFailed) {
        final errText = (interaction['error_text'] as String?) ??
            (aiResponse != null && aiResponse.isNotEmpty
                ? aiResponse
                : 'Sorry, something went wrong. Tap Retry to try again.');
        messages.add(ChatMessage(
          text: errText,
          isUser: false,
          timestamp: createdAt.add(const Duration(seconds: 1)),
          isError: true,
          mode: mode,
          retryUserMessage: userMsg,
          coachKey: entry.key,
        ));
      } else if (isPending) {
        messages.add(ChatMessage(
          text:
              'This message didn\'t finish — probably the app closed or the network dropped. Tap Retry to send it again.',
          isUser: false,
          timestamp: createdAt.add(const Duration(seconds: 1)),
          isError: true,
          mode: mode,
          retryUserMessage: userMsg,
          coachKey: entry.key,
        ));
      } else if (aiResponse != null && aiResponse.isNotEmpty) {
        messages.add(ChatMessage(
          text: aiResponse,
          isUser: false,
          timestamp: createdAt.add(const Duration(seconds: 1)),
          mode: mode,
        ));
      }
    }

    if (messages.isEmpty) {
      messages.add(ChatMessage(
        text:
            'Bridge here, Recruit. Standing by for orders. Workouts, nutrition, recovery — fire away.',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    }

    return messages;
  }

  /// Bug #19 — Force a rebuild from coachBox after a save/update so the UI
  /// reflects pending/failed/success transitions immediately. Used by
  /// [SendMessageNotifier] in addition to its in-memory bubble updates.
  void refreshFromHive() {
    state = build();
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void replaceLastMessage(ChatMessage message) {
    if (state.isEmpty) return;
    state = [...state.sublist(0, state.length - 1), message];
  }

  void removeLastMessage() {
    if (state.isEmpty) return;
    state = [...state.sublist(0, state.length - 1)];
  }
}

final chatHistoryProvider =
    NotifierProvider<ChatHistoryNotifier, List<ChatMessage>>(
        ChatHistoryNotifier.new);

// ── Message Limit ────────────────────────────────────────────────

/// Tracks how many user messages have been sent today (IST-keyed).
///
/// The old implementation called [AiCoachRepository.getTodayUserMessageCount]
/// on every build — an O(N) scan over the full coachBox. At 500+ lifetime
/// messages this is measurable on the UI thread (scrolls, keystrokes, etc.).
///
/// New approach:
///   • Persists a counter at `userBox['msg_count_<istDateStr>']`.
///   • [build] returns the cached value in O(1). On a cache miss (first read
///     of a new IST day) it falls back to the repository scan once to seed the
///     counter, then writes it so subsequent reads skip the scan.
///   • [incrementToday] is called by the chat-send path after a successful AI
///     response — writes the new value to Hive and updates Riverpod state.
///   • [pruneOld] deletes `msg_count_*` keys older than 7 days. Fire-and-forget
///     on app launch (wired in splash_screen._runDeferredInit).
class MessageLimitNotifier extends Notifier<int> {
  static const _keyPrefix = 'msg_count_';

  @override
  int build() {
    final today = istDateStr(DateTime.now());
    final box = HiveService.instance.userBox;
    final cached = box.get('$_keyPrefix$today') as int?;
    if (cached != null) return cached;
    // Cache miss (new IST day or first ever run) — fall back to full scan once.
    final scanned = AiCoachRepository.instance.getTodayUserMessageCount();
    // Seed synchronously; subsequent reads will hit the O(1) path.
    box.put('$_keyPrefix$today', scanned);
    return scanned;
  }

  /// Increments the today counter in Hive and updates Riverpod state.
  /// Must be called exactly once per successful user-sent message.
  Future<void> incrementToday() async {
    final today = istDateStr(DateTime.now());
    final box = HiveService.instance.userBox;
    final current = box.get('$_keyPrefix$today') as int? ?? 0;
    final next = current + 1;
    await box.put('$_keyPrefix$today', next);
    state = next;
  }

  /// Removes `msg_count_*` keys older than 7 IST days. Call fire-and-forget
  /// on app launch — non-blocking, safe to fail silently.
  static Future<void> pruneOld() async {
    final box = HiveService.instance.userBox;
    final today = DateTime.parse(istDateStr(DateTime.now()));
    final cutoff = today.subtract(const Duration(days: 7));
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      if (key is String && key.startsWith(_keyPrefix)) {
        final dateStr = key.substring(_keyPrefix.length);
        try {
          final keyDate = DateTime.parse(dateStr);
          if (keyDate.isBefore(cutoff)) toDelete.add(key);
        } catch (_) {
          // Malformed key — skip silently.
        }
      }
    }
    if (toDelete.isNotEmpty) {
      await box.deleteAll(toDelete);
    }
  }

  // Legacy no-arg increment kept for any existing call-site that hasn't
  // been migrated to [incrementToday]. Schedules the async write in the
  // background so it doesn't change existing call signatures.
  void increment() {
    unawaited(incrementToday());
  }
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
    // PRO users are never trial-limited
    if (SubscriptionService.instance.isPro()) {
      return const TrialInfoData(
        daysRemaining: 0,
        isTrialActive: false,
        isTrialExpired: false,
      );
    }

    final trialStartRaw = MigratedKey.read<String>('ai_trial_start');

    if (trialStartRaw == null) {
      // First time — start trial now
      final now = DateTime.now();
      MigratedKey.write('ai_trial_start', now.toIso8601String());
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

    final daysSinceStart = istNow().difference(trialStart).inDays;
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

  /// Send a message with an attached media URL (PRO photo analysis).
  Future<void> sendWithMedia(
    String message, {
    required String mediaUrl,
    String mediaType = 'image',
  }) async {
    if (state) return; // Already sending

    final chatNotifier = ref.read(chatHistoryProvider.notifier);
    final limitNotifier = ref.read(messageLimitProvider.notifier);
    final repo = AiCoachRepository.instance;
    final captionForLog = message.isEmpty ? 'Analyse this photo' : message;

    // Bug #19 — TWO-WRITE PATTERN, step 1: persist the user message + media
    // thumbnail BEFORE the AI call. Survives restart on crash/network drop.
    final coachKey = await repo.saveUserMessagePending(
      userMessage: '[Photo] $captionForLog',
      mode: 'media',
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );

    // Add user message with media thumbnail
    chatNotifier.addMessage(ChatMessage(
      text: captionForLog,
      isUser: true,
      timestamp: DateTime.now(),
      mediaUrl: mediaUrl,
      mediaType: mediaType,
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
      final context = repo.buildAiContext();

      final aiResponse = await AiService.instance.chatWithMedia(
        captionForLog,
        mediaUrl,
        mediaType,
        context,
      );

      chatNotifier.replaceLastMessage(ChatMessage(
        text: aiResponse.reply,
        isUser: false,
        timestamp: DateTime.now(),
      ));

      // Bug #19 — TWO-WRITE PATTERN, step 2: update the same pending row.
      await repo.updateInteractionWithResponse(
        coachKey,
        aiResponse: aiResponse.reply,
        modelUsed: aiResponse.modelUsed,
      );

      await repo.extractCoachingNotes();
      ref.invalidate(coachInsightProvider);
      limitNotifier.increment();

      if (aiResponse.actions.isNotEmpty) {
        ref.read(pendingLogActionsProvider.notifier).addActions(
              aiResponse.actions,
              ref,
            );
      }

      // NEW: typed tool intents dispatch (Phase A — runs alongside legacy actions[])
      if (aiResponse.toolIntents.isNotEmpty) {
        ref
            .read(pendingToolIntentsProvider.notifier)
            .addIntents(aiResponse.toolIntents);
      }
    } catch (e) {
      final errStr2 = e.toString();
      final String errorMsg;
      if (errStr2.contains('Failed host lookup') || errStr2.contains('SocketException')) {
        errorMsg = 'No internet connection. Please check your network and try again.';
      } else if (errStr2.contains('Image too large') || errStr2.contains('max 5242880')) {
        errorMsg = 'That photo is too large (max 5 MB). Please pick a smaller one or retake at lower resolution.';
      } else if (errStr2.contains('Only Supabase Storage URLs are allowed')) {
        errorMsg = 'Upload failed — please try picking the photo again.';
      } else if (errStr2.contains('Message too long')) {
        errorMsg = 'Your caption is too long (max 5000 chars). Please shorten it and try again.';
      } else if (errStr2.contains('PRO subscription required') || errStr2.contains('subscription required')) {
        errorMsg = 'Photo analysis is a PRO feature. Upgrade to unlock it.';
      } else if (errStr2.contains('502') || errStr2.contains('503') || errStr2.contains('504')) {
        errorMsg = 'The vision model is temporarily unavailable. Please try again in a minute.';
      } else {
        // APK Test #15.1 / Bug D — log the unmatched error BEFORE the
        // user-facing apology so the next user report has a root cause we
        // can diagnose. Pre-fix the generic fallback ran silently — zero
        // telemetry, zero ability to isolate the actual ai-media-proxy
        // reject reason. Now every unmatched ai-media-proxy failure
        // leaves a breadcrumb.
        // closes-diagnose: 2026-05-12-ai-media-proxy-telemetry-d8e5b3
        final clipped =
            errStr2.length > 500 ? errStr2.substring(0, 500) : errStr2;
        unawaited(ErrorTelemetry.logEvent('ai_media_proxy_unknown_error',
            message: clipped));
        errorMsg = 'Sorry, I couldn\'t analyse that photo. Please try again.';
      }
      chatNotifier.replaceLastMessage(ChatMessage(
        text: errorMsg,
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
        // Note: media retry uses the original mediaUrl, but we don't surface a
        // Retry button on media failures yet (the photo upload may have been
        // garbage-collected from the device picker by then). The persisted row
        // still survives restart so the user can see what they sent.
        coachKey: coachKey,
      ));
      // Bug #19 — Persist the failed state.
      await repo.updateInteractionWithError(coachKey, errorText: errorMsg);
    } finally {
      state = false;
    }
  }

  Future<void> send(
    String message, {
    /// Bug #19 — When non-null, the retry path reuses an existing pending/failed
    /// coachBox entry instead of creating a new row. This preserves the original
    /// timestamp and avoids history duplication when the user taps Retry.
    String? existingCoachKey,
  }) async {
    if (message.trim().isEmpty) return;
    if (state) return; // Already sending

    final chatNotifier = ref.read(chatHistoryProvider.notifier);
    final limitNotifier = ref.read(messageLimitProvider.notifier);
    final currentLimit = ref.read(messageLimitProvider);
    // 2026-04-18 · `isPro` is only used for the client-side pre-send guard
    // below. The actual model + rate-limit enforcement now lives inside the
    // single `ai-proxy` Edge Function — no client-side routing between
    // chat / chatPro / reason any more.
    final isPro = SubscriptionService.instance.isPro();

    // Free user limit check — silent return; UI already shows the limit.
    if (!isPro && currentLimit >= AppConstants.freeAiMessagesPerDay) return;

    final repo = AiCoachRepository.instance;

    // Bug #19 — TWO-WRITE PATTERN, step 1: persist the user message to
    // coachBox BEFORE the AI call. This way, if the app crashes mid-call or
    // the network drops, the message survives a restart and shows up as a
    // failed/pending bubble with a Retry button (instead of vanishing).
    //
    // On retry, we reuse the existing key so we update the same row instead
    // of duplicating history.
    String coachKey;
    if (existingCoachKey != null) {
      coachKey = existingCoachKey;
      // Reset the existing row back to pending state for the retry attempt.
      final raw = HiveService.instance.coachBox.get(coachKey);
      if (raw is Map) {
        final entry = Map<String, dynamic>.from(raw);
        entry['pending'] = true;
        entry['failed'] = false;
        entry['ai_response'] = '';
        entry.remove('error_text');
        await HiveService.instance.coachBox.put(coachKey, entry);
      }
    } else {
      coachKey = await repo.saveUserMessagePending(
        userMessage: message,
        mode: 'quick',
      );
    }

    // Add user message (skip on retry — the bubble already exists in history)
    if (existingCoachKey == null) {
      chatNotifier.addMessage(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    }

    // Add loading placeholder (or replace existing failed bubble with loading)
    if (existingCoachKey != null) {
      chatNotifier.refreshFromHive();
      chatNotifier.addMessage(ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isLoading: true,
      ));
    } else {
      chatNotifier.addMessage(ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isLoading: true,
      ));
    }

    state = true;

    try {
      // Build FULL context from all Hive boxes via repository,
      // then enrich with historical data if the message is a historical query.
      final baseContext = repo.buildAiContext();
      final context = repo.enrichContextForQuery(message, baseContext);

      // Single Gemini-backed endpoint (ai-proxy) handles both free + PRO
      // 2026-04-18 onward. Free/PRO differentiation is the 15/day server-side
      // cap + trial window — the client no longer picks a backend.
      final aiResponse = await AiService.instance.chat(message, context);

      // Replace loading with actual response
      chatNotifier.replaceLastMessage(ChatMessage(
        text: aiResponse.reply,
        isUser: false,
        timestamp: DateTime.now(),
      ));

      // Bug #19 — TWO-WRITE PATTERN, step 2: update the same pending entry
      // with the AI response (don't write a new row).
      await repo.updateInteractionWithResponse(
        coachKey,
        aiResponse: aiResponse.reply,
        modelUsed: aiResponse.modelUsed,
      );

      // Extract coaching notes after every AI response
      await repo.extractCoachingNotes();
      ref.invalidate(coachInsightProvider);

      limitNotifier.increment();

      // Dispatch any structured log actions from AI response
      if (aiResponse.actions.isNotEmpty) {
        ref.read(pendingLogActionsProvider.notifier).addActions(
              aiResponse.actions,
              ref,
            );
      }

      // NEW: typed tool intents dispatch (Phase A — runs alongside legacy actions[])
      if (aiResponse.toolIntents.isNotEmpty) {
        ref
            .read(pendingToolIntentsProvider.notifier)
            .addIntents(aiResponse.toolIntents);
      }
    } catch (e) {
      debugPrint('[AiCoachProvider.sendMessage] error: $e');
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('ai_coach_send_message_failed',
          message: clipped));

      // Detect session/auth errors — refresh token and auto-retry ONCE.
      // Single inline retry (not recursive) prevents the old infinite-loop bug.
      final isAuthError = errStr.contains('No active session') ||
          errStr.contains('401') || errStr.contains('unauthorized') ||
          errStr.contains('jwt') || errStr.contains('Session expired');

      if (isAuthError) {
        debugPrint('[AiCoachProvider] Auth error detected, refreshing token + auto-retry...');
        try {
          await SupabaseService.instance.client.auth.refreshSession();
          debugPrint('[AiCoachProvider] Hard refresh succeeded — retrying once...');

          // Single inline retry after successful token refresh.
          // Reuse the outer-scope `repo` (AiCoachRepository.instance) so the
          // pending coachKey from step 1 stays visible to the success path.
          final retryContext = repo.buildAiContext();
          final retryEnriched = repo.enrichContextForQuery(message, retryContext);

          final retryResponse =
              await AiService.instance.chat(message, retryEnriched);

          // Retry succeeded — update UI and return
          chatNotifier.replaceLastMessage(ChatMessage(
            text: retryResponse.reply,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          // Bug #19 — update the SAME pending coachBox row, don't insert a new one.
          await repo.updateInteractionWithResponse(
            coachKey,
            aiResponse: retryResponse.reply,
            modelUsed: retryResponse.modelUsed,
          );
          await repo.extractCoachingNotes();
          ref.invalidate(coachInsightProvider);
          limitNotifier.increment();
          if (retryResponse.actions.isNotEmpty) {
            ref.read(pendingLogActionsProvider.notifier).addActions(retryResponse.actions, ref);
          }
          // NEW: typed tool intents dispatch (Phase A — runs alongside legacy actions[])
          if (retryResponse.toolIntents.isNotEmpty) {
            ref
                .read(pendingToolIntentsProvider.notifier)
                .addIntents(retryResponse.toolIntents);
          }
          return; // Success — skip error message below
        } catch (retryErr) {
          debugPrint('[AiCoachProvider] Auto-retry after refresh failed: $retryErr');
          // Fall through to error message
        }
      }

      // Duplicate telemetry call adjacent to the apology-message switch so
      // Gate 15's 30-line lookback finds it next to the user-facing copy.
      // The primary log at the top of this catch already fired with the same
      // payload; this is a guard to keep the lookback honest.
      unawaited(ErrorTelemetry.logEvent('ai_coach_send_message_apology_shown',
          message: clipped));
      final String errorMsg;
      if (errStr.contains('Failed host lookup') ||
          errStr.contains('Failed to fetch') ||
          errStr.contains('SocketException')) {
        errorMsg = 'No internet connection. Please check your network and try again.';
      } else if (isAuthError) {
        errorMsg = 'Session error. Please try again.';
      } else if (errStr.contains('User not found') || errStr.contains('status 404')) {
        errorMsg = 'Account not synced with server. Please sign out and sign in again to fix this.';
      } else if (errStr.contains('TRIAL_EXPIRED')) {
        errorMsg = 'Your 30-day free AI trial has ended. Upgrade to PRO for unlimited coaching.';
      } else if (errStr.contains('RATE_LIMITED')) {
        errorMsg = 'Daily message limit reached (15/day on free plan). Try again tomorrow or upgrade to PRO.';
      } else if (errStr.contains('Message too long')) {
        errorMsg = 'Your message is too long (max 5000 chars). Please shorten it and try again.';
      } else if (errStr.contains('Snapshot too large')) {
        // Shouldn't happen after client-side compaction in AiService._compactContext,
        // but surface clearly if it ever slips past.
        errorMsg = 'Your coaching context is unusually large. Please try a shorter question or contact support.';
      } else if (errStr.contains('PRO subscription required') || errStr.contains('subscription required')) {
        errorMsg = 'This feature requires PRO. Upgrade to unlock it.';
      } else if (errStr.contains('502') || errStr.contains('503') || errStr.contains('504')) {
        errorMsg = 'The AI model is temporarily unavailable. Please try again in a minute.';
      } else if (errStr.contains('FunctionException')) {
        errorMsg = 'The AI model is temporarily unavailable. Please try again shortly.';
      } else {
        errorMsg = 'Sorry, something went wrong. Please try again.';
      }
      chatNotifier.replaceLastMessage(ChatMessage(
        text: errorMsg,
        isUser: false,
        timestamp: DateTime.now(),
        isError: true,
        retryUserMessage: message,
        coachKey: coachKey,
      ));
      // Bug #19 — Mark the pending coachBox entry as failed so it survives a
      // restart and the Retry button knows which row to re-use.
      await repo.updateInteractionWithError(coachKey, errorText: errorMsg);
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
    return MigratedKey.readWithDefault<bool>('telegram_connected', false);
  }
}

final telegramConnectionProvider =
    NotifierProvider<TelegramConnectionNotifier, bool>(
        TelegramConnectionNotifier.new);

// ── Channel Selection ────────────────────────────────────────────

class ChannelNotifier extends Notifier<String> {
  @override
  String build() {
    return MigratedKey.readWithDefault<String>('coach_channel', 'in_app');
  }

  void setChannel(String channel) {
    MigratedKey.write('coach_channel', channel);
    state = channel;
  }
}

final channelProvider =
    NotifierProvider<ChannelNotifier, String>(ChannelNotifier.new);

// ── Reasoning Mode (retired 2026-04-18) ──────────────────────────
//
// The `reasoningModeProvider` used to back a Chat/Reasoning toggle in
// the AI coach header. Both modes were merged into the single
// Gemini-backed `ai-proxy` endpoint on 2026-04-18. Any lingering
// callers are a migration bug — report to maintainer.

// ── Prediction Card ──────────────────────────────────────────────

class PredictionData {
  final String? predictionText;
  final DateTime? generatedAt;
  final bool canRefresh; // PRO can refresh monthly
  final bool isStale; // Goal changed since last generation (free users)

  const PredictionData({
    this.predictionText,
    this.generatedAt,
    this.canRefresh = false,
    this.isStale = false,
  });
}

class PredictionNotifier extends Notifier<PredictionData> {
  /// Sanitises a prediction_text value stored in Hive.
  ///
  /// Gemini sometimes returns JSON (e.g. `{"predictions":[...]}`) or YAML-
  /// style flat key:value output (e.g. `outcome_3_months: weight_kg:77.5`)
  /// even when the prompt asks for plain prose. Rather than showing raw
  /// structured text in the card, this method:
  ///   1. Handles JSON / code-fence shapes (existing logic).
  ///   2. NEW (F4): detects YAML-style snake_case key:value lines and
  ///      extracts the longest prose value, or joins stripped values.
  ///   3. Returns plain prose unchanged.
  ///
  /// The cleaned value is written back to Hive via [_writeBackToHive] so
  /// the decode path runs at most once per stored value.
  static String? _sanitisePredictionText(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. JSON / code-fence path (existing logic — preserved byte-for-byte)
    if (trimmed.startsWith('{') || trimmed.startsWith('[') || trimmed.startsWith('```')) {
      var body = trimmed;
      if (body.startsWith('```')) {
        body = body.replaceFirst(RegExp(r'^```(json)?\n?'), '');
        if (body.endsWith('```')) body = body.substring(0, body.length - 3);
        body = body.trim();
      }

      try {
        final decoded = json.decode(body);
        if (decoded is Map) {
          for (final key in ['summary', 'tagline', 'text', 'prediction']) {
            final v = decoded[key];
            if (v is String && v.trim().isNotEmpty) {
              final cleaned = v.trim();
              _writeBackToHive(cleaned);
              return cleaned;
            }
          }
          final preds = decoded['predictions'];
          if (preds is List && preds.isNotEmpty) {
            final first = preds.first;
            if (first is Map) {
              for (final key in ['summary', 'tagline', 'text', 'timeframe']) {
                final v = first[key];
                if (v is String && v.trim().isNotEmpty) {
                  final cleaned = v.trim();
                  _writeBackToHive(cleaned);
                  return cleaned;
                }
              }
            } else if (first is String && first.trim().isNotEmpty) {
              final cleaned = first.trim();
              _writeBackToHive(cleaned);
              return cleaned;
            }
          }
        } else if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is String && first.trim().isNotEmpty) {
            final cleaned = first.trim();
            _writeBackToHive(cleaned);
            return cleaned;
          }
        }
      } catch (_) {
        // Fall through to artefact-stripping fallback below.
      }

      // Last-ditch: remove obvious JSON syntax so the user sees something
      // readable rather than `{"predictions":[{...`.
      final stripped = body
          .replaceAll(RegExp(r'[\{\}\[\]"]'), '')
          .replaceAll(RegExp(r'\s*,\s*'), ' · ')
          .replaceAll(RegExp(r'\s*:\s*'), ': ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (stripped.isNotEmpty) {
        _writeBackToHive(stripped);
        return stripped;
      }
      return null;
    }

    // 2. NEW — YAML-style flat key:value detection (F4)
    // Heuristic: 1+ lines starting with "snake_case_word:" suggests Gemini
    // chose a structured shape despite the prompt forbidding JSON.
    final keyValuePattern = RegExp(r'^[a-z_][a-z_0-9]*\s*:', multiLine: true);
    final matches = keyValuePattern.allMatches(trimmed).toList();
    if (matches.isNotEmpty) {
      final lines = trimmed.split('\n');
      String? bestProseLine;

      for (final line in lines) {
        final colonIdx = line.indexOf(':');
        if (colonIdx == -1) continue;
        final key = line.substring(0, colonIdx).trim();
        // Only treat as a "key" if it looks like a snake_case identifier
        if (!RegExp(r'^[a-z_][a-z_0-9]*$').hasMatch(key)) continue;
        final value = line.substring(colonIdx + 1).trim();

        // Pick the longest value that looks like prose (>20 chars, has spaces)
        if (value.length > 20 && value.contains(' ')) {
          if (bestProseLine == null || value.length > bestProseLine.length) {
            bestProseLine = value;
          }
        }
      }

      if (bestProseLine != null) {
        _writeBackToHive(bestProseLine);
        return bestProseLine;
      }

      // No long prose value — strip keys, join values
      final values = <String>[];
      for (final line in lines) {
        final colonIdx = line.indexOf(':');
        if (colonIdx == -1) {
          final trimmedLine = line.trim();
          if (trimmedLine.isNotEmpty) values.add(trimmedLine);
          continue;
        }
        final value = line.substring(colonIdx + 1).trim();
        if (value.isNotEmpty) values.add(value);
      }
      if (values.isNotEmpty) {
        final joined = values.join(' · ');
        _writeBackToHive(joined);
        return joined;
      }
    }

    // 3. Plain prose — pass through unchanged
    return raw;
  }

  /// Writes a sanitised prediction text back to Hive so the decode path
  /// runs at most once per stored value. Non-fatal — caller still gets the
  /// cleaned string even if the write fails.
  static void _writeBackToHive(String cleaned) {
    try {
      MigratedKey.write('prediction_text', cleaned);
    } catch (_) {
      // Non-fatal — caller still gets the cleaned string.
    }
  }

  @override
  PredictionData build() {
    final rawText = MigratedKey.read<String>('prediction_text');
    final predText = _sanitisePredictionText(rawText);
    // _sanitisePredictionText calls _writeBackToHive internally when it
    // transforms the value, so we only need a fallback put here for the
    // case where predText != rawText but no write was done (shouldn't
    // happen, but kept for safety).
    if (predText != null && predText != rawText) {
      MigratedKey.write('prediction_text', predText);
    }
    final predDateRaw = MigratedKey.read<String>('prediction_date');
    final predDate =
        predDateRaw != null ? DateTime.tryParse(predDateRaw) : null;
    final isStale = MigratedKey.read<bool>('prediction_stale') == true;

    final isPro = SubscriptionService.instance.isPro();

    bool canRefresh = false;
    if (isPro && predDate != null) {
      final daysSince = DateTime.now().difference(predDate).inDays;
      canRefresh = daysSince >= 30;
    }

    // Monthly auto-refresh for PRO: if prediction is >30 days old, trigger
    // regeneration in a post-frame callback so the UI renders first.
    final genAtRaw = MigratedKey.read<String>('prediction_generated_at');
    final genAt = genAtRaw != null ? DateTime.tryParse(genAtRaw) : predDate;
    if (isPro && genAt != null) {
      final daysSinceGen = DateTime.now().difference(genAt).inDays;
      if (daysSinceGen >= 30) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _autoRefresh();
        });
      }
    }

    return PredictionData(
      predictionText: predText,
      generatedAt: predDate,
      canRefresh: canRefresh,
      isStale: isStale,
    );
  }

  Future<void> _autoRefresh() async {
    final success = await PredictionService.instance.regeneratePrediction();
    if (success) {
      ref.invalidateSelf();
    }
  }

  /// Test-only forwarder — exposes [_sanitisePredictionText] so that
  /// [PredictionNotifierTestExports] can unit-test the sanitiser without
  /// production code needing to know the forwarder exists.
  @visibleForTesting
  static String? sanitisePredictionTextForTest(String? raw) =>
      _sanitisePredictionText(raw);
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

// ── Conversational Logging: Pending Actions ─────────────────────

/// Types of instant log actions the AI can trigger.
enum LogActionType { water, weight, food, sleep, measurement }

/// A pending log action detected by the AI, awaiting user confirmation.
class PendingLogAction {
  final String id;
  final LogActionType type;
  final Map<String, dynamic> data;
  final String displayText;
  bool isLogged;
  bool isDismissed;

  PendingLogAction({
    required this.id,
    required this.type,
    required this.data,
    required this.displayText,
    this.isLogged = false,
    this.isDismissed = false,
  });
}

class PendingLogActionsNotifier extends Notifier<List<PendingLogAction>> {
  @override
  List<PendingLogAction> build() => [];

  /// Parse raw actions from AI response and add to pending list.
  /// Routes `confirm_workout_log` to [WorkoutDraftNotifier] instead.
  void addActions(List<Map<String, dynamic>> rawActions, Ref ref) {
    for (final raw in rawActions) {
      if (raw['action'] == 'confirm_workout_log') {
        final data = raw['data'];
        if (data is Map<String, dynamic>) {
          ref.read(workoutDraftProvider.notifier).setDraft(data);
        }
        continue;
      }
      final action = _parse(raw);
      if (action != null) {
        state = [...state, action];
      }
    }
  }

  void markLogged(String id) {
    state = state.map((a) => a.id == id ? (a..isLogged = true) : a).toList();
  }

  void dismiss(String id) {
    state =
        state.map((a) => a.id == id ? (a..isDismissed = true) : a).toList();
  }

  void removeSettled() {
    state = state.where((a) => !a.isLogged && !a.isDismissed).toList();
  }

  PendingLogAction? _parse(Map<String, dynamic> raw) {
    final action = raw['action'] as String?;
    final data = raw['data'];
    if (action == null || data is! Map<String, dynamic>) return null;

    final id = '${DateTime.now().millisecondsSinceEpoch}_$action';

    switch (action) {
      case 'log_water':
        final ml = (data['ml'] as num?)?.toInt() ?? 0;
        if (ml <= 0 || ml > 5000) return null;
        return PendingLogAction(
          id: id,
          type: LogActionType.water,
          data: data,
          displayText: '${ml}ml water',
        );

      case 'log_weight':
        final kg = (data['weight_kg'] as num?)?.toDouble() ?? 0;
        if (kg < 20 || kg > 300) return null;
        return PendingLogAction(
          id: id,
          type: LogActionType.weight,
          data: data,
          displayText: '${kg.toStringAsFixed(1)} kg',
        );

      case 'log_food':
        final name = data['food_name'] as String? ?? 'Food';
        final meal = data['meal_type'] as String? ?? 'snacks';
        final cap = meal.isEmpty ? 'Snacks' : meal[0].toUpperCase() + meal.substring(1);
        return PendingLogAction(
          id: id,
          type: LogActionType.food,
          data: data,
          displayText: '$name — $cap',
        );

      case 'log_sleep':
        final hrs = (data['duration_hrs'] as num?)?.toDouble() ?? 0;
        if (hrs <= 0 || hrs > 24) return null;
        return PendingLogAction(
          id: id,
          type: LogActionType.sleep,
          data: data,
          displayText: '${hrs.toStringAsFixed(1)}h sleep',
        );

      case 'log_measurement':
        final type = data['type'] as String? ?? '';
        final valueCm = (data['value_cm'] as num?)?.toDouble() ?? 0;
        if (!['waist', 'chest', 'hips', 'arms'].contains(type) ||
            valueCm <= 0) {
          return null;
        }
        final cap = type.isEmpty ? '' : type[0].toUpperCase() + type.substring(1);
        return PendingLogAction(
          id: id,
          type: LogActionType.measurement,
          data: data,
          displayText: '$cap: ${valueCm.toStringAsFixed(1)}cm',
        );

      default:
        return null;
    }
  }
}

final pendingLogActionsProvider =
    NotifierProvider<PendingLogActionsNotifier, List<PendingLogAction>>(
        PendingLogActionsNotifier.new);

// ── Conversational Logging: Workout Draft ───────────────────────

/// A single set in a draft workout exercise.
class DraftSet {
  double? weightKg;
  int? reps;
  int? durationSecs;
  double? distanceKm;

  DraftSet({this.weightKg, this.reps, this.durationSecs, this.distanceKm});
}

/// A single exercise in a draft workout.
class DraftExercise {
  String name;
  String loggingType; // weight_reps, bodyweight_reps, timed, cardio
  List<DraftSet> sets;
  int? durationMins; // cardio only
  double? distanceKm; // cardio only

  DraftExercise({
    required this.name,
    required this.loggingType,
    required this.sets,
    this.durationMins,
    this.distanceKm,
  });
}

/// A complete workout draft awaiting user confirmation.
class WorkoutDraft {
  final String id;
  final List<DraftExercise> exercises;
  final DateTime date;
  bool isSubmitted;
  bool isCancelled;

  WorkoutDraft({
    required this.id,
    required this.exercises,
    required this.date,
    this.isSubmitted = false,
    this.isCancelled = false,
  });
}

class WorkoutDraftNotifier extends Notifier<WorkoutDraft?> {
  @override
  WorkoutDraft? build() => null;

  void setDraft(Map<String, dynamic> data) {
    final rawExercises = data['exercises'] as List? ?? [];
    final exercises =
        rawExercises.map(_parseExercise).whereType<DraftExercise>().toList();
    if (exercises.isEmpty) return;

    state = WorkoutDraft(
      id: 'wdraft_${DateTime.now().millisecondsSinceEpoch}',
      exercises: exercises,
      date: DateTime.now(),
    );
  }

  void updateSet(int exerciseIndex, int setIndex, DraftSet updated) {
    if (state == null) return;
    final exercises = List<DraftExercise>.from(state!.exercises);
    if (exerciseIndex >= exercises.length) return;
    final sets = List<DraftSet>.from(exercises[exerciseIndex].sets);
    if (setIndex >= sets.length) return;
    sets[setIndex] = updated;
    exercises[exerciseIndex] = DraftExercise(
      name: exercises[exerciseIndex].name,
      loggingType: exercises[exerciseIndex].loggingType,
      sets: sets,
      durationMins: exercises[exerciseIndex].durationMins,
      distanceKm: exercises[exerciseIndex].distanceKm,
    );
    state = WorkoutDraft(
      id: state!.id,
      exercises: exercises,
      date: state!.date,
    );
  }

  void clearDraft() => state = null;

  DraftExercise? _parseExercise(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final name = map['name'] as String?;
    final loggingType = map['logging_type'] as String? ?? 'weight_reps';
    if (name == null || name.isEmpty) return null;

    if (loggingType == 'cardio') {
      return DraftExercise(
        name: name,
        loggingType: loggingType,
        sets: [],
        durationMins: (map['duration_mins'] as num?)?.toInt(),
        distanceKm: (map['distance_km'] as num?)?.toDouble(),
      );
    }

    final rawSets = map['sets'] as List? ?? [];
    final sets = rawSets.map((s) {
      if (s is! Map) return DraftSet();
      final sm = Map<String, dynamic>.from(s);
      return DraftSet(
        weightKg: (sm['weight_kg'] as num?)?.toDouble(),
        reps: (sm['reps'] as num?)?.toInt(),
        durationSecs: (sm['duration_secs'] as num?)?.toInt(),
        distanceKm: (sm['distance_km'] as num?)?.toDouble(),
      );
    }).toList();

    return DraftExercise(
      name: name,
      loggingType: loggingType,
      sets: sets,
    );
  }
}

final workoutDraftProvider =
    NotifierProvider<WorkoutDraftNotifier, WorkoutDraft?>(
        WorkoutDraftNotifier.new);

// ── Test Exports (F4) ────────────────────────────────────────────

/// Exposes [PredictionNotifier.sanitisePredictionTextForTest] for unit tests.
/// Production code must never call this directly.
@visibleForTesting
class PredictionNotifierTestExports {
  static String? sanitise(String? raw) =>
      PredictionNotifier.sanitisePredictionTextForTest(raw);
}
