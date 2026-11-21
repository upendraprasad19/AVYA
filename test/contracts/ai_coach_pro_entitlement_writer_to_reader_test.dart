// Contract test — `checkPro` must tolerate ≥2 active subscription rows AND
// stay fail-closed AND log the downgrade.
//
// SoT concept: ai_coach_pro_entitlement. Diagnose: f2b9d4 (2026-09-03).
// Tech-debt audit 2026-09-02, Slice A, finding CODE-6.
//
// WRITER  the payment path inserts rows into `subscriptions`
//         (UNIQUE exists on razorpay_payment_id ONLY — migrations 052/094)
// READER  supabase/functions/ai-proxy/index.ts `checkPro()`
//
// Pre-fix `checkPro` ran `.eq("status","active").gt("end_date",…).maybeSingle()`
// with NO `.order("end_date").limit(1)`. Because there is no UNIQUE on
// `subscriptions(user_id)`, a user holding two overlapping active rows — the
// ordinary shape of a renewal bought before the old term lapses — made
// `maybeSingle()` synthesise PGRST116, `data` came back null, and a PAYING
// customer silently lost every PRO coach tool. The sibling query at
// `weekly-report/index.ts:74-84` already defends this way.
//
// It also destructured no `error` and used a bare `catch (_)`, so the
// downgrade produced no evidence at all (the 9d12af class).
//
// ⚠ WHAT MUST NOT CHANGE: returning `false` on error is DELIBERATE — the
// docstring says "cheaper to incorrectly gate a PRO user than to leak
// unlimited chat to a free user". An earlier draft of the audit plan proposed
// "fixing" that, which would have created the exact leak it guards against.
// The fail-closed test below exists to stop a future refactor doing so.
//
// SCOPE — honest (CLAUDE.md rule 21): SOURCE-GREP assertions prove PRESENCE,
// not runtime behaviour. `checkPro` is module-private inside
// `serve(async (req) => {…})` with no exports, and `ai-proxy` reads
// `Deno.env.get(...)!` at module load — there is no importable surface, and no
// Deno on the dev machine. CI's `deno check` is the compile proof; the SoT
// entry is marked `presence_only:` for exactly this reason.

import 'dart:io';
import 'package:test/test.dart';

const _aiProxy = 'supabase/functions/ai-proxy/index.ts';
const _sibling = 'supabase/functions/weekly-report/index.ts';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  late String checkProBody;

  setUpAll(() {
    final src = _stripComments(File(_aiProxy).readAsStringSync());
    // Isolate the function body — otherwise these assertions could be
    // satisfied by an unrelated subscriptions query elsewhere in a 1000+ line
    // file, which would make the test green about code it never examined.
    final start = src.indexOf('async function checkPro(');
    expect(start, greaterThan(-1), reason: 'checkPro() must still exist');
    final end = src.indexOf('\n}', start);
    expect(end, greaterThan(start), reason: 'checkPro() body must be findable');
    checkProBody = src.substring(start, end);
  });

  group('ai_coach_pro_entitlement writer → reader', () {
    test('READER destructures error from the subscription lookup', () {
      expect(
        RegExp(r'\{\s*data\s*,\s*error\s*\}\s*=\s*await\s+client')
            .hasMatch(checkProBody),
        isTrue,
        reason:
            'Pre-fix this was `const { data } = await client…`, so a failed '
            'query was indistinguishable from "no active subscription" and a '
            'paying user lost every PRO tool with no log anywhere.',
      );
    });

    test('READER tolerates ≥2 active rows via order + limit(1)', () {
      expect(
        RegExp(r'''\.order\(\s*["']end_date["']''').hasMatch(checkProBody),
        isTrue,
        reason:
            'No UNIQUE exists on subscriptions(user_id) — only on '
            'razorpay_payment_id. Two overlapping active rows (a renewal '
            'bought before the old end_date) make maybeSingle() error.',
      );
      expect(
        RegExp(r'\.limit\(\s*1\s*\)').hasMatch(checkProBody),
        isTrue,
        reason: 'Without .limit(1) the ≥2-row case still errors.',
      );
    });

    test('the sibling query this mirrors still carries the same defence', () {
      // If weekly-report ever loses its ordering, this concept's "copy the
      // neighbour" justification silently evaporates. Pin both ends.
      final sib = _stripComments(File(_sibling).readAsStringSync());
      expect(
        RegExp(r'''\.order\(\s*["']end_date["'].*\n\s*\.limit\(\s*1\s*\)''')
            .hasMatch(sib),
        isTrue,
        reason:
            'weekly-report/index.ts is the reference implementation for this '
            'pattern; if it drifts, checkPro has no sibling to match.',
      );
    });

    test('STILL fails closed — deliberate, must never be "fixed" open', () {
      final returnsFalse =
          RegExp(r'return\s+false\s*;').allMatches(checkProBody);
      expect(
        returnsFalse.length,
        greaterThanOrEqualTo(2),
        reason:
            'Both the error branch and the catch must return FALSE. Returning '
            'true on error would hand unlimited chat to every free user during '
            'any Postgres blip.',
      );
      expect(
        RegExp(r'return\s+true\s*;').hasMatch(checkProBody),
        isFalse,
        reason: 'checkPro must never GRANT pro on an error path.',
      );
    });

    test('logs the downgrade — silence was the actual defect', () {
      expect(
        RegExp(r'console\.error\(\s*\n?\s*`\[ai-proxy\.checkPro\]')
            .hasMatch(checkProBody),
        isTrue,
        reason:
            'Fail-closed was always correct; being SILENT about it was not. '
            'Without a log, a paying user losing PRO tools produces zero '
            'evidence — the 9d12af class.',
      );
    });
  });
}
