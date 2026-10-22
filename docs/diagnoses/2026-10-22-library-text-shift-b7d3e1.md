---
bug_id: b7d3e1
date: 2026-10-22
batch: library-data-repair
blast_radius: platform
status: fixed
symptom: >
  On 136 of the 292 bundled library rows every text field from met_value to source sat one
  column to the right. The app showed a number as the breathing cue (suppressed by a guard,
  so the section simply vanished), the breathing text as the first coaching cue, the cues
  under "common mistakes", and the mistakes as the warm-up. The AI coach's cloud copy carries
  the same shift: on 2026-10-22 cloud E013 Lateral Raise returned coaching_cues
  ["Natural breathing"] and common_mistakes ["Slight forward lean; lead with elbows not
  hands; stop at shoulder height"]. Separately, the 156 healthy rows stored their cues as ONE
  "; "-joined string (115 coaching_cues rows, 84 common_mistakes rows), which the active-
  workout coaching panel renders as a single packed bullet. OI-149 had recorded the text as
  unrecoverable; it was never lost, only shifted.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
related_bugs: [e1a7c4, ada3fb]
recurrence: >
  Recurrence of the exercise_library_schema class (e1a7c4, 2026-07-19: 9 stub rows with a
  different key set). Same known-good fix: rewrite the rows in the bundled JSON, bump the
  seed version so putAll rewrites every install, and regenerate the cloud seed (ada3fb
  pattern), with a contract test over the bundled file.
writers:
  - { file: assets/data/exercise_library.json, line: 1, source: "136 rows' text fields moved back by scripts/repair_exercise_library_v12.js repairText; every row's coaching_cues / common_mistakes split into one cue per item" }
  - { file: lib/core/services/seed_service.dart, line: 194, source: "_seedExercises putAll rewrites each row on the v12 re-seed (version bump lands with Task 2 of the same batch)" }
readers:
  - { file: lib/features/train/screens/active_workout/coaching_content_panel.dart, line: 75, source: "_stringList renders each list element as one bullet and does NOT split on ';' (packed bullet)" }
  - { file: lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart, line: 43, source: "_cues splits on ';' — rendered healthy rows correctly, the shifted rows' wrong fields regardless" }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, line: 1254, source: "PlannedExercise.notes = coaching_cues.first — the packed string before, one cue now" }
  - { file: supabase/functions/_shared/tools/exercise/getFormCues.ts, line: 65, source: "AI coach form cues read cloud coaching_cues / common_mistakes (shifted in cloud; fixed by the batch's cloud re-seed)" }
hive_key_prefix: n/a
hive_key_formula: "exerciseBox keyed by the row id E###"
sync_methods: n/a
restore_methods: n/a
cloud_table: exercise_library
cloud_columns: coaching_cues, common_mistakes
contract_test_path: test/contracts/exercise_library_text_shape_contract_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a — exerciseBox is a global bundled seed, not user-scoped
forbidden_patterns_checked: >
  The shifted rows were identified by data, not by list: exactly the rows whose breathing_cue
  matches ^\d+(\.\d+)?$, which are also exactly the rows with a null met_value (136 = 136,
  same ids). The file key order met_value > cal_per_set_est > breathing_cue > coaching_cues >
  common_mistakes > warmup_protocol > pro_tip > is_indian_context > indian_alternative >
  source > is_active gives the chain. Two values fell into boolean columns and are lost: the
  original pro_tip (now is_indian_context = false) and the original source (now is_active =
  true). Healthy rows' cue strings contain no ';' that is not a separator (0 occurrences of a
  ';' followed by a non-space). check_equipment_audit.dart still passes after the move (it
  scans name, coaching_cues, common_mistakes, pro_tip and warmup_protocol).
