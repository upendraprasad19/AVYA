---
bug_id: c3f9b2
date: 2026-07-19
batch: exercise-lib-13a
blast_radius: platform
status: fixed
symptom: >
  The V4 last-resort fallback pool `universalPoolV4` (attempt-5 of the cascade) had
  duplicate + wrong-pattern entries: horizontal_pull = ['Inverted Row','TRX Row',
  'Inverted Row','Dead Bug'] (Inverted Row duplicated + Dead Bug is a CORE move,
  not a row); hip_isolation = ['Glute Bridge','Side Plank','Glute Bridge'] (Glute
  Bridge duplicated + Side Plank is CORE); shoulder_isolation = ['Pike Push Up',...]
  (Pike Push Up is a vertical PUSH served as a rear-delt fallback — the documented
  "Pike Push Up assigned to rear delt slot" symptom). The cascade_tracer.dart copy
  (which the scorecard runs off) was a MANUAL duplicate with NO test asserting it
  stayed equal to production — silent-drift risk (H5).
concept: universal_pool_fallback
sot_registry_entry: universal_pool_fallback
writers:
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, line: 497, source: "universalPoolV4 (:497-509) — deduped; Dead Bug/Side Plank replaced with real Towel Row/Glute Kickback (now bodyweight library rows); shoulder_isolation -> E261 Bodyweight Rear Delt Raise" }
  - { file: test/plan_generator/v4_diagnostic/cascade_tracer.dart, line: 53, source: "universalPoolV4Mirror — the tracer copy, edited in lockstep + renamed public for the equality test" }
readers:
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, line: 1152, source: "_cascadeFill attempt-5 — resolves each pool name via repo.search, injury+equipment-filters, else safely omits" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/universal_pool_mirror_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  n/a — universalPoolV4 is a static const in plan-engine code, not user data.
forbidden_patterns_checked: >
  Verified cascade_tracer.dart:52 is the ONLY other code copy of universalPoolV4
  (Round-2 grep — query_v4_mirror.dart has no pool; all other hits are comments /
  generated artifacts). Both edited identically + pinned by an equality test so a
  future one-sided edit is caught. The replacement names (Towel Row / Glute
  Kickback / Bodyweight Rear Delt Raise) are all real library rows post-batch (E255
  / E257 / E261), so repo.search resolves them at attempt-5.
proposed_fix: >
  Dedupe both lists; replace the wrong-pattern CORE moves (Dead Bug in
  horizontal_pull; Side Plank in hip_isolation) with the now-real bodyweight library
  rows for those patterns (Towel Row, Glute Kickback); point the shoulder_isolation
  fallback at E261 Bodyweight Rear Delt Raise (a real bodyweight rear-delt) instead
  of Pike Push Up (a vertical push). Edit cascade_tracer's copy in lockstep and
  expose it (universalPoolV4Mirror) for an equality test.
regression_test_planned: >
  test/contracts/universal_pool_mirror_test.dart — asserts
  cascade_tracer.universalPoolV4Mirror == ExerciseSelector.universalPoolV4
  (deep-equal), so the manual copy can never silently drift from production again.
impact_analysis: >
  Live, pre-existing: when an equipment-light slot exhausted attempts 1-4, the
  attempt-5 fallback could serve a wrong-pattern move (a core move for a row/hip
  slot; a vertical push for a rear-delt slot) — an incoherent pick. Low frequency
  (attempt-5 only) but a real quality floor. The scorecard/matrix ran off the
  un-tested tracer copy, so a divergence would have silently invalidated the
  regression harness. Fix + equality test close both. Blast radius platform.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "universalPoolV4 deduped + pattern-corrected in exercise_selector.dart + cascade_tracer lockstep; flutter analyze clean; universal_pool_mirror_test green" }
  - { layer: hive_local_state, status: not_applicable, evidence: "static const code, no Hive state" }
  - { layer: client_server_contract, status: not_applicable, evidence: "attempt-5 fallback is client-only plan-engine logic; no server contract" }
---

## Root cause

`universalPoolV4` (`exercise_selector.dart:497-509`) is the attempt-5 last-resort pool,
keyed by movement_pattern. Three entries were wrong: two lists carried a duplicate name,
and two carried a CORE move (Dead Bug / Side Plank) filed under a pull/hip pattern, while
`shoulder_isolation` fell back to Pike Push Up (a vertical push). Separately, the
pure-Dart `cascade_tracer.dart` — which the scorecard + generator_matrix run off — held a
MANUAL verbatim copy with no test pinning it equal to production, so a future edit to one
could silently diverge the harness (H5).

## Fix

Dedupe + replace the wrong-pattern moves with the now-real bodyweight library rows
(Towel Row E255, Glute Kickback E257 — both normalized this batch) and point
shoulder_isolation at E261. Edit the tracer copy in lockstep, rename it public, and add
`universal_pool_mirror_test.dart` asserting the two are deep-equal.

## Verification

`universal_pool_mirror_test` green (the copies match); `flutter analyze` clean. The
attempt-5 fallback now serves an on-pattern bodyweight move for every pattern.
