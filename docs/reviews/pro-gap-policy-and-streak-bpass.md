---
reviewed_at: 2026-10-18T14:00:00+05:30
staged_against: pro-gap-policy-and-streak (staged tree, before the first commit)
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass), third independent reader after plan-review rounds 1 and 2
lens_set: [writer_reader_drift, guard_without_its_mirror, blast_radius_mismatch, unawaited_no_error_sink, missing_input, test_strength, performance]
findings_count: 7
verdict: accepted
---

# Code Review (B-pass) - pro-gap-policy-and-streak (Piece B, d7a3e5)

Seven findings; the author's triage:

1. **P1 (CONFIRMED) streak break hit free users with an expired plan.** A rowless yesterday broke the chain for anyone, including a free
   user whose plan simply ended (nothing writes rows after `plan_end`, `enable_hold_weeks` OFF) and a PRO user whose advance had not run
   yet. FIXED: the break applies only to a MID gap (a later schedule row exists); a trailing gap is skipped as before. Same bound added to
   the client and server completion rate. Tests: trailing gap keeps 7, mid gap with a future row breaks, trailing rate 1.0.
2. **P2 `plan_status` cost.** `getDaysSinceLastWorkout` deep-copied every box row on each snapshot. FIXED: `progress.last_workout_date`
   first, the scan only as a fallback (test reads the cheap field).
3. **P2 server rate vs sync lag.** Unpushed past rows read as blank on the server, deflating the rate (delays a promotion, never grants
   one). DOCUMENTED at the function and in the plan; no code change (a recency gate on `last_sync` would add a second source of truth).
4. **P3 server `present` completeness** depends on the 1000-row cap. DOCUMENTED in the function's warning comment.
5. **P3 client first-row parse.** FIXED: date-shaped keys only (`_scheduleRowBounds`).
6. **P3 test strength.** FIXED: the Deno fake returns the newest row when `ascending` is flipped; future-row and trailing-gap cases added.
7. **P3 `plan_status` floor.** FIXED: the blank-gap trigger uses the same 7-day floor as the freeze reset.

Lenses with no findings: freeze-reset-after-commit ordering, kill-switch default direction, IST/UTC arithmetic on the client, SoT YAML
shape, Edge Function typing and throw semantics.

## Founder triage notes
Pending. Not deployed: `evaluate-rank-promotions` (the server mirror) and the `plan_status` prompt rule each need the founder's go.
