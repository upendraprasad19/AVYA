---
reviewed_at: 2026-10-07T11:00:00+00:00
staged_against: coach-history-correctness-tools at commit 9e8b6d09 (L1b server readers and coach tools), before the merge to main
blast_radius: platform
reviewer: 2 fresh context-blind Sonnet reviewers (read-only, exhaustive command allow-list: no scripts, no database statements)
lens_set: [writer_reader_drift, guard_without_its_mirror, missing_input, asserted_fixture_value, blast_radius_mismatch]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — L1b coach history tools and server readers (`coach-history-correctness-tools`)

Plan `docs/plans/coach-history-correctness-tools.md` (v12); diagnose-docs a1c7e3, b2d8f4, c3e9a5, d4fab6, e5abc7, f6bcd8, a7cde9, b8def0, c9ef01.

**Provenance of this file (read first).** The B-pass ran on 2026-10-07 and its outcome was recorded in the `## B-pass` section of `docs/plan-reviews/coach-history-correctness-tools.md` (commit 259c4339). This review FILE was not written at the time, so the merge-to-main gate `check_plan_review_record_exists` failed on `60724824` (a `bpass: accepted` record with no `bpass_review:` file). This file is written afterwards from that recorded outcome and from commit 9e8b6d09; the reviewers' full per-finding wording was not kept and is not reconstructed here. Nothing below is stronger than what the record states.

**Outcome:** no P0 or P1. Six items were fixed in the same commit; none was dismissed.

## Findings (as recorded, all fixed in 9e8b6d09)

1. **Cross-tick double announce in pr-detection.** A winner could be announced by two hourly ticks. Fixed: winners are announced only by the tick holding their own `completed_at` (keyed context read). Pin: `pr-detection/window_test.ts`.
2. **`to` unbounded in `getPRTimeline`.** Fixed: defaults to IST today.
3. **`truncated` dropped.** `getProgressSummary` and `getNutritionHistory` now surface it; `getPromotionStatus` throws instead of shortening a streak.
4. **Exercise key case-sensitive.** The dedupe key is now case-insensitive (`_shared/live_exercise_rows.ts`).
5. **Stale comments and doc wording.** Corrected.
6. **Mutation driver not committed.** `docs/audit/coach-history-correctness-tools.mutants.py` committed (50 of 50 mutants red).

## Checks recorded with the pass

- Live read-only: 226 of 226 `workout_log_exercises.workout_log_id` values are v5-versioned, 0 null.
- `_shared/ist_date.ts` and `_shared/paged_fetch.ts`: unchanged (byte-identical, `git diff --stat`).
- Scoped-WARN gate baseline at that commit: 0 WARN lines (the gate was later flipped to a hard failure in 346a82de).
