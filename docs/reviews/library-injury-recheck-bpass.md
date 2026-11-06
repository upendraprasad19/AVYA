---
reviewed_at: 2026-10-24T01:30:00+05:30
staged_against: 07f41517bcccea4fefb3a608ef4013109513c58d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted  # 0 P0, 1 P1 + 5 P2: all six verified by the author before acting, all six accepted; none a false alarm (0% noise)
---

# Code Review (B-pass) — branch `library-injury-recheck`, `git diff origin/main...HEAD` (34 files)

Severity count: P0 0 · P1 1 · P2 5.

Method note. Every number below was computed from the committed files with `node` (read-only; scratch scripts live in the session scratchpad, not the repo) or read from the cited line. I ran three named test files, all green: `test/contracts/injury_recheck_v14_contract_test.dart`, `test/contracts/library_seed_v14_upgrade_behavioral_test.dart`, `test/contracts/warmup_library_injury_mirror_test.dart` (28 passed; TZ=Asia/Kolkata). I did not run the sweep or the full suite (barred), did not run `flutter analyze lib/` (the three test runs compiled `seed_service.dart`, `warmup_cooldown.dart`, `injury_substitutes.dart`, which are the only `lib/` files with code changes), and did not mutate anything (lens 6 mutation was optional; see lens 6 below for what I did instead). `git status --short` is empty apart from this file.

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** `assets/data/exercise_library.json` rows E102 `Incline Push Up` (`["wrist"]`) and E020 `Diamond Push Up` (`["elbow","wrist"]`); decision recorded only at `docs/plans/2026-10-23-library-injury-recheck.md` Ruling 2 (plan line 80 area, "Incline/Diamond Push Up stay as they are").
- **claim:** The batch tags `Push Up` shoulder on the founder's word ("wrist and shoulders"), and the same table tags every other push-up variant for shoulder (E010 Pike, E103 Decline, E233 Deficit, E191 TRX, E262 Elevated Pike, E076 Dand, E212 Wall, E285 Elevated Diamond). The two variants it leaves out are exactly the ones that survive the shoulder filter. For a shoulder-injured user the horizontal_push survivors are, per tier (computed from the library, `not tagged shoulder`, `equipment_tier` contains the tier): bodyweight = `Diamond Push Up` (foundational, Beginner+Intermediate) and `Incline Push Up` (Beginner); home_dumbbells = those two plus `Floor Press`; basic_gym and full_gym add `Chest Squeeze Press`, `Svend Press`, `Machine Chest Press`. Phase 1 (`foundational only`, `queryV4` filter 6, `exercise_repository.dart:404`) therefore hands a shoulder-injured bodyweight or home beginner and intermediate user **Diamond Push Up** as the chest slot, the push-up the author declined to tag, right after Push Up was removed "because it loads the shoulder". That is the same class this batch exists to close (a row that loads the joint, untagged), kept on purpose to avoid 30 extra thin days (plan Ruling 2), not on clinical grounds. The decision is also not recorded anywhere durable: `grep -n "Incline Push\|Diamond Push\|Ruling 2"` over the diagnose doc, the closure ledger and `open_issues.md` returns nothing, and neither id appears in `scripts/data/library_injury_additions_v14.json`. A reader of the diagnose doc or the ledger would conclude the push-up family is covered.
- **verification:** `node -e "const L=require('./assets/data/exercise_library.json');for(const t of ['bodyweight','home_dumbbells'])console.log(t,L.filter(r=>r.movement_pattern.includes('horizontal_push')&&r.equipment_tier.includes(t)&&!r.injury_contraindications.includes('shoulder')).map(r=>r.name+(r.is_foundational?'*':'')).join(' | '))"` prints `Diamond Push Up* | Incline Push Up` for bodyweight. Then `grep -c "E102\|E020" scripts/data/library_injury_additions_v14.json` returns 0.
- **suggested-fix:** Founder call, asked as one line: tag E102 and E020 shoulder (the cost the plan measured is +30 thin days, which OI-401 owns), or record in the diagnose doc, the closure ledger and a pinned test that the two are shoulder-safe by decision, with the reason. Either way add a contract assertion naming them, so the decision cannot drift silently. If the answer is "tag", the shoulder substitute list needs no change (neither is in it).
- **status:** accepted - fixed in the batch: Diamond Push Up and Incline Push Up tagged shoulder (plan Ruling 2 reversed, execution ruling E7); the new test pins all 11 push-up-named rows; mutation reddens 5 tests. I verified the claim first (the rows were shoulder-free while E285 and four siblings were tagged).

