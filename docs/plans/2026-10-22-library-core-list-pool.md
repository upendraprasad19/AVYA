# Batch B1 — Core-list exercise pool (ship-dark) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revision:** r3 (2026-10-23).
- **Round 1:** `not_converged`, 2 P0 / 7 P1 / 12 P2.
- **Round 2:** `not_converged`, 0 P0 / 2 P1 / 10 P2 / 13 mechanical. Both P1s concerned shipped-data drops; the fixes were checked by counterfactual simulation.

Resolution maps are at the end.

**Approval (founder, 2026-10-23):** B1 and B2 approved; Ruling 12 confirmed; **execution mode: inline** (§4.12.7), on branch `library-batch-b`. Base fast-forwarded to `47cb142c` (4 commits, none touching `lib/` or `assets/`), so every reference to the pre-change tree `08c077d1` means this base.

**Goal:** Behind a default-OFF flag, the generator picks every strength exercise from the founder-approved core list for the user's effective level, with same-family fill from rows that are core at no lower level, else the slot drops. OFF output is proven byte-identical to `main` `08c077d1`, with two exceptions, each recorded in its own diagnose doc:
- Task 1: repeat pins, library and custom, now pass the equipment capability check.
- Task 1b: injury tags.

**Architecture:** New library keys only, so OFF reads nothing new. A pure `CoreListSelector.rankedPool` returns the ordered candidate pool for a slot. `ExerciseSelector._pickCoreList` takes the final pick through the existing `_selectCandidate`, so the injury-substitute and cross-phase levers stay one implementation. `pickV4` delegates to it as its first statement when `enable_core_list_pool` is ON. A test-only trace sink records per-slot provenance. A golden recorded from the pre-change tree proves OFF identity. An ON-world gate runs the real `generateV4` and reads the trace. One live safety fix lands first: the attempt-5 pool and repeat pins check equipment capability.

**Tech Stack:** Flutter/Dart, Hive (untyped row maps), `flutter_test`, node (data script), `package:crypto` (sha256).

**Spec:** `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` (§2 D2/D3/D5/D6/D8, §3.1, §4.1–4.3, §9 row B). Evidence: session scratchpad `batchb/q1_data_delta.md`, `batchb/q2_generator_path.md`, review `batchb/b1_review1.md`.

**Blast radius:** `platform`. Full ×2 plan review, B-pass before merge, flag logged in `docs/ship_dark_pending_review.yaml`.

**Scope split (ruling):** Batch B is two plans. **B1 (this plan)** covers selection. **B2** covers the session-size set budget (`docs/plans/2026-10-22-session-set-budget.md`) and builds on B1. B1 does NOT edit `lib/shared/repositories/plan_engine/plan_generator.dart` (rule 14; the founder's 2026-10-22 waiver covers B2's wiring only).

## Global Constraints

- **D3:** a core list per level drives generation. Non-core rows serve swap/search and §4.2 family fill only.
- **D6 / §4.2:** never a lower level's core pick, neither as a core pick nor through family fill.
- **D2 / §4.1:** `discipline` ∈ {`calisthenics_skill`, `olympic`} never enters a normal plan.
- **D8:** the generator never auto-adds custom exercises. Community and custom rows carry no core fields and are never selected by the ON path.
- **§4.1 pool:** `core_levels` contains the effective level (`PlanGenerator.effectiveLevel`); discipline not excluded; equipment fail-closed through `EquipmentCapability.canPerform`, or the `queryV4` tier rule when capability is null; no injury contraindication (the same `_isContraindicated`); minus exclusions. Previous-phase avoid, plateau rotation and L6 demote keep working.
- **Flag:** `enable_core_list_pool`, default OFF (`configBox` value `== true`). OFF output byte-identical to the Task 0 golden, apart from the keys the Task 1 and Task 1b diagnose docs name.
- **Library data:** no edit to any EXISTING field of `assets/data/exercise_library.json`; new keys only, proven against a committed per-row reference. `primary_muscles` is never renamed.
- **Capability semantics:** `capability == null` means "do not enforce capability". The ON path then falls back to the `queryV4` tier rule; it never enforces nothing.
- **Process:**
  - Tests run with `TZ=Asia/Kolkata`.
  - Commits only via `scripts/safe_commit.sh "<msg>"`; one push for the batch; no APK.
  - Commands handed to the founder use PowerShell (`$env:VAR='x'; cmd`); commands run by the agent use Bash.
- **Literals:** every literal a test asserts about real data is computed from the data first (code-review lens 8).

## Review Focus

1. **Promoted users on thin setups.** A bodyweight or home beginner reaches effective intermediate at phase 3 and advanced at phase 5 (`plan_generator.dart:365-374`). D6 accepts their gaps, so slots drop; days must not empty and lower-level rows must not return through fill. Covered by the Task 3 fill-path persona and the Task 4 level and empty-day counts on phases 1–5.
2. **Stale Hive (v12 rows, no core fields) with the flag ON.** Covered by Task 3 `stale library delegates to OFF` (trace: `delegations == 0`) and the mixed-library case.
3. **Community, custom and pinned rows.** Pins bypass `pickV4`, but `fresh()` refills through it (`exercise_selector.dart:788-800`); customs carry `equipment_needed: []`. Covered by Task 1 custom-pin tests and Task 0 pin personas.
4. **Injured, excluding and owned-equipment users with the flag ON.** Covered by Task 3 ON filter tests and the Task 4 hard counts over 24 injury, 4 exclusion and 4 owned-equipment personas.
5. **Gym users and improvised rows after Phase 1.** `_preferNovel` walks the list (`exercise_selector.dart:1054-1065`), so the improvised rule must be a filter keyed on capability, not on the tier label. Covered by Task 3 with `previousPhaseByDay` set and owned-equipment personas.

---

## Rulings

1. **Equipment tokens move to Batch D.** The 15 tokens (spec §3.2) and the 12 shipped rows that would use them are not in B1. Users cannot own new kit until D's gym-extras checklist. Six tokens are aliases today, so making them canonical changes custom/community normalisation (`equipment_vocab_library_contract_test.dart:91-92`). `yoke` would make E182 unperformable. Closure `upstream_blocked`; reopens when Batch D's plan is approved.
2. **No cloud migration in B1.** No Edge Function reads a new field. Cloud already carries 20 of the 39 JSON keys (`scripts/seed_exercise_library.js:119-127`). Spec §3.3 is corrected in Task 5. Closure `verified_clean` (evidence: the grep).
3. **Existing-field retags.** Class (d) retags in `q1_data_delta.md` §1.1 change OFF output and were never founder-decided. They are handled in four groups:
   - **(a) Strength movement patterns: applied ON-only** through a new key `slot_pattern` (Ruling 4) on the 12 kept rows whose strength-pattern set changes:
     - E015 Front Raise → shoulder_isolation
     - E048 Glute Bridge → hip_dominant
     - E222 Kas Glute Bridge → hip_dominant
     - E127 Reverse Hyper → hip_dominant
     - E046 Nordic Curl → knee_dominant
     - E276 Standing Towel Pull Apart → shoulder_isolation
     - E064 Rowing Machine → no strength pattern
     - E292 Sliding Leg Curl → knee_dominant
     - E050 Sumo Deadlift → hip_dominant
     - E274 Prone T Raise → shoulder_isolation
     - E277 Prone W Raise → shoulder_isolation
     - E198 Lunge with Twist → knee_dominant

     The value is the full draft `movement_pattern`. These close the structural holes the review measured: Front Delts shoulder_isolation drops at every tier, and beginner hamstring curls drop everywhere. The 18 secondary-tag-only drops are not applied, because no strength slot reads them.
   - **(b) Five safety-direction `injury_contraindications` additions:**
     - E061 +knee
     - E070 +shoulder +elbow
     - E121 +wrist +shoulder
     - E127 +lower_back
     - E173 +lower_back

     **Founder decision (2026-10-22): apply all five live, flag or no flag.** This is Task 1b, a bug fix with a diagnose doc. It knowingly supersedes the Batch 13-B tags on E121 (`injury_undertag_13b_contract_test.dart:55`). Tags are only added, never removed: E070 keeps `wrist`. OFF output changes only for injured personas, and Task 1b names every golden key that changes.
   - **(c) Ordering, prescription and logging fields stay as shipped, for OFF and ON:** `is_foundational`, `priority_tier`, `rep_range`, `exercise_type`, `logging_type`, `category`, `difficulty_level`, `suitable_for`. Shipped values carry Batch 13/A founder decisions; the drafts are agent proposals. Cost: ON ordering uses today's values. Closure `verified_clean`, evidence the class table in `q1_data_delta.md`.
   - **(d) Not applied: spec §3.1's `difficulty_level` `elite` (E070) and `suitable_for` `Calisthenics` (10 rows).** Both apply only to discipline-excluded skill rows, which ON never selects, and `queryV4` compares `suitable_for` (`exercise_repository.dart:391-400`). Recorded as a spec deviation (Task 5).
