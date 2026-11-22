---
branch: start-prefill-fixes
review_rounds: 2
ground_truth_verified: true
verdict: converged
blast_radius: account
reviewed_at: 2026-11-21T20:30:00+05:30
closure_ledger: docs/audit/start-prefill-fixes.closure.yaml
---

# Plan review — `start-prefill-fixes`

Home calendar day sheet START, exact-name prefill, reps ceiling, TRY line. Tier M,
measured blast radius `account`. Two independent context-blind Sonnet rounds; round 2
ran on the post-round-1 state. The B-pass (`/code-review`) is self-triggered at the
merge step (CLAUDE.md §4.3), not yet run: no commit or merge has been asked for.

## Rounds

| Round | Against | Verdict | Findings |
|---|---|---|---|
| 1 | the uncommitted draft (plan + diff) | converged | 4 (0 P0/P1, 1 P2, 3 P3); C1-C8 all CONFIRMED |
| 2 | the post-round-1 diff | converged | 2 (0 P0/P1/P2, 2 P3); round-1 remediation CONFIRMED |

Both rounds ran the new tests plus the neighbouring prefill, Home START and resume-guard
tests green (round 2: +297, 0 failures).

## Dispositions

- R1 P2 exact-name trade-off: accepted and written into the diagnose-doc (the writer's
  identity is `exerciseNameKey`).
- R1 P3 TRY line printed the raw last reps: verified by the coordinator, FIXED
  (`triedRepsText`, 3 call sites, card test, mutation M7).
- R1 P3 inventory reach (the copy constant `trainStartWorkoutCta`): FIXED (regex widened,
  constant pinned unused).
- R1 P3 sheet enabled by opened date vs today's row at tap: accepted, documented.
- R2 P3 closure ledger omitted the TRY-line fix: FIXED (entry O2d).
- R2 P3 the Home wiring is pinned by a source count, not a mounted Home screen: accepted;
  the sheet-level tests are behavioral and the count pins the shared method.

## Why converged

Severity fell to zero P0/P1 in both rounds and round 2 found only documentation and
coverage-reach items, none changing behaviour. All findings are terminal in the closure
ledger; ground truth (file:line, git history of the sheet button, the only two callers of
`logsForExercise`, the part-file import chain) was verified by the reviewers and, for the
TRY line, by the coordinator.
