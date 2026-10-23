# Injury re-check (seed v14) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revision:** r3 (2026-10-23), CONVERGED.
- **Round 1:** `not_converged`, 0 P0 / 4 P1 / 7 P2 / 3 mechanical (session scratchpad `injury/review_1.md`).
- r2 resolves every finding (resolution map at the end) and re-ran the probe over the WIDEST library-touching test set (`injury/probe2_tests.txt`).
- **Round 2:** `converged`, 0 P0 / 0 P1 / 9 P2 / 5 mechanical (`injury/review_2.md`). r3 applies every P2 and mechanical fix (resolution map at the end).

**Approval (founder, 2026-10-23):**
- The founder rejected the 13-B "kept safe for variety" principle: "We cannot give a bicycle crunch or a V-up or a Russian twist to a injured user."
- The founder approved the per-row table (session scratchpad `injury/injury_table.md`) with three edits:
  - Lat Pulldown +shoulder.
  - Chin Up = elbow only ("chinup is elbow").
  - Push Up = wrist + shoulder.
- My Incline/Diamond Push Up extension is dropped. Measured cost: 30 extra thin days.
- Ships live with no flag, the same call the founder made for the five v13 tags (2026-10-22, "Apply all 5 live").
- Execution mode: **inline** (§4.12.7), branch `library-injury-recheck`, base `d93f7e9d`.
- The thin-day top-up (founder option (b), 2026-10-23) is the NEXT plan. It is tracked as its own OI, minted with this plan (OI-401). It is not part of this plan.
- **Not yet approved:** Ruling 3's three added shoulder substitutes are this plan's own call. The founder's yes is asked at the converged-plan gate.
- The exercise picker stays unfiltered (founder 2026-10-23, Ruling 4).

**Goal:** 102 library rows gain 146 injury tags (additions only), so the always-on injury filter stops serving those moves to users with that injury. The warm-up list and the curated substitutes agree with the new tags.

**Out of scope:** the cardio finisher (`WorkoutDay.finisher`, `cardio_finisher.dart`). It takes no injuries today and no screen shows it (OI-396). It can still hold Burpee or Mountain Climber for a shoulder- or wrist-injured `lose_fat` user. OI-396 owns the fix; the closure ledger records it.

**Architecture:**
- A committed table `scripts/data/library_injury_additions_v14.json` (id → tokens, plus a reason per row) is unioned into `injury_contraindications` by a new script, `scripts/add_library_injury_tags_v14.js`.
  - Same formatter and round-trip guard as `scripts/add_library_core_fields_v13.js:46-70`.
  - Union, sorted, canonical tokens only, never removing a tag.
- The seed version goes 13 → 14, so existing installs re-seed.
- No code path changes, only data plus two data-shaped code tables (`_moveInjuries`, `InjurySubstitutes._preferred`).

**Tech Stack:** Flutter/Dart, Hive (untyped row maps), `flutter_test`, node (data script).