4. **ON-only label keys.** ON reads `slot_focus ?? target_focus` and `slot_pattern ?? movement_pattern`. `target_focus` and `movement_pattern` stay unchanged because `queryV4` (OFF) and `exercise_display.dart:11-26` read them. The flip commit copies both keys into their fields and deletes them. `slot_focus` is present on 19 rows:
   - **14 rows where the draft label changes slot visibility** (class a):
     - E064 [Full Body, Mid Back]
     - E114 [Shoulders, Front Delts, Upper Chest]
     - E118 [Mid Chest]
     - E186 [Front Delts, Shoulders, Mid Chest, Triceps]
     - E198 [Glutes, Quads, Core/Obliques]
     - E264 [Lats, Mid Back]
     - E272 [Shoulders, Rear Delts]
     - E273 [Lateral Delts, Shoulders]
     - E274 [Mid Back, Rear Delts]
     - E275 [Lats, Mid Back]
     - E276 [Rear Delts, Mid Back]
     - E277 [Mid Back, Rear Delts]
     - E289 [Lateral Delts, Shoulders]
     - E290 [Shoulders, Rear Delts]
   - **5 rows where the draft label adds a `split_resolver.dart` sub-focus** (OI-386):
     - E090 [Core, Core/Obliques, Forearms]
     - E122 [Biceps (Short Head)]
     - E133 [Core, Core/Obliques]
     - E172 [Core/Obliques]
     - E175 [Core/Obliques]

   E052's "Calves (Soleus)" already sits in its `primary_muscles`, which the sub-focus rule reads.
5. **No universal pool in the ON path.** §4.2 handles an empty slot with family fill, then a drop. The OFF pool stays verbatim for OFF. It holds 7 discarded rows (E261 E263 E265 E144 E254 E075 E271) and the skill row E072. This resolves spec §9 row B's "universal-pool names repointed" and the E261/E274 items:
   - E261 carries `core_levels: []` and no `variant_family`, so ON never picks it.
   - E274 Prone T Raise is the beginner core row of that movement.

   Closure `verified_clean`; spec edited (Task 5).
6. **Warm-up / cool-down repoint moves to Batch C.** The discarded names it emits have kept replacements only among Batch C rows. Closure `upstream_blocked`; reopens when Batch C's plan is approved.
7. **Phase 1 "foundational-only" is a preference, not a filter.** Foundational rows rank first. Today's cascade does the same: attempt 1 requires foundational, attempt 2 drops the requirement (`exercise_selector.dart:1095,1109-1119`). A hard filter would drop more Phase 1 slots. **Founder decision (2026-10-22): preference.** Spec §4.1 is reworded in Task 5.
8. **`beat-my-coach` bug is filed, not fixed here.** `index.ts:195` filters on capitalised categories, while live categories are lowercase (verified by a read-only query), so every challenge comes from the fallback list (`:248-258`). Filed via `mint_oi.sh` with options (a) make the query work (changes content) and (b) delete the dead query. Closure `blocked_on_user`.
9. **The ON path is gated by real production runs plus a test-only trace.** The gate calls the real `generateV4`. Provenance comes from `CoreListSelector.debugTrace`, which production code writes and only tests read. It is not a reimplementation, so it creates no new mirror. The OFF mirrors are untouched.
10. **Stored but not yet read:** `gym_availability`, `requires_coaching`, `high_impact`, `skill_track`, `skill_step`, `regression_to`, `progression_to`.
    - Consumers: Batch D (gym availability) and the Phase-2 track (§8).
    - `regression_to` / `progression_to` are kept only when the name resolves to exactly one shipped row; an assertion enforces this.
    - Task 4 lists high-impact and requires-coaching picks as flip-review items.
    - Closure `upstream_blocked`; reopens when Batch D's plan is approved.
11. **Stale `plan_generator.dart:144-146` comment** ("Null whenever … the tier is not bodyweight"). It is outside rule 14 for B1, so B2 Task 6 fixes it, since B2 is authorised to edit that file. Closure `upstream_blocked`; reopens at B2 Task 6.
12. **Empty days: any-level core before the OFF cascade. CONFIRMED by the founder 2026-10-23** as an emergency exception to D6 / spec §4.2 / §10.1; Task 5 adds it to §4.2. A day whose two variants both empty (only injured bodyweight users on shipped data) takes core rows of any level before the OFF cascade. This is the one place a lower-level core row may appear, and it is never a retired row. D6 accepts gaps, not empty strength days. Cost if wrong: an injured promoted user sees an easier move on that day. Counted; the flip requires 0 after Batch C. Closure `upstream_blocked`, reopening at Batch C.

---

## File structure

| File | Responsibility |
|---|---|
| `test/plan_generator/generator_golden_test.dart` + `test/fixtures/generator_golden_hashes.json` (create) | Per-persona sha256 of the real `generateV4` (OFF identity). |
| `test/contracts/exercise_library_frozen_reference_test.dart` + `test/fixtures/exercise_library_v12_row_hashes.json` (create) | Per-row hash of every pre-existing key, recorded on `08c077d1`. |
| `lib/shared/repositories/plan_engine/exercise_selector.dart` (modify) | Task 1: att5 + pin checks, stale comments. Task 3: delegation, `_pickCoreList`, `_buildExercise({String? typeOverride})`. |
| `scripts/add_library_core_fields_v13.js` + `scripts/data/library_core_fields_v13.json` (create) | Idempotent merge of the new keys from a committed per-id table. |
| `assets/data/exercise_library.json`, `lib/core/services/seed_service.dart` (modify) | New keys; seed v13. |
| `lib/shared/repositories/plan_engine/core_list_selector.dart` (create) | Pure ranked pool per slot + `@visibleForTesting` trace sink. No Hive, no flags. |
| `lib/shared/repositories/plan_engine/plan_engine_flags.dart` (modify) | `coreListPoolEnabled`; stale capability comment (:388). |
| `test/plan_generator/core_list_pool_gate_test.dart` + `test/plan_generator/baseline/core_list_pool_report.md` (create) | ON-world invariants + flip-review report. |

