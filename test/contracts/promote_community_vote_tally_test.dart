// test/contracts/promote_community_vote_tally_test.dart
//
// Contract for OI-82 — `promote-community-item` called a Postgres RPC that has
// never existed, and the error was swallowed by a guard that could not fire.
//
// WHAT WAS WRONG
// --------------
// Both promotion paths began with:
//
//     const { data: candidates, error: countErr } =
//       await admin.rpc("community_votes_summary", { p_item_type: ... });
//     const list = candidates ?? (await fallbackCount(admin, ...));
//     if (countErr && !list) console.warn(...);
//
// `community_votes_summary` is absent from `pg_proc` in EVERY schema on
// `dedsavbjuwgarrhphgnl` (verified live 2026-08-01, confirmed twice). PostgREST
// reports a missing function as an `error` object rather than throwing, so
// `candidates` was always `null` and the `??` fell through to the tally on every
// tick. The "primary" path never executed in production.
//
// The guard could never report it either: `fallbackCount` returns `[]` on
// failure, and `![]` is `false` in JS, so `countErr && !list` was unreachable
// even when `countErr` was set. A dead guard around a dead call reads as error
// handling, which is why this survived a paging audit that explicitly waived
// these two reads.
//
// No migration in the repo ever defined the function (the only textual mention
// is a prose comment in `101_admin_dashboard_metrics_functions.sql`, which cites
// it as an example of an existing public function — it is not one). So there was
// no unapplied migration to restore; the call was speculative code whose helper
// was never written.
//
// SOURCE-GREP by necessity: this is Deno Edge Function code with no Dart
// runtime, matching the existing EF contract tests. It pins the three things a
// grep genuinely can — the RPC name is gone, the dead guard shape is gone, and
// both paths call the tally directly.
//
// Run: flutter test test/contracts/promote_community_vote_tally_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fn = 'supabase/functions/promote-community-item/index.ts';

/// Strips `/* … */` blocks and `//` line comments.
///
/// The assertions below are about LIVE CODE. The function's own doc comment
/// deliberately records the deleted `.rpc("community_votes_summary")` call and
/// the dead `countErr` guard as the historical reason it exists, so asserting
/// over the raw file would fail on its own explanation — and "delete the
/// explanation to make the test pass" is the wrong direction.
/// The line-comment pass is string-literal aware. A naive `indexOf('//')`
/// also matches inside `"https://…"`, which this very file's target contains
/// three times (two import specifiers and the OneSignal fetch URL) — it would
/// silently truncate those lines mid-statement. Harmless against today's
/// assertions, but it makes the stripper lie about what the code says, so any
/// future assertion added near a URL line would misbehave for a reason nobody
/// would look for. B-pass finding 3.
String _codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map(_stripLineComment)
    .join('\n');

String _stripLineComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == r'\') {
        i++; // skip the escaped char
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == '"' || c == "'" || c == '`') {
      quote = c;
      continue;
    }
    if (c == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

void main() {
  late String src;
  late String code;

  setUpAll(() {
    final f = File(_fn);
    expect(f.existsSync(), isTrue, reason: '$_fn must exist');
    src = f.readAsStringSync();
    code = _codeOnly(src);
  });

  group('OI-82 — the vote tally is the only path, and it is called directly',
      () {
    test('no live .rpc() call to the nonexistent community_votes_summary', () {
      expect(code, isNot(contains('community_votes_summary')),
          reason: 'the RPC is absent from pg_proc in every schema on this '
              'project, so any call to it errors on every tick');
      expect(code, isNot(contains('.rpc(')),
          reason: 'promote-community-item makes no RPC call at all any more');

      // The doc comment SHOULD still explain what was removed and why.
      expect(src, contains('community_votes_summary'),
          reason: 'the historical record must survive in the doc comment — a '
              'silent deletion loses why the primary path never ran');
    });

    test('the dead `countErr && !list` guard is gone', () {
      expect(code, isNot(contains('countErr')),
          reason: 'the guard `if (countErr && !list)` could never fire — the '
              'tally returns [] on failure and ![] is false — so it reported '
              'error handling that did not exist');
    });

    test('both promotion paths call the tally directly', () {
      expect(code, contains('await countApproveVotes(admin, "food")'));
      expect(code, contains('await countApproveVotes(admin, "exercise")'));

      // The old name implied a fallback relationship to a primary that never
      // ran. Nothing should reintroduce it.
      expect(code, isNot(contains('fallbackCount(')),
          reason: 'renamed to countApproveVotes — it is THE tally, not a '
              'fallback to anything');
    });

    test('the tally is still paged (OI-79 must not regress)', () {
      expect(code, contains('fetchAllPages<{ item_id: string }>'),
          reason: 'this reads one row per VOTE, not per item. An un-ranged read '
              'clips at 1000 and every derived count is silently too low, so '
              'items at threshold never get promoted — a wrong-result path, '
              'not merely an incomplete one (OI-79).');
      expect(code, contains('orderBy: "id"'),
          reason: 'a pagination loop without a stable sort key is its own bug');
    });

    test('no orphaned oi79-ok waiver is left behind', () {
      // The two waivers existed solely to excuse the deleted .rpc() reads.
      // check_unbounded_cron_reads.dart matches waivers by line proximity, so a
      // waiver whose target is gone can drift onto a neighbouring read and
      // silently bless it — a failure mode that gate's own comments name.
      // Checked against the RAW source: a waiver IS a comment.
      expect(src, isNot(contains('oi79-ok')),
          reason: 'no read in this file is waived any more; the tally is paged');
    });
  });
}
