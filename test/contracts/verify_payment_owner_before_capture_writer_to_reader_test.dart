// test/contracts/verify_payment_owner_before_capture_writer_to_reader_test.dart
//
// payment-hardening U1 (OI-350 / OI-359, diagnose b5e8d2). verify-payment must prove the caller owns the payment
// (notes.user_id present: 400; equal to the JWT caller: 403) BEFORE it captures it or answers with its status.
// Writer: the two guards. Readers that must stay behind them: the capture POST and the status echo. Client
// reader: RazorpayService trusts only `status == 200 && verified == true`, so the reordered refusals change
// nothing it does. Behaviour: the "U1:" tests in supabase/functions/verify-payment/index_test.ts (no capture
// request is recorded on a refusal). This file pins the ORDER in source (comments stripped).
//
// Run: flutter test test/contracts/verify_payment_owner_before_capture_writer_to_reader_test.dart

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/verify-payment/index.ts';
const _client = 'lib/core/services/razorpay_service.dart';

void main() {
  group('verify_payment_owner_before_capture', () {
    test('both guards run BEFORE the capture and BEFORE the status echo '
        '(payment-hardening U1, OI-350 / OI-359; checked against code only)',
        () {
      // Before U1 the guards sat after the capture block and after the
      // `payment.status !== "captured"` echo, so a caller holding ANOTHER
      // user's authorized payment id made this function capture it, and any
      // payment's status came back in a 200. Behaviour: the U1 tests in
      // supabase/functions/verify-payment/index_test.ts.
      final code = File(_path)
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          // `(?<!:)` keeps the `https://` of the capture URL.
          .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

      final missing = RegExp(r'if\s*\(\s*!\s*notesUserId\s*\)').firstMatch(code);
      final mismatch =
          RegExp(r'if\s*\(\s*notesUserId\s*!==\s*userId\s*\)').firstMatch(code);
      final capture = RegExp(r'/capture`').firstMatch(code);
      final authorizedBranch =
          RegExp(r'payment\.status\s*===\s*"authorized"').firstMatch(code);
      final echo =
          RegExp(r'payment\.status\s*!==\s*"captured"').firstMatch(code);

      for (final (name, m) in [
        ('the 400 guard', missing),
        ('the 403 guard', mismatch),
        ('the capture URL', capture),
        ('the authorized branch', authorizedBranch),
        ('the status echo', echo),
      ]) {
        expect(m, isNotNull, reason: '$name not found in verify-payment code');
      }
      for (final (name, guard) in [('400', missing!), ('403', mismatch!)]) {
        for (final (later, m) in [
          ('the first /capture', capture!),
          ('the authorized branch', authorizedBranch!),
          ('the status echo', echo!),
        ]) {
          expect(guard.start < m.start, isTrue,
              reason: 'the $name ownership guard must precede $later');
        }
      }
    });

    test('the client trusts only a 200 with verified == true (a 400/403 is a soft failure either way)', () {
      final src = File(_client).readAsStringSync();
      expect(src, contains('verifyResponse.status == 200'));
      expect(src, contains("data['verified'] == true"));
    });
  });
}
