---
bug_id: c41a7e
date: 2026-11-28
batch: media-two-new-two-retag
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Library change, not a defect report. Two rows had an animation waiting that showed different kit from the row (E027 T-Bar Row
  labelled barbell, picture a plate-loaded station; E120 Svend Press labelled barbell, picture a weight plate), and the library had
  no machine preacher curl and no forward band Pallof press although unused animations of both existed. Founder decisions
  2026-11-28 (plan docs/plans/2026-11-28-media-two-new-two-retag.md): add G0592 and G0979, retag E027 to machines with new
  instructions, retag E120 to dumbbells with instructions unchanged, no injury restriction on the Band Pallof Press.
  This is the diagnose doc the cloud seed migration header links, and the one the frozen row reference asks for: it re-records
  the rows E027 and E120 only.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
contract_test_path: test/contracts/library_v30_two_new_two_retag_contract_test.dart
related_bugs: [b4d9e1, d8ac69]
recurrence: |
  Not a recurrence. It follows the retag shape of d8ac69 (Batch C2c, E230) and the kept-row record shape of b4d9e1.
writers:
  - { file: scripts/add_library_batch_c_v15.js, method_or_widget: "RETAG_FILES list (E230, E027, E120) and the source rows G0592 / G0979", line: 225 }
  - { file: scripts/seed_exercise_library.js, method_or_widget: "kept-row records grouped by row id; BATCH v30", line: 57 }
readers:
  - { file: lib/core/services/seed_service.dart, method_or_widget: "_seedExercises (putAll by id at exercise_library_version 30)", line: 358 }
  - { file: supabase/functions/_shared/tools/exercise/getFormCues.ts, method_or_widget: "reads cloud coaching_cues by name or alias", line: 65 }
hive_key_prefix: "exerciseBox (exercise_library rows by id); no per-user key"
hive_key_formula: "exerciseBox.put(row['id'], row) in SeedService._seedExercises (putAll, whole map replaced by id)"
sync_methods:
  - "none: exercise_library is bundle-seeded to Hive and migration-seeded to the cloud; no client sync writes it"
restore_methods:
  - "none: the library is not user data; the next launch re-seeds from the bundle (seed version 30)"
cloud_table: exercise_library
cloud_columns:
  - equipment_needed
  - coaching_cues
ist_handling:
  - { file: supabase/migrations/CLAUDE.md, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: the seed runs at launch before the providers read the library"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: exercise_library is shared reference data (RLS USING true); no user row is written or read by this change."
forbidden_patterns_checked:
  - { pattern: "a hand edit of assets/data/exercise_library.json that the importer --check does not reproduce", absent: true }
proposed_fix: |
  Two new source rows through the importer; the importer's retag stage takes a list of records (E230, E027, E120); the two held
  old-row pairs are released into the media input with a recorded decision; media table, stills and upload for four objects;
  seed version 29 to 30; a cloud re-seed migration (two changed rows, two inserts, inline rollback). The cloud generator now
  compares the previous tuple with every record column of a row reverted at once, because E027 changes two cloud columns.
regression_test_planned: |
  test/contracts/library_v30_two_new_two_retag_contract_test.dart, test/contracts/library_seed_v30_upgrade_behavioral_test.dart,
  the retag-list group in test/scripts/library_media_importer_test.dart, and the v30 checker and generator guard in
  test/contracts/exercise_library_cloud_seeded_test.dart.
impact_analysis: |
  Platform tier. E027 leaves the basic_gym pool (machines is full_gym only), E120 enters home_dumbbells, G0592 enters full_gym and
  G0979 enters home_dumbbells, basic_gym and full_gym; the measured effect on generated plans is recorded in the plan-review
  record. The migration changes the live coach at once (getFormCues): a partial search for "pallof" returns Band Pallof Press
  ahead of Band Vertical Pallof Press, and E027's new cues reach installed apps whose bundled row still says barbell. Nothing
  under lib/ reads the cloud exercise_library table.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "SeedService._exerciseLibraryVersion 29 -> 30; importer --check byte-identical to the shipped library." }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v30_upgrade_behavioral_test.dart: a v29 box ends at v30 with the five rows as bundled (E027, E120, G0592, G0979, G0574) and every other row unchanged; a v30 box is not rewritten." }
  - { layer: postgres_schema, status: verified, evidence: "equipment_needed and coaching_cues are existing columns; equipment_tier and gym_availability are not cloud columns (COLUMN_SQL in the seed generator); no schema change." }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "the generated draft differs from migration 183 by exactly two changed tuples (E027, E120) and two new ones; the live apply and its per-row read-back are recorded in the apply commit and happen only on the founder's go." }
  - { layer: storage_buckets_objects, status: fixed_in_this_batch, evidence: "four objects (1,487,888 bytes): dry run 4 local files ok, 0 sha mismatch; the upload runs only on the founder's go and is verified with --verify." }
---

## G0574 joins the rotation (founder 2026-11-28)

The first CI run on PR #363 showed one real behaviour change: with E027 out of basic_gym, a basic_gym advanced repeat phase
(week 2) put Cable Low Seated Row on both the Pull and the Upper day (`cross_day_variety_behavioral_test.dart`, 0 -> 1).
Founder decision: G0574 Landmine T-Bar Row (barbell, basic_gym and full_gym, lower_back, picture checked against its still)
gets `core_levels: [intermediate, advanced]`; it also carries `same_movement_as: E027`, so a full gym never gets both
T-bar rows on one day. Both keys change in `scripts/data/library_batch_c_source.json`; neither is a cloud column, and the
regenerated cloud draft is identical to the one before the change.

