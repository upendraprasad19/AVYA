---
bug_id: d4b8e1
date: 2026-10-21
batch: l2-no-custom-autoadd (Batch 0a; repair of existing plans = Batch 0b, docs/plans/2026-10-21-l2-custom-repair.md)
status: fixed
blast_radius: platform
tier: full
symptom: |
  Founder (web app, logged in as upendraprasad19, 2026-10-21): today's
  "Upper push + core" workout listed 14 exercises / 56 sets — 8 library picks
  plus 6 of his own custom exercises (tuck planche, Barbell Planche Hollow Press,
  Cable Pull Down, L Sit, Elbow Lever, Single Leg Back Lever). Cloud
  user_progress.plan_json.schedules (Phase 4, plan_start 2026-10-12): every push
  day 8 + 6 customs (56-66 sets), every pull day 8 + 2, every leg day 8 + 1.
  Every Phase-3 day before 2026-10-12 had 8 — the customs were created
  2026-09-14 .. 2026-10-02, after Phase 3 was generated.
concept: generator_no_custom_autoadd
sot_registry_entry: generator_no_custom_autoadd
related_bugs: [e7b2d4]
recurrence: |
  Not a recurrence. docs/diagnoses/INDEX.md has no prior record of the
  generator appending customs (grep: custom append / L2 / supplement /
  too many exercises / custom in plan). Related: e7b2d4 (2026-09-17, customs
  invisible in the swap picker) — its fix made the creation sheet store
  primary_muscles, which made customs ELIGIBLE for L2 (the sheet's own comment
  said so: "re-arms the plan-generator supplement path"). L2 itself was always
  uncapped. Class: an additive post-pass with no cap and a substring match.
writers:
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method: "pickV4 post-pass gate (was phase >= 2 && (demoted || customs); now demoted only)", line: 634 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method: "_applyHistoryAdjustments (L2 block removed; L6 kept)", line: 853 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method: "buildPinnedDays custom fallback (unchanged; the only remaining custom emitter)", line: 740 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "generateAndSchedule → upsertScheduled per generated day", line: 280 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "currentPlanProvider (Train tab day list)", line: 993 }
  - { file: lib/shared/repositories/plan_engine/training_history_analyzer.dart, method_or_widget: "demotedExercises (L6 input, unchanged)", line: 316 }
hive_key_prefix: "schedule_ (rows written by generateAndSchedule; no new key)"
hive_key_formula: "unchanged: 'schedule_' + istDateStr(date)"
sync_methods: [pushWorkoutPlanForSyncDomain, syncWorkoutData]
restore_methods: [_restoreWorkoutPlan, mergeScheduleBundleIntoHive]
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: test/contracts/l2_no_custom_autoadd_behavioral_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 88, fn: istDateStr }
provider_invalidations: [currentPlanProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a: pure selection change; customs are read from the user-scoped customBox (HiveUserSession) only by buildPinnedDays, unchanged"
forbidden_patterns_checked:
  - { pattern: "getCustomExercises( in exercise_selector.dart outside buildPinnedDays", absent: true }
  - { pattern: "_eligibleCustomExercises as a CODE symbol in lib/ or test/ (comments and one reason: string still name it as history)", absent: true }
  - { pattern: "a custom name in any generated day at phase 1-4 (behavioural, l2_no_custom_autoadd_behavioral_test)", absent: true }
proposed_fix: |
  Founder decision 2026-10-21: "never auto-add customs". Removed the L2 block in
  _applyHistoryAdjustments, its `customs` parameter and both call-site
  arguments, the `customs` local in pickV4 and _eligibleCustomExercises. The
  post-pass gate is now `phase >= 2 && demoted.isNotEmpty`, so L6 (demote a lift
  the user swapped away from) runs exactly as before. _buildCustomExercise and
  _muscleTokens stay (buildPinnedDays). Customs reach a plan only through an
  explicit action (swap sheet, add picker, template builder, coach
  swapExercise) or as a repeat pin of such a choice.
  §4.6 waiver: no kill switch — the removed path IS the defect, a switch would
  keep it reachable, and §4.6 step 4 deletes the old path anyway. Revert = git
  revert of the merge.
  NOT fixed here (Batch 0b, separate branch): plans ALREADY generated keep their
  customs (only upendraprasad19 in cloud: 16 planned days from 2026-10-21), and a
  REPEAT phase advance re-pins names from the finished phase's rows. 0b adds a
  one-time post-restore repair of future planned rows + a read-side strip of
  repeat pins.
regression_test_planned:
  - test/contracts/l2_no_custom_autoadd_behavioral_test.dart
impact_analysis: |
  Every user with a custom exercise who reaches a new phase (2+) gets a plan of
  library picks only — session length returns to the volume filter's target
  (VolumeFilter.targetCount) instead of target + every matching custom. Users
  without customs: byte-identical (customs was empty, the gate reduced to the
  demoted check). Repeat-phase pins and explicit swaps/adds unchanged.
  Pre-launch: testing accounts only (CLAUDE.md §1); cloud check found customs
  inside a plan for one user (the founder).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/shared/repositories/plan_engine/: no issues; l2_no_custom_autoadd_behavioral_test 4/4 green; 11 neighbouring test files (exercise_selector greps, custom-exercise contracts, exercise_seam_lib_test) 72/72 green" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "behavioural test seeds 4 customs in the user-scoped customBox and a swapped_from schedule row in workoutBox; generated phases 1-4 contain no custom; L6 still demotes the swapped-away lift" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "2026-10-21 query of user_progress.plan_json.schedules joined to user_custom_exercises: only upendraprasad19 has customs in a plan (16 future planned days, 2 completed template days); repair is Batch 0b" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no server-side plan generation touches customs (supabase/functions grep, review round 1)" }
  - { tier: 12, name: "Client to server contract", status: verified, evidence: "generated rows reach plan_json via the existing pushWorkoutPlanForSyncDomain; no payload shape change" }
