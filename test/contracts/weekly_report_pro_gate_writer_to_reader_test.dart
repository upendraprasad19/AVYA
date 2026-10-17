// Contract test — weekly-report's first-free-report gate must FAIL CLOSED.
//
// SoT concept: weekly_report_pro_gate. Diagnose: e4d1b7 (2026-09-03).
// Tech-debt audit 2026-09-02, Slice A, finding CODE-8.
//
// WRITER  supabase/functions/weekly-report/index.ts — report-log insert
// READER  supabase/functions/weekly-report/index.ts — first-free-report gate
//
// Pre-fix the reader was `const { count: previousReportCount } = await
// supabase…` with no `error`. On any transient PostgREST failure `count` is
// null, `(null ?? 0) === 0` made `isFirstReport` TRUE, the
// `!hasPro && !isFirstReport` gate did not fire, and a FREE user received an
// unbounded Gemini 2.5 **Pro** report — the most expensive call in the app.
// The sibling subscription query 11 lines above already destructured its error
// (`subError`): same function, mirror not applied.
//
// The WRITER half matters just as much: that insert is the SOLE writer for the
// count. supabase-js RESOLVES (never rejects) on a PostgREST error, so a
// discarded result means a silent failure keeps the count at 0 forever and the
// gate stays permanently open. Fixing the reader alone would have left it live.
//
// related_bugs: c8f229 (verify-payment ownership check fail-open when a field
// was absent — same shape), 9d12af (gating decision going wrong with no log).
//
// SCOPE — honest (CLAUDE.md rule 21): these are SOURCE-GREP assertions and
// prove PRESENCE, not runtime behaviour. A behavioral Deno test is NOT
// reachable — the function is `serve(async (req) => {…})` with no exports and
// there is no Deno on the dev machine. CI's `deno check` is the compile proof;
// the SoT entry is marked `presence_only:` for exactly this reason.

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/weekly-report/index.ts';

/// Strips `//` and `/* */` so an assertion can never be satisfied by prose
/// that merely DESCRIBES the pattern — `feedback_source_grep_strip_comments_first.md`.
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  late String src;
  setUpAll(() => src = _stripComments(File(_path).readAsStringSync()));

  group('weekly_report_pro_gate writer → reader', () {
    test('READER: the previous-report count destructures its error', () {
      // ⚠ REPOINTED by OI-162 slice 3a, not loosened. The invariant is
      // unchanged — the read feeding `isFirstReport` must destructure `error`,
      // because a discarded error yields a falsy count, `(null ?? 0) === 0` is
      // true, and the gate hands a free user a Gemini 2.5 Pro report. Only the
      // read MOVED: `count:` over `ai_coach_interactions` became `data:` over
      // `usage_counters`, so the old shape can no longer match.
      expect(
        RegExp(r'data:\s*freeReportQuota\s*,\s*error:\s*\w+').hasMatch(src),
        isTrue,
        reason:
            'The ledger read feeding `isFirstReport` must destructure `error`. '
            'Without it a failed query is indistinguishable from an absent '
            'row, and the gate hands a free user a Gemini 2.5 Pro report.',
      );
    });

    test('READER: isFirstReport FAILS CLOSED when that read errored', () {
      // Pre-fix this was the bare `(previousReportCount ?? 0) === 0`.
      expect(
        RegExp(r'isFirstReport\s*=\s*previousReportError\s*\?\s*false')
            .hasMatch(src),
        isTrue,
        reason:
            'On a count error `isFirstReport` must be FALSE (deny). Denying a '
            'report is recoverable; an unbounded Gemini 2.5 Pro call is not.',
      );
    });

    test('WRITER: the report-log insert result is checked, not discarded', () {
      expect(
        RegExp(r'error:\s*reportLogError\s*\}\s*=\s*await\s+supabase')
            .hasMatch(src),
        isTrue,
        reason:
            'This insert is the ONLY writer for the count read above. '
            'supabase-js resolves rather than rejects on a PostgREST error, so '
            'a discarded result lets a silent failure hold the count at 0 '
            'forever and leave the free-report gate permanently open.',
      );
    });

    test('WRITER: still stamps the channel the READER counts', () {
      // Pins the writer→reader join itself. If either side's channel string
      // changed independently, the gate would silently count nothing — the
      // ⚠ REPOINTED by OI-162 slice 3a, and it came back STRONGER.
      //
      // It used to pin one pair: the writer stamps the channel the reader
      // counts. After the slice there are TWO writes with two distinct
      // purposes, and BOTH are required — which the single-pair assertion
      // structurally could not express:
      //
      //   1. the `ai_coach_interactions` insert  -> the PERSISTED report and
      //      the row a reinstall restores (sync_coach.dart restores every
      //      channel unfiltered). No longer feeds the gate at all.
      //   2. `consume_quota('weekly_report_free')` -> the QUOTA, on a ledger
      //      `rolling-context` cannot prune. This is what the reader reads.
      //
      // Deleting either one is a silent regression the old assertion would
      // have missed: dropping (1) loses the only copy of the report, dropping
      // (2) reopens the resettable-quota bug.
      expect(
        RegExp(r'channel:\s*"weekly_report"').hasMatch(src),
        isTrue,
        reason: 'the record writer must still stamp channel="weekly_report" — '
            'it is the only persisted copy and the restore source',
      );
      expect(
        RegExp('''['"]weekly_report_free['"]''').hasMatch(src),
        isTrue,
        reason: 'the quota writer must consume the SAME key the reader reads',
      );
      expect(
        RegExp(r'\.eq\(\s*"quota_key"\s*,\s*\w+\s*\)').hasMatch(src),
        isTrue,
        reason: 'the reader must filter on quota_key — the writer/reader pair '
            'is now keyed on the ledger, not on a channel string',
      );
    });
  });
}
