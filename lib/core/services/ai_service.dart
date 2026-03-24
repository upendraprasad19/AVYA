import 'dart:convert';

import 'package:icanbefitter/core/services/supabase_service.dart';

/// Calls Supabase Edge Functions for AI chat.
///
/// All AI calls go through Edge Functions — API keys are NEVER
/// exposed on the client.
///
/// Free users: Edge Function `ai-proxy` with 3-tier fallback
///   Cerebras Llama 3.1 8B -> Groq Llama 4 -> Gemini 2.0 Flash Lite
///
/// PRO users: Edge Function `ai-proxy-pro`
///   Cerebras gpt-oss-120B (direct)
class AiService {
  AiService._();
  static final AiService _instance = AiService._();
  static AiService get instance => _instance;

  final SupabaseService _supabase = SupabaseService.instance;

  /// Send a message to the free-tier AI coach.
  ///
  /// The [context] map should contain the user's daily snapshot
  /// (~300 tokens) for personalised responses.
  ///
  /// Returns the AI response text, or throws on failure.
  Future<String> chat(String message, Map<String, dynamic> context) async {
    final response = await _supabase.callFunction(
      'ai-proxy',
      body: {
        'message': message,
        'context': context,
      },
    );

    if (response.status != 200) {
      throw AiServiceException(
        'AI chat failed with status ${response.status}',
        statusCode: response.status,
      );
    }

    final data = response.data;
    if (data is String) {
      final parsed = json.decode(data) as Map<String, dynamic>;
      return parsed['response'] as String? ?? '';
    }
    if (data is Map) {
      return (data['response'] as String?) ?? '';
    }

    throw AiServiceException('Unexpected AI response format');
  }

  /// Send a message to the PRO-tier AI coach (Cerebras gpt-oss-120B).
  ///
  /// Requires active PRO subscription. The [context] map should
  /// contain the user's daily snapshot for personalised responses.
  ///
  /// Returns the AI response text, or throws on failure.
  Future<String> chatPro(String message, Map<String, dynamic> context) async {
    final response = await _supabase.callFunction(
      'ai-proxy-pro',
      body: {
        'message': message,
        'context': context,
      },
    );

    if (response.status != 200) {
      throw AiServiceException(
        'PRO AI chat failed with status ${response.status}',
        statusCode: response.status,
      );
    }

    final data = response.data;
    if (data is String) {
      final parsed = json.decode(data) as Map<String, dynamic>;
      return parsed['response'] as String? ?? '';
    }
    if (data is Map) {
      return (data['response'] as String?) ?? '';
    }

    throw AiServiceException('Unexpected PRO AI response format');
  }

  /// Send a message to the PRO reasoning engine (GLM-4.7 on Cerebras).
  ///
  /// Used for deep personalised coaching in the Reasoning tab.
  Future<String> reason(String message, Map<String, dynamic> context) async {
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

    final data = response.data;
    if (data is String) {
      final parsed = json.decode(data) as Map<String, dynamic>;
      return parsed['response'] as String? ?? '';
    }
    if (data is Map) {
      return (data['response'] as String?) ?? '';
    }

    throw AiServiceException('Unexpected reasoning response format');
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