---

### Task 0: Golden fixture and frozen library reference

**Files:** create the golden test + fixture, `exercise_library_frozen_reference_test.dart` + `test/fixtures/exercise_library_v12_row_hashes.json`.

**Interfaces:** `generatorGoldenPersonas()` (top-level in the golden test) — reused by Task 4.

- [ ] **Step 1: Write the golden test.**
  - **Harness:** from `cross_phase_variety_behavioral_test.dart` `setUpAll`. Temp Hive; `GuardedBox.testBypassOwnership = true`; every library row put by `id`; `markInitializedForTests()`; `HiveUserSession.openForUser`. File-level `@Timeout(Duration(minutes: 10))` and `library;`. One `test()` per tier plus one for the extra personas, so a failure names its group.
  - **Personas** (deterministic order; each through `PlanGenerator.instance.generateV4(..., previousWeights: const {})`):
    - **grid:** tier {bodyweight, home_dumbbells, basic_gym, full_gym} × goal {build_muscle, lose_fat, strength, general_fitness} × days {3,4,5,6} × level × phase {1..5} = 960;
    - **injuries:** {['knee'], ['shoulder'], ['lower_back']} × 4 tiers × (build_muscle, 4d, intermediate, phases 1, 2) = 24;
    - **exclusions:** {['barbell'], ['pull-up bar']} × {basic_gym, full_gym} (build_muscle, 4d, intermediate, p1) = 4;
    - **cross-phase:** {full_gym, home_dumbbells} × {beginner, intermediate}, phase 2 with `previousPhaseByDay` derived as `prevFrom` does = 4;
    - **owned equipment** (profile `equipment_owned` written to `userBox` before the call, cleared after):
      - bodyweight beginner owning ['dumbbells', 'pull-up bar'], phases 1 and 3;
      - home_dumbbells intermediate owning ['pull-up bar', 'bench'], phases 1 and 3;
      - (build_muscle, 4d) = 4;
    - **pins:** full_gym intermediate and bodyweight beginner, phase 2, with `pinnedExercisesByDay` = their own phase-1 A/B names per day, plus one custom row (`equipment_needed: []`, name 'My Band Row', put in `HiveService.instance.customBox`, which `getCustomExercises()` reads at `exercise_repository.dart:463-470`) added to day 0's A list = 2;
    - **total** = 998.
  - **Key and value:** key `'$group|$tier|$goal|${days}d|$level|p$phase'`; value = `sha256(utf8(jsonEncode(phase.toMap())))`. Use `sha256Hex` from `scripts/migration_ledger_hash_lib.dart`, as `exercise_plate_swap_record_test.dart:17` does; `package:crypto` is only a transitive dependency.
  - **Location:** `generatorGoldenPersonas()` lives in `test/helpers/generator_golden_personas.dart`, so Task 4 imports it without a `main`.
  - **Fixture metadata:** `_meta: {recorded_on: '08c077d1', personas: 998}` is ignored by the comparison.
  - **Modes:** `RECORD_GENERATOR_GOLDEN=1` writes the fixture (sorted keys); otherwise the test compares and lists the first 10 differing keys.
  - **Header comment:** "Re-record only in a commit whose diagnose doc or plan names each changed key (B2, Batch C and OI-53 flips will)."
- [ ] **Step 2: Write the frozen reference test.**
  - For each row: `sha256(jsonEncode(SplayTreeMap(row restricted to the keys present on 08c077d1)))`, plus that row's key list.
  - `RECORD_LIBRARY_REFERENCE=1` writes `{id: {keys: [...], sha256}}`; otherwise every recorded key must exist and every hash must match.
  - This replaces `git show`, because CI's unit-test job checks out at depth 1 (`.github/workflows/test.yml:128`).
- [ ] **Step 3: Record both on the untouched tree.** Run `RECORD_GENERATOR_GOLDEN=1 RECORD_LIBRARY_REFERENCE=1 TZ=Asia/Kolkata flutter test test/plan_generator/generator_golden_test.dart test/contracts/exercise_library_frozen_reference_test.dart`. Expected: PASS, with 998 golden keys and 285 reference rows.
- [ ] **Step 4: Prove determinism.** Re-run without the env vars → PASS.
- [ ] **Step 5: Prove each test can fail.**
  - Swap `Barbell Curl` and `Self-Resisted Bicep Curl` `priority_tier` → both FAIL (golden names full_gym keys; reference names E-ids).
  - Restore by byte copy; `git diff --stat assets/` is empty.
- [ ] **Step 6: Commit** `test(plan-engine): golden of the real generator and frozen library reference before Batch B1`.

### Task 1: Equipment capability on the attempt-5 pool and on repeat pins (live safety fix)

**Files:**
- `exercise_selector.dart`:
  - att5 loop `:1172-1210`;
  - `buildPinnedDays.resolve` `:747-778`;
  - stale comments at `:502-518`.
- `plan_engine_flags.dart:388` (comment).
- New test `test/contracts/universal_pool_capability_behavioral_test.dart`.
- Diagnose doc `docs/diagnoses/2026-10-22-att5-capability-mirror-only-<id>.md`:
  - full template;
  - recurrence class OI-89 (`f7b2c4` / `c9a7e2` / `b6f4d1` / `d3a8f5`);
  - mirror-only guard.

**Writer/reader:**
- **Writers of the hazard:**
  - `_cascadeFill` attempt 5 (`:1172-1210`);
  - `buildPinnedDays.resolve` (`:747-778`).

  Both build a `PlannedExercise` with no capability check.
- **Readers:**
  - Train / Active Workout;
  - the mirror `cascade_tracer.dart:322-326`, which does check, so `scorecard_gate_test.dart:80-89` cannot see a production leak.
- **Origin:** the check was added to the mirror only, in `a7c2d194`.
- **Gating:** `capability` is non-null at every tier since OI-144 (`training_history_analyzer.dart:273-298`), and null when `disable_equipment_capability_floor` is set. That existing switch is the §4.6 kill switch for this fix.

- [ ] **Step 1: Write the failing tests.**
  - **`att5 skips a pool move the user cannot perform`:**
    - Setup: a synthetic box with one `vertical_pull` row needing ['barbell'], plus the real Pull Up / Chin Up / Inverted Row / Sliding Lat Pull / Doorway Isometric Lat Pull / Prone Lat Pull rows with `movement_pattern: ['warmup']`. That pattern forces attempt 5, which resolves pool names by NAME.
    - Call: `pickV4` at bodyweight with `resolveCapability(tier: 'bodyweight', exclusions: {}, flagEnabled: true)`; one day of 2 `vertical_pull` slots.
    - Assert: every pick passes `canPerform`; the first pick is not Pull Up.
  - **`capability null keeps today's att5 order`:** with `capability: null`, the first pick is Pull Up.
  - **`a library pin the user cannot perform is dropped and refilled`:** pin Barbell Curl, bodyweight capability → no built exercise fails `canPerform`; the slot is refilled through `fresh()`.
  - **`a custom pin with no recorded equipment is kept`:** custom 'My Band Row' with `equipment_needed: []`, bodyweight capability → present.
  - **`a custom pin needing kit the user lacks is dropped`:** custom with `['barbell']`, bodyweight capability → absent. This intentionally changes live behaviour for AI-authored customs with a real requirement; the diagnose doc says so.
  - **`pins with capability null are kept`:** Barbell Curl present.
