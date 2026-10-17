---
branch: regen-wave-alignment
date: 2026-09-08
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/df96a61cf598-bpass.md
---

# Plan-review record — OI-166 Unit 1 (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Platform tier**, measured against the ACTUAL staged file list
(`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -` → `platform`),
because `lib/core/services/sync/**` is pinned `platform` at `docs/blast_radius.yaml:63`. Not
catastrophic → no Hermes pass.

## Scope

OI-166 Unit 1 — what survived the §4.12.1 SPLIT, plus two bugs found while reviewing it.

1. **`scripts/check_single_schedule_row_builder.dart`** (+ pure
   `scripts/schedule_row_builder_gate_lib.dart`) — the §4.11 gate that must exist BEFORE Unit 2's
   `buildScheduleRows` refactor. WARN-only by built-in default (`const _hardFail = false`, not a
   call-site flag, because pre-commit and CI auto-wire every `check_*.dart` by glob with no args).
2. **`rawWeekNumberFor` / `rawWeekNumber` / `planWeekAndCharacterFor`** extracted in
   `workout_schedule_read_service.dart`; `template_service.dart`'s duplicated week arithmetic
   repointed at the shared copy.
3. **The hotel planner's three wrong stamps** (`week: 1`, `week_character: 'baseline'`,
   `day_of_week: d.weekday`) now derived from each row's own date — diagnose `a9f3c7`.
4. **OI-170** — the `day_of_week` cloud round-trip — diagnose `c4e8b2`.
5. **OI-171** — the deload lift's blob push ordering — diagnose `b6d1f4`.

## Review history — five rounds, then a split

| Round | Verdict | What it found |
|---|---|---|
| 1 | not-converged | 11 findings |
| 2 | not-converged | 5 new P1s **inside round 1's corrections** |
| 3 | not-converged | 2 P1 + 6 P2; produced the implementation inventory |
| 4 | not-converged | 5 P1 + 5 P2; found a FOURTH row implementation, and OI-170 |
| 5 | not-converged | 7 P1 + 9 P2, **four P1s inside round 4's own remediations** |

Round 5 is §4.12.1's split signal stated verbatim: *"when successive reviews keep surfacing new
material issues, that is the signal the unit is too large — split it and ship the smallest
converged piece, don't review the large thing a fifth time."* It independently recommended the
same split point already decided one message earlier.

**Unit 1 (this record) is converged** — round 5 found nothing blocking in items 1-3.
**Unit 2** (the shared `buildScheduleRows`, callers A/B/C, the deload dual write, the coach's
`current_plan` write, the preview-cache rule) is re-planned from scratch; its five surviving P1s
are recorded in the plan doc and the in-flight memory.

⚠ **Unit 1 does NOT fix OI-166's filed symptom.** The stale phase-arc strip is the coach never
writing `current_plan`, which is Unit 2's §5. Stated here so the merge is not read as closing
OI-166 — the board entry still says OPEN, correctly.

## Ground truth verified

- Every citation in the plan re-read against source in-session. Two of the author's own numbers
  were found inflated during round 5 and restated (the coach drops 2 live `PlanGenerator` inputs,
  not 4; 2 of 4 blob writers pair `syncWorkoutData()`, not all 4).
- Round 5's P2-9 was **corrected in the reviewer's disfavour**: it concluded the lifted blob
  *"never reaches `plan_json`"*, which overreached — the row writes' own fan-out does reach it.
  Verifying before acting changed the fix from a new fan-out to one narrow ordered push, and
  produced OI-171 with the accurate mechanism.
- Live state checked where it mattered: `grep -rn "day_of_week" supabase/functions/` → 0 (positive
  control `scheduled_workouts` → 5 files), so no Edge Function reads the column and no server-side
  contract constrains the fix.

## B-pass — 5 findings, 0 false alarms, all fixed in-batch

`docs/reviews/df96a61cf598-bpass.md`. Two context-blind agents, lenses split 1-5 / 6-8. Summary of
what it changed, because three of the five were not code defects:

- **P0** — a three-way OI-number collision with numbers `main` minted concurrently
  (`OI-167/168/169` → renumbered `173/174/175`). ⚠ `check_oi_numbering_unique.dart` reported
  `PASS (vacuous)`: this branch has zero commits, so HEAD is the merge commit it was cut from and
  the gate compared that commit's two parents instead of the staged board against mainline.
- **P0** — the OI-171 regression test was unstaged and its diagnose-doc cited an unrelated
  contract test.
- **P1** — the plan doc and the board both described a batch that no longer existed: header said
  `account` while the diff measured `platform`, §10 listed OI-170 as out-of-scope while the diff
  implemented it, the board said OPEN while the diagnose-docs said fixed, and **no `feature_flag`
  existed** though `platform`'s `requires:` list demands one. Fixed by correcting all four and
  adding the kill-switch `disable_day_of_week_derive`.
- **2 × P2** — the OI-171 fix had zero coverage (proven by deleting the line: 60 tests stayed
  green), and the new gate was defeated on the reviewer's first attempt by index-assignment
  indirection.

## Mutation proofs (rule 21 / rule 24) — every test in this batch was broken on purpose first

| What was mutated | Red |
|---|---|
| `parsed.weekday - 1` → `parsed.weekday` (the original defect) | 4 / 13 |
| kill-switch polarity `!=` → `==` (default becomes the broken path) | 4 |
| gate removed from the restore wiring (legacy arm unreachable) | 1 |
| deload push MOVED above the blob write (the pre-fix defect) | 1 / 23 |
| deload push DELETED | 3 / 23 |
| week derived from `nowWall()` instead of the row's date | 3 / 19 |
| short-blob guard deleted | 2 / 19 |
| gate: two-key AND → OR | 4 / 26 |
| gate: `stripDartComments` → identity | 4 / 26 |
| gate: allowlist `containsKey` deleted | 2 / 26 |
| gate: index-assignment arm deleted | 3 / 26 |

Every mutation left the file **compiling** — a compile error is red for the wrong reason. Every one
was confirmed APPLIED by `grep -c` before the run; one attempt silently matched nothing and
reported 26/26 green, which the applied-check caught. Three fixture defects were found this way
across the batch, none by reading.

## Deliberately NOT done, each with an owner

- **Unit 2** — the shared builder and everything that depends on it. Re-planned from scratch; five
  P1s carried forward in `docs/audit/oi166-regen-wave-alignment-plan.md`.
- **The gate's named-constant residual** — a source grep cannot close it, and tightening the
  pattern only moves the boundary. Pinned as an executable test so the limit reddens if anyone
  closes it; Unit 2's shared builder is the structural fix.
- **Q7** (`switch_goal` refresh regression) — parked on the OI-166 board entry with the Unit 2
  re-plan as owner, not in this doc.
- **OI-173/174/175** — cold-start weight estimate, past-`plan_end` prune, `rawWeek > 4` semantics.
  Each on the board with a terminal owner; the last two carry founder questions.
