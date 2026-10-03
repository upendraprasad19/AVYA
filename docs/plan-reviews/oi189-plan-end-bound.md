---
branch: oi189-plan-end-bound
date: 2026-09-13
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi189-plan-end-bound-bpass.md
---

# Plan-review record — OI-189: every phase-layout writer stops at `plan_end`; every regen sweeps past it; every window move is pushed (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). **Platform**
tier — not by design intent but by path: round 4 F3's one-line `pausedForSimulation` guard lives
in `lib/core/services/sync/sync_workout.dart`, which `docs/blast_radius.yaml:63` pins `platform`;
every other staged path is `account` or below. The plan said `account` until staging time; corrected
in the plan, the diagnose-doc and here. Not catastrophic → no Hermes. `bpass:` flips to `accepted`
only on the founder's explicit word after triage.

Plan: `docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md` (v5; its Review log is the
round-by-round record). Diagnose-doc: `docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md`.
Test: `test/contracts/oi189_plan_end_bound_behavioral_test.dart` (12 behavioural + 9 source pins
+ 6 unit tests on the B-pass-extracted phaseNote()/phaseDayLabel(), 27/27; 22 mutation legs each
reddened on the predicted assertion — the last 3 added fixing B-pass findings B-1/B-2/B-4).

## Scope

1. `WorkoutScheduleReadService.sweepNonCompletedRowsPastPlanEnd({dryRun})` — NEW shared helper;
   removes non-completed `schedule_*` rows of any type + `displaced_*` shadows past the STORED
   `plan_end`; returns `({workouts, removed})`; no-op unless BOTH window keys are stored.
2. Writer B (`generateAndScheduleFromDate`) sweeps after its delete loop and pushes `plan_json`
   before returning.
3. Writer A (`generateAndSchedule`) gains `bool pushPlanWindow = false`; pushes only when true;
   `true` at exactly `autoGenerateNextPhaseIfNeeded` and the PRO advance. The facade does not
   forward it.
4. `redoWeek4` pushes after moving `plan_end`; `pushWorkoutPlanForSyncDomain` guards on
   `pausedForSimulation` first.
5. Writer C (`RegeneratePlanPlanner.plan()`) bounds every day at `plan_end`; result gains
   `requestedWeeks` / `phaseEndsOn` / `clearsPastPhaseEnd`; `totalWeeks` becomes the bounded count.
6. Both dispatcher commit sites sweep, push after the splice, carry `cleared`; the empty-set branch
   is success-with-`cleared` when the sweep removed anything, failure (cache kept) otherwise.
7. Both diff previews render the phase note (three forms); the week section hides at 0 weeks.
8. Board: OI-189 CLOSED; OI-174 OPEN narrowed; OI-190 gains the card-copy inputs; OI-166 pointer.
   Nested CLAUDE.md sentences (train, ai_coach). SoT registry `line_range`s refreshed.

Founder decisions 2026-09-12: **D1** restore residual stays on OI-174 (no restore-path change);
**D2** user-placed rows past `plan_end` are swept too.

## Ground truth verified

- Writer/reader census by file:line (diagnose-doc `writers:` / `readers:`), every anchor re-derived
  from the working tree after the edits.
- Prod (read-only, `dedsavbjuwgarrhphgnl`, 2026-09-13): `user_progress.plan_json` — 10 users, 369
  schedule keys, **0** past `plan_end_date`; `scheduled_workouts` — 369 rows, **0** past the
  snapshot's `plan_end` (any status). SQL in the diagnose-doc tier-4 evidence.
- `flutter analyze lib/ test/` — 0 errors, 0 warnings (`^\s*warning -` anchor).
- Census run: 92 test files naming any touched basename → 849 tests, all green.
- `sh scripts/pre-commit.sh` — full loop, OK; parity gate 0 errors after the six `line_range`
  shifts (+56 before the helper, +141 after).

## Rounds (all context-blind; every finding verified against the code before folding)