## Finding 2 — P2 — missing_input (sweep non-vacuity)

- **file:line:** `test/plan_generator/injury_floor_sweep_test.dart:261-287` (repeat block), also `:203-259`.
- **claim:** Can any gate pass if the generator returns nothing? Yes. `scan` increments `t.runs` before looking at any day (`:135`), and the only count assertion is `expect(t.runs, N)` (`:226`, `:255`, `:285`). Nothing asserts that a day or a pick was scanned (`t.days`, a pick counter). The `repeat` test has **no empty-day gate at all** (it calls only `expectSafe`, `:286`), so a run in which every day comes back with zero exercises (an exercise box that opened empty, a flag default that makes every slot omit) gives `unsafe 0, unresolved 0` and passes. `singles` would catch that case through `empty == 0` and `pairs` through `<= 4`, but only if those two tests run in the same invocation; each test stands alone (`--plain-name`). Today it is latent: I confirmed the tags and the generator are consistent through the contract test (real `generateV4`, with positive controls), not through this file.
- **verification:** `grep -n "expect(" test/plan_generator/injury_floor_sweep_test.dart` lists the gates; none reads `t.days` or a pick count.
- **suggested-fix:** Add `expect(t.days, greaterThan(0))` and a `picks` counter with a lower bound to `expectSafe`, and give `repeat` an `empty` ceiling (0 today, per the diagnose table).
- **status:** accepted - fixed in the batch: every block asserts days >= runs x 6 and picks > 0, and the repeat block asserts 0 empty days.

## Finding 3 — P2 — asserted_fixture_value (sweep input width)

- **file:line:** `test/plan_generator/injury_floor_sweep_test.dart:210` and `:240` (`const [3, 5]`), `:268` (`const d = 4`).
- **claim:** Singles and pairs sweep only 3- and 5-day plans; repeat sweeps only 4-day. 6-day plans (valid: `daysPerWeek` is 3|4|5|6) are never swept, and 4-day plans are swept only for the repeat path. A 6-day plan uses variant A only and, for beginners, targets 4 exercises per day (`plan_engine/CLAUDE.md` count table), so a two-slot loss is a thin day there. The diagnose doc's tables ("singles 44 thin / 11 one-exercise / 0 empty", "pairs ... 4 empty"), the OI-401 "Measured" paragraph and its done-when ("a behavioural sweep then shows 0 one-exercise days") are therefore measured over 2 of the 4 day counts. The golden covers 4-day only and has 24 `injury|` keys (knee, lower_back, shoulder only), so elbow, hip, wrist, neck, ankle and hamstring have no golden pin at all. `week 3/4` are not a gap: `periodization_engine.dart:82` shows weeks 3 and 4 reuse variants A and B.
- **verification:** `grep -n "const \[3, 5\]\|const d = 4" test/plan_generator/injury_floor_sweep_test.dart`; `node -e "const g=require('./test/fixtures/generator_golden_hashes.json');console.log([...new Set(Object.keys(g).filter(k=>k.startsWith('injury|')).map(k=>k.split('|')[1]))])"` prints only `knee, lower_back, shoulder`.
- **suggested-fix:** Add `4, 6` to the days list (or a separate 6-day block with its own timeout) before OI-401 uses the sweep as its done-when, and say in the diagnose doc that the figures cover 3- and 5-day plans.
- **status:** accepted - fixed in the batch: the sweep is five blocks over 3, 4, 5 and 6 day plans with BEFORE measured on the v13 library; the 4/6-day blocks found 1 and 6 empty days (execution ruling E8).

## Finding 4 — P2 — asserted_fixture_value (baseline refresh launders drift)

