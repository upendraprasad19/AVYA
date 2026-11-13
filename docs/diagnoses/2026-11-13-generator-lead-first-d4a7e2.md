---
bug_id: d4a7e2
date: 2026-11-13
batch: generator-step2-allocator
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-486 (generator full audit 2026-11-08, step 2 of the generator overhaul): a day's main lift ended with fewer sets
  than an accessory on the same day. Over the 2,304-plan audit grid (4 goals x 3-6 days x 3 levels x 4 tiers x 30-90
  minutes x phases 1-3, no focus, no injuries) 1,084 plans held a "starved lead" (a compound lead 2+ sets under an
  isolation; 2,284 flags), 2,676 / 3,265 / 2,676 days in weeks 1 / 2 / 3 held an exercise at the lead's sets + 2 or
  more, and 5,720 week-1 leads sat at 2 sets. Example (cross_day_variety fixture, full_gym 6-day beginner, main):
  Push A opened with Dumbbell Bench Press at 2 sets while Cable Rope Pushdown held 5.
concept: lead_first
sot_registry_entry: lead_first
contract_test_path: test/contracts/lead_first_allocator_behavioral_test.dart
related_bugs: [e5c2a9, 44d40a, cf970c, e4b7a2]
recurrence: |
  Not a recurrence of a fixed bug: e5c2a9 (OI-456 piece B, the count band) recorded this outcome as a stated
  consequence of seating every exercise at 2 sets first ("accessories can take weekly top before a lead lift grows, so
  a lead lift can end at 2 sets", plan_engine/CLAUDE.md). 44d40a (the core-list audit) and the 2026-11-08 generator
  audit measured it (OI-486); cf970c (Unit 1B-Q) moved the B leg day's quad compound second because the allocator
  seats in split order; e4b7a2 (Unit 1B-R) is the previous kill-switch unit whose golden fixture this one re-records.
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grep for "lead lift", "lead_starved", "starved lead",
  "firstLifts", "lead can end at 2" (token and concept); every hit read.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "allocate: the kill-switch read (leadFirst ?? PlanEngineFlags.leadFirstEnabled)", line: 178 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "worldIsWorse (R3's pure test)", line: 218 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateLeadFirst (R3: lead, capped, main worlds per variant; B over the chosen A; whole-plan fallback)", line: 239 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: opener per day (openerAmong over budgeted slots)", line: 524 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant pass A: R1, the lead seated at baseSets when it fits", line: 565 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: R2 underLead (pass C only; pass D exempt)", line: 757 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant stats: leadSeats (the day's lead and what bound it)", line: 834 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "apply: the kill-switch read (capToLead)", line: 83 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_weekTwoGains: R5, each day's lead index and the lead + 1 hold", line: 207 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method_or_widget: "leadFirstEnabled (disable_lead_first, default ON)", line: 58 }
readers:
  - { file: lib/shared/repositories/plan_engine/sequencing_engine.dart, method_or_widget: "openerOf (the lead; shares _sorted with _reorderDay)", line: 62 }
  - { file: lib/shared/repositories/plan_engine/sequencing_engine.dart, method_or_widget: "_reorderDay (unchanged order; reads _sorted)", line: 101 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4 calls allocate (no leadFirst argument) and apply (none), so both read the flag", line: 293 }
  - { file: test/plan_generator/plan_audit/plan_audit_lib.dart, method_or_widget: "PlanAuditor.audit lead_starved skips a focus row (d27)", line: 315 }
hive_key_prefix: "configBox['disable_lead_first']; plan_json.workouts[].exercises[].sets (the plan blob)"
hive_key_formula: "PlannedExercise.sets per week -> WorkoutDay.toMap exercises[].sets"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); set counts pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); a stored plan is not rewritten, the rule applies to plans generated from now on"
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
  - { pattern: "a budgeted row at its day's lead + 2 or more (non-focus), any week, any golden persona", absent: true }
  - { pattern: "a day whose first exercise differs from the switch-off plan's while that exercise is still in the day", absent: true }
  - { pattern: "a hold (not budgeted) taken as the lead", absent: true }
  - { pattern: "a kept world worse than main: a day under min(count floor, main rows) or a group main trains at 0", absent: true }
  - { pattern: "an output change with disable_lead_first set (1,010 golden personas)", absent: true }
  - { pattern: "plan_generator.dart modified (CLAUDE.md 4.4 rule 14)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-12-generator-step2-allocator.md (v8, seven review rounds, founder d26-d29).
  The lead = SequencingEngine.openerOf over the day's budgeted rows (the row the sequencer opens with; one sort shared
  with _reorderDay, List.sort stable below 32 rows); not admitted -> openerOf over the admitted slots, as week 2.
  R1: pass A seats the lead at SessionBudget.baseSets (3) when time, caps, top, the count target and (rank 0) the
  reservation allow, never by an eviction; else exactly as on main.
  R2: pass C holds every other budgeted slot at the lead's sets + 1; pass D (focus) is exempt (d27).
  R3: per variant, the lead world, else the capped world (R2 only), else main's, the first not worse than main
  (worldIsWorse); B's worlds copy the chosen A's days and stats and compare with main's B; neither B world holding sends
  the whole plan to main. AllocationStats.leadWorld and leadSeats are new.
  R5: week 2 holds a row that is not the lead and credits no focus group (a hold included) to the lead's week-2 sets + 1.
  Kill switch disable_lead_first (PlanEngineFlags.leadFirstEnabled, default ON), read by allocate and apply unless
  their new optional leadFirst argument is given; plan_generator.dart untouched.
regression_test_planned: |
  test/contracts/lead_first_allocator_behavioral_test.dart (35 tests: openerOf incl. the library sweep; R1-R3, R5; the
  kill switch and the leadFirst argument); test/plan_generator/lead_first_gate_test.dart (1,010 golden personas, both
  worlds); test/plan_generator/lead_first_kill_switch_golden_test.dart (OFF = main 9fc3b043 byte for byte);
  plan_audit_lib_test.dart (the focus skip).
impact_analysis: |
  Platform tier (plan engine): every generated plan's set counts. 939 of 1,010 golden personas change. Costs accepted
  by the founder (d26, d28): days lose or swap an exercise, some 30-minute days run up to the count floor's 300 s
  bound over, Calves and Glutes sets fall (plan section 4). The app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "session_set_allocator.dart, periodization_engine.dart, sequencing_engine.dart, plan_engine_flags.dart; flutter analyze clean; 72 affected test files re-run, every moved pin re-read (below); mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "configBox['disable_lead_first'] read through PlanEngineFlags like every engine switch (lead_first_allocator_behavioral_test group 6: unset ON, set OFF, the argument overrides both ways); no new box, no stored plan rewritten" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no cloud column, table or migration: set counts live inside plan_json, whose shape is unchanged" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged (sets per exercise only); the 1,010-persona golden re-recorded and the OFF fixture equals main's hashes" }
---

## Root cause

Measured on main 9fc3b043 with the 2,304-plan audit (`plan_audit_dump_test.dart`) and the prototype runs logged in the
plan (sections 2-4).

- **Seat order.** `SessionSetAllocator` pass A seats every slot at 2 sets rank by rank across the week, then pass B
  grows to 3 and passes C / D grow towards the band floors and the focus top (OI-456 piece B, e5c2a9). A compound
  lead credits several groups, so it meets a session cap or weekly top first; an isolation keeps growing.
- **Which row leads.** The allocator protected rank 0 (the split's first slot); the user lifts the sequencer's opener
  (`_reorderDay`: compound, bilateral, CNS demand), which is not rank 0 on many days. A protection keyed on rank 0
  missed the row that opens the day. 2A keys every rule on the opener and leaves the sequencer unchanged.

## Measured on the final tree

- **The prototype reproduced byte for byte.** The 2,304-plan dumps and audits of the clean build equal the prototype
  z7051's in all three grids (no focus, `glutes_legs`, `chest_shoulders_arms`; `cmp` on `plan_dump.jsonl` and
  `audit.json`), so every number in plan sections 3-4 holds for this code: starved-lead plans 1,084 -> 47 (the 57
  residue flags are all holds: 43 Hollow Body Hold, 14 Doorway Isometric Row), suitable 513 -> 789, days with an
  exercise at the lead + 2 2,676 / 3,265 / 2,676 -> 58 / 59 / 58, zero cells 0, days below the floor 0, first exercise
  changed on 0 days; costs 12,090 days lose an exercise (7,224 swaps), total minutes -0.32%, Calves -3,374 sets.
- **Golden (1,010 personas):** 939 keys change (bodyweight 212, home_dumbbells 238, basic_gym 217, full_gym 224, extra
  48). `lead_first_kill_switch_golden_test.dart`: with `disable_lead_first` set every persona equals main 9fc3b043's
  fixture (copied as `generator_golden_hashes_lead_first_off.json`). The loaded-wins OFF fixture was re-recorded with
  2A ON (939 keys change there too).
- **Whole-engine gate (`lead_first_gate_test.dart`):** 18,080 day-weeks with a budgeted row, 718 opened by a
  not-budgeted row; 0 budgeted rows at the lead + 2; 0 openers moved; kept worlds A 944 lead / 66 capped, B 768 lead /
  2 capped, never main.
- **Session-budget gate:** green with no change to its limits (`session_set_budget_gate_test.dart`), so d28's
  conditional raise was not needed: every overrun 2A adds is a day the gate already excuses (the count floor's forcing).
- **Timing:** `generateV4` over the 1,010 personas 52.2 s with the switch set, 52.8 s without (two runs each; +1%).
- **Week 2 (golden personas):** 29,940 -> 29,224 rows; rows left at the base cue (not gained) 27,950 -> 27,339;
  plans whose week 2 gained nothing (week 1's note) 382 -> 449.
- **Leads still under 3 sets (P3-1, `leadSeats`, the 2,304 grid, week 1, kept world):** 935 of 10,368; cause the
  clock 475, a group's cap or top 430 (Glutes 243, Back 130, Shoulders 51, Hamstrings 18, Chest 14, Core 4), none
  unexplained; by minutes 30: 463, 45: 182, 60: 148, 90: 142; by level beginner 627, intermediate 98, advanced 210.
  (The plan's 815 counts the dump's opener at 2 sets; `leadSeats` counts every kept-world lead, the capped world's
  included, so the two differ by definition.)

## Existing pins that moved (re-read one by one; none loosened without a measured reason)

- `session_set_allocator_behavioral_test.dart`: three crafted days re-recorded (the lead at 3; the focus cap of 12
  reached by five rows, one fewer); the 30-minute day is now count-forced 90 s over (A2 names `bi`); the seeded sweep
  excuses A2's documented 300 s on a `countForced` day.
  - The B review pinned the excused days exactly: 25 variant-days in 12 seed plans, 10.8 to 198 s over.
  - So a new forced day, or a deeper overrun, reddens.
- `session_set_budget_consumers_test.dart` and `session_set_budget_wiring_test.dart`: the same A2 excuse, per day and
  per the variant the week reads, each pinned exactly.
  - Consumers: 15 day-weeks of seed plans 16, 54, 55 and 57, 10.8 to 90 s over.
  - Wiring: 8 day-weeks, 10.8 to 75.6 s over.
- `exercise_count_band_behavioral_test.dart` (c): the forced 4th lift now 284.4 s over (was 76.8), inside 300 s.
- `oi489_timed_hold_real_engine_test.dart`: a count-forced day may take the 5 minutes; the Ruling 5c Upper Pull day is
  asserted never excused. The excused days are pinned exactly: Lower Body at 32.9 minutes in weeks 1-3, both goals.
- `allocator_timed_hold_eviction_behavioral_test.dart` (2 fixtures) and `rest_by_type_behavioral_test.dart` (e): run in
  the main world (`leadFirst: false`); their hand-worked arithmetic is main's and the guard / pricing they test is the
  same code in every world.
- `rest_by_type_behavioral_test.dart` (f): full_gym 5-day intermediate [6, 5, 6, 6, 6] (one row fewer).
- `plateau_rotation_behavioral_test.dart`: exact per-day deltas {w2d1: -1, w4d1: -1} replace the [0, 1] bound.
- `quads_floor_6day_behavioral_test.dart`: a 2A override layer (4 cells fall, the R2 hold named as the cap cause, 16
  switched-off cells), dead-override checks extended.
- `cross_day_variety_behavioral_test.dart`: shared Push A / B lifts 12 -> 10 (Dumbbell Fly gives its seat).
- `injury_recheck_v14_contract_test.dart`: the Hip Abduction Machine persona re-searched (full_gym advanced 4-day).
  Cause traced in the B review. The 3-day plan's Legs day holds five Glutes-crediting rows; at 2 sets each they fill
  the advanced Glutes session cap (10). R1 seats the lead (Barbell Back Squat) at 3, so the cap refuses Hip Abduction
  Machine, and Hanging Leg Raise takes the eighth seat (the D-2A-2 swap class).
- `same_movement_day_gate_test.dart`: the loaded-version floor 931 -> 719 (main 992; N19 633 -> 379), shared days 0.
- `injury_floor_sweep_lib.dart` `kThinCeilings`: see the next section.

## A plan claim the build disproved: kThinCeilings can rise

Plan section 3 said an injured user's thin day keeps at least main's rows, "so kThinCeilings cannot rise from R1-R3".
Measured: three blocks rose, all in `f_repeat_pairs30` (home_dumbbells 120 -> 121, basic_gym 94 -> 96, full_gym 21 ->
22; one-exercise days and empty days unchanged; every added day a lower_back + elbow pair). Probe: with the phase-1
pins generated with the switch set and phase 2 with the rule ON, all four blocks give exactly the old 60 / 120 / 94 /
21. So R3 holds inside a generation; a pinned repeat starts from the previous phase's plan, which 2A changed (a day
holding one exercise fewer pins one fewer). Same class as the recorded C2a decision (`repeat bodyweight` 0 -> 4).
Re-recorded at the measured counts with the cause; routed to unit 2B (the 3-exercise day floor, OI-452).

## Mutations (rule 21)

Scratchpad runner (`mut/run.py`): each mutant applied by an exact single-match replacement (asserted), the applied
change confirmed, `lead_first_allocator_behavioral_test.dart` (or the audit test) run, the source restored, every file
sha256-checked after the pass; a compile error is never counted as red (none compiled red).

First pass: 41 mutants, 37 red, 4 green. Each survivor got a fixture, and the four were re-run: all red.
- M08, the focus exemption applied in pass C as well. The old fixture could not see it, because pass D gives the
  same final sets whenever time is plentiful. New test: "pass C caps a focus row too" (a tight clock, so growth
  order decides; Triceps t2 4 vs 3). 1 red.
- M21, R1's fit check priced at 2 sets. The clock test asserted rows only. The mutant overruns, loses `acc`, and
  R3 falls back to the capped world, which reproduces main's rows. Added `leadWorld == 'lead'` to that test. 1 red.
- M22, the rank-0 reservation counting the later days' openers instead of their rank-0 rows. New test: "the
  reservation keeps room for the later days' RANK-0 rows" (day 5's fly would miss the Chest top; A falls to
  capped). 1 red.
- M28, R2 reading rank 0 in the capped world only. New test: "the capped world caps against the opener too"
  (b 5 vs 4). 1 red.

Red counts per mutant, from the first pass:
- M01 10, M02 2, M03 1, M04 2, M05 3, M06 1, M07 2, M09 2, M10 6, M11 5, M12 5, M13 3, M14 1, M15 1, M16 1,
  M17 3, M18 1, M19 1, M20 1, M23 2, M24 1, M25 2, M26 1, M27 2, M29 1, M30a 6, M30b 4, M31 1, M32 3, M33 6,
  M34 2, M35 1, M36 1 (`plan_audit_lib_test.dart`, the focus skip), M37 1, M38 1, M39 1, M40 10.
- The mutants cover:
  - R1: seat sets, the opener vs rank 0, the target count, the price, the reservation, eviction;
  - R2: +1, +2, rank 0, pass D, the C-only variants;
  - R3: each `worldIsWorse` term, the C branch, B's baseline and copy source, the whole-plan fallback, stats,
    the label;
  - `openerOf`: list order, comparator, holds, ties, the admitted fallback;
  - R5: rank 0, A vs B list, removed, budgeted-only, focus;
  - the kill switch: both arguments, the default;
  - the 6-day path.

Final file: 35 tests, all green. The gate test (`lead_first_gate_test.dart`) was not mutated separately. It pins
world counts and the lead + 2 / opener invariants over 1,010 personas, and M04/M05/M17 change exactly what it counts.
