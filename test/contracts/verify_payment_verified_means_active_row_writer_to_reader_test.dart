// test/contracts/verify_payment_verified_means_active_row_writer_to_reader_test.dart
//
// OI-410 (diagnose in docs/diagnoses/2026-10-26-verify-payment-non-active-row-*.md). verify-payment answered
// `verified: true` for a payment whose subscriptions row was NOT `active` (cancelled, expired, ...), through three
// replay doors: the idempotency pre-select's `else` arm, the OFF-branch 23505 re-read, and the stacking-ON rpc's
// `inserted = false` answer. Invariant: for a row this request did not insert, `verified: true` needs a read, in
// the same request, that saw `status === "active"`; a non-active row is a soft failure (HTTP 200
// `verified: false`), and a row that cannot be read is "unconfirmed" (also a soft failure).
// Writer: verify-payment/index.ts (`replayVerdict`, `replayGate`, the three doors).
// Readers: RazorpayService._pollAndActivate (Phase 2) and payment_retry_attempt.dart, which write PRO only on
// `verified == true` (their own pins: verify_payment_owner_before_capture_writer_to_reader_test.dart and
// test/core/payment_retry_attempt_test.dart).
//
// This file pins the SHAPE in source (comments stripped). PRESENCE only: behaviour is in
// supabase/functions/verify-payment/index_test.ts (T0-T4, the real supabase-js client on a fetch-level fake).
//
// Run: flutter test test/contracts/verify_payment_verified_means_active_row_writer_to_reader_test.dart

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/verify-payment/index.ts';

String _code() => File(_path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    // `(?<!:)` keeps the `https://` of the Razorpay URLs.
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('verify_payment_verified_means_active_row', () {
    test('replayVerdict is the ONE place that decides, with a single strict `=== "active"`', () {
      final code = _code();
      final decl = RegExp(r'export function replayVerdict\([^)]*\)[^{]*\{([\s\S]*?)\n\}').firstMatch(code);
      expect(decl, isNotNull, reason: 'export function replayVerdict not found');
      final body = decl!.group(1)!;
      expect(RegExp(r'===\s*"active"').allMatches(body).length, 1);
      expect(body, isNot(contains('==="active')));
      expect(body, isNot(contains('toLowerCase')), reason: 'a case-insensitive compare would admit "ACTIVE"');
      expect(body, contains('"unconfirmed"'));
      expect(body, contains('"not_active"'));
    });

    test('exactly three doors call replayGate, each returns the refusal, with the row each door read', () {
      final code = _code();
      final calls = RegExp(r'const refused = replayGate\((\w+),\s*(\w+),\s*paymentId\);\s*if \(refused\) return refused;')
          .allMatches(code)
          .toList();
      expect(calls.length, 3, reason: 'one replayGate call per replay door');
      expect(calls.map((m) => m.group(1)).toSet(), {'paymentSubRow', 'raceRow', 'storedRow'});
      // each `const refused = replayGate(` in the file is one of those three (the definition is `function replayGate(`)
      expect(RegExp(r'const refused = replayGate\(').allMatches(code).length, 3);
      expect(RegExp(r'function replayGate\(').allMatches(code).length, 1);
    });

    test('each door reads the status, keyed on payment id AND user id (compact chains)', () {
      final code = _code();
      // door 1: the idempotency pre-select
      expect(
        RegExp(r'\.select\("id, end_date, status"\)\s*\.eq\("razorpay_payment_id",\s*paymentId\)\s*\.eq\("user_id",\s*userId\)')
            .allMatches(code)
            .length,
        1,
      );
      // door 2: the 23505 re-read
      expect(
        RegExp(r'\.select\("end_date, status"\)\s*\.eq\("razorpay_payment_id",\s*paymentId\)\s*\.eq\("user_id",\s*userId\)')
            .allMatches(code)
            .length,
        1,
      );
      // door 3: the stacking-ON status read, only when the rpc did not insert
      expect(
        RegExp(r'if \(!rec\.inserted\) \{[\s\S]{0,260}?\.select\("status"\)\s*\.eq\("razorpay_payment_id",\s*paymentId\)\s*\.eq\("user_id",\s*userId\)\s*\.maybeSingle\(\)')
            .allMatches(code)
            .length,
        1,
      );
    });

    test('the answer chain keeps its shape: one `if (paymentSubRow === null && stackingOn)`, one `else if (paymentSubRow === null)`, and the final `else` arm opens with the door-1 gate', () {
      final code = _code();
      // a FOURTH arm falling through to the final `verified: true` would add no literal and no gate call: pin the chain
      expect(RegExp(r'if \(paymentSubRow === null && stackingOn\) \{').allMatches(code).length, 1);
      expect(RegExp(r'\} else if \(paymentSubRow === null\) \{').allMatches(code).length, 1);
      expect(RegExp(r'\} else \{\s*(?://[^\n]*\s*)*const refused = replayGate\(paymentSubRow, null, paymentId\);').allMatches(code).length, 1);
      // and nothing else sits between the first arm and the door-1 gate: exactly ONE `else if` in that span
      final start = code.indexOf('if (paymentSubRow === null && stackingOn) {');
      final end = code.indexOf('const refused = replayGate(paymentSubRow, null, paymentId);');
      expect(start >= 0 && end > start, isTrue);
      expect(RegExp(r'\belse\s+if\b').allMatches(code.substring(start, end)).length, 1, reason: 'a fourth arm would skip every replay gate');
    });

    test('the early read stays active-only and `verified: true` has exactly two literals (the early read and the final answer)', () {
      final code = _code();
      expect(RegExp(r'\.eq\("status",\s*"active"\)').allMatches(code).length, 1);
      // a third `verified: true` answer would be a new door that skips the replay gate
      expect(RegExp(r'verified:\s*true').allMatches(code).length, 2);
    });

    test('the two soft-failure bodies are 200 `verified: false` answers with these exact messages', () {
      final code = _code();
      expect(code, contains('"Subscription for this payment is not active"'));
      expect(code, contains('"Could not confirm this payment yet; please retry"'));
      final gate = RegExp(r'function replayGate\([\s\S]*?\n\}').firstMatch(code);
      expect(gate, isNotNull);
      final body = gate!.group(0)!;
      expect(RegExp(r'verified:\s*false').allMatches(body).length, 2);
      expect(RegExp(r'status:\s*200').allMatches(body).length, 2);
      expect(body, isNot(contains('end_date')), reason: 'a refusal never carries a date');
      expect(body, contains('codeToken(rowStatus)'), reason: 'the raw status is never logged');
    });
  });
}