**What else the link does.** `SameMovement` is symmetric for the same-day rule, so a previous-phase or swapped-away T-Bar
Row also soft-avoids the Landmine row for as long as the swap history window holds it, and a demoted T-Bar Row demotes it
(one direction, original to linked row). A basic_gym user who swapped away from T-Bar Row because the gym has no station
therefore sees the Landmine row ranked lower. Read from the code, not run.

**What the pairing gate can and cannot show.** Across the 998 golden personas (weeks 1 and 2) Landmine T-Bar Row sits on
8 days and T-Bar Row on 64, and no day holds both EVEN WITH THE LINK REMOVED, so those runs do not exercise the link. It
is a guarantee, pinned directly by the pairing test in `library_v30_two_new_two_retag_contract_test.dart`.

**A pre-v30 saved plan.** A repeat phase that pins T-Bar Row for a basic_gym user drops it without a substitute (OI-534,
parked until the store launch).

## Plan snapshots and pins re-recorded for library v30

Attribution: main's CI at the base `d2d92832` is green with the old library. Up to `f87869cd`, the run these values were
taken from, `lib/` changed only the seed version and comments (plus the plan-engine guide), so every moved value comes
from library data (the later merge of main brought PR 349's own `lib/` changes; CI on the merged head passed every plan
sweep with these values): E027 out of basic_gym,
E120 into home_dumbbells, G0592 and G0979 added, G0574 on the core list and linked to E027. Values were taken from the CI
run of `f87869cd` (every gate prints its counters), except the allocator's `over` map, its floor counts and the weekly
ON digest, which are cut off or unreached there and were printed locally.

| What | Moved |
|---|---|
| generator golden | 80 of 1,010 personas (76 grid, 4 injury) |
| balanced-week / loaded-wins / lead-first switch-off goldens | 122 / 122 / 134 of 1,010 |
| day-floor fixture | 328 combo keys; OFF digests of phases 1 and 4 for home_dumbbells, basic_gym, full_gym |
| day-floor counts | home_dumbbells: phase 1 thin-off 76 -> 80, knock-on 6 -> 9; phase 4 thin-off 188 -> 168 |
| goal-training baseline | 88 of 1,152 build and strength hashes (52 basic_gym, 36 full_gym); other sections untouched |
| goal-training counts | week-1 mains at a range bound 3601 -> 3591; both digests |
| weekly minimum | switch-off Core zero weeks 42 -> 45; ON digest |
| titration / plateau | per-goal counters and their totals (see the diff of the lib) |
| three random sweeps | they draw rows by index, so two new rows change every draw: digest, both `over` maps, floor seats 21 -> 27 |

Safety readings on the new values: day floor, 12 blocks, 6,720 persona runs, 0 days under 3 with the floor on, nothing in
`bad`; allocator floor seats past the clock 0 (the largest forced overrun in that sample is 154.8 s, was 198.0 s);
goal training 0 rep misses and no muscle group newly at zero; weekly minimum ON verdicts, new majors (0), over-time
maximum (6) unchanged; titration failure list empty and, for each goal, no more flat weeks under the band bottom with the
feature on than off.

## Frozen row reference

`test/fixtures/exercise_library_v12_row_hashes.json` is re-recorded for exactly **E027** (equipment_needed, equipment_tier,
coaching_cues) and **E120** (equipment_needed, equipment_tier, gym_availability).

## Plan review

Two context-blind Sonnet rounds. Round 1 found the planned step order would have left both new rows without injury tags and
media (the builders only see rows that already exist), the unit tests that stay red until the migration is applied, and missed
pins. Round 2 simulated the corrected order on a copy and converged, with wrong script flags and further pins.

## Mutations (rule 21)

Run against commit 4dd76242, one at a time, each confirmed applied (exactly one match, bytes changed) and restored byte for
byte (`git status --porcelain` clean afterwards). No compile errors. Counts are the runner's totals; in the cloud-seeded file
two of them are the tests that stay red until the migration is applied.

| Mutation | Tests red |
|---|---|
| `library_e120_retag.json` removed from `RETAG_FILES` | 4 (importer) |
| generator reverts only the first column of a row | 1 beyond the 2 expected: `setUpAll` of the CLI group, the generator refusing E027, so that group does not run |
| `Band Pallof Press` removed from the Dart safe pool | 2 |
| G0592's `media_slug` key renamed in the library | 2 (v30 contract) |
| `_exerciseLibraryVersion` left at 29 | 1 (v30 upgrade) |
| one v30 record's tier glob removed from `blast_radius.yaml` | 1 |

Run on 2026-11-28 after G0574 joined, one at a time, restored byte for byte:

| Mutation | Tests red |
|---|---|
| G0574's `same_movement_as` removed | 1 of the same-day gate, on its pair-count pin only (no shared day appears, see above); 2 of the v30 contract (G0574's values and the pairing test) |
| G0574's `core_levels` emptied | 1 (`cross_day_variety_behavioral_test.dart`, the repeat-phase case) |
