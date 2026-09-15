import 'dart:convert';
import 'dart:io';

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

/// Relative to the package root, which is `flutter test`'s cwd. RR-src-0 is the
/// positive control that this still resolves.
const _efSourcePath = 'supabase/functions/redeem-referral/index.ts';

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
    test('RR-6: a VALID non-user JWT reaches the FUNCTION own 401', () async {
      // Added 2026-08-16. Every other 401 in this file is the GATEWAY's, so
      // before this test index.ts:55-60 — the function's own authentication
      // branch — was covered by nothing: deleting it outright reddened no test
      // here. The header above states that the function's {error, ...} contract
      // is unreachable for RR-1/RR-2; this closes that gap rather than only
      // documenting it.
      //
      // The anon key is a structurally VALID JWT, so the gateway admits the
      // request and index.ts runs; getUser() then resolves to no user and takes
      // the 401 branch. It carries no user identity, so this cannot read or
      // mutate anybody's rows.
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _anonKey,
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({'code': 'AVYA-TEST1234'}),
      );

      expect(response.statusCode, equals(401));
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // Pinning the literal string is right HERE and wrong in RR-1: this copy
      // is ours (index.ts:57), not Supabase platform copy. If someone edits the
      // function's message, this SHOULD red.
      expect(body['error'], equals('Authentication required'),
          reason: 'this 401 comes from index.ts:57, not the gateway');
      expect(body['request_id'], isA<String>(),
          reason: 'index.ts stamps a request_id on every response it authors');

      // Guards the test against silently decaying into a third gateway test:
      // if the gateway ever answers this request, `code` appears and `error`
      // vanishes, and RR-6 stops covering the function without anyone noticing.
      expect(body['code'], isNull,
          reason: 'gateway shape here means the request never reached index.ts '
              'and this test no longer covers the function');
      expect(body['success'], isNot(true));
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
  // Source pins — no network, no credentials, so these keep running in the
  // dart-define-less `Unit Tests` CI job (the reason the skip: above is scoped
  // to the live group rather than to main()).
  //
  // These replace five tests that compared literals to themselves — the whole
  // of RR-local-4 was `expect(50 >= 50, isTrue)`, and RR-local-1 tested Dart's
  // own `trim().toUpperCase()`. None could fail for any change to the product,
  // and RR-local-4 pinned `MAX_REDEMPTIONS_PER_CODE = 50`, a constant that
  // appears NOWHERE in index.ts — so it documented a cap the function has never
  // enforced. Replaced 2026-08-16 with assertions read from the function
  // source, which CAN fail when the function changes.
  // ─────────────────────────────────────────────────────────────────────────

  group('redeem-referral — source pins', () {
    late final String source = File(_efSourcePath).readAsStringSync();

    test('RR-src-0: the function source resolves from the test cwd', () {
      // Positive control. Without it every pin below passes vacuously the
      // moment this path is wrong — an empty input set wearing the same colour
      // as nothing-wrong, which is the same class as the skip: above.
      expect(File(_efSourcePath).existsSync(), isTrue,
          reason: 'wrong path ⇒ the pins below assert nothing');
      expect(source, contains('handleRedeemReferral'));
    });

    test('RR-src-1: codes are trimmed and uppercased before matching', () {
      expect(source, contains(r'(body.code ?? "").trim().toUpperCase()'),
          reason: 'index.ts:65 — a lowercase code from the UI must still match');
    });

    test('RR-src-2: CODE_FORMAT accepts AVYA- plus 8 uppercase alphanumerics',
        () {
      final decl =
          RegExp(r'const\s+CODE_FORMAT\s*=\s*/([^/]+)/').firstMatch(source);
      expect(decl, isNotNull, reason: 'CODE_FORMAT declaration not found');

      final pattern = RegExp(decl!.group(1)!);
      expect(pattern.hasMatch('AVYA-TEST1234'), isTrue);
      expect(pattern.hasMatch('avya-test1234'), isFalse,
          reason: 'index.ts uppercases first, so the regex itself is strict');
      expect(pattern.hasMatch('AVYA-SHORT'), isFalse);
      expect(pattern.hasMatch('A' * 50), isFalse,
          reason: 'the over-long code RR-2 sends would be rejected here too, '
              'if a valid JWT ever let it reach the function');
    });

    test('RR-src-3: the self-referral guard is still present', () {
      expect(source, contains('codeRow.user_id === referee.id'),
          reason: 'index.ts:88 — without it a user can refer themselves');
    });

    test('RR-src-4: the PRO grant is still 7 days', () {
      expect(source, matches(RegExp(r'const\s+DAYS_GRANTED\s*=\s*7\s*;')),
          reason: 'changes what every redeeming user actually receives');
    });

    test('RR-src-5: the new-recruit eligibility window is still 7 days', () {
      expect(
          source,
          matches(RegExp(r'const\s+SIGNUP_WINDOW_MS\s*=\s*'
              r'7\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1000\s*;')),
          reason: 'index.ts:94 compares the referee signup age against this');
    });

    test('RR-src-6: both 200 paths still carry success:true', () {
      // invite_friends_sheet.dart:106 reads `body['success'] == true`, so the
      // fresh-redeem 200 AND the 23505 idempotent-race 200 must both set it —
      // else the race path renders as a failure to the user.
      expect(RegExp(r'success:\s*true').allMatches(source).length,
          greaterThanOrEqualTo(2),
          reason: 'index.ts:127 (already-redeemed race) and :148 (fresh)');
    });
  });
}