- [ ] **Step 2: Run** → the enforcing library tests and the barbell-custom test FAIL; the other three PASS.
- [ ] **Step 3: Implement.**
  - **att5:** the mirror's order puts the capability skip first, then exclusions, then injury. In that order: `if (capability != null && !EquipmentCapability.canPerform(resolved['equipment_needed'], capability)) continue;`. A placeholder (name absent from the library) builds `['bodyweight']` and stays allowed.
  - **`resolve`:** `if (capability != null && !EquipmentCapability.canOfferInPicker(row['equipment_needed'], capability, isCustom: isCustom)) continue;`.
  - Correct the stale comments: `exercise_selector.dart:502-518`, the `buildPinnedDays` docstring `:695-702`, the `resolve` comment `:743-746`, and `plan_engine_flags.dart:388`.
  - **Repoint the existing test** `repeat_phase_pinned_selection_behavioral_test.dart:239-266` (test 5). It pins a `['machines']` row at bodyweight and expects it kept. Repoint it to a synthetic row put into the exercise box, whose `equipment_needed` is performable at bodyweight but whose `equipment_tier` omits bodyweight (no shipped row has that shape: 0 of 285). That keeps the "tier is not re-filtered" property pinned. Never loosen it. Its old expectation is the behaviour this task removes.
- [ ] **Step 4: Run.** The new file → PASS 6/6.
  - Count att5 reaches on the golden grid with `cascade_tracer.dart`, a read-only probe whose count goes in the diagnose doc. If the count is 0, the doc says "latent on the grid".
  - Run `generator_golden_test.dart`: every key matches except `pins|…` keys whose custom row needs kit. The fixture's custom has `[]`, so expect 0 changes. Any other changed key is a real leak: record it in the doc, then re-record with that key named.
- [ ] **Step 5: Mutate**, restoring by byte copy after each:
  - drop the att5 check → test 1 FAILS;
  - drop the pin check → test 3 FAILS;
  - swap `canOfferInPicker` for `canPerform` → test 4 FAILS.
- [ ] **Step 6: Commit** with:
  - the validated diagnose doc;
  - `plan_engine/CLAUDE.md` "A capability filter empties a slot" row corrected;
  - subject `fix(plan-engine): check equipment on the attempt-5 pool and repeat pins`;
  - trailer `closes-diagnose: <id>`.

### Task 2: Core-list fields on the shipped library (seed v13)

**Files:**
- Create:
  - `scripts/data/library_core_fields_v13.json`;
  - `scripts/add_library_core_fields_v13.js`;
  - `test/contracts/exercise_library_core_fields_contract_test.dart`.
- Modify:
  - `assets/data/exercise_library.json`;
  - `seed_service.dart:104`;
  - `exercise_library_schema_contract_test.dart`: `_canonicalKeys`, `_optionalKeys`, and the `35` / `4` counts at `:50-53`.

**Interfaces (row keys read by Task 3):**
- **Required:**
  - `core_levels` (`List<String>` ⊂ {beginner, intermediate, advanced}, may be empty);
  - `discipline` (strength, calisthenics_skill, olympic, plyometric, mobility, cardio, prehab, yoga, conditioning);
  - `gym_availability` (home, standard_gym, well_equipped_gym, specialty);
  - `requires_coaching`, `high_impact` (bool).
- **Optional:**
  - `variant_family`: absent on the 66 discarded rows;
  - `slot_focus`: the 19 rows of Ruling 4;
  - `slot_pattern`: the 12 rows of Ruling 3(a), value = the draft `movement_pattern`;
  - `skill_track`, `skill_step`, `regression_to`, `progression_to`.

- [ ] **Step 1: Build the committed table** from session scratchpad `tag/merged.json`, using `_decision` as the authority (219 keep, 66 discard).
  - **`core_levels`:** the merged value when keep, else `[]`. This clears E144 E195 E223 E234 E265 E293.
  - **`variant_family`:** only when keep.
  - **`slot_focus` / `slot_pattern`:** exactly Rulings 4 and 3(a).
  - **Links:** a link is kept only when it resolves to exactly one shipped row.
  - **`_meta`:** source path and sha256 of the `merged.json` used.
  - **Counts for the tests:** recompute per-level core counts over keep rows (planning count: 73 / 91 / 67).
- [ ] **Step 2: Write the failing contract test.** It checks:
  - every row has the required keys with legal values;
  - `variant_family` is absent iff the row is one of the 66 discarded rows;
  - every discarded row has `core_levels: []`;
  - `slot_focus` and `slot_pattern` sit on exactly the listed ids with the listed values;
  - per-level core counts equal Step 1's;
  - every `regression_to` / `progression_to` resolves to exactly one row.

  Update `_canonicalKeys` (+5 required) and `_optionalKeys` (+7 optional), and change the asserted counts to 40 / 11. Pin the per-level counts as literals once computed (expected 73 / 91 / 67). The frozen reference test from Task 0 already guards existing keys.
- [ ] **Step 3: Run** both tests → FAIL.
- [ ] **Step 4: Implement the script.**
  - Copy the Batch A formatter (`repair_exercise_library_v12.js:164-180`: 2-space JSON, the decimal rule for `met_value` / `cal_per_set_est`) into the new script. That script has no `module.exports` and runs `main()` at load (`:189`).
  - Add keys after the last existing key. The script is idempotent and refuses a missing or extra id.
  - First check that an unchanged round-trip reproduces the shipped bytes.
  - Run it; bump `_exerciseLibraryVersion` to 13.
- [ ] **Step 5: Run** the two contract tests, the frozen reference, `exercise_library_cloud_seeded_test.dart` and the golden → all PASS.
- [ ] **Step 6: Mutate**, restoring after each:
  - `core_levels` → `['beginnr']` on one row → contract FAILS;
  - edit one existing key → reference FAILS.
- [ ] **Step 7: Commit** `feat(library): core-list selection fields on the shipped library (seed v13)`. `docs/naming_conventions.md` §8 gains:
  - **core list** (not the `core` pattern or the Core muscle);
  - `core_levels`, `variant_family`, `discipline`, `gym_availability`;
  - `slot_focus` / `slot_pattern` (ON-only overlays, not `target_focus` / `movement_pattern`);
  - `requires_coaching`, `high_impact`.

### Task 1b: Five safety-direction injury tags (live fix, founder decision 2026-10-22)

Runs after Task 2, so the v13 seed bump delivers it. Both merge in the same PR.

**Files:**
- `assets/data/exercise_library.json`, five rows; additions to `injury_contraindications` only:
  - E061 +knee
  - E070 +shoulder +elbow
  - E121 +wrist +shoulder
  - E127 +lower_back
  - E173 +lower_back
- `test/contracts/injury_undertag_13b_contract_test.dart:55` (E121 pin).
- `test/fixtures/exercise_library_v12_row_hashes.json`, re-recorded for exactly these 5 ids.
- `test/fixtures/generator_golden_hashes.json`, re-recorded for exactly the keys listed in the diagnose doc.
- New: `test/contracts/injury_safety_tags_v13_behavioral_test.dart`.
- New: `docs/diagnoses/2026-10-22-library-injury-undertag-v13-<id>.md`.
  - Template: full, because this is a recurrence of the 13-B under-tag class (`seed_service.dart:87-89`).
  - `related_bugs`: the 13-B diagnose doc (grep `docs/diagnoses/INDEX.md` for "under-tag").

