# Two new exercises and two equipment retags (library v30)

Branch `media-two-new-two-retag`, base `d2d92832`. Blast radius: platform (bundled library, plan-generator inputs, cloud
seed migration, live storage upload). Execution: inline, one writer. Plan review ×2, B-pass and
`docs/plan-reviews/media-two-new-two-retag.md` before merge.

## Founder decisions (chat, 2026-11-28)

1. Add **Machine Preacher Curl** (animation 0592) and **Band Pallof Press** (animation 0979). Row specs approved.
2. Retag **E027 T-Bar Row** barbell → machines, animation 0606, new instructions.
3. Retag **E120 Svend Press** barbell → dumbbells (the app counts weight plates as dumbbells), animation 0856,
   instructions unchanged.
4. Band Pallof Press carries **no injury restriction** (approved for this row; it is not a general "kept safe" list).
5. E095 Preacher Curl and E132 Pallof Press (cable) keep waiting for new artwork. Their held picks 0592 and 0979 go to
   the two new rows instead; releasing those held picks later would show one picture on two exercises (note on OI-443).

**Three separate approvals still needed, each asked at the time:** (a) upload of the four files to the live
`exercise-media` bucket; (b) the live cloud migration (`Destructive?: yes`: dry run and sign-off first); (c) the merge.

## Rows

New ids `G0592`, `G0979` (precedent: S1b-2 added G rows). Text ASCII, no `;`.

| Field | G0592 Machine Preacher Curl | G0979 Band Pallof Press |
|---|---|---|
| category / movement_pattern / exercise_type | pull / elbow_flexion / isolation | core / core / isolation |
| primary / secondary | Biceps / Brachialis, Forearms | Core, Obliques / Front Delts |
| target_focus | Biceps (Short Head) | Core/Obliques |
| equipment_needed | machines | resistance band |
| derived equipment_tier | full_gym | home_dumbbells, basic_gym, full_gym |
| difficulty / suitable_for | intermediate / Intermediate, Advanced | beginner / Beginner, Intermediate, Advanced |
| sets, reps, rep_range, rest | 3, "10-12", "10-12", 60 | 3, "10-12 each side", "10-12", 60 |
| logging_type / is_bilateral | weight_reps / true (both arms on the handles) | weight_reps / false |
| tempo, met, cns, priority_tier | 2-1-2-0, 3.5, 1, 3 | 2-1-2-0, 3.5, 1, 3 |
| variant_family / core_levels | preacher_curl / [] | anti_rotation / [] |
| injury tags | elbow | none |
| discipline / gym_availability | strength / well_equipped_gym | strength / home |
| requires_coaching, high_impact, is_foundational | false | false |
| breathing_cue | Exhale curling up, inhale lowering | Exhale pressing out |
| coaching_cues | Set the seat so your upper arms rest flat on the pad / Hold the handles with your palms up / Curl without lifting your elbows / Lower slowly, stopping just before your arms are fully straight | Stand sideways to the anchor with the band at chest height / Brace your core / Press straight forward without turning / Pause for one second, return slowly, and repeat on both sides |
| common_mistakes | Lifting your elbows / Dropping the weight and snapping your elbows straight / Shrugging because the seat is poorly adjusted | Twisting toward the anchor / Leaning away / Shrugging or rushing |
| pro_tip / indian_alternative | "Stop just short of lockout to spare the elbow tendon." / "" | "Step further from the anchor for more tension." / "" |

Kept rows (only these keys change):

- **E027:** `equipment_needed` `["machines"]`, `equipment_tier` `["full_gym"]`, `coaching_cues`
  `["Stand on the platform with your feet planted","Hinge at the hips","Keep your back flat","Pull towards your lower chest"]`.
  `gym_availability` stays `well_equipped_gym`; injury tag `lower_back` stays.
- **E120:** `equipment_needed` `["dumbbells"]`, `equipment_tier` `["home_dumbbells","basic_gym","full_gym"]`,
  `gym_availability` `standard_gym` → `home` (the value most dumbbell rows carry; `grep gym_availability lib/` finds a
  comment only). Injury tags stay `[]` (it is in `kV14SafePool`).

## Execution order (review 1: the builders only see rows that already exist)

0. Before any edit: record the Task 6 base measurements on the untouched tree.

1. Retag records and the generalised retag stage (Task 3).
2. G0979 hand-written injury row (Task 1, first paragraph).
3. Source rows, criterion inputs, media map (Task 2).
4. Injury builder (appends G0592), then scope `--write`, re-pin, `--check`.
5. Importer with no flags (it writes by default; adds the two rows, applies retags).
6. Old-row input edit, media builder `--write`, `--check` (it maps G rows only if they are already in the library).
7. Importer again (attaches media keys), then importer `--check`.
8. Stills `--src <wardroom dir>` (there is no `--write` flag), then `--check`. Then expect 872 rows, 765 mapped rows, 764 files, 4 upload candidates.