- **file:line:** `test/plan_generator/baseline/baseline_scorecard.json` (whole file), `baseline_plans.md`; claim at `docs/diagnoses/2026-10-23-library-injury-recheck-d30de7.md:249-253` and `docs/audit/library-injury-recheck.closure.yaml` item T7.
- **claim:** The diagnose doc says the refresh "clears" a stale baseline and treats the 165 stale personas as harmless drift. Measured against `origin/main`'s committed file: 177 personas changed, 164 of them **uninjured** (`inj:none`), 154 strictly lower, none higher (e.g. `build_muscle | bodyweight | 3d | beginner | p6 | inj:none` volume 68.2 to 65.0, overall 83.6 to 83.1; by phase p6 78, p1 38, p2 38). The injury tags cannot change an uninjured persona (every reader returns early on an empty injury list), so these are pre-existing score declines from earlier batches that the no-regression gate never saw. Computed from the personas arrays: mean overall 86.250 to 86.123 (-0.127), of which uninjured drift is -0.071 and the v14 injured personas -0.056. The gate floor is `baseline - 0.05` on the one-decimal aggregate string (`scorecard_gate_test.dart:151-154`), so the floor drops from 86.15 to 86.05 and `total_fallback_picks` from 2862 to 2866; about half of the lost headroom is not this batch's cost. No OI or ledger item records "uninjured volume fell on 164 personas, cause unverified"; the cause list in the diagnose doc ("7 duplicate rows retired, labels fixed, 136 coaching texts moved") is asserted, not shown.
- **verification:** `node -e "const {execSync}=require('child_process');const o=JSON.parse(execSync('git show origin/main:test/plan_generator/baseline/baseline_scorecard.json',{maxBuffer:1e8,env:{...process.env,MSYS_NO_PATHCONV:'1'}}));const n=require('./test/plan_generator/baseline/baseline_scorecard.json');const m=new Map(o.personas.map(p=>[p.id,p]));console.log(n.personas.filter(p=>p.id.endsWith('inj:none')&&p.overall<m.get(p.id).overall-0.001).length)"` prints 154.
- **suggested-fix:** Mint an OI for the uninjured volume decline (find which batch moved it), and in the diagnose doc split the aggregate move into "v14: -0.056" and "pre-existing: -0.071". Keep the refresh if the founder agrees, but not as an unrecorded side effect.
- **status:** accepted - confirmed (164 uninjured personas moved) and attributed to commit `ad896b42` by swapping only the library file; filed as OI-404 with the measured effect and a done-when.

## Finding 5 — P2 — writer_reader_drift (a consumer the change did not account for)

- **file:line:** `lib/features/ai_coach/services/injury_swap_planner.dart:136-192` and `:211-233`.
- **claim:** The coach's `modifyWorkoutForInjury` swap planner decides "loads the injured part" by substring match on muscle names (`_affectedMusclesForBodyPart`, `_exerciseHitsMuscles`) and picks the FIRST same-category library row that does not hit those muscles. It never reads `injury_contraindications`. The plan, the diagnose doc's reader list ("Not a reader" names only the picker), the SoT entry `exercise_injury_tags` and the ledger item `PICKER-UNFILTERED` (whose evidence is a grep for the tag string) do not mention it. Replaying its selection rule over the library in `Hive` key order, the first substitute for some categories is a row tagged for the very injury: lower_back plus a `legs` exercise returns `Front Squat` (`["hip","knee","lower_back","wrist"]`, tagged before and after v14); knee plus `cardio` returns `Running (Treadmill)`; after v14 shoulder and wrist plus a `full_body` exercise return `Surya Namaskar` (`["lower_back","shoulder","wrist"]`, untagged before v14, so v14 turned a silently-served row into a known-unsafe one). This is pre-existing and outside the diff, but it is the explicit "I am injured" feature, and the batch's stated goal is that an injured user is not handed such rows.
- **verification:** `grep -n "injury_contraindications" lib/features/ai_coach/services/injury_swap_planner.dart` returns nothing; replay: the scratch script `swap.js` in the session scratchpad (library order, the two helper rules copied from the file) prints the tagged first-substitutes above.
- **suggested-fix:** Add `isContraindicated(libEntry, [bodyPart])` to `_findSubstitute` (reuse `ExerciseSelector._isContraindicated` semantics, canonicalising `bodyPart` through `InjuryVocab`), or file an OI and add the planner to the SoT readers as "known non-reader". The `upper_back`, `chest`, `quad`, `calf` body parts are not canonical tokens and need a decision.
- **status:** accepted - confirmed by reading `_findSubstitute` and a grep over lib/; pre-existing and outside this diff, filed as OI-403. The reviewer's Front Squat and Surya Namaskar replay is recorded there as unverified.