proposed_fix: >
  scripts/repair_exercise_library_v12.js repairText, idempotent: for each shifted row,
  met_value <- old cal_per_set_est; cal_per_set_est <- Number(old breathing_cue);
  breathing_cue <- old coaching_cues joined with ', '; coaching_cues <- split(old
  common_mistakes) (E064's three-element list re-joined first); common_mistakes <- split(old
  warmup_protocol); warmup_protocol <- old pro_tip; pro_tip <- ''; is_indian_context <- (old
  indian_alternative == 'Yes'); indian_alternative <- old source; source <- ''. Then split
  every row's coaching_cues / common_mistakes on ';'. Written in the file's own layout
  (2-space indent, decimal met/cal), so the second run is byte-identical. The numeric-
  breathing guards in both renderers stay.
regression_test_planned: >
  test/contracts/exercise_library_text_shape_contract_test.dart (6): no numeric
  breathing_cue; every cue list non-empty with no ';' item; E013 and E064 pinned to values
  computed from the PRE-repair file; the four Indian-context ids and eight Indian
  alternatives recovered; met/cal decode as double. breathing_cue_numeric_suppressed_test
  now asserts 0 numeric rows; exercise_plate_sheet_test exercises the suppression on a
  synthetic copy of Surya Namaskar plus its mirror (the repaired row renders BREATHING).
  MUTATION: one E001 cue re-packed as "a; b" -> the shape test reddened (2 of 6, the second
  because the mutated file lost the decimal format); restored from a byte copy and verified
  with cmp.
impact_analysis: >
  Every user who opened FORM & CUES or the plate sheet on 136 exercises (including Lateral
  Raise, Face Pull, Pull Up, Rowing Machine and most cardio, core and mobility rows) saw the
  wrong text under every heading, and the AI coach served breathing text as form cues. On the
  156 healthy rows the coaching panel showed all cues as one paragraph. Data-only fix, no
  behaviour change in generation: cue text feeds only display and PlannedExercise.notes.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "two stale OI-149 comments rewritten; guards unchanged; 31 tests green across the Task 1 set" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "bundled JSON repaired; the v12 seed bump (same batch) rewrites every install's exerciseBox via putAll" }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "pre-apply 2026-10-22: cloud E013 coaching_cues = ['Natural breathing'] (the shift), 292 rows, 0 inactive, 0 aliases. Migration 162 applied 2026-10-22 11:38 IST; post-apply checks by UUID v5: 285 kept rows active, 7 retired inactive, 7 with name_aliases, E013 cues = bundled, E165 cues = E216's, E260 {dumbbells,bench} kept" }
  - { layer: migrations_applied, status: fixed_in_this_batch, evidence: "162_reseed_exercise_library.sql rehearsed on prod inside BEGIN/ROLLBACK (same checks, all true; live unchanged after), then applied via .claude/apply_migration_via_api.js (HTTP 201); backups/applied_migrations.json entry 162 with the file's sha256, same commit as the .sql" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "getFormCues reads columns; no code change, no deploy" }
---

## Root cause

A spreadsheet column shift on 136 rows moved every field from `met_value` to `source` one
place right, in file key order. The rows are exactly the ones whose `breathing_cue` is a bare
number, which coincide with a null `met_value`. OI-149 checked the seed migrations and git
history for the "lost" breathing text and concluded it existed nowhere. It sat in
`coaching_cues` the whole time.

## Fix

`repairText` moves each value back, splits every cue list into one cue per item, and writes
the file in its own layout. The cloud copy is regenerated from the repaired JSON in Task 6.

## Verification

Contract test 6/6 (RED 5/6 first), the Task 1 set 31/31, the equipment audit PASS, mutation
reddened. The live cloud shift was confirmed before the fix.

## B-pass hardening (2026-10-22)

`docs/reviews/library-data-repair-bpass.md` Findings 1, 2, 3 and 5. Migration 162's header now
says `Destructive?: yes` (it rewrites rows) and carries an inline rollback: re-apply 125, then 126
(125 predates that fix to E260), then clear `name_aliases` (125 never wrote it). The cloud-seeded
test pins the header and that the retire UPDATEs run after the upsert. The active-workout panel's
numeric-breathing guard, until now pinned only by a source-grep, has a rendered-widget test
(`coaching_panel_numeric_breathing_behavioral_test.dart`, synthetic row plus Surya Namaskar mirror;
mutation: guard replaced by `false` reddens the synthetic case only).
