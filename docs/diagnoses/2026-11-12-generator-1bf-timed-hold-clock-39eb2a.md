---
bug_id: 39eb2a
date: 2026-11-12
batch: generator-step1-1bf
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-489: on a 30-minute advanced bodyweight plan the core-list picker hands each day more library timed rows ("holds")
  than the old picker did, and the allocator spent every hold's time before it seated any budgeted slot, so a later
  compound that would have given the WEEK its first credit for a major muscle was dropped for time alone:
  build_muscle|3|advanced|bodyweight|30|2 and |3 held 0 Chest sets in weeks 2 and 4 (the B Push day kept Isometric
  Lateral Raise, Hollow Body Hold, Standing Towel Pull Apart and Copenhagen Plank and dropped Elevated Pike Push Up,
  Hindu Pushup and Decline Push Up); lose_fat / general_fitness|3|advanced|bodyweight|30|1 held 0 Hamstrings sets in
  weeks 1-4 (Full Body B dropped Bodyweight Good Morning and kept Doorway Isometric Row and Hollow Body Hold).
  Found with it, by the session-budget gate once every goal ran on the core-list pool (Ruling 5c):
  lose_fat / general_fitness|4|advanced|bodyweight|30|1, the Upper Pull day ran 32.6 minutes against 30 + 2, because the
  empty-day guard forced its lead past a clock the holds had already spent. And (Ruling 12, founder d19): a hip-injured
  user's knee-dominant slot held only jump rows, so 3,189 day-weeks of the 15-pair grid opened with a jump row.
concept: session_set_budget
sot_registry_entry: |
  session_set_budget (docs/sot_registry.yaml) - amended by this unit (OI-489, Ruling 5 / 5c); behavioral test
  test/contracts/allocator_timed_hold_eviction_behavioral_test.dart, real-engine pin
  test/plan_generator/oi489_timed_hold_real_engine_test.dart.
contract_test_path: test/contracts/allocator_timed_hold_eviction_behavioral_test.dart
related_bugs: [cb50cb, d3b7f1, c3f9b2]
recurrence: |
  NOT a recurrence of a recorded bug. No diagnose names the hold-before-rank ordering: the B2 session_set_budget and
  OI-456 piece A / B diagnoses price a timed row at its own rest and count it toward the count band, and neither orders it
  against the rank. Nearest: cb50cb (a set refused because another credited group was at its top: the same allocator,
  the ledger side rather than the clock side) and d3b7f1 (the allocator's earlier count fix). Same family as OI-486 (a
  day's main lift starved; step 2). c3f9b2 is cited because its subject, the universal pool, is deleted by this unit;
  its contract test (universal_pool_mirror_test.dart) is deleted with both sides (Ruling 7), so c3f9b2's citations in
  the skills' bug-class tables are history from this unit on.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant step 1: every not-budgeted row's time (a library timed hold) is spent before pass A seats a budgeted slot", line: 223 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "evictFor (Ruling 5 / 5c): which holds ranked after a slot give way, guards (a)-(e), all or nothing, last first", line: 336 }
  - { file: assets/data/exercise_library.json, method_or_widget: "injury_contraindications of the 14 lower-body jump rows (Ruling 12, seed v25)", line: 1 }
readers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "pass A: refuses a slot that does not fit the clock; with Ruling 5 calls evictFor when the slot brings the week a first credit", line: 435 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "the empty-day guard: forces the lead; with Ruling 5c calls evictFor(d, pick.rank, ...) first", line: 481 }
  - { file: lib/shared/repositories/plan_engine/core_list_selector.dart, method_or_widget: "rankedPool hard filter (injury_contraindications), read through _pickCoreList / _selectCandidate", line: 322 }
hive_key_prefix: "schedule_<date>.exercises[] (workoutBox); plan_json.workouts[].exercises (the plan blob); exerciseBox rows (seed v25)"
hive_key_formula: "PlannedExercise.sets -> WorkoutDay.toMap exercises[].sets; exerciseBox[id].injury_contraindications"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); sets and names pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); the exercise library re-seeds from the bundle (v24 -> v25)"
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
cross_account_guard: "unchanged: generation writes through the existing plan writers (wrapUserScopedBox); the seed writes the shared exerciseBox."
forbidden_patterns_checked:
  - { pattern: "a hold that is the day's only credit for one of its groups given way (guard a)", absent: true }
  - { pattern: "a major or focus hold given way to a slot whose new credit has no major group (guards b, e)", absent: true }
  - { pattern: "a partial eviction that leaves the slot still refused (guard c, all or nothing)", absent: true }
  - { pattern: "a custom row, a row with no library match or a non-timed row evicted", absent: true }
  - { pattern: "the hip tag added by code (a second contraindication source) instead of the library data", absent: true }