**Spec:** `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §4.1 (pool: "no injury contraindication"). The per-row decisions are the founder-approved table. Evidence, in the session scratchpad `injury/`:
- `proposal.json`: the final table.
- `injury_table.md`: the founder review document.
- `sweep_before2.txt`, `sweep_noext.txt`: measurements.
- `probe_tests.txt`: probe 1 (data only, 21 files).
- `probe2_tests.txt`: probe 2 (full change, every test under `test/contracts`, `test/plan_generator`, `test/profile` and `test/ai_coach`; the command is its first line).
- `review_1.md`: round-1 review.

**Blast radius:** `platform` (plan-engine data). Full ×2 plan review, B-pass before merge. Not ship-dark.

## Global Constraints

- **Additions only.** No row loses an injury token. No other key of any row changes, proven by `exercise_library_frozen_reference_test.dart`, which is re-recorded for exactly the 102 ids.
- **Canonical tokens only:** `InjuryVocab.canonicalTokens` (`lib/core/utils/injury_vocab.dart`), the 9 tokens ankle, elbow, hamstring, hip, knee, lower_back, neck, shoulder, wrist.
- **Founder calls, pinned literally by tests:**
  - Kettlebell Goblet Press ∋ shoulder.
  - Lat Pulldown ∋ shoulder.
  - Chin Up ∋ elbow and ∌ shoulder.
  - Push Up = {shoulder, wrist}.
  - Hollow Body Hold ∋ lower_back.
  - Hip Abduction Machine and Hip Adduction Machine ∋ hip.
  - Every elbow_flexion and elbow_extension row ∋ elbow.
  - Burpee and Mountain Climber ∋ shoulder and ∋ wrist.
  - Decline Sit Up and Reverse Hyper keep lower_back (CARVEOUT-E173-E127 is closed as "keep").
- **Stay untagged (the new safe pool, 33 rows):** listed verbatim in Task 1. Pinned empty by the new contract test, which replaces `k13bKeptSafe`.
- **Warm-up mirror:** `WarmupCooldownSelector._moveInjuries` equals the library tags for every warm-up/cool-down name that is also a library row (27 names, all present). Today the test checks 3.
- **Curated substitutes:** every name in `InjurySubstitutes._preferred[token]` is a library row NOT tagged `token`.
- **No cloud change:** `injury_contraindications` is not a cloud column (migration 074 excludes it, per the 13-B diagnose `f4c1e8`).
- **Process:**
  - Tests run with `TZ=Asia/Kolkata`.
  - Commits only via `scripts/safe_commit.sh "<msg>"`; one push for the batch; no APK.
  - Commands handed to the founder use PowerShell; commands the agent runs use Bash.

## Review Focus

1. **Two injuries at once** (e.g. shoulder + wrist at home). The filter is a union, so the pool shrinks faster. Covered by the sweep's pair block (Task 1 Step 3): all 15 pairs of knee, shoulder, lower_back, wrist, elbow and hip (the six injuries with the most new tags), on the OFF path, measured before and after. unsafe == 0 is gated; an empty-day rise stops the batch.
2. **Warm-up and cool-down for shoulder users.** Push Up leaves the shoulder warm-up. The floor holds by construction: a dynamic move survives in every day type and tier (`warmup_cooldown.dart:114-139`), the `Deep Breathing` floor is at `:261-263`, and `Slow Walking` at `:270` (round-1 reviewer, verified). Pinned by `warmup_injury_filter_behavioral_test.dart`'s floor test (`:196-209`, unchanged, green in probe 2). Task 3 Step 4b repoints the U3 shoulder test in the same file.
3. **A stale Hive box at v13.** Expected: the seed bump re-seeds, and the new tags reach the filter. Covered by a behavioural seed test (Task 3 Step 9). Plans already stored on a device are NOT rewritten by a re-seed; the injured tester's next generation picks the new tags up. Pre-launch, every account is a testing account (root CLAUDE.md §1), so this is not a real-user risk. The diagnose doc records it.
4. **Custom and community rows** carry no injury tags. Expected: unchanged, never filtered (no change in this plan).
5. **The ON path** (`enable_core_list_pool`, dark) uses the same predicate. Expected: the B1 gate's hard zeros stay 0; the report is regenerated.

## Rulings

1. **No flag.** The founder's live call for safety tags (2026-10-22, repeated today) is treated as covering this batch. Safety-direction data only removes options for injured users. Cost if wrong: one revert of the data table plus a seed bump.
2. **Incline/Diamond Push Up stay as they are** (wrist; elbow+wrist). The founder named Push Up only; the extension was mine, and it measured +30 thin days.
3. **Curated substitutes: dead names out, three shoulder-safe names in.**
   - Every removed name is now tagged for its injury. The filter already drops it before the re-rank, so removing it changes no output.
   - Measured with the v14 tags (session probe, 864 phase-1 personas: 6 injuries × 4 tiers × 4 goals × 3 levels × 3/4/5 days, re-rank ON vs OFF): the shoulder list changes **0** plans. Its live members (Machine Chest Press, Face Pull, Band Pull Apart, Chin Up, Tricep Pushdown (Cable)) never move a pick. Other injuries still do: lower_back 72, wrist 68, knee 22, hip 2. The probe's output was printed, not saved, so these figures are UNVERIFIED by artifact. Task 3 Step 5 re-measures shoulder after the change and saves the output.
   - A live feature that does nothing is a defect this change creates. So the shoulder list gains Floor Press, Chest Squeeze Press (horizontal_push) and Machine High Row (vertical_pull). All three are in `kV14SafePool`, so they are untagged, present, and correct for their patterns.
   - This changes shoulder users' picks toward those rows. The shoulder golden keys change in this batch anyway.
   - Cost if wrong: a shoulder user's chest slot prefers Floor Press over Machine Chest Press.
   - **Needs the founder's yes** at the converged-plan gate: a preference change, not a safety tag.
   - The `elbow` key is deleted: both of its names are now elbow-tagged, and every elbow-pattern row is too. `preferredFor` skips a missing key (`injury_substitutes.dart:80`). The count changes in three places: `injury_substitutes.dart:18` ("6 of the 9"), `plan-engine-detail.md:191` and `sot_registry.yaml:10637` (both "6 of 9"; grep `6 of (the )?9`). Each becomes "covers 5 of the 9 … ankle/elbow/hamstring/neck have no curated list".
4. **The exercise picker in a workout lists every exercise, injury or not.** `exercise_picker_sheet.dart:32` calls `ExerciseRepository.instance.getAll()` with no injury filter. Founder decision 2026-10-23: "user should be able select, add, swap all the exercises. so leave as it is." The closure ledger records it as `verified_clean` with that quote. This plan does not change it.
5. **The sweep test is committed** as `test/plan_generator/injury_floor_sweep_test.dart`. It asserts unsafe main picks == 0, unsafe warm-up/cool-down picks == 0, unresolved names == 0 and empty days == 0, and prints the thin-day report. Thin days are OI-401's job, so they are reported, not gated, here.
   - The committed test reads only `assets/data/exercise_library.json`. The `INJURY_SWEEP_LIBRARY` override used for the measurements is removed, so `spawn_env_manifest_test.dart` stays green (round-1 F2, measured red with it).
   - "Before" comes from Task 1 Step 4 (run on today's data); "after" from Task 2 Step 6.
6. **Repeat phases are measured, not gated.** A pin that is now contraindicated is dropped with no refill (`exercise_selector.dart:994`). The sweep's repeat block counts days left under 3 after the drop. The number goes in the diagnose doc and to OI-401, whose top-up must cover the repeat path too.

## File structure

- New: `scripts/data/library_injury_additions_v14.json` (the table: `_meta`, `additions`, `reasons`).
- New: `scripts/add_library_injury_tags_v14.js` (applier: `--check` round-trip only; refuses unknown ids and non-canonical tokens).
- Modify: `assets/data/exercise_library.json` (102 rows, `injury_contraindications` only).
- Modify: `lib/core/services/seed_service.dart:105-110` (v14 comment + `_exerciseLibraryVersion = 14`).
- Modify: `lib/shared/repositories/plan_engine/warmup_cooldown.dart` (`_moveInjuries` Push Up; the comment that names this batch as owed).
- Modify: `lib/shared/repositories/plan_engine/injury_substitutes.dart` (dead names out; comment counts).
- New: `test/contracts/injury_recheck_v14_contract_test.dart`.
- New: `test/contracts/library_seed_v14_upgrade_behavioral_test.dart` (Task 3 Step 9).
- Commit: `test/plan_generator/injury_floor_sweep_test.dart` (already drafted in the worktree; Task 1 Step 3 finishes it).
- Repoint: the 8 files probe 2 reddened (Task 3 lists them).
- Re-record: `test/fixtures/exercise_library_v12_row_hashes.json`, `test/fixtures/generator_golden_hashes.json`, `test/plan_generator/baseline/baseline_scorecard.json`, `test/plan_generator/baseline/baseline_plans.md`, `test/plan_generator/core_list_pool_report.md`.
- New helper: `test/helpers/injury_safe_pool.dart` (`kV14SafePool`), imported by both the new contract test and the 13-B test (round-2 M12).
- Also committed (Task 4 Step 4b): `docs/audit/open_issues.md` (OI-400, OI-401), `docs/superpowers/skills-log.md`, this plan.
- Docs: the diagnose doc, `docs/sot_registry.yaml` (`exercise_injury_tags`), `docs/reference/exercise-library.md` if it describes the tags, `docs/audit/library-injury-recheck.closure.yaml`.

---

### Task 1: Failing tests first

**Files:** new `test/contracts/injury_recheck_v14_contract_test.dart`; `test/plan_generator/injury_floor_sweep_test.dart` (turn its report into assertions).

**Interfaces:** consumes nothing earlier. Produces `kV14SafePool` (the 33 names) in `test/helpers/injury_safe_pool.dart`, imported by Task 3's 13-B test repoint. No `_test.dart` imports another.

- [ ] **Step 1: Data contract (A).** Read `assets/data/exercise_library.json`.
  - Assert the founder calls from Global Constraints, each as a literal expectation on a name.
  - Assert every row whose `movement_pattern` contains `elbow_flexion` or `elbow_extension` contains `elbow`.
  - Assert every name in `kV14SafePool` exists and has an empty list. The list, verbatim: Machine Chest Press, Floor Press, Chest Squeeze Press, Svend Press, Face Pull, Band Pull Apart, Reverse Fly, Bodyweight Rear Delt Raise, Dumbbell Row, Seated Cable Row, Chest Supported Row, Seal Row, Inverted Row, TRX Row, Machine High Row, Machine Low Row, Glute Bridge, Lateral Band Walk, Plank, Dead Bug, Pallof Press, Cycling (Stationary), Assault Bike, Sled Push, Prowler Push, Slow Walking, Arm Circles, Deep Breathing, Cat-Cow Stretch, Thoracic Extension (Foam Roller), Thoracic Rotation, Foam Roll IT Band, Foam Roll Upper Back.
  - Assert no row outside `kV14SafePool` has an empty list (the 252 other rows are all tagged).
  - Assert, for every id in `scripts/data/library_injury_additions_v14.json`, that the library list ⊇ the table's tokens and is sorted.
- [ ] **Step 2: Behavioural (B).** Real `PlanGenerator.instance.generateV4`, flag OFF, one test per founder call:
  - shoulder: no Push Up / Kettlebell Goblet Press / Lat Pulldown;
  - lower_back: no Crunches / Bicycle Crunch / V-Up / Russian Twist / Hollow Body Hold;
  - elbow: no elbow_flexion / elbow_extension row;
  - hip: no Hip Abduction / Adduction Machine;
  - over the golden grid tiers.
  - Each test has a positive control: the same persona uninjured contains at least one of the named moves, so the absence is not vacuous. Pick the persona by searching the grid first; record it in the test.
- [ ] **Step 3: Sweep.** In `injury_floor_sweep_test.dart`:
  - Remove the `INJURY_SWEEP_LIBRARY` override (Ruling 5).
  - Count `unresolvedMain` and `unresolvedWarm`: picks whose lowercased name matches no library row. Today such a pick is skipped silently.
  - Add three blocks, each counting unsafe main / unsafe warm-cool / unresolved / empty / thin:
    - **singles:** the existing block.
    - **pairs:** all 15 pairs of {knee, shoulder, lower_back, wrist, elbow, hip} × 4 tiers × 4 goals × 3 levels × {3, 5} days × phase 1 (1,440 runs). Round 2 chose the set by tokens added per injury: shoulder 31, lower_back 26, elbow 22, wrist 19, hip 18, knee 12.
    - **repeat:** 9 injuries × 4 tiers × 4 goals × 3 levels × 4 days, phase 1 → 2 (432 personas, 864 generations).
      - Generate phase 1 uninjured.
      - Build `pinnedExercisesByDay` (`Map<int, ({List<String> a, List<String> b})>`, `plan_generator.dart:99`) from its variant-A and variant-B names per day index, with `namesByDay` (`test/helpers/generator_golden_personas.dart`).
      - Generate phase 2 with the injury and those pins.
      - Count days under 3 exercises. Report only (Ruling 6).
  - Singles, pairs and repeat are three separate `test()` calls, each with its own timeout. Record each block's standalone wall time in the diagnose doc. Keep the whole file under about 5 minutes standalone; singles measured 2:01 alone. If over, drop phase 3 from singles and say so.
  - Assertions, all blocks: `unsafeMain == 0`, `unsafeWarm == 0`, `unresolvedMain == 0`, `unresolvedWarm == 0`.
  - Assertions, singles and pairs: `empty == 0`.
  - Print the thin report: sizes, thin by injury × tier, thin days.
  - Header comment: the finisher is outside this change (OI-396).
- [ ] **Step 4: Run** `TZ=Asia/Kolkata flutter test test/contracts/injury_recheck_v14_contract_test.dart test/plan_generator/injury_floor_sweep_test.dart test/contracts/spawn_env_manifest_test.dart` and save the output as the BEFORE record.
  - Expected: FAIL on the data pins and the behavioural tests (no data change yet).
  - The sweep's singles PASS (0 / 0 / 0, `sweep_before2.txt`).
  - Pairs are measured for the first time. If any of unsafe, unresolved or empty is non-zero TODAY, that is a pre-existing defect. Stop, report it, and add it to this batch's fix list before going on.
  - `spawn_env_manifest_test` PASSES.

### Task 2: Data, seed, warm-up list, substitutes

**Files:** the table, the applier, `exercise_library.json`, `seed_service.dart`, `warmup_cooldown.dart`, `injury_substitutes.dart`.

- [ ] **Step 1: Write the table** from `injury/proposal.json` (102 ids). `_meta.decision` quotes the founder approval and its three edits; `reasons` keeps the one-line reason per row.
- [ ] **Step 2: Write the applier**, copying `add_library_core_fields_v13.js`'s `format()` and round-trip guard. Run `node scripts/add_library_injury_tags_v14.js --check`. Expected: `round-trip OK (285 rows)`. Then apply.
  - Expected: 102 rows changed, 146 tokens added.
  - `git diff --stat` touches only `assets/data/exercise_library.json` (plus the new files).
  - `node` recount: 33 rows with an empty list.
- [ ] **Step 3: Seed v14.** Add the v14 comment (the founder rejection of the 13-B carve-out, the counts, the plan path) and set `_exerciseLibraryVersion = 14`.
- [ ] **Step 4: Warm-up list.** Set `_moveInjuries['Push Up'] = {'wrist', 'shoulder'}`. Then rewrite the comments that turn false:
  - `warmup_cooldown.dart:16-19`: "Push Up stays for a shoulder injury … the library tags it wrist-only".
  - The comment that says the main-move under-tagging is "a separate, deliberate library-audit batch": it now says v14 closed it.
- [ ] **Step 5: Substitutes.** Remove every name now tagged for its key:
  - shoulder: Dumbbell Bench Press, Push Up, Kettlebell Goblet Press, Lat Pulldown. Tricep Pushdown (Cable) STAYS: it is elbow-tagged only, still shoulder-safe and live (round-1 F5).
  - knee: Leg Press;
  - wrist: none;
  - elbow: Tricep Pushdown (Cable), Cable Curl → the key is deleted (Ruling 3);
  - hip: none (Leg Press is knee/lower_back; Leg Extension is knee only).
  - Recompute the list by script before editing, never by hand.
  - Add to shoulder, in this order after Machine Chest Press: Floor Press, Chest Squeeze Press. Add Machine High Row before Chin Up (Ruling 3).
  - Update the doc comment. Remove the "sole shoulder-safe overhead press" line, and add that the elbow list is empty (every elbow-pattern row is elbow-tagged).
  - New test in `injury_recheck_v14_contract_test.dart`, "every curated substitute is safe for its injury": for each `InjurySubstitutes._preferred` key (read through `preferredFor([key])`), every name is a library row not tagged `key`. Mutation: re-add `Push Up` to shoulder → FAIL.
- [ ] **Step 6: Run Task 1's tests.** Expected: PASS. Then run the sweep and save it as the AFTER record.
  - Expected: 0 empty, 0 unsafe main, 0 unsafe warm/cool (it was 640 before Step 4), 0 unresolved.
  - Thin is about 44 for singles (reported, not gated). The substitute change can move it; explain any move.
  - Pairs: if empty rises above the BEFORE record, stop and tell the founder.
  - The before/after figures go in the diagnose doc.
- [ ] **Step 7: No commit yet.** Task 3 repoints the tests this data change reddens. Data, code and repoints land in ONE commit, at the end of Task 3, so no commit carries a red test.

### Task 3: Repoint the tests the data change reddens

Measured, not guessed. Probe 2 (`injury/probe2_tests.txt`, first line holds the command) applied the FULL change: the table, `_moveInjuries` Push Up, and the substitute edits from Task 2 Step 5 (with Tricep Pushdown kept for shoulder). It then ran `TZ=Asia/Kolkata flutter test test/contracts test/plan_generator test/profile test/ai_coach`, the widest set that can read the library: 6,641 passed, 4 skipped, **12 failed, in 9 files**.
- One of them, `spawn_env_manifest_test.dart`, is the sweep's env override; Ruling 5 removes it.
- The other 11, in 8 files, are below.
- The mirror test and the substitute test (1) PASS with the full change. The three added shoulder subs make the shoulder re-rank move a pick again.
- Every repoint keeps the test's intent and swaps its literal for the v14 founder value. None is loosened.

**Files:** the eight reddened files plus the mirror and substitute tests, two fixtures (`exercise_library_v12_row_hashes.json`, `generator_golden_hashes.json`) and two baseline files (`baseline_scorecard.json`, `baseline_plans.md`).

- [ ] **Step 1: `injury_undertag_13b_contract_test.dart`** (3 tests).
  - "every 13-B row carries EXACTLY its expected injury tokens": update `k13bExpected` for the 13-B rows the v14 table extends: E022 +elbow, E057 +hip, E074 +shoulder, E101 +elbow, E135 +shoulder (round-1 reviewer: exactly these five). Compute the new lists by script from the table.
  - "corrections are exact": Hollow Body Hold `isEmpty` → `{'lower_back'}` (founder call 4). The other three corrections stay as they are.
  - "the injury-safe pool stays untagged": replace `k13bKeptSafe` with Task 1's `kV14SafePool`. Push Up's pin becomes `{'shoulder', 'wrist'}`, with a reason quoting the founder.
  - Rewrite the stale comments that name the 13-B carve-out.
- [ ] **Step 2: `injury_safety_tags_v13_behavioral_test.dart`**, "the five rows carry exactly their added tags, nothing removed". E061 Running gains `hip` (warm-up alignment). Assert the five rows ⊇ their v13 additions, and equal the v14 union.
- [ ] **Step 3: `exercise_library_merge_contract_test.dart`**, "injury tags are never merged".
  - The literals become E107 `['hip']`, E176 `['hip', 'lower_back']`, E016 `['elbow', 'shoulder', 'wrist']`, E097 `['elbow']`.
  - The reason says the values come from the v14 table, and the Batch A merge still carries nothing.
  - Rewrite the `:10-11` comment and the test title (no "founder 13-B carve-out").
- [ ] **Step 4: `warmup_library_injury_mirror_test.dart`.** Keep the existing 3-name test (`mainCascadeOverlapMoves`, `warmup_cooldown.dart:101`). Add a second test over the existing `@visibleForTesting` `WarmupCooldownSelector.moveInjuries` (`:95`), with no new lib API (round-1 M12): every key is a library name, and its set equals the library list (27 of 27, measured). Mutation: revert Push Up in `_moveInjuries` → FAIL.
- [ ] **Step 4b: `warmup_injury_filter_behavioral_test.dart`**, "shoulder injury DROPS shoulder-loading warmup/cooldown moves (U3)" (`:112-120`, round-1 F1, probe 2 red).
  - Add `'Push Up'` to `_shoulderMoves` (`:24-30`).
  - Replace `:116-120` with `expect(names, isNot(contains('Push Up')))`, quoting the founder call.
  - Rewrite the `:22-23` comment.
  - Add the positive control the plan used to claim existed (round-2 F2): in the uninjured baseline test (`:104-110`), add `expect(warmupCooldownNames(gen(injuries: const [])), contains('Push Up'))`.
  - The mutation in Step 10 (revert `_moveInjuries` Push Up) must turn THIS test red too.
- [ ] **Step 5: `injury_substitute_preference_behavioral_test.dart`.** Test (1) PASSES in probe 2. Run it again after Task 2 to confirm.
  - Re-measure Ruling 3 with a TEMPORARY untracked file under `test/plan_generator/` (a test file must sit in the project to resolve `package:icanbefitter`). It is deleted before the commit; confirm with `git status`.
  - Parameters: 6 injuries (shoulder, knee, lower_back, wrist, elbow, hip) × 4 tiers × 4 goals × 3 levels × {3, 4, 5} days, phase 1. Generate with `disable_injury_substitute_pref` set (OFF) and deleted (ON), and count personas whose ordered variant-A names differ.
  - Save the output to `injury/subs_probe_after.txt` and quote the per-injury counts in the diagnose doc.
  - Stop condition: shoulder count == 0 means Ruling 3 failed. Stop and report.
- [ ] **Step 5b: `core_list_pool_behavioral_test.dart`**, "injured user keeps the soft avoid and L6" (`:626-645`, probe 2 red: expected `['Dumbbell Bench Press']`, actual `['Machine Chest Press']`).
  - The synthetic rows use the OLD shoulder substitute names. Variant B soft-avoids A and takes the next curated sub, and Dumbbell Bench Press is no longer curated.
  - Rename the synthetic `C2` to `'Floor Press'` (now the second curated shoulder sub).
  - Change BOTH assertions on `'Dumbbell Bench Press'` to `'Floor Press'`: `:639` (variant B) and `:643` (phase 2 after the demote of A takes the next curated sub, by the same logic as before; round-2 F1).
  - The test's subject (soft avoid and L6 survive for an injured user) stays the same.
- [ ] **Step 6: Frozen reference.** `RECORD_LIBRARY_REFERENCE_IDS=<the 102 ids, comma-separated, from the table> flutter test test/contracts/exercise_library_frozen_reference_test.dart`. Then `git diff --stat test/fixtures/exercise_library_v12_row_hashes.json`: exactly 102 hash lines change. A different count is a defect.
- [ ] **Step 7: Golden.**
  - `RECORD_GENERATOR_GOLDEN=1 flutter test test/plan_generator/generator_golden_test.dart`.
  - The changed keys must ALL start with `injury|`. Probe 1 (data only) showed 18: knee×full_gym p1/p2; shoulder × 4 tiers × p1/p2; lower_back × 4 tiers × p1/p2. Probe 2 (full change) reported the golden failing with the same test; recompute the key list after Task 2.
  - Any non-`injury|` key changing is a defect: stop.
  - List the keys in the diagnose doc.
- [ ] **Step 8: B1 gate report.** `WRITE_CORE_LIST_REPORT=1 flutter test test/plan_generator/core_list_pool_gate_test.dart`. The hard zeros stay 0; commit the regenerated `core_list_pool_report.md`.
- [ ] **Step 8b: Scorecard baseline** (`test/plan_generator/scorecard_gate_test.dart`, probe 2 red on both no-regression ceilings).
  - Total fallback picks went 2862 → 2866 (ceiling 2862).
  - Mean overall went 86.20 → 86.12 (floor 86.15).
  - Same cause as 13-B, whose commit `2d2c7645` re-baselined `test/plan_generator/baseline/baseline_scorecard.json`: injured personas lose options on purpose.
  - Re-baseline with `dart run test/plan_generator/generate_baseline.dart`. It rewrites BOTH `baseline_scorecard.json` (`generate_baseline.dart:78`) and `baseline_plans.md` (`:114`); commit both, and run the moved-persona check over both.
  - Before committing, diff the old and new per-persona scores. Every persona whose score or fallback count moved must be an injury persona (`generator_matrix.dart:262-277`). Any uninjured persona moving is a defect: stop.
  - Put the aggregates before/after and the moved personas in the diagnose doc. The ceilings themselves are untouched.
- [ ] **Step 9: Seed.**
  - The version pins (`exercise_library_core_fields_contract_test.dart:144`, `>= 13`; `exercise_plate_library_data_test.dart:33`, `>= 12`) stay green at 14.
  - Add a behavioural seed test beside `library_seed_prune_behavioral_test.dart` (round-1 F9), `test/contracts/library_seed_v14_upgrade_behavioral_test.dart`:
    - put a v13-shaped `E005` Push Up row (`injury_contraindications: ['wrist']`) in `exerciseBox`;
    - set `exercise_library_version = 13`, with `seeded`, `seeded_exercises` and `seeded_foods` true and the food version current;
    - run `SeedService.instance.seedIfNeeded()`;
    - assert E005's list is `['shoulder', 'wrist']` and the stored version is 14.
  - Use a plain `test()`, not `testWidgets`; real I/O inside `testWidgets` hangs (CLAUDE.md §4.9). Open the boxes with `setUpHiveForTests` (`test/helpers/hive_test_setup.dart:30`).
  - Set `food_library_version` to a large number (e.g. 9999), so the test never seeds foods into an unopened box when the private food constant moves.
  - This is the first test to call `seedIfNeeded`. If the bundled asset cannot load under `flutter_test`, STOP and ask the founder about a `@visibleForTesting` seam (a lib change). A source-grep is not an acceptable fallback, and this is not a Ruling to make alone.
  - Mutation: seed constant back to 13 → FAIL.
- [ ] **Step 10: Mutations.** Each must redden at least one test. Confirm each applied with `grep -c`, and restore with `git diff` empty afterwards.
  - Remove Push Up's `shoulder` in the library → contract test + behavioural FAIL.
  - Revert `_moveInjuries` Push Up → mirror + `warmup_injury_filter_behavioral_test` + sweep (`unsafeWarm`) FAIL.
  - Seed 14 → 13 → the seed test FAILs.
  - Re-add `Push Up` to the shoulder substitutes → the substitute-safety test FAILs.
  - Record the counts in the diagnose doc.
- [ ] **Step 11: Diagnose doc, then commit.** Write and validate the diagnose doc (Task 4 Step 1) first. Then commit Tasks 1-3 together:
  - message `fix(library): injury re-check — 102 rows gain 146 tags, seed v14`;
  - body: the test paths, plus `closes-diagnose: d30de7`.

### Task 4: Diagnose doc, registry, docs, closure, gate loop, review, PR

- [ ] **Step 1: Diagnose doc** `docs/diagnoses/2026-10-23-library-injury-recheck-d30de7.md`, full template.
  - This is a recurrence of the under-tag class: `related_bugs: [f4c1e8, c2d5e8, e1a7c4, a1f6c3]`.
  - Writer: the library rows.
  - Readers:
    - `exercise_repository.dart:411-420` (queryV4 filter 8);
    - `exercise_selector.dart:470-482` (V3 filter) and `:1452-1470` (`_isContraindicated`);
    - `warmup_cooldown.dart` `_moveInjuries` (its own table, now value-checked for all 27 names);
    - `injury_substitutes.dart` (re-rank only).
  - Not a reader: `exercise_picker_sheet.dart:32` (a user choice; Ruling 4).
  - `touched_layers_checked` per §6.
  - The mutation evidence from Task 3.
  - The measured sweep: before 28 thin / 0 one-exercise; after about 44 / 11 (Task 2 Step 6 has the final figures), plus the pairs and repeat blocks.
  - The scorecard before/after and the moved personas (Task 3 Step 8b).
  - Tier 2 (Hive) line: stored plans are not rewritten by a re-seed; pre-launch, so not a real-user risk (root CLAUDE.md §1).
  - Validate with `dart run scripts/validate_diagnose_doc.dart <path>`.
- [ ] **Step 2: SoT registry** `exercise_injury_tags`:
  - repoint the stale reader line ranges (`:335-345` is now `:411-420`);
  - add the v14 writer (table + applier) and the warm-up and substitute coherence notes;
  - point `behavioral_test_path:` at the new contract test.
- [ ] **Step 3: Docs.**
  - `docs/architecture/plan-engine-detail.md` and `lib/shared/repositories/plan_engine/CLAUDE.md`, wherever they state the 13-B carve-out.
  - `docs/reference/exercise-library.md` if it describes injury tagging.
  - Known stale (round-1 M13):
    - `lib/core/utils/injury_vocab.dart:5` ("150 of 259 rows"; recount);
    - `docs/architecture/plan-engine-detail.md:27`;
    - `docs/sot_registry.yaml` around `:11395-11408` (carve-out text, "Goblet Press retained as the sole shoulder-safe overhead-press sub");
    - the three "6 of (the )?9" lines (Ruling 3).
  - Grep for `kept safe`, `carve-out`, `k13bKeptSafe`, `sole shoulder-safe`, `Goblet Press is the` and `6 of (the )?9` across `docs/`, `lib/`, `test/` and `scripts/` before editing (`scripts/repair_exercise_library_v12.js:74` is one hit). Every hit is rewritten, or left with a reason.
  - A closure ledger is a dated record. `docs/audit/library-data-repair.closure.yaml:162` (E107 "untagged for hip injuries", `k13bKeptSafe`) and any other historical ledger stay as they are; the new ledger names them as superseded. A shipped script's comment (`repair_exercise_library_v12.js:74`) is also history: leave it, and name it.
- [ ] **Step 4: Closure ledger** `docs/audit/library-injury-recheck.closure.yaml`, with items:
  - the retag;
  - the warm-up mirror;
  - the substitutes;
  - the sweep;
  - CARVEOUT-E173-E127, which updates the B1 ledger entry to `closed_in_commit`, "keep";
  - the picker (`verified_clean`; founder: leave it, the user may pick any exercise);
  - the thin days (`upstream_blocked`, `blocker: OI-401 thin-day top-up`, `reopen_when: OI-401 merges`);
  - the finisher (`upstream_blocked`, `blocker: OI-396 renders and injury-filters the cardio finisher`, `reopen_when: OI-396 merges`);
  - the scorecard re-baseline (`closed_in_commit`, with the before/after aggregates);
  - the repeat-phase drop count (`closed_in_commit` as measured-and-reported; the refill belongs to OI-401).
- [ ] **Step 4b: Docs commit.** One `docs(library): injury re-check registry, docs and closure` commit via `scripts/safe_commit.sh "<msg>"`. It holds:
  - the SoT registry and the docs;
  - both closure ledgers (the new one, and B1's `CARVEOUT-E173-E127` entry);
  - `docs/audit/open_issues.md` (OI-400, OI-401) and `docs/superpowers/skills-log.md`;
  - this plan;
  - the indexes pre-commit regenerates (`OPEN_INDEX.md`, `docs/diagnoses/INDEX.md`). Stage them.

  The new ledger's `closed_in_commit` entries cite the Task 3 Step 11 SHA. Scratchpad evidence dies with the session, so the durable record is the committed table `_meta` and the diagnose doc: copy the before/after figures there.
- [ ] **Step 5: Full gate loop** (§4.12.8):
  - `flutter analyze lib/`;
  - full `TZ=Asia/Kolkata flutter test`;
  - the pre-commit loop.
- [ ] **Step 6: B-pass** (`/code-review`, a fresh Sonnet reviewer) over `git diff origin/main...HEAD`, with lenses 1, 6, 7 and 8 and this plan's Review Focus. Triage, then fix with a failing test first.
  - The review file `docs/reviews/<x>-review.md` needs a same-dated entry in `.claude/skills/code-review/tuning-history.md` in the same commit (`check_skill_tuning_history.dart`).
  - Every `fix(...)` follow-up commit carries `closes-diagnose: d30de7` (`check_bugfix_commits_have_diagnose.dart`).
- [ ] **Step 7:** Plan-review record `docs/plan-reviews/<recordSlug>.md`, in its own commit. Push via HTTPS `safe_push.sh`, `gh pr create`, then `get_status` + `set_monitor`. Merge on green via `safe_pr_merge.sh`, then retire the worktree.

## Round-1 resolution (`injury/review_1.md`, not_converged, 0 P0 / 4 P1 / 7 P2 / 3 M)

| # | Sev | Finding | Resolution |
|---|---|---|---|
| F1 | P1 | `warmup_injury_filter_behavioral_test.dart:118` pins Push Up kept for shoulder; not probed | Task 3 Step 4b; probe 2 confirmed red |
| F2 | P1 | Sweep's `INJURY_SWEEP_LIBRARY` reddens `spawn_env_manifest_test` | Ruling 5: override removed; Task 1 Step 4 runs the manifest test |
| F3 | P1 | Scorecard ceilings not probed | Probe 2: red (2866 > 2862; 86.12 < 86.15); Task 3 Step 8b re-baselines with a moved-persona check |
| F4 | P1 | Two injuries at once unmeasured on OFF | Task 1 Step 3 pair block; Review Focus 1 now cites it |
| F5 | P2 | Tricep Pushdown wrongly removed from shoulder subs | Task 2 Step 5: kept; Ruling 3 lists it live |
| F6 | P2 | Ruling 3 additions outside approval; probe numbers unsaved | Approval + Ruling 3 say founder's yes is asked at the converged gate; Task 3 Step 5 saves a re-measure |
| F7 | P2 | Sweep skips unresolved names; finisher unscanned | Task 1 Step 3 counts and gates unresolved; Goal "Out of scope" + closure item OI-396 |
| F8 | P2 | "T1b" untracked, name collision | OI-401 minted; renamed throughout; closure `blocker: OI-401` |
| F9 | P2 | Seed proven by source-grep only; stored plans | Task 3 Step 9 behavioural seed test; Review Focus 3 + diagnose tier-2 line |
| F10 | P2 | Probe count and command not recorded | Probe 2 recorded with its command; Task 3 intro restated |
| F11 | P2 | Repeat path not in the sweep | Ruling 6 + the sweep's repeat block (reported) |
| M12 | M | `mirroredMoveNames` duplicates `moveInjuries` | Task 3 Step 4 uses `moveInjuries` |
| M13 | M | More stale comments | Task 2 Step 4 + Task 4 Step 3 lists |
| M14 | M | "thin 44" read as exact | Task 2 Step 6: "about 44, reported" |

## Round-2 resolution (`injury/review_2.md`, converged, 0 P0 / 0 P1 / 9 P2 / 5 M)

| # | Finding | Resolution |
|---|---|---|
| F1 | Second stale `'Dumbbell Bench Press'` assertion at `:643` | Task 3 Step 5b changes both |
| F2 | Step 4b's positive control did not exist | Step 4b adds `contains('Push Up')` to the uninjured baseline test |
| F3 | Pairs omitted elbow and hip | All 15 pairs of six injuries (1,440 runs) |
| F4 | Sweep runtime and structure | Three `test()` calls, wall times recorded, ~5 min cap |
| F5 | `6 of 9` grep missed two hits; wrong line | Pattern `6 of (the )?9`, three named lines, new wording |
| F6 | No commit for docs, ledgers, OIs, skills-log, plan | Task 4 Step 4b docs commit |
| F7 | Seed test details | Plain `test()`, `setUpHiveForTests`, food version 9999, stop-and-ask fallback |
| F8 | `baseline_plans.md` also rewritten | Added to Step 8b and the Re-record list |
| F9 | Probe body not saved | Temporary untracked test file with stated parameters; output saved |
| M10 | `scripts/` grep scope; ledger contradiction | `scripts/` added; historical ledgers and scripts left and named |
| M11 | Tuning history; `closes-diagnose` on fix commits | Step 6 names both |
| M12 | `kV14SafePool` home | `test/helpers/injury_safe_pool.dart` |
| M13 | Review Focus 2 wording | Points at the unchanged floor test |
| M14 | Task 3 file counts | Restated |

## Execution rulings (made while building, after both review rounds)

| # | Ruling | Why | Cost if wrong |
|---|---|---|---|
| E1 | The proposal table (`scripts/data/library_injury_additions_v14.json`) was created before the failing tests, as spec data. | The table is the founder-approved decision list; the tests assert against it, so they cannot be written first without it. The tests still ran RED (23 fail, 2 pass) before any library byte changed. | None: RED was observed. |
| E2 | Generator personas in the contract test come from a reach search over the real `generateV4`. A move no persona reaches is asserted on `queryV4` with a positive control instead. | Goblet Press, V-Up, Hollow Body Hold, Burpee and Mountain Climber are never picked by any tier x goal x level x days, so a generator assertion on them would pass with the tag missing. | A reached-move assertion is only as wide as the persona list; the sweep covers the rest. |
| E3 | The pairs block gates `empty <= kPairsEmptyBaseline` (2), the count measured on the unmodified v13 library. Singles stay `empty == 0`. | Two injuries at once already left 2 days empty before v14, so `== 0` would fail on data this PR did not make. OI-401 (thin-day top-up) takes the ceiling to 0. | The ceiling lets a NEW empty day through only if an old one is fixed first; the AFTER run shows the actual count. |
| E4 | The "sorted" assertion covers the rows the table touched, not all 285. | 16 rows the table does not touch (E229, E248, ...) keep their v13 tag order; order is never read by the filter, and re-sorting them would change rows outside the decision list. | None for behaviour. |
| E5 | The pairs ceiling moves from 2 to 4 (`kPairsEmptyBaseline`). **The founder was asked and said ship (2026-10-23): "Ship, allow 4".** | Plan Step 6 said stop and tell the founder if pairs went above 2. They did: the two v13 empties (knee+hip, knee+lower_back) stay and two new ones appear (lower_back+hip, week-2 leg day, 3 and 5 days) because Deficit Reverse Lunge is hip-tagged. Removing that tag would be the "kept safe" principle he rejected. | The sweep lets 2 more empty days through until OI-401 lands and takes the ceiling to 0. |
| E6 | The scorecard moved-persona check compares a fresh v13 regeneration against a fresh v14 regeneration, not the committed JSON against v14. | The committed baseline (last regenerated 2026-08-28) already differs from a fresh run on the unmodified library in 165 of 606 personas, so the literal check would stop on drift this change did not cause. Fresh vs fresh: 12 personas moved, all injured, 0 of 576 uninjured. The refreshed baseline clears the old drift too. | A reviewer sees a 177-persona baseline diff; the diagnose doc explains the 165. |
