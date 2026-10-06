---
bug_id: f4c1e8
date: 2026-07-19
batch: exercise-lib-13b
blast_radius: platform
status: fixed
symptom: >
  The always-on queryV4 injury filter (exercise_repository.dart:335-345) excludes an
  exercise for an injured user ONLY when the exercise's injury_contraindications list
  CONTAINS the user's injury token; a MISSING or EMPTY list is never excluded. After
  13-A closed the 9 field-MISSING stub rows, 135 of 259 rows still carried an empty
  `[]` — so injury-provocative movements were silently served to injured users: e.g.
  Romanian Deadlift / Meadows Row (empty) to a lower_back-injured user, Front Raise /
  Pull Up (empty) to a shoulder-injured user, Nordic / Leg Curl (empty) to a
  hamstring-injured user. Two already-tagged rows were also under-tagged: GHD Sit Up
  (`[hip]` only — a notorious lumbar move served to lower_back users) and barbell Good
  Morning (`[lower_back]` only, missing hamstring while its bodyweight sibling had both).
concept: exercise_injury_tags
sot_registry_entry: exercise_injury_tags
writers:
  - { file: assets/data/exercise_library.json, line: 1, source: "26 under-tagged rows gained injury_contraindications + 2 existing rows deepened (GHD Sit Up +lower_back, Good Morning +hamstring); UNION with existing tokens; clinically-nuanced per movement_pattern (tag the provocative pattern, keep the controlled/rehab variant safe)" }
  - { file: lib/core/services/seed_service.dart, line: 89, source: "_exerciseLibraryVersion 8->9 — idempotent putAll re-seeds each row's whole map so existing installs pick up the new tags" }
  - { file: lib/shared/repositories/plan_engine/injury_substitutes.dart, line: 27, source: "curated-sub coherence — removed 'Front Raise' from the shoulder list (now shoulder-tagged) and the stale 'Wall Sit' from the knee list (Wall Sit is itself [knee]-tagged); Kettlebell Goblet Press retained as the sole shoulder-safe overhead press per founder" }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, line: 340, source: "queryV4 injury filter — exact lowercase match `contra.any((c)=>c.toLowerCase()==injury)`; a newly-tagged row is now excluded for the matching injured user" }
  - { file: lib/shared/repositories/plan_engine/injury_substitutes.dart, line: 27, source: "preferredFor re-rank runs on the POST-filter candidate list; the sub lists stay coherent with the new tags (>=1 shoulder sub still safe: Goblet Press/Face Pull/Band Pull Apart/etc.)" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a — injury_contraindications is NOT in migration 074's INSERT columns or ON CONFLICT SET (verified) so it is not surfaced to cloud; no prod re-apply
contract_test_path: test/contracts/injury_undertag_13b_contract_test.dart
ist_handling: n/a — pure static-data tagging, no date-key handling
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  n/a — exerciseBox is a global bundled-asset seed, not user-scoped. Re-seed on the
  version bump (8->9) overwrites each row's map wholesale; no per-user state involved.
forbidden_patterns_checked: >
  Verified NO new vocabulary token leaked: all 28 rows' tags are drawn from the closed
  9-token InjuryVocab.canonicalTokens set (data-contract test asserts canon.containsAll
  for every row) so injury_vocab_library_contract_test stays green. Verified the JSON
  diff touches ONLY injury_contraindications field/token/bracket lines (git diff -U0
  filter returned zero non-injury lines) — no float/formatting collateral (the 13-A
  JSON.stringify float-stripping footgun avoided via a per-field text replacer). Verified
  none of the 28 rows appear in warmup_cooldown.dart _moveInjuries (Push Up/Band Pull
  Apart/Baithak) so no mirror sync needed; a NEW value-agreement test now guards that.
proposed_fix: >
  Comprehensive-tag the under-tagged strength rows' injury_contraindications per a
  clinically-nuanced per-movement_pattern methodology, UNIONing with existing tokens.
  Tag the classically-provocative pattern (overhead press -> shoulder, hinge/bent-row ->
  lower_back+hamstring, deep-knee -> knee, loaded/hanging/support core -> lower_back/
  shoulder/wrist) and KEEP the controlled/machine/rehab variant safe (push-ups, machine
  press, dumbbell/cable curls, chest-supported/machine rows, Glute Bridge, Leg Press,
  rear-delt work) so no injured user loses a whole movement category (variety-first,
  founder-directed). Founder decisions: keep carries + crunch/sit-up family + hip machines
  safe; keep Kettlebell Goblet Press as the one shoulder-safe overhead press. Fix the two
  existing under-tags (GHD Sit Up, Good Morning). Bump _exerciseLibraryVersion 8->9. No
  cloud/migration (injury_contraindications is not a cloud column).
regression_test_planned: >
  test/contracts/injury_undertag_13b_contract_test.dart — (A) DATA CONTRACT pins the
  EXACT expected token set for all 28 rows + the 4 heuristic corrections (Reverse Nordic
  =knee, Copenhagen=hip, Nordic=knee+hamstring, Hollow Body=safe) + the kept-safe pool
  stays empty + vocab stays closed to 9; (B) BEHAVIORAL drives the REAL generator and
  asserts a hamstring / lower_back injured plan contains ZERO of the newly-contra rows
  with non-vacuity via the uninjured persona. Plus
  test/contracts/warmup_library_injury_mirror_test.dart — _moveInjuries value-agreement
  for the 3 library-overlap warmup moves.
impact_analysis: >
  Live SAFETY hole: 135/259 rows carried an empty injury_contraindications, so the
  always-on filter served injury-provocative lifts (hinges, bent rows, overhead presses,
  loaded spinal flexion) to injured users whenever it fell through to those rows. 13-B
  tags 26 of them + deepens 2 existing under-tags. Only injured users are affected —
  non-injured plans are byte-identical (the filter is skipped when injuries is empty).
  Variety is preserved for injured users: the controlled/machine/rehab pool stays safe,
  so no movement category is emptied (Round-2 verified the universal-pool floor holds for
  every pattern; only vertical_push x shoulder narrows to the founder-kept Goblet Press +
  a bodyweight fallback). Blast radius platform (plan engine data; client-only, ships via
  seed version bump; NO cloud re-apply). Recurrence of e1a7c4 (the field-MISSING half of
  this hole) and a1f6c3 (the injury filter shipped non-functional); sibling data-hole
  class d4e8a1 / 40a426.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "28 rows tagged + injury_substitutes coherence edits + seed 8->9 + injury_vocab/comment refresh; flutter analyze 'No issues found'; new tests green" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeds v9 (idempotent putAll); the filter (exercise_repository:340) reads the new injury_contraindications from the seeded map" }
  - { layer: postgres_schema, status: not_applicable, evidence: "injury_contraindications is not a cloud column — absent from migration 074 INSERT + ON CONFLICT SET (verified); no schema change" }
  - { layer: postgres_data, status: not_applicable, evidence: "no prod re-apply; the AI coach's cloud exercise_library copy reads name/coaching_cues/primary_muscles only, none of which 13-B touches" }
  - { layer: migrations_applied, status: not_applicable, evidence: "no migration; row count stays 259 so exercise_library_cloud_seeded_test row-count parity is unaffected" }
  - { layer: client_server_contract, status: verified, evidence: "end-to-end: injured persona -> generateV4 -> queryV4 filter excludes the newly-tagged rows (injury_undertag_13b behavioral group); non-injured persona byte-identical" }
---

## Root cause

The queryV4 injury filter (`exercise_repository.dart:335-345`, exact-lowercase match at
`:340`) excludes a row **only** when its `injury_contraindications` list contains the
user's injury token. An empty (or missing) list therefore reads as "no contraindication"
and the row is **always kept**. 13-A closed the 9 rows whose field was *missing* (the
E252 Wall-Sit knee hole, `e1a7c4`), but 135 of 259 rows still carried an empty `[]`. So
whenever the cascade filled a slot from one of those rows — Romanian Deadlift for a
lower_back user, Front Raise / Pull Up for a shoulder user, Nordic Curl / Leg Curl for a
hamstring user — the injury filter did nothing. Two already-tagged rows were also
under-tagged: GHD Sit Up carried `[hip]` (missing `lower_back`, though it is one of the
most lumbar-provocative core moves) and barbell Good Morning carried `[lower_back]`
(missing `hamstring`, while its own bodyweight sibling E253 already had both).

This is the empty-`[]` half of the same class as `e1a7c4` (missing field) and a
continuation of `a1f6c3` (the injury filter that originally shipped non-functional).

## Fix

Comprehensive, clinically-nuanced tagging of the under-tagged strength rows (26 new + 2
deepened), UNIONed with existing tokens. The nuance — tag the classically-provocative
pattern, keep the controlled/machine/rehab variant safe — is what preserves variety: an
injured user loses the risky movements but keeps a deep safe pool in every category, so
no slot goes empty (Round-2 confirmed the universal-pool floor holds for every movement
pattern). Founder-directed carve-outs: carries, the crunch/sit-up family, and all hip
machines stay safe; Kettlebell Goblet Press stays the one shoulder-safe overhead press.
Four heuristic mis-tags from the derivation dry-run were hand-corrected (Reverse Nordic →
knee, not hamstring/lower_back; Copenhagen Plank → hip, not wrist; Nordic → knee+hamstring;
Hollow Body kept safe). `injury_substitutes.dart` was reconciled (Front Raise + stale Wall
Sit removed). `_exerciseLibraryVersion` 8→9 re-seeds; no cloud/migration because
`injury_contraindications` is not a cloud column.

## Verification

`flutter analyze` clean. `injury_undertag_13b_contract_test` pins every tag decision
(data) + proves end-to-end filtering for hamstring/lower_back injured personas with
non-vacuity (behavioral). `warmup_library_injury_mirror_test` guards the warmup mirror.
Scorecard baseline regenerated — only the injury sub-sweep personas move (non-injured are
byte-identical). ×2 context-blind review converged (Round-1 restored the hanging-move
lower_back tags + caught the GHD/Good-Morning under-tags; Round-2 CONVERGED).
