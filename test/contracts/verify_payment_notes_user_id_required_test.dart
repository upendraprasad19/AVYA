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