## Task 1: injury table

`scripts/data/library_injury_additions_v15.json`: write the G0979 row by hand
(`tokens: []`, `class: judgement`, a non-PENDING reason naming decision 4, `variant_family: anti_rotation`), add
`Band Pallof Press` to `safe_pool_additions` and to `test/helpers/injury_safe_pool.dart` in the same order (E132 Pallof
Press and N01 Bird Dog, the same-family originals, are untagged; G1015 is tagged `shoulder` for its overhead path).
Then run `node scripts/build_library_injury_additions_v15.js`; it must append G0592 with exactly `["elbow"]`. If it
derives anything else (for example `wrist`), stop and ask: the approved spec says elbow.

## Task 2: new rows in the source file

Add both rows to `scripts/data/library_batch_c_source.json` (same keys as G0372 / G1015, `changes: {}`,
`confidence: "high"`, `note` free of the words the scope criterion matches), `_meta.criterion_inputs` entries, and
`{_gif,_folder}` entries in `library_batch_c_media_map.json`. `_folder` = the generation-ledger name. 0979's folder
("Band Horizontal Pallof Press") differs from the row name, so it needs `_meta.picture_checked.G0979` with what I saw in
the picture. Run `node scripts/library_batch_c_scope.js --write`, re-pin `_meta.inputs_sha256` from the value `--check`
prints, then `--check` green.

## Task 3: generalise the retag stage

`scripts/add_library_batch_c_v15.js` reads one hard-wired record (`library_e230_retag.json`). Change it to a list:
the E230 record plus `library_e027_retag.json` and `library_e120_retag.json`, same schema and same refusal rules per
record, plus a refusal when two records name one id. `before` values are generated by a script from the HEAD library,
never typed (E027 text carries non-ASCII in other keys). `equipment_tier` is in the record because the importer does not
derive it for kept rows. Update the importer's sandbox copy list in its test and the account-tier glob in
`docs/blast_radius.yaml` for the two new files. Test: both records apply, are idempotent, and a foreign value throws;
mutate by deleting one record from the list.

## Task 4: media

- `docs/audit/library-old-rows-media-input.json`: move E027 and E120 from `held` to `entries` with
  `equipment_checked: true` and `released_by` naming decisions 2 and 3. Picks match, so no repick. The equipment-check
  record is not edited.
- `node scripts/build_library_media_v16.js --old-rows ... --wardroom-dir <primary wardroom dir> --write`, then `--check`.
- Run the importer, `--check`; E027/E120 get media keys. `demo_slug` stays (the animation wins; the media kill switch
  falls back to the plate).
- Stills: `node scripts/bundle_exercise_stills.js --src <wardroom dir>`, `--check`.
- Upload: dry run only until approval (a). Then `--execute --only <4 slugs> --report <outside repo>`, `--verify --only`.
  Expected objects: 0592-preacher-curl, 0979-band-horizontal-pallof-press, 0606-t-bar-row, 0856-weighted-svend-press.
  Counts and byte totals are read from the builder output, not typed from this plan (expected +4 rows, +4 files).
- Seed `_exerciseLibraryVersion` 29 → 30.
- `test/fixtures/exercise_library_v12_row_hashes.json`: re-record E027 and E120 only; the diagnose doc names both.

## Task 5: cloud seed migration

**Expected red until the apply, by test title:** in `exercise_library_cloud_tuples_match_test` the line-for-line
equality test and "a media key added ... leaves it green" (its other mutation tests pass vacuously before the apply); in
`exercise_library_cloud_seeded_test` "seed row count matches" and the "exactly one tuple" test. These compare the library with the newest seed under
`supabase/migrations/` (183, 870 rows). `Supabase Integration Tests` does not read the library, so a red there stops
the batch. Precedent: applying 183 turned
the tuples-match test green (commit `ffe716c1`). So before the apply, "CI green" for the review gate means: those named
tests are the only failures (read every unit and sweep shard log), listed in the plan-review record. This departs from
CLAUDE.md §4.12.8, since `land_pr --ci-only` will not print `ci-green` in that state. Any other red stops the batch. After the apply commit the
whole PR must be green. `supabase/migrations/CLAUDE.md:72` asks a destructive migration to merge the code half first;
these tests force apply-before-merge, as every library seed has done; say so when asking for approval (b). The apply adds two rows and changes two before the
new app code ships. Check at pre-apply that the shipped app does not read cloud `exercise_library` in a way those rows
could break.

