# Batch A — Library data repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (execution mode is INLINE, see below). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the 292-row bundled exercise library and its cloud copy. When it is done:
- coaching text sits in the right fields, one cue per list item;
- true duplicates collapse into one row;
- one mislabelled row becomes visible to the generator's slots;
- the start/end pictures the founder flagged are the right way round.

**Architecture:** Mostly a data rewrite of `assets/data/exercise_library.json`, shipped by one seed bump (v11 → v12) and one non-destructive cloud re-seed migration. The only Dart changes:
- the seed now PRUNES retired ids (`putAll` never deletes today);
- `ExerciseRepository`'s two exact-name lookups fall back to `name_aliases`.

There is no generator code change. `plan_generator.dart` and `exercise_selector.dart` are untouched.

**Tech Stack:** Flutter/Dart, Hive, Supabase Postgres, Node (one-shot repair script, seed generator), Python (plate pipeline record only).

**Spec:** `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §9 row A. Task 0 corrects the spec from the evidence below. Label normalisation moves to Batch B: on today's pool it would make towel moves win the novelty picks for home and gym users (see Evidence).

**Tier / process:** L (schema + plan-engine data + migration).
- Plan review ×2 context-blind. Record at `docs/plan-reviews/library-data-repair.md`.
- B-pass before the merge and before the live apply.
- Recurrence class `exercise_library_schema`: every diagnose-doc cites `e1a7c4` (stub-schema re-seed) and `ada3fb` (cloud seed).

**Execution mode (§4.12.7): INLINE.** Every task rewrites the same JSON file and the same count pins, so there is a single writer in one worktree (`library-data-repair`), and the tasks run in order. One mutation per task is re-verified before its commit.

**Commits:** one per task, pushed ONCE at the tip; the PR's CI is the full-suite gate. Between Task 2's commit and Task 6's commit, `exercise_library_cloud_seeded_test` (seed tuple count == JSON rows) is red, because the new seed file may only be committed together with its ledger entry after the live apply. The tip is green. Pre-commit runs no tests (ADR-0018), so this does not block the intermediate commits.

**Founder gates, all listed up front:**
1. Approve this plan.
2. Accept a §4.6 waiver: a seed rewrite has no kill switch. Rollback = revert the JSON, bump to v13, re-run migration 125.
3. Give a separate go for the prod work in Task 6, after the B-pass: one rolled-back rehearsal, then the live apply.

No EF deploy, no APK, no Supabase branch (the migration is non-destructive).

## Global Constraints

- **Row counts.** Library rows 292 → **285** (7 retired). Ids are never renumbered or reused. A retired id never reappears as a row; it is listed in exactly one kept row's `merged_ids`.
- **Optional keys are ABSENT, never `""` or `null`** (`docs/naming_conventions.md:250`):
  - `demo_slug` / `demo_pair`: absent on rows with no drawing.
  - `name_aliases` (List<String>, already read by `ExerciseRepository.search`): present only on rows that absorbed a retired name.
  - `merged_ids` (List<String>): present only on rows that absorbed a retired id.
- **`injury_contraindications` is never merged.** Kept rows keep their own tags. `test/contracts/injury_undertag_13b_contract_test.dart:72-79` (`k13bKeptSafe`) pins 'v-up' and 'hip abduction machine' as untagged, by founder decision.
- **`primary_muscles` is edited only by the same-pattern merge union in Task 2.** It feeds `muscle_groups.dart`, the superset antagonists, titration, plateau and the scorecard.
- **Coaching text is moved VERBATIM.** No rewording or capitalisation; only field placement and list splitting change.
- **Number format.** `met_value` and `cal_per_set_est` are always written with a decimal point (`5.0`, not `5`). All 448 non-null values in today's file are written that way, so Dart decodes them as `double`.
- **JSON layout.** The file keeps its existing 2-space indent and key order.
- **Seed version.** `_exerciseLibraryVersion = 12`, one bump for every task.
- **Cloud seed.**
  - File name `<NNN>_reseed_exercise_library.sql`. It must match `[/\\]\d+_\w*seed_exercise_library\.sql$` (`exercise_library_cloud_seeded_test.dart:40`).
  - `NNN` comes only from `sh scripts/mint_migration.sh reseed_exercise_library`.
  - Generate with `node scripts/seed_exercise_library.js <NNN>_reseed_exercise_library.sql`. Always pass the name: the script's default overwrites 125.
  - Cloud ids: UUID v5 of `exercise_library|<E###>`, namespace `5a1f0b0c-9dad-11d1-80b4-00c04fd430c8`.
