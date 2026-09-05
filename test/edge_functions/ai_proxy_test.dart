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

  // Delegates to the helper's FOUR-input predicate rather than checking url +
  // anonKey locally. This file's own two-value gate was the hole: with the
  // email and password now environment-driven, a run missing either would have
  // fallen through to a live `signInWithPassword(email: '', password: '')`
  // instead of skipping — failing with the exact error a WRONG password gives.
  if (!SupabaseTestHelper.hasCredentials) {
    test('SKIPPED: SUPABASE_URL / _ANON_KEY / _TEST_EMAIL / _TEST_PASSWORD '
        'not all set', () {});
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
      email: SupabaseTestHelper.testEmail,
      password: SupabaseTestHelper.testPassword,
    );
    accessToken = response.session!.accessToken;

    // OI-115's SECOND "also in scope" bullet: this file WRITES —
    // three live ai-proxy calls insert rows into ai_coach_interactions and
    // spend the signed-in account's daily quota. The board calls that the "same
    // boundary question" as the deletes, and the first pass guarded only the
    // deletes. A write to a non-QA account is less destructive than a delete but
    // it is still writing to somebody's real account, so it takes the same
    // membership check. There is no delete here, so this is the only guard on
    // the path.
    SupabaseTestHelper.assertDisposableTarget(
      signedInId: response.user!.id,
      targetId: response.user!.id,
    );

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

  /// Decoded 200 body, or `null` when the shared QA account has exhausted its
  /// REAL 10/day chat cap — in which case the cap contract is asserted instead,
  /// so neither branch is a free pass.
  ///
  /// ⚠ WHY THIS EXISTS, because "tolerate a 429" looks like weakening a test.
  /// Three tests below (T15, T18, T19) each send ONE live chat as ONE shared QA
  /// account, so a CI run costs 3 of that account's 10 daily messages. They
  /// asserted a bare `200` and were green for months — **because the cap was
  /// broken.** Until 2026-09-05 the trigger counted rows in
  /// `ai_coach_interactions`, which `rolling-context` prunes nightly, so the
  /// count reset before it could ever bite. OI-162 slice 2 (migration 129)
  /// moved it onto the durable `usage_counters` ledger and the cap started
  /// working — main went red on the 4th run of the IST day with
  /// `Expected: <200> Actual: <429>`, and the live ledger showed
  /// `test6@gmail.com chat_app used=10`.
  ///
  /// So this is not a test being loosened to accommodate a bug. It is a test
  /// that asserted something it does not control — the quota state of a shared
  /// account — being corrected to assert what it actually verifies: that
  /// `ai-proxy` returns a well-formed answer OR a well-formed refusal. The 429
  /// branch pins the `RATE_LIMITED` contract that `nutrition_provider.dart` and
  /// the client error-mapping depend on, which nothing asserted before.
  ///
  /// ⚠ The 3-runs-per-IST-day ceiling is REAL and is not fixed by this helper.
  /// A dedicated per-run QA account (or a PRO one, which the chat trigger
  /// exempts entirely) is the actual fix; it needs a founder decision about
  /// test-account provisioning, so it is raised rather than assumed here.
  Map<String, dynamic>? chatBodyOrAssertCapped(http.Response response) {
    if (response.statusCode == 429) {
      final capped = json.decode(response.body) as Map<String, dynamic>;
      expect(capped['code'], 'RATE_LIMITED',
          reason: 'a capped chat must carry the RATE_LIMITED code the client '
              'maps to its "daily limit" copy (ai-proxy err() at :766)');
      expect((capped['error'] ?? '').toString().toLowerCase(), contains('limit'),
          reason: 'the 429 body must say what happened');
      return null;
    }
    expect(response.statusCode, 200,
        reason: 'chat should return 200, or 429 when the shared QA account is '
            'capped — got ${response.statusCode}: ${response.body}');
    return json.decode(response.body) as Map<String, dynamic>;
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

      final data = chatBodyOrAssertCapped(response);
      if (data == null) return; // capped — the cap contract was asserted

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

      final data = chatBodyOrAssertCapped(response);
      if (data == null) return; // capped — the cap contract was asserted

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

      final data = chatBodyOrAssertCapped(response);
      if (data == null) return; // capped — the cap contract was asserted

      // Must have these fields (matching AiChatResponse structure)
      expect(data.containsKey('reply') || data.containsKey('response'), isTrue,
          reason: 'Must have reply/response field');
      expect(data.containsKey('model_used'), isTrue,
          reason: 'Must have model_used field');
    });
  });
}