## Finding 6 — P2 — blast_radius_mismatch

- **file:line:** `docs/blast_radius.yaml:486` (`assets/**` is `feature`), `:483` (`scripts/**` feature), `:484` (`test/**` feature).
- **claim:** This branch is `platform` only because it also edits `lib/shared/repositories/plan_engine/**` (comment and one map entry). The file that actually decides what an injured user receives, `assets/data/exercise_library.json`, and its table `scripts/data/library_injury_additions_v14.json` classify as `feature`. The plan header calls the change "platform (plan-engine data)", which the registry does not say. A later commit that only removes or edits tags in the library JSON (the same class that took five batches to stabilise) would classify `feature`: no ×2 plan review, no B-pass, no plan-review record. The seed constant at `lib/core/services/seed_service.dart` falls under `lib/core/services/**` = `account`.
- **verification:** `grep -n "assets" docs/blast_radius.yaml` returns only line 486; `grep -n "exercise_library" docs/blast_radius.yaml` returns nothing.
- **suggested-fix:** Add explicit `platform` globs for `assets/data/exercise_library.json` and `scripts/data/library_injury_additions_*.json` above the catch-alls (first match wins), with a registry-coverage test line, or state in the plan that the data file relies on the plan_engine edit to reach `platform`.
- **status:** accepted - fixed in the batch: `docs/blast_radius.yaml` classifies the library JSON and the injury-tag tables as `account` (not `platform`, which also requires a feature flag); `blast_radius_library_data_account_test.dart` pins it (execution ruling E9).

## Founder triage notes
<filled in by founder during triage>

---

# What each lens checked and found clean

## 1. writer_reader_drift
Command: `grep -rn "injury_contraindications\|_moveInjuries\|injuryExclusions" lib supabase scripts test --include=*.dart --include=*.ts --include=*.js` plus `grep -rn "contraindicat|InjurySubstitutes|InjuryVocab" lib`.
- Readers in `lib/`: `exercise_repository.dart:411-421` (queryV4 filter 8, exact lowercase `==`), `exercise_selector.dart:470-484` (V3), `:1456-1468` (`_isContraindicated`, attempt 5 and pins and the core-list hard filter), `warmup_cooldown.dart:28-66` (own table), `injury_substitutes.dart` (re-rank). All consistent with the new data; none changed semantics. The registry line ranges (`411-420`, `:416`, `470-482`, `1456-1468`, `seed_service.dart:116`) all match the files.
- Not readers: `supabase/**` (zero hits for the tag field; the cloud `exercise_library` has no such column, migration 162 header lines 12-19 say so), `exercise_picker_sheet` (founder decision). One consumer not accounted for: Finding 5.
- Moved-prose sub-check: `plan-engine-detail.md` and the registry paragraph relocate or supersede 13-B carve-out text in place (no move to a file a gate does not list).
- The 27-key warm-up mirror: `node` over `_moveInjuries` vs the library: 27 of 27 equal as sets, 0 duplicate or case-colliding names (`mirror.js`); the all-27 test also passed on a real run.
- Existing installs, by reading `seed_service.dart:141-208, 237-255`: a device with `seeded_exercises` true and `exercise_library_version` 13 gets `needExerciseUpgrade` true, `_seedExercises` runs `putAll` keyed by id, prunes only ids in `merged_ids`, then stamps 14. Library rows are seed-only (user edits live in `customBox`; custom and community rows have UUID keys and are never touched by `putAll`). The only other `exerciseBox` writer is `sync_community.dart:523-529`, which `put`s only when the key is absent. So nothing overwrites the box afterwards. The behavioural test drives the real `seedIfNeeded` and passes. Caveat that already exists and is unchanged: a `_seedExercises` exception leaves the flags and the old tags in place until the next launch (telemetry only).
- Uninjured users: lib changes are the seed constant, a comment, one `_moveInjuries` value, three `_preferred` edits and one key removal. `preferredFor([])` is empty, `_moveIsContra` returns false on an empty set, `_isContraindicated` returns false on an empty list, queryV4 `injuryLower` is null. Data: `node` proves 0 non-tag keys changed over 285 rows (`diff1.js`), and the golden fixture's 975 non-`injury|` keys are unchanged (`fix.js`: 18 changed, 18 start with `injury|`). No uninjured path found.

