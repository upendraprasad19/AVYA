---
bug_id: b1c4e7
date: 2026-10-22
batch: library-batch-b
status: fixed
blast_radius: platform
symptom: >-
  The equipment capability floor (OI-89) did not apply on the two pick paths
  that resolve an exercise by NAME and bypass queryV4: the attempt-5 universal
  pool and repeat-phase pins. A shoulder-injured bodyweight user was prescribed
  Chin Up (pull-up bar), Inverted Row and TRX Row (suspension trainer) and Band
  Pull Apart (resistance band); home_dumbbells and basic_gym users the same
  minus the items their tier grants. A repeat phase could carry forward a pin
  (library or custom) the user can no longer perform. The scorecard was blind to
  it because the check existed only in its diagnostic mirror.
concept: equipment_capability_floor
sot_registry_entry: equipment_capability_floor
writers:
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method: _cascadeFill attempt 5 (universal pool, picks by NAME)
    line: 1181
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method: buildPinnedDays.resolve (repeat-phase pins, picks by NAME)
    line: 756
readers:
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: Train tab / Active Workout (render the built PlannedExercise)
    line: 427
  - file: test/plan_generator/v4_diagnostic/cascade_tracer.dart
    method_or_widget: CascadeTracer.trace att5 mirror (DID check — hence the blind scorecard)
    line: 322
hive_key_prefix: schedule_
hive_key_formula: "workoutBox schedule_<date> rows built from the generated Phase"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/universal_pool_capability_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Attempt 5 skips a pool row the user cannot perform
  (EquipmentCapability.canPerform), checked FIRST, before exclusions and
  injury, the mirror's order. buildPinnedDays.resolve drops a pin that fails
  EquipmentCapability.canOfferInPicker(isCustom:), so a user-authored custom
  with no recorded equipment (the creation sheet stores []) is still kept, while
  a custom that records kit the user lacks is dropped like a library row. A null
  capability (the existing disable_equipment_capability_floor kill switch, or an
  unreadable Hive) skips both checks, so the switch is this fix's §4.6 gate.
regression_test_planned:
  - test/contracts/universal_pool_capability_behavioral_test.dart
  - test/contracts/repeat_phase_pinned_selection_behavioral_test.dart
  - test/plan_generator/generator_golden_test.dart
related_bugs:
  - f7b2c4  # OI-89 library equipment vocabulary restore + floor flip (a7c2d194 put the att5 check in the mirror only)
  - c9a7e2  # OI-89 warm-up / finisher equipment-blind
  - b6f4d1  # OI-89 UI seams unfiltered
  - d3a8f5  # OI-89 equipment_access default drift
recurrence: |
  Recurrence of the OI-89 capability-floor class (f7b2c4 / c9a7e2 / b6f4d1 /
  d3a8f5): a pick path that does not go through queryV4 has to apply the floor
  itself. Also an instance of feedback_mistake_guard_without_its_mirror, the
  inverse shape: the guard went into the MIRROR and not into production, so the
  measurement that should have found the gap was the one place it was closed.
  plan_engine/CLAUDE.md's "The scorecard is green in every world" row warns the
  other way round (add to both mirrors); this instance adds the reverse check.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Two checks in exercise_selector.dart (att5 :1205-1215, resolve :775-782) plus corrected comments there and in plan_engine_flags.dart. New universal_pool_capability_behavioral_test.dart 6/6; repeat_phase_pinned_selection test 5 repointed to a performable off-tier synthetic row; 25/25 across pinned, capability-leak, exclusion and new suites. Mutations: drop att5 check -> test 1 red; drop pin check -> tests 3 and 5 red; canOfferInPicker -> canPerform -> test 4 red; each restored byte-identical (cmp)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "No Hive key or shape change. The generated Phase written to schedule_ rows simply contains different (performable) exercises for the affected personas." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill: existing schedules regenerate at the next phase; pre-launch, every account is a testing account (CLAUDE.md §1)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart (rule 8)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Generator golden (998 personas, real generateV4): the 960-persona grid is byte-identical; exactly 6 keys changed, all injury|shoulder at bodyweight/home_dumbbells/basic_gym p1+p2, re-recorded and named below. A read-only production probe over all 24 injury personas found 0 off-capability picks after the fix." }