- **No `exerciseBox.clear()`.** The prune is `deleteAll(<explicit ids>)`.

## Review Focus

1. **A retired name already sits in a planned day.** The founder's Phase-4 plan may hold "Hip Abductor Machine", which the frozen baseline picks.
   - Expect: the day still shows the plate and cues, and the AI coach still finds repaired form cues. The cloud row stays, inactive, with its text copied from the kept twin.
   - Pinned: alias test (Task 2) and cloud test (Task 6).
   - Scope: only test accounts can hold such a day (§1). The cloud audit covered logs and templates, not planned days, because plans live in Hive.
2. **Upgrade from v11 with community rows in `exerciseBox`.**
   - Expect: only the 7 retired E-ids are deleted, and non-E keys are untouched.
   - Pinned: prune test (Task 2).
3. **Fresh install, or a box that never held a retired id.**
   - Expect: the prune is a no-op.
   - Pinned: Task 2.
4. **A slot that picked the retired twin.**
   - Expect: it now picks the kept twin, e.g. Glutes/hip_isolation in Phase 1 at full_gym gets Hip Abduction Machine.
   - Pinned: inheritance test (Task 2) plus the pick diff (Task 5).
5. **A repaired row in the coaching panel and the plate sheet.**
   - Expect: one bullet per cue, and no numeric breathing value is shown.
   - Pinned: Task 1. The guards are kept and tested with a synthetic numeric row.

---

## Evidence (verified 2026-10-21/22; round-1 review re-derived the counts)

**136 shifted rows.** Exactly the rows whose `breathing_cue` is numeric; `met_value` is null on exactly those rows. Every text field moved one column right. A dry-run of the Task 1 mapping gave:
- 0 empty lists, 0 numeric `breathing_cue` left, 0 `;` left;
- `cal == 2 × met` on 40 of the 136 repaired rows (40 of the 156 healthy rows also show it), which confirms which column each value came from.
- Of the 7 pairs, E165, E167, E168, E107 and E176 are shifted rows.

**List shape.** Healthy rows (156) store cues as `"; "`-joined text: 115 rows in `coaching_cues`, 84 in `common_mistakes`. `coaching_content_panel.dart:75-81` does not split on `;`; `exercise_plate_sheet.dart:43-51` does. Only real arrays render correctly on both.

**Duplicates (cloud, 2026-10-22).**
- No `workout_log_exercises` rows under any of the 7 retired names.
- No `workout_logs` or `template_exercises` reference them by id or name.
- Both FKs (`workout_logs_exercise_id_fkey`, `template_exercises_exercise_id_fkey`) are `NO ACTION`.
- `beat-my-coach/index.ts:198` filters `is_active = true`; `getFormCues.ts:65-92` does not. So `is_active = false` hides the rows from the first and keeps form cues for the second.

**Not merged.** Each goes to Batch C, as named in its spec row:
- E075 Dip (Parallel Bars) / E008 Chest Dip: different emphasis and drawing; E075 is hard-coded at `exercise_selector.dart:529`.
- E261 / E274: E261 heads `universalPoolV4['shoulder_isolation']` (`:532`).
- E117 / E007: the founder kept both.

**Labels.** Six KEPT bodyweight rows are invisible to their slot label: E272, E273, E276, E277, E289, E290. Making them visible on today's pool is a regression:
- `_preferNovel` (`exercise_selector.dart:1054-1066`) walks past the first sorted entries whenever `avoidNames` is non-empty. A Phase 2+ home user's Lateral Delts pool would become [E013, E273, E289] and flip to Towel Lateral Raise.
- E276/E277 would stay inert anyway: every Mid Back slot is `compound` and both rows are isolation.

These six move to Batch B's equipment-aware pool (OI minted in Task 0). Only E172's typo (`target_focus` "Lats" on a side bend) is fixed here.

**Plates.** The founder's export `our_image_start_end_swapped` (scratchpad `export_t2.json`) has 19 rows on 19 distinct slugs, all pairs. `our_image_marked_wrong` lists E207 (sole user of `torso-twist-stretch`) and E179 (shares `hanging-leg-raise` with E057).

## File map

