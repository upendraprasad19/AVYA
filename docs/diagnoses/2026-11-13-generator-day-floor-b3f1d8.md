---
bug_id: b3f1d8
date: 2026-11-13
batch: generator-step2b-day-floor
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-452 (step 2 of the generator overhaul, unit 2B): a day could end with 1 or 2 exercises. Measured on main 8a2e1c5a
  over the probe's two injury-sweep blocks (weeks 1-2, 34,560 day-weeks): 369 thin day-weeks (pairs 70, all 5-day;
  the 30-minute pinned repeat 299), equal to `kThinCeilings`; over the whole injured grid (46,512 runs, 418,608
  day-weeks, 60 minutes) 2,292 thin and 94 one-exercise day-weeks; the r6 removed-runs ratchets held 4 to 50 thin days
  per block. A user should not go to the gym for a 10-minute, two-exercise session.
concept: day_floor
sot_registry_entry: day_floor
contract_test_path: test/contracts/day_floor_behavioral_test.dart
related_bugs: [2d04d7, d4a7e2, e5c2a9]
recurrence: |
  Recurrence of the thin-day class. 2d04d7 (OI-401, the thin-day top-up) fixed the SELECTOR side: an injured user's
  selector day is topped up to 3. After the session set budget went on (2026-11-02), the ALLOCATOR removed slots whose
  group's weekly top was spent (closure row SBF-THIN-DAYS, docs/audit/set-budget-flip.closure.yaml); a guard that took
  removed slots back over the top fixed the sweeps and was reverted because it broke the weekly-top invariant (a top
  of 16 reached 26). e5c2a9 (OI-456 piece B, the count band) added pass A2, which forces only within the top. d4a7e2
  (Unit 2A) made three 30-minute repeat blocks a day thinner through its pins (`kThinCeilings` note). The known-good
  fix differs from the reverted guard in what the founder decided (d30-d33) and in a RESTATED invariant: only days
  under 3, 2 sets a seat, the worlds chosen first, every seat named. Bug-history lookup (CLAUDE.md 4.1.5): grep of
  docs/diagnoses for "thin", "SBF-THIN-DAYS", "one-exercise", "weekly top", "kThinCeilings", "countForced" (token and
  concept); every hit read.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "allocate: the kill-switch read (dayFloor ?? PlanEngineFlags.dayFloorEnabled), passed to both 2A paths", line: 204 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "floorPrefers (F2: fewest groups over the top, least excess, cheapest)", line: 170 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateLeadFirst: the chosen worlds (wA, wB) re-run with the floor, B copying the floored A; the 6-day re-run", line: 327 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: floorSeats copied for B's copied days", line: 513 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: labelBeforeFloor snapshot, then the floor block (canFloor, overTop, overClock, ledger.add)", line: 778 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method_or_widget: "dayFloorEnabled (disable_day_floor, default ON)", line: 72 }
readers:
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "BudgetLedger.fits: an over-top group fits no further set (passes B, C, D never grow a floor seat)", line: 568 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_weekTwoGains: week 2 gains nothing on an over-top group; week 4 keeps a 2-set seat at 2", line: 165 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4 calls allocate without dayFloor, so it reads the flag (untouched, rule 14)", line: 293 }
  - { file: test/helpers/budget_invariant_oracle.dart, method_or_widget: "BudgetInvariantOracle: weekCeiling, floorOverClockSeconds, countForcedSeconds (every test reader of the top and the time)", line: 15 }
