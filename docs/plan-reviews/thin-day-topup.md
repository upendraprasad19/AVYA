---
branch: thin-day-topup
date: 2026-10-24
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/thin-day-topup-bpass.md
---

# Plan-review record - thin-day top-up (OI-401, platform)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED:** `git diff origin/main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -`
printed `Blast-radius: platform` for the 27 files of the branch diff (the plan engine under `lib/shared/repositories/plan_engine/`
sets it). The pre-commit NOTE on the records commit (`2b88e7c2`) agreed independently.

## What this branch is

Plan: `docs/plans/2026-10-24-thin-day-topup.md` (r3, rulings R1 to R13). Founder decision on OI-401 (option b, 2026-10-23):
a generated day with fewer than 3 exercises, for an injured user, is topped up with safe moves for that day's own muscles
(own pattern, then neighbour patterns, then safe core) and then stops. "Kept safe for variety" was rejected; the picker, swap
and add sheets stay unfiltered.

Code: `ExerciseSelector.topUpDays` runs on the finished day list at the three exits (the `pickV4` cascade end, the B1
`_pickCoreList` return, the `buildPinnedDays` end). Pure rules live in `thin_day_topup.dart`. The kill-switch is
`configBox['disable_thin_day_topup']` (default ON, getter `PlanEngineFlags.thinDayTopupEnabled`). `plan_generator.dart` is
untouched (root CLAUDE.md rule 14). The exercise-seam allowlist moved 16 to 17 `repo.queryV4(` sites.

Measured on the real generator over 7,200 runs, kill-switch set (main) against the branch, empty / thin / one-exercise:
singles 3/5 days 0/74/19 to 0/0/0; singles 4/6 days 1/75/13 to 0/0/0; pairs 3/5 days 4/531/197 to 0/2/0; pairs 4/6 days
6/647/241 to 0/6/0; repeat 0/768/310 to 0/0/0. Unsafe, unresolved, unperformable and duplicate picks stay 0. The residual is
one persona, filed as OI-408.

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Two context-blind plan lenses (A and B), every claim verified against code and live state | `not_converged`. Lens A 0 P0 / 2 P1 / 8 P2 / 6 M; lens B 0 P0 / 3 P1 / 8 P2 / 3 M. Five distinct P1s: the exercise-seam gate (both lenses), the slot's own pattern never retried, the Task 2 commit order against the diagnose gate, an untested equipment leak. r2 resolved every finding (resolution map in the plan) and re-measured the revised design on a second throwaway prototype. |
| 2 | Two fresh lenses on the POST-round-1 plan (r2) | `converged`. Lens A 0 P0 / 0 P1 / 6 P2 / 4 M; lens B 0 P0 / 0 P1 / 9 P2 / 4 M. r3 applied every P2 and mechanical fix (second resolution map). No design change. |
| B-pass | Fresh adversarial pass on the staged diff (`docs/reviews/thin-day-topup-bpass.md`) | 6 findings, 0 false alarms, all fixed in `f9f9b9fd`; verdict `accepted`. The material one: the core stage from phase 2 took the compound-first row (Dragon Flag for advanced users), now plan R13. |

## Rulings made during execution (plan section "Rulings")

R1 to R10 were settled in the plan before execution (R10, the seam allowlist, came out of round 1). Three were added while executing, each with a regression test that fails without it
and a mutation that reddens it:

- **R11** (full suite): a demoted (L6) curated sub leaves the candidate pool unless it is the only candidate.
- **R12** (full suite): the B1 gate keeps B1's own picks and any skill or olympic row hard, and attributes top-up additions
  by re-running the persona once with the kill-switch set; the three rows it pins (E234, E261, E271) are the R9 evidence.
- **R13** (B-pass): the core stage is foundational-first in every phase, and a `calisthenics_skill` or `olympic` row is never
  added at any stage.

## Verification state at the time of this record

- 35 of 35 mutations applied and killed, none a compile error (two runs, both stated in the diagnose-doc).
- Closure ledger `docs/audit/thin-day-topup.closure.yaml`: 20 of 20 entries terminal (two `upstream_blocked`: the R9 core-list
  question on the `enable_core_list_pool` flip review, and OI-408).
- The full local suite and `flutter analyze` on the final tree run after this record and before the push; their result goes
  in the PR description, not here.
