---
branch: ai-coach-ux-tool-integrity
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/2026-09-18-ai-coach-ux-tool-integrity-bpass.md
blast_radius: platform
open_issues: none-affected
date: 2026-09-18
---

# Plan review — `ai-coach-ux-tool-integrity`

Spec: `docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md`
(origin: founder APK test2 observations — AI-coach verbosity, tool UX,
tool-interference audit). Plan:
`docs/superpowers/plans/2026-09-18-ai-coach-ux-tool-integrity.md`.

Platform tier: touches `supabase/functions/` (captain_manual.ts + rank_engine.ts),
streak/rank math, and the coach write paths.

Two independent context-blind review rounds ran (general subagents, fresh
context each), plus a third-pass B-pass. Both rounds returned material
findings that changed the diff. All 22 findings across the three passes were
fixed in-branch (commits `ebfdfb37`, `f2f1854a`, `ac83530b`, `fc7f729a`);
none deferred; the accepted deviations are documented in
`docs/diagnoses/2026-09-18-reschedule-terminal-rows-e8f4a3.md`.

## Round 1 — 10 findings (2 High, 3 Medium, 5 Low)

Found the two writer/reader seams the batch's own comments claimed were
closed but were not:

1. **HIGH** `moveExerciseLogs` never maintained `exercise_log_index_<date>`
   — moved logs were invisible to the INDEX-FIRST canonical read on any
   destination date that already had logs (the batch's own test fixture
   could not see this because it seeded rows without index entries — a
   state `logExercise` never produces).
2. **HIGH** the restore merge (`_restoreScheduledWorkouts`) had no
   terminal-row arm — a stale cloud `planned` row resurrected the moved day
   on the next restore, re-creating the exact harm C2's comment claimed was
   fixed.
3-10. Destination-collision merge semantics, `workout_log_id` re-stamp,
   CoachSwapSheet status guard, terminal destination refusal,
   `completion_prompt` resolution on move/drop, scheduleForm TOMORROW
   mislabel, silent numeric coercion in the log sheet, a pre-existing
   `DateTime.parse` local-midnight trap in the same function.

All fixed in `ebfdfb37` with behavioral tests + per-fix mutations.

## Round 2 — verified all 10 fixes real, found 2 new (introduced by the fixes)

1. **MED** the collision merge's recompute silently SHRANK restore-shaped
   rows (top-level aggregates, no `sets[]` — the documented d4e7c2 asymmetry)
   colliding with a moved row. Fixed `f2f1854a`: per-side contribution
   (sets-derived when `sets[]` present, own aggregates otherwise) —
   preserve-don't-shrink.
2. **LOW-MED** the swap sheet's round-1 guard blocked PAUSED days,
   contradicting the dispatcher's own paused-is-swappable contract. Fixed
   `f2f1854a` (+ `ac83530b` for the log sheet's mirrored guard).

The round-2 → round-1-fix chain is itself the §4.12 warning made concrete:
the corrections (a guard, a recompute) introduced two new defects that only
a review OF THE FIXES caught.

## B-pass — accepted-with-findings (9: 1×P1, 2×P2, 4×P3, 2×P4)

The P1 was a genuine cross-seam divergence BOTH plan rounds missed: the
SERVER-side `rank_engine.ts` completion-rate (evaluate-rank-promotions cron)
still counted terminal rows against the promotion gate while the client
excluded them — permanent rank-gate deflation after any reschedule. Fixed
`fc7f729a` with client-parity status skipping + Deno tests. P2s: pauseRange
clobbering terminal rows; a false OI-174 citation. P3s: IST-date off-by-one
on non-IST hosts (pure UTC-midnight parse extracted + pinned), planner
dead-end on terminal destinations, missing double-tap latch on both capture
sheets. All fixed in `fc7f729a`; P3 is_pr rescan and P4 items documented as
accepted deviations (display-only readers / degenerate fallbacks) in the
e8f4a3 diagnose doc's B-pass section.

## Convergence

Round 2 verified every round-1 fix real and mutation-backed; the B-pass
verified the merge/restore/index seams across BOTH client and server. Final
state: all review findings resolved or explicitly documented as accepted
deviations with named readers. Verdict: converged.