Cloud columns that change: E027 `equipment_needed` + `coaching_cues`; E120 `equipment_needed`; two INSERTs.
`equipment_tier` and `gym_availability` are not cloud columns.

`scripts/seed_exercise_library.js` rebuilds the previous tuple with **one** record column reverted, so two columns on
E027 are refused. Change: collect all kept-row records, group by id, and compare the previous tuple with **all** of that
id's `before` columns reverted at once; keep one rollback UPDATE per (id, column); count distinct ids in the header
sentence **and in the Destructive line** (`changed.length` is per (id, column): 3 entries, 2 ids). Refuse two records
naming the same (id, column). Set `newRowNote` (it is `'none'` today, which would print beside two new ids). The existing
one-column cases must behave as before.
Records: `library_v30_equipment.json` (column `equipment_needed`, E027 + E120) and `library_v30_t_bar_cues.json`
(column `coaching_cues`, E027). BATCH: label `library v30`, this batch's diagnose id, `batchTag: 'v30'`,
`newRowIds: ['G0592','G0979']`, `previousMigration: '183'` (the newest `*exercise_library.sql`). The generated header
and rollback must name three column UPDATEs and the deactivation of both inserts. The label keeps a suffix the
contract's `_batchLabel` pattern can match (`library v30, OI-443`; extend the pattern, do not loosen it). Tests:
- `exercise_library_cloud_seeded_test.dart`: a v30 rollback checker; the cases that read freshly generated output in the
  OI-523 shape (about :752-761, :826-836, :958-991) are repointed to the applied file 183, as earlier batches did; the
  block at about :994-1037 keeps the v28 BATCH as a sandbox literal. A v30 version of the header/rollback test still
  runs on freshly generated `plain` and `split` output: diagnose link, three UPDATEs, both inserts deactivated,
  "(2 carry new values)" with 2 inserts, and an unknown-label mutation. `_withGeneratorSandbox` copies a fixed list: add
  both v30 records and file 183.
- `exercise_library_cloud_tuples_match_test.dart`: its sandbox copies only migration 176; it must copy 183, and its
  record list gains the two new records.
- `docs/blast_radius.yaml`: account globs for **all four** new data files (two retag records, two cloud records).
A mutation reverting only one E027 column must be refused by the generator.

Ordering (supabase/migrations/CLAUDE.md "Review a migration as a DRAFT"): generate with `--out` into `test/sql/` as the
draft, named `test/sql/999_reseed_exercise_library.sql` (the generator only accepts `<digits>_..seed_exercise_library.sql`);
the B-pass sees the draft. The header lists E027 once per column, so word the count as rows, not entries. Keep the two
literals existing mutations replace (`const restoreValue = ...` and `JSON.stringify(row[rec.column] ?? null)`); a wrong
`before` refusal still names the id and `previous seed migration (NNN)`. Rehearsal: in the local docker database first if it is available here,
including the rollback block. `supabase/migrations/CLAUDE.md:64` asks for a dry run on a Supabase branch for
`Destructive?: yes`. Precedent is mixed: 162, 164 and 173 were rehearsed on live in `BEGIN ... ROLLBACK` (162 on an
explicit founder instruction); 174, 175, 176 and 183 in local docker. When asking for approval (b) I state which method
ran, that it is not a Supabase-branch dry run, and let the founder decide. Pre-apply: compare live rows per id (md5 over
the cloud columns) with what 183 wrote; any drift stops. After the go: `sh scripts/mint_migration.sh <slug>`, copy the
draft to that name, apply, read back the four rows, commit file + `backups/applied_migrations.json` together, delete the
draft. No column changes, so no schema snapshot change.
Rollback in the cloud: the inline UPDATEs; inserted rows are deactivated, never deleted.

## Task 6: plan-generator effect (measured before the review of the diff)

The four rows change what the generator can pick: E027 leaves basic_gym, E120 enters home_dumbbells, G0592 enters
full_gym, G0979 enters home/basic/full. (Review 1 measured by hand: the basic_gym horizontal-pull core pool drops 9 → 8
intermediate and 5 → 4 advanced.) Many tests outside `test/plan_generator/` read the real library and some run the real
generator (`test/contracts/` set-allocator, keep-all-slots, universal-pool, arm-swap, injury-recheck;
`test/plan_engine_v4/`). So measure, before (base) and after: `test/plan_generator/`, `test/plan_engine_v4/`,
`test/contracts/`, the generator golden and the three kill-switch goldens. The stop-and-ask rule below covers all of them. The same rule applies to inline
digests, measured counts, baselines and reach personas (`goal_training_gate`, `weekly_minimum_gate`, arm-swap and
set-allocator counts, injury-recheck reach personas, `day_floor_off_hashes.json`): a value changes only when the four
rows explain it. Report which goldens move
and why; re-record a golden only when the diff is explained by these four rows. **Stop and ask the founder** if a day
falls below its exercise floor, an injury sweep fails, or a core-list slot loses its only candidate. Do not weaken a
floor or a sweep to pass. No `lib/shared/repositories/plan_engine/**` edit.

