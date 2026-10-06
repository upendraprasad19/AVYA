// Regression contract for d2b9e6 (referral RLS-context, 2026-06-13 Unit 1).
//
// Applying a referral code ALWAYS failed: redeem-referral read the REFERRER's code
// under the REFEREE's RLS context — the user JWT in `global.headers` made PostgREST
// run as `authenticated`, which the own-only referral_codes RLS + the service_role-only
// redeem_referral_atomic RPC both reject. referral_redemptions had 0 rows EVER, and the
// client masked the 4xx as a generic "Network error".
//
// This pins the fix across the EF (pure service-role client + getUser(token) + a single
// {success} shape) and the three client callers. Source-grep (the EF runs in Deno; the
// client FunctionException flow is integration-heavy), comment-stripped so the
// bug-describing comments cannot satisfy the assertions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  final ef = _strip(File('supabase/functions/redeem-referral/index.ts')
      .readAsStringSync());
  final repo = _strip(
      File('lib/features/profile/repositories/referral_repository.dart')
          .readAsStringSync());
  final onboarding = _strip(
      File('lib/features/onboarding/providers/onboarding_provider.dart')
          .readAsStringSync());
  final invite = _strip(
      File('lib/features/profile/screens/invite_friends_sheet.dart')
          .readAsStringSync());

  group('d2b9e6 — redeem-referral EF uses a pure service-role client', () {
    test('does NOT bake the user JWT into global.headers (the RLS-context bug)', () {
      expect(
        RegExp(r'global\s*:\s*\{\s*headers\s*:\s*\{\s*Authorization').hasMatch(ef),
        isFalse,
        reason:
            'the user JWT in global.headers overrides the service_role apikey → '
            'PostgREST runs as `authenticated` → RLS blocks the referrer-code read '
            'and the service_role-only RPC. Must use a pure service-role client.',
      );
    });

    test('authenticates the caller with getUser(token), not bare getUser()', () {
      expect(ef.contains('getUser(token)'), isTrue,
          reason:
              'validate the referee via getUser(token) on the service-role client');
    });

    test('200 success body carries `success: true` (one shape for all 3 callers)', () {
      expect(RegExp(r'success\s*:\s*true').hasMatch(ef), isTrue,
          reason:
              "the EF 200 body must include success:true so invite_friends_sheet "
              "(which reads body['success']) stops showing a false error on success");
    });

    test('the 23505 race-fallback 200 ALSO carries success:true (B-pass P2)', () {
      expect(ef.contains('alreadyRedeemed'), isTrue,
          reason: 'the 23505 idempotent-race fallback must exist');
      expect(RegExp(r'success\s*:\s*true').allMatches(ef).length,
          greaterThanOrEqualTo(2),
          reason:
              'BOTH the normal 200 and the 23505 alreadyRedeemed 200 must carry '
              "success:true, or invite_friends_sheet's body['success'] check shows a "
              'false error on a concurrent-redemption race');
    });
  });

  group('d2b9e6 — the three client callers converge on the contract', () {
    test('referral_repository unpacks FunctionException → surfaces the server message',
        () {
      expect(repo.contains('on FunctionException'), isTrue,
          reason:
              'the EF 4xx validation responses throw FunctionException — unpack it');
      expect(repo.contains("['error']"), isTrue,
          reason:
              "surface details['error'] (the server reason) instead of a generic "
              '"Network error" that hides why the code failed');
    });

    test('onboarding redeem routes through callFunction, not a raw invoke', () {
      expect(RegExp(r"callFunction\(\s*'redeem-referral'").hasMatch(onboarding),
          isTrue,
          reason:
              'onboarding redeem must route through callFunction (refreshes the JWT)');
      expect(
        RegExp(r"functions\s*\.\s*invoke\(\s*'redeem-referral'").hasMatch(onboarding),
        isFalse,
        reason: 'no raw functions.invoke for redeem-referral at onboarding (§2.31)',
      );
    });

    test("invite_friends_sheet success-detection reads body['success']", () {
      expect(invite.contains("['success']"), isTrue,
          reason:
              "invite_friends keys success off body['success'] — now satisfied by "
              'the EF sending success:true');
    });
  });
}
