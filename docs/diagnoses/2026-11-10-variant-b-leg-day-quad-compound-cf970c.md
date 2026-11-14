---
bug_id: cf970c
date: 2026-11-10
batch: generator-step1-1bq
status: fixed
blast_radius: platform
symptom: >-
  Week 2 (variant B) of 3, 4 and 5-day build_muscle and 3-day strength plans held no quad work. Measured on main
  cc8286ad over the 2,304-plan audit: with the core-list pool ON, 182 plans had "Week 2: no sets at all for Quads"
  that their live twin did not have (OI-475; the Unit 1B flip criterion "no plan worse than its live twin"). The live
  picker hid it by putting a quad-crediting row (a Wall Sit, a lunge) into a non-quad slot.
concept: variant_b_leg_quad_compound
sot_registry_entry: variant_b_leg_quad_compound
writers:
  - file: lib/shared/repositories/plan_engine/split_resolver.dart
    method: _get3DayV4 Legs slotsB (shared by build_muscle and strength)
    line: 578
  - file: lib/shared/repositories/plan_engine/split_resolver.dart
    method: _get4DayV4 build_muscle Legs slotsB
    line: 661
  - file: lib/shared/repositories/plan_engine/split_resolver.dart
    method: _get5DayV4 build_muscle Legs slotsB
    line: 890
  - file: lib/shared/repositories/plan_engine/plan_engine_flags.dart
    method: variantBQuadEnabled (kill-switch disable_variant_b_quad, default ON)
    line: 44
