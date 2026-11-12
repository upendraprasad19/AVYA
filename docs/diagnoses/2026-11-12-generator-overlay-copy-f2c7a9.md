---
bug_id: f2c7a9
date: 2026-11-12
batch: generator-step1-1bf2
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-495 (items 1B-7 and 1B-11 of the step-1 plan, split out of Unit 1B-F under section 4.12.1): two label sets for one
  exercise. 27 library rows carried a core-list overlay (`slot_pattern` on 13, `slot_focus` on 19) that only the
  core-list picker read (`slot_pattern ?? movement_pattern`, `slot_focus ?? target_focus`); every other reader read the
  row's own field. So the thin-day top-up's queryV4 (an injured user's day under 3 exercises) filtered E048 Glute
  Bridge as `hip_isolation` while the picker placed it as `hip_dominant`; the muscle label showed the old
  `target_focus` on 19 rows; the cloud `exercise_library.movement_pattern` held the old first element on 12 rows; and
  the plan audit judged "a loaded row of the same pattern could be used" by labels the picker never used (116 plans
  flagged `unloaded`, 275 `improvised`, most of them by the old labels).
concept: core_list_pool
sot_registry_entry: core_list_pool
contract_test_path: test/contracts/library_overlay_copy_test.dart
related_bugs: [c1d7a4, b7e2c4, c2a7f1, e4b7a2]
recurrence: |
  A recurrence of the writer / reader drift class (CLAUDE.md section 4.1, the default suspect): one concept (an
  exercise's movement pattern and muscle focus) written to two fields and read from different ones by different
  readers. It was a deliberate, ruled design while the core-list pool sat behind `enable_core_list_pool` (B1 Ruling 4,
  docs/plans/2026-10-22-library-core-list-pool.md:83: the overlays are ON-only so the OFF world stays byte-identical,
  and the flip copies them in). Unit 1B-F flipped the pool and split the copy out, so from 2026-11-11 the drift had no
  OFF world to protect. c1d7a4 (Batch C1) is where the importer first passed a source row's overlay through (LINK);
  b7e2c4 (S1b-2) gave N19 / N20 their `slot_pattern` (N19's was dropped by the founder, 2026-11-09, and stays
  `hip_isolation`); c2a7f1 (C2a) measured removal depth under both semantics and is left alone (its frozen
  `depth_before` cells were measured under the slot semantics). The known-good fix of the class is applied: one field,
  one writer, every reader on it, and a test that fails if a second field is read again (the planted-overlay test).
  e4b7a2 (Unit 1B-R) is cited because its audit residue (Hamstring Walkout, Nordic Curl as `unloaded`) was partly this
  label drift in the audit, not in the plans.
writers:
  - { file: scripts/data/library_overlay_copy_v27.json, method_or_widget: "the overlay-copy record: 26 kept rows, before {movement_pattern, target_focus, slot_focus?, slot_pattern?} and after {movement_pattern, target_focus}", line: 1 }
  - { file: scripts/add_library_batch_c_v15.js, method_or_widget: "the OVERLAY-COPY STAGE: readOverlayCopy, overlayCopyRow (at before -> after with both keys removed; at after left alone; anything else refused)", line: 475 }
  - { file: scripts/add_library_batch_c_v15.js, method_or_widget: "LINK = ['same_movement_as'] (slot_pattern left the pass-through)", line: 112 }
  - { file: scripts/data/library_batch_c_source.json, method_or_widget: "N20 movement_pattern knee_dominant -> hip_dominant, its slot_pattern removed", line: 57297 }
  - { file: lib/core/services/seed_service.dart, method_or_widget: "_exerciseLibraryVersion 26 -> 27", line: 189 }
  - { file: supabase/migrations/176_reseed_exercise_library.sql, method_or_widget: "re-seed: 12 rows' movement_pattern (TEXT, first element) change; inline rollback restores the 12 old values as bare strings", line: 1 }
  - { file: scripts/seed_exercise_library.js, method_or_widget: "BATCH (library v27, Unit 1B-F2, previous 175) and the rollback emitter's TEXT_FROM_ARRAY / restoreValue (firstOrNull for movement_pattern and exercise_type)", line: 46 }
readers:
  - { file: lib/shared/repositories/plan_engine/core_list_selector.dart, method_or_widget: "rankedPool patternOk / target and subFocusMatches read movement_pattern / target_focus (were the overlays)", line: 225 }
  - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: "queryV4 movement_pattern / target_focus filters (only caller: the thin-day top-up, exercise_selector.dart:662)", line: 312 }
  - { file: lib/core/utils/exercise_display.dart, method_or_widget: "ExerciseDisplay.formatMuscleLabel (the label changes on the 19 slot_focus rows)", line: 9 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "a swap copies the incoming row's target_focus into the plan row (display only)", line: 576 }
  - { file: lib/core/services/seed_service.dart, method_or_widget: "seedIfNeeded version gate: a v26 box rewrites the 27 rows by id", line: 228 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: "snapshot exercise label (reads category first; target_focus unchanged in effect for the 27 rows)", line: 614 }
  - { file: lib/features/ai_coach/services/injury_swap_planner.dart, method_or_widget: "reads target_focus only when it is a String; library rows hold a List, so no change", line: 196 }
hive_key_prefix: "exerciseBox rows (seed v27); plan_json.workouts[].exercises[].target_focus (stored plan rows keep the label they were generated or swapped with)"
hive_key_formula: "exerciseBox[<id>].movement_pattern / target_focus for the 27 ids"
sync_methods:
  - "none on the client: the library is bundle-seeded; the cloud copy is written by migration 176"
restore_methods:
  - "the exercise library re-seeds from the bundle (v26 -> v27); plan_json restore unchanged"
cloud_table: exercise_library
cloud_columns:
  - movement_pattern
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: generation reads exerciseBox at generation time; the seed runs before every generation path (splash_screen.dart:160, train_provider.dart:787, onboarding_provider.dart:563)"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: the seed writes the shared exerciseBox; no user-scoped box is touched."
forbidden_patterns_checked:
  - { pattern: "a library row that still carries slot_pattern or slot_focus", absent: true }
  - { pattern: "a reader of slot_pattern / slot_focus under lib/", absent: true }
  - { pattern: "an uninjured plan that changes (golden 1,010 personas equal, plan_dump byte-identical)", absent: true }
  - { pattern: "a text[] literal written into the TEXT column movement_pattern by the rollback", absent: true }
  - { pattern: "an unsafe pick from the top-up's wider label set (queryV4's injury filter is unchanged; sweeps' unsafe zeros hold)", absent: true }
proposed_fix: |
  Ruling 1 (data): the 26 kept rows take the record's after (the overlay value) in movement_pattern / target_focus and
  lose both keys, through a new multi-key overlay-copy stage in the importer; N20 (a Batch C source row) is edited in
  the source and `slot_pattern` leaves the importer's LINK list. N19 stays `hip_isolation` (founder 2026-11-09).
  Ruling 2 (reader): CoreListSelector reads the rows' own fields (three reads).
  Ruling 3 (seed): v27; a v26 install rewrites the 27 rows by id.
  Ruling 4 (cloud): reseed migration 176, generated by the seed generator from a per-column record
  (scripts/data/library_f2_movement_pattern.json, the 12 rows whose first element changes; E064 keeps cardio). The
  generator's rollback emitter wrote a JSON array as a text[] literal. Postgres does NOT refuse that in the TEXT
  columns movement_pattern / exercise_type: it assignment-casts it to the text `{vertical_push}` (measured in the local
  rehearsal), so the rollback would have corrupted 12 rows silently. It now maps those two through firstOrNull
  (TEXT_FROM_ARRAY).
  Ruling 5 (scope): no kill switch. Section 4.6 names the plan generator among its triggers, so this is a stated
  exception: there is no new code path to gate (the reader change is an identity on the shipped data, proved by the
  golden, the plan dump and library_overlay_copy_test.dart's per-row identity with the old reader); the one output change,
  the injured top-up, is bounded by the exact sweep ratchet; the founder ruled the copy into the flip with no gate (B1
  Ruling 4). Ship-dark (section 4.12.4) was considered: a data flag would need both label sets shipped side by side,
  which is the overlay this unit removes.
  Rollback: reverting the commit restores the picker's behaviour (bundle and seed v26 return with the next install of
  that build). A device already at seed v27 keeps the copied rows (the seed upgrades only when the stored version is
  lower); the reverted reader then reads `slot_pattern ?? movement_pattern` = the copied values, so its plans are
  unchanged but its injured top-up keeps the new labels. A full data rollback is a seed v28 writing the overlays back
  (the record's before) plus migration 176's inline rollback.
regression_test_planned: |
  test/contracts/library_overlay_copy_test.dart (the data; the per-row identity with the old reader on the v26 library;
  a planted overlay moves no core-list pool of any V4 slot, and would have moved pools under the old reader);
  test/contracts/library_seed_v27_upgrade_behavioral_test.dart (a v26 box ends at v27, the 27 rows as bundled, every
  other row unchanged, the v26 sha256 pin; MIRROR);
  test/scripts/library_media_importer_test.dart group "the overlay-copy stage" (a) to (e);
  test/contracts/exercise_library_cloud_seeded_test.dart (the F2 rollback shape; restores equal 175's values; the file
  differs from 175 on exactly the 12 tuples; the emitter without firstOrNull is caught in a sandbox; the S1b-3 merge
  branch keeps its sandbox under a restated BATCH);
  test/contracts/exercise_library_cloud_tuples_match_test.dart (the generated SQL equals migration 176).
impact_analysis: |
  Platform tier (plan engine reader) with account-tier library data and a cloud re-seed. Uninjured plans: unchanged.
  Injured plans: the top-up may pick differently (one sweep block fell, none rose). Display: the muscle label of 19
  rows. Cloud: 12 movement_pattern values; no Edge Function reads that column. The app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "core_list_selector.dart reads movement_pattern / target_focus; flutter analyze clean; library_overlay_copy_test green; mutations below red" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeded v26 -> v27 (library_seed_v27_upgrade_behavioral_test; MIRROR: a v27 box is not rewritten)" }
  - { layer: postgres_schema, status: verified, evidence: "exercise_library.movement_pattern and exercise_type are TEXT (backups/live_schema_columns.json; the generator's INSERT flattens with firstOrNull); no schema change" }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "migration 176 applied 2026-11-12 on the founder's explicit go (apply_migration_via_api.js, HTTP 201); live read-back 934 / 870 / 64 before and after, the other 922 rows' md5 unchanged (9b21684f...), the 12 rows at the new values" }
  - { layer: migrations_applied, status: fixed_in_this_batch, evidence: "176 minted by scripts/mint_migration.sh (MIG-176); backups/applied_migrations.json entry with the file hash (Gate 39 and Gate 14 pass)" }
  - { layer: edge_function_code, status: verified, evidence: "no Edge Function reads exercise_library.movement_pattern (getFormCues selects name, cues, mistakes, instructions, muscles, difficulty, logging type)" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the stored plan rows keep their target_focus until regenerated or swapped" }
---

## Root cause

Measured on main 67b536e4. B1 (seed v13) wrote the core-list labels as overlays so the OFF world (queryV4, the old
cascade) stayed byte-identical; the flip (Unit 1B-F, 2026-11-11) made the core-list pool the only picker and deleted
the OFF world, but split the copy out (OI-495). From then on, the picker read the overlay and every other reader read
the row's own field: queryV4 in the injured thin-day top-up, the muscle label, the cloud column and the plan audit.

## Measured (prototype = the final asset and reader)

- Golden (1,010 personas): equal to main's fixture, 0 keys differ.
- 2,304-plan audit (no injuries): `plan_dump.jsonl` byte-identical to main (sha256 5b3da296...). `audit.json` differs
  only because the audit's checks read the target fields: `unloaded` plans 116 -> 46, `improvised` 275 -> 0, verdicts
  suitable 482 -> 513, needs work 1519 -> 1763, not suitable 303 -> 28. A measurement correction, not a plan change.
- Injured sweeps: `f_repeat_pairs30 full_gym` thin days 27 -> 21 (ratchet lowered in `injury_floor_sweep_lib.dart`);
  every other block equal; one-exercise days and empty days unchanged; unsafe picks 0.
- Core-list gate (1,036 personas): green.
- Cloud: migration 176 differs from 175 on exactly the 12 tuples (asserted in exercise_library_cloud_seeded_test).

## Fixture re-records (named ids only)

`test/fixtures/exercise_library_v12_row_hashes.json`: re-recorded with `RECORD_LIBRARY_REFERENCE_IDS` for exactly the 26
kept overlay rows E015, E046, E048, E050, E064, E090, E114, E118, E122, E127, E133, E172, E175, E186, E198, E222, E264,
E272, E273, E274, E275, E276, E277, E289, E290, E292 (the frozen-reference test named exactly these 26 red before the
re-record). The seed tests v23 to v26 rebuild their older bundles through `withOverlaysV26`
(`test/helpers/library_overlay_v26.dart`), so their sha256 pins are unchanged and prove the helper.

## Mutations (rule 21)

Each applied (grep count checked) and restored (cmp against a copy):

- `core_list_selector.dart`: `slot_pattern ?? movement_pattern` restored in `patternOk`; `slot_focus ?? target_focus`
  restored in `target`; `slot_focus ?? target_focus` restored in `subFocusMatches`: each reddens 1 test,
  library_overlay_copy_test's planted-overlay test.
- `library_overlay_copy_v27.json`: E015's after changed to `vertical_push`: reddens 1 test (the data test).
- `seed_service.dart`: `_exerciseLibraryVersion` back to 26: reddens the v27 seed test's "a v26 box ends at v27".
- The seed generator's `restoreValue` without firstOrNull (sandbox copy): the generated rollback holds
  `SET movement_pattern = ARRAY['vertical_push']::text[]` and the F2 shape check reports it.
- The importer's stage (test/scripts/library_media_importer_test.dart): at before -> after; `--check` fails at before;
  a partial match refused naming the id and key; an unnamed overlay key refused; an absent record a no-op; a source,
  unknown or repeated id refused.

## Skill self-evolution

The rollback emitter's silent cast is recorded as debugging skill class 2.154 (`.claude/skills/debugging/bug-classes.md`,
SKILL.md table): a JSON array written into a TEXT column is not refused by Postgres, it becomes the text `{x}`.
