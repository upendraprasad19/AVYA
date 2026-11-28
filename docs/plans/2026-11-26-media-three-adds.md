# Plan: three old-row animations (E051, E109, E264) — r3

Branch `media-three-adds`. Blast radius: account. Founder approval, 2026-11-26 chat: "Yes, add the 3" (the question named
the three files and the live Storage upload). Recipe: `docs/operations/EXERCISE_MEDIA.md` section 6, "Add or release old-row pairs". OI-443.

| Row | equipment_needed | New file | 2026-10-17 record |
|---|---|---|---|
| E051 Standing Calf Raise | barbell | 0108 Barbell Standing Leg Calf Raise | picked 0605 (a machine); `held`, in `equipment_mismatch` |
| E109 Glute Kickback (Cable) | cables | 0228 Cable Standing Kickback | no pick (0228 discarded by the "first pass (auto)") |
| E264 Table Row | elevated surface | `table-row-clean` (founder's own file) | picked N001; `left_out` |

Evidence for the pictures: three source frames and the Wardroom still per file, looked at on 2026-11-26. Equipment matches the row in all three.

## Two tool facts the recipe does not cover
1. `scripts/build_library_media_v16.js:41,226-228,326` accepts only 4-digit gif numbers; the ledger entry `table-row-clean` is skipped
   as "never mappable". Its ledger record is otherwise complete (stage ready, animation and thumbnail sha256, 12 frames, 389,712 bytes).
   `test/helpers/library_media_table_checks.dart:9` and `scripts/upload_exercise_media.js:34` also require a 4-digit slug prefix.
2. `test/helpers/library_old_rows_input_checks.dart` rule P2 requires every bucket pair to be a 2026-10-17 pick with the same gif,
   so neither a different gif (E051) nor a row with no pick (E109) can enter.

## Changes
A. **Builder:** one explicit constant `FOUNDER_FILES = { '9001': 'table-row-clean' }`. The number 9001 addresses that one ledger id;
   slug `9001-table-row`. No other non-numeric ledger id becomes mappable; a ledger that also has a real `9001_` entry fails.
   Checks of `verify()` (paths, sha, bytes, frames, size cap) apply unchanged. The three 4-digit regexes stay as they are.
B. **Picks record:** add a top-level `repicks` object to `docs/audit/library-old-rows-picks-2026-10-17.json`:
   `{"E051": {"gif_id": "0108", "replaces": "0605", "decided_by": "founder chat 2026-11-26 ..."},
     "E109": {"gif_id": "0228", "replaces": null, ...}, "E264": {"gif_id": "9001", "replaces": "N001", ...}}`.
   The original `picks` list is not edited.
C. **Rule helper:** the effective pick map is `picks` overlaid with `repicks`. New rule P8, fail closed: each repick needs a non-empty
   `decided_by`, a `gif_id`, and `replaces` equal to the original pick (null only if there is none); and every repicked id must be in
   `entries` with `released_by`. Mutation tests for each leg (empty decided_by, wrong replaces, repick not in entries, no released_by).
D. **Input file:** move E051 out of `held` and E264 out of `left_out`; add the three entries with `equipment_checked: true` and `released_by`.
E. Recipe steps 2-5: `build_library_media_v16.js --old-rows ... --write` (needs the folder, which lives in the primary checkout:
   pass `--wardroom-dir`); `upload_exercise_media.js --only <3 slugs> --execute --report <outside repo>` then `--verify --only`;
   `add_library_batch_c_v15.js`; `bundle_exercise_stills.js --src` then `--check`; bump `_exerciseLibraryVersion` 28 -> 29.
   The upload happens only after both plan reviews converge. Objects are additive; rollback is `--delete-object` after the Hold recipe.
F. Pins and docs: grep `test/`, `lib/`, `supabase/functions/`, `docs/` for the seed version 28 and the media counts
   (758 rows -> 761, 757 files -> 760, 137 old rows -> 140, total bytes) and repoint; update EXERCISE_MEDIA.md (counts, FOUNDER_FILES,
   repicks), `docs/sot_registry.yaml` line ranges if moved, OI-443 (held 10 -> 9, left_out 1 -> 0).
G. E109 has a still-image plate (`demo_slug: cable-kickback`): with media it shows the animation instead, and
   `disable_exercise_animations` falls back to the plate. Check the plate-sheet tests.

## Not in scope
The other held pairs, any equipment retag, Supabase tables, migrations, Edge Functions, app Dart logic (only the seed constant), APK build, merge.

## Verification
Media, stills, seed, plate-sheet and importer tests; `build --check`; importer `--check`; stills `--check`; upload `--verify --only`
(sha match plus the privacy probes); `flutter analyze --no-fatal-infos`; pre-commit gates; CI on the PR; B-pass before merge.

## r2 amendments (review 1: NOT converged; each overrides the r1 text above where they differ)

R1 (P0). The r1 builder change fails: `slugFor` (builder:251-255) compares kebab(name) `table-row-clean` with kebab(id.slice(5))
`row-clean` and refuses; table leg (g) (`library_media_table_checks.dart:139-147`) repeats the slice. New A:
`FOUNDER_FILES = { '9001': { ledger_id: 'table-row-clean', slug: '9001-table-row-clean' } }`. `byNum`, `slugFor` and leg (g)
special-case ONLY that exact gif + ledger_id pair (a 9001 slug with any other ledger_id, or that ledger_id under another gif, fails).
The fixed slug skips only the two-derivations comparison; every `verify()` file check still applies. A fixture ledger without
the entry stays valid unless 9001 is referenced. A real `9001_` ledger entry beside it fails. 9001 in the G/N media map is refused.
Tests for each leg, in the builder tests and the table checks, each mutated once.

R2 (P1). `library_seed_v23..v28_upgrade_behavioral_test.dart` rebuild old bundles from the CURRENT asset and compare sha256.
Add one shared helper that removes the three media keys from E051/E109/E264 and apply it in every rebuild; the six digests stay
unchanged. Add `library_seed_v29_upgrade_behavioral_test.dart` (v28 box -> v29 writes exactly the three rows; mirror: a box at 29
is not rewritten; v28 rebuild digest pinned, computed independently with Python from the base commit). Mutate: leave the
constant at 28 and confirm it reddens.

R3 (P1). Every literal current-version `28` in the v16 and v18..v28 tests (including the MIRROR `_markSeeded(hive, 28)`) becomes 29.
`_markSeeded(hive, 27)` style "previous version" calls stay. The cloud generator label `library v28, OI-523` stays.

R4 (P2). P8 hardened: P1 AND P2 both read the effective map (so E109 is partitioned too); `repicks` must be a map; each id an
E row of the library; `decided_by` a trimmed non-empty String; `gif_id` != `replaces`; `replaces` compared with the ORIGINAL
`picks`, never the overlay; each repicked id in `entries` with a non-blank `released_by`. A test pins the exact three
id->gif pairs (E051 0108, E109 0228, E264 9001), because editing repick and entry together would otherwise stay green.
Mirror mutations: repick parked in a bucket; blank released_by; wrong replaces; empty decided_by; gif_id == replaces.

R5 (P2). Rollback of one of these rows: the EXERCISE_MEDIA "Hold" recipe edits the C1 source and cannot undo an E row. Instead:
move the entry back (E051 -> `held` with 0605, E264 -> `left_out` N001, E109 removed) AND delete its repick, rebuild with
`--old-rows`, importer, stills, seed bump, then `--delete-object`. Write this into EXERCISE_MEDIA section 6.

R6 (P2) docs: EXERCISE_MEDIA lines 24, 129, 133, 175 (137/106/31 -> 140/107/33) and section 1 counts; GO_LIVE_CHECKLIST 5.8;
OI-443 counts (including "754/106"); `exercise_media_fields` registry prose; `seed_service.dart:193` citations in
`docs/sot_registry.yaml` if they move. Reviewer's predicted totals: 761 rows, 760 files, 312,506,374 animation bytes,
stills 3,814,554 bytes — take the final numbers from the built table, not from here.

R7 (P3). Held source row G0108 already maps gif 0108: note on OI-437 that releasing it would duplicate E051 with a shared
animation. The old HELD-E051 / E264-OWN-FILE closure entries are history and stay; the new equipment check and decision go in
`docs/audit/library-old-rows-equipment-check.json` only if no rule or hash depends on the old shape (else in the repick record).

Review 1 answers: readers (client, resolver, upload tool, stills bundler, schema test, importer) accept `9001-table-row-clean`;
no cloud migration (the cloud tuples test excludes media keys).

## r3 amendments (review 2: design works end to end on temp copies; two plan-text defects; override r2 where different)

S1 (corrects R2). The "every other row is unchanged" tests in v24..v28 seed their Hive box from the same rebuild, so stripping the
media keys inside the rebuild makes the upgrade "change" E051/E109/E264. Apply the strip helper ONLY inside the digest
expression (all six digest tests); the box keeps being seeded from the unstripped rebuild. Digests stay unchanged.

S2 (replaces R5). Rollback is whole-batch only: revert table, input, repicks record, library, stills, test pins and docs to the
pre-batch content; keep the builder/rule code if wanted but with no 9001 or repick in use; set the seed to **30** (never back to 28);
then `upload_exercise_media.js --delete-object <name> --execute --confirm-bucket exercise-media --report <path>` for the three
objects (it accepts names absent from the table, upload:664-667). A per-row rollback is not supported and EXERCISE_MEDIA says so.
The `held.rows`, `left_out` and `equipment_mismatch` keys of the equipment-check record stay unchanged (P3 and P7 read them,
and the rollback needs them), which settles R7: the new decision is recorded in `repicks` only.

S3 (adds to R6): also `docs/reference/exercise-library.md:16-17`, `docs/naming_conventions.md:257` (already stale), EXERCISE_MEDIA
lines 12, 15, 16 (still says seed 24), 30, 49-52 (including the egress arithmetic) and 72.

Review-2 measured totals (prototype): 761 rows, 760 files, 312,506,374 bytes, stills 3,814,554 bytes, 140 old rows.

S4 (review 2 confirm: CONVERGED; two wording fixes). In S2 "revert test pins" means: current-version literals become 30, not 28
(previous-version seeds stay; the v29 test and strip helper are deleted or rewritten for 30). "Keep the code" means: either revert
P8 with its tests, or keep it with `repicks: {}` and remove the three-pair pin and real-data mutation tests.