| File | Change |
|---|---|
| `assets/data/exercise_library.json` | Tasks 1–4 data |
| `scripts/repair_exercise_library_v12.js` (new) | One-shot, idempotent repair; header names this plan |
| `lib/core/services/seed_service.dart:80-97,194-200` | v12 history comment; prune after `putAll` |
| `lib/shared/repositories/exercise_repository.dart:43-66` | Alias fallback in `getByExactName`, `hasExactNameWhere` |
| `lib/features/train/screens/active_workout/coaching_content_panel.dart:56-63`, `lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart:103-105` | Stale "OI-149: text exists nowhere" comments → describe the guard only |
| `assets/exercise_plates/*` | 19 slugs swap -1↔-3; delete `torso-twist-stretch-{1,3}.svg` |
| `scripts/build_exercise_plates.py` | `SWAP_FRAMES` (19 slugs), applied where -1/-3 are written |
| `docs/plans/exercise-plates-mapping.json` | Drop 9 entries (7 retired + E207 + E179) → 156 |
| `scripts/seed_exercise_library.js` | Emit `name_aliases` (NULL when absent); emit `UPDATE … SET is_active = false` for every `merged_ids` UUID |
| `supabase/migrations/<NNN>_reseed_exercise_library.sql` | Generated: upsert 285 rows, deactivate 7 |
| `backups/applied_migrations.json` | Entry; committed WITH the .sql after the live apply |
| `test/plan_generator/dump_all_picks.dart` (new) | `dart run` tool: every persona's picks from `generateAll()` → JSON at a path argument |
| Diagnose-docs ×4 (`docs/diagnoses/2026-10-22-library-*-<id>.md`) | One per Tasks 1–4; full template (recurrence class) |
| `docs/audit/library-data-repair.closure.yaml` | Gate 40 |
| Docs | SoT `exercise_library_schema` (`docs/sot_registry.yaml:11299`); `docs/naming_conventions.md` (`name_aliases`, `merged_ids`); `docs/architecture/train-detail.md:21`; spec; OI board |

---

### Task 0: Spec corrections, OIs, pre-change pick dump

- [ ] **Step 1: Correct the spec.**
  - Status → "Approved 2026-10-21; Batch A planned 2026-10-22".
  - §3.1 label line: "`target_focus` (never `primary_muscles`) is normalised to the slot vocabulary in Batch B, with the equipment-aware pool".
  - §3.3: retired rows stay in cloud as `is_active = false`.
  - §3.4: "927 kept rows include 219 of the 292 library rows".
  - §9 row A: "text un-shift + list shape (OI-149), 7 duplicates retired + aliases, E172 label typo, 19 founder-flagged start/end swaps, 2 wrong drawings removed".
  - Row B gains: "target_focus for the 6 invisible bodyweight rows; universal-pool and warmup/cooldown names repointed to kept rows; E261/E274 (one movement)".
  - Row C gains: "remove the remaining discarded library rows (incl. E075, E261), then relabel E274".
- [ ] **Step 2: Update scratchpad `tag/merged.json`** (Batch B/C input) to the Task 2 directions: E216/E219/E220 keep, E165/E167/E168 discard. Print the remaining library-discard count and put that number in the spec's row C.
- [ ] **Step 3: Mint three OIs** with `sh scripts/mint_oi.sh "<title>"`. Each says **Blocked on:** "Batch B generator rework (spec §9 row B)":
  - (a) "Generator: 57 library rows unreachable because no slot requests exercise_type 'calisthenics'".
  - (b) "Generator: 11 of 13 attempt-1 sub-focus strings match 0 rows (slot `long_head` vs data 'Long Head')".
  - (c) "Library: 6 kept bodyweight rows (E272 E273 E276 E277 E289 E290) invisible to their slot label".
- [ ] **Step 4: Create the dump tool and record the before-state.**
  - Create `test/plan_generator/dump_all_picks.dart`, mirroring `generate_baseline.dart`'s entry. It writes `{personaId: [[dayName, [exerciseName…]]…]}` from `generateAll()` to `args[0]`.
  - Run `dart run test/plan_generator/dump_all_picks.dart <scratchpad>/picks_before.json` BEFORE any data change.

### Task 1: Coaching-text un-shift + list shape (closes OI-149)

**Files:**
- Script; JSON; two stale comments.
- Tests:
  - `test/contracts/exercise_library_text_shape_contract_test.dart` (new);
  - `test/contracts/breathing_cue_numeric_suppressed_test.dart` (header + test 2);
  - `test/contracts/exercise_plate_sheet_test.dart:138-151`.
- Diagnose `…-library-text-shift-<id>.md`.

**Interfaces:** Produces `repairText(rows) → rows` in the script. Tasks 2 and 3 add `mergeDuplicates` and `relabel`; the script runs all three in that order, plus `writeLibrary(rows)` (the number-format rule above).

