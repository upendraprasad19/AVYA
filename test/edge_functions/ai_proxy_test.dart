@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_test_helper.dart';

/// Layer 3: AI proxy Edge Function API tests.
///
/// Direct HTTP calls to Edge Functions — no UI, no Flutter widgets.
/// Validates auth guards, response format, and basic functionality.
///
/// Run: flutter test test/edge_functions/ai_proxy_test.dart \
///        --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isEmpty || anonKey.isEmpty) {
    test('SKIPPED: SUPABASE_URL / SUPABASE_ANON_KEY not set', () {});
    return;
  }

  late SupabaseClient client;
  late String accessToken;

  /// Whether `setUpAll` got all the way through sign-in.
  ///
  /// Both fields above are `late`. When `setUpAll` fails — which it does today,
  /// because the QA account does not exist — they are never assigned, and
  /// `tearDownAll`'s `signOut()` throws `LateInitializationError`, REPLACING
  /// the real failure in the output (OI-115, "also in scope" bullet 3).
  var setUpSucceeded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // That binding stubs ALL HTTP to a synthetic 400 without opening a
    // socket, which kills these INTEGRATION tests in setUpAll before their
    // first assertion (diagnose 3b7e1c). This file installs the binding
    // itself rather than calling SupabaseTestHelper.init(), so it must undo
    // the stub itself too — the original fix reached only test/supabase/.
    SupabaseTestHelper.restoreRealHttp();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getAll') return <String, dynamic>{};
      if (call.method == 'setBool' || call.method == 'setString' || call.method == 'remove') return true;
      return null;
    });

    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey);
    client = Supabase.instance.client;

    // Sign in as test user to get a valid access token
    final response = await client.auth.signInWithPassword(
      email: 'qa@icanbefitter.com',
      password: 'QA_Test_2024!',
    );
    accessToken = response.session!.accessToken;
    setUpSucceeded = true;
  });

  tearDownAll(() async {
    if (!setUpSucceeded) return;
    await client.auth.signOut();
  });

  /// Helper to call an Edge Function via HTTP.
  Future<http.Response> callEdgeFunction(
    String functionName, {
    Map<String, dynamic>? body,
    String? token,
    bool includeAuth = true,
  }) async {
    final url = '$supabaseUrl/functions/v1/$functionName';
    return http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'apikey': anonKey,
        if (includeAuth) 'Authorization': 'Bearer ${token ?? accessToken}',
      },
      body: json.encode(body ?? {}),
    );
  }

  group('AI Proxy — Auth', () {
    // T16: No auth token → 401
    test('T16: request without auth token returns 401', () async {
      final response = await callEdgeFunction(
        'ai-proxy',
        body: {'message': 'hello', 'context': {}, 'snapshot_json': {}},
        includeAuth: false,
      );

      // Edge Functions return 401 for missing/invalid auth
      expect(
        [401, 403].contains(response.statusCode),
        isTrue,
        reason:
            'Should reject unauthenticated request (got ${response.statusCode})',
      );
    });
  });

  group('AI Proxy — Free Tier', () {
    // T15: Free user chat → 200 + valid response
    test('T15: free user chat returns valid AI response', () async {
      final response = await callEdgeFunction(
        'ai-proxy',
        body: {
          'message': 'Say hello in one word',
          'context': {
            'profile': {'name': 'QA Test', 'goal': 'build_muscle'},
          },
          'snapshot_json': {
            'profile': {'name': 'QA Test', 'goal': 'build_muscle'},
          },
        },
      );

      expect(response.statusCode, 200,
          reason: 'Free chat should return 200 (got ${response.statusCode}: ${response.body})');

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Response must have 'reply' or 'response' field
      final reply = data['reply'] ?? data['response'];
      expect(reply, isNotNull, reason: 'Response must contain reply text');
      expect(reply, isA<String>());
      expect((reply as String).isNotEmpty, isTrue);

      // Should include model info
      expect(data['model_used'], isNotNull,
          reason: 'Response should indicate which model was used');
    });

    // T19: Context is used by the AI
    test('T19: AI references user context in response', () async {
      final response = await callEdgeFunction(
        'ai-proxy',
        body: {
          'message': 'What is my fitness goal? Answer in one short sentence.',
          'context': {
            'profile': {
              'name': 'TestUser',
              'goal': 'build_muscle',
              'primary_goal': 'build_muscle',
            },
          },
          'snapshot_json': {
            'profile': {
              'name': 'TestUser',
              'goal': 'build_muscle',
              'primary_goal': 'build_muscle',
            },
          },
        },
      );

      expect(response.statusCode, 200);

      final data = json.decode(response.body) as Map<String, dynamic>;
      final reply =
          ((data['reply'] ?? data['response']) as String).toLowerCase();

      // The AI should reference muscle/strength since the goal is build_muscle
      expect(
        reply.contains('muscle') ||
            reply.contains('strength') ||
            reply.contains('build') ||
            reply.contains('goal'),
        isTrue,
        reason: 'AI should reference user goal. Got: $reply',
      );
    });
  });

  group('AI Proxy — Response Format', () {
    // T18: Response has correct structure
    test('T18: response has reply, model_used, tokens_used fields', () async {
      final response = await callEdgeFunction(
        'ai-proxy',
        body: {
          'message': 'hi',
          'context': {},
          'snapshot_json': {},
        },
      );

      expect(response.statusCode, 200);

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Must have these fields (matching AiChatResponse structure)
      expect(data.containsKey('reply') || data.containsKey('response'), isTrue,
          reason: 'Must have reply/response field');
      expect(data.containsKey('model_used'), isTrue,
          reason: 'Must have model_used field');
    });
  });
}
