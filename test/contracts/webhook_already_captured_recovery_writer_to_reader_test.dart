// test/contracts/webhook_already_captured_recovery_writer_to_reader_test.dart
//
// payment-hardening U2 (OI-351, diagnose a9e2f7). Writer: razorpay-webhook's rereadIsCaptured (one bounded GET of
// the payment after Razorpay REFUSED our capture). Reader: the captureRefused branch, which records the row only
// on a strict "captured, this id, this amount" answer and otherwise keeps today's 502. Behaviour: the "U2 (1)" to
// "U2 (15c)" Deno tests in supabase/functions/razorpay-webhook/index_test.ts (incl. a TRUE golden with the kill
// switch set, and a hang bounded at 1.5 s). This file pins the wiring in source and the switch's documentation,
// and (hermes H12, diagnose c7e3b1) that the notes.user_id refusals run before the capture; behaviour: "H12:" tests.
//
// Run: flutter test test/contracts/webhook_already_captured_recovery_writer_to_reader_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _path = 'supabase/functions/razorpay-webhook/index.ts';
const _inventory = 'docs/operations/SECRET_INVENTORY.md';

String _code(String ts) => ts
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('webhook_already_captured_recovery', () {
    final code = _code(File(_path).readAsStringSync());

    test('the recovery is called exactly once, behind the switch, inside the captureRefused branch', () {
      const call =
          'if (!recoveryDisabled && await rereadIsCaptured(razorpayPaymentId, paymentEntity.amount, credentials)) {';
      expect(call.allMatches(code).length, 1);
      expect(RegExp(r'rereadIsCaptured\(').allMatches(code).length, 2, reason: 'the declaration and the one call');
      final branch = code.indexOf('if (captureRefused) {');
      expect(branch, greaterThan(0));
      expect(code.indexOf(call), greaterThan(branch));
    });

    test('the switch is read once per request with the shared exact-"true" rule', () {
      expect(code, contains('export const CAPTURE_RECOVERY_DISABLE_ENV = "DISABLE_WEBHOOK_CAPTURE_RECOVERY";'));
      expect('isEnvExactlyTrue(CAPTURE_RECOVERY_DISABLE_ENV)'.allMatches(code).length, 1);
    });

    test('the GET is bounded (a race against a timer) and the body is read inside the raced promise', () {
      final start = code.indexOf('export async function rereadIsCaptured(');
      final end = code.indexOf('export async function handler(');
      final fn = code.substring(start, end);
      expect(fn, contains('Promise.race([read, timeout])'));
      expect(fn.indexOf('await resp.json()'), lessThan(fn.indexOf('Promise.race([read, timeout])')));
      expect(fn, contains('}, timeoutMs);'));
      expect(code, contains('export const RECOVERY_GET_TIMEOUT_MS = 1500;'));
    });

    test('the recovery GET is a Razorpay fetch, not a supabase call (the client-declaration-order pin holds)', () {
      final start = code.indexOf('export async function rereadIsCaptured(');
      final end = code.indexOf('export async function handler(');
      final fn = code.substring(start, end);
      expect(fn, contains('fetch(`https://api.razorpay.com/v1/payments/\${paymentId}`'));
      expect(fn.contains('supabaseClient'), isFalse);
    });

    // hermes H12 (diagnose c7e3b1, bug class 2.120): a payment no row can record (no notes.user_id, or not a UUID)
    // is refused while only authorized; capturing it first took the money with nothing to write.
    test('the two notes.user_id refusals precede the capture POST and the authorized branch', () {
      final missing = code.indexOf('if (!userId) {');
      final malformed = code.indexOf('if (!uuidRegex.test(userId)) {');
      final branch = code.indexOf('if (event === "payment.authorized" && paymentEntity.captured === false) {');
      final post = code.indexOf('/capture`');
      for (final i in [missing, malformed, branch, post]) {
        expect(i, greaterThan(0));
      }
      expect('if (!userId) {'.allMatches(code).length, 1);
      expect('if (!uuidRegex.test(userId)) {'.allMatches(code).length, 1);
      expect(missing, lessThan(branch));
      expect(malformed, lessThan(branch));
      expect(branch, lessThan(post));
    });

    test('the kill switch is documented in the secret inventory', () {
      expect(File(_inventory).readAsStringSync(), contains('`DISABLE_WEBHOOK_CAPTURE_RECOVERY`'));
    });
  });
}