mutation_proven:
  mutated: "exercise_selector.dart replaced by its origin/main version (L2 present; grep -c 'L2: append eligible customs' = 1), file restored byte-identical afterwards (cmp)"
  result: "3 of 4 tests RED: (1) leaked {My Tuck Planche, My Elbow Lever, My Back Lever, My Jump Squat}; (2) phase 3 leaked the same four; (4) its no-custom assertion. (3) phase 1 stays green by design (L2 never ran at phase 1). Second mutation (B-pass finding 5): L6's `result[i] = replacement;` replaced by a comment → test (4) RED on its L6 assertion, 3 others green — so (4) proves L6 survived the removal."
  confirmed_applied: "grep -c before/after (L2 marker 1 -> restored 0; L6 replacement line 1 -> 0 -> restored 1) + cmp of the restored file each time"
---

## Summary

The plan generator no longer adds a user's custom exercises to generated days.
A founder's Phase-4 push day had grown from 8 to 14 exercises (56 sets) because
every custom exercise he had created matched some muscle on the day.

## Root cause

Lever L2 (2026-05-31) in `ExerciseSelector._applyHistoryAdjustments` appended,
at phase >= 2, every custom whose `primary_muscles` substring-matched any slot
`targetMuscle`/`subFocus` of the day: no cap, no level or skill filter, no
movement-pattern match (Cable Pull Down and Single Leg Back Lever landed on push
days; tuck planche on back day). It was dormant for most users until e7b2d4
started storing `primary_muscles` on customs.

## Fix

L2 removed; L6 kept. See `proposed_fix` (incl. the §4.6 waiver).

## Not in this batch

Existing polluted plans and the repeat-pin re-materialisation are Batch 0b
(`docs/plans/2026-10-21-l2-custom-repair.md`), split per §4.12.1 after two
review rounds surfaced material issues only in the repair half.

## Known limits

- An old app build keeps running L2 until updated (web deploy and AAB roll
  independently).
- `plan_generator.dart:133` still mentions "L2 custom-append" in a comment.
  Deliberately not edited: root rule 14 forbids touching `plan_generator.dart`
  without explicit founder instruction, and a comment does not change behaviour.
  `plan_engine_flags.dart:160` (edited) now differs from it on that one word.
- `buildPinnedDays.resolve()` re-applies equipment-exclusion and injury to a
  pinned name, not the OI-89 capability check (true before this batch too;
  recorded on OI-211, which tracks custom-exercise capability).
