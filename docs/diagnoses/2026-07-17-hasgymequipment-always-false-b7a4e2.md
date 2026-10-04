---
bug_id: b7a4e2
date: 2026-07-17
batch: wu2-gym-cardio-gate
status: fixed
blast_radius: platform
symptom: >
  On every GENERATED workout plan, gym users (basic_gym / full_gym) NEVER received
  the gym-cardio warmup moves (_gymCardio: Jump Rope / Cycling (Stationary) /
  Running (Treadmill)) or the gym finisher variants (Treadmill Intervals /
  Stationary Bike Sprints) — always the bodyweight fallbacks (Spot Jogging / High
  Knees). Cause: WarmupCooldownSelector.attach (:141) + CardioFinisher.attach (:28)
  compute `hasGymEquipment = equipmentList.any((e) => e.contains('gym') ||
  e.contains('full'))`, but on a generated plan `equipmentList = _getEquipmentList
  (tier)` = ITEM tokens (none/bodyweight/dumbbells/…) which contain neither 'gym'
  nor 'full' → hasGymEquipment is ALWAYS FALSE. Path-scoped: the custom-template
  path passes the tier STRING ['full_gym'] where the predicate is correctly TRUE,
  so only the GENERATED path was affected.
concept: equipment_exclusion_filter
sot_registry_entry: >
  Extends the equipment_exclusion_filter concept (⑥ B1/C1) to the WU-2 warmup/cardio
  stage. generateV4 computes a flag-gated hasGymEquipment override from the EFFECTIVE
  (exclusion-subtracted) equipment (`cardio machine`, added to the gym tiers in ⑥ C2,
  gates the gym-cardio pools) and passes it to both attach methods; a null override
  (tier-string callers: template_service, tests) keeps the old predicate. Not a new
  concept — a writer/reader-drift fix within the existing equipment contract.
writers: >
  lib/core/utils/equipment_vocab.dart — tierItems: `cardio machine` ADDED to
  basic_gym + full_gym (the token that gates the gym-cardio pools). lib/shared/
  repositories/plan_engine/plan_generator.dart — generateV4 (~:195) computes
  `hasGymOverride = enable_equipment_exclusions ? effectiveEquip.contains('cardio
  machine') : null` (effectiveEquip = equipmentList minus equipmentExclusionSet) and
  passes it to CardioFinisher.attach (:196) + WarmupCooldownSelector.attach (:205).
  warmup_cooldown.dart + cardio_finisher.dart — attach() gains an optional
  `bool? hasGymEquipmentOverride` (null → the OLD predicate → byte-identical;
  non-null → use it). Gated on PlanEngineFlags.equipmentExclusionsEnabled (ship-dark,
  the same flag as C1).
readers: >
  WorkoutDay.warmup / WorkoutDay.finisher (models.dart) — the warmup/finisher arrays
  now include a gym-cardio move for gym users (flag ON), rendered by the Active
  Workout warmup/finisher section. Consumed via the schedule-row JSON (Hive-row-local;
  no cloud column). Unchanged shape; this fix changes WHICH moves populate them.
hive_key_prefix: schedule_
hive_key_formula: "schedule_<yyyy-mm-dd> — warmup/finisher ride inside the schedule_* row's warmup/finisher arrays (WorkoutDay.toMap). This fix changes WHICH moves populate them (a gym-cardio variant for gym users, flag ON), not the key."
sync_methods: >
  syncScheduledWorkouts / _syncWorkoutPlan embed the warmup/finisher arrays in
  user_progress.plan_json.schedules (scheduled_workouts has no warmup/finisher
  column). This fix changes the array CONTENTS only; no new sync surface.
restore_methods: >
  _restoreWorkoutPlan applies plan_json.schedules. No new restore path; a
  re-generation on a restored profile re-computes the signal via the same seam.
cloud_table: user_profile
cloud_columns: >
  n/a — no column added by C2 (reuses C1's equipment_exclusions text[] for the
  exclusion subtraction). backups/live_schema_columns.json unchanged by C2.
contract_test_path: test/contracts/wu2_gym_cardio_gate_behavioral_test.dart
ist_handling: >
  n/a — no date key; warmup/finisher durations are static.
provider_invalidations: >
  n/a — plan (re)generation invalidations fire on the downstream write path, unchanged.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a to change — generateV4 reads the exclusion set via the C1 central-read
  (user-scoped, guarded); warmup_cooldown/cardio_finisher are pure functions over the
  passed-in signal. No new box access.
forbidden_patterns_checked: []
proposed_fix: >
  Add `cardio machine` to the gym tierItems (the token the gym-cardio pools need).
  Add an optional `bool? hasGymEquipmentOverride` to both attach methods (null → the
  old predicate, so template_service + the tier-string tests are byte-identical). In
  generateV4 compute the override flag-gated from the effective (exclusion-subtracted)
  equipment and pass it to both attach calls. Gated on enable_equipment_exclusions
  (ship-dark). Net: gym users get gym cardio (flag ON), excluding cardio machine
  removes it; flag OFF is byte-identical (the always-false old predicate on the
  generated path).