readers:
  - file: lib/shared/repositories/plan_engine/session_set_allocator.dart
    method_or_widget: allocate (seats the day's slots in split order up to the count band; the Glutes session cap refuses a later quad row that also credits Glutes)
    line: 138
  - file: lib/shared/repositories/plan_engine/split_resolver.dart
    method_or_widget: selectV4 (reads the kill-switch once per call)
    line: 413
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _pickCoreList (one row per slot; the core-list pool takes the slot's own row)
    line: 773
  - file: lib/shared/repositories/plan_engine/sequencing_engine.dart
    method_or_widget: sequence (reorders each day after seating, compound first)
    line: 33
  - file: lib/shared/repositories/plan_engine/thin_day_topup.dart
    method_or_widget: anchors (orders an injured user's thin-day top-up anchors by slot priority; the only priority reader on this path)
    line: 51
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/variant_b_quads_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "a change to plan_generator.dart (root CLAUDE.md rule 14)", absent: true }
  - { pattern: "a credit-rule change (OI-475 L2, kept for step 2)", absent: true }
proposed_fix: >-
  OI-475 level L1 (plan docs/plans/2026-11-10-generator-1bq-variant-b-quads.md): each B leg day of the 3, 4 and 5-day
  splits carries a Quads / knee_dominant / compound slot at priority 1, SECOND (after the Hamstrings hinge, before the
  Glutes hinge). Slot counts unchanged. Second, not third: a third-place slot left 8 advanced bodyweight / home 30
  minute plans without quads (the Glutes session cap refused Single Leg Squat after the hinge and bridge). The Glutes
  hip_isolation slot moves behind the Calves slot (4-day: and Core): directly after the hinges it pushed Calves / Core
  off the day (round-2 review: 51 live plans without Calves, 12 live / 24 ON without Core, in weeks 2 and 4).
regression_test_planned:
  - test/contracts/variant_b_quads_behavioral_test.dart
related_bugs:
  - cb50cb  # OI-454: the 6-day Legs B Quads slot + the credit rule; same class, different split
  # Parent board item: OI-475 (even weeks hold no quad work; L1 is this fix, L2/L3 stay in step 2).
recurrence: |
  Same class as cb50cb (OI-454): a split's slot list starves a muscle the weekly floor needs, and the allocator, which
  seats slots in split order, cannot recover it. cb50cb fixed the 6-day split with a slot swap and a credit rule; this
  is the slot-only level (OI-475 L1) for the 3, 4 and 5-day splits. The credit rule (L2) and a quad hit on another day
  (L3) stay in step 2.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "split_resolver.dart three B leg days; variant_b_quads_behavioral_test.dart 66 tests (split shape, kill switch, week-2 / week-4 quad, Hamstrings, Calves and Core sets OFF and ON); six mutations, table below (28 / 12 / 4 / 1 / 2 / 13 red)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No stored value changes; plans are generated on demand. A tester's existing plan keeps its weeks until the next generation." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema touched." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage touched." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Generation is local (rule 8); the 998-persona golden changes in 242 keys, all build_muscle 3/4/5-day or strength 3-day. Injury personas: the golden's 24 injury keys change and the injury sweeps stay green; whether an injured user's week-2 Legs day keeps a quad row is not measured." }
impact_analysis: >-
  Pool OFF (`enable_core_list_pool` off, live, every user today): 242 of 998 golden keys change, all in the four changed splits; live plans with a major muscle
  at 0 sets 92 -> 28. Pool ON (dark): plans worse than their live twin 186 -> 4 (Quads 184 -> 0; the 4 left were on main,
  OI-489). No muscle of any kind gains a zero-set week in either world (per plan, every week). Costs, fewer week-2 sets,
  none to 0: Quads 52 live (build_muscle 4/5-day full_gym, a Wall Sit seat became a loaded compound), Glutes 94 live /
  116 ON (the isolation row drops at short minutes), Hamstrings 74 / 73, Calves 28 / 21, Core 35 / 8; `ab_swing` plans
  OFF 293 -> 304, ON 257 -> 402; `stretch_lift` OFF +21; one ON plan (strength 3-day advanced home_dumbbells 30)
  newly seats E292 Sliding Leg Curl where main had no week-2 quad set; same-movement ON placements 977 -> 931 (N19 on fewer B days; shared days stay 0). The
  kill-switch `disable_variant_b_quad` restores main byte for byte (998 of 998 golden hashes).
---

# Variant B leg day gets a quad compound (cf970c)

## What changed
- `split_resolver.dart`: in the B variant of the Legs day of the 3-day (build_muscle and strength), 4-day and 5-day
  build_muscle splits, a Quads / knee_dominant / compound slot at priority 1 sits second, and the Glutes
  hip_isolation slot sits behind the Calves slot (4-day: and the Core slot). Slot counts unchanged.
- Kill-switch `disable_variant_b_quad` (`PlanEngineFlags.variantBQuadEnabled`, default ON), read once per
  `SplitResolver.selectV4` call; set, it restores the pre-1B-Q B lists verbatim. Measured: with it set, all 998 golden
  personas hash equal to main cc8286ad's fixture (0 differ). `plan_generator.dart` is not touched.
- Deload (week 4) is variant B. Measured for build_muscle 3/4/5-day intermediate, bodyweight and full_gym, 30 and 60
  minutes: the deload leg day keeps its exercise count; at full_gym it seats Front Squat where the old day took a Wall
  Sit through another slot, and no persona loses its last quad or hamstring set. The deload filter does not read the
  slot's priority (`VolumeFilter.filterDays` is passed `baseline`, plan_generator.dart:174); priority 1 matches variant
  A's Quads compound. Slot priority is read only by `ThinDayTopUp.anchors` (thin_day_topup.dart:51,
  an injured user's thin day): the Quads compound becomes that day's second top-up anchor.

## Mutation evidence (rule 21)
`test/contracts/variant_b_quads_behavioral_test.dart`, 66 tests. Each mutation by script from a saved copy of the fixed
file, applied (non-equal by `cmp`), run, restored and `cmp`-checked, all on the final tree.

| mutation | red |
|---|---|
| the new B lists replaced by the old (`slotsB: false ? ...` in all three days) | 28 |
| the Quads compound THIRD (swapped with the Glutes hinge in all three days) | 12 (4 shape + the 8 audit personas ON) |
| the new slot at priority 4 instead of 1 | 4 (shape only: no path reads it for an uninjured persona) |
| the kill-switch ignored (`variantBQuad ?? true`) | 1 |
| the old B list edited (3-day Quads compound line commented out) | 2 |
| the Glutes isolation slot back in fourth place (the round-2 tree) | 13 (4 shape + 9 Calves / Core persona runs) |
