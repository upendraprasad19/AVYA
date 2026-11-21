---
reviewed_at: 2026-11-18T18:40:00+05:30
staged_against: df5bea73 (branch oi191-goal-target, committed three-dot diff against origin/main)
blast_radius: account
reviewer: claude-sonnet-via-skill (2 fresh seats: A coach door and shared patch, B Edit Profile, rule and readers)
lens_set: [writer_reader_drift, unawaited_no_error_sink, guard_without_its_mirror, asserted_fixture_value]
findings_count: 13
verdict: accepted
---

# Code Review — OI-191 target weight and calorie targets follow the goal (df5bea73)

Thirteen findings (no P0 / P1; six P2, seven P3), every one closed in the follow-up commit of the same branch. The full
table with dispositions and the mutation results is in `docs/diagnoses/2026-11-18-goal-target-weight-agreement-b5d2e8.md`
("B-pass round 1"). In short:

- Seat A: every-outcome invalidation unobservable on the success path (P2, fixed with a failure-path test and a helper
  test); PRO prediction branches and the `goalChanged || targetSeeded` gate untested (P2, fixed with a seam and tests in
  both halves); `markStale` / invalidate error sinks (P3, fixed); a throw inside the lock-time build on corrupt data
  (P3, fixed); the coach result did not carry the new writes (P3, fixed); the preview was kg-only (P3, fixed); the
  recompute kill switch does not govern the new writer (P3, stated).
- Seat B: the refusal popup in kilograms for an imperial user (P2, fixed); the daily weigh-in breaking the pair for a
  Cut user who reached the goal (P2, stated consequence plus test); mirror-case test gaps (P2, eleven widget tests
  added); dropdown re-select, the new lower range bound on an untouched target (P3, fixed); half-tenth rounding (P3,
  stated).

## Founder triage notes

Accepted by the author under the standing rule (no deferrals): all thirteen are fixed or stated with a test; `false_alarm`
count 0.

## Tuning entry
- **2026-11-18** - blast-radius account - 13 findings; 0 false_alarm; tuning: lens 8 gained the redundant-path sub-check (a guard that claims "on every outcome" needs a test on the branch where the older tail does NOT run, and a mutation of its argument, not its text); the seat briefs quoted the founder decisions and the accepted residue and no seat re-litigated either.