## 2. function_exception_swallow
Command: `git diff origin/main...HEAD -U0 | grep -cE "unawaited\(|\.functions\.invoke\(|\.invoke\("` returned 0. No Edge Function call is added or changed.

## 3. blast_radius_mismatch
Command: read `docs/blast_radius.yaml` lines 104-127, 483-486, 566-570. Finding 6. Otherwise the commit trailers (`Blast-radius: platform` on the fix and docs commits) match the plan_engine edits; `closes-diagnose: d30de7` is present on the `fix(` commit.

## 4. secrets_in_tree
Command: `git diff origin/main...HEAD | grep -nE "^\+" | grep -nE "sk-[A-Za-z0-9]{10,}|rzp_(live|test)_|AKIA[0-9A-Z]{12,}|-----BEGIN|eyJ[A-Za-z0-9_-]{20,}|service_role"` returned 0 hits.

## 5. unawaited_no_error_sink
Same grep: 0 `unawaited(` added or changed. No new async call site.

## 6. guard_without_its_mirror
Mirrors checked, not accepted from the diff's own tests:
- Library tags vs `_moveInjuries`: mirrored and pinned for all 27 keys; a case-typo in a map key would pass the mirror test (it lowercases) but is caught by the existing drift guard `warmup_injury_filter_behavioral_test.dart:217-224` (exact-case set difference) and by the sweep's `unsafeWarm`.
- Library tags vs `InjurySubstitutes._preferred`: `node` replay of every listed name (`mirror.js`): all 19 entries exist, none tagged for its own key (Chin Up elbow, Tricep Pushdown elbow, Cable Curl elbow, Leg Curl hamstring, Landmine Press shoulder, Hip Thrust hip, Leg Press knee+lower_back are tagged for OTHER injuries only, which is correct for a single-injury user; multi-injury users are protected by the filter that runs first). The elbow key removal leaves `preferredFor(['elbow'])` empty (re-rank no-op, no crash).
- "Chin Up is elbow" mirror: tested both ways in the contract test (shoulder keeps Chin Up and drops Lat Pulldown; elbow the reverse). Passed.
- Mirror of "tags added": removal. The applier refuses removal (`add_library_injury_tags_v14.js:60`), 0 tags removed proven by `diff1.js`. Mirror of "table row already satisfied": the script re-sorts a row even when it gains nothing (`:65`), harmless here (no such row; `orderChanged` is empty).
- Mirror of "the safe pool stays untagged": the contract test asserts both directions (33 named rows empty, nothing else empty). Finding 1 is the mirror the diff's tests share a blind spot on (they assert Push Up is tagged and never ask what survives next to it).
- Sweep: Finding 2 (non-vacuity) and Finding 3 (input width).
- Mutation: none run (optional, and Finding 1/2/3 are visible by reading). No file I may mutate was touched.

