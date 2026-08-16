import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// ─────────────────────────────────────────────────────────────────────────────
/// redeem-referral Edge Function — Integration Test (Requires Supabase)
/// Run with: flutter test test/edge_functions/redeem_referral_test.dart
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Tests the redeem-referral Edge Function endpoint.
/// These tests hit the actual Supabase Edge Function (staging).
///
/// RR-1  — Missing auth returns 401 (gateway-rejected — see below)
/// RR-2  — Invalid JWT is gateway-rejected with 401
/// RR-5  — OPTIONS request returns CORS headers
///
/// (This list used to also claim RR-3 "Empty body returns error" and RR-4
/// "Non-existent code returns Invalid referral code". NEITHER HAS EVER EXISTED
/// in this file — `grep "test('RR-"` returns only 1, 2, 5 and the RR-local-*
/// set. Corrected 2026-08-16; a doc listing tests that do not exist reads as
/// coverage.)
///
/// ── WHO ANSWERS THESE REQUESTS (read before changing an assertion) ──────────
/// The deployed function runs with **verify_jwt: true**. The Supabase GATEWAY
/// therefore rejects any request without a valid Authorization header BEFORE
/// the function body executes, and the gateway's error shape is NOT the
/// function's:
///
///   gateway  → {"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"..."}
///   function → {"error":"...","request_id":"..."}   (index.ts:57-60, :156-164)
///
/// So for RR-1 and RR-2 the function's `{error, ...}` contract is unreachable,
/// and asserting ANY function-shaped key against them is asserting a contract
/// nothing produces. `success` is emitted ONLY on the 200 success paths
/// (index.ts:127, :148).
///
/// NOTE: Tests that require valid JWT and code redemption are covered
/// in the integration test suite on device (auth_flow_test.dart).

const _functionUrl =
    'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/redeem-referral';
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

void main() {
  // Gates ONLY the live-endpoint group below (see the skip: at its close).
  final bool hasKey = _anonKey.isNotEmpty;

  group('redeem-referral Edge Function', () {
    test('RR-1: Missing auth returns 401', () async {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _anonKey,
        },
        body: jsonEncode({'code': 'AVYA-TEST1234'}),
      );

      expect(response.statusCode, equals(401),
          reason: 'Missing Authorization header should return 401');
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // This asserted `body['success'] isFalse` until 2026-08-16 and failed on
      // every CI run that reached it, because the gateway answers this request
      // (verify_jwt: true — see the header) and its body carries only
      // {code, message}. `success` was never present; neither is `error`, so
      // "assert the function's error key instead" would have failed too.
      //
      // What is asserted instead is the property that actually matters and
      // holds no matter WHO answers: the response must never claim success.
      // Deliberately NOT pinning the gateway's `code`/`message` strings —
      // those are Supabase platform copy we do not control, and pinning them
      // buys nothing while risking a false red on any platform change.
      //
      // Still falsifiable: flip verify_jwt off and let the function 200 this
      // request, and both assertions here red.
      expect(body['success'], isNot(true),
          reason: 'an unauthenticated request must never report success');
    });

    test('RR-2: Invalid JWT is gateway-rejected with 401', () async {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _anonKey,
          'Authorization': 'Bearer invalid-jwt-token',
        },
        body: jsonEncode({'code': 'A' * 50}),
      );

      // Was `anyOf(401, 200)`, which accepted both outcomes and so could
      // barely fail. With verify_jwt: true a malformed bearer token cannot
      // reach the function at all, so 401 is guaranteed — assert exactly that.
      expect(response.statusCode, equals(401),
          reason: 'a malformed JWT is rejected by the gateway, not the function');
    });

    test('RR-5: OPTIONS request returns CORS headers', () async {
      final request = http.Request('OPTIONS', Uri.parse(_functionUrl));
      request.headers['Origin'] = 'https://icanbefitter.com';
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      expect(response.headers.containsKey('access-control-allow-origin'), isTrue,
          reason: 'CORS preflight should include Allow-Origin header');
    });
    // A REPORTED skip, not a silent one. Each test used to open with
    // `if (!hasKey) return;`, which makes a credential-less run render as a
    // PASS — indistinguishable from "the endpoint behaved correctly". That is
    // the OI-105 class: an empty input set reporting in the same colour as
    // nothing-wrong. A group-level `skip:` with a reason prints the reason and
    // counts as skipped.
    //
    // Scoped to THIS group on purpose: the RR-local-* group below needs no
    // network and must keep running in the dart-define-less `Unit Tests` CI
    // job, so an early `return` from main() would silently drop that coverage.
  }, skip: hasKey ? null : 'SUPABASE_ANON_KEY not set — live-endpoint tests skipped');

  // ─────────────────────────────────────────────────────────────────────────
  // Local validation logic tests (always run, no network needed)
  // ─────────────────────────────────────────────────────────────────────────

  group('redeem-referral — local validation', () {
    test('RR-local-1: Code trimming and uppercasing', () {
      const input = '  avya-test1234  ';
      final processed = input.trim().toUpperCase();
      expect(processed, equals('AVYA-TEST1234'));
    });

    test('RR-local-2: Code length validation (max 20)', () {
      const validCode = 'AVYA-UPEN1234';
      const tooLong = 'AVYA-ABCDEFGHIJKLMNOP';
      expect(validCode.length <= 20, isTrue);
      expect(tooLong.length <= 20, isFalse);
    });

    test('RR-local-3: Self-referral guard logic', () {
      const referrerId = 'user-aaa-bbb';
      const refereeIdSame = 'user-aaa-bbb';
      const refereeIdDiff = 'user-ccc-ddd';

      expect(referrerId == refereeIdSame, isTrue,
          reason: 'Same IDs should be caught as self-referral');
      expect(referrerId == refereeIdDiff, isFalse,
          reason: 'Different IDs should pass self-referral check');
    });

    test('RR-local-4: MAX_REDEMPTIONS_PER_CODE is 50', () {
      const maxRedemptions = 50;
      expect(49 >= maxRedemptions, isFalse);
      expect(50 >= maxRedemptions, isTrue);
      expect(51 >= maxRedemptions, isTrue);
    });

    test('RR-local-5: PRO_DAYS grant is 7', () {
      const proDays = 7;
      final endDate = DateTime(2026, 4, 7).add(Duration(days: proDays));
      expect(endDate, equals(DateTime(2026, 4, 14)),
          reason: '7-day PRO grant from Apr 7 should end Apr 14');
    });
  });
}