- [ ] **Step 1: Write the failing data contract.**
  - `no row has a numeric breathing_cue` (today 136).
  - `coaching_cues and common_mistakes are non-empty List<String> with no element containing ';'`.
  - `E013 repaired`:
    - `breathing_cue == 'Natural breathing'`;
    - `coaching_cues == ['Slight forward lean','lead with elbows not hands','stop at shoulder height']`;
    - `common_mistakes == ['Swinging body','going above shoulder height','too heavy']`;
    - `warmup_protocol == 'None needed'`, `met_value == 3.0`, `cal_per_set_est == 5.0`, `pro_tip == ''`.
  - `E064 repaired`:
    - `breathing_cue == 'Exhale on the drive (pull)'`;
    - `coaching_cues == ['Legs first, then lean back, then pull','reverse on return','keep back straight']`;
    - `common_mistakes == ['Pulling with arms first','rounding back','rushing the stroke']`;
    - `cal_per_set_est == 18.0`.
  - `indian fields recovered`: `is_indian_context` is true for E076, E077, E078, E200; `indian_alternative` is non-empty for E054, E061, E062, E063, E076, E077, E078, E200.
  - `met/cal are doubles`: every non-null `met_value` and `cal_per_set_est` decodes as `double`.
- [ ] **Step 2: Run** `flutter test test/contracts/exercise_library_text_shape_contract_test.dart`. Expect FAIL.
- [ ] **Step 3: Implement `repairText`.** For each row whose `breathing_cue` is numeric, every value is taken from the ORIGINAL row:
  - `met_value` ← old `cal_per_set_est`.
  - `cal_per_set_est` ← `Number(old breathing_cue)`.
  - `breathing_cue` ← old `coaching_cues.join(', ')`.
  - `coaching_cues` ← `split(old common_mistakes)`. When the OLD `common_mistakes` list has more than one element (only E064), first join it into one string with `', '`.
  - `common_mistakes` ← `split(old warmup_protocol)`.
  - `warmup_protocol` ← old `pro_tip`; `pro_tip` ← `''`.
  - `indian_alternative` ← old `source` for the 8 ids, else `''`; `source` ← `''`.
  - `is_indian_context` ← `true` for the 4 ids.

  Then for ALL rows: `coaching_cues = split(coaching_cues)`, `common_mistakes = split(common_mistakes)`, where `split` = flatMap on `';'`, trim, drop empties. The script is a no-op on its own output.
- [ ] **Step 4: Rewrite the old pins and comments.**
  - `breathing_cue_numeric_suppressed_test` test 2 → "0 numeric rows remain (OI-149 repaired)". Keep test 1 (both surfaces guard `^\d+(\.\d+)?$`). Rewrite the header.
  - Point `exercise_plate_sheet_test.dart:138-151` at a synthetic row map with `breathing_cue: '12'`.
  - Fix the two stale code comments.
- [ ] **Step 5: Run** the three files plus `coaching_content_test`, `coaching_notes_behavioral_test`, `exercise_library_schema_contract_test` and `dart run scripts/check_equipment_audit.dart`. Expect PASS.
- [ ] **Step 6: Mutation.** Put one `"a; b"` element back → the shape test reddens. Revert; `git diff --stat` shows only the intended files.
- [ ] **Step 7: Diagnose-doc + `dart run scripts/validate_diagnose_doc.dart <path>`.**
  - Writers: the JSON; `seed_service.dart:194` (`putAll`).
  - Readers:
    - `coaching_content_panel.dart:75-81`;
    - `exercise_plate_sheet.dart:43-51`;
    - `exercise_selector.dart:1254` (`notes = coaching_cues.first`, now one cue instead of the packed text);
    - `getFormCues.ts:65-92` (the cloud copy is shifted too, so the coach serves mistakes as cues; Task 6 fixes it).
  - Commit with trailers `closes-diagnose: <id>` and `closes-oi: OI-149`.

### Task 2: Retire 7 duplicate rows, aliases, seed prune, v12

**Files:**
- `seed_service.dart`, `exercise_repository.dart`, JSON, plates mapping json.
- Tests:
  - `test/contracts/exercise_library_merge_contract_test.dart` (new);
  - `test/contracts/library_seed_prune_behavioral_test.dart` (new);
  - `test/contracts/seed_prune_wired_test.dart` (new; `presence_only: true` because the call site sits inside an asset-loading method);
  - `test/contracts/exercise_alias_lookup_behavioral_test.dart` (new).
- Pins to update:
  - `exercise_library_schema_contract_test.dart` (`_optionalKeys` +2; "35 + 4"; 285 rows; 158 plated);
  - `exercise_plate_library_data_test.dart` (v ≥ 12, 285 rows, 158/127, mapping);
  - `test/plan_generator/exercise_target_focus_review.csv` (delete the 7 rows).