## Task 7: tests, pins, docs

- `library_media_table_test.dart:108-112` pins 621 new rows on 620 files, in assertions and title: 623 on 622.
- Typed media totals in `docs/naming_conventions.md` (about :260), `docs/reference/exercise-library.md` (about :17) and
  `docs/operations/EXERCISE_MEDIA.md` are updated from builder output.
- Test mechanics: in `library_seed_v29`, strip the new data **only inside the digest `jsonEncode` argument** (the same
  function also seeds the box); its MIRROR `markedVersion` and expected version move to 30. The v30 digest helper strips
  the media keys from E027/E120 as well as restoring their old values. A "drop one retag record" test first resets the
  library to `before`, otherwise dropping it changes nothing.
- `injury_recheck_v14_contract_test.dart`: the elbow count goes up by one (G0592) and `kV14SafePool.length` 56 → 57,
  with the title and header comment.
- `plate_flags.dart` comment and `EXERCISE_MEDIA.md` carry new/old/overlap counts; derive them again. The checklist file
  is `docs/operations/GO_LIVE_CHECKLIST.md` (5.5, 5.8). Byte totals come from the table or the upload dry run. Add the
  four new data files to `blast_radius_library_data_account_test.dart`.
- Row-count pins 870 → 872; artless 721 → 723; new-row count 642 → 644; verify each by grepping the literal across
  `test/` first, plate-art count 149 unchanged. `library_media_table_test` uses held E027 in its P3/P7 negative cases:
  repoint to E095 (still held) without loosening the expected rule.
- Seed literals in the v16 and v18-v29 tests → 30; new `exercise_library_v30_*` contract test: the two new rows
  field-for-field, the two retagged rows' changed keys, media on all four, tiers derived, seed 30.
- Older tests that rebuild an earlier library digest must drop G0592/G0979 and restore E027/E120 **in the digest
  expression only**, never in the shared rebuilt list.
- Docs: `docs/operations/EXERCISE_MEDIA.md`, `docs/reference/exercise-library.md`, `docs/naming_conventions.md`, `docs/sot_registry.yaml`, OI-443 (held pairs drop by two, note on 0592/0979),
  context budget, `docs/audit/media-two-new-two-retag.closure.yaml`, a diagnose-style batch doc linked by the migration
  header.
- OI-437 note: held picks G1615 and G1349 are near-neighbours of the new curl and of T-Bar Row. Not in this batch.
- Mutations (each confirmed applied, then reverted from a commit): drop one retag record; revert one E027 column in the
  generator check; remove `Band Pallof Press` from the safe pool; give G0592 no media; leave seed at 29.
- Gates: `flutter analyze --no-fatal-infos`, the pre-commit gate loop, then the full suite from CI on the open PR.
  The PR must run the plan-generator sweeps (the library is an input; check the `sweeps:` line).

## Risks

- The apply changes the live coach at once: a partial `getFormCues` search for "pallof" will return Band Pallof Press
  ahead of Band Vertical Pallof Press, and E027's machine cues reach installed apps that still say barbell.
- A workout generated for a basic gym no longer offers T-Bar Row (intended: the station is a machine).
- Rollback of the app change is whole-batch (the media table test refuses an orphaned `unmapped` file) AND forward-only
  on the seed: a box at 30 is reseeded only by a HIGHER version, so a revert ships as seed 31 and retires G0592 and G0979.
- Uploaded objects are additive; unused objects are harmless and are not deleted by a rollback.

## Addendum (2026-11-28, after the first CI run)

Founder: add G0574 Landmine T-Bar Row to the rotation. Source row: `core_levels: [intermediate, advanced]`,
`same_movement_as: E027`. Reason: the basic_gym advanced repeat phase repeated Cable Low Seated Row on two days once E027
became machine-only. Pins that restate the rule move with it (core-level Table A, the linked-row set, the same-day gate's
pair count, the v29 rebuild helper). Cloud draft unchanged. Plan snapshots are re-recorded after this change.