| Round | Verdict | Findings | What changed |
|---|---|---|---|
| 1 (2026-09-12) | material-issues | 11 (2 P1, 5 P2, 4 P3) | Sweep on B only → shared helper + both coach commit sites; `pushSnapshot` ≠ `plan_json` and the restore resurrects → push after every sweep; second prod census; wording narrowed + D2; explicit-`startDate` bounded too; Retry loop (no `clearCache` on refusal); clock-seam fixtures; "0-week plan" note replaces the header; BOTH window keys required; hold/redo write-then-move window documented. |
| 2 (2026-09-13) | material-issues | 14 (2 P1, 4 P2, 8 P3) | Refusal returned before the push and before `execute()`'s tail; writer A moved the window and pushed nothing (`c9e4b7` hazard) → push on A; `_phaseNote` third form; free-user copy removed; M2 did not compile; M8/M9 added; `recordNonFatal(reason:)`; B push placement; fabricated `coach_regen_phase_stamp` pointer removed; EF-authored summary → OI-190; census widened; bound normalised. |
| 3 (2026-09-13) | material-issues | 6 (1 P1, 2 P2, 3 P3) | **Round 2's unconditional A push fires on the reinstall path** (`auth_session_bootstrapper.dart:653` generates on a fresh Hive BEFORE the restore; `_syncWorkoutPlan` is a whole-blob REPLACE) → `pushPlanWindow` opt-in at the two advance sites, pinned both ways; sweep-only regen must SUCCEED to reach the invalidate tail (round 2's failure-path invalidation dropped); pushes had no test → source pins + M11-M17; count = workouts only; slips. |
| 4 (2026-09-13) | material-issues | 8 (1 P1, 2 P2, 5 P3) | C5's same-id second dispatch hit `execute()`'s idempotency marker (test bug) → fresh id; `redoWeek4` moves the window without a push → block + M18; year-sim reaches the push unguarded → `pausedForSimulation` guard + M19; branch on `removed` not `workouts` (record return); `:742` repair trigger named; "never a hang" corrected; card copy → OI-190; CLAUDE.md append point. |
| 5 (2026-09-13) | **converged** | 4 (0 P0-P2, 4 P3) | Wording/count slips only: stale round-3 clause, hermetic-test rationale, "four" → five sites / six blocks, one `holdWeek` anchor. Confirmed every round-4 delta against the tree (fresh-id path, `redoWeek4` last statement, sim flush order + `weeklyFullSync` bypass, record-type shapes on SDK ^3.11.1, both new pins' literals absent today). |

Why not split (§4.12.1): rounds 3-4 found defects INSIDE the previous round's corrections and in
the tests, not new design — the same helper + bound + sweeps + pushes shipped; the sweeps are unsafe
without the pushes and the bound is pointless without the sweep.

## Implementation notes

- `dart format` was NOT applied to the eight lib files (not format-clean at base; formatting them
  produced a 1,700-line diff hiding the real 403-line change). The new test file is format-clean.
- `res.data as Map` → `as Map?` + `isNotNull` (`cast_nullable_to_non_nullable` is a WARNING here).
- The regen-block pin gained `expect(sweep, isNonNegative)` after M8 showed `-1 < emptyBranch`
  passing with the sweep absent — found by the mutation, the reddens-nothing class.

## B-pass

`bpass_review` above. Findings and their triage are recorded in that file; this record's `bpass:`
is flipped to `accepted` by the founder's word, never by the agent.

## Feature-flag deviation (platform tier `requires:`, founder-ratified 2026-09-13)

`docs/blast_radius.yaml:25` lists `feature_flag` in platform tier's `requires:`. This batch ships
with no kill-switch on the sweep or the new durability pushes. Per the B-pass's Finding 1, the
founder was given the choice between adding one (new scope: threading a flag through 7 call sites
— both dispatcher commit sites, writer A/B/C, `redoWeek4`, the `pausedForSimulation` guard — plus
its own review round) and waiving the requirement with a written, self-attested deviation — the
same shape as the 2026-08-11 `commit-merge-push-process` ADR-0018 precedent for this exact
registry field. **Founder chose to waive it, 2026-09-13.** Substitute safety net offered in place
of a flag: 27/27 behavioural + unit tests, 22 mutation legs each reddened on the predicted
assertion, both live prod censuses at 0/369 rows past `plan_end` (so there is effectively nothing
live for a flag to switch off), and five context-blind plan-review rounds plus the two-reviewer
B-pass itself. No new code shipped for this deviation; it is a documented process exception, not
a compliance claim.
