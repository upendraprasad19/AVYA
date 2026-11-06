---
bug_id: c9a7e2
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  A bodyweight-tier user is prescribed Dead Hang (pull-up bar), Band Pull Apart
  (resistance band) and Chest Doorway Stretch (doorway) in the warm-up and
  cool-down of every generated day, and a bodyweight `recompose` user is given a
  jump-rope finisher twice a week. All four ship in the current APK.
concept: exercise_equipment_tier
sot_registry_entry: exercise_equipment_tier
writers:
  - file: lib/shared/repositories/plan_engine/warmup_cooldown.dart
    method: _timedExercise / _warmupExercise (PlannedExercise construction)
    line: 249
  - file: lib/shared/repositories/plan_engine/cardio_finisher.dart
    method: _finisherExercise (PlannedExercise construction)
    line: 223
readers:
  - file: lib/shared/repositories/plan_engine/plan_generator.dart
    method_or_widget: generateV4 (CardioFinisher.attach)
    line: 324
  - file: lib/shared/repositories/plan_engine/plan_generator.dart
    method_or_widget: generateV4 (WarmupCooldownSelector.attach)
    line: 334
  - file: lib/core/services/template_service.dart
    method_or_widget: buildFromTemplate (WarmupCooldownSelector.attach)
    line: 169
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/warmup_finisher_capability_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - pattern: "equipmentNeeded"
    absent: false
  - pattern: "case 'jump_rope':\\s*\\n\\s*return _jumpRopeFinisher\\(\\);"
    absent: true
proposed_fix: >-
  Populate equipmentNeeded on every PlannedExercise these two stages build, then
  filter both against the user's capability set under the SAME floor the injury
  filter already established. Give jump_rope the bodyweight degradation its four
  sibling cases already had.
regression_test_planned:
  - test/contracts/warmup_finisher_capability_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "warmup_cooldown.dart + cardio_finisher.dart declare equipment per move and filter on it; 11 tests in warmup_finisher_capability_test.dart, 56 green across six equipment/injury suites; flutter analyze reports no errors or warnings." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Both stages are pure functions over an in-memory WeekPlan. No Hive read or write added; the capability set arrives as a parameter." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill; no cloud row carries warm-up equipment." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads warm-up or finisher moves." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron generates plans." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "Warm-up and cool-down are generated client-side and never round-trip as equipment claims." }
impact_analysis: >-
  Every generated workout day carries a warm-up and cool-down, and the finisher
  lands on 2 days per week, so this reached every bodyweight user on every plan.
  The finisher half is goal-driven rather than equipment-driven: _defaultForGoal
  maps recompose to jump_rope and cardioGoalDefaultEnabled is default ON, so no
  user action was needed to trigger it. Severity is bounded by these being
  warm-up and finisher moves rather than working sets, but the trust cost is the
  same as the main-plan leak — the app said "no equipment needed" and then asked
  for a pull-up bar.
---

# Warm-up, cool-down and the cardio finisher were equipment-blind

## What was wrong

Two plan-engine stages prescribe into every generated day and neither consulted
the user's equipment:

- **`warmup_cooldown.dart`** gated exactly one thing — `_gymCardio`, behind
  `hasGymEquipment`. Everything else was unconditional, and three of its moves
  need equipment: `Dead Hang` (pull-up bar) and `Band Pull Apart` (resistance
  band) sit in the **advanced** dynamic-warm-up lists for `pull`, `upper` and
  `shoulders_arms`; `Chest Doorway Stretch` sits in three cool-down lists.
- **`cardio_finisher.dart:110`** — `case 'jump_rope': return _jumpRopeFinisher();`
  was the only one of five cases taking no equipment signal at all. Its four
  siblings each take `hasGymEquipment` and degrade to a documented bodyweight
  fallback. `_defaultForGoal` maps `recompose` to `jump_rope`, and
  `cardioGoalDefaultEnabled` is a `disable_`-keyed kill-switch, default **ON**.

The function's own docstring claimed the opposite — *"every token below is an
existing `_buildFinisher` case with a bodyweight fallback"* — false for precisely
the token that had none. That comment is corrected with the code.

## Why no existing guard caught it

`equipmentNeeded` was set **zero times** in either file. Every `PlannedExercise`
they built left the field null.

That matters more than it first appears. A capability oracle reading
`equipmentNeeded` is structurally **blind** to these stages — it would report a
clean plan while the warm-up carried a pull-up bar. And applying `canPerform`
naively would have been worse: it fails **closed** on an empty requirement, so it
would have deleted every warm-up move on every tier.

So the field had to be populated *before* any filter could be trusted. That
ordering is the fix, not a detail of it.

## The fix

`_moveEquipment` declares what each move needs; anything unlisted resolves to
`['bodyweight']`, never `[]`. Both construction sites set the field. All three
pools — cardio lead-in, dynamic warm-up, cool-down stretches — filter on
capability alongside the existing injury drop, under the **same floor** that
filter already established: if filtering empties a pool, a universally-safe
anchor is substituted rather than a bare day shipped.

`jump_rope` now degrades to the mini-HIIT bodyweight finisher when the user
cannot perform it, matching its four siblings.

## Recurrence

Same class as the main-plan leak this batch exists to close (OI-89): a stage that
emits exercises without consulting equipment. It is the **eleventh** such seam
found, and the fourth found by a review round rather than by design — which is
why `scripts/check_exercise_seams.dart` now pins the inventory by count so a
twelfth cannot arrive unnoticed.
