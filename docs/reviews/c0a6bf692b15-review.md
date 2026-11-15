---
reviewed_at: 2026-11-02T20:30:00+05:30
staged_against: c0a6bf692b15
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, inserted_lines_registry, test_passes_for_wrong_reason, kill_switch_off_equivalence, missing_input]
findings_count: 9
verdict: accepted
verdict_note: reviewed on the pre-fix staged diff (21 files, hash 9b6092b57d9b); no P0/P1; every P2/P3 and the 3 named test holes were handled in this batch, the fixes are in the diff this file is named for
---

# Code Review - c0a6bf692b15

The fresh Sonnet reviewer found no P0 or P1 (read-only; it could not run tests). Triage by the author.

## P2-1 / P2-2 - writer_reader_drift (inserted-lines sub-check)
- **file:** docs/sot_registry.yaml (grantFirstProFreezes idempotency reader; user_repository, streak_progress_service, day_rollover_service, workout_repository ranges)
- **claim:** one reader range was missed and ranges for the same files were only partly shifted; `_calculateStreak` and `completionRateOverWindow` entries pointed into other functions.
- **status:** accepted - fixed: every touched range recomputed from HEAD ranges through the diff hunks, `_calculateStreak` (420-597), `completionRateOverWindow` (635-683) and `reckonStreakDecayAndPersist` (335-356) re-anchored from symbol lines; parity gate PASS.

## P3-1 - diagnose consequence (h) understated the push count
- **status:** accepted - fixed: three un-coalesced pushes named in (h) and in `sync_methods:`.

## P3-2 - reckon #1 throws, reckon #2 succeeds
- **status:** accepted - documented as consequence (k): skipping the credit would reopen a lost-credit path.

## P3-3 - late rows from PlanIntegrityReconciler after the marker settles
- **status:** accepted - fixed: named in consequence (f).

## P3-5 - duplicated rules predicate
- **status:** accepted - fixed: one `StreakProgressService.settleThenCreditActive` getter read by `refillIfNewWeek` and `_calculateStreak`.

## P3-7 - brand-new account gets no credit on day one
- **status:** accepted - documented as consequence (j).

## P3-4 / P3-6 - newest-first spend (already consequence (c)); PENDING_STAMP and relative import
- **status:** false_alarm / no action - (c) already accepted; Gate 40 passes with the placeholder; the relative import matches the file's style.

## Test holes (1, 2, 3, 4)
- **status:** accepted - fixed: 3 PRO-cap tests (the cap mutant `isPro ? 1 : 1` reddened 3), a pure-read test across the cutoff, a marker-for-another-account deferral test (26 tests). Holes 5 and 6 (real-clock tests, istMondayKey zone) are pinned by the source-grep pin and documented in the diagnose.

## Tuning entry
- **2026-11-02** - blast-radius platform - 9 findings; 2 false_alarm/no action; tuning: none (the inserted-lines sub-check found the stale-range class again; the lens is working).
