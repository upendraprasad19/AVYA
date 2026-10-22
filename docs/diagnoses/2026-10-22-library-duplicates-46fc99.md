---
bug_id: 46fc99
date: 2026-10-22
batch: library-data-repair
blast_radius: platform
status: fixed
symptom: >
  Seven bundled library rows duplicated a kept twin: the same movement under a second name,
  usually with the same drawing. E241 Close-Grip Bench Press / E016 Close Grip Bench Press,
  E240 Overhead Cable Extension / E097 Overhead Tricep Cable Extension, E225 Hip Abductor
  Machine / E107 Hip Abduction Machine, E249 V-Ups / E176 V-Up, E165 Quad Stretch / E216
  Standing Quad Stretch, E167 Cross Body Shoulder Stretch / E219 Cross-body Shoulder Stretch,
  E168 Doorway Chest Stretch / E220 Chest Doorway Stretch. The generator dedups on the
  picked NAME, so one plan could serve both twins as two different exercises, and the
  library counted 292 rows where 285 movements exist.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
related_bugs: [e1a7c4, ada3fb, b7d3e1]
recurrence: >
  Recurrence of the exercise_library_schema class (e1a7c4, 2026-07-19 stub rows; b7d3e1,
  this batch's text shift). Known-good fix reused: rewrite the bundled JSON, bump the seed
  version so every install re-seeds, regenerate the cloud seed (ada3fb), contract test over
  the bundled file. NEW for this class: a re-seed by putAll never deletes, so retiring a
  row needs an explicit prune; and a retired NAME must still resolve, so the kept row
  carries name_aliases.
writers:
  - { file: assets/data/exercise_library.json, line: 1, source: "scripts/repair_exercise_library_v12.js mergeDuplicates: 7 rows removed; each kept row gains name_aliases + merged_ids; same-pattern twins also take the union of target_focus / primary_muscles, the min priority_tier and the OR of is_foundational" }
  - { file: lib/core/services/seed_service.dart, line: 220, source: "_seedExercises putAll writes the 285 rows (seed v12)" }
  - { file: lib/core/services/seed_service.dart, line: 223, source: "pruneRetired(exerciseBox, retiredLibraryIds(entries.values)) deletes the merged_ids keys from an existing install" }
  - { file: lib/core/services/sync/sync_community.dart, line: 529, source: "the only other exerciseBox writer: community rows keyed by their user_custom_exercises UUID, put only when absent; it can never re-create an E### key" }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, line: 48, source: "getByExactName: exact-name loop, then a name_aliases loop (exact always wins)" }
  - { file: lib/shared/repositories/exercise_repository.dart, line: 69, source: "hasExactNameWhere: same two loops; the alias rows are checked after every named row" }
  - { file: lib/shared/repositories/exercise_repository.dart, line: 105, source: "search already matched name_aliases before this batch" }
  - { file: lib/shared/repositories/exercise_repository.dart, line: 253, source: "isCompoundByExactName goes through getByExactName, so a retired name keeps its compound flag" }
hive_key_prefix: n/a
hive_key_formula: "exerciseBox keyed by the row id E###; community rows by UUID"
sync_methods: n/a
restore_methods: n/a
cloud_table: exercise_library
cloud_columns: name_aliases, is_active, coaching_cues, common_mistakes
contract_test_path: test/contracts/exercise_library_merge_contract_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a — exerciseBox is a global bundled seed, not user-scoped
forbidden_patterns_checked: >
  Injury tags are never merged: the founder's 13-B carve-out keeps 'v-up' and 'hip
  abduction machine' untagged (k13bKeptSafe in injury_undertag_13b_contract_test.dart), so
  E176 and E107 keep injury_contraindications == []. That means a hip-injured Phase-1 user
  can now be given the Hip Abduction Machine, which is now foundational; E225's 'hip' tag is
  not carried over. This is the carve-out's intent ("hip machines stay safe") and is
  recorded here deliberately. Not merged (different movements): E075/E008, E261/E274,
  E117/E007. The stretches keep E216/E219/E220 because warmup_cooldown.dart:145-147 emits
  those names. The prune deletes only ids listed in merged_ids, never a UUID key.
proposed_fix: >
  mergeDuplicates (idempotent) applies the merge table and drops the 7 rows. SeedService
  bumps to v12; after putAll, pruneRetired deletes the retired ids that exist in the box.
  getByExactName and hasExactNameWhere keep their exact-name loop and add a second loop over
  rows whose name_aliases (trimmed, lower-cased) contains the target.