**Interfaces:**
- Produces `static Set<String> retiredLibraryIds(Iterable<Map> rows)` in `SeedService`: the union of `merged_ids`. Pure, `@visibleForTesting`.
- Produces `static Future<void> pruneRetired(Box box, Set<String> ids)`: `box.deleteAll(ids.where(box.containsKey))`.
- `getByExactName(String)` and `hasExactNameWhere(String, bool Function(Map))` keep their signatures.

**Merge table.** Every kept row gains `name_aliases += [retired name]` and `merged_ids += [retired id]`.

Where the twins share `movement_pattern`, the kept row ALSO takes the retired twin's selection fields, so the slot it served keeps the same movement. Unions de-duplicate case-insensitively, keeping the kept row's spelling ("Triceps (long head)" vs "Triceps (Long Head)").
- the union of `target_focus` and `primary_muscles`;
- the min of `priority_tier`;
- the OR of `is_foundational`.

Nothing else is merged, injury tags included.

| Retired → kept | Selection fields carried over | Note |
|---|---|---|
| E241 Close-Grip Bench Press → E016 Close Grip Bench Press | none (patterns differ) | `elbow_extension` loses one compound row; no pool exhausts |
| E240 Overhead Cable Extension → E097 Overhead Tricep Cable Extension | priority 3→2 | |
| E225 Hip Abductor Machine → E107 Hip Abduction Machine | foundational, priority 3→2, target_focus + Glutes, primary_muscles + Glutes | E107 stays injury-untagged (`k13bKeptSafe`) |
| E249 V-Ups → E176 V-Up | priority 3→2, primary_muscles + Core | E176 stays injury-untagged (`k13bKeptSafe`) |
| E165 Quad Stretch → E216 Standing Quad Stretch | none (patterns differ) | `warmup_cooldown.dart:142-148` emits E216/E219/E220 names, so keeping these needs no generator change |
| E167 Cross Body Shoulder Stretch → E219 Cross-body Shoulder Stretch | none | |
| E168 Doorway Chest Stretch → E220 Chest Doorway Stretch | none | |

- [ ] **Step 1: Write the failing tests.**
  - **Merge contract:**
    - 285 rows, and none of the 7 ids is present;
    - each retired id appears in exactly one `merged_ids`, and no row id appears in any `merged_ids`;
    - no alias equals another row's `name` (case-insensitive);
    - the table holds: E107 `is_foundational == true`, `priority_tier == 2`, `target_focus` contains 'Glutes', `injury_contraindications == []`; E176 `injury_contraindications == []`; E016 `movement_pattern == ['horizontal_push']`.
  - **Schema contract:**
    - `_optionalKeys = {'demo_slug','demo_pair','name_aliases','merged_ids'}`;
    - `name_aliases` / `merged_ids`, when present, are non-empty `List<String>`;
    - 285 rows, with the E261/E294 asserts kept.
  - **Prune behavioral** (real Hive box in a temp dir). Start with keys `E241`, `E016`, `0c5e…` (a UUID-shaped community key), then run `pruneRetired(box, retiredLibraryIds(<bundled rows>))`:
    - `E241` is absent; `E016` and the community key are present;
    - a second run does not throw;
    - on an empty box it is a no-op.
  - **Prune wired:** in `seed_service.dart`, with comments stripped, `pruneRetired(` appears after `putAll(entries)` inside `_seedExercises`.
  - **Alias behavioral** (repo over a box seeded from the bundled JSON):
    - `getByExactName('Hip Abductor Machine')?['id'] == 'E107'`, also for `' hip abductor machine '`;
    - `isCompoundByExactName('Close-Grip Bench Press') == true` (E016 is compound; without the alias this returns false);
    - `hasExactNameWhere('V-Ups', (_) => true) == true`;
    - `getByExactName('Nonexistent') == null`.
    - **Mirror:** in a 2-row box, row A named "X" and row B with alias "X" → returns A.
  - **Inheritance behavioral:**
    - `queryV4(movementPattern: 'hip_isolation', targetMuscle: 'Glutes', equipmentTier: 'full_gym', exerciseType: 'isolation', foundationalOnly: true, exclusions: const {}, capability: null)` contains E107. Today it returns E225; `is_foundational` decides this.
    - Run the same call again with `capability` built the way `test/plan_generator/generator_matrix.dart` builds it (`EquipmentVocab.effectiveItems` for `full_gym`). Production derives capability at every tier (OI-144).
    - `E107.primary_muscles.map(muscleGroupOf)` contains the group `muscleGroupOf('Glutes')` returns. This is the scorecard/titration credit that E225's `['Glutes']` gave; queryV4 already matches E107 through "Glutes (medius)", so only `muscleGroupOf` sees the union.