proposed_fix: |
  Ruling 5 (OI-489): timed rows still spend their time first, so a day that is not starved is unchanged. When pass A
  refuses a budgeted slot on time alone AND the slot would give the week its first credit for one of its groups, the
  library holds ranked after it may give way, last first, under guards (a) never the day's only credit for one of its own
  groups, (b) a major hold only to a slot bringing a major, (c) decided before anything changes and only if together they
  make the slot fit, (d) never below SessionBudget.countFloor (A2 and selectorThin read the reach from before any
  eviction), (e) a focus hold only to a slot bringing a major (prototype H3).
  Ruling 5c: before the empty-day guard forces its lead past the clock, the holds ranked after the lead give way under the
  same guards minus the first-credit condition. One helper, evictFor, serves both callers; the guard passes pick.rank
  (the slot's index in its day).
  Ruling 12 (d19): the 14 lower-body jump rows that lacked `hip` gain it in the library data (seed v25; 5 E-rows through
  the importer's new injury-tag stage and its record scripts/data/library_injury_additions_v25.json, 8 G-rows plus
  G3582's table row through the builder's family floor, G3656 by hand), and Warmup / cooldown's Jumping Jacks and Jump
  Rope entries gain `hip`.
regression_test_planned: |
  test/contracts/allocator_timed_hold_eviction_behavioral_test.dart (Ruling 5 guards and Ruling 5c's group, including
  all or nothing, focus through the guard and a cap-forced lead); test/plan_generator/oi489_timed_hold_real_engine_test.dart
  (the four OI-489 keys and the two Ruling 5c keys on the real engine and library); test/scripts/library_media_importer_test.dart
  group "the injury-tag stage"; test/contracts/library_seed_v25_upgrade_behavioral_test.dart; the r6_removed_runs_* hard
  test asserts no Ruling 12 jump row in any hip-injured run.
impact_analysis: |
  Platform tier (plan engine). Every generated plan passes through the allocator; the change acts only on a day whose
  clock a hold has spent, and only for a slot bringing a first weekly credit (5) or a forced lead (5c). The seed bump
  touches the shared exercise library on every device (bundle-only; no cloud migration in this unit, the overlay copy is
  Unit 1B-F2, OI-495). The app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "session_set_allocator.dart evictFor + both call sites; seed_service.dart v25; warmup_cooldown.dart; flutter analyze clean; behavioral and real-engine tests green, mutants below red" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeded v24 -> v25 (library_seed_v25_upgrade_behavioral_test: a v24 box upgrades, the 14 rows carry hip, every other row byte-identical)" }
  - { layer: postgres_data, status: not_applicable, evidence: "no cloud write in this unit; the cloud exercise_library overlay copy is Unit 1B-F2 (OI-495), which waits on its own live-apply go" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged (sets and names only); the golden re-record attributes every changed key" }
---

## Root cause (OI-489, Ruling 5)

Measured with a probe on the four keys and a temporary print in the allocator (not committed). The picker is not the
cause: `_pickCoreList` picks Bodyweight Good Morning (E253) for the Hamstrings hinge and Hindu Pushup (G3662) and
Decline Push Up (E103) for the B Push day's chest slots. The writer is `SessionSetAllocator._variant`'s step 1, which
spends the time of every not-budgeted row (a timed hold) before pass A seats any budgeted slot in rank order; the
reader is pass A, which refuses a slot that does not fit the clock. On a 30-minute advanced bodyweight day the core-list
picker hands over more holds than the old picker (week 2, 216 days per world, holds per day: OFF 0:93 / 1:102 / 2:15 /
4:3 / 5:3, ON 0:39 / 1:82 / 2:57 / 3:31 / 4:7), so the clock was gone before rank 0. The OI's first hypothesis (the
Single Leg Glute Bridge `target()` filter) is superseded by this measurement.

## Ruling 5c (build finding)

`session_set_budget_gate_test.dart`, run with every goal on the core-list pool for the first time, failed its time zero
on `lose_fat` and `general_fitness|4|advanced|bodyweight|30|1`: the Upper Pull day held Doorway Isometric Row, Single Arm
Isometric Lat Pull, Doorway Isometric Curl and Hollow Body Hold (1,344 of 1,440 seconds) and its only budgeted slot,
Sliding Lat Pull (256.8 s), was refused; Back was already credited by the holds, so Ruling 5 let nothing go, and the
empty-day guard forced the lead past the clock (32.6 minutes). Main's allocator builds the identical day on the core
path; these goals never ran there before. With 5c, Single Arm Isometric Lat Pull gives way, Sliding Lat Pull grows to 3
sets, 29.6 minutes. Residue (pinned by two fixtures): a forced minor pick beside major holds, or a day at its floor,
still runs past the clock.

## Ruling 12 (founder d19)

Writer: the library tags (Jump Squat E193, Box Jump E066, Forward Jump G1472, Skater Hops G3361 carried only `ankle` /
`knee`); with a hip injury the knee_dominant pool held only jump rows and `CoreListSelector.rankedPool` keeps a
jump-only pool rather than empty the slot. Reader: `_pickCoreList` through `_selectCandidate`. Fixed in the data so the
contraindication contract keeps one source (14 rows, seed v25). The frozen-reference fixture
(`exercise_library_v12_row_hashes.json`) was re-recorded for exactly the five E-rows it hashes: E063, E065, E066, E193,
E202.

## Mutations (rule 21)

- Ruling 5, real engine (`oi489_timed_hold_real_engine_test.dart`): main's allocator (no eviction) reddens every OI-489
  expectation; guard (e) reverted to prototype H2 (`!bringsMajor` dropped) reddens the focus pin only.
- Ruling 5c: the guard's `evictFor` call removed reddens both 30 + 2 tests; 13 mutants over 5c, pass A and the shared
  helper's guards, all red (Task 2 record, plan section 9). The three round-18 tests (all or nothing, focus through the
  guard, cap-forced lead) each red under their own mutant.
