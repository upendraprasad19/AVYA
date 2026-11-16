---
bug_id: f3c9a6
date: 2026-11-16
batch: generator-step3c
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-396 (step 3C of the generator overhaul). Every Cut (lose_fat) and Maintain (general_fitness) plan day carried a
  cardio finisher (`WorkoutDay.finisher`) that no screen showed. It took no injuries, so a knee-injured user was given
  Burpees and Jump Squats. Its time was not reserved: the allocator filled the whole session with lifts, and the
  finisher ran past the user's minutes. A second defect was found while tracing the writers: Edit Profile's reschedule
  (`generateAndScheduleFromDate`) did not write the `finisher` key, so the same plan carried a finisher or not depending
  on which writer scheduled it (writer drift).
concept: cardio_finisher_shown
sot_registry_entry: cardio_finisher_shown
contract_test_path: test/contracts/cardio_finisher_shown_pure_test.dart
related_bugs: [b7a4e2, c9a7e2, d30de7]
recurrence: |
  The reschedule half is a recurrence of the writer/reader drift class (feedback_writer_reader_field_drift_recurring.md,
  bug class 1): two writers of `schedule_<date>`, one of them never taught a key the other writes. The known-good fix is
  applied (both writers emit the key; a behavioral test compares their output, "the writers keep the finisher"). The
  finisher itself has two prior diagnoses: b7a4e2 (`hasGymEquipment` always false on the generated path, WU-2) and
  c9a7e2 (warm-up and finisher blind to equipment, OI-89). Neither covered injuries, display or time. d30de7 (the
  library injury re-check) set the tags the injured rule leans on. Bug-history lookup (CLAUDE.md 4.1.5): grep of
  docs/diagnoses for "finisher", "CardioFinisher", "OI-396", "generateAndScheduleFromDate" and "shortenDay"
  (token and concept): the hits are the three above plus f19a7c / a4f7e1 / 280c4d / e2d6b8, which mention the finisher
  in passing only.
