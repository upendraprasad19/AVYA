---
bug_id: e7f118
date: 2026-10-22
batch: library-data-repair
blast_radius: platform
status: fixed
symptom: >
  On 19 paired exercise plates the sheet's START panel showed where the rep ENDS and the
  END panel where it starts: Pike Push Up opened head-down, Pull Up opened with the chin
  over the bar (founder review export our_image_start_end_swapped, 2026-10-21: 19 rows on
  19 distinct slugs, all pairs). Two rows pointed at a drawing of a different movement
  (export our_image_marked_wrong): E207 Torso Twists at a standing stretch
  (torso-twist-stretch, its only user) and E179 Toes to Bar at the hanging leg raise it
  shared with E057.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
related_bugs: [e1a7c4, ada3fb, b7d3e1, 46fc99, 2390f5]
recurrence: >
  Recurrence of the exercise_library_schema class (this batch's b7d3e1, 46fc99, 2390f5):
  bundled library data that disagrees with what it describes. Known-good fix reused:
  correct the data at its writer, ship with the v12 seed bump, pin with a contract test.
  NEW here: the defect sat in the upstream catalogue's frame order, so the fix also lives
  in the asset pipeline (SWAP_FRAMES) or a rebuild would re-introduce it.
writers:
  - { file: scripts/build_exercise_plates.py, line: 63, source: "SWAP_FRAMES: the 19 slugs whose upstream frame 1 is the END; main() writes their frames swapped so <slug>-1.svg is always START" }
  - { file: assets/exercise_plates/pull-up-1.svg, line: 1, source: "the 38 committed SVGs of the 19 slugs swapped -1 <-> -3 (byte-identical renames: the crop is the union of both frames); torso-twist-stretch-1/-3.svg deleted" }
  - { file: assets/data/exercise_library.json, line: 1, source: "scripts/repair_exercise_library_v12.js dropPlates: E207 and E179 lose demo_slug and demo_pair" }
readers:
  - { file: lib/shared/widgets/exercise_plate/plate_resolver.dart, line: 57, source: "resolvePlate: assetPaths [<slug>-1.svg, <slug>-3.svg] for a pair, [] (monogram) for a row without demo_slug" }
  - { file: lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart, line: 137, source: "assetPaths[0] is captioned START and assetPaths[1] END" }
hive_key_prefix: n/a
hive_key_formula: "exerciseBox keyed by the row id E###"
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: "none: demo_slug / demo_pair are not cloud columns and the SVGs ship in the app bundle"
contract_test_path: test/contracts/exercise_plate_swap_record_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a — bundled assets, not user-scoped
forbidden_patterns_checked: >
  The swap is recorded by content, not by name: test/fixtures/plate_swap_hashes.json was
  written from the files BEFORE the swap ({slug: {"1": sha256(old -3), "3": sha256(old
  -1)}}), and no slug's two frames were identical, so a non-swap cannot pass. E179 keeps
  E057's hanging-leg-raise files (E057 still uses them; that slug is also one of the 19
  swaps). Counts after the change: 156 plated rows, 129 artwork-less, 152 slugs, 138 pairs,
  14 singles, 290 SVGs; every count pin was moved with it. The remaining
  'torso-twist-stretch' references are the vendored upstream manifest and dated spec notes.
proposed_fix: >
  Swap each of the 19 pairs' files through a temporary name; add SWAP_FRAMES to
  build_exercise_plates.py and apply it where the frames are written; delete
  torso-twist-stretch-{1,3}.svg; dropPlates removes E207/E179's plate keys (idempotent); the
  plates mapping json drops the two rows (158 -> 156).
regression_test_planned: >
  test/contracts/exercise_plate_swap_record_test.dart (4; RED 3/4 first, the fixture-coverage
  test passing from the start as a structural pin): SWAP_FRAMES declares exactly the 19
  slugs; each slug's committed -1/-3 hash equals the fixture; E207/E179 carry no plate key
  and torso-twist-stretch is gone. Count pins updated in exercise_plate_assets_present_test,
  exercise_plate_library_data_test, exercise_plate_resolver_test and the schema contract;
  every exercise_plate_* test plus plate_attribution_surface_test green (61). MUTATIONS,
  restored from byte copies and checked with cmp: pull-up's two files un-swapped -> the hash
  test red (both files named); "v-up" removed from SWAP_FRAMES -> the declaration test red.
  VISUAL: Pike Push Up and Pull Up -1/-3 rendered side by side (headless Edge, scratchpad
  platecheck/plates.png): START shows arms extended / a dead hang, END head lowered / chin
  over the bar.
impact_analysis: >
  Every user who opened the plate sheet for these 19 exercises saw the movement backwards,
  which teaches the wrong starting position (a pull-up from the top, a pike push-up from
  the bottom). Toes to Bar and Torso Twists now show the monogram plate instead of a wrong
  picture. Display only: plates do not feed generation.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "38 SVGs swapped, 2 deleted, 2 rows' plate keys dropped; 61 plate tests green" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "the batch's v12 seed bump rewrites E207/E179 without plate keys in every install via putAll (putAll replaces the whole map)" }
  - { layer: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json: exercise_library carries no demo_slug / demo_pair column" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "no Edge Function reads plates" }
---

## Root cause

The upstream catalogue numbers its frames by drawing order, not by movement phase, and on
19 pairs it drew the finish first. The pipeline mapped frame 1 to START for every pair.
Separately, the slug mapping matched two rows to a drawing by name similarity rather than
by movement.

## Fix

The pipeline now carries the 19 swaps, the committed files are swapped to match, and the
two mismatched rows lose their plate keys.

## Verification

Swap-record test RED then GREEN, every plate test green, two mutations reddened, and a
visual check of Pike Push Up and Pull Up. The visual check rendered the asset files
themselves; the sheet's START = `-1.svg` mapping is pinned by exercise_plate_resolver_test.