**Writer/reader:**
- **Writer:** the library row's `injury_contraindications`.
- **Readers:**
  - `queryV4` filter 8 (`exercise_repository.dart:411-422`);
  - `ExerciseSelector._isContraindicated` (`exercise_selector.dart:1223-1235`, attempts 5 and pins);
  - the ON `F` via the same predicate.
- **Not a reader:** `WarmupCooldownSelector._moveInjuries`. It keeps its own table, already tags Running `{knee, ankle, hip}`, and its overlap list `mainCascadeOverlapMoves` (Push Up, Band Pull Apart, Baithak) contains none of the five, so its value-agreement test is unaffected.

- [ ] **Step 1: Write the failing test.** For each (row, added token), compute a persona whose OFF plan contains that row without the injury: tier, goal, days, level, phase from the golden grid. Then assert the same persona with `injuries: [token]` contains no such row. Pairs with no such persona (for example, E070 is discipline-excluded only in ON, so check its OFF reach) are asserted on `queryV4` directly: a `queryV4(movementPattern: <row pattern>, injuryExclusions: [token], …)` result excludes the row.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Edit the five rows with the Task 2 script's formatter, in a separate table `scripts/data/library_injury_additions_v13.json` that the script applies. Update the E121 pin.
- [ ] **Step 4: Re-record and check.** Re-record the reference and golden.
  - `git diff` of the reference fixture must touch exactly the five ids.
  - Every changed golden key must be one whose pre-change plan contains a (row, added-token) pair matching the persona's injury. Round 2's OFF simulation expects exactly `injury|shoulder|home_dumbbells|p1` and `…|p2`; recompute before asserting. List the keys in the diagnose doc.
  - The new E121 pin is `['lower_back', 'shoulder', 'wrist']` (sorted).
  - Any other changed key is a defect: stop and investigate.
- [ ] **Step 5: Mutate** by removing E121's `wrist` → its pair FAILS. Restore.
- [ ] **Step 6: Commit** `fix(library): five safety-direction injury tags` with `closes-diagnose: <id>`.

### Task 3: `CoreListSelector`, flag, delegation, trace

**Files:**
- Create: `core_list_selector.dart`, `test/contracts/core_list_pool_behavioral_test.dart`.
- Modify:
  - `plan_engine_flags.dart` (getter beside `:456`);
  - `exercise_selector.dart`;
  - `scripts/exercise_seam_lib.dart` (allowlist 15 → 16 for the new `.getAll()`, with the reason sentence updated at `:59`).

**Interfaces:**
- **Flag:** `PlanEngineFlags.coreListPoolEnabled` → `configBox.get('enable_core_list_pool') == true`, `try/catch` → `false`.
- **`CoreListSelector`** (pure, static):
  - `static bool hasCoreFields(Iterable<Map<String, dynamic>> rows)`: true iff any row has a `core_levels` key.
  - `static final Set<String> improvisedTokens = EquipmentVocab.tierItems['bodyweight']!.toSet()` (`lib/core/utils/equipment_vocab.dart:291-294`: none, bodyweight + the household baseline).
  - `static bool needsImplementPreference(Set<String>? capability, String equipmentTier)`: true iff `(capability ?? EquipmentVocab.tierItems[equipmentTier]?.toSet() ?? {})` has a token outside `improvisedTokens`.
  - `static ({List<Map<String, dynamic>> ordered, String source, bool improvisedRemoved}) rankedPool({required List<Map<String, dynamic>> rows, required MuscleSlot slot, required String level, required int phase, required String equipmentTier, required Set<String>? capability, required Set<String> exclusions, required bool Function(Map<String, dynamic>) isContraindicated, required Set<String> pickedNames, required Set<String> demotedNames, Set<String> softAvoidNames = const {}, bool anyCoreLevel = false})`. `anyCoreLevel` replaces steps 3's level tests with "`core_levels` non-empty" and skips fill.
    - `source` ∈ {`core`, `fill`, `drop`};
    - `ordered` is empty iff `source == 'drop'`.
  - `static String typeFor(Map<String, dynamic> row, MuscleSlot slot)`: `compound` if `exercise_type` contains it, else `isolation` if it contains that, else `slot.exerciseType` (OI-385).
  - `@visibleForTesting static CoreListTrace? debugTrace`. It is written from `exercise_selector.dart`, so that line carries `// ignore: invalid_use_of_visible_for_testing_member`, because a `warning -` line aborts pre-push.
  - Every list field read from Hive (`core_levels`, `slot_focus`, `slot_pattern`, `exercise_type`, `equipment_tier`, `equipment_needed`) arrives as `List<dynamic>`; map it `toString` before comparing.
- **`class CoreListTrace`:**
  - `int delegations`;
  - `final List<CoreListTraceSlot> slots`. Each records: day index, variant 'A'/'B', slot, source, picked id, pool size, `improvisedRemoved`, `nonImprovisedInPool`, the `families` set used for fill, and the picked row's `variant_family`;
  - `final List<({int day, String variant})> copied`, `emergencyAnyLevel` and `refilled`.
- **`ExerciseSelector.pickV4`, first statement:**
  ```dart
  if (PlanEngineFlags.coreListPoolEnabled) {
    final rows = exerciseRepo.getAll();
    if (CoreListSelector.hasCoreFields(rows)) {
      return _pickCoreList(/* same args */, rows: rows);
    }
  }
  ```
  - The OFF body below it is untouched.
  - `_pickCoreList` increments `debugTrace?.delegations`.
- **`_pickCoreList`:**
  - **Variants:** per day, variant A then B. `slotsB == null` reuses A (as `:631`). For B, unless `goal == 'strength'`, A's names are a **soft avoid** (`softAvoidNames`): they sort after every other row instead of being filtered out, so a slot whose only core rows A used repeats A's pick rather than dropping. This differs from OFF's hard exclusion at `:623` (round-2 P1-1). The counterfactual (`batchb/b1_review2.md` "Counterfactual r2b") cut uninjured gym multi-drop lists from 61 to 0.
  - **Avoid names** as `:594-605`: previous phase ∪ `plateauAvoidNames`.
  - **Per slot × `slot.count`:**
    - call `rankedPool` with `isContraindicated: (r) => _isContraindicated(r, injuries)`;
    - on a non-drop, pick `_selectCandidate(ordered, injuries:, applyInjurySubstitutePreference:, avoidNames:)`. `avoidNames` = previous-phase ∪ plateau ∪ `softAvoidNames` ∪ `demotedNames`, all lowercased. `_selectCandidate`'s curated injury-substitute narrowing (`exercise_selector.dart:1029-1043`) would otherwise bypass the soft avoid and L6 for injured users (round-3 P2-3);
    - build `_buildExercise(row, typeOverride: CoreListSelector.typeFor(row, slot))`;
    - record a trace slot.
  - **Empty variants (round-2 P1-1, Ruling 12).** In order:
    1. A variant whose strength list ends EMPTY copies the other variant's list. Recorded in `copied`.
    2. A day whose two variants are both empty re-runs every slot through `rankedPool(anyCoreLevel: true)`: core at ANY level, same `F`. Its picks get trace source `emergency`, and it is recorded in `emergencyAnyLevel`. No retired row can enter, because discarded rows have `core_levels: []` after Task 2.
    3. Copy again if one variant is still empty.
    4. Only if that is still empty does the OFF cascade (`_fillSlots`) run. Recorded in `refilled`. That brings what OFF brings today (no regression versus OFF), including rows retired before Batch C deletes them. Round 3's wider sweep found this in 8 of 6,336 multi-injury keys (bodyweight beginner, shoulder + lower_back).

    `copied`, `emergencyAnyLevel` and `refilled` record one entry per (day, variant) (M-3).
  - **L6:** `demotedNames = phase >= 2 ? TrainingHistoryAnalyzer.demotedExercises() : {}`. Names are original-case, compared exactly, as `_applyHistoryAdjustments` does (`exercise_selector.dart:877`). The OFF post-pass is not run on ON picks, because it queries `queryV4` and would swap in non-core rows.

