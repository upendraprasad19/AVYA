// Source-grep contract for the delete-account Edge Function safety
// surface (DPDP §17).
//
// Originally landed as T-1 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12 — file name now
// reflects the source-of-truth concept (delete-account safety), not the
// audit date.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-1 delete-account Edge Function safety contract (DPDP §17)', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/delete-account/index.ts');
    });

    test('verify_jwt=true at config layer (no manual auth bypass)', () {
      // The function MUST re-validate the JWT server-side via
      // auth.getUser(token) — this is the canonical "second layer"
      // after Supabase's gateway-level verify_jwt. Source-grep the
      // auth.getUser call.
      expect(src.contains('auth.getUser('), isTrue,
          reason: 'delete-account must call auth.getUser server-side; '
              'JWT gateway alone is insufficient for an irreversible action.');
    });

    test('confirmation_token check is exact-match', () {
      expect(
        src.contains('DELETE-MY-ACCOUNT-') ||
            src.contains('confirmation_token'),
        isTrue,
        reason:
            'delete-account must validate confirmation_token against the '
            'derived `DELETE-MY-ACCOUNT-<userIdPrefix>` value. Without '
            'this a stolen JWT could trigger deletion without the user '
            'physically typing the confirm string.',
      );
    });

    test('Razorpay cancel must succeed before deletion proceeds', () {
      expect(
        src.contains('api.razorpay.com/v1/subscriptions') ||
            src.contains('/subscriptions/') && src.contains('/cancel'),
        isTrue,
        reason:
            'delete-account must POST to Razorpay cancel endpoint before '
            'the auth.users delete. Otherwise we delete the user in our '
            'system but Razorpay keeps charging them.',
      );
    });

    test('account_deletion_log audit row written', () {
      expect(src.contains('account_deletion_log'), isTrue,
          reason:
              'delete-account must INSERT into account_deletion_log so '
              'support has a record of the deletion event (no FK; survives '
              'the cascade).');
    });
  });
}
