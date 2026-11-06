// Bug a2c8e6 — delete-account Razorpay-cancel must be NON-FATAL so a Razorpay
// API hiccup (or a subscription-lookup error) cannot indefinitely block a
// legally-required DPDP §17 erasure. Pre-fix every cancel failure (lookup error,
// HTTP non-ok, exception) returned 502 and ABORTED the erasure. Fix: record the
// failure durably in account_deletion_log.razorpay_cancel_status (no FK, survives
// the auth delete) for out-of-band follow-up, and PROCEED with the erasure —
// still cancel-first so a healthy cancel protects the user from post-deletion
// charges.
//
// Source-grep contract (the EF runs in Deno; a behavioral test needs a Deno
// harness). Scoped to the RAZORPAY CANCEL section so an unrelated 502 elsewhere
// can't mask a regression.
//
// closes-diagnose: a2c8e6
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('delete-account Razorpay-cancel is non-fatal (a2c8e6)', () {
    late String src;
    late String cancelBlock;

    setUpAll(() {
      src =
          File('supabase/functions/delete-account/index.ts').readAsStringSync();
      final start = src.indexOf('RAZORPAY CANCEL');
      final end = src.indexOf('ONESIGNAL UNSUBSCRIBE');
      expect(start, isNonNegative, reason: 'cancel section must exist');
      expect(end, greaterThan(start), reason: 'onesignal section follows');
      cancelBlock = src.substring(start, end);
    });

    test('the cancel block no longer aborts the erasure with a 502', () {
      expect(
        cancelBlock.contains('return jsonError(502, "razorpay_cancel_failed"'),
        isFalse,
        reason: 'a Razorpay cancel failure must NOT abort the DPDP §17 erasure; '
            'record it and proceed.',
      );
    });

    test('cancel failures are recorded durably + cancel-first preserved', () {
      expect(cancelBlock.contains('cancelFailures'), isTrue,
          reason: 'failed cancellations must be tracked.');
      expect(cancelBlock.contains('cancel_failed'), isTrue,
          reason: 'razorpay_cancel_status records cancel_failed for follow-up.');
      expect(cancelBlock.contains('/cancel'), isTrue,
          reason: 'healthy cancel still runs first (protects user from charges).');
    });

    test('the audit log still records razorpay_cancel_status', () {
      expect(src.contains('razorpay_cancel_status: razorpayStatus'), isTrue,
          reason: 'account_deletion_log must record the (possibly failed) '
              'cancel status so it is not silently lost.');
    });

    test('audit-insert failure with a failed cancel emits a last-resort log '
        '(B-pass F1 — no silent billing loss)', () {
      // If the audit row insert ALSO fails (correlated outage), a failed cancel
      // must still leave a greppable trace in the function logs so the
      // subscription can be cancelled manually.
      expect(src.contains('ORPHAN_BILLING'), isTrue,
          reason: 'a failed cancel + failed audit insert must emit a distinctive '
              'ORPHAN_BILLING log so the billing obligation is not silently lost.');
      // The audit-insert catch must be console.error (not the old console.warn).
      expect(
        RegExp(r'audit insert failed \(non-fatal\):').hasMatch(src) &&
            src.contains('console.error'),
        isTrue,
        reason: 'the audit-insert failure must log at error level.',
      );
    });
  });
}
