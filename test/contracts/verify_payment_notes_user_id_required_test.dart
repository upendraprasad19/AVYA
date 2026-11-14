// Contract test — verify-payment MUST reject any payment whose
// `notes.user_id` is absent (400) BEFORE the ownership-mismatch check.
//
// Closes OI-29 (audit-2026-05-17 Hermes F4). Pre-fix the ownership check
// was `if (notesUserId && notesUserId !== userId) { return 403; }` —
// fail-open when `notes.user_id` was absent. An attacker who learns a
// captured Razorpay payment_id without notes could claim entitlement
// under their own JWT. Defense-in-depth: amount-derived plan limits
// blast radius but doesn't eliminate it.
//
// closes-diagnose: see `docs/diagnoses/2026-05-17-oi-29-verify-payment-notes-fail-open-*.md`

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/verify-payment/index.ts';

void main() {
  group('verify-payment notes.user_id required guard', () {
    test('"if (!notesUserId)" 400 guard appears BEFORE the !== userId check',
        () {
      final src = File(_path).readAsStringSync();

      final missingGuard = RegExp(r'if\s*\(\s*!\s*notesUserId\s*\)');
      final mismatchCheck =
          RegExp(r'if\s*\(\s*notesUserId\s*!==\s*userId\s*\)');

      final missingMatch = missingGuard.firstMatch(src);
      final mismatchMatch = mismatchCheck.firstMatch(src);

      expect(
        missingMatch,
        isNotNull,
        reason:
            'expected guard `if (!notesUserId)` returning 400 for missing '
            'user_id in payment notes. Without it the function fails open when '
            'notes is absent.',
      );
      expect(
        mismatchMatch,
        isNotNull,
        reason:
            'expected ownership-mismatch check `if (notesUserId !== userId)` '
            'returning 403. Both guards required; this test pins their '
            'co-existence.',
      );
      expect(
        missingMatch!.start < mismatchMatch!.start,
        isTrue,
        reason:
            'guard order regression: `if (!notesUserId)` (400) MUST appear '
            'BEFORE `if (notesUserId !== userId)` (403). Pre-fix the missing '
            'guard didn\'t exist; if a future refactor inverts the order the '
            'fail-open bug returns.',
      );
    });

    test('forbid the legacy fail-open pattern `if (notesUserId && ...)` '
        '(checked against code only, not comments)', () {
      final src = File(_path).readAsStringSync();

      // Strip JS line comments (`// ...`) and block comments (`/* ... */`)
      // before searching. The OI-29 fix adds a comment quoting the old
      // pattern in prose, which would falsely match a naive grep.
      final stripped = src
          // Block comments first (greedy across lines).
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          // Then line comments to end-of-line.
          .replaceAll(RegExp(r'//[^\n]*'), '');

      final failOpenRegex = RegExp(
        r'if\s*\(\s*notesUserId\s*&&\s*notesUserId\s*!==\s*userId\s*\)',
      );
      expect(
        failOpenRegex.hasMatch(stripped),
        isFalse,
        reason:
            'legacy fail-open pattern `if (notesUserId && notesUserId !== '
            'userId)` re-introduced in CODE (not in a comment). Use the '
            'two-step guard pattern instead: first 400 on missing, then 403 '
            'on mismatch.',
      );
    });

    test('both idempotency subscriptions reads by razorpay_payment_id are '
        'ALSO scoped to user_id (Hermes L23, 2026-09-11 — defense-in-depth)',
        () {
      // Not independently exploitable — payment.notes.user_id is already
      // proven == the caller's userId by the guard pinned above, before
      // either read below runs. Added anyway: a bare .eq("razorpay_payment_id",
      // paymentId) with no .eq("user_id", ...) is a "non-local" read (L23's
      // term) that would matter if a future refactor ever reordered the
      // ownership check above this line or reached it by a path that skips
      // it. ASSOCIATION, not membership: pin that user_id is queried in the
      // SAME statement as razorpay_payment_id, for BOTH read sites — one
      // fixed instance is not proof the sibling site got the same treatment.
      final src = File(_path).readAsStringSync();

      final subscriptionsReadBlocks = RegExp(
        r'\.from\("subscriptions"\)[\s\S]{0,200}?\.eq\("razorpay_payment_id",\s*paymentId\)[\s\S]{0,200}?\.maybeSingle\(\)',
      ).allMatches(src).toList();

      expect(
        subscriptionsReadBlocks.length,
        greaterThanOrEqualTo(2),
        reason: 'expected at least 2 subscriptions reads keyed on '
            'razorpay_payment_id (the idempotency pre-SELECT and the '
            '23505-race recovery read) — found '
            '${subscriptionsReadBlocks.length}. If this count changed, '
            're-verify every site below still carries the user_id filter, '
            'not just the ones this test happened to find.',
      );

      for (final m in subscriptionsReadBlocks) {
        final block = m.group(0)!;
        expect(
          RegExp(r'\.eq\("user_id",\s*userId\)').hasMatch(block),
          isTrue,
          reason: 'a subscriptions read scoped to razorpay_payment_id must '
              'ALSO carry .eq("user_id", userId) in the same statement — '
              'found a read missing it:\n$block',
        );
      }
    });

    test('400 body says "Missing user_id in payment notes"', () {
      // Pins the error string so client-side error mapping
      // (`AiService._extractError`) can match it deterministically.
      final src = File(_path).readAsStringSync();
      expect(
        src.contains('Missing user_id in payment notes'),
        isTrue,
        reason:
            'expected error message "Missing user_id in payment notes" in the '
            'OI-29 guard. Update this test if the wording changes — and '
            'update any client-side error mapping in the same PR.',
      );
    });
  });
}
