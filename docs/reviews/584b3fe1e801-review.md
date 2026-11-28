---
reviewed_at: 2026-11-22T10:40:00+05:30
staged_against: 584b3fe1e801
reviewed_sha: b3847820
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: pending
verdict_note: F1 (weight half of a stray row) waits on the founder's scope call; ledger entry B1.
---

# Code Review — 584b3fe1e801 (branch start-prefill-fixes, head b3847820)

Fresh Sonnet reviewer, context-blind, read-only; ran 53 tests green (the four new files plus
`phase_c_oi_closures_test` and `last_performance_per_set_contract_test`). No P0 or P1.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** `exercise_card.dart:289-299`, `exercise_last_try_lines.dart:98-106`
- **claim:** the 2x ceiling guards the reps of a stray last row; its weight is still prefilled and feeds TRY.
- **status:** blocked_on_user (founder approved a reps rule only; ledger B1; residual written in the diagnose-doc)

## Finding 2 — P3 — guard_without_its_mirror
- **file:line:** `day_detail_sheet.dart:485-495`, `home_screen.dart:946-950`
- **claim:** START enabled but `workoutDayForDate` can return null, so the tap closed the sheet and did nothing.
- **status:** accepted, fixed (host passes a null `onStart` when no day resolves; source pin; mutation: 1 red). Unawaited `onStart` future has no sink: same as the Today card before, not worse.

## Finding 3 — P3 — test teeth
- **file:line:** `day_detail_sheet_start_behavioral_test.dart:55-66`
- **claim:** the test name said the sheet closes THEN calls onStart; it asserts neither order.
- **status:** accepted, fixed (renamed to what it asserts; the host context is used, so order is not load-bearing).

## Finding 4 — P3 — writer_reader_drift
- **file:line:** `docs/sot_registry.yaml` four `exercise_card.dart` ranges
- **claim:** not shifted for the +2 lines at 292.
- **status:** accepted, fixed (+2 on 683-711, 744-778, 810-841, 1029-1318; parity gate passes).

## Finding 5 — P3 — blast_radius_mismatch
- **claim:** diagnose-doc said `feature`, the plan-review record says `account`.
- **status:** accepted, fixed (`account`).

## Finding 6 — P3 — guard_without_its_mirror
- **claim:** `planTopReps` gives no ceiling for `8-12 reps`, `10-12/side`, an en dash, `30s`.
- **status:** accepted as documented; no ceiling is the pre-change behavior, so never worse.

## Lens results
Writer/reader: one non-test caller of the new parameter, both pass `exactNameOnly: true`; every
`lastPerformanceProvider` reader sees exact-name history; `expandable_day_card` shows the raw real last
reps (consistent with LAST). Secrets: clean. Missing input: all paths exist. Fixture values recomputed
(`TRY: 112.5KG × 8`, boundary table 16/17, 24/25) and correct.

## Founder triage notes
Pending: F1.

## Tuning entry
- **2026-11-22** - blast-radius account - 6 findings; 0 false_alarm; tuning: none (one P2 was a scope question, five were small and fixed).
