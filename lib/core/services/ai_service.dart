import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Structured response from any AI Edge Function.
///
/// [reply] is the visible message text (ICBF_LOG tags already stripped
/// server-side). [actions] contains zero or more log actions to be routed
/// to the conversational log handler on the client.
class AiChatResponse {
  final String reply;
  final String modelUsed;
  final int tokensUsed;
  final List<Map<String, dynamic>> actions;

  const AiChatResponse({
    required this.reply,
    required this.modelUsed,
    required this.tokensUsed,
    this.actions = const [],
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
/// PRO users: Edge Function `ai-proxy-pro`
///   Cerebras Llama 3.3 70B (direct)
class AiService {
  AiService._();
  static final AiService _instance = AiService._();
  static AiService get instance => _instance;

  final SupabaseService _supabase = SupabaseService.instance;
  final http.Client _httpClient = http.Client();

  // ── Response parsing helpers ──────────────────────────────────

  /// Parse the Edge Function response into an [AiChatResponse].
  AiChatResponse _parseResponse(dynamic data) {
    if (data is String) {
      final parsed = json.decode(data) as Map<String, dynamic>;
      return _buildResponse(parsed);
    }
    if (data is Map) {
      return _buildResponse(Map<String, dynamic>.from(data));
    }
    throw AiServiceException('Unexpected AI response format');
  }

  /// Build an [AiChatResponse] from a decoded JSON map.
  AiChatResponse _buildResponse(Map<String, dynamic> data) {
    final rawActions = data['actions'];
    return AiChatResponse(
      reply: data['reply'] as String? ?? data['response'] as String? ?? '',
      modelUsed: data['model_used'] as String? ?? 'unknown',
      tokensUsed: (data['tokens_used'] as num?)?.toInt() ?? 0,
      actions: (rawActions is List)
          ? rawActions
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : const [],
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
    try {
      final response = await _supabase.callFunction(
        'ai-proxy',
        body: {
          'message': message,
          'context': context,
          'snapshot_json': context,
        },
      );

      if (response.status != 200) {
        throw AiServiceException(
          'AI chat failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } on http.ClientException {
      return _directHttpCall('ai-proxy', message, context);
    } catch (e) {
      // Web fallback: 'Failed to fetch' is thrown by the browser fetch API
      if (e.toString().contains('Failed to fetch')) {
        return _directHttpCall('ai-proxy', message, context);
      }
      rethrow;
    }
  }

  /// Direct HTTP fallback for web when Supabase client fails.
  Future<AiChatResponse> _directHttpCall(
      String functionName, String message, Map<String, dynamic> context) async {
    final url = '${AppConstants.supabaseUrl}/functions/v1/$functionName';
    final session = _supabase.client.auth.currentSession;
    final token = session?.accessToken ?? AppConstants.supabaseAnonKey;

    final response = await _httpClient.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': AppConstants.supabaseAnonKey,
      },
      body: json.encode({
        'message': message,
        'context': context,
        'snapshot_json': context,
      }),
    );

    if (response.statusCode != 200) {
      throw AiServiceException(
          'Direct call failed: ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _buildResponse(data);
  }

  // ── PRO tier ──────────────────────────────────────────────────

  /// Send a message to the PRO-tier AI coach (Cerebras Llama 3.3 70B).
  ///
  /// Requires active PRO subscription. The [context] map should
  /// contain the user's daily snapshot for personalised responses.
  ///
  /// Returns an [AiChatResponse] with reply text and any detected
  /// log actions, or throws on failure.
  Future<AiChatResponse> chatPro(
      String message, Map<String, dynamic> context) async {
    try {
      final response = await _supabase.callFunction(
        'ai-proxy-pro',
        body: {
          'message': message,
          'context': context,
          'snapshot_json': context,
        },
      );

      if (response.status != 200) {
        throw AiServiceException(
          'PRO AI chat failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } on http.ClientException {
      return _directHttpCall('ai-proxy-pro', message, context);
    } catch (e) {
      if (e.toString().contains('Failed to fetch')) {
        return _directHttpCall('ai-proxy-pro', message, context);
      }
      rethrow;
    }
  }

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
    try {
      final response = await _supabase.callFunction(
        'ai-media-proxy',
        body: {
          'message': message,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'context': context,
          'snapshot_json': context,
        },
      );

      if (response.status != 200) {
        throw AiServiceException(
          'Media AI chat failed with status ${response.status}',
          statusCode: response.status,
        );
      }

      return _parseResponse(response.data);
    } on http.ClientException {
      return _directMediaHttpCall(message, mediaUrl, mediaType, context);
    } catch (e) {
      if (e.toString().contains('Failed to fetch')) {
        return _directMediaHttpCall(message, mediaUrl, mediaType, context);
      }
      rethrow;
    }
  }

  /// Direct HTTP fallback for media calls on web when Supabase client fails.
  Future<AiChatResponse> _directMediaHttpCall(
    String message,
    String mediaUrl,
    String mediaType,
    Map<String, dynamic> context,
  ) async {
    final url = '${AppConstants.supabaseUrl}/functions/v1/ai-media-proxy';
    final session = _supabase.client.auth.currentSession;
    final token = session?.accessToken ?? AppConstants.supabaseAnonKey;

    final response = await _httpClient.post(
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
        'context': context,
        'snapshot_json': context,
      }),
    );

    if (response.statusCode != 200) {
      throw AiServiceException(
          'Direct media call failed: ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _buildResponse(data);
  }

  // ── Reasoning ─────────────────────────────────────────────────

  /// Send a message to the PRO reasoning engine (GLM-4.7 on Cerebras).
  ///
  /// Used for deep personalised coaching in the Reasoning tab.
  Future<AiChatResponse> reason(
      String message, Map<String, dynamic> context) async {
    final response = await _supabase.callFunction(
      'ai-proxy-pro',
      body: {
        'message': message,
        'context': context,
        'mode': 'reasoning',
      },
    );

    if (response.status != 200) {
      throw AiServiceException(
        'Reasoning failed with status ${response.status}',
        statusCode: response.status,
      );
    }

    return _parseResponse(response.data);
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