regression_test_planned: >
  test/contracts/wu2_gym_cardio_gate_behavioral_test.dart (Hive + real library, via
  generateV4, 5-day week so the gym-cardio pool rotation surfaces) — the SOLE proof
  since the Batch-0 scorecard scores only main exercises: flag ON + full_gym → a
  gym-cardio warmup move + (general_fitness) the Stationary Bike Sprints finisher;
  flag ON + exclude cardio machine → bodyweight cardio; flag OFF → NO gym cardio
  (byte-identical). shared_contracts_test.dart:825 (tier-string attach) stays green.
touched_layers_checked:
  - "tier: 1_client_code, status: fixed_in_this_batch — equipment_vocab.dart + plan_generator.dart + warmup_cooldown.dart + cardio_finisher.dart edited; flutter analyze clean."
  - "tier: 2_hive_local_state, status: fixed_in_this_batch — wu2_gym_cardio_gate_behavioral_test.dart seeds the real library + asserts the generated warmup/finisher arrays; 3/3 green; shared_contracts_test 126/126 green (no tier-string regression)."
  - "tier: 3_postgres_schema, status: verified — no column added by C2 (reuses C1's equipment_exclusions); the Batch-0 scorecard is unaffected (keys off equipment_tier, not the item list — generator_matrix's item mirror is dead code, 0 call sites)."
impact_analysis: >
  Blast radius platform (lib/shared/repositories/plan_engine/** + core/utils).
  Behavior change (flag ON only): gym users' GENERATED warmup + finisher now offer a
  gym-cardio variant (Treadmill/Bike), and excluding `cardio machine` removes it. Flag
  OFF (ship-dark, the same enable_equipment_exclusions as C1) → byte-identical: the
  generated path's old predicate stays always-false (item tokens never contain
  'gym'/'full'), and tier-string callers (template_service + shared_contracts_test)
  keep the old predicate via the null override. The Batch-0 scorecard is BLIND to
  warmup/finisher (scores only plan.allExercises) — the behavioral test is the sole
  proof; NO baseline move + NO regen (the item list is not scored; generator_matrix's
  item mirror is dead code). Adding cardio machine to the gym tiers also surfaces one
  inert "Cardio Machine" excludable chip in the C1 Customize UI (consistent — a user
  without a treadmill excludes it). WU-2 was founder-split from C1 as a distinct unit
  (2026-07-17). ×2 plan review converged.
---

# hasGymEquipment always-false → gym users denied gym cardio (b7a4e2)

## What happened
On every generated plan, gym users never received gym-cardio warmups or finisher
variants — the always-false `hasGymEquipment` gate forced the bodyweight fallbacks.
The custom-template path (which passes the tier string) was unaffected.

## Root cause
Writer/reader drift: `WarmupCooldownSelector.attach:141` + `CardioFinisher.attach:28`
compute `hasGymEquipment` from `equipmentList.any(contains('gym')||contains('full'))`,
but generateV4 passes `_getEquipmentList(tier)` = ITEM tokens (none/bodyweight/…),
which contain neither substring → always false. The reader expected the tier STRING;
the writer passed the item LIST.

## Fix
Add `cardio machine` to the gym tiers; compute a flag-gated hasGymEquipment override
in generateV4 from the effective (exclusion-subtracted) equipment; pass it to both
attach methods (null → old predicate, keeping template_service + tier-string tests
byte-identical). See `proposed_fix` + `docs/plans/wu2-gym-cardio-gate-batch.md`.

## Shared-flag no-op consequence (B1/C1 test adaptation)
Because WU-2 rides the SAME `enable_equipment_exclusions` flag, flipping that flag is no
longer a *pure* no-op: it also activates the gym-cardio FIX for every gym user, even with
zero exclusions set (intended — gym users were wrongly denied gym cardio). B1's + C1's
shipped NO-OP tests asserted flag-ON-empty == flag-OFF byte-identical on the WHOLE Phase;
that legitimately breaks for gym tiers. Both were adapted (test-only) to assert the
exclusion filter's no-op on the plan MINUS the two WU-2-owned fields (`warmup`+`finisher`,
stripped from both the `workouts` compat list AND `week_plans[].workout_days[]`); the
warmup/finisher behavior is covered precisely by `wu2_gym_cardio_gate_behavioral_test`.
No coverage lost. See the B-pass record for the full reasoning.

## Related
⑥ C2 — the WU-2 gym-cardio gate, founder-split from C1 (2026-07-17). Sibling of
d3f8a1 (warmup injury filter, same file). ×2 plan review converged.
closes-diagnose: b7a4e2
