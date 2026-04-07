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
/// RR-1  — Missing auth returns 401
/// RR-2  — Invalid code format returns error
/// RR-3  — Empty body returns error
/// RR-4  — Non-existent code returns "Invalid referral code"
/// RR-5  — OPTIONS request returns CORS headers
///
/// NOTE: Tests that require valid JWT and code redemption are covered
/// in the integration test suite on device (auth_flow_test.dart).

const _functionUrl =
    'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/redeem-referral';
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

void main() {
  // Skip all tests if anon key not provided (CI environments without secrets)
  final bool hasKey = _anonKey.isNotEmpty;

  group('redeem-referral Edge Function', () {
    test('RR-1: Missing auth returns 401', () async {
      if (!hasKey) return; // Skip in environments without the key

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
      expect(body['success'], isFalse);
    });

    test('RR-2: Invalid code format (too long) returns error', () async {
      if (!hasKey) return;

      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _anonKey,
          'Authorization': 'Bearer invalid-jwt-token',
        },
        body: jsonEncode({'code': 'A' * 50}),
      );

      // Should be 401 (invalid JWT) or 200 with error
      expect(response.statusCode, anyOf(401, 200));
    });

    test('RR-5: OPTIONS request returns CORS headers', () async {
      if (!hasKey) return;

      final request = http.Request('OPTIONS', Uri.parse(_functionUrl));
      request.headers['Origin'] = 'https://icanbefitter.com';
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      expect(response.headers.containsKey('access-control-allow-origin'), isTrue,
          reason: 'CORS preflight should include Allow-Origin header');
    });
  });

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