impact_analysis: >-
  Real but narrow on the shipped library. The cascade_tracer mirror counts 8
  attempt-5 picks across the 960-persona golden grid (all bodyweight), and none
  of them changed: on the grid this is latent. It is live for injured users,
  because an injury empties attempts 1-4 more often: all six shoulder personas
  below basic_gym-and-up changed. Repeat pins are the second path: a user whose
  previous phase held a move they can no longer perform (an exclusion added, a
  custom that records kit) had it carried forward. Severity is platform: an
  exercise the user cannot do is an unusable session, and for an injured user a
  substituted improvisation is worse than the safe omission the floor provides.
---

# The floor was only in the mirror

## What was wrong

OI-89 made `EquipmentCapability.canPerform` a hard floor: the generator must
never prescribe a move needing kit the user lacks. `queryV4` (attempts 1-4)
applies it. Two production paths do not use `queryV4`, they resolve an
exercise by NAME:

- `_cascadeFill` attempt 5, the universal bodyweight pool;
- `buildPinnedDays.resolve`, repeat-phase pins.

Commit `a7c2d194` added the att5 skip to `cascade_tracer.dart:322-326`, the
diagnostic mirror, and not to `exercise_selector.dart`. The comment at
`exercise_selector.dart:502-518` even said att5 applies "(since OI-89)
capability". So `scorecard_gate_test.dart`'s hard "equipment violations == 0"
was measuring a cascade that production did not run.

## What a user got (pre-fix, real generateV4, read-only probe)

| persona | off-capability picks |
|---|---|
| `injury|shoulder|bodyweight|…|p1`, `p2` | Chin Up [pull-up bar], Inverted Row [suspension trainer], TRX Row [suspension trainer], Band Pull Apart [resistance band] |
| `injury|shoulder|home_dumbbells|…|p1`, `p2` | Chin Up, Inverted Row, TRX Row |
| `injury|shoulder|basic_gym|…|p1`, `p2` | Inverted Row |

After the fix the same probe finds 0 across all 24 injury personas, and these
six are the only golden keys that changed (re-recorded in this commit).

## The fix

- att5: `canPerform` first, then exclusions, then injury (the mirror's order).
  A pool name with no library row still builds a `['bodyweight']` placeholder.
- pins: `canOfferInPicker(isCustom:)`. A custom created in the app records
  `[]` (the creation sheet has no equipment field), and the user has already
  done it, so it is kept. A custom that RECORDS kit the user lacks (for example
  one the AI coach authored) is now dropped. **This changes live behaviour for
  such customs**, deliberately: the same rule as a library row.
- What a dropped pin leaves (B-pass F6): the variant is refilled through
  `pickV4` only when EVERY pin dropped. Beside a performable pin, an
  unperformable library pin, a community row whose `equipment_needed`
  normalises to `[]` (`canPerform` fails closed and it is not a custom) or a
  custom recording kit the user lacks just shortens that day by one exercise.
  That is the shape of today's exclusion and injury pin drops. Pinned by the
  two-pin test in `universal_pool_capability_behavioral_test.dart`.
- The kill switch is the existing `disable_equipment_capability_floor`: it
  makes `capability` null, which skips both checks.

`repeat_phase_pinned_selection_behavioral_test.dart` test 5 pinned a
`['machines']` row at bodyweight and expected it KEPT, which is the behaviour
removed here. It now pins a synthetic row that is performable at bodyweight
but whose `equipment_tier` omits bodyweight (no shipped row has that shape),
so "tier is not re-filtered" stays pinned.

## Ruling recorded in the batch ledger

The plan's att5 test seeded a synthetic barbell `vertical_pull` row. With
`capability: null`, attempt 4 (tier dropped) would pick it, so the
"capability null keeps today's order" test could never reach attempt 5. The
row is omitted; with no `vertical_pull` row at all, both tests reach attempt 5.
