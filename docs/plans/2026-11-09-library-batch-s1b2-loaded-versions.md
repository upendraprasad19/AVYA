# Library Batch S1b-2: 9 loaded versions, the same-movement rule, E010 / E045 `suitable_for`, seed v23, one cloud migration (v4, converged after review #3)

> **For agentic workers:** inline (§4.12.7): one worktree (`generator-step1-s1b2`, base `5d64d1a9` = PR #236), one
> writer. Reviewers and the B-pass are fresh Sonnet subagents.

**Founder decisions.** 2026-11-08 (board d8 to d11): the 9 dumbbell / kettlebell versions (OI-148; the 3 weighted
rows wait for Batch D's dip belt token) **on the condition that a loaded version and its original never share a
day**. 2026-11-09 (board d12): E010 Pike Push Up `suitable_for` gains Advanced, E045 Romanian Deadlift gains Beginner
(closure 1B-10b). The link field must not be called "twin" (founder wording, 2026-11-09).

**Split after review #1 (§4.12.1).** Draft 1 also retired E053 Donkey Calf Raise. That needs machinery of its own:
the removals file is bound to the 66-row founder sheet and to `removed_in` c2a / c2b
(`library_batch_c2_removals_file_test.dart:50-85`, `seed_exercise_library.js:229-230`), and E053's media is rebuilt
by `build_library_media_v16.js` from a hash-pinned old-rows input (`library_media_table_test.dart:455-456`) with no
prune step for a removed mapped row. E053 becomes **Library Batch S1b-3** (own plan after this merges). Closure
1B-9's `reopen_when` moves to "S1b-3 plan".

**Why this is NOT ship-dark.** New rows enter `queryV4` pools, `suitable_for` is a `queryV4` filter, and the rule is
code in both pickers. Full ×2 plan review, B-pass, record (`review_rounds: 2+`, no `tier`), golden re-recorded with
every changed key attributed. Blast radius **platform** (`supabase/migrations/**`,
`lib/shared/repositories/plan_engine/**`). `plan_generator.dart` is NOT touched (§4.4 rule 14).

**One live step.** The cloud re-seed migration (nine new rows, E010 / E045 `suitable_for`), on the founder's own go on
the exact file (§4.3). No bucket write.

## Facts (verified 2026-11-09 at `5d64d1a9` by four review seats; re-verified in Task 0)

| Fact | Source |
|---|---|
| Pairs (new ↔ original): N14 Dumbbell Sumo Squat ↔ E147 Sumo Squat; N15 Dumbbell Split Squat ↔ E259 Split Squat; N16 Dumbbell Walking Lunge ↔ E042 Walking Lunge; N17 Dumbbell Lateral Lunge ↔ E145 Lateral Lunge; N18 Dumbbell Hip Thrust ↔ E047 Hip Thrust (barbell, bench); N19 Dumbbell Glute Bridge ↔ E048 Glute Bridge; N20 Dumbbell Sumo Deadlift ↔ E050 Sumo Deadlift (barbell); N21 Kettlebell Romanian Deadlift ↔ E045 Romanian Deadlift; N22 Weighted Russian Twist ↔ E059 Russian Twist. No collision with any name, alias or removed name | library read; seat B r2 |
| Live name-keyed sets in generation: see the table in Decision 2. Dead: `exercise_selector.dart:284, 365, 383, 468` (V3 `pick()`, no caller) | seats A r1, r2 |
| Cross-variant: OFF B hard-excludes A's names except `strength` (`exercise_selector.dart:690, 924`); ON B soft-avoids A (`softFor`, `:876`). `excludeNames` and the universal-pool skip (`:1735`) are exact case; avoid sets are lowercase | read |
| `queryV4` callers pass `suitableFor: effectiveExp == 'advanced' ? null : effectiveExp` (`:274, 1329, 1446, 1655, 1675, 1692, 1711`). The ON family fill reads `suitable_for` (`core_list_selector.dart:302`); neither E010 (core int / adv) nor E045 (core every level) reaches that stage | read; seat A r2 |
| Importer `buildRow` (`add_library_batch_c_v15.js:137-160`) copies only `REQUIRED` (`:85-92`, includes `gym_availability`, `breathing_cue`, `pro_tip`), `variant_family` from the injury table row, and `LADDER`; it unions the source's raw injury tags with the table tokens; `slot_pattern` and any other key are DROPPED. Media keys are appended last (`:192-198`; `library_batch_c_rows_contract_test.dart:88-89`). `_optionalKeys`: `exercise_library_schema_contract_test.dart:41-49`, `library_batch_c_rows_contract_test.dart:37`. `slot_pattern` is pinned to 12 ruled ids (`exercise_library_core_fields_contract_test.dart:33-46, 128`). The `_Tree` sandbox (`test/scripts/library_media_importer_test.dart:25-52`) copies a hard-coded list of data files | seats B r1, r2 |
| Scope script (`library_batch_c_scope.js:97-125, 107, 149-152, 316`): each new source row needs `_meta.criterion_inputs` (`name`, `equipment_needed`, `core_levels`, `confidence: "high"`), a media-map entry `{}`, a note free of `renam|founder|trusted` and of the `strong` words, `changes` empty; `inputs_sha256` re-pinned by hand (`library_batch_c_source_test.dart:319-325`) | seat B r2 |
| Injury table: hand-written `judgement` rows are accepted and exempt from the builder (`library_batch_c_injury_coverage_test.dart:575-600`); the builder would add family `floor` / `majority` tokens. An untagged new row must be in `safe_pool_additions` (`:367-395`) and in `kV14SafePool` (`test/helpers/injury_safe_pool.dart`, `:471`), else `newRowPickViolations` (`test/helpers/library_injury_floor.dart`) flags it. E048 is untagged | seat B r2 |
| Pins that move: 862 → 871 (`exercise_library_merge_contract_test.dart:40-41`, `exercise_library_schema_contract_test.dart:177-178`, `exercise_plate_library_data_test.dart:43`); artwork-less 713 → 722 (`exercise_plate_library_data_test.dart:57-63`, `exercise_plate_resolver_test.dart:80`); new-row ids 633 → 642 (`library_new_row_pick_violations_test.dart:53`); core totals 131 / 156 / 128 → 135 / 165 / 137 (`exercise_library_core_fields_contract_test.dart:150`); `_meta.derived` rows 717, shipped 642, core 61 / 64 / 54 rows 100 (recounted by the test, written by `--write`); `core_list_like_for_like_data_test.dart:28`; `scorecard_gate_test.dart`; `generator_golden_hashes.json`. Unchanged: media rows 621 (`library_media_table_test.dart:111`) | seat B r2 |
| E010 / E045 exception owners: `library_s1_core_levels_test.dart:60-63, 122`; `core_list_pool_gate_test.dart:41-43, 274` | seat A r1 |
| Cloud: generator `BATCH` (`seed_exercise_library.js:46-70`) supports ONE retag record; new-row deactivation only for `replacement_new` removals; header hard-codes "the ONE changed row" and c2a / c2b. `exercise_library_cloud_seeded_test.dart`: `_batchLabel` regex `Batch (C2[a-z])\)` (`:130`), C2c checks (`:111-152`), a CLI group asserting `C2c`, the E230 restore line and the retag refusals (`:395-612`, `:468`, `:549-600`). Red from the library change until a newer seed file is on disk: `exercise_library_cloud_tuples_match_test.dart:113`, `exercise_library_cloud_seeded_test.dart:224, 245`. Cloud today 925 rows, 862 active, 63 inactive; `suitable_for` is a cloud column; the generator emits every column the new rows need | seat B r1, r2 |
| Seed `_exerciseLibraryVersion = 22` (`seed_service.dart:160`); 22 pinned at `library_seed_v20_upgrade_behavioral_test.dart:85, 97, 107`, `v21:83, 92, 101`, `v22:83, 92` | seat B r2 |
| `kettlebell` is granted by `full_gym` only; `elevated surface` at every tier. `gym_availability` values in the library: standard_gym, home, well_equipped_gym, specialty | read |

## Decisions (mine unless marked founder)

1. **The nine rows (founder: the set; mine: the fields).** Source rows N14 to N22, built so the importer reproduces
   them byte for byte.
   - **Copied from the original:** `category`, `movement_pattern`, `slot_pattern` (E048 and E050 carry one: N20 takes
     `[hip_dominant]`; N19 does NOT, founder 2026-11-09 after the Task 3 audit, so the ON Glutes isolation slot offers it; and N19 takes
     `priority_tier` 3, not E048's 2, so a gym user keeps E109 Glute Kickback (Cable) in that slot, founder 2026-11-09), `primary_muscles` in order (OI-454 contract), `secondary_muscles`, `target_focus`,
     `suitable_for`, `difficulty_level`, `priority_tier`, `tempo`, `is_bilateral`, `default_sets`.
   - **Set for the load:** `equipment_needed` [dumbbells] (N18 [dumbbells, elevated surface]; N21 [kettlebell], full
     gym only); `logging_type: weight_reps`; `is_foundational: false` (so the rows appear from phase 2; Phase 1 asks
     for foundational rows first); `discipline: strength`, `high_impact: false`, `requires_coaching: false`;
     `gym_availability: home` for the dumbbell rows (N11 precedent), `standard_gym` for N21; `confidence: high`.
     `exercise_type` copies the original except **N15 compound** (E259 is typed isolation; a loaded split squat is a
     compound lift; stated, measured in Task 3). **N20's reps / rest / CNS are set for dumbbells**, not copied
     (E050 is 5-6 reps, 180 s, CNS 5 for a barbell): `default_reps 8-12`, `rep_range 8-12`, rest 120, `cns_demand 3`;
     the other rows keep the original's numbers. `breathing_cue`, `coaching_cues`, `common_mistakes`, `pro_tip`,
     `indian_alternative`, `note` written for the load (N16 does not reuse E042's "add dumbbells" tip).
   - **`core_levels`** (each inside `suitable_for`, no exception): N14, N15, N19, N21 every level; N16, N17, N18, N20,
     N22 [intermediate, advanced]. Several are wider than the original (E147 / E259 / E048 core beginner only; E145
     intermediate only): the bodyweight originals stop at beginner because they cannot be loaded, and the load is
     what lets the movement progress (the S1 draft-1 values the founder saw on 2026-11-08). Task 3 reports each
     row's ON picks by level.
   - **`suitable_for` of N21** is E045's AFTER Decision 3 (all three levels), written as a source literal; a test
     asserts N21's equals E045's.
   - **Injury tags:** source raw tags = the original's tags; the table row is HAND-WRITTEN (class `judgement`,
     reason "loaded version of <id>, same joints", tokens ⊆ the original's tags, `variant_family` the original's);
     never builder-generated (it would add family tokens). A test asserts each final tag set equals the original's.
     **N19 is untagged** like E048: "Dumbbell Glute Bridge" joins `safe_pool_additions` and `kV14SafePool`.
   - **G0845 Legs Up Weighted Russian Twist** stays and is not linked: it is a different variant (legs raised), core
     `[]`, so the ON pool never picks it while N22 is core. OFF, G0845 and N22 may share a day; accepted and stated.
2. **The same-movement rule (founder condition; mine: the shape).**
   - **Field.** `same_movement_as` (JSON-only, new rows only, value the original's id). Not transitive (two loaded
     versions of one original would not exclude each other; none exists). The importer's pass-through list becomes
     `LINK = ['slot_pattern', 'same_movement_as']`, copied after `LADDER`, before the media keys. Intended allow-list
     additions: `same_movement_as` in both `_optionalKeys`; `slot_pattern` in the rows-contract `_optionalKeys`; N19 and
     N20 in the `_slotPattern` pin (12 → 14 ids).
   - **Principle.** A day never holds a row and its partner (founder). Where generation already treats a name as a
     HARD exclusion, the partner is excluded too; where it is a SOFT avoid tied to a day or variant, the partner is
     avoided too; per-exercise preferences stay keyed to the exercise. Decided set by set:

     | Set (file:line) | Kind | Expanded? |
     |---|---|---|
     | `queryV4 excludeNames` (`exercise_repository.dart:407-408`), fed by `_cascadeFill` (`exercise_selector.dart:1552`, `1657-1712`), `_topUpVariant` (`:1308, 1325`), L6 (`:1430-1447`), OFF B-vs-A (`:690, 924`) | hard | yes, once per call from the `getAll()` list the method already holds; no map is built when `excludeNames` is empty |
     | Universal-pool skip (`:1735`, bypasses `queryV4`) | hard | yes (built once per fallback; `repo` in scope) |
     | ON `passes` (`core_list_selector.dart:272`) and ON `picked` (`exercise_selector.dart:853`) | hard | yes, maintained incrementally (each chosen row adds its partner) |
     | ON B-vs-A `softFor` (`:876`), top-up softAvoid (`:1250, 1267`) | soft, variant | yes |
     | Cross-phase (`previousPhaseNamesByDay`), upper-day (`earlierFeederNamesA/B`) | soft, day | yes (lowercase) |
     | Demoted names (`:789, 1354, 1437-1454`; `core_list_selector.dart:398`) | per-exercise preference | no |
     | Plateau avoid (`plateauAvoidNames`, `:660-670, 800-815`, top-up) | per-exercise preference | no |

     **Amended by Unit 1B-F (2026-11-11, `docs/plans/2026-11-10-generator-1bf-flip.md`, Ruling 7):** the cascade,
     the universal pool, L6's post-pass and the mirrors in this table are deleted; the core-list pool is the only
     picker. The "Demoted names ... no" row no longer holds there: a demoted ORIGINAL's loaded versions are demoted
     with it (one direction; `ExerciseSelector._demotedWithLoadedVersions`), read by `_pickCoreList` (rankedPool's
     demoted set and the avoid set) and by the top-up, so a user who moved away from E147 is not handed N14. A
     demoted loaded version does not demote its original. Plateau names stay per exercise.

     **L6 consequence (stated):** L6 passes the day's `pickedNames`, which still holds the demoted pick while its
     replacement is chosen, so the partner is not that replacement (a user who moved away from E147 is not handed
     N14 in its place). After a swap the demoted name leaves the set (`exercise_selector.dart:1458`), so a later swap
     on the same day may pick it (no violation: the original is gone). Behavioural case with two demoted picks on
     one day; its own Task 3 attribution class.
   - **Helper.** Pure `SameMovement` (`lib/shared/repositories/plan_engine/same_movement.dart`):
     `SameMovement.fromRows(rows)`, `expand(Set<String>)` (exact casing), `expandLower(Set<String>)`; symmetric;
     unknown names pass through. Task 2 re-greps `pickedNames|excludeNames|avoidNames|softAvoid|demoted|plateau` and
     the diagnose doc lists every live hit against the table.
   - **Mirrors in lockstep:** `QueryV4Mirror` exclude (`test/plan_generator/v4_diagnostic/query_v4_mirror.dart:136-138`),
     `cascade_tracer.dart` at `:183, 216, 242, 266` and its attempt-5 pool; a `v4_diagnostic_test.dart` case.
   - **Scope.** Plan generation only: swap sheet, templates, custom pins, `buildPinnedDays` repeat pins, restore and
     `injury_substitutes.dart` (curated by name; the new rows are not in it) are unchanged.
   - **Registry.** SoT concept `same_movement_rule` (writer: source rows via the importer; readers: the seams;
     `behavioral_test_path:` the Task 2 production test); `docs/naming_conventions.md`: "not `twin` (retired-row
     mechanics), not `variant_family`"; `docs/sot_registry.yaml` ranges recomputed from anchors.
3. **E010 / E045 `suitable_for` (founder).** Both `[Beginner, Intermediate, Advanced]` through a new kept-row stage,
   `scripts/data/library_s1b2_suitable_for.json` (`{id, before, after}`), applied inside the importer's `kept.map`
   after the core-levels stage with the same before / after / throw logic; added to the `_Tree` sandbox data list;
   an `account` glob in `docs/blast_radius.yaml` with its constant in `blast_radius_library_data_account_test.dart`.
   Both exception owners drop E010 / E045. Effects: E045 OFF enters every dumbbell and gym beginner hip_dominant
   pool, Phase 1 included (foundational, priority 1, compound), measured not assumed (file-order ties); a beginner
   with `lower_back` or `hamstring` keeps today's pick. E045 ON: zero (already core at beginner). E010: zero in both
   worlds (OFF never filters advanced by `suitable_for`; ON core int / adv never reaches the family fill); Task 3
   proves both zeros.
4. **Seed v23 and one cloud migration.** Bundled 871 rows; cloud 925 → 934 rows, active 871, inactive 63. Generator
   `BATCH` gains `keptRowRecords` (a list: E010, E045 `suitable_for`; the E230 retag is live and re-seeds unchanged),
   `newRowIds` (N14 to N22), Intent / header text for "2 changed rows, 9 new rows", and an inline rollback that
   restores the two `suitable_for` values and sets the nine rows `is_active = false` (never DELETE). The test file's
   CLI group (`:395-612`) and `_batchLabel` regex are REWRITTEN for the S1b-2 shape (the C2c assertions describe a
   generator that no longer exists; migration 173's own text stays covered by the tuple checks against the file).
   Allocation `sh scripts/mint_migration.sh <slug>` (`--next` only reads); ledger hash on the LF file;
   `previousMigration: '173'`.
   **Red window and gate loop.** From the library change until a newer seed file is on disk, exactly these are red:
   `exercise_library_cloud_tuples_match_test.dart:113`, `exercise_library_cloud_seeded_test.dart:224, 245`. The
   pre-go gate loop runs with the generated file present UNTRACKED in `supabase/migrations/` (minted number reserved,
   `PRE_COMMIT_GATE_JOBS=1` on this VPS), so those tests are green; exactly ONE gate is then red by design: Gate 14
   (`scripts/check_migrations_applied.dart:43-50, 119-126` lists the directory and reports `UNAPPLIED: <file>` until
   `backups/applied_migrations.json` has the entry). Its output goes into the B-pass brief; every other gate must be
   green. After the apply, the ledger entry, the file and the code are staged together (the C2c precedent, `0577f760`)
   and the whole loop must be green before the commit.
5. **Media: none.** No media keys; initials in the UI (OI-442 precedent); scope media map `N14..N22: {}`.
6. **Gate zero, production path.** New `test/plan_generator/same_movement_day_gate_test.dart`: real `generateV4` over
   `generatorGoldenPersonas()`, OFF and ON, `@Timeout(10 min)`; per variant (`weekPlans[0]` A, `[1]` B) hard zero for a
   day holding a row and its partner; the oracle restates the link from the raw library (never calls `SameMovement`);
   non-vacuity counts (days holding either member of a pair, per world, must be > 0). Mutation-proven.

## Tasks

### Task 0: Baselines (scratch, clean tree)
- [ ] Audit OFF and ON (`PLAN_AUDIT_OUT`), gate report, `dump_all_picks` OFF; beginner hip_dominant picks by tier and
      injury; advanced vertical_push picks.
- [ ] Re-read every fact above at `HEAD`.

### Task 1: The data (RED tests first)
**Files:** `library_batch_c_source.json` (rows, `_meta.criterion_inputs` ×9, `--write`, `inputs_sha256` re-pin),
`library_batch_c_media_map.json` (`{}` ×9), `library_injury_additions_v15.json` (+9 hand-written),
`library_s1b2_suitable_for.json` (new), `add_library_batch_c_v15.js` (LINK, suitable_for stage),
`assets/data/exercise_library.json` (importer output, `--check` byte-equal), `test/helpers/injury_safe_pool.dart`,
`docs/blast_radius.yaml` + pin, `test/scripts/library_media_importer_test.dart` (`_Tree` list, stage cases).
- [ ] RED: the nine rows with Decision 1's fields, `same_movement_as`, and N19 / N20 `slot_pattern`; each link names
      an existing unlinked original; final injury tags equal the original's; N21's `suitable_for` equals E045's; E010
      / E045 after; `core_levels ⊆ suitable_for` with no exception; the stage refuses a foreign value.
- [ ] Repoint every pin in the Facts table to the stated values; never loosened.
- [ ] Mutations: LINK removed from the importer; one link at a missing id; one `suitable_for` back to `before`; one
      new row's tier off its equipment; one new row's injury tags short by one; N19 out of the safe pool.

### Task 2: The rule (RED first)
- [ ] Helper + unit tests (symmetric, pass-through, casing).
- [ ] Wire every "yes" row of Decision 2's table, `grep -c` each; mirrors in lockstep.
- [ ] Behavioural tests on production `generateV4`, real library: home_dumbbells and basic_gym personas never get a
      day with E147 and N14 (both orders), OFF and ON; a day holding N19 makes the universal pool skip E048; OFF
      non-strength B never holds A's partner, ON B avoids it softly; L6 with E147 demoted never substitutes N14;
      a demoted or plateau name's partner is NOT avoided for that reason alone.
      (Amended by Unit 1B-F, Ruling 7: this now holds for plateau names only; a demoted original's loaded versions
      are demoted with it on the core path and the top-up.)
- [ ] Gate (Decision 6).
- [ ] Mutations (applied, `grep -c`): `queryV4` expansion removed; universal-pool skip reverted; ON `passes`
      reverted; helper one-directional; a mirror left unexpanded; demoted set wrongly expanded.

### Task 3: Measure and attribute
- [ ] Audit OFF and ON after; `dump_all_picks` diff; `RECORD_GENERATOR_GOLDEN=1`, every changed key classified (new
      row picked / E045 widened / E010 widened / same-day exclusion / B-vs-A exclusion / L6 partner exclusion / N15
      typed compound / ripple), a counterfactual run per class.
- [ ] `scorecard_gate_test.dart`, `injury_sweep_*`, the multi-injury sweep, both gates.
- [ ] Results section: picks of each new row by tier, level and world (N19 / N20 in ON hip_dominant slots through `slot_pattern`); rule firings; beginner hinge before / after;
      E010 zero in both worlds; E045 ON zero.

### Task 4: Seed v23, cloud generator, gate loop, reviews
- [ ] Seed constant 22 → 23 with comment; the pins repointed; `library_seed_v23_upgrade_behavioral_test.dart`
      (real `seedIfNeeded`: a v22 box ends at v23 with the nine rows and the two widenings, every other row
      unchanged; a v23 box not rewritten); registry cites from anchors.
- [ ] Generator `BATCH` and the rewritten CLI group; guard tests (missing record, drifted record, unknown tag).
- [ ] Mint the number, generate the file untracked; gate loop (§4.12.8): whole-project analyze,
      `sh scripts/pre-commit.sh`, full suite + golden; green except Gate 14 (Decision 4), whose output is recorded.
- [ ] B-pass (lenses 1, 3, 6, 7, 8; plus a v22 install on the new bundle, the universal pool, the lowercase sets, the
      L6 consequence, the untracked-file loop).

### Task 5: The live step (founder's go on the exact file)
- [ ] Rehearse in `BEGIN ... ROLLBACK` in the local docker image (then a read-only count on prod); expected 934 / 871 /
      63; show the founder the file and the rollback; on the go apply via `.claude/apply_migration_via_api.js`,
      per-row md5 against the generator, append `backups/applied_migrations.json`, stage the file, re-run the gate loop.

### Task 6: Close-out
- [ ] Diagnose doc; `generator-step1a.closure.yaml` 1B-8, 1B-10b, 1B-11 closed, 1B-9 → S1b-3;
      `library-batch-s1b2.closure.yaml`; OI-148 text (the 3 weighted rows stay, Batch D); plan-review record;
      `land_pr.sh`; worktree retired; memory; board (S1b-3 added).
- [ ] Founder device list: from phase 2, a home-dumbbell leg day can show a dumbbell version and never its original
      that day; a beginner dumbbell plan can show Romanian Deadlift in phase 1.

## Results (Task 3, measured 2026-11-09 on the final tree)

**Two founder rulings after the first measurement (2026-11-09).** (1) N19 Dumbbell Glute Bridge drops the copied
`slot_pattern: [hip_dominant]`: with it, the ON pool never offered N19 in the Glutes hip_isolation slot, so home-dumbbell
users kept bodyweight Glute Kickback there and the audit's "unloaded where a loaded row fits" rose 441 -> 502 on 61
plans whose picks were identical. (2) N19 takes `priority_tier` 3, not E048's 2: at 2 it displaced E109 Glute Kickback
(Cable), the S1b-1 gym choice, in the gym Glutes isolation slot (498 -> 92 plans per gym tier). Both are pinned in
`library_s1b2_loaded_versions_test.dart`; the `_slotPattern` pin keeps N20 only.

**Same-movement gate (998 personas).** OFF: 4,441 member-days, 5 loaded-version placements, 0 shared days. ON: 3,184
member-days, 977 placements, 0 shared days. Each gate mutation (queryV4 expansion removed; ON picked partners removed)
reddens its own world only.

**Plan audit (2,304 plans, no injuries), S1b-1 -> S1b-2.**

| measure | OFF before | OFF after | ON before | ON after |
|---|---|---|---|---|
| verdict suitable | 165 | 165 | 431 | 431 |
| unloaded pick where a loaded row fits | 1700 | 1700 | 441 | 441 |
| a major muscle at 0 sets in week 1, 2 or 3 | 84 | 92 | 284 | 278 |
| lead lift 2+ sets under an isolation | 876 | 879 | 1090 | 1085 |

The OFF +8 zero-set plans are all `build_muscle|5|beginner|basic_gym|{30,45,60,90}|{1,2}`, week 2 Quads at 0: E045
Romanian Deadlift, now open to beginners, takes variant A's hinge in weeks 1 and 3, so variant B no longer excludes
Bodyweight Good Morning and picks it over Trap Bar Deadlift, the week's only Quads credit. This is the OI-475 class
("even weeks can hold no quad work", measured 2026-11-07, founder call pending); this batch moves which plans show
it and adds the eight to that item's evidence.

**Plans holding each row (audit, 576 plans per tier: bodyweight / home_dumbbells / basic_gym / full_gym).**

| row | OFF | ON |
|---|---|---|
| N18 Dumbbell Hip Thrust | 0 | 0 / 169 / 0 / 0 |
| N19 Dumbbell Glute Bridge | 0 | 0 / 500 / 92 / 92 |
| N20 Dumbbell Sumo Deadlift | 0 | 0 / 116 / 0 / 0 |
| N22 Weighted Russian Twist | 0 | 0 / 20 / 0 / 0 |
| N14, N15, N16, N17, N21 | 0 | 0 |
| E045 Romanian Deadlift | 0 / 448 / 293 / 258 -> 0 / 576 / 421 / 441 | 0 / 576 / 240 / 240 (unchanged) |
| E010 Pike Push Up | unchanged | unchanged (bodyweight 426; equipped 0) |

OFF places a loaded version almost never (0 in the audit, 5 in the golden): queryV4 ties break by key order and an E
original sorts before its N version, the equipment-fit gap tracked as OI-484. ON places them through the core-list
ranking. N14 to N17 and N21 reach no plan in either world: their originals or other core rows outrank them in every
slot they fit; they are in the library for swaps and for the step-2 ranking.

**Golden (998 personas): 442 keys changed** (basic_gym 221, full_gym 165, home_dumbbells 54, bodyweight 2; grid 430,
injury 7, cross 3, owned 2). Attributed by counterfactual record runs from the final tree, each reverting one class:
- nine rows removed (which also removes every same-movement link): 343 keys return to the S1b-1 hash;
- E045 `suitable_for` back to [Intermediate, Advanced]: 99 keys return;
- E010 `suitable_for` back to [Beginner, Intermediate]: 0 keys move;
- the rule off (rows kept): 13 keys differ from the final tree, all inside the 343.
The 343 and the 99 are disjoint and cover all 442: 330 new-row picks and their ripple (later slots, B-vs-A and top-up
choices shifting once a pool gains a row), 13 where the rule fired, 99 from the E045 widening. Fixture re-recorded.


**Gate loop findings (Task 4, 2026-11-09).** The full suite surfaced three suites this batch moves, each fixed in the
batch: (1) `core_list_like_for_like_data_test.dart` re-recorded on purpose: N19 joins every Glutes hip_isolation cell,
after E109 in the six gym cells and alone in the three home_dumbbells cells (the founder's two N19 rulings, nothing
else moved); (2) `quads_floor_6day_behavioral_test.dart` D2: N14 Dumbbell Sumo Squat and N17 Dumbbell Lateral Lunge
copy their originals' `primary_muscles` (another muscle first, Quads and Glutes listed), so they join the known
not-quad-first set and keep the same Glutes credit as Sumo Squat and Lateral Lunge; (3)
`exercise_library_cloud_tuples_match_test.dart`: its sandbox copied the generator's record files by name and missed
`library_s1b2_suitable_for.json` (a hard stop in the generator), so it now copies every `scripts/data/library_*.json`
and pins the three names; its "a row removed" mutant removed the last row, now N22, which the generator refuses by
design (`BATCH.newRowIds`), so it removes the first (ordinary) row.

**Migration 174 (Task 5 rehearsal, 2026-11-09).** Minted `mig/174`; the generated file is byte-identical to the one
generated before the N19 rulings (`priority_tier` and `slot_pattern` are not cloud columns). Local docker
(`supabase/postgres:17.6.1.084`): the table built from the live column types, then 074, 125, 162, 164, 167, 171, 173
replayed, gives 925 / 862 / 63 and a content md5 (every column but `created_at`) of `a9ac6569e77ce70f2b7fc8634e1644de`,
equal to prod read read-only the same day. Inside `BEGIN ... ROLLBACK`: 934 / 871 / 63; 2 existing rows changed (E010
and E045 `suitable_for`, each now Beginner, Intermediate, Advanced); 9 new rows; post-apply md5
`fd91c822e22819c993b2ed541620a496`, unchanged by a second apply; the inline rollback leaves 0 existing rows differing
and the 9 new rows inactive (934 / 862 / 72).
**Applied live 2026-11-10** on the founder's go, by `.claude/apply_migration_via_api.js` (HTTP 201): read-back 934 / 871 /
63, content md5 `fd91c822e22819c993b2ed541620a496` (equal to the rehearsal); ledgered in `backups/applied_migrations.json`.

## Review log
- **Round 1 (draft 1), two seats.** Seat A: 4 P1 (OFF B hard-excludes A; dead V3 lines listed, live ones missing;
  expansion must run before the loop from the full library; mirror call sites), 4 P2, 1 P3. Seat B: 2 P0 (the
  importer drops unknown keys; E053 cannot use the sheet-bound removals file), 5 P1 (E053 media is generated; scope
  inputs; injury table rows carry the family; pinned counts; the seed generator cannot emit a new-row rollback or a
  record list), 5 P2. Resolution: v2; E053 split to S1b-3.
- **Round 2 (v2), two fresh seats.** Seat A: 2 P1 (the name-keyed sets were not decided one by one: plateau,
  demoted, top-up softAvoid; L6's partner exclusion unstated), 4 P2 (N20 barbell numbers, N15 typed isolation,
  `gym_availability` unset, G0845 overlap, the ON `suitable_for` reader, core levels wider than the originals), P3s.
  Seat B: 4 P1 (the importer drops `slot_pattern` and three pins hold it; N19 is untagged and needs the safe pool;
  counts wrong or missed: new-row ids 633, media rows 621 unchanged, core totals; the cloud tests' CLI group must be
  rewritten and the red set listed, with a gate loop that can be green), 3 P2 (scope `confidence` and note words, the
  suitable_for stage placement and sandbox list, hand-written injury rows), P3s. Resolution: v3 (Decision 2's table,
  Decision 1 field list, Decision 4 red window and loop, Facts table).
- **Round 3 (v3), one fresh seat, both lenses (convergence check).** Every v3 resolution verified against the code
  (the set table complete and coherent; LINK, the `_slotPattern` pin, the hand-written injury rows and the N19 safe
  pool accepted; counts recomputed: 871, 722, 642, 135 / 165 / 137, derived 717 / 642 / 61 / 64 / 54 / 100, cloud
  934 / 871 / 63). 1 P1: the untracked-file loop cannot be fully green because Gate 14 lists the directory; 2 P2
  (L6 wording after a swap removes the demoted name; skip the partner map on an empty `excludeNames`), 1 P3 (confirm
  N19 / N20 ON picks). v4 folds all four; the P1 fix is a stated expected red with its gate cited, no design change.
  Converged.