hive_key_prefix: "configBox['disable_day_floor']; plan_json.workouts[].exercises[] (the plan blob)"
hive_key_formula: "PlannedExercise rows and sets per week -> WorkoutDay.toMap exercises[]"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); rows and set counts pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); a stored plan is not rewritten, the floor applies to plans generated from now on"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers (wrapUserScopedBox); the flag lives in configBox like every PlanEngineFlags switch."
forbidden_patterns_checked:
  - { pattern: "a day under 3 exercises in the gate's blocks (pairs phase 1 / 4, the 30-minute pinned repeat), weeks 1-4", absent: true }
  - { pattern: "a day that loses an exercise against the floor-off plan of the same persona", absent: true }
  - { pattern: "a group past its session cap", absent: true }
  - { pattern: "a group past its weekly top without a floor seat naming it", absent: true }
  - { pattern: "a floor seat in countForced", absent: true }
  - { pattern: "an output change with disable_day_floor set (the gate's floor-off digests vs main 8a2e1c5a)", absent: true }
  - { pattern: "an uninjured golden persona changed (1,010)", absent: true }
  - { pattern: "plan_generator.dart modified (CLAUDE.md 4.4 rule 14)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-13-generator-step2b-day-floor.md (v6, four review rounds, founder d30-d33).
  F1: after pass A2, a day whose rows (budgeted and not) are under min(3, its reach) seats remaining slots at 2 sets
  past a group's weekly top, one per day per round: no excess limit (d30), every phase (d31), up to its reach (d32),
  not bound by the clock (d33); never past a session cap, never a reservation-blocked slot.
  F2: SessionSetAllocator.floorPrefers: the fewest groups over their top, then the least excess, then the cheapest;
  ties to the lowest rank; no lead preference.
  F3: with Unit 2A on, the worlds are chosen with the floor off, then the chosen A and B are re-run with it (B copying
  the floored A); the 6-day path re-runs A.
  F4: AllocationStats.floorSeats (FloorSeat: name, sets, overTop, overBy = each group's exact excess, overClock,
  overSeconds = the overrun); never in countForced; belowCount keeps
  the label A2 left (a snapshot taken before the floor).
  F5: kill switch disable_day_floor (PlanEngineFlags.dayFloorEnabled, default ON) and allocate(dayFloor:), in both 2A
  paths. The budget invariant is restated in one shared test oracle.
regression_test_planned: |
  test/contracts/day_floor_behavioral_test.dart (F1-F5 and the interactions, crafted fixtures worked by hand);
  test/plan_generator/day_floor_gate_{pairs_p1,pairs_p4,rep30}_test.dart (floor on vs off, weeks 1-4, the oracle, the
  floor-off digests vs main 8a2e1c5a); test/plan_generator/day_floor_kill_switch_test.dart (the four combinations);
  every reader of the weekly top and the day's time routed through test/helpers/budget_invariant_oracle.dart.
impact_analysis: |
  Platform tier (plan engine): an injured user's thin days gain rows past a weekly top. Uninjured plans are unchanged
  (1,010 golden personas). Costs accepted by the founder (d30-d33): a group's weekly sets can pass its top by up to 8
  in the probe (42 group-weeks at +6 / +8), and a floored day can run past its minutes by the floor seat's time. The
  app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "session_set_allocator.dart, plan_engine_flags.dart; flutter analyze clean; every test file that reaches the allocator (79) run on the built tree, each red listed with its cause below; mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "configBox['disable_day_floor'] read through PlanEngineFlags like every engine switch (day_floor_behavioral_test F5: absent ON, set OFF, the argument overrides, in both 2A paths); no new box, no stored plan rewritten" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no cloud column, table or migration: rows and set counts live inside plan_json, whose shape is unchanged" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the 1,010-persona golden passes unchanged; the gate's floor-off digests equal main 8a2e1c5a" }
---

## Root cause

Measured on main 8a2e1c5a (plan §1). The labels hid it: 363 of the 369 thin day-weeks read `selectorThin` (3
selector slots are below the 4-5 count floor), yet the selector gave 3 and the day ended with 1 or 2. A temporary
trace of every left-out slot showed each was refused by a WEEKLY top that earlier days had filled (Back 219, Glutes
69, Quads 61, Shoulders 29, Chest 8, Biceps 2), while the session cap had room and the day had 700-850 s left. Pass
A2's `canForce` refuses any slot past a weekly top, so nothing could seat them.

- **Writer:** `SessionSetAllocator._variant` pass A (`ledger.fits`: time, session cap, weekly top) and pass A2
  (`canForce`: never past a top or a cap).
- **Reader:** the count verdict (`selectorThin` / `belowCount`) and the sweep ratchets (`kThinCeilings`,
  `r6_removed_runs_lib.dart`).

## Fix

See `proposed_fix`. The floor runs after A2 and before passes B, C and D; since an over-top group fits no further set
(`BudgetLedger.fits`), those passes never grow a floor seat, week 2 gains nothing on it and week 4 keeps it at 2.

## Measured on the final tree

- **The gate** (`day_floor_gate_{pairs_p1,pairs_p4,rep30}_test.dart`, the real generator, each persona with the floor
  on and off, weeks 1-4, 6,720 personas, 120,960 day-weeks): no day under 3 with the floor on in any block. Thin
  day-weeks with it off, every one of which gains rows and reaches 3: pairs phase 1 140 (home 40, basic 60, full 40),
  pairs phase 4 178 (home 40, basic 90, full 48), the 30-minute repeat 598 (bodyweight 120, home 242, basic 192, full 44);
  each is exactly twice the probe's weeks 1-2 count (70 / 89 / 299). No exercise lost against the floor-off plan; no
  day at 3 or more gains a row. Knock-on (same exercises, fewer sets): 7 day-weeks, all in the repeat (bodyweight 4,
  home 3). The prototype probe had counted 10 over weeks 1-2; the difference between the prototype and the final tree
  was not traced (NOT established), the final count is the one pinned. The oracle holds on every day-week (week <= top +
  floor over-top sets, no session cap passed).
- **The kill switch.** The digest of the sha256 of every floor-off plan of the gate equals the one recorded on a
  detached checkout of main 8a2e1c5a in all 12 (block, tier) cells: with `disable_day_floor` set, the 6,720 injured
  personas generate main's plans byte for byte. The four `disable_lead_first` x `disable_day_floor` combinations are
  pinned on a sample where the floor acts (`day_floor_kill_switch_test.dart`).
- **A 2A residue, not the floor's.** 9 day-weeks (pairs phase 1, home_dumbbells: wrist + elbow, strength,
  intermediate, 4 days) hold a row at the lead + 2 or more, with the floor ON and OFF alike (identical plans, probe):
  both variants fell back to Unit 2A's `main` world (whole-plan fallback), where R2 does not apply; the 2A gate covers
  uninjured personas only, where `main` is never kept. The gate pins the count and fails on any lead + 2 the floor adds.
  Finding for the next step's plan (unit 2C), not a new unit.