**The `rankedPool` algorithm (exact):**

1. **Hard filter `F`** over `rows`. A row passes when all of these hold:
   - `slot_pattern ?? movement_pattern` contains `slot.movementPattern`;
   - a `core_levels` key is present;
   - `discipline` ∉ {calisthenics_skill, olympic};
   - equipment:
     - if `capability != null`: `canPerform(equipment_needed, capability)`;
     - else the `queryV4` tier rule (`exercise_repository.dart:370-381`): `equipment_tier` non-empty and lacking `equipmentTier` → reject;
   - no `EquipmentVocab.fromProfile(equipment_needed)` token in `exclusions`;
   - `!isContraindicated(row)`;
   - `name` ∉ `pickedNames`.
2. **Target `T(row)`:** any element of `slot_focus ?? target_focus` contains `slot.targetMuscle` (case-insensitive), else any `primary_muscles` element does (as `queryV4:311-324`).
3. **Rank** with `rank = {beginner: 0, intermediate: 1, advanced: 2}`.
   - **Core pool:** `P1 = F ∩ T ∩ core_levels contains level`.
   - **Family fill**, only if `P1` is empty:
     - `families` = the `variant_family` of rows with pattern ∧ `T` ∧ `core_levels` containing `level`, ignoring every user filter;
     - `P2 = F ∩ T ∩ variant_family ∈ families ∩ (no element of core_levels has rank ≤ rank[level]) ∩ suitable_for contains the capitalised level`.

     So a row core only at a HIGHER level may fill; a lower-core row never does (D6).
   - If both are empty → `drop`.
4. **Improvised filter (OI-387/388):**
   - **Applies when:** `needsImplementPreference(capability, equipmentTier)` and the slot pattern ∈ {elbow_flexion, elbow_extension, shoulder_isolation, horizontal_pull, vertical_pull}.
   - **Removes:** rows whose `equipment_needed` ⊆ `improvisedTokens`.
   - **Guard:** only when at least one other row remains; `improvisedRemoved` = whether any row was removed.
5. **Order**: stable, ties by `id` ascending:
   - L6 first: rows whose `name` ∈ `demotedNames` go after every non-demoted row. This is a partition applied before keys a–e, which matches the OFF guarantee (`exercise_selector.dart:874-901`: swap to any non-demoted alternative).
   - Then the soft avoid: rows whose `name` ∈ `softAvoidNames` go after the rest (still before demoted rows).
   - a. Phase 1: `is_foundational == true` first (Ruling 7).
   - b. Sub-focus (OI-386), when `slot.subFocus != null`:
     - `cable` → `equipment_needed` contains `cables`, the canonical token (`equipment_vocab.dart:35,110`);
     - `isolation` → `exercise_type` contains `isolation`;
     - otherwise a label in `(slot_focus ?? target_focus) ∪ primary_muscles` whose normalised form contains the normalised `"$targetMuscle $subFocus"`. To normalise: lowercase; `_ / ( )` → space; collapse spaces.

     Matching rows go first.
   - c. `exercise_type` contains `slot.exerciseType` first.
   - d. `priority_tier` ascending (missing = 3).
   - e. `is_foundational == true` first.

- [ ] **Step 1: Write the failing tests.** Real shipped library in Hive; flag via `configBox.put('enable_core_list_pool', true)`; personas through `generateV4`; trace via `CoreListSelector.debugTrace = CoreListTrace()` in `setUp`, nulled in `tearDown`. Each test names the change that makes it fail.
  - **`OFF is the golden`:** flag absent → 4 golden keys match; `debugTrace.delegations == 0`.
  - **`every ON pick is core for the effective level, or a fill core at no level at or below it`:**
    - personas: 12 (tier × level) combos, build_muscle 4d, phases 1 and 5;
    - a `core` source must be core at the level;
    - a `fill` source must have no `core_levels` element with rank ≤ the level, must share a family, and must have `suitable_for`.
  - **`never a lower level through fill`:**
    - persona: bodyweight intermediate, phase 1, the computed fill-path persona;
    - assert no pick has a `core_levels` element of lower rank;
    - assert at least one `fill` trace entry exists (compute first, so the test is not vacuous).
  - **`no skill or olympic row`:** crafted `rankedPool` unit. A row with `discipline: calisthenics_skill`, core at the level, matching pattern and target → never in the pool. On shipped data the clause is unobservable: all 10 skill/olympic rows have `core_levels: []` (round-2 P2-3). The real-data check that E069 E070 E071 E072 E073 E074 E086 E101 E179 E180 never appear stays, as presence evidence.
  - **`ON honours injuries`:** for each of knee / shoulder / lower_back × 4 tiers, no picked row's `injury_contraindications` contains the injury.
  - **`ON honours exclusions`:** for ['barbell'] at full_gym, no pick needs barbell.
  - **`ON with capability null uses the tier rule`:**
    - set `disable_equipment_capability_floor`;
    - bodyweight beginner: no picked row lacks 'bodyweight' in `equipment_tier`;
    - at least one pick exists.
  - **`owned equipment turns the implement preference on`:**
    - bodyweight beginner owning ['dumbbells'], **3 days** (the beginner 4-day split has no elbow or shoulder_isolation slot);
    - the elbow_flexion pick is not E268 when a dumbbell curl is in the pool (trace `improvisedRemoved == true`);
    - with nothing owned, E268 may be picked (compute which first).
  - **`OI-388`:** full_gym beginner → no E268 / E270 pick.
  - **`OI-387`:**
    - home_dumbbells and full_gym with `previousPhaseByDay` set: no pick from E272 E273 E276 E277 E289 E290 in a trace slot where `improvisedRemoved` was possible (non-improvised rows in the pool);
    - bodyweight beginner, phase 2, **5 days**: the Lateral Delts slot picks E273 or E289.
  - **`OI-385`:**
    - compute a calisthenics-typed row that is core for a named persona and wins a compound slot there;
    - its `PlannedExercise.exerciseType` is `compound`.
  - **`OI-386`:**
    - unit: a crafted `Triceps (Long Head)` row ranks first for `Triceps / long_head`;
    - real data: a `Core / obliques` slot for an intermediate picks a row whose labels contain Core/Obliques (E090 or E175; compute which).
  - **`slot_pattern fills the Front Delts isolation slot`:** a full_gym intermediate `Front Delts / shoulder_isolation` slot picks E015 (trace source `core`).
  - **`family fill, then drop`:** unit tests on `rankedPool`.
  - **`stale library delegates to OFF`:** rows stripped of `core_levels` → `delegations == 0` and output hash equals OFF.
  - **`mixed library`:** one row with `core_levels`, the rest stripped → `delegations == 1`.
  - **`community and custom rows never selected`:** a `source: 'community'` row matching pattern and target → never picked; no crash.
  - **`B soft-avoids A`:** crafted Legs day with ONE core Glutes row → A and B both pick it, and B has no drop. With the hard exclusion (mutation), B drops it → FAIL.
  - **`an emptied variant copies the other`:** crafted rows where B's slots all drop and A's do not → B equals A; `copied` has the day.
  - **`both empty → any-level core, never retired`:** crafted rows where the day's only matching rows are core at a lower level plus one retired row (`core_levels: []`, no family) → picks are the lower-level core rows, never the retired one; `emergencyAnyLevel` has the day; `refilled` is empty.
  - **`OFF cascade only as the last resort`:** no core row matches at all → `refilled` has the day.
  - **`injured user keeps the soft avoid and L6`:** shoulder-injured persona with the injury-substitute preference on. A demoted name and an A name are not picked when a non-avoided curated substitute exists (round-3 P2-3).
  - **`cables sub-focus`:** crafted `rankedPool` unit. For a `Rear Delts / cable` slot, a `['cables']` row ranks before a `['dumbbells']` row of equal priority (round-3 P2-6).
  - **`variety levers work ON`:**
    - L6: a demoted name is not picked when another candidate exists;
    - cross-phase: phase 2 with `previousPhaseByDay` differs from phase 2 without it on a slot with ≥ 2 candidates;
    - plateau: a name in `plateauAvoidNames` is not picked when a sibling exists.
