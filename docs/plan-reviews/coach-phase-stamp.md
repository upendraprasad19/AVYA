---
branch: coach-phase-stamp
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-phase-stamp-review.md
---

# Plan review — coach plan-generation phase demotion + phase row-stamp (item ② + COACH-1)

Smallest converged piece of Batch 1 (workout-generator adaptive overhaul), shipped
first per §4.12. Fixes two coupled coach defects with a shared root (the planners
never read the user's real `current_phase`): item ② (regen/switchGoal demoted
advanced users to Foundation) + COACH-1 (three coach schedule-row writers omitted the
`phase` key the main scheduler stamps).

## Review rounds (≥2, on the design + the ground truth)
- **Round A — Round-4 AI-coach integration audit** (workout-generator overhaul,
  `~/.claude/plans/ok-lock-1a-and-atomic-balloon.md`): a context-blind reviewer
  identified COACH-1 (coach-regen rows unstamped) and confirmed item ②'s fix approach
  (thread `current_phase`), verifying the 3 missing writers against code.
- **Round B — dedicated context-blind B-pass on the implemented diff**
  (`docs/reviews/coach-phase-stamp-review.md`): verified end-to-end persistence,
  switchGoal coverage, `_restEntry` threading, `as int?` safety (live schema), hotel
  decoupling, test non-vacuity, and completeness (no other coach schedule-writer gap).
  Verdict ACCEPTED.

## Ground-truth verification (true)
Self-verified against live code + live schema: the 3 unstamped writers
(regenerate_plan_planner.dart workout + `_restEntry` rows, hotel_workout_planner.dart);
`current_phase` always written as int (reconciler/graduation/onboarding) + read via
`as int?` by ~15 existing readers; `user_progress.current_phase` is `int4` (no cloud
`phase` column on `scheduled_workouts`); the `{...entry}` spread at
`workout_write_service.dart:549` persists the stamp to the real Hive sink.

## Verdict: converged
Behavioral regression test green (`test/contracts/coach_regen_phase_stamp_behavioral_test.dart`),
diagnose-doc `9c3e7a` validated, B-pass accepted, analyze clean. No open issues.