regression_test_planned: >
  exercise_library_merge_contract_test (285 rows; each retired id in exactly one merged_ids;
  no alias collides with a name; E107/E176/E016 selection fields and injuries pinned);
  library_seed_prune_behavioral_test (real Hive box: E241 deleted, E016 and a UUID community
  key kept, idempotent, empty box no-op); seed_prune_wired_test (presence only: the call
  sits after putAll inside _seedExercises, an asset-loading method); and
  exercise_alias_lookup_behavioral_test (retired names resolve; the compound check follows
  the alias; mirror: an exact name beats an alias that sorts first; queryV4 Phase-1
  hip_isolation/Glutes at full_gym returns E107 with and without the derived capability;
  E107's muscles credit the Glutes group). MUTATIONS, each restored from a byte copy and
  checked with cmp: (1) prune call removed -> wired test red (1); (2) _hasAlias forced
  false -> alias test red (4); (2b) the two loops collapsed into one name-or-alias loop ->
  the mirror red (1, returned 'A'); (3) E107 is_foundational false -> queryV4 red (1);
  (4) 'Glutes' dropped from E107 primary_muscles -> muscleGroupOf red (the set became
  {null}: neither 'Abductors' nor 'Glutes (medius)' maps to a group, so before the merge
  E107 credited no group at all) plus the merge contract's selection-fields test (2 red in
  all).
impact_analysis: >
  Readers that look a row up by id degrade to null when a stored plan holds a retired id:
  swap_service.dart:467, tool_dispatcher.dart:1899, ai_coach_provider.dart:1698,
  injury_swap_planner.dart:195, swap_exercise_diff.dart:99, tool_confirm_card.dart:356,
  template_service.dart:357 (keyed by name), train_provider.dart:377 and :411 (both fall
  back to the alias-aware search). Every one is null-safe: it falls through to the custom
  box and then to "unresolved". The plan's own audit counted 0 stored pre-merge ids; the
  re-check on 2026-10-22 found 0 in template_exercises, workout_log_exercises,
  workout_log_sets and workout_logs (by E-id, by library UUID and by name), but 8 of the 20
  user_progress.plan_json blobs hold E225 and 1 holds E241. Every account is a testing
  account (CLAUDE.md §1) and no store build ever shipped a pre-v12 library, so no real user
  can hold a retired id; the planned rows also carry the exercise NAME, which resolves
  through the alias. verified_clean. By-name scans that bypass the repo
  (workout_write_service.dart:303-317, auth_session_bootstrapper.dart:1202,
  logging_type_repair_migrator.dart:125) fall back to data-shape inference for a retired
  name, which gives these seven movements the same logging_type (the weighted ones log
  weight > 0, V-Ups is bodyweight, the retired stretches are never generated):
  verified_clean. Progression / PR series under a retired name do not join the kept name;
  cloud holds 0 logs under those names: verified_clean.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "seed v12 + pruneRetired; alias fallback in getByExactName / hasExactNameWhere; flutter analyze lib/ 0 errors, 0 warnings; Task 2 set + Task 1 set + injury/plate/equipment/cross-account tests 113/113" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_prune_behavioral_test over a real Hive box: retired key deleted, kept and community keys survive" }
  - { layer: postgres_data, status: verified, evidence: "2026-10-22 read-only: the 7 retired rows are live in cloud exercise_library (by UUID v5); 0 references in template/log tables; 8+1 test-account plan_json blobs. Cloud fix (is_active=false + kept cues) is the batch's Task 6 re-seed migration" }
  - { layer: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json: exercise_library has name_aliases and is_active; merged_ids stays local (not a cloud column)" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "no Edge Function code change" }
---

## Root cause

The library grew by appending rows from several sources, and seven of them restated a
movement an earlier row already held under a slightly different name. Nothing checked for
it: ids were unique, names were unique, and the generator's name-based dedup treats two
spellings as two exercises.

## Fix

Retire each duplicate into its twin. The kept row keeps its id and name, lists the old name
in `name_aliases` and the old id in `merged_ids`, and, where the twins served the same
movement slot, inherits the retired row's selection fields so that slot still fills. The
seed prunes the retired ids from existing installs, and the exact-name lookups fall back to
the alias so a plan written before v12 still finds its cues and drawings.

## Verification

Four new test files (20 tests), RED first; the wider set 113/113; equipment audit PASS over
285 rows; five mutations each reddened their test.