writers:
  - { file: lib/shared/repositories/plan_engine/cardio_finisher.dart, method_or_widget: "CardioFinisher.plan (decided before sizing; FinisherPlan.secondsByDay) / attach(plan:)", line: 68 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4: the plan call, SessionBudgetContext.finisherSecondsByDay, attach(plan:) (rule-14 waivers d56 / d61 / d75 / d76)", line: 305 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "generateAndSchedule and generateAndScheduleFromDate write the `finisher` key (the second was the drift)", line: 595 }
  - { file: lib/features/ai_coach/services/hotel_workout_planner.dart, method_or_widget: "plan copies workout.finisher", line: 211 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "shortenDay removes the key when it writes the row (d79)", line: 719 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_saveCoachInjuryToProfile writes a coach injury into profile['injuries'] (d77 / d78)", line: 701 }
readers:
  - { file: lib/shared/repositories/plan_engine/finisher_safety.dart, method_or_widget: "FinisherSafety.shownFinisherMaps / shownOfRow / isInjured (the one read rule)", line: 20 }
  - { file: lib/shared/repositories/plan_engine/finisher_show_context.dart, method_or_widget: "FinisherShowContextReader.read (switch + profile; fails closed)", line: 1 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "workoutDayForDate and CurrentPlanNotifier build: WorkoutDayData.finisher / finisherSeconds / budgetMinutes", line: 769 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "homeCardMinutes(schedule, finisher:)", line: 1 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "BudgetLedger day budget minus SessionBudgetContext.finisherSecondsOn(day)", line: 1 }
  - { file: lib/features/train/screens/active_workout/screen.dart, method_or_widget: "FINISHER section (finisher_section)", line: 799 }
hive_key_prefix: "workoutBox schedule_<date>['finisher'] (list of exercise maps); userBox profile['injuries'] (read; the coach now writes it); configBox['disable_cardio_finisher_shown']"
hive_key_formula: "PlannedExercise.toMap() per finisher item, the plan's FinisherPlan.exercises; the HIIT's last item stores rest_seconds 60 (the round rest)"
sync_methods:
  - "SyncService plan push (user_progress.plan_json carries the days' finisher maps, unchanged shape); scheduled_workouts carries no content keys"
  - "profile push of injuries (unchanged path; the coach writer uses ProfileWriteService.patchProfileWith)"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); a stored plan made before 3C keeps its finisher and is read through the same rule (plan section 2.4)"
cloud_table: user_progress
cloud_columns:
  - plan_json
  - user_profile.injuries
  - user_profile.coach_extraction_locked_fields
ist_handling:
  - { file: lib/features/train/screens/active_workout/warmup_cooldown_section.dart, method_or_widget: "the FINISHER tick key warmup_checks_<IST today>_finisher, istDateStr like the warm-up", line: 38 }
provider_invalidations:
  - "ToolDispatcher.execute: a coach injury saved to the profile invalidates the profile providers (and the workout providers on the all-swaps-failed outcome) BEFORE the failure early return"
telemetry_op_types:
  success: []
  failure: [tool_dispatch_coach_injury_profile_write]
cross_account_guard: "The coach profile write captures HiveUserSession.currentOwnerFullId at handler start and passes stillOwner to ProfileWriteService.patchProfileWith, which refuses when the owner changed (test: an owner captured before the swap loop that no longer matches writes nothing). Generation and display read user-scoped boxes through the existing wrappers."
forbidden_patterns_checked:
  - { pattern: "a build_muscle or strength golden persona that changes (1,010 personas, finisher_attribution_golden_test (2))", absent: true }
  - { pattern: "an output change with disable_cardio_finisher_shown set (1,010 golden personas equal main 862f0bc2)", absent: true }
  - { pattern: "a finisher day below the count floor (2,304-plan cost table on the built tree)", absent: true }
  - { pattern: "a jumping finisher for an injured run, or any finisher at home for one (injury sweeps a-f, the finisher scan)", absent: true }
  - { pattern: "a screen or minutes reader that reads schedule_<date>['finisher'] without FinisherSafety", absent: true }
  - { pattern: "plan_generator.dart changed outside the waived lines (d56 / d61 / d75 / d76)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-16-generator-step3c-cardio-finisher.md (rev 7, six review rounds, founder 2026-10-22 and
  d56, d61, d74-d79). Engine: CardioFinisher.plan decides the finisher before sizing (any injury -> only Stationary
  Bike Sprints with gym cardio, none without; under 60 resolved minutes the 4-minute mini HIIT; the HIIT stores its
  round rest), and SessionBudgetContext.finisherSecondsByDay takes its time from those days only. Display: one pure
  read rule (FinisherSafety) behind every screen and every minutes reader (a required `finisher:` argument), the
  FINISHER section on the active workout, Train's expansion and the preview sheet; shortenDay drops the finisher first.
  Writers: the reschedule writer and the hotel planner write the key. Coach: a confirmed modifyWorkoutForInjury adds
  its canonical token to profile['injuries'] (the read rule's only signal) and locks the field; the diff preview and
  the confirm card say so. Kill switch disable_cardio_finisher_shown (default ON).
regression_test_planned: |
  test/contracts/cardio_finisher_shown_pure_test.dart (30: isInjured, the read rule table, detail / minutes label, the
  plan's shapes, pricing parity, the coach mapping and patch, the confirm card's executed line);
  test/contracts/cardio_finisher_reservation_behavioral_test.dart (12, the real generateV4: shapes, d74 / d76, the
  reservation, the positive control, Build unchanged, phases 1 / 4 / 5);
  test/contracts/finisher_display_behavioral_test.dart (14: Train == Home, the profile rule, the switch, the reader
  failing closed, shortenDay d79, the two writers, a day swap carries it, the session never logs it);
  test/contracts/coach_injury_profile_write_behavioral_test.dart (11, the real ToolDispatcher.execute);
  test/features/train/finisher_sections_test.dart (6), test/ai_coach/injury_modify_diff_adds_line_test.dart (5);
  test/plan_generator/finisher_kill_switch_golden_test.dart, finisher_attribution_golden_test.dart; the injury sweep's
  finisher scan (test/helpers/injury_floor_sweep_lib.dart).
impact_analysis: |
  Platform tier (plan engine, display, coach). Cut and Maintain plans change: their finisher days give the finisher's
  time to it (240 / 540 / 480 / 240 s), so those days hold fewer sets, and some muscle-weeks go to 0 under 60 minutes
  (d76's accepted cost, table below). Build and strength plans are byte-identical. Every user who has a stored plan sees
  its finisher (uninjured) or the bike / nothing (injured) after the update; the day's minutes now include it. The app
  is not live; testers regenerate. The model-facing tool descriptions change only after the ai-proxy deploy (founder go).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "cardio_finisher, plan_generator (waived lines), session_budget, session_estimate, finisher_safety, finisher_show_context, train_provider, home_screen, swap_service, workout_schedule_read_service, hotel_workout_planner, tool_dispatcher, injury_vocab, coach_injury_profile, the diff preview and confirm card, the active workout and Train sections; flutter analyze --no-fatal-infos clean; mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "schedule_<date>['finisher'] written by both schedule writers and read through FinisherSafety on real Hive rows (finisher_display_behavioral_test); profile['injuries'] written by the coach through patchProfileWith on real Hive (coach_injury_profile_write_behavioral_test); the switch read through PlanEngineFlags" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration: the finisher lives inside plan_json, whose shape is unchanged; injuries and the lock list already exist (migration 148)" }
  - { layer: edge_function_code, status: fixed_in_this_batch, evidence: "the modifyWorkoutForInjury and shortenWorkout tool descriptions (model-facing text only); deno check of both and ai-proxy/index.ts clean; 290 _shared/tools Deno tests pass; deployed only on the founder's go" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the main golden re-recorded with per-class attribution (410 keys, all Cut / Maintain); the OFF fixture equals main" }
---

## Root cause

- **Not shown, not safe, not timed.** `CardioFinisher.attach` ran at Stage 7, after the allocator had sized every day
  to the user's minutes, took no injuries and wrote `WorkoutDay.finisher`. No screen read it.
  - Writer: `CardioFinisher.attach` (`cardio_finisher.dart`), called from `generateV4`.
  - Readers: none on screen; the minutes readers (`budgetedDaySeconds`, `homeCardMinutes`, `shortenDay`) priced the
    lifts only.
- **Writer drift.** `generateAndSchedule` copied `workoutDay.finisher` into `schedule_<date>`;
  `generateAndScheduleFromDate` (Edit Profile's reschedule) built the same row without the key. A reader added for 3C
  would have shown the finisher on some plans and not on others with the same profile.

## Fix

See `proposed_fix`. The plan's section 2 has the design; the decisions are d56, d61, d74-d79 on the board.

## Measured on the built tree

- **OFF.** With the switch set, the 1,010 golden personas equal main 862f0bc2 (`finisher_kill_switch_golden_test`,
  fixture `generator_golden_hashes_finisher_off.json`).
- **Golden.** 410 of 1,010 keys change: lose_fat 240, general_fitness 170, nothing else. The attribution test splits
  the cause:
  - (1) with the finisher's time not reserved (`CardioFinisher.debugReserve = false`), ON and OFF differ only in each
    day's `finisher` maps;
  - (2) with it, every build_muscle and strength persona equals OFF; of the 3,123 changed days, 2,610 carry the
    finisher and 513 do not (the allocator's weekly ledger is shared across the week's days).
  Re-recorded with that attribution in the golden test header.
- **Cost table** (the plan's section 2.2, re-run on the built tree: Cut / Maintain x 3-6 days x 3 levels x 4 tiers x
  phases 1-3, uninjured; week 1's finisher days; a muscle-week is a library primary muscle trained OFF in a week 1-3
  with 0 sets ON):

  | Goal, minutes | finisher days | fewer exercises | below the count floor ON / OFF | exercises ON / OFF | muscle-weeks at 0 | sets lost on finisher days |
  |---|---|---|---|---|---|---|
  | Cut 30 | 288 | 0 | 0 / 0 | 4.00 / 4.00 | 228 | 286 |
  | Cut 45 | 288 | 113 | 0 / 0 | 5.34 / 5.74 | 84 | 393 |
  | Cut 60 | 288 | 66 | 0 / 0 | 6.02 / 6.28 | 30 | 645 |
  | Cut 90 | 288 | 0 | 0 / 0 | 6.28 / 6.28 | 0 | 30 |
  | Maintain 30 | 288 | 0 | 0 / 0 | 4.00 / 4.00 | 216 | 279 |
  | Maintain 45 | 288 | 96 | 0 / 0 | 5.38 / 5.72 | 66 | 318 |
  | Maintain 60 | 288 | 45 | 0 / 0 | 6.02 / 6.20 | 30 | 340 |
  | Maintain 90 | 288 | 0 | 0 / 0 | 6.20 / 6.20 | 0 | 12 |

  Equal to the prototype's short-finisher table the founder chose from (d76), except sets lost at Maintain 30 / 45 / 60
  (277 / 317 / 337 on the prototype; 2-3 sets more here). No finisher day is below the count floor.

## Every red on the built tree, with its cause

Each was run on the built tree before any expectation moved. Rule (plan section 3): a gate that measures ANOTHER unit
runs both of its worlds with `disable_cardio_finisher_shown` set and prices no finisher (no screen shows one in that
world); a fixture that names an older main sets the switch on its OFF side; a digest of the live engine is re-recorded.

- **Kill-switch goldens** (`goal_training`, `balanced_week`, `lead_first`, `loaded_wins`) and `day_floor_kill_switch_test`:
  their OFF worlds predate 3C; they set the switch and equal their fixtures.
- **`goal_training_gate_test`** (3A): with the finisher, `identical OFF` went 92 -> 104 and the Strength focus grid's
  main lifts 29,010 -> 28,634 (the reserved time removes lifts on finisher days, in both of its worlds). It measures 3A,
  so both worlds set the switch; every recorded number and digest holds again.
- **`weekly_minimum_gate_test`** (2C-b): same rule, both worlds set the switch.
- **`oi489_timed_hold_real_engine_test`, Ruling 5c**: with the 240 s mini HIIT on days 0 and 2 of the 4-day 30-minute
  Cut / Maintain plan, the count floor force-seats the Upper Pull day (never below the floor; d76's cost). The test pins
  Ruling 5c (OI-489) at exact minutes, so those two tests set the switch.
- **`session_estimate_display_test`**: its two source pins were repointed to the new call shapes
  (`homeCardMinutes(schedule, finisher: ...)`, `budgetedDayMinutes(row, finisher: shownFinisher)`), never loosened.
- **The main golden**: re-recorded (above).
- **Gate 19** (`check_hive_map_field_drift`): `profile_injury_added` is a tool RESULT key, not a Hive field; allowlisted
  with that reason.
- Live gates that price the day take the stored finisher (`session_set_budget_gate_test`, `quads_floor_6day`,
  `plan_audit_dump_test`, `repeat_minutes_gate_lib`): green.

## Mutations

Each mutant was applied once by a script (anchor found, applied count checked, compile clean), run, and restored; the
script compares a sha256 of the file before and after. Red counts per test file:

| Mutant | Red |
|---|---|
| M1 the injury rule ignored (`CardioFinisher.plan`) | pure 1, reservation 3; injury sweep e: 4 (every tier) |
| M2 the injury rule inverted (home gets the bike, gym none) | pure 2, reservation 3 |
| M3 nothing reserved (`secondsByDay` empty) | pure 1, reservation 1 |
| M4 reserved on every day | pure 1, reservation 0, then 1 (see below) |
| M5 `generateV4` passes no finisher seconds to the context | reservation 1 |
| M6 the read rule ignores injuries | pure 2, display 3 |
| M7 the display ignores the switch | pure 1, display 1 |
| M8 Train's constructor reads no finisher | display 4 |
| M9 the reschedule writer drops the finisher (the drift) | display 1 |
| M10 `finisherSecondsOfPlanDay` drops the rest term | pure 2 (pricing parity) |
| M11 `shortenDay` keeps the finisher key (d79) | display 3 |
| M12 the profile invalidation only on success | coach 0, then 1 (see below) |
| M13 the switch dropped from the OFF golden | `finisher_kill_switch_golden_test` 1 |
| M15 `startWorkout` copies the finisher into the session | display 1 ("the session never logs the finisher") |

(pure = `cardio_finisher_shown_pure_test`, reservation = `cardio_finisher_reservation_behavioral_test`, display =
`finisher_display_behavioral_test`, coach = `coach_injury_profile_write_behavioral_test`.)

**M4 survived the first run** in the behavioral file: the only test of "a non-finisher day keeps its budget" used Build
plans, which carry no finisher. A first replacement (a per-day line) stayed green too, because the count floor's
forcing bound sits above it. The kept test compares each non-finisher day of 15 Cut plans with the same day in the
switch-set world: mean loss under 120 s (measured on the tree), red under M4. **M12 survived** because the
all-swaps-failed test checked Hive, not the provider; it now reads `userProfileProvider` before and after.

## B-pass

The B-pass runs on the CI-green PR head (`docs/reviews/generator-step3c-bpass.md`); its findings and fixes are recorded there and in the review commit.
