---
reviewed_at: 2026-11-28T20:00:00+05:30
staged_against: ed00f2da6d8ad52e6b7a278afed8319d66d54f84
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
verdict_note: marked by the coordinating session after triage; the founder has not read this file, and the upload, the database apply and the merge each still need their go. 8 fixed, 1 parked on the board (OI-534)
---

# Code Review (B-pass) — library v30

PR https://github.com/upendraprasad19/AVYA/pull/363. One context-blind Sonnet seat on `origin/main...ed00f2da`, read-only
(the four builder `--check` commands, five named test files, `dart analyze`). CI on that head: every job passed except
the 4 tests that compare the library with the newest cloud seed migration, red until the reseed is applied.

**No P0 or P1.** The seat's own checks found: the cloud draft differs from migration 183 by exactly E027, E120 and two
inserts, with a rollback restoring both E027 columns; the re-recorded counts it recomputed match; no loosened
comparator or floor in the diffs it read; no secret-shaped literal; the four stills match the media table.

The fixes below were not given a second independent seat. They change two tests and documents, comments and one test
failure message; no app behaviour.

## Finding 1 — P2 — guard_without_its_mirror (history reader)
- **file:line:** lib/shared/repositories/plan_engine/exercise_selector.dart:431
- **claim:** a repeat phase drops a pinned exercise the user's equipment can no longer do, with no substitute; a basic_gym plan saved before v30 that holds T-Bar Row comes out one exercise short.
- **verification:** the coordinator read `buildPinnedDays.resolve` and confirmed it; the scenario was not run.
- **status:** accepted, filed as OI-534 and parked `upstream_blocked` until the store launch (existing saved plans are testing accounts only, CLAUDE.md 1). A fix is a plan-engine change, outside this library batch.

## Finding 2 — P2 — asserted_fixture_value
- **file:line:** test/plan_generator/same_movement_day_gate_test.dart:86
- **claim:** the new T-Bar pair had no recorded mutation and nothing showed any persona exercised it.
- **verification:** measured. The two rows sit on 8 and 64 persona days; with the link removed still no day holds both.
- **status:** accepted, fixed. The gate now types the pair and asserts each side appears; a pairing test on the real library was added to the v30 contract; both mutations are in diagnose c41a7e (link removed: 1 gate test on its pair-count pin, 2 contract tests; off the core list: the cross-day test). The diagnose states that the persona runs do not exercise the link.

## Finding 3 — P3 — writer_reader_drift
- **claim:** the link also soft-avoids and demotes the Landmine row after a T-Bar Row swap or a previous phase.
- **status:** accepted, written into diagnose c41a7e. The same-day rule is the founder's decision and stays.

## Finding 4 — P3 — asserted_fixture_value
- **claim:** the switch-off recordings still claimed equality with older trees.
- **status:** accepted, fixed: test names, comments, the three fixtures' notes, the day-floor failure message and the plan-engine guide now say they are self-recorded since v30 (equality last proven at seed 29).

## Finding 5 — P3 — docs count
- **claim:** `plate_flags.dart` said 107 old rows have both an animation and a drawing.
- **verification:** counted from the library: 108.
- **status:** accepted, fixed.

## Finding 6 — P3 — writer_reader_drift (inserted lines)
- **claim:** two `docs/sot_registry.yaml` line ranges were not shifted.
- **status:** accepted, fixed (331-381, 199-220); `check_sot_registry_parity.dart` passes.

## Finding 7 — P3 — docs
- **claim:** stale "9 remain" held pairs (7), "79 held rows" (75), "four rows" (five) in the diagnose, and an attribution sentence scoped to HEAD after main was merged in.
- **status:** accepted, all four fixed.

## Finding 8 — P3 — process
- **claim:** the closure ledger and plan-review record were absent.
- **status:** accepted, both written with this review.

## Finding 9 — P3 — blast_radius_mismatch (rollback)
- **claim:** reverting the app to seed 29 would not reseed a box already at 30.
- **status:** accepted, the plan now says a rollback is forward-only (seed 31 retiring the two new ids).

## Not verified by the seat
The four animated files (they live in the primary checkout), any live cloud state, the 4 expected red tests, the
injury builder's `--check`, and gate counters outside the tests it ran (it relied on CI for those).

## Tuning entry
- **2026-11-28** - blast-radius platform - 9 findings; 0 false_alarm; tuning: none.
