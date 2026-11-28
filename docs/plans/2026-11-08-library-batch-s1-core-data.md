# Library Batch S1a (generator step 1 data: core-list levels for R1, R7, Hip / Glutes and level agreement; gate zeros R9 (i) and (iv); seed v21, no cloud change) Implementation Plan (v4, converged)

> **For agentic workers:** inline (§4.12.7). Steps use checkbox syntax. Reviewers and the B-pass are fresh Sonnet subagents.

**Status.** v4 (converged after review #3), 2026-11-08, branch `generator-step1-r1-data` (worktree of the same name, based on origin/main
`c2841edb`, which holds PR #234 = generator step 1A). Review #1 (two context-blind seats, lens A data and generator
effect, lens B pipeline / cloud / seed / tests) returned 15 P1 between them on draft 1; draft 2 answered them. Review #2 (two fresh seats on draft 2) found no design issue and 3 P1 (gate scope, tier, a CI-unrunnable test input); draft 3 answers them (log at the end). Review #3 (a fresh seat on draft 3, convergence check) found no P0 or P1; v4 folds its two P2 and four P3 (log at the end).

**Split (review #1).** Draft 1 bundled two units with different machinery. They are now two batches:
- **S1a, this plan:** only `core_levels` edits. `core_levels` is NOT a cloud column (`backups/live_schema_columns.json`
  has no such column for `exercise_library`; `scripts/seed_exercise_library.js:300-307` lists it among the JSON-only
  fields that live in the bundled Hive box), so the seed generator's SQL does not change, the newest seed migration
  (173) still matches, and there is NO live step. Phones get the change through seed v21.
- **S1b, its own plan after S1a merges:** the 9 dumbbell and kettlebell twins (N rows with `criterion_inputs`, injury
  table rows through `build_library_injury_additions_v15.js`, `slot_pattern` / type choices, initials only because the
  plates' SVG frames are not in the repo), the "a twin and its sibling never share a day" rule (it does NOT exist
  today: `core_list_selector.dart:274-295` uses `variant_family` only for the family FILL, and the OFF path has no family
  logic, so the founder's 2026-11-08 condition needs CODE in both worlds), E053's retirement (the removals generator
  only knows the 66-id sheet and `c2a`/`c2b`; E053 carries media `0284-donkey-calf-raise` in the media table, the
  old-rows input and the stills bundle), and the cloud migration for those rows (one live go). The closure ledger
  entries 1B-8 and 1B-9 move to S1b with that reopen trigger.

**Goal.** The core-list pool (`enable_core_list_pool`, still OFF) gets the founder-approved levels, the two gate zeros
that need data (R9 (i) no jump pick unless the pool was jump-only; (iv) Quads and Hamstrings hip_dominant compound
slots filled for bodyweight intermediate / advanced and home_dumbbells advanced) land with it, and every
`core_levels` value lies inside the row's `suitable_for` except two named exceptions.

**Founder decisions (2026-11-08, board d8 to d11).** R1 table including G1490 and E291; E046 Nordic Curl advanced;
R7 household rows at intermediate and advanced for Biceps and the Lateral / Rear / Front Delt slots, Lower Chest left
as is; advanced Hip and Glutes isolation: E107 (gym), G3667 and E257 (bodyweight and home). The level-agreement
items (step-1 plan 1B-10) were in the approved step-1 scope; their exact values are mine (Decision 2), with two
items put to the founder before the build go (Decision 3).

**Mode and tier.** Inline, one worktree, one writer. Blast radius **platform**: `docs/blast_radius.yaml` itself is
`platform` (`docs/blast_radius.yaml:398`) and Task 1 edits it; the library JSON (`:525`) and `seed_service.dart`
(`:623`) are `account` (Task 4 confirms with `blast_radius_from_diff.dart`). Full ×2 plan review, B-pass
(`docs/reviews/generator-step1-r1-data-bpass.md` with its dated `## Tuning entry`), record
`docs/plan-reviews/generator-step1-r1-data.md` (`blast_radius: platform`, `review_rounds`, `ground_truth_verified: true`,
`verdict: converged`, `bpass: accepted`, `bpass_review:`). Commit prefix `feat(library):` (the 0577f760 precedent; no
`closes-diagnose:` required, the diagnose doc is still written and cited). No live step.

**Effect.** OFF: none. `core_levels` is read in `lib/` only by the core-list code (`core_list_selector.dart`) and the
top-up's pass 1 (`exercise_selector.dart`, R4, `coreListOnly` false on the OFF path); the 998-persona golden and
`scorecard_gate_test.dart` must be byte-identical (Task 3 proves it). ON: measured in Task 3.

## Global constraints

- Only `core_levels` changes, on the Table A ids; every other key of every row byte-identical; no row added or
  removed. The frozen reference fixture does not cover `core_levels` (35 frozen keys; checked by lens B), so it does
  not move.
- **Where each id's value lives (lens B 5):** the importer (`scripts/add_library_batch_c_v15.js`) rebuilds every
  SOURCE id (G and N rows) from `scripts/data/library_batch_c_source.json` on every run, and
  `library_batch_c_rows_contract_test.dart:243-250` compares shipped core counts of the source rows with
  `_meta.derived.core`. So G / N values are edited IN THE SOURCE, `_meta.derived.core` is re-derived by
  `node scripts/library_batch_c_scope.js --write` and `--check` is green (C6). `criterion_inputs` are frozen inputs and
  are NOT edited (they hold the first-written `core_levels`; `inputs_sha256` hashes them), so the C1 to C5 triage sets
  do not move: Task 1 confirms with `--check` before and after. E rows (kept rows) take their value through a record
  plus importer stage, `scripts/data/library_s1_core_levels.json` (`before` / `after` per E id, generated with node
  from `git show HEAD:assets/data/exercise_library.json`; the stage applies `after` to a row at `before`, is a no-op at
  `after`, stops on anything else; the C2c `retagRow` pattern), so a later hand edit cannot silently drift.
- No `;`, no text edits; `dart run scripts/check_equipment_audit.dart` stays green untouched.

## What is already true (read 2026-11-08 by me and the two round-1 seats)

| Fact | Source |
|---|---|
| Library 862 active rows; 653 with `core_levels: []` | library |
| R1 rows today: E038, G0413, G0336, G0381, E044, E042 [beg, int]; E143, G1476, G0411 []; N11, E253 [beg]; E292 [beg]; N08 []; E046 [] (suit [Advanced]); G1373 [beg]; G1387, G1490 []; E291 [beg, int] | library, source |
| R7 rows: Biceps E268, E269, E282; Lateral Delts E273, E289; all household, [beg]. Rear Delts slot (`shoulder_isolation`): E276 Standing Towel Pull Apart (`slot_pattern [shoulder_isolation]`, `slot_focus [Rear Delts, Mid Back]`, towel, prehab), E274 Prone T Raise and E277 Prone W Raise (same slot overlay, bodyweight, strength), all [beg]. `rankedPool` reads `slot_pattern ?? movement_pattern` and excludes only `calisthenics_skill` / `olympic` | library, lens A mirror |
| Front Delts `shoulder_isolation` at bodyweight: no household or bodyweight row exists (front raises need dumbbells, band, cable or barbell), so that drop stays and is reported | lens A |
| Hip / Glutes isolation: E107 Hip Abduction Machine `machines` []; G3667 Side Lying Hip Adduction [beg, int]; E257 Glute Kickback [beg, int]; `machines` is full_gym only | library, `equipment_vocab.dart:291-310` |
| Level disagreements (`core_levels` not inside `suitable_for`): E010 Pike Push Up [int, adv] / [Beg, Int]; E020 Diamond Push Up [int, adv] / [Beg, Int]; E045 Romanian Deadlift [beg, int, adv] / [Int, Adv]; E134 Copenhagen Plank [int, adv] / [Adv]; E255 Towel Row [beg] / [Int, Adv] | full-library scan |
| Drops ON (`core_list_pool_report.md` at `c2841edb`): bodyweight advanced Lateral Delts 288, Biceps 280, Hamstrings hip_dominant 280, Glutes hip_isolation 224, Hip 208, Lower Chest 152, Rear Delts 96, Front Delts 80; intermediate Biceps 219, Lateral 204, Hamstrings 187, Lower Chest 102, Rear 88, Front 62; Lats / Mid Back horizontal_pull 8 each; basic / full / home advanced Hip 208 | report |
| Trace fields for R9 (i): `jumpRemoved`, `jumpOnlyPool` exist (`core_list_selector.dart:29-31`, `:195`, `:315-319`; read at `exercise_selector.dart:867-868`) | lens B |
| Seed: `_exerciseLibraryVersion = 20` (`seed_service.dart:150`); pins `== 20` in `library_seed_v16_upgrade_behavioral_test.dart:31` (`_currentVersion`, comment `:29`), `library_seed_v18_..._test.dart:79`, `library_seed_v19_..._test.dart:83`, `library_seed_v20_..._test.dart:85, :97, :110` | lens B |
| Core totals typed as literals in `exercise_library_core_fields_contract_test.dart:140-147` (129 / 138 / 98) | lens B |
| Lens A mirror (rankedPool pass / target / level filter, no injuries): after Table A no jump-only pool remains (six before: Calves bodyweight int / adv, Quads compound and isolation bodyweight and home_dumbbells adv); Quads compound and Hamstrings hip_dominant compound non-empty everywhere | `scratchpad/sim.py` (lens A) |

## Decisions

1. **Table A, founder-approved fills** (R1, R7, Hip / Glutes):
   - R1 as the step-1 plan's table: E038, G0413, G0336, G0381, E044, E042 add adv; E143, G1476, G0411 = [adv]; N11, E253 add int, adv; E292 add int, adv; N08 = [int, adv]; E046 = [adv]; G1373 add int, adv; G1387, G1490 = [int, adv]; E291 add adv.
   - R7: E268, E269, E282 (Biceps), E273, E289 (Lateral Delts), E276, E274, E277 (Rear Delts) add int, adv. E274 and E277 are bodyweight prone raises (not household); three rows keep variant B and phase 2 from repeating one (lens A 2). Front Delts: nothing to add (reported).
   - Hip / Glutes: E107 = [adv], G3667 add adv, E257 add adv.
   - **G0339 Dumbbell Lying Hamstring Curl = [int, adv]** (mine, review #2 lens A P2-2): E292 and N08 at intermediate and advanced put a towel or no-equipment curl into the basic_gym Hamstrings `knee_dominant` isolation slot as a CORE pool, ahead of the fill row G0339 that basic gym users get today. With G0339 core at its own `suitable_for` levels, the step-1A like-for-like reduction (R3 (a)) keeps the dumbbell curl for any implement user, and bodyweight users are unchanged (G0339 needs dumbbells and a bench). Without it this batch would reintroduce a household pick for an equipped user, the class the founder asked to remove. Measured by review #3: basic_gym int / adv curl slot fill [G0339] becomes core [G0339]; full_gym int / adv grows from [E049, G0599] to [E049, G0599, G0339] (G0339 last, priority 3, so variant B or phase 2 can reach it); bodyweight and home_dumbbells unchanged by G0339 (it needs a bench) except a home_dumbbells user who owns a bench, whose pool becomes the one-row like-for-like [G0339]. Reported to the founder with the rest.
   - **G0355 Dumbbell Single Arm Lateral Raise = [int, adv]** (mine, found by the Task 3 audit, 2026-11-08): with E273 / E289 core at intermediate and advanced, a day with TWO Lateral Delts slots (the 5-day split) took E013 Lateral Raise in the first and Towel Lateral Raise in the second, because `pickedNames` removes E013 from the second slot's pool BEFORE the improvised filter, leaving only household rows (review #2 assumed household rows reach an equipped user only when every implement row is contraindicated or excluded; same-day dedup is the third door). A second dumbbell lateral raise on the list keeps a loaded row in that pool, so the filter removes the towel move. Measured before the fix: Towel Lateral Raise as a household pick for an equipped user in 88 audit plans (32 before S1a).
   - N08, E292, E046 serve the Hamstrings `knee_dominant` (curl) slot; the R9 (iv) Hamstrings `hip_dominant` cells depend on E253 and N11 only. (Lens A: on the Legs day the Glutes hip_isolation slot comes before Hip, so E257 lands in Glutes and G3667 in Hip; at basic_gym advanced like-for-like gives Glutes E109 and Hip E257.)
2. **Level agreement** (`core_levels ⊆ suitable_for`, enforced by a whole-library contract test with a named-exception map):
   - E020 Diamond Push Up = [int] (matches no slot in the mirror, so no pick moves); E134 Copenhagen Plank = [adv].
   - **Named exceptions, kept as they are:** E010 Pike Push Up [int, adv] (narrowing empties the bodyweight advanced Front Delts `vertical_push` compound slot, where E010 is the only row, lens A 1) and E045 Romanian Deadlift [beg, int, adv] (narrowing turns every gym and dumbbell beginner's hinge into Bodyweight Good Morning or a glute bridge, because phase 1's foundational key precedes the fit key, lens A 6). Each exception names its reason in the test; the honest fix for both is a `suitable_for` decision, which moves OFF picks and is not this batch's call. Ledgered `blocked_on_user` (Decision 3).
   - E255 Towel Row: see Decision 3.
3. **Put to the founder before the build go (one message, with the measured numbers from Task 3):** (c) the named R1 side effect (review #2 lens A P2-1): with E038 Goblet Squat at advanced, advanced basic and full gym Quads compound pools become [Back Squat, Front Squat, Goblet Squat] (it replaces Bulgarian Split Squat at basic gym and Leg Press at full gym on the id tie), and home_dumbbells advanced gets nine loaded squat and lunge rows instead of two jump rows; (d) G0339 above; (e) gym users can get E257 Glute Kickback or G3667 Side Lying Hip Adduction (bodyweight rows) in the advanced Hip slot, since the like-for-like step cannot fire there (first-listed muscles "Abductors" / "Adductors"); a home_dumbbells advanced band user gets E257 instead of band G0980 in the Glutes isolation slot, as home_dumbbells intermediate does today; (f) Sliding Leg Curl as the home_dumbbells intermediate and advanced hamstring curl (274 audit plans, see Results). (a) E255 Towel Row: `[]` (narrow, loses a beginner bodyweight back row, leaving E264 and N12) or `[int, adv]` (fills the bodyweight Lats / Mid Back horizontal_pull drops at intermediate and advanced, 8 each, with a household row, the R7 (b) logic); default `[]` until answered. (b) Whether E010 and E045 should become suitable for the levels their core lists already name (an OFF change, so it would be its own small batch with the golden re-recorded) or stay as named exceptions.
4. **Gate zeros R9 (i) and (iv)** (scope, review #2 lens A P1-1: (iv) covers every gate persona with `persona.injury == null` (`core_list_pool_gate_test.dart:109`), any kind; the injured personas (`test/helpers/generator_golden_personas.dart:125-134`, effective level intermediate) are exempt because knee and lower_back contraindications empty those cells before and after this batch) land in `test/plan_generator/core_list_pool_gate_test.dart` as specified in the step-1 plan (section 3, R9), each mutation-proven (mutation: drop one R1 row's advanced level so a jump-only pool returns; let a jump row through the partition), `grep -c` confirms each mutation applied, the reds recorded.
5. **Seed v21:** `_exerciseLibraryVersion` 20 to 21, a v21 comment block (Table A rows rewrite through `putAll` by id, as the v20 block says), the version pins repointed (never loosened), the v20 test's "a box already at v20 is not rewritten" mirror (`library_seed_v20_upgrade_behavioral_test.dart:107`) moved to 21 and renamed (at v21 a v20 box upgrades, so that mirror would go red), a new `library_seed_v21_upgrade_behavioral_test.dart`: a v20 box upgrades to the Table A values with every other key unchanged; a fresh install equals the asset; the old copy on the new tree (an install at v20) is what the upgrade fixes.

## Tasks

### Task 0: Baselines before any edit (scratch)
- [ ] `WRITE_CORE_LIST_REPORT=1 TZ=Asia/Kolkata flutter test --ignore-timeouts test/plan_generator/core_list_pool_gate_test.dart` on the clean tree; keep `report_before.md` (the tracked report is current at `c2841edb`; re-run to be sure).
- [ ] The 2,304-plan audit ON (`PLAN_AUDIT_OUT`); OFF is unchanged by construction and proven by the golden in Task 3.
- [ ] `node scripts/library_batch_c_scope.js --check` green on the clean tree.

### Task 1: The data (RED tests first)
**Stage position (review #2 lens B P2-1):** the new stage runs as its own pass over the kept rows AFTER the existing retag and E274 `target_focus` steps (`add_library_batch_c_v15.js:304-310`) and BEFORE the media stage, which stays last; E274 is in Table A, so a stage case asserts E274 keeps `target_focus` Mid Back.
**Files:** `scripts/data/library_batch_c_source.json` (G / N `core_levels` and `_meta.derived` via `--write`), `scripts/data/library_s1_core_levels.json` (new, E ids), `scripts/add_library_batch_c_v15.js` (the stage; header rule list updated), `assets/data/exercise_library.json`, `test/contracts/exercise_library_core_fields_contract_test.dart` (typed totals `:140-147` edited to the new counts, computed by node and pasted, with a comment naming this batch), new `test/contracts/library_s1_core_levels_test.dart`, `test/scripts/library_media_importer_test.dart` (stage cases), `docs/blast_radius.yaml` (`account` glob for the new record, as for `library_e230_retag.json`) and its pin in `blast_radius_library_data_account_test.dart`.
- [ ] Commit a fixture `test/fixtures/library_core_levels_before_s1a.json` (id to `core_levels` for all 862 rows, generated by node from the c2841edb library; CI's unit-test job checks out shallow, `.github/workflows/test.yml:135`, so no test reads git history).
- [ ] RED tests (`library_s1_core_levels_test.dart`): every Table A id ships its `after`; the record's `before` equals the fixture for each E id; the whole-library rule `core_levels ⊆ suitable_for` holds except the named exceptions, and each exception still disagrees (so a later fix forces the map to shrink); no row PRESENT IN THE FIXTURE and outside Table A changed `core_levels` (keyed on the fixture's ids, so S1b's new rows do not trip it; a later deliberate `core_levels` edit extends Table A or re-records the fixture in its own commit).
- [ ] Importer stage cases: a library at `before` gets `after`, everything else byte-identical, a second run byte-identical, `--check` 0; a foreign value exits non-zero; an absent record is a printed no-op (tests copy the script into temp trees).
- [ ] Edit the source, `library_batch_c_scope.js --write` then `--check`; generate the record; run the importer; `--check` byte-equal. Expected library diff: `core_levels` lines of the Table A rows only.
- [ ] Contracts: `library_batch_c_rows_contract_test.dart`, `library_batch_c_source_test.dart`, `exercise_library_core_fields_contract_test.dart`, `core_list_like_for_like_data_test.dart` (three cells move, review #3: `full_gym|intermediate|Hamstrings|knee_dominant|` and `full_gym|advanced|...` gain G0339; `home_dumbbells|advanced|Glutes|hip_isolation|` disappears because E257 makes that core pool all improvised; re-recorded with this reason in a comment), schema / text-shape / equipment-tier contracts. Fix, never loosen.
- [ ] Mutations: one E `after` back to `before`; one G `after` back in the source without `--write` (C6 red); a core level outside `suitable_for` on a non-exception row; an exception narrowed (the "still disagrees" pin red); the blast-radius glob removed. `grep -c` each; record reds.

### Task 2: Gate zeros R9 (i) and (iv) (Decision 4)
- [ ] Write (i) over every trace slot (both variants, phases 1-5): a picked row with `high_impact` or `discipline: plyometric` fails unless `jumpOnlyPool`; (iv) for every bodyweight intermediate / advanced and home_dumbbells advanced persona, every Quads compound and Hamstrings hip_dominant compound trace slot has source `core` or `fill`. Run red on the c2841edb library (data absent), green after Task 1; then the two mutations of Decision 4. Note (review #3): the bodyweight advanced Quads pool (E042, E143, G1476) exactly fills the one day block with three Quads `knee_dominant` slots, and the two-row Hamstrings `hip_dominant` pool (E253, N11) exactly fills the day with two; (iv) has no slack, so a later edit dropping one of those rows turns it red by design.

### Task 3: Measure
- [ ] OFF identity: `TZ=Asia/Kolkata flutter test test/plan_generator/generator_golden_test.dart` (no record flag) and `scorecard_gate_test.dart` green unchanged.
- [ ] Gate report after (998 personas + 576-run sweep) against `report_before.md`; the audit ON after against before.
- [ ] Results section: every changed ON pick by rule; every remaining drop with its reason (Front Delts named); the jump rows and the hamstring zero weeks before and after; B-repeats-A cells; R6 numbers (emergencyAnyLevel, refilled, retired ids) for the 1B plan; the E255 and E010 / E045 numbers for Decision 3.

### Task 4: Seed v21, gate loop, B-pass
- [ ] Decision 5 (files: `lib/core/services/seed_service.dart`, the four pinned tests, the new v21 test, `docs/sot_registry.yaml` seed-constant cites recomputed from anchors).
- [ ] Classify the staged paths with `dart run scripts/blast_radius_from_diff.dart <paths>`.
- [ ] Gate loop (§4.12.8): `flutter analyze --no-fatal-infos` (whole project), `sh scripts/pre-commit.sh`, full `TZ=Asia/Kolkata flutter test --exclude-tags golden` in the background, the golden test separately.
- [ ] B-pass on the staged tree; lenses 1, 3, 6, 7, 8 plus: the importer stage's mirror (a G row at `before` in the source vs the library), the exception map's mirror, the v20 install on the new tree.

### Task 5: Close-out
- [ ] Commit the regenerated `test/plan_generator/core_list_pool_report.md`; `docs/naming_conventions.md` gains the two new file names; `docs/reference/exercise-library.md` core counts; `_suitableDisagreeIds` in `core_list_pool_gate_test.dart:41` shrinks to E010 and E045.
- [ ] Diagnose doc `docs/diagnoses/2026-11-08-library-batch-s1a-<id>.md` (bug-history lookup cited: c1d7a4 core rows missing, b2c7e4, d8ac69; `touched_layers_checked` 12 tiers; no cloud tier touched, stated with the column evidence). Closure ledger `docs/audit/library-batch-s1a.closure.yaml`; in `generator-step1a.closure.yaml`: S1A-R1-DATA, S1A-NORDIC, S1A-R7-GAPS, S1A-R9-I-IV to `closed_in_commit`, 1B-10 retitled with E020 and split (`closed_in_commit` for E020 / E134 / E255, a new `blocked_on_user` row for E010 / E045, `total_findings` and `closed_count` recomputed), 1B-11 retitled "Cloud re-seed migration (S1b, seed v22)" since S1a uses v21, 1B-8 and 1B-9 reopen trigger "S1b plan"; every `closed_in_commit` row stamped with the fix SHA in the close-out commit. Plan-review record, `land_pr.sh`, worktree retired, memory retrospective.
- [ ] Founder device list (needs the flag ON on a debug build, since the pool is OFF): an advanced bodyweight plan has biceps, lateral and rear delt work, a hamstring hinge every week and no jump squat as the main leg lift.

## Results (Task 3, measured 2026-11-08 on the final Table A, 34 rows)

**OFF identity.** `generator_golden_test.dart` and `scorecard_gate_test.dart` green unchanged on the 33-row data; the
2,304-plan OFF dump is byte-identical to step 1A's (`cmp`) on the final 34-row data (G0355 is a `core_levels` edit,
which the OFF path does not read).

**2,304-plan audit, pool ON** (step 1A at 93550461 -> S1a):

| measure | 1A | S1a |
|---|---|---|
| verdict not suitable / needs work / suitable | 358 / 1,581 / 365 | 505 / 1,387 / 412 |
| jump rows in week 1 (as the lead) | 1,273 (573) | 0 (0) |
| week-1 days opening with a non-compound (plans / days) | 310 / 445 | 12 / 12 |
| plans with a major muscle at 0 sets in week 1, 2 or 3 | 330 | 284 |
| plans with a household substitute for an equipped user | 44 (Sliding Leg Curl 44, Towel Lateral Raise 32) | 274 (Sliding Leg Curl 274, Towel Lateral Raise 32) |
| plans with an unloaded pick | 468 | 548 |
| plans with a lead lift 2+ sets under an isolation | 1,005 | 1,108 |

Reading the moves:
- The "not suitable" count rises because plans that used to drop a slot now fill it, and the fills carry their own
  codes (low_volume, unloaded); "suitable" rises 365 -> 412.
- **Sliding Leg Curl (E292, towel) 44 -> 274 plans:** the Hamstrings curl slot of home_dumbbells users at intermediate and
  advanced. No dumbbell hamstring curl works without a bench (G0339 needs one; home_dumbbells has no bench), so the core
  pool is E292, N08 and, at advanced, E046; before S1a the slot took the bodyweight fill row E230. A slider curl is the
  standard bench-free hamstring curl; the audit flags it by its towel token. Put to the founder (Decision 3 (f)).
- **Towel Lateral Raise** went 32 -> 88 before G0355 and back to 32 with it (Decision 1).
- **Unloaded:** jump picks (Jump Squat 192, Lunge with Jump 166 plans) are gone; Walking Lunge 216 -> 366 and Single Leg
  Glute Bridge 103 -> 143 take those leg slots (both foundational bodyweight rows, which the phase-1 foundational key
  ranks ahead of the non-foundational dumbbell rows; that order is the 1A plan's, `plan_engine/CLAUDE.md`); Glute
  Kickback 0 -> 114 in the advanced gym Hip slot (Decision 3 (e)); Bodyweight Good Morning 12 -> 58.
- **Lead starved** 1,005 -> 1,108: new hinge leads (Bodyweight Good Morning 2 sets vs a calf raise 5) are the step-2
  allocator class (OI-486), not a data effect.

**Gate report (998 personas + 576-run sweep, `core_list_pool_report.md`):** hard counts 0 including R9 (i) and (iv);
`emergencyAnyLevel` personas 2 -> 0; multi-injury sweep emergencyAnyLevel 40 -> 16 runs, refilled 16 (unchanged, 1B-6);
high-impact picks Jump Squat 682 / Lunge with Jump 288 -> none; drops: every Biceps, Lateral Delts, Hamstrings hinge,
Glutes and Hip drop at bodyweight and every advanced Hip drop at the gym tiers is gone; left: Lower Chest (founder: left
as is) 152 / 102 / 152 / 103, Front Delts 80 / 62 (no row exists), Lats `vertical_pull` 24 / 27, Rear Delts 12 at
bodyweight intermediate, Triceps 8 / 10, and the intermediate gym lines the report already carried (Lateral Delts 8,
Quads 6, Shoulders 6, Upper Chest 4, Front Delts 4, Hamstrings 4), none touched by this batch.

**Mutations.** Gate: G1 (the pre-S1a library) red with 52 jump-only pools (Quads 38, Calves 14) and 34 unfilled
Hamstrings hinges; G2 (the R2 jump partition off) red with 42 jump picks. Contracts: an E `after` back to `before` (the
S1a test and importer `--check` red); a G source value back without `--write` (scope `--check` red, C6); a core level
outside `suitable_for` (2 red); an exception narrowed (2 red); the blast-radius glob removed (2 red). Each applied
(`grep -c` or a printed count), and every file was restored byte-identical (`cmp`).

## Review log
- **Round 1 (draft 1, 2026-11-08), two seats.** Lens B: `core_levels` is not a cloud column (the migration and rollback design was wrong); the seed generator and seeded test have no shape for added rows outside the twin flag or for an `s1` removal; E053 is not in the generated removals file and carries media; G / N values must change in the source with `_meta.derived` re-derived; new N rows need `criterion_inputs`, injury-table builder rows and scope entries; a fifth disagreement E020; pinned counts (862, 149 / 713, 633, 129 / 138 / 98, "Donkey Calf Raise" present); plates' frames absent; baseline re-freeze for E053. Lens A: narrowing E010 empties the bodyweight advanced Front Delts compound slot; E276 fills Rear Delts through its `slot_pattern` overlay (and E274, E277 likewise); the family "same movement" rule does not exist; twins need `slot_pattern`, `exercise_type`, `is_foundational` and `equipment_tier` chosen deliberately; narrowing E045 changes beginner hinge quality; E255 could fill Lats / Mid Back. Resolution: split into S1a (this plan, `core_levels` only, no cloud) and S1b (twins, family rule, E053, migration), and Decisions 1 to 3 rewritten.
- **Round 2 (draft 2, 2026-11-08), two fresh seats.** Lens A (own rankedPool mirror): no empty cell, no jump-only pool, R9 (iv) cells non-empty, fills confirmed, OFF identity holds (readers of `core_levels` traced). P1: (iv) as worded fails on the injured golden personas. P2: Goblet Squat enters advanced gym Quads pools; basic_gym Hamstrings curl becomes a towel curl; E255's effect needs numbers. Lens B: no-cloud claim holds (no hash or column), source edit plus `--write` sufficient (`inputs_sha256` untouched). P1: the tier is platform (`docs/blast_radius.yaml:398`); `git show c2841edb` tests fail on CI's shallow checkout. P2: stage position vs E274, the v20 mirror test, ledger rows 1B-10 / 1B-11, missing deliverables (B-pass file, report, naming). Resolution: draft 3 (G0339 added to Table A; (iv) scoped; fixture instead of git; tier platform; the rest listed in Tasks).
- **Round 3 (draft 3, 2026-11-08), one fresh seat, convergence.** No P0 / P1. P2: the like-for-like test moves in three cells; G0339's effect at full_gym and for a bench-owning home user unstated. P3: (iv) exemption as `injury == null`; zero slack in two pools; household-free bodyweight rows at gym Hip; the fixture assertion keyed on its ids. All folded into v4. **Converged.**