- Ruling 12 / seed v25: the importer's injury-tag stage removed (5 red); a record `before` mismatch accepted ((c) red);
  the record ignored under `--check` ((b) red); `_exerciseLibraryVersion` set back to 24 (the v25 upgrade test red);
  G1472's table `hip` dropped (3 coverage and 8 importer tests red).
- queryV4 rules (Ruling 7, `query_v4_rules_behavioral_test.dart`): each of the four filters off and each of the three
  sort keys removed reddens its own test. The foundational sort key first survived: a Hive box iterates keys sorted, so
  the ids `P2F` < `P2NF` already gave the expected order; the ids now make key order the exact reverse of the expected
  order, with a precondition assert, and the mutant is red.

## Measured on the final tree

- 2,304-plan audit (no injuries) against live (main's OFF world), main ON and prototype H (`audit_1bq_d`, `audit_1bf_pH`):
  5 plans differ from H, every one Ruling 5c's (lose_fat / general_fitness|4|advanced|bodyweight|30|1,
  build_muscle|3|advanced|bodyweight|30|2 and |3, strength|3|advanced|bodyweight|30|1: a day of 32-34 minutes ends at
  29-30 with one hold fewer). Majors at 0 in weeks 1-3 where live has sets 0; weeks of 0 Hamstrings 0; zero cells newly
  against main ON 0; cells newly below live 6 in 4 plans (H's Biceps pair plus 5c's 4 Back cells, 1-2 sets); deepened 0;
  worse plans 3 (5c's); net set-weeks vs main ON Chest +10, Back -7, Shoulders +4, Quads +2, Hamstrings +16, Glutes +18,
  Core -107, Biceps +25, Triceps +10, Calves +4; minor zero cells vs live Triceps 308 / 86, Core 132 / 52, Biceps 116 / 36,
  Calves 18 / 9 (OI-496, d14); 0 empty days over 41,472 day-weeks; `iso_first` 12 -> 0 with the built type.
- Golden (1,010 personas): every one of the 998 previous keys equals main's pre-flip ON world, prototype H3 and the flip
  + 5c snapshot: Rulings 5, 5c and 12 change no golden key; 12 exclude-everything keys added.
- Focus grid (5,760 plans): 70 of 103,680 lines differ from H3's dump, all in the 5 Ruling 5c keys.
- Core-list gate (1,036 personas): green; report regenerated (`emergencyAnyLevel` 0 personas; the 576-run sweep 16
  runs, no retired / skill / olympic pick in its built lists).
- CI hard test (2,637 runs): 0 empty, 0 flagged, 0 hip jump rows; thin / one-exercise r9 284 / 16, ext 182 / 6.
