---
branch: session-set-budget
date: 2026-10-25
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/session-set-budget-bpass.md
---

# Plan-review record - session set budget (Batch B2, ship-dark, platform)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED:** `git diff origin/main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -` printed
`Blast-radius: platform` for the 46 files of the branch (the plan engine under `lib/shared/repositories/plan_engine/` sets it).
The pre-commit NOTE on the batch's commits agreed independently.

## What this branch is

Plan: `docs/plans/2026-10-22-session-set-budget.md` (r6, rulings 1 to 14), executed inline on this branch. Founder decisions
F1 to F5 (2026-10-22): rule 14 waived for the `generateV4` wiring only; an empty `session_duration_minutes` means 60; a focus
muscle may reach about 25 weekly sets; user-added exercises are never trimmed or counted while library repeat pins are
budgeted; the focus session cap is 12.

Under the flag `enable_session_set_budget` (default OFF, `PlanEngineFlags.sessionSetBudgetEnabled`) a generated day is sized by
the user's minutes: `SessionSetAllocator.allocate` sets each budgeted exercise's sets from a time model, a weekly band and a
session cap per muscle group; `PeriodizationEngine.apply`, `VolumeTitration.applyToWeeks` and `WarmupCooldownSelector.attach`
take the same `SessionBudgetContext`; Train, Home and the coach's `shortenDay` show the same minutes through
`budgetedDaySeconds`. OFF is byte-identical (`test/plan_generator/generator_golden_test.dart`, 998 personas, and
`test/contracts/session_set_budget_wiring_test.dart`).

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Context-blind plan review, every claim verified against code | `not_converged`, 7 P1. |
| 2 | Fresh reviewers on the POST-round-1 plan (r2) | `not_converged`: 2 P1 in the allocator's admission rule, 13 P2, 12 mechanical. r3 replaced admission with a priority-rank rule and replayed it before dispatch. |
| 3 | Fresh reviewers on r3 | `not_converged`: 1 P1 (the lead-lift count cannot pass when weekly tops bind), 8 P2, 8 mechanical. r4 added a rank-0 reservation. |
| 4 | Fresh reviewers on r4 | `converged`: 0 P0, 0 P1, 6 P2, 8 mechanical. r5 applied every P2 and mechanical item. r6 is a rebase onto the thin-day top-up (Ruling 14) and nothing else. |
| B-pass | Three fresh read-only adversarial reviewers on the diff (`docs/reviews/session-set-budget-bpass.md`) | 36 findings (7 P2, 29 P3), 0 false alarms, each verified by the author, fixed or recorded with a terminal state; verdict `accepted`. The material ones: the display priced cardio and timed rows as one 40 s set (a day understated by 20 to 40 minutes), the coach's `shortenDay` used a third estimator, and the gate could pass on stale allocator stats. |

Rounds 1 to 3 each returned material findings (section 4.12.1 reads that as a sign the unit may be too large); round 4 returned
none (0 P0, 0 P1), so the unit converged at four rounds without a split.

## Rulings made during execution

Settled in the plan before execution: Rulings 1 to 14. Added while executing, each with a test that fails without it:

- **Task 7:** the time hard zero exempts only the day's forced lead lift (the empty-day guard put it on although library
  timed and distance rows had spent the budget). Seven days of 33,204 run over minutes + 2, worst 5.5 minutes.
- **B-pass R1 P2-2:** the lead-lift policy: protected from the week and from an empty day, not from the clock.
- **B-pass R3 P2-1:** a cardio, distance or timed row whose `reps` names minutes works that long per set in the time model.
- **Merge with `origin/main` (payment-hardening, #165):** the conflicted merge could not pass `check_code_review_pass_exists.dart`
  (no `MERGE_HEAD` stand-down; class 6 of `feedback_gates_unsatisfiable_at_merge`), so it was made with `-X theirs` for the
  four shared files and the B2 side restored in the next commit; the final tree equals the hand-resolved tree.

## Verification state at the time of this record

- Mutation proof: 44 mutants this round (35 killed first time, 1 compile error re-run and killed, 8 survivors: 7 pinned by new
  tests and re-run killed, 1 equivalence removed). Earlier cycles: allocator 33, consumers 38, wiring 12 of 12, display 19 of 19,
  gate 10 of 10.
- Closure ledger `docs/audit/session-set-budget.closure.yaml`: 60 of 60 entries terminal (Gate 40). The `upstream_blocked` ones
  are product questions for the `enable_session_set_budget` flip review (floors, forced lead lift, 90-minute leftover, repeat
  phase), Rulings 6 and 7, the migration-017 column comment, the stale `plan_generator.dart` header (rule 14), the two literature
  citations, the core-list picks (`enable_core_list_pool` flip review) and OI-412.
- Local full `flutter test` on `32ae232c` (the merged tree): 10,961 passed, 28 skipped, 0 failed. `flutter analyze lib/`: 0 errors,
  0 warnings (60 existing infos). The ON-world gate over 1,847 real `generateV4` runs: green. CI on the PR is the full-suite gate
  for `main`; its result goes in the PR description, not here.
- The flip commit (deleting the OFF paths, CLAUDE.md 4.6 step 4) needs the full x2 review again and a `bpass: accepted`.