- **Uninjured golden** (1,010 personas): unchanged. `lead_first_gate_test` and the session-set-budget gate: green.

## Every red on the built tree, with its cause

All 79 test files that reach the allocator or the generator were run on the built tree before any re-record
(1,014 passed, 41 red). The golden (1,010 personas), `lead_first_gate_test`, both kill-switch goldens and the
session-set-budget gate stayed green.

- `kThinCeilings` (`injury_sweep_a_pairs_test` home / basic / full, `injury_sweep_f_repeat_pairs30_test` all four
  tiers): every block measures 0 / 0 (was pairs 20 / 2, 30 / 2, 20 / 0; repeat 60 / 8, 121 / 2, 96 / 2, 22 / 0).
  Lowered to 0, the old values kept in a comment.
- The eight `r6_removed_runs_*_test.dart` (25 per-tier tests): every block measures 0 / 0 (was 1 to 50 thin, 0 to 6
  one-exercise). Lowered to 0, the old values kept in a comment.
- `exercise_count_band_behavioral_test` (e) and (m): the floor seats past the clock (d33) and past the top (d30). Each
  keeps its original assertions with `dayFloor: false` and pins the floor-on result.
- `quads_credit_flag_consumers_test` (allocator, week 2): the full-credit days handed two slots are floored to two
  (d32). Both run with `dayFloor: false` so they still differ ONLY in the credit flag; a new test pins the floor-on
  allocation (Glutes 24, Quads 12).