- [ ] **Step 2: Run.** Expect FAIL.
- [ ] **Step 3: Implement.**
  - `mergeDuplicates` in the script (table, then delete the 7 rows).
  - v12 plus a history comment covering Tasks 1–4.
  - In `_seedExercises`, after `putAll`: `await pruneRetired(_hive.exerciseBox, retiredLibraryIds(entries.values));`.
  - In both name lookups: keep the exact loop, then add a second loop over rows whose `name_aliases` is a `List` containing the trimmed, lowercased target.
- [ ] **Step 4: Run** every Task 2 test, plus:
  - Task 1's tests;
  - `injury_undertag_13b_contract_test.dart`;
  - `test/auth/cross_account_isolation_test.dart`;
  - `exercise_plate_library_data_test.dart`, `exercise_plate_resolver_test.dart`;
  - `test/contracts/equipment_tier_consistency*`;
  - `dart run scripts/check_equipment_audit.dart`.

  Expect PASS. (The cloud seeded test is expected red until Task 6.)
- [ ] **Step 5: Mutations.**
  - Remove the `pruneRetired` call → the wired test reddens.
  - Remove the alias loop → the alias test reddens.
  - Set E107 `is_foundational: false` → the queryV4 assertions redden.
  - Drop `Glutes` from E107's `primary_muscles` → the `muscleGroupOf` assertion reddens.
- [ ] **Step 6: Diagnose-doc.**
  - Writers: the JSON; `_seedExercises`.
  - Readers: `getByExactName`, `hasExactNameWhere`, `search` (`exercise_repository.dart:86`).
  - By-id sites, which degrade to null and need a stored pre-merge id (cloud audit found 0): `swap_service.dart:467`, `tool_dispatcher.dart:1899`, `ai_coach_provider.dart:1698`, `injury_swap_planner.dart:195`, `swap_exercise_diff.dart:99`, `tool_confirm_card.dart:356`, `template_service.dart:357`, `train_provider.dart:377,411` (the last two fall back to alias-aware `search`).
  - By-name scans that bypass the repo: `workout_write_service.dart:303-317`, `auth_session_bootstrapper.dart:1202`, `logging_type_repair_migrator.dart:125`. A retired name there falls back to data-shape inference. For these 7 movements that gives the same `logging_type` (the weighted ones log weight > 0; V-Ups is bodyweight; the retired stretches are never generated), so the terminal state is `verified_clean`.
  - Progression/PR series under a retired name do not join the kept name. Cloud has 0 logs under those names and §1 says pre-launch accounts are test accounts → `verified_clean`.
  - E107 becomes foundational and stays untagged, so a hip-injured Phase-1 user can now get the Hip Abduction Machine. E225's `hip` tag is not carried over. This matches the founder's 13-B carve-out ("hip machines stay safe", `k13bKeptSafe`); record it.

### Task 3: E172 label typo

**Files:** JSON (via `relabel`); `test/contracts/library_label_typo_behavioral_test.dart` (new); diagnose `…-library-label-typo-<id>.md`.

- [ ] **Step 1: Write the failing test.**
  - `queryV4(movementPattern: 'core', targetMuscle: 'Core', equipmentTier: 'home_dumbbells', exerciseType: 'isolation', exclusions: const {}, capability: null)` contains E172.
  - E172 and E163 (Foam Roll IT Band, the same typo, a flexibility row) carry no 'Lats' in `target_focus`. A general "Lats only on pull patterns" rule is NOT usable: E070 Front Lever, E154 Lat Stretch, E159 Child's Pose and E213 Dead Hang carry Lats correctly.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3:** E172 `target_focus` → `["Core"]`; E163 → `["Legs"]`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Mutation.** Restore "Lats" → both tests redden.
- [ ] **Step 6: Diagnose-doc.**
  - Readers: `exercise_repository.dart:285-303`, `exercise_display.dart:9-25`.
  - Record why the six bodyweight rows are NOT relabelled here (Evidence) and cite OI (c).

### Task 4: Plates — 19 start/end swaps, 2 wrong drawings

**Files:**
- `assets/exercise_plates/`, `scripts/build_exercise_plates.py`;
- JSON: E207 and E179 lose their `demo_slug` and `demo_pair` keys;
- mapping json (-2 → 156);
- `test/fixtures/plate_swap_hashes.json` (new).
- Tests:
  - `test/contracts/exercise_plate_swap_record_test.dart` (new);
  - `exercise_plate_assets_present_test.dart:34-38,56-66` (152 slugs, 138 pairs, 14 singles, 290 SVGs);
  - `exercise_plate_library_data_test.dart` and the schema contract (156 plated, 129 without);
  - `exercise_plate_resolver_test.dart:64-81` (129 artwork-less).

