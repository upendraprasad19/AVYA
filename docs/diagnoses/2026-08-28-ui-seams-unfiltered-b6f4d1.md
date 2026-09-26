---
bug_id: b6f4d1
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  A bodyweight-tier user tapping "swap" or "+ Add Exercise" mid-workout is
  offered all 259 library rows including Barbell Back Squat; the template builder
  shows the same unfiltered list; and the AI coach can swap them onto any
  exercise at all. Three of the four ship in the current APK.
concept: exercise_equipment_tier
sot_registry_entry: exercise_equipment_tier
writers:
  - file: lib/features/profile/screens/edit_profile_screen.dart
    method: _save (equipment_access / equipment_exclusions into userBox profile)
    line: 1686
  - file: lib/shared/repositories/plan_engine/training_history_analyzer.dart
    method: resolveCapabilityFromProfile (the shared derivation these seams read)
    line: 170
readers:
  - file: lib/features/train/widgets/exercise_swap_sheet.dart
    method_or_widget: _loadExercises
    line: 67
  - file: lib/features/train/screens/active_workout/exercise_picker_sheet.dart
    method_or_widget: _loadAllExercises
    line: 31
  - file: lib/features/train/screens/template_builder_screen.dart
    method_or_widget: _refresh
    line: 516
  - file: lib/core/services/swap_service.dart
    method_or_widget: swapExerciseInDay
    line: 170
hive_key_prefix: profile
hive_key_formula: "HiveService.instance.userBox.get('profile')['equipment_access']"
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns: [equipment_access, equipment_exclusions]
contract_test_path: test/contracts/ui_seam_capability_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [training_history_analyzer_capability_profile]
cross_account_guard: true
forbidden_patterns_checked:
  - pattern: "widget\\.equipment"
    absent: true
  - pattern: "getAll\\(\\)\\.take\\(30\\)"
    absent: true
proposed_fix: >-
  Give each of the four seams the user's capability set from one shared helper,
  resolveCapabilityFromProfile. The three list seams filter; SwapService refuses
  with a message naming the fix, because silently substituting a different
  exercise than the caller asked for is worse than saying no.
regression_test_planned:
  - test/contracts/ui_seam_capability_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Four seams filtered or guarded; 9 tests in ui_seam_capability_test.dart, 56 green across five capability suites; check_exercise_seams.dart holds at 33 sites; analyze reports no errors or warnings on lib/." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "No Hive write added. The helper READS userBox['profile'] equipment_access / equipment_exclusions / equipment_owned; Gate 19 _alwaysOk gained equipment_access and equipment_owned for the same heuristic mis-attribution equipment_exclusions already carried." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL in this commit." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads the swap or picker lists." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron drives a swap." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The AI coach swap_exercise tool reaches SwapService via tool_dispatcher; that path is now guarded at the service, not only in the UI, so a coach-driven swap is subject to the same check as a user-driven one." }
impact_analysis: >-
  Reach is every bodyweight user who ever taps swap or add-exercise, which is a
  core in-workout interaction rather than an edge path. Severity is bounded by
  the user having to choose the unusable exercise themselves rather than being
  prescribed it — but the swap sheet exists precisely because the prescribed one
  did not suit, so offering 259 rows including barbell work is the app failing at
  the moment the user asked for help. The SwapService path is worse: the AI coach
  can select the exercise on the user's behalf with no UI involved at all.
---

# The four exercise seams the compiler could not reach

## What was wrong

The generator seams take `capability` as a **required** parameter, so a missed
one fails to build. These four call none of those functions, so nothing
structural protected them:

| seam | state before |
|---|---|
| `exercise_swap_sheet.dart:67` | `repo.getAll()`, no filter of any kind |
| `exercise_picker_sheet.dart:31` | `getAll()` + customs, filtered on category and name only |
| `template_builder_screen.dart:516` | `getAll().take(30)`, `search()`, and customs — all unfiltered |
| `swap_service.dart:170` | no equipment check at all |

## The trap in seam 6

`ExerciseSwapSheet` already declared `final List<String>? equipment;`, accepted
it in the constructor, and read it **nowhere** — evidence someone intended this
fix and stopped. Filtering by that field is the obvious move and is **wrong**:
its only caller (`swap_sheets.dart:52`) passes
`currentExercise.equipmentNeeded`, the **outgoing** exercise's requirement. A
user swapping away from Chin Up would have been offered only pull-up-bar
exercises — the inverse of the intent. A separate `capability` parameter is added
and the old field kept, with a comment recording what it actually holds.

## Why seam 7's fix is not the obvious one

Filtering had to happen **before** `.take(30)`, not after. Filtering the first
thirty rows would leave a bodyweight user with a near-empty list; the cap belongs
on the filtered set. All three reads are covered — customs, the empty-query
default view, and search.

## Why seam 9 refuses instead of substituting

The caller asked for a specific exercise. Quietly giving them a different one is
worse than saying no, so the service throws `equipment_unavailable` with a
message naming the fix ("add it under Profile > Equipment"). This path is not
reachable through any sheet: the AI coach's `swap_exercise` tool drives
`SwapService` directly (`tool_dispatcher.dart:275`, `:588`), and
`WorkoutScheduleService.swapExerciseInDay` delegates here as well, so one check
covers both entry points.

## Recurrence

Seams 6 and 7 were found in review round 1, seams 8 and 9 in round 2 — the count
went 5 → 7 → 10 → 11 across four rounds, each finding one the last had missed.
That is a method failure, not a counting one, and it is why
`scripts/check_exercise_seams.dart` now pins the inventory by count so a twelfth
cannot arrive unnoticed. The gate corrected this author's own hand survey on its
first run, catching two sites that were `//` comments a plain grep had counted.
