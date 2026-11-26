---
reviewed_at: 2026-11-16T22:30:00+05:30
staged_against: fa793157433ecaca0c08e2438a4b1bc592e14425
branch: generator-step3d-a
blast_radius: platform
reviewer: claude-sonnet-via-skill (1 fresh seat)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 2 P2 and 3 P3; all 5 fixed in the B-pass commit, none a false alarm
---

# B-pass: generator-step3d-a (Unit 3D-a, the server's hold-week copy, FOB-4 / OI-175)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head fa793157, with CI green on that SHA
(PR #289). One fresh Sonnet seat read the three-dot diff `origin/main...fa793157`: `_shared/hold_week.ts` and its
tests, `weekly-recap-ready`, `weekly-report`, and the docs. The brief quoted the recorded decisions and the rejected
alternatives: fail closed, the phase gate kept, the recap reads the week while the report reads today, no Peak or
Deload claim, no cloud column, a read that never throws, and deploys only on the founder's go. No finding re-opened
a decision.

The seat ran eight mutants. Five were red. Three were green and became Findings 1 and 2. Every fix below was mutated
after it landed; all six mutants went red and each file was restored from a backup (diagnose `c4e8b1`, B-pass
section).

## Finding 1 - P2 - guard_without_its_mirror - the recap's window order was unpinned
- **file:line:** `supabase/functions/weekly-recap-ready/index.ts` (the fulfilled branch's `fetchHoldOrdinals` call)
- **claim:** the source pin checked that `weekMonday,` and `weekSunday,` both appear, not their order. A swapped call
  (`gte` Sunday, `lte` Monday) matches nothing, and every holder silently reads "Week 4" with `hold_read_failed`
  false. 28/28 tests stayed green.
- **verification:** the seat swapped the two argument lines and confirmed the change with `diff`; 28 passed.
- **fix:** the batch step is one helper, `recapHoldsForBatch(supabase, progressRows, week)` in `_shared/hold_week.ts`,
  tested end to end. The stub client now applies the recorded `gte` / `lte` window to dated rows, so a swapped window
  returns nothing. The call site passes the `istWeekBounds` object whole, so there are no two strings left to swap.
  The source pin names the one call.
- **status:** accepted, fixed (mutant "helper window swapped" red, 1 of 32).

## Finding 2 - P2 - guard_without_its_mirror - the map hand-off to the texts was unpinned
- **file:line:** `weekly-recap-ready/index.ts` (`holdMap = holds.map;`), `weekly-report/index.ts`
  (`todayHold.map.get(targetUserId) ?? null`)
- **claim:** `holdMap = new Map()` in the recap, or `null` in place of the report's lookup, leaves the feature dead
  with every test green.
- **verification:** both mutants applied (one changed line each) and ran 28/28 green.
- **fix:** the report's whole path (phase gate, one-day read, lookup, builder) is one helper, `reportWeekLineFor`,
  tested end to end for a holder, phase 2, no progress row, a failed read and a day with no hold row. The call site
  `const weekLine = await reportWeekLineFor(...)` is pinned. The recap's `holdMap = holds.map;` is pinned inside the
  fulfilled branch, and the helper test builds the holder's text from the helper's own map.
- **status:** accepted, fixed. The mutants "recap map dropped", "report hold dropped (helper)" and "report call site
  bypassed" each went red, 1 of 32.

## Finding 3 - P3 - function_exception_swallow - a failed hold read was invisible to cron_call_log
- **file:line:** `weekly-recap-ready/index.ts`, `logCronEnd(logId, "success", ...)`
- **claim:** `hold_read_failed` reached only the HTTP body (read by no one) and the console line. A persistent
  failure, such as a renamed column, would page nobody.
- **verification:** `logCronEnd`'s options are only `httpStatus`, `requestId` and `errorSummary`
  (`_shared/cron_telemetry.ts:75-79`).
- **fix:** the run is still logged as `success` (the push went out), now with `errorSummary: "hold_read_failed"`
  whenever a hold read failed. A source pin covers it.
- **status:** accepted, fixed (mutant "cron summary dropped" red).

## Finding 4 - P3 - guard_without_its_mirror - no year-end bounds test, no exactly-100-ids test
- **claim:** month end was covered, year end was not, and the 100-id chunk boundary was tested only at 150.
- **fix:** `istWeekBounds` year end (Thursday 2026-12-31 at 11:30 IST and Friday 2027-01-01 at 00:30 IST both give
  2026-12-28..2027-01-03), and exactly 100 ids give one chunk. Both pass.
- **status:** accepted, fixed.

## Finding 5 - P3 - doc consistency - the record said `bpass: pending`
- **fix:** this file, and `docs/plan-reviews/generator-step3d-a.md` set to `bpass: accepted`.
- **status:** accepted, fixed.

## Lenses checked clean (the seat's evidence, re-checked where it named a number)
- **writer_reader_drift.** The only `week_number` writer is the schedule push (`sync_workout.dart:2350`). The registry
  ranges matched the files; they were re-derived after the fixes, and parity passes.
- **blast_radius_mismatch.** `supabase/functions/**` is platform in `docs/blast_radius.yaml`, as is the record.
- **secrets_in_tree, unawaited_no_error_sink.** Clean: both reads are awaited, and nothing new floats.
- **missing_input.** `scheduled_workouts (id, user_id, scheduled_date, week_number)` and
  `user_progress.current_phase` are in `backups/live_schema_columns.json` (migrations 001 / 002).
- **asserted_fixture_value.** 2026-11-15 is a Sunday; 14:30Z is 20:00 IST Sunday and 18:40Z is 00:10 IST Monday;
  2026-12-02 is a Wednesday. All literals match.

## Founder triage notes
Self-triaged under the standing directive ("Let's complete everything"). Every finding was fixed in this batch.

## Tuning entry

- **2026-11-16** - blast-radius platform - 5 findings (0 P0/P1, 2 P2, 3 P3); 0 false_alarm; tuning: one lesson.
  - A source pin on a call's ARGUMENTS that checks presence and not order (two strings that each appear) cannot see
    a swapped date window. Where the arguments carry an order or a hand-off, move the step into a helper the
    behavioural test calls end to end, and give the stub client the filters it records (a stub that records `gte` /
    `lte` but ignores them cannot fail on a swapped window). Lens 6 now asks reviewers to swap every pair of
    same-typed arguments at a pinned call site.
