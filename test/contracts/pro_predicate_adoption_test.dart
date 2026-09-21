// test/contracts/pro_predicate_adoption_test.dart
//
// Regression guard for the PRO-tier predicate.
//
// WHAT HAPPENED (2026-07-26)
// --------------------------
// `morning-alert` decided PRO status from `users.subscription_status === "pro"`
// — a denormalized column with NO expiry term, which nothing ever writes back
// to 'free'. Three code paths set it to 'pro' (the update_user_subscription_status
// trigger, razorpay-webhook, verify-payment); none unset it.
//
// Live at the time: that column claimed 6 PRO users. The correct predicate
// (`subscriptions.status='active' AND end_date > now()`) returned **zero** —
// every subscription in the table had expired, the newest 13 days earlier. So
// 6 churned users were receiving Gemini-generated PRO-tier copy: paid AI tokens
// spent on people who had stopped paying, and the churn signal destroyed.
//
// The wider problem was that FIVE distinct hand-rolled PRO predicates existed
// across the Edge Functions with no shared helper. This test pins the two rules
// that make that unrepeatable.
//
// Rule 1 — the shared helper exists and implements BOTH terms.
// Rule 2 — no Edge Function READS `users.subscription_status` to decide tier.
//          (Writing it is fine — it stays as a cache for the admin dashboard;
//          it is reading it as truth that is the bug.)
//
// This test FAILS on the pre-fix source and PASSES after, per CLAUDE.md r21.

import 'dart:io';
import 'package:test/test.dart';

const _functionsDir = 'supabase/functions';
const _helper = '$_functionsDir/_shared/subscription.ts';

/// Reads of the denormalized column — the bug shape.
///
/// Deliberately does NOT match a write (`subscription_status: "pro"` inside an
/// update payload), which is legitimate: the column remains a cache, it just
/// must never be the source of truth for a tier decision.
final _readPatterns = <RegExp>[
  // .select("... subscription_status ...")
  RegExp(r'''\.select\(\s*['"][^'"]*subscription_status'''),
  // user.subscription_status === / !== / ==
  // `[!=]?` not `[!=]` — the mandatory form matched `===` and `!==` but NOT a
  // bare `==`, while the comment claimed all three. B-pass finding 3.
  RegExp(r'''\.subscription_status\s*[!=]?=='''),
  // .eq("subscription_status", ...)
  RegExp(r'''\.eq\(\s*['"]subscription_status['"]'''),
];

