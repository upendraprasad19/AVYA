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
//          Since OI-202 (migration 152) the column no longer exists AT ALL, so
//          this rule has no exemption left; the stricter "no reference to the
//          dropped columns anywhere" scan lives in
//          test/contracts/subscription_columns_dropped_test.dart. This rule stays
//          as the read-shape detector with its positive control.
//
// This test FAILS on the pre-fix source and PASSES after, per CLAUDE.md r21.

import 'dart:io';
import 'package:test/test.dart';

const _functionsDir = 'supabase/functions';
const _helper = '$_functionsDir/_shared/subscription.ts';

/// Reads of the denormalized column — the bug shape.
///
/// Matches READS only; a stray WRITE of the (now dropped) column is caught by
/// subscription_columns_dropped_test.dart instead.
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
            '_shared/subscription.ts instead. (The column is dropped — OI-202.)\n'
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
      // EACH pattern must catch its OWN shape. `any(...)` above is satisfied by
      // the `===` pattern alone, so a broken `.select` or `.eq` pattern left every
      // assertion green (mutation B18, OI-202: a deliberately broken `.eq(`
      // pattern reddened nothing).
      const ownShapes = <String>[
        '.select("id, subscription_status")',
        'if (u.subscription_status === "pro") {}',
        '.eq("subscription_status", "pro")',
      ];
      expect(ownShapes.length, _readPatterns.length);
      for (var i = 0; i < _readPatterns.length; i++) {
        expect(_readPatterns[i].hasMatch(ownShapes[i]), isTrue,
            reason: 'read pattern #$i (${_readPatterns[i].pattern}) does not '
                'match its own known-bad shape `${ownShapes[i]}`');
      }
      // A WRITE-shaped line is not a READ and must not trip THIS detector (the
      // dropped-columns scan owns writes) — keeps the two rules' scopes distinct.
      const knownGood = '.update({ subscription_status: "pro" })';
      expect(
        _readPatterns.any((p) => p.hasMatch(knownGood)),
        isFalse,
        reason: 'the read detector must stay read-shaped; writes belong to '
            'subscription_columns_dropped_test.dart.',
      );
    });
  });
}
