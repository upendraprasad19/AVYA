// Bug t1m5b0 regression test (APK Test #16.2).
//
// Pins the contract that supabase/functions/_shared/tools/progress/
// getProgressSummary.ts dispatches its 5 read-only SELECTs via
// Promise.all rather than sequential awaits.
//
// Pre-fix each was awaited sequentially; at typical 200-1200 ms per
// Supabase round-trip on ap-southeast-1, the 5 awaits accumulated to
// 3-5 s wall clock, brushing the 3500 ms tool-loop budget and
// returning tool_timeout. None of the queries depend on each other's
// results, so parallel dispatch collapses wall clock to the slowest
// single query (~1-1.5 s).
//
// Source-grep contract — Edge Functions run on Deno; we can't easily
// unit-test them from Dart. The grep pins the structural shape that
// the perf fix depends on.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('t1m5b0 — getProgressSummary handler uses Promise.all over its 5 SELECTs',
      () {
    final src = File(
            'supabase/functions/_shared/tools/progress/getProgressSummary.ts')
        .readAsStringSync();

    // Strip block + line comments so the explanatory comment doesn't
    // shadow the assertion if a future reorder leaves the comment but
    // removes the actual Promise.all.
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(
      stripped.contains('await Promise.all('),
      isTrue,
      reason:
          'getProgressSummary must dispatch its 5 read-only SELECTs via '
          'Promise.all. Sequential awaits accumulate past the wall-clock '
          'budget and return tool_timeout, which Gemini paraphrases as '
          '"the system timed out gathering your phase summary."',
    );

    // Count occurrences of `.from("` inside the parallelized block —
    // there must be at least 5 (one per SELECT). Crude but catches any
    // accidental removal of a query during a future refactor.
    final fromMatches =
        RegExp(r'\.from\(\s*"\w+"').allMatches(stripped).length;
    expect(fromMatches, greaterThanOrEqualTo(5),
        reason:
            'Expected at least 5 sb.from("...") calls in the handler (one per '
            'SELECT). Found $fromMatches — has a query been removed?');
  });

  test('t1m5b0 — getProgressSummary maxLatencyMs raised to 6000', () {
    final src = File(
            'supabase/functions/_shared/tools/progress/getProgressSummary.ts')
        .readAsStringSync();

    expect(
      src.contains(RegExp(r'maxLatencyMs:\s*6000\b')),
      isTrue,
      reason:
          'Tool registration must set maxLatencyMs to 6000 ms. Lower budgets '
          'cut into cold-Postgres-cache recovery time even with Promise.all.',
    );
    expect(
      src.contains(RegExp(r'maxLatencyMs:\s*3500\b')),
      isFalse,
      reason:
          'Pre-fix budget of 3500 ms must not be re-introduced; it triggers '
          'tool_timeout on cold-cache rebuilds.',
    );
  });
}