Iterable<File> _edgeFunctionSources() => Directory(_functionsDir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts'));

/// File + exact literal snippet for the ONE reviewed exception to the rule
/// below (2026-09-22, diagnose 9c4f2e). `founder_digest_content.ts`'s
/// `lapsedYesterday` metric deliberately reads `subscription_status` to
/// COUNT how often it drifts from `subscription_expires_at` — a
/// founder-facing "churn proxy" KPI, not a tier/access decision (see that
/// file's own doc comment on `lapsedYesterday` for the full reasoning: it
/// measures the exact cache-vs-truth drift this test exists to keep OUT of
/// tier decisions elsewhere; no user's access or AI-generated content
/// changes based on this read). Rewriting it to use fetchProUserIds()
/// instead would defeat the metric's own purpose — that helper reports who
/// is AUTHORITATIVELY pro right now, not who the stale cache still claims
/// is pro after expiry, which is the drift being measured.
///
/// Exempted by exact snippet removal, not a file-level skip, so a
/// DIFFERENT, illegitimate read added later to this same file is still
/// caught by the patterns below — and the companion `expect` in the loop
/// fails loudly if this literal ever stops matching, so the exemption
/// cannot silently widen or go stale.
const _metricsOnlyExemptFile =
    'supabase/functions/_shared/founder_digest_content.ts';
const _metricsOnlyExemptSnippet = '.eq("subscription_status", "pro")';

/// Strips block and line comments so prose describing the bug (including this
/// file's own rationale, mirrored into the helper's docstring) is not mistaken
/// for code. Per `feedback_source_grep_strip_comments_first`.
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  group('PRO predicate adoption', () {
    test('the shared helper exists and exports both entry points', () {
      final f = File(_helper);
      expect(f.existsSync(), isTrue,
          reason: '$_helper must exist — it is the single definition of PRO.');
      final src = f.readAsStringSync();
      expect(src, contains('export async function fetchProUserIds'),
          reason: 'Batch callers need a set-fetch; a per-user check inside a '
              'pagination loop is one query per user.');
      expect(src, contains('export async function isProUser'));
    });

    test('the helper checks status AND end_date — both terms', () {
      final src = _stripComments(File(_helper).readAsStringSync());
      expect(src, contains('"status"'),
          reason: 'Must filter status=active.');
      expect(src, contains('"end_date"'),
          reason: 'A status-only check reads every lapsed row as PRO — status '
              'is never reconciled to expired. This is THE bug.');
      // Both must appear in each of the two exported queries.
      final gtCount = RegExp(r'\.gt\(\s*"end_date"').allMatches(src).length;
      expect(gtCount, greaterThanOrEqualTo(2),
          reason: 'Both fetchProUserIds and isProUser must apply the expiry '
              'term. Found $gtCount `.gt("end_date")` call(s).');
    });

    test('no Edge Function READS users.subscription_status to decide tier', () {
      final violations = <String>[];
      for (final file in _edgeFunctionSources()) {
        var src = _stripComments(file.readAsStringSync());
        final relPath = file.path.replaceAll('\\', '/');
        if (relPath == _metricsOnlyExemptFile) {
          final before = src;
          src = src.replaceFirst(_metricsOnlyExemptSnippet, '');
          expect(src, isNot(before),
              reason: 'the reviewed metrics-only exemption snippet '
                  '($_metricsOnlyExemptSnippet) no longer appears verbatim '
                  'in $relPath — either it moved/was reformatted (update '
                  '_metricsOnlyExemptSnippet to match the new text) or it '
                  'was removed entirely (delete the now-unused exemption '
                  'too). Do not let this assertion go red silently.');
        }
        for (final p in _readPatterns) {
          if (p.hasMatch(src)) {
            violations.add('${file.path} matches ${p.pattern}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '`users.subscription_status` has no expiry term and nothing '
            'writes it back to "free" — reading it as truth marks lapsed users '
            'as PRO indefinitely. Use fetchProUserIds()/isProUser() from '
            '_shared/subscription.ts instead. Writing the column is still '
            'allowed (it is a cache for the admin dashboard).\n'
            'Violations:\n  ${violations.join("\n  ")}',
      );
    });

    test('POSITIVE CONTROL: the detector actually detects', () {
      // Guards against the whole test above passing vacuously if a pattern is
      // broken by a future edit — every other assertion here is an absence.
      const knownBad = 'const isPro = user.subscription_status === "pro";';
      expect(
        _readPatterns.any((p) => p.hasMatch(knownBad)),
        isTrue,
        reason: 'The detector failed to flag the exact pre-fix line from '
            'morning-alert:358. If this fails, the absence assertions above '
            'are passing vacuously and the guard is dead.',
      );
      // All three equality forms, not just the two the original regex caught.
      for (final op in ['==', '===', '!==']) {
        expect(
          _readPatterns.any(
            (p) => p.hasMatch('if (u.subscription_status $op "pro") {}'),
          ),
          isTrue,
          reason: 'Loose `$op` comparison must be flagged too.',
        );
      }
      // And a legitimate WRITE must NOT be flagged.
      const knownGood = '.update({ subscription_status: "pro" })';
      expect(
        _readPatterns.any((p) => p.hasMatch(knownGood)),
        isFalse,
        reason: 'Writing the cache column is legitimate and must not trip the '
            'guard — otherwise razorpay-webhook and verify-payment fail.',
      );
    });
  });
}