- [ ] **Step 2: Run** → the ON tests FAIL; `OFF is the golden` PASSES.
- [ ] **Step 3: Implement** the getter, the selector, the trace, `_pickCoreList`, `typeOverride` (default `null` → today's `_extractFirst`), and the seam allowlist.
- [ ] **Step 4: Run** the new file → PASS. Then the golden → PASS, `check_exercise_seams.dart` → PASS, `flutter analyze lib/` → 0 issues.
- [ ] **Step 5: Mutate**, one at a time with a byte-copy restore, and ledger each:

  | Mutation | Test that must FAIL |
  |---|---|
  | drop the discipline clause | skill test |
  | P2 rank rule → `!core_levels.contains(level)` | lower-level fill test |
  | drop the injury clause | injury test |
  | drop the exclusion clause | exclusion test |
  | drop the null-capability tier rule | capability-null test |
  | key the partition on `equipmentTier != 'bodyweight'` | owned-equipment test |
  | remove `hasCoreFields` | stale-library test |
  | B hard-excludes A's names | `B soft-avoids A` |
  | remove the copy step | `an emptied variant copies the other` |
  | `anyCoreLevel` admits `core_levels: []` | `both empty → any-level core` |
  | drop the L6 partition | variety (L6) |
  | drop `previousPhaseByDay` from avoid | variety (cross-phase) |
  | drop `plateauAvoidNames` | variety (plateau) |
  | `typeFor` returns `slot.exerciseType` always | OI-385 |
  | soft-avoid sorts after demoted rows | `B soft-avoids A` |
  | omit soft/demoted from `avoidNames` | `injured user keeps the soft avoid and L6` |
  | `cables` → `cable` | `cables sub-focus` |
  | read `movement_pattern` instead of `slot_pattern ?? …` | Front Delts test |
- [ ] **Step 6: Commit** `feat(plan-engine): core-list pool behind enable_core_list_pool (ship-dark)`. Ledger entry in `docs/ship_dark_pending_review.yaml`:
  - `flag: enable_core_list_pool`, `branch: library-batch-b`;
  - `build_commit: <resolved in the Task 6 docs commit>`, `build_date: 2026-10-22`;
  - `flip_reviewed: false`, `flip_commit: null`;
  - `note`, listing the flip criteria from Task 4's "reported, not gated" block: `emergencyAnyLevel == 0` after Batch C, plus the founder's call on promoted and injured thin sessions.

### Task 4: ON-world gate over the real generator

**Files:** `test/plan_generator/core_list_pool_gate_test.dart` (`library;`, `@Timeout(Duration(minutes: 10))`, one `test()` per tier), generated report.

- [ ] **Step 1: Write the gate.** Flag ON, `generatorGoldenPersonas()`, real `generateV4`, trace attached.
  - **Hard counts that must be 0:**
    - equipment violations: `canPerform` false, or the tier rule when null;
    - discipline violations;
    - level violations (as Task 3 test 2), excluding trace source `emergency` (round-3 P2-2);
    - contraindicated picks over injury personas;
    - excluded-equipment picks;
    - improvised picks in trace slots where `needsImplementPreference` held and non-improvised rows existed;
    - variants with zero strength exercises after the empty-variant steps;
    - `refilled` entries (OFF cascade) over the 998 personas;
    - picks of retired rows (`core_levels: []` and no `variant_family`) over the 998 personas;
    - full_gym and basic_gym lists with more than 1 dropped slot, over **uninjured** personas (counterfactual: 0 of 480).
  - **Reported, not gated** (these are flip criteria in the ship-dark ledger; they are expected to fall once Batch C's 84 core rows land):
    - `emergencyAnyLevel` days (counterfactual: 2, bodyweight shoulder-injured Pull);
    - a **multi-injury sweep** (every tier × level × days, phases 1–2, every pair of {knee, shoulder, lower_back, wrist}): `emergencyAnyLevel` and `refilled` counts, and any retired picks. The gate's hard zeros cover the 998 personas only, and the report says so (round-3 P2-4);
    - the B-repeats-A rate per tier × level, which is the cost of the soft avoid (round-3 P2-5);
    - `copied` variants;
    - injured personas' drops and list sizes, broken out separately (counterfactual: 8 basic_gym injury lists drop 2+ slots);
    - thin sessions for promoted users (bodyweight advanced mean 4.71 exercises per list vs 8.69 OFF; D6 accepts these gaps);
    - core-vs-`suitable_for` disagreements E010 E020 E045 E134 E255 (round-2 P2-10);
    - high-impact and requires-coaching picks.
  - **Report** (`WRITE_CORE_LIST_REPORT=1`), per tier × effective level:
    - core / fill / drop counts and drop slot types;
    - p5, min and mean strength exercises per day, ON vs OFF;
    - sub-focus match rate per sub-focus;
    - high-impact and requires-coaching picks;
    - top 20 repeated picks.
- [ ] **Step 2: Run** with the report env → PASS. Read the report and copy its drop and fill counts into the plan-review record. A non-zero hard count is fixed in the selector or data, with a failing test first, before this commit.
- [ ] **Step 3: Mutate:**
  - disable `canPerform` in `F` → equipment count FAILS;
  - drop the injury clause → contraindicated count FAILS.
- [ ] **Step 4: Commit** `test(plan-engine): ON-world gate and report for the core-list pool`.

### Task 5: OI board and spec alignment

**Files:** `docs/audit/open_issues.md`, the spec.

- [ ] **Step 1: OI board.**
  - OI-385/386/387/388:
    - keep OPEN;
    - "Blocked on" → the flip of `enable_core_list_pool`;
    - "Verified" → today with Task 3 test names;
    - amend OI-388's done-when to say home_dumbbells users also leave improvised rows when they own an implement.
  - Mint the `beat-my-coach` OI (Ruling 8) via `sh scripts/mint_oi.sh "<title>"`.
  - Mint the finisher OI: "Cardio finisher is generated but no screen shows it". Body:
    - founder 2026-10-22: show it after the main lifts, injury-safe; injured users get Stationary Bike Sprints in a gym and no finisher at home;
    - `CardioFinisher.attach` takes no injuries today;
    - needs the founder's rule-14 OK for the `plan_generator.dart` pass-through;
    - must set B2's `finisherSeconds`.
  - Rebuild `OPEN_INDEX.md`.
- [ ] **Step 2: Spec edits.**
  - §9 row A → SHIPPED (PR #147 `08c077d1`).
  - Row B → split B1 / B2.
  - §3.2 → tokens move to Batch D (Ruling 1).
  - §3.3 → cloud carries a subset of columns (Ruling 2).
  - §3.1 → `slot_focus` / `slot_pattern` overlays until the flip, plus `elite` / `Calisthenics` not applied (Rulings 3 and 4).
  - §4.1 → Phase 1 foundational is a preference (Ruling 7, founder 2026-10-22).
  - §9 row B → no universal pool in ON (Ruling 5).
  - §5 per-session citation → Remmert, Pelland et al. 2025 (SportRxiv preprint).
  - Warm-up repoint → row C (Ruling 6).
- [ ] **Step 3: Commit** `docs: Batch B1 board and spec alignment`.

### Task 6: Registry, docs, closure, review record, gate loop, PR

- [ ] **Step 1: SoT registry.**
  - New concept `core_list_pool`:
    - writer: the v13 script + `seed_service.dart`;
    - readers: `core_list_selector.dart`, `_pickCoreList`;
    - `behavioral_test_path`: the Task 3 file.
  - Add `core_list_selector.dart` as a reader on the injury, capability, exclusion and variety concepts.
  - Update the `exercise_library_schema` entry (key counts, v13).
- [ ] **Step 2: Docs.**
  - `plan_engine/CLAUDE.md` stage 3: the ON delegation and pool contract, in ≤ 6 lines.
  - `docs/architecture/plan-engine-detail.md`: the narrative.
  - Run `dart run scripts/check_context_artifact_budget.dart`.
- [ ] **Step 3: Closure YAML** `docs/audit/library-core-list-pool.closure.yaml` (Gate 40):
  - **Task items:** `closed_in_commit`.
  - **Rulings:**
    - 1, 6 and 10: `upstream_blocked` with blocker and `reopen_when`;
    - 2 and 5: `verified_clean`;
    - 3(a): `closed_in_commit`;
    - 3(b): `closed_in_commit` (Task 1b);
    - 3(c) and 3(d): `verified_clean`;
    - 8: `blocked_on_user`;
    - 11: `upstream_blocked` (B2 Task 6).
  - **OIs:** OI-385..388 `upstream_blocked`; reopen at the flip.
  - **Floor tests:** "Batch C removes E263 / E265 and the att5 floor test in `equipment_exclusion_filter_behavioral_test.dart` must be repointed": `upstream_blocked`; reopens at Batch C's plan.
  - **Ruling 12 and the Task 4 reported items:** `upstream_blocked`; reopen at Batch C / the flip.
  - **Task 1's existing-test repoint and the `slot_pattern` flip copy:** `closed_in_commit` / `upstream_blocked` (flip).
- [ ] **Step 4: Plan-review record** `docs/plan-reviews/<recordSlug of library-batch-b>.md`. It needs:
  - `---` frontmatter, `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`;
  - the Task 4 counts;
  - the ledger's `build_commit` resolved.

  Commit it after the B-pass review file, in its own commit (code-review skill: plan-review citation breaks the hash fixed point).
- [ ] **Step 5: Full gate loop (§4.12.8) and PR.**
  - `flutter analyze lib/`, `TZ=Asia/Kolkata flutter test`, `sh scripts/pre-commit.sh`.
  - `/code-review` (B-pass), then fix its findings.
  - `scripts/safe_push.sh`, `gh pr create`, `get_status` → `set_monitor`.
- [ ] **Step 6: Flip.** It is owed later as a separate reviewed commit, expected after Batch C adds the 84 core rows not shipped yet (56 / 47 / 32), with the report as evidence.

---

## Round-3 resolution (b1_review3.md, verdict converged)

**P2:**
- 1: Ruling 12 is marked for founder confirmation; §4.2 is edited if it is confirmed.
- 2: trace source `emergency`, exempt from the level count.
- 3: soft-avoid and demoted names are also passed as `avoidNames`, plus an injured test.
- 4: the multi-injury sweep is reported, and the gate width is stated.
- 5: the B-repeats-A rate is reported.
- 6: `cables` unit test and mutation.

**Mechanical:** M-1 to M-4 applied.

## Round-2 resolution (b1_review2.md)

**P1:**
- **P1-1:** B soft-avoids A; an empty variant copies the other; a doubly-empty day takes any-level core rows; the OFF cascade runs last; four tests and three mutations.
- **P1-2:** the gym multi-drop count covers uninjured personas (counterfactual 0). Injured, emergency, copied and thin-session counts are reported as flip criteria.

**P2:**
- 1: test (5) repointed; docstrings fixed.
- 2: L6 is a partition applied first.
- 3: the skill test is a crafted unit.
- 4: the mutation table names the stale-library test.
- 5: trace gains `nonImprovisedInPool`, `families`, the pick's family.
- 6: `cables`.
- 7: OFF wording; Task 1b's oracle tightened.
- 8: injured personas broken out; flip carries the founder's call.
- 9: 3-day / 5-day personas.
- 10: suitable_for disagreements reported.

**Mechanical:** M1–M13 applied. M12: literals pinned. M13: covered by the soft-avoid rule.

## Round-1 resolution (b1_review1.md)

**P0:**
- **P0-1:** P2 rank rule; level oracle in Task 3 test 2 and Task 4; fill-path persona; mutation.
- **P0-2:** `canOfferInPicker` with `isCustom`; two custom-pin tests; golden pin personas.

**P1:**
- **P1-1:** `needsImplementPreference` keyed on capability; owned-equipment personas and test.
- **P1-2:** tier rule when capability is null; test and mutation.
- **P1-3:** shared `_isContraindicated` passed in; injury, exclusion and null tests; gate counts; mutations.
- **P1-4:** the trace `delegations` makes the stale-library test discriminate; mixed-library test added.
- **P1-5:** `CoreListSelector.debugTrace`.
- **P1-6:** Ruling 3(a) `slot_pattern` on 12 rows; Ruling 3(b) safety tags applied live (Task 1b, founder decision); 3(c) / 3(d) terminal states; Front Delts test.
- **P1-7:** frozen per-row reference fixture.

**P2:**
- 1: att5 order, comments, att5 reach count, kill switch.
- 2: schema test names and counts; plate test dropped.
- 3: formatter copied, round-trip check, `_meta` sha.
- 4: per-tier tests, 10 min timeout, golden only at task ends.
- 5: `_meta`, re-record policy, owned and pin personas.
- 6: `_selectCandidate` reused; L6 original case.
- 7: refill is an emergency path, per variant; gate requires 0.
- 8: test wording fixed from computed data; OI-386 real-data test; slot_focus +5 sub-focus rows; OI-388 text amended.
- 9: gym drop ceiling; p5 / min reported.
- 10: high-impact and coaching picks reported.
- 11: spec edits for Rulings 3, 4, 5, 7.
- 12: review-record step, ledger fields, closure entries, SoT readers, plateau ON test, `$env` note, E261 wording, link assertion.