## 7. missing_input
- `scripts/data/library_injury_additions_v14.json` exists, has `_meta`/`additions`/`reasons`; 102 ids, 146 tokens, every id in the library, every token canonical (`diff1.js`; the contract test also passed).
- The applier reproduces the committed library byte for byte from `origin/main`'s library (`repro.js`: `reproduces committed true`, 522998 bytes each; second application is idempotent; both files LF-only, `.gitattributes` `eol=lf`). The old library round-trips through `format()`. `[...new Set([...old, ...tokens])].sort()` re-sorts only the table rows; the 16 unsorted lists in the library (E229, E248, E253 ...) are untouched rows, as E4 says.
- `docs/audit/library-injury-recheck.closure.yaml` names `docs/plan-reviews/library-injury-recheck.md`, which is not in the tree yet (`git ls-files docs/plan-reviews | grep -i injury` shows two other branches' records). The plan lands it in its own later commit (Step 7); the merge gate requires it by then. Informational, not a finding.
- `test/fixtures/exercise_library_v12_row_hashes.json`: exactly 102 changed entries and they equal the table's id set (`fix2.js`). Golden: 18 of 999 keys, all `injury|`, none other.
- `docs/reference/exercise-library.md`: the plan asked to update it "if it describes the tags"; I did not find a stale tag count in the diff's docs set.

## 8. asserted_fixture_value
Every LITERAL about real data recomputed from `assets/data/exercise_library.json`:
- 285 rows; 102 changed; 146 tokens added; 0 removed; per-token counts shoulder 31, lower_back 26, elbow 22, wrist 19, hip 18, knee 12, hamstring 7, ankle 7, neck 4: all equal the diagnose doc.
- 33 untagged rows equal `kV14SafePool` exactly (name list printed and compared); `252 of 285` in `injury_vocab.dart:5` is right.
- 30 rows in the elbow_flexion/elbow_extension patterns, all tagged elbow; the founder-call names: Burpee `["ankle","knee","shoulder","wrist"]`, Mountain Climber `["shoulder","wrist"]`, Push Up `["shoulder","wrist"]`, Chin Up `["elbow"]`, Hollow Body Hold `["lower_back"]`, both hip machines `["hip"]`, Decline Sit Up and Reverse Hyper `["lower_back"]` (unchanged), Crunches/Bicycle Crunch `["lower_back","neck"]`, V-Up `["hip","lower_back"]`, Russian Twist `["lower_back"]`, Deficit Reverse Lunge `["hip","knee"]` (was `["knee"]`), Leg Press `["knee","lower_back"]`.
- Warm-up mirror 27 of 27; `E061 Running (Treadmill)` `["ankle","hip","knee"]` matches the repointed v13 test.
- Substitute-list claims: "5 of the 9 tokens" (shoulder, knee, lower_back, wrist, hip) correct.
- Unrecomputable without the barred sweep or generator runs: the sweep tables, "224 of 864 personas", the scorecard "12 injured personas moved" figure (I verified the committed diff instead: 13 injured personas changed, all `full_gym | 4d | p1`, plus the uninjured drift of Finding 4), and the mutation counts. Treat those as author-attested.
- Suppression tests with a paired positive control: all eight generator personas and the elbow test carry a positive control and passed in my run; the queryV4 block does too.
- Remaining docs claims spot-checked: SoT `exercise_injury_tags` readers/writers (lines 11435-11496), `plan-engine-detail.md` item 8 and the "5 of 9" wording, `bug-classes.md` 2.117 (no duplicate heading introduced; the 2.36-2.41 and 2.53-2.55 duplicates are older and outside this diff).

---

```yaml
diagnose_stanza:
  symptom: Rows the v14 table leaves untagged next to rows it tags let a shoulder-injured user receive Diamond Push Up and Incline Push Up; the coach injury-swap planner ignores the tags.
  concept: exercise_injury_tags
  writers:
    - { file: assets/data/exercise_library.json, method: injury_contraindications (E102, E020 not in table), line: 1 }
  readers:
    - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: queryV4 injury filter, line: 413 }
    - { file: lib/features/ai_coach/services/injury_swap_planner.dart, method_or_widget: _findSubstitute (does not read the tags), line: 211 }
  hive_key_prefix: exerciseBox
  hive_key_formula: "exerciseBox[<id>]['injury_contraindications']"
  sync_methods: []
  restore_methods: []
  cloud_table: null
  cloud_columns: []
  contract_test_path: "must add: assertion naming E102 and E020 in test/contracts/injury_recheck_v14_contract_test.dart"
  ist_handling: []
  provider_invalidations: []
  telemetry_op_types: { success: [], failure: [] }
  cross_account_guard: n/a
  forbidden_patterns_checked:
    - { pattern: "unawaited\\(|\\.invoke\\(", absent: true }
    - { pattern: "sk-|rzp_live_|AKIA|-----BEGIN", absent: true }
  proposed_fix: Founder call on E102 and E020; add non-vacuity and day-count width to the sweep; tag-aware substitute in the coach swap planner; explicit platform globs for the library data file.
  regression_test_planned: [test/contracts/injury_recheck_v14_contract_test.dart, test/plan_generator/injury_floor_sweep_test.dart]
```
