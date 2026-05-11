import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';

/// Structured response from any AI Edge Function.
///
/// [reply] is the visible message text (ICBF_LOG tags already stripped
/// server-side). [actions] contains zero or more log actions to be routed
/// to the conversational log handler on the client.
///
/// [toolIntents] are typed write intents emitted by the server-side AI
/// coach tool registry (Phase A.6+). The dispatcher confirms each with the
/// user before executing it against the right Hive repository.
///
/// [toolCallsLog] is per-call telemetry from the server (tool name, status,
/// latency, etc.) — used for debugging the tool pipeline. Never surfaced
/// to end users.
class AiChatResponse {
  final String reply;
  final String modelUsed;
  final int tokensUsed;
  final List<Map<String, dynamic>> actions;
  final List<ToolIntent> toolIntents;
  final List<Map<String, dynamic>> toolCallsLog;

  const AiChatResponse({
    required this.reply,
    required this.modelUsed,
    required this.tokensUsed,
    this.actions = const [],
    this.toolIntents = const [],
    this.toolCallsLog = const [],
  });
}

/// Calls Supabase Edge Functions for AI chat.
///
/// All AI calls go through Edge Functions — API keys are NEVER
/// exposed on the client.
///
/// Free users: Edge Function `ai-proxy` with 3-tier fallback
///   Cerebras Llama 3.1 8B -> Groq Llama 4 -> Gemini 2.0 Flash Lite
///
/// All users: single Edge Function `ai-proxy` (Gemini 2.5 Flash)
///   Cerebras Llama 3.3 70B (direct)
class AiService {
  AiService._();
  static final AiService _instance = AiService._();
  static AiService get instance => _instance;

  final SupabaseService _supabase = SupabaseService.instance;
  http.Client? _httpClient;

  /// Lazily-created HTTP client for web fallback calls.
  /// Closed by [dispose] when the app shuts down.
  http.Client get _client => _httpClient ??= http.Client();