**Slugs:** pike-push-up, cable-curl, hanging-leg-raise, rowing, band-pull-apart, pull-up, cable-kickback, banded-lateral-walk, landmine-press, meadows-row, spider-curl, v-up, jumping-jack, arm-circles, frog-pump, machine-row, donkey-kick, feet-elevated-pike-push-up, prone-y-raise.

- [ ] **Step 1: Record the hashes BEFORE the swap.** Write `plate_swap_hashes.json` = `{slug: {"1": sha256(old -3 file), "3": sha256(old -1 file)}}`.
- [ ] **Step 2: Write the failing test.**
  - `build_exercise_plates.py` declares `SWAP_FRAMES` equal to exactly these 19 slugs.
  - Each slug's committed files match the fixture.
  - E207 and E179 have no `demo_slug` key.
  - `torso-twist-stretch-*.svg` is absent.
- [ ] **Step 3: Run** → FAIL.
- [ ] **Step 4: Implement.**
  - Swap each pair via a temporary name.
  - Apply `SWAP_FRAMES` in the script where -1/-3 are written.
  - Delete the two `torso-twist-stretch` files and edit the JSON keys.
- [ ] **Step 5: Run** this test and every `exercise_plate_*` test → PASS.
- [ ] **Step 6: Mutation.** Un-swap one slug → the test reddens.
- [ ] **Step 7: Visual check and diagnose-doc.**
  - Web (`flutter run -d chrome --dart-define-from-file=.env`): plate sheet for Pike Push Up and Pull Up. Screenshot START/END into the diagnose-doc (`…-plate-frame-order-<id>.md`).
  - Reader: `plate_resolver.dart:57-84`.

### Task 5: Generator verification (no code change)

- [ ] **Step 1:** `dart run test/plan_generator/dump_all_picks.dart <scratchpad>/picks_after.json`, then diff against `picks_before.json`. Acceptance: every changed pick is one of:
  - a retired name replaced by its kept twin;
  - E172 newly picked;
  - a downstream reshuffle caused by those two.

  List the counts per class in the Task 2 diagnose-doc. If any other change appears, stop and investigate.
- [ ] **Step 2: Scorecard gate.** `flutter test test/plan_generator/scorecard_gate_test.dart` against the EXISTING `baseline/baseline_scorecard.json`. Expect PASS: 0 missing / unsafe / equipment violations; fallbacks ≤ the baseline; mean ≥ the floor. Never re-baseline the scorecard JSON to make this pass.
- [ ] **Step 3: Regenerate the readable artifacts only.**
  - `dart run test/plan_generator/generate_baseline.dart`, then `git checkout -- test/plan_generator/baseline/baseline_scorecard.json`. Keep the regenerated `baseline_plans.md`.
  - Say in the commit message that `baseline_plans.md` is newer than the scorecard JSON on purpose, because the scorecard is a ratchet.
  - Say that the dump runs the harness without `avoidNames`, so cross-phase `_preferNovel` effects are outside it. The merges add no new rows to any pool, so they cannot create a new novelty candidate.
  - Regenerate `sample_plans_output.md` with `sample_plans_report.dart`.
- [ ] **Step 4: Run the library-driven generator tests** (`TZ=Asia/Kolkata flutter test <files>`):
  - cross_phase_variety, deload_working_base_stash, equipment_exclusions_activation, equipment_exclusion_filter (`*_behavioral_test`);
  - injury_filter, injury_substitute_preference, l2_no_custom_autoadd (`*_behavioral_test`);
  - plateau_escalation, plateau_rotation (`*_behavioral_test`);
  - `repeat_content_scheduling_test`, `repeat_phase_pinned_selection_behavioral_test`, `wu2_gym_cardio_gate_behavioral_test`;
  - `universal_pool_mirror_test`, `warmup_injury_filter_behavioral_test`, `warmup_finisher_capability_test`, `injury_safe_omission_test`.

  Commit.

### Task 6: Cloud re-seed migration (non-destructive)

- [ ] **Step 1: Extend `exercise_library_cloud_seeded_test.dart`.** The newest seed file must:
  - list `name_aliases` among the INSERT columns;
  - contain, for each of the 7 pairs, one statement `UPDATE exercise_library r SET is_active = false, coaching_cues = k.coaching_cues, common_mistakes = k.common_mistakes FROM exercise_library k WHERE r.id = '<retired uuid>' AND k.id = '<kept uuid>';`, with UUIDs computed in the test from `merged_ids` and the namespace above. Copying the text matters because three retired rows (E165/E167/E168) are shifted rows, and `getFormCues` matches them by exact name with no `is_active` filter;
  - start no line of an UPDATE with `('`, because the tuple-count regex `^\('[0-9a-f]{8}-` would count it;
  - say `Destructive?: no`;
  - say `Rollback strategy:` naming `125_reseed_exercise_library.sql`.

  The tuple count == JSON rows (285) assertion stays. Run → FAIL.
