---
bug_id: c2d5e8
date: 2026-10-22
batch: library-batch-b
status: fixed
blast_radius: platform
symptom: >-
  Five library rows were missing a safety-direction injury tag, so the queryV4
  injury filter could hand them to a user with that injury: Renegade Row (E121)
  to a shoulder- or wrist-injured user, Running (Treadmill) (E061) to a knee
  injury, Front Lever Hold (E070) to a shoulder or elbow injury, Reverse Hyper
  (E127) and Decline Sit Up (E173) to a lower-back injury. Measured live on the
  generator: a shoulder-injured home_dumbbells intermediate user was given
  Renegade Row in phases 1 and 2.
concept: exercise_injury_tags
sot_registry_entry: exercise_injury_tags
writers:
  - file: assets/data/exercise_library.json
    method: injury_contraindications on E061 / E070 / E121 / E127 / E173 (union, additions only)
    line: 1
  - file: scripts/add_library_core_fields_v13.js
    method: addInjuryTags (applies scripts/data/library_injury_additions_v13.json)
    line: 33
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion (12→13)
    line: 110
readers:
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 injury filter (attempts 1-4)
    line: 412
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _isContraindicated (attempt 5 and repeat pins)
    line: 1252
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<id>]['injury_contraindications'] (re-seeded by SeedService v13 putAll)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: []
contract_test_path: test/contracts/injury_safety_tags_v13_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Add the five tags (E061 +knee, E070 +shoulder +elbow, E121 +wrist +shoulder,
  E127 +lower_back, E173 +lower_back) through a committed additions table,
  scripts/data/library_injury_additions_v13.json, which the v13 library script
  unions into injury_contraindications (never removing a tag; result sorted;
  non-canonical tokens refused). Delivered to existing installs by the seed v13
  bump that Task 2 made. The 13-B pin for E121 is updated to
  ['lower_back', 'shoulder', 'wrist'].
regression_test_planned:
  - test/contracts/injury_safety_tags_v13_behavioral_test.dart
  - test/contracts/injury_undertag_13b_contract_test.dart
  - test/contracts/exercise_library_frozen_reference_test.dart
  - test/plan_generator/generator_golden_test.dart
related_bugs:
  - f4c1e8  # Batch 13-B injury under-tagging (26 rows tagged, 2 deepened)
  - e1a7c4  # Batch 13-A injury field missing on stub rows
  - a1f6c3  # injury filter non-functional
recurrence: |
  Recurrence of the 13-B under-tag class (f4c1e8): the injury filter excludes a
  row only when its list CONTAINS the user's token, so a missing tag is a silent
  pass. Known-good fix applied the same way: additions only (UNION), tokens
  closed to InjuryVocab, a contract pin per changed row, and a seed bump so the
  stale Hive box receives them. New this time: a behavioural test per (row,
  token) pair with a positive control, rather than a tag-list pin alone.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "assets/data/exercise_library.json five rows (13 insertions, 4 deletions, nothing else); additions table + addInjuryTags in the v13 script (idempotent: a second run is byte-identical). New injury_safety_tags_v13_behavioral_test.dart: 8 tests red before, 9/9 green after; 13-B contract 7/7 with the E121 pin updated. Mutation: removing E121's wrist reddens the +wrist pair and the exact-tags test; restored byte-identical (cmp)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "SeedService v13 (Task 2) re-seeds exerciseBox by id via putAll, so a v12 box receives the tags; exercise_library_core_fields_contract_test pins the version >= 13." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json exercise_library has no injury_contraindications column (26 columns, none of them injury tags), consistent with the 13-B entry: not a cloud column." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud column carries the tags, so there is no row to backfill." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration (plan Ruling 2)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart; no Edge Function reads injury_contraindications." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Generator golden (998 personas): exactly 2 keys changed, injury|shoulder|home_dumbbells|build_muscle|4d|intermediate|p1 and p2; a probe on the pre-change library shows both plans held Renegade Row and both post-change plans do not. Frozen reference: exactly E061 E070 E121 E127 E173 re-hashed (targeted RECORD_LIBRARY_REFERENCE_IDS mode), every other row unchanged." }
impact_analysis: >-
  Only E121 is reached by any golden persona's plan (19 of 998, all
  home_dumbbells or gym build_muscle), so the live change is the shoulder case
  above; with a wrist injury the same users would also have received it. The
  other four rows are picked by no golden persona today; their tags matter for
  the ON core-list path (Task 3 reads the same predicate) and for any user whose
  slot reaches them. All five changes are in the safe direction: an injured user
  loses one exercise and the cascade substitutes.
---

# Five rows the injury filter could not see

## What was wrong

`queryV4` drops a row for an injured user only when the row's
`injury_contraindications` contains the user's token. These five had no such
token for an injury their movement clearly loads:

| row | added | why |
|---|---|---|
| E061 Running (Treadmill) | knee | repetitive impact; the warm-up table already tags it `{knee, ankle, hip}` |
| E070 Front Lever Hold | shoulder, elbow | straight-arm lever, extreme shoulder/elbow load (keeps `wrist`) |
| E121 Renegade Row | wrist, shoulder | loaded plank on the wrists, anti-rotation through the shoulder |
| E127 Reverse Hyper | lower_back | loaded lumbar extension |
| E173 Decline Sit Up | lower_back | loaded spinal flexion |

## What a user got

With a shoulder injury, a home_dumbbells intermediate user's phase 1 and 2
plans contained Renegade Row. Those are the only two golden keys that changed.

## Decision and the 13-B carve-outs

The founder decided on 2026-10-22 to apply all five live, with or without the
core-list flag (plan Ruling 3(b)). It knowingly supersedes the 13-B tags on
E121 (`['lower_back']`).

**Flagged for the founder:** the 13-B registry entry also records founder
carve-outs in which the "crunch/sit-up family + hip machines stay safe". E173
Decline Sit Up is a sit-up, and E127 Reverse Hyper is a machine. 13-B itself
tagged GHD Sit Up `lower_back`, so the carve-out was never absolute, and no
test pins either row empty. The 2026-10-22 decision names these two tags
explicitly, so they are applied. If the carve-out was meant to cover them,
removing the tag is a one-line change to the additions table.

## Not a reader

`WarmupCooldownSelector._moveInjuries` keeps its own table (Running is
already `{knee, ankle, hip}` there) and its overlap list
`mainCascadeOverlapMoves` (Push Up, Band Pull Apart, Baithak) holds none of
the five, so its value-agreement test is unaffected.