  /// Closes the HTTP client. Call from app teardown (e.g. in main dispose).
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }

  // ── Error / size helpers ──────────────────────────────────────

  /// Pull a meaningful error message out of the Edge Function response body.
  ///
  /// Edge Functions return `{"error": "..."}` on non-200. Without this,
  /// callers would only see "status 400" and have no idea whether the user
  /// sent something too long, the snapshot blew past the 10KB limit, or
  /// the upstream model was actually down.
  String? _extractError(dynamic data) {
    try {
      Map<String, dynamic>? map;
      if (data is String) {
        final decoded = json.decode(data);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } else if (data is Map) {
        map = Map<String, dynamic>.from(data);
      }
      if (map == null) return null;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
      final msg = map['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {
      // Fall through — unparseable body, nothing we can surface.
    }
    return null;
  }

  /// Server-side snapshot limit (ai-proxy, unified 2026-04-18).
  /// We stay a little under to absorb JSON overhead added by the platform.
  static const int _maxSnapshotBytes = 9500;

  /// Compact the context JSON so it fits inside the server's snapshot limit.
  ///
  /// Keeps the core profile / progress / today's data and trims the biggest
  /// optional fields first. Without this, any historical query that triggers
  /// `enrichContextForQuery` (exercise history, nutrition/weight trends) can
  /// easily blow past 10KB and get rejected with a generic 400.
  ///
  /// A9 — Spec §7.3 priority order (APK Test #4):
  ///   1. step_history_7d      ← pedometer history, cheapest to lose
  ///   2. water_7d             ← hydration trend, not needed per-turn
  ///   3. weight_trend         ← 30-day weight series
  ///   4. nutrition_trend_7d   ← macro trend (keep meals_today — it's load-bearing)
  ///   5. exercise_history     ← past lift data
  ///   6. personal_records     ← PRs
  ///   7. coach_notices        ← in-app notices
  ///   8. truncate coaching_notes → 1000 chars
  ///   9. drop fitness_summary (last resort)
  ///
  /// Never-drop set (Captain Manual §2/§4/§8):
  ///   data_window_days, first_workout_date, workout_logs_count,
  ///   nutrition_logs_count_7d, sleep_logs_count_7d,
  ///   today_workout, yesterday_workout, week_lookahead,
  ///   meals_today, current_plan_summary,
  ///   current_rank, next_rank,
  ///   subscription,
  ///   committed_at, committed_to_lt_cdr, days_since_commitment.
  Map<String, dynamic> _compactContext(Map<String, dynamic> context) {
    Map<String, dynamic> working = Map<String, dynamic>.from(context);
    int size() => json.encode(working).length;
    if (size() <= _maxSnapshotBytes) return working;

    // Drop order — least load-bearing first.
    // NOTE: `current_rank` / `next_rank` / `subscription` / `committed_at`
    // and the anti-fab grounding keys are intentionally absent from this
    // list — they are identity-bearing and must survive all trim paths.
    // `meals_today` is also excluded: it is the only per-turn food log the
    // coach can reason about for protein-gap and calorie advice.
    const trimSteps = [
      'step_history_7d',   // 1 — pedometer history
      'water_7d',          // 2 — hydration trend series
      'weight_trend',      // 3 — 30-day weight series
      'nutrition_trend_7d', // 4 — 7-day macro trend (meals_today kept)
      'nutrition_trend',   // 4b — legacy key (same domain, remove if present)
      'exercise_history',  // 5 — past lift data
      'personal_records',  // 6 — PRs
      'coach_notices',     // 7 — in-app notices
    ];
    for (final key in trimSteps) {
      if (size() <= _maxSnapshotBytes) return working;
      working.remove(key);
    }

    // Step 8: truncate coaching_notes to 1000 chars — it can grow unbounded
    // across sessions but the most recent 1000 chars carry ~90% of the signal.
    if (size() > _maxSnapshotBytes) {
      final notes = working['coaching_notes'];
      if (notes is String && notes.length > 1000) {
        working['coaching_notes'] = '${notes.substring(0, 1000)}…';
      } else if (notes is Map) {
        // Drop everything except the most recent text field if present.
        final text = notes['text'] ?? notes['notes'];
        working['coaching_notes'] = text is String && text.length > 1000
            ? '${text.substring(0, 1000)}…'
            : text;
      }
    }
    if (size() <= _maxSnapshotBytes) return working;

    // Step 9 (last resort): drop fitness_summary.
    working.remove('fitness_summary');
    return working;
  }

  /// Test-only seam exposing the private compaction routine.
  @visibleForTesting
  static Map<String, dynamic> compactForTest(Map<String, dynamic> ctx) {
    return AiService._instance._compactContext(ctx);
  }

  // ── Response parsing helpers ──────────────────────────────────

  /// Parse the Edge Function response into an [AiChatResponse].
  AiChatResponse _parseResponse(dynamic data) {
    if (data is String) {
      try {
        final parsed = json.decode(data) as Map<String, dynamic>;
        return _buildResponse(parsed);
      } on FormatException catch (e) {
        throw AiServiceException('Malformed AI response JSON: $e');
      }
    }
    if (data is Map) {
      return _buildResponse(Map<String, dynamic>.from(data));
    }
    throw AiServiceException('Unexpected AI response format');
  }

  /// Pure / static parser for `tool_intents` field on an ai-proxy response.
  /// Defensive: a single malformed intent must not break the whole chat.
  /// Exposed as static so unit tests can assert multi-intent dispatch and
  /// snapshot-grounding contracts without spinning Hive/network/Riverpod.
  static List<ToolIntent> parseToolIntents(Map<String, dynamic> data) {
    final toolIntentsJson = (data['tool_intents'] as List?) ?? const [];
    final parsedIntents = <ToolIntent>[];
    for (final raw in toolIntentsJson) {
      if (raw is! Map) continue;
      try {
        parsedIntents
            .add(ToolIntent.fromJson(Map<String, dynamic>.from(raw)));
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[AiService] tool_intent parse failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'ai_service_parse_tool_intents'));
      }
    }
    return parsedIntents;
  }

  /// Build an [AiChatResponse] from a decoded JSON map.
  AiChatResponse _buildResponse(Map<String, dynamic> data) {
    final rawActions = data['actions'];

    // Phase A.6+ — typed write intents from the server tool registry.
    // ai-media-proxy does NOT emit tool_intents yet, so the field is
    // routinely absent there; default to empty list rather than null.
    final parsedIntents = parseToolIntents(data);

    // Per-call telemetry — tool name, status, latency, etc. Server-only
    // diagnostics; never surfaced to the user.
    final toolCallsLogJson = (data['tool_calls_log'] as List?) ?? const [];
    final parsedCallsLog = <Map<String, dynamic>>[];
    for (final raw in toolCallsLogJson) {
      if (raw is Map) {
        parsedCallsLog.add(Map<String, dynamic>.from(raw));
      }
    }

    return AiChatResponse(
      reply: data['reply'] as String? ?? data['response'] as String? ?? '',
      modelUsed: data['model_used'] as String? ?? 'unknown',
      tokensUsed: (data['tokens_used'] as num?)?.toInt() ?? 0,
      actions: (rawActions is List)
          ? rawActions
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : const [],
      toolIntents: parsedIntents,
      toolCallsLog: parsedCallsLog,
    );
  }

  // ── Free tier ─────────────────────────────────────────────────

  /// Send a message to the free-tier AI coach.
  ///
  /// The [context] map should contain the user's daily snapshot
  /// (~300 tokens) for personalised responses.
  ///
  /// Returns an [AiChatResponse] with reply text and any detected
  /// log actions, or throws on failure.
  Future<AiChatResponse> chat(
      String message, Map<String, dynamic> context) async {
    final compact = _compactContext(context);
    try {
      final response = await _supabase.callFunction(
        'ai-proxy',
        body: {
          'message': message,
          'context': compact,
          'snapshot_json': compact,
        },
      );

      if (response.status != 200) {
        final serverError = _extractError(response.data);
        throw AiServiceException(
          serverError ?? 'AI chat failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } on http.ClientException {
      return _directHttpCall('ai-proxy', message, compact);
    } catch (e) {
      // Web fallback: 'Failed to fetch' is thrown by the browser fetch API
      if (e.toString().contains('Failed to fetch')) {
        return _directHttpCall('ai-proxy', message, compact);
      }
      rethrow;
    }
  }

  /// Send a prediction request that bypasses daily limits and interaction
  /// logging. Used for onboarding predictions and PRO monthly refreshes.
  ///
  /// The Edge Function handles `type: 'prediction'` by skipping the daily
  /// message count check and the `ai_coach_interactions` insert.
  Future<AiChatResponse> predict(
      String message, Map<String, dynamic> context) async {
    final compact = _compactContext(context);
    try {
      final response = await _supabase.callFunction(
        'ai-proxy',
        body: {
          'message': message,
          'context': compact,
          'snapshot_json': compact,
          'type': 'prediction',
        },
      );

      if (response.status != 200) {
        final serverError = _extractError(response.data);
        throw AiServiceException(
          serverError ?? 'Prediction failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } catch (e) {
      if (e is AiServiceException) rethrow;
      throw AiServiceException('Prediction request failed: $e');
    }
  }

  /// Direct HTTP fallback for web when Supabase client fails.
  /// Proactively refreshes JWT before making the call.
  Future<AiChatResponse> _directHttpCall(
      String functionName, String message, Map<String, dynamic> context) async {
    final url = '${AppConstants.supabaseUrl}/functions/v1/$functionName';
    // Ensure fresh token before direct HTTP call
    final freshToken = await _supabase.ensureFreshToken();
    final token = freshToken ?? _supabase.client.auth.currentSession?.accessToken ?? AppConstants.supabaseAnonKey;

    final compact = _compactContext(context);
    final response = await _client.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': AppConstants.supabaseAnonKey,
      },
      body: json.encode({
        'message': message,
        'context': compact,
        'snapshot_json': compact,
      }),
    );

    if (response.statusCode != 200) {
      String? serverError;
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map) serverError = _extractError(decoded);
      } catch (_) {}
      throw AiServiceException(
        serverError ?? 'Direct call failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _buildResponse(data);
  }

  // ── PRO tier (retired 2026-04-18) ─────────────────────────────
  //
  // `chatPro` and `reason` used to route PRO traffic to the separate
  // `ai-proxy-pro` Edge Function (Cerebras Llama 3.3 70B) and the
  // reasoning backend (GLM-4.7 plan, never shipped). Both were merged
  // into the single Gemini-backed `ai-proxy` endpoint on 2026-04-18.
  // Callers should use `chat()` — server-side `isPro` gate handles
  // unlimited-vs-capped differentiation. `ai-proxy-pro` now returns
  // 410 Gone for any stragglers.

  // ── Media (PRO — Photo Analysis) ──────────────────────────────

  /// Send a message with an attached image to the PRO media AI coach.
  ///
  /// Requires active PRO subscription. The image at [mediaUrl] must
  /// already be uploaded to Supabase Storage. The Edge Function fetches
  /// it server-side and sends base64 to Gemini Flash for vision analysis.
  ///
  /// Returns an [AiChatResponse] with reply text and any detected
  /// log actions, or throws on failure.
  Future<AiChatResponse> chatWithMedia(
    String message,
    String mediaUrl,
    String mediaType,
    Map<String, dynamic> context,
  ) async {
    final compact = _compactContext(context);
    try {
      final response = await _supabase.callFunction(
        'ai-media-proxy',
        body: {
          'message': message,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'context': compact,
          'snapshot_json': compact,
        },
      );

      if (response.status != 200) {
        final serverError = _extractError(response.data);
        throw AiServiceException(
          serverError ?? 'Media AI chat failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } on http.ClientException {
      return _directMediaHttpCall(message, mediaUrl, mediaType, compact);
    } catch (e) {
      if (e.toString().contains('Failed to fetch')) {
        return _directMediaHttpCall(message, mediaUrl, mediaType, compact);
      }
      rethrow;
    }
  }

  /// Direct HTTP fallback for media calls on web when Supabase client fails.
  /// Proactively refreshes JWT before making the call.
  Future<AiChatResponse> _directMediaHttpCall(
    String message,
    String mediaUrl,
    String mediaType,
    Map<String, dynamic> context,
  ) async {
    final url = '${AppConstants.supabaseUrl}/functions/v1/ai-media-proxy';
    // Ensure fresh token before direct HTTP call
    final freshToken = await _supabase.ensureFreshToken();
    final token = freshToken ?? _supabase.client.auth.currentSession?.accessToken ?? AppConstants.supabaseAnonKey;

    final compact = _compactContext(context);
    final response = await _client.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': AppConstants.supabaseAnonKey,
      },
      body: json.encode({
        'message': message,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'context': compact,
        'snapshot_json': compact,
      }),
    );

    if (response.statusCode != 200) {
      String? serverError;
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map) serverError = _extractError(decoded);
      } catch (_) {}
      throw AiServiceException(
        serverError ?? 'Direct media call failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _buildResponse(data);
  }

}

/// Exception thrown by [AiService] when an Edge Function call fails.
class AiServiceException implements Exception {
  final String message;
  final int? statusCode;

  const AiServiceException(this.message, {this.statusCode});

  @override
  String toString() => 'AiServiceException: $message (status: $statusCode)';
}