- [ ] **Step 2: Update the script.**
  - `name_aliases` goes in the column list and `DO UPDATE SET`, emitted as `NULL` when absent (`sqlTextArray` returns an empty array, so guard it).
  - After the upsert, emit the per-pair `UPDATE` above.
  - Header: Intent / Destructive no / Rollback 125 / Linked diagnose-doc = Task 1's id.
  - Move `CURRENT_SEED` to the new file name in the same edit, as the script's own header says.
- [ ] **Step 3: Mint and generate.** `sh scripts/mint_migration.sh reseed_exercise_library`, then `node scripts/seed_exercise_library.js <NNN>_reseed_exercise_library.sql`. Run the test → PASS. Leave the .sql UNSTAGED. `check_migration_ledger_paired` and Gate 14 require its ledger entry in the same commit. Gate 14 also reads the working tree, so **no commit may be made between this step and Step 7**. A B-pass fix to code waits until Step 7, or the .sql is moved to the scratchpad while that commit is made.
- [ ] **Step 4: B-pass.** Run `/code-review` over the whole branch together with the generated .sql. Fix the findings, and regenerate the .sql if the script changed.
- [ ] **Step 5: Rehearse (needs the founder's go).** Write a scratchpad copy wrapped in `BEGIN; … ROLLBACK;` and run it with `node .claude/apply_migration_via_api.js dedsavbjuwgarrhphgnl <copy>` (the file is about 150 KB, over the MCP tool's cap). Expect no error. Record the result in the Task 1 diagnose-doc.
- [ ] **Step 6: LIVE APPLY** under the same go: `node .claude/apply_migration_via_api.js dedsavbjuwgarrhphgnl supabase/migrations/<NNN>_reseed_exercise_library.sql`. Verify with `execute_sql`, counting by the library UUIDs (UUID v5 of the E-ids), not by `count(*)`:
  - 285 active and 7 inactive library rows;
  - E013 `coaching_cues` = the Task 1 pinned list;
  - E107 `name_aliases = {Hip Abductor Machine}`;
  - E165 `coaching_cues` = E216's.
- [ ] **Step 7: Ledger and commit.** Add the `backups/applied_migrations.json` entry: `applier: claude-via-node-api`, the hash from `dart run scripts/migration_ledger_hash.dart <NNN>`, and a note. Commit the .sql and the ledger TOGETHER.

### Task 7: Close-out

- [ ] **Step 1: Docs.**
  - SoT `exercise_library_schema`: new keys; `behavioral_test_path:` → prune and alias tests; `seed_prune_wired_test` as `presence_only: true` with its reason.
  - Naming conventions: add `name_aliases` (search + exact-name fallback) and `merged_ids` (seed prune), and update the counts on the `demo_slug` row (`:250`) to "156 of 285 rows, 152 slugs".
  - `docs/architecture/train-detail.md:21`.
  - OI-149 → CLOSED, archived to `closed_issues.md`. The commit that flips the board carries `closes-oi: OI-149`, which `check_closes_oi_cited.dart` requires.
- [ ] **Step 2: Gate 40.** `docs/audit/library-data-repair.closure.yaml`:
  - Tasks 1–4 `closed_in_commit`;
  - OIs (a)(b)(c) `upstream_blocked` with `reopen_when: Batch B`;
  - the by-name-scan and progression items `verified_clean` with evidence.
- [ ] **Step 3: Full gate loop (§4.12.8).**
  - `flutter analyze lib/`;
  - `TZ=Asia/Kolkata flutter test`;
  - `sh scripts/pre-commit.sh` from Bash.
- [ ] **Step 4: Push and PR.**
  - `scripts/safe_push.sh`, then `gh pr create`.
  - `get_status` → `set_monitor` (auto_fix + address_comments).
  - Merge via `sh scripts/safe_pr_merge.sh <pr>` once CI is green.
  - Retire the worktree (§4.13.8) and walk §5.
- [ ] **Step 5: Owed to the founder after the next build:**
  - a repaired exercise shows separate cue bullets;
  - Pike Push Up START/END are right;
  - search "close-grip" finds Close Grip Bench Press;
  - a coach form-cue question returns real cues.