- `session_set_allocator_behavioral_test`: boundBy (days 1-4 floor their lead past the clock, d33, so day 0's lead
  stays at 2 bound by Chest), the weekly top (16 -> 20, reach-2 days, d32), the lighter phase (12 -> 24, d31), R1 P2-2
  (the dropped lead is floored past the clock, d33; the nested CLAUDE.md sentence "protected from the week and from an
  empty day, not from the clock" gains "since Unit 2B a lead on a thin day may be seated past the clock"): each keeps
  its original under `dayFloor: false` and pins the floor-on result. The seeded sweep's week and time checks read the
  oracle; 12 floor seats in the sweep, all past a top, none past the clock (pinned).
- Checked and unaffected: `thin_day_topup_behavioral_test` (~373, ~427, ~444) and `session_set_budget_wiring_test:302`
  (their thin days come from the selector, reach 2, floored to their reach); `lead_first_gate_test` reads no top or
  time.

## Mutations

Each mutant applied once (count checked, file restored byte for byte after each), against
`day_floor_behavioral_test.dart`; no compile error, every one red:

| Mutant | Red |
|---|---|
| M01 F1: refuse a seat past the weekly top | 14 |
| M02 F1: session-cap check dropped | 1 (the cap fixture) |
| M03 F1: `reserveBlocked` check dropped | 1 (the reservation fixture) |
| M04 F1: skip a day whose reach is under 3 (d32 reversed) | 2 |
| M05 F1: no floor in a lighter phase (d31 reversed) | 1 |
| M06 F1: the 300 s clock bound restored (d33 reversed) | 1 |
| M07 F2: the over-top count key dropped | 1 |
| M08 F2: the excess key dropped | 1 |
| M09 F2: the cost key dropped | 2 |
| M10 F2: ties to the later rank (`<=`) | 6 |
| M11 F4: `overClock` never set | 2 |
| M12 F4: `overClock` always set | 11 |
| M13 F4: the label read after the floor | 1 (the clock-label fixture) |
| M14 F3: the floor inside the world choice | 6 |
| M15 F3: B copies the unfloored A | 1 |
| M16 F3: `floorSeats` not copied to B | 1 |
| M17 F5: the switch ignored in the 2A path | 2 |
| M18 F5: the switch ignored in the 2A-off path | 6 |
| M19 F3: the 6-day path not re-run | 4 |

The shared oracle, against `day_floor_behavioral_test`, `session_set_allocator_behavioral_test` and
`exercise_count_band_behavioral_test`: O1 `weekCeiling` without the floor allowance, 9 red (the floor fixtures, the
re-recorded weekly top and lighter phase, the seeded sweep); O2 `overClock` seconds never excused, 2 red.

## B-pass (docs/reviews/generator-step2b-day-floor-bpass.md)

Three fresh Sonnet seats ran on d7013d29 (CI green): 0 P0 or P1. Fixed in the review commit:
- `FloorSeat` gains `overBy` (each over-top group's exact excess, at most 2) and `overSeconds` (the part of the seat
  past the seconds left; the whole seat when none were left). The shared oracle sums those exactly, instead of 2 sets
  and the full seat seconds per seat matched by name (seat 2, finding 2-4).
- The count-target test is now a premise pin (every count max >= 3), plus a `canFloor` comment explaining why the
  floor needs no target guard (S1-2, 2-1).
- Stale `day_floor_gate_test.dart` citations repointed to the three gate files and their lib (S1-1, 2-2).
- Rows asserted per week in the weeks 1-4 fixture (2-5), and two test comments (2-3, 2-6).

Seat 3 ran 32 new mutants on the post-fix tree, and 26 were red. Of the 6 green:
- 3-1: the oracle summing the first `overBy` value, or a flat 2 per `overTop` group (m08, m09). Fixed by an oracle
  unit test over hand-built stats.
- 3-2: a group exactly at its top counted as over (m13 in the over count, m29 in `overTop` / `overBy`), and a group
  under its top lowering the excess (m30). Fixed by two F2 fixtures (at-top tie, under-top tie).
- m19 (the floor seat's `why` reset) and m06 (`overClock` `>=`): equivalent. `why` is read only for non-admitted slots
  and nothing un-admits a floor seat; at exact equality, `overSeconds` is 0 either way.

The coordinator re-applied m08, m09, m13, m29 and m30 after the fixes. Each one is now red in exactly one test, the
test written for it (`day_floor_behavioral_test`, 22 passed and 1 failed each), and the files were restored with a
sha256 check after each.
