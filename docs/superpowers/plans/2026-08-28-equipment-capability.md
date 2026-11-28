# Equipment Capability Model — Implementation Plan (×2-review converged)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user on the Bodyweight tier is never prescribed or offered an exercise requiring equipment they were told they do not need — anywhere in the app.

**Architecture:** Twelve canonical equipment tokens are added, derived from the library's own pre-normalization vocabulary recovered from git. A tier-agnostic predicate `EquipmentCapability.canPerform(equipmentNeeded, effective)` replaces tier-string reasoning, where `effective = tierItems[tier] ∪ owned − exclusions`. It is threaded as a **required** parameter through every generator seam so a missed one fails to compile, passed explicitly to the five widget/service seams the compiler cannot reach, and its coverage is enforced by two new enumeration gates rather than by anyone's judgement.

**Tech Stack:** Dart / Flutter, Hive, Riverpod, Supabase Postgres + Edge Functions. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-28-equipment-capability-design.md`. ⚠ The design says migration **122** and cites `_restoreUserProfile` at `:505/:512/:558-570`; both are wrong and corrected here (124, and `:567-647`/`:574`/`:622-623`). Task 13 fixes the design text.

**Review history:** round 1 (3 lenses) returned 20 P0; round 2 (2 lenses) returned 5, of which two were defects introduced by the round-1 rewrite. Changes from round 2 are marked **[R2]**; round-1 changes **[R1]**. ~35 round-1 corrections were independently verified correct in round 2.

---

## Ordering — corrected **[R2]**

Round 1 established that retag-first is harmful: bodyweight `horizontal_pull` drops to one Intermediate-only row, so every bodyweight beginner's pull slot falls through to the tier-dropping attempt 4 and returns a barbell row.

Round 1's fix — flip the flag *before* the data — was **also wrong**, and round 2 traced why. `universalPoolV4['vertical_pull']` is `['Pull Up', 'Chin Up', 'Inverted Row']`. After the retag: Pull Up and Chin Up are `['pull-up bar']`; `Inverted Row`'s recovered value is `['Barbell on Rack or TRX']` → `['suspension trainer']`; and the audit corrects `Negative Pull Up` — the only capability-passing `vertical_pull` row in the library — to `['pull-up bar']`. All four skip, the loop exhausts, and `_cascadeFill` returns null (`exercise_selector.dart:1196`). With the flag already ON, **every bodyweight persona loses their vertical_pull slot** until the replacement exercise lands.

**The real fix is atomicity, not sequencing.** The data change and the exercises that keep every pattern non-empty are one unit and land in one commit (Task 8). The flag flips after them (Task 9).

Corrected order: vocabulary → predicate → **enumeration gates** → threading (OFF) → non-generator seams → **data + exercises, atomic** → flip → persistence → records.

⚠ Two claims from the round-1 draft are struck: *"attempts 1–3 are untouched"* is false — the four over-tagged rows (Standing Calf Raise, Reverse Crunch, Decline Push Up, Chin Up) are tier-selectable and capability-rejected, which is the point of the batch, not a side effect. And *"a strict improvement"* overstates it; flipping carries a named tail risk that Task 9 must measure.

**The scorecard cannot referee any of this. [R2]** `scorecard_gate_test.dart` runs through `cascade_tracer.dart` → `query_v4_mirror.dart`, which reads no flag and calls no production selector. The round-1 draft said this in its Ordering section and then made the scorecard the verification two tasks later. Verification is the Task 6 behavioural test, which drives the real `pickV4`.

---

## Task 0: PRECONDITIONS — founder authorizations

These are hard blockers, not mid-batch escalations. Round 1 found that scheduling the rule-14 stop inside Task 6 would leave five later tasks committing onto a non-compiling tree, and `pre-push.sh` runs `flutter analyze` unconditionally above every early exit — the whole batch becomes unpushable.

- [ ] **P0-a — Rule 14: authorization to modify `plan_generator.dart`.** Exactly three edits, verified as sufficient to reach both branches of the `:175-206` ternary: pass `capability:` at `:176` (`buildPinnedDays`) and `:191` (`pickV4`), and compute the set beside the existing `resolveEquipmentExclusions` call at **`:140-142`** (`:141-143` in earlier drafts was off by one **[R2]**).
- [ ] **P0-b — Migration 124 apply authorization** (§4.3: plan approval ≠ deploy approval).
- [ ] **P0-c — Migration 125 apply authorization. [R2]** `check_migration_ledger_paired.dart` couples the *file's commit* to a `backups/applied_migrations.json` entry carrying `migration`, `applied_at`, `hash`, `applier`. So 125 cannot even be committed until it is applied — the authorization is a precondition, not a Task-12 detail.
- [ ] **P0-d — Worktree state.** Verified: `HEAD == origin/main == 66b88fcf`, 0 ahead. The old "rebase off orphaned `83509ee1`" instruction is **done — do not re-run it**. Local `main` is `acd6c818`, 2 ahead of origin, and is the merge target. Re-check before merging.
- [ ] **P0-e — Batch size, acknowledged.** Eleven enforcement seams, ~18 new exercises, a 117-row triage, two new gates, two migrations.

## Global Constraints

- **Blast radius `platform`** (verified by live classifier over the full touched set). ×2 review + `bpass: accepted`.
- **§4.6:** enforcement behind `enable_equipment_capability_floor`, default OFF, flipped in Task 9.
- **No `<6hex>` literals** in commit bodies — `commit-msg.sh` greps `[a-f0-9]{6,}`.
- **Migrations are 124 and 125.** 122 and 123 exist and were applied 2026-08-26.
- **§4.13** commits via `safe_commit.sh`. **OI-86** never two test suites at once. **Never `TZ=UTC`.**

---

## Task 1: The four vocabulary constants, in lockstep

**Files:** `equipment_vocab.dart`; `scripts/check_equipment_vocab_lockstep.dart` + `scripts/equipment_vocab_lockstep_lib.dart` (new); `test/scripts/equipment_vocab_lockstep_lib_test.dart` (new); `test/contracts/equipment_vocab_library_contract_test.dart` (7 rewrites)

- [ ] **Step 1–2:** Failing gate test in `test/scripts/`, matching the convention every `mutation_proven` ledger entry uses. It must contain `expect(violations, isNotEmpty)` — verified as an accepted red-path form — and reference `check_equipment_vocab_lockstep` by name in source.
- [ ] **Step 3: Add the 12 tokens**, `precedenceOrder` / `aliasKeys` getters, and the 24-entry `_precedence`:

  ```
   1 bodyweight        7 resistance band  13 kettlebell          19 ez-bar
   2 wall              8 jump rope        14 suspension trainer  20 battle ropes
   3 towel             9 ab wheel         15 parallel bars       21 cables
   4 foot anchor      10 medicine ball    16 pull-up bar         22 machines
   5 doorway          11 plyo box         17 bench               23 smith machine
   6 elevated surface 12 dumbbells        18 barbell             24 cardio machine
  ```

  This preserves the relative order of all 12 existing tokens, so no existing OR-compound changes resolution among them — a safety property worth asserting in the test. **[R2]**

- [ ] **Step 4: `_aliases` — 8 deletions, 9 re-points, 2 KEPT. [R2]**
  **Delete (shadowed — `_mapPart:151` checks canonical first):** `medicine ball` `:126`, `wall` `:127`, `doorway` `:128`, `elevated surface` `:131`, `ab wheel` `:135`, `jump rope` `:136`, `parallel bars` `:137`, `battle ropes` `:99`.
  **Re-point:** `trx`/`trx suspension trainer` `:138-139` → `suspension trainer`; `box`/`box (30-45cm)`/`box (30-60cm)` `:123-125` → `plyo box`; `partner` `:145`/`nordic attachment` `:146` → `foot anchor`; `chair` `:129` → `elevated surface`; `pole` `:143` → `elevated surface`; `broomstick` `:144` → `towel`.
  ⚠ **KEEP `yoga mat` `:133` and `foam roller` `:134` mapping to `bodyweight`.** The round-1 draft deleted them. They are not shadowed — neither becomes canonical — and deleting them opens a fail-closed hole at two live free-text seams (`normalizedEquipmentRow:233` for community rows, `createCustomExercise` for user/AI text), where `[]` now means *invisible* rather than *permissive*. Decision 9 removes them from **data**, which is Task 8, not from the vocabulary.
- [ ] **Step 5: Rewrite SEVEN assertions** in `equipment_vocab_library_contract_test.dart`, each independently re-derived twice: `:77` `Box or Bench`→`plyo box`; `:78` `Barbell on Rack or TRX`→`suspension trainer`; `:87` `Battle Ropes`→`battle ropes`; `:88` `Box (30-45cm)`→`plyo box`; `:89` `Medicine Ball`→`medicine ball`; `:110`→`['dumbbells','plyo box']`; `:111-112`→`['bodyweight','foot anchor']`. Remove the stale `// E044` at `:110` and `// E148 (dedup)` at `:112`. No eighth assertion is affected — `:72-76`, `:80-83`, `:90-92`, `:115-117` all still hold.
- [ ] **Step 6: Ledger entry — top-level mapping key, block list:**

  ```yaml
  check_equipment_vocab_lockstep.dart:
    mutation_proven: true
    test_path:
      - test/scripts/equipment_vocab_lockstep_lib_test.dart
    evidence: "<neutered X; N tests reddened — fill after Step 7>"
  ```

  No `// Gate: N` and no wiring — `pre-commit.sh:324` and `test.yml:234` both glob `scripts/check_*.dart`, and `GATE_INDEX.md` regenerates automatically.
- [ ] **Step 7: Mutation-prove; Step 8: commit** `feat(equipment): 12 canonical tokens with _precedence/_chipLabels/_aliases in lockstep`.

## Task 2: Two lists — grants vs questions

- [ ] **Step 1: DECIDE FIRST. [R2]** Design §3 says gym-tier Customize is unchanged; adding accessory tokens to `basic_gym`/`full_gym` would add ~7 chips there. Resolve before writing the test — the round-1 draft wrote the assertion in Step 1 and scheduled the decision in Step 4.
- [ ] **Step 2–3:** Failing test, then add the baseline to all four `tierItems`. ⚠ **Append after index 1** — `equipment_chip_vocab_contract_test.dart:26-28` asserts `list.take(2) == ['none','bodyweight']` for every tier. **[R2]**
- [ ] **Step 4: `tierExcludableItems` has FIVE readers, not one. [R2]** `equipment_vocab.dart:308` (inside `pruneToTier`), `edit_profile_screen.dart:418`, `edit_profile_screen.dart:1309`, and `equipment_chip_vocab_contract_test.dart:33,42,44,46,48` + `:71-78`. Migrate all of them, and note `:1309` is re-pointed again in Task 11 — the two tasks must agree.
- [ ] **Step 5:** Extend `floorSanitizedExclusions` to strip `wall`, making it un-excludable exactly as `bodyweight` is. ⚠ Phrase it as **stripped from the exclusion set**, not "survives" — two round-1 steps described the same line in opposite words. **[R2]**
- [ ] **Step 6:** Rewrite `:25`, `:42`, `:46`, `:48`; compute lengths, do not guess. **Step 7:** `flutter test test/contracts/` — passes because the library's `equipment_needed` holds only the 11 old tokens, so widening `tierItems` changes no row's `derived`. **Step 8:** commit.

## Task 3: `effectiveItems` and the capability predicate

- [ ] **Steps 1–4:** 15 tests. Fail-closed on null / empty / unmappable / non-list; `none` stripped at the boundary; read-side reconcile (`pruneToTier` has one call site and is bypassed by onboarding and cloud restore).
- [ ] **Step 5: Define the tier-miss branch. [R2]** `tierItems` has four keys; `equipment_access` is read at 14 sites with 4 defaults and can hold legacy free text. An unmapped tier must fail **open** to the widest set — a tier miss is a data problem, not a capability claim, and failing closed there drops every row.
- [ ] **Step 6:** Drop the tautological `expect(e.where((t) => t == 'bench').length, 1)` on a Set — it cannot fail. **Step 7:** mutation-prove (4 redden). **Step 8:** commit.

## Task 4: The two enumeration gates **[R2] — new**

Seams found per review round: **5 → 7 → 10 → 11**. That is a method failure, not a counting failure. Both gates ship `--warn-only` first, per §4.11 (gate before refactor), and flip to hard-fail after Task 8.

- [ ] **Gate A — seam enumeration.** Every `PlannedExercise(` construction site and every `repo.getAll()` / `repo.search(` / `repo.queryV4(` / `getCustomExercises(` call in `lib/`, checked against an allowlist of sites known to apply a capability filter. A new emission site fails the gate until someone decides what it does.
- [ ] **Gate B — library equipment audit.** Scan each row's `name`, `coaching_cues`, `common_mistakes`, `pro_tip`, `indian_alternative`, `warmup_protocol` for equipment nouns and flag any whose canonical token is absent from that row's `equipment_needed`. Evidence from **outside** the field the predicate reads — which is the only way to catch a wrong row. Measured: **82 of 259 flagged**, true positives falling straight out (Jump Rope, Ab Wheel Rollout, Dip (Parallel Bars), Chest Dip, Handstand Hold, Box Jump, Dragon Flag). Scope the required pass to the **117 rows carrying the bodyweight tier**. False positives are real (E002 flags on a `pro_tip` mentioning a barbell) — this is triage input, not a verdict.
- [ ] Ledger entries for both; mutation-prove both; commit.

## Task 5: The capability producer, and threading it through the generator

**Requires Task 0 P0-a.**

- [ ] **Step 1:** Failing behavioural test driving the real `pickV4`. Oracle reads `e.equipmentNeeded` (`models.dart:129`; the field is `exerciseName`, there is no `name`). All 11 patterns.
- [ ] **Step 2:** Flag `enable_equipment_capability_floor`, default OFF.
- [ ] **Step 3:** Compute the set at `plan_generator.dart:140-142` from tier + `equipment_owned` + `equipment_exclusions`.
- [ ] **Step 4: OFF = skip the call. [R2]** A "universal set" does **not** work: `canPerform` returns false on `needed.isEmpty` *regardless of `effective`*, so it would still drop rows whose `equipment_needed` normalizes to `[]`. Only skipping the filter is byte-identical when OFF. The round-1 draft offered these as equivalent options.
- [ ] **Step 5:** Thread `required Set<String> capability`. Counts verified twice: `queryV4` 5 lib / 0 test; `pickV4` 2 lib + 3 test (`injury_safe_omission_production_test.dart:98,114,128`); `buildPinnedDays` 1 lib.
- [ ] **Step 6: Scope to bodyweight in `_cascadeFill`, and give seams 3 and 4 the same gate. [R2]** At attempt 4 `equipmentTier` is not passed, so `queryV4` cannot distinguish callers. `buildPinnedDays.resolve()` (`:707-738`) and `_applyHistoryAdjustments` (`:815`) are not `_cascadeFill` and need the rule stated explicitly, or they enforce for gym users too — which with fail-closed silently drops unmappable community and custom rows at every tier.
- [ ] **Step 7: Close seam 5.** Convert `exercise_repository.dart:302`'s `return true` to a fall-through, following the precedent at `:285-296`. ⚠ **0 of 259 rows have empty `equipment_tier`, so no existing test can redden. [R2]** Rule 21 requires a synthetic no-tier row in the regression test or the fix is unproven.
- [ ] **Step 8:** Attempt 5 — place the check beside the existing exclusion drop at `:1174-1178`, where `resolved` exists. `:1156` has nothing to test. Note `_buildUniversalFallback` hardcodes `equipmentNeeded: const ['bodyweight']` (`:403`), so a pool name absent from the library bypasses the check and self-reports as bodyweight.
- [ ] **Step 9–11:** Run with flag OFF (all pre-existing tests unchanged); mutation-prove each drop; commit + `ship_dark_pending_review.yaml` entry.

## Task 6: The five non-generator seams

The compile guarantee does not reach these. Each takes `Set<String> capability` explicitly. Gate A pins the set.

- [ ] **Seam 6 — swap sheet.** ⚠ Do **not** filter by `widget.equipment`; its caller passes `currentExercise.equipmentNeeded`, the *outgoing* exercise. Add a real parameter, update `active_workout/swap_sheets.dart:39-52`, filter `_customExercises` too.
- [ ] **Seam 7 — template builder.** `:518` (`getCustomExercises`), `:524` (`getAll().take(30)` — the default view), `:528` (search). Filter **before** `.take(30)`.
- [ ] **Seam 8 — active-workout picker.** `exercise_picker_sheet.dart:31-36`, `getAll()` + customs, filtered on category and name only.
- [ ] **Seam 9 — `SwapService.swapExerciseInDay`** (`swap_service.dart:170`). `WorkoutScheduleService.swapExerciseInDay:262` delegates to it at `:267`, so patching here also covers the AI-coach tool at `tool_dispatcher.dart:275, 588`.
- [ ] **Seam 10 — cardio finisher.** `cardio_finisher.dart:110` — `jump_rope` is the only case that ignores `hasGymEquipment`. `_defaultForGoal` maps `recompose` → `jump_rope` (`:83-84`) and the flag is default ON, so a bodyweight recompose user gets it twice a week **in the shipped APK**. Correct the false docstring at `:70-75` with the code.
- [ ] **Seam 11 — warmup/cooldown. [R2]** `warmup_cooldown.dart` prescribes into every day via `plan_generator.dart:324` and `template_service.dart:169`. It contains **Dead Hang** (`:120`, `:128` — pull-up bar), **Band Pull Apart** (`:102`, `:116` — resistance band) and **Chest Doorway Stretch** (`:47` — doorway, which is excludable).
  ⚠ **`equipmentNeeded` is set ZERO times in this file or `cardio_finisher.dart`** — verified. Every `PlannedExercise` they build leaves it null, so the Task 5 oracle is blind to them, and applying `canPerform` directly would fail-closed and delete every warm-up on every tier. **Populate `equipmentNeeded` on `_timedExercise` (`:249-257`), `_warmupExercise` (`:265-273`) and `_finisherExercise` (`cardio_finisher.dart:223-233`) FIRST**, then filter.
- [ ] Diagnose-doc + `closes-diagnose:` with a real id — this task fixes live shipped bugs.

## Task 7: One `equipment_access` fallback

- [ ] **Step 1:** The regex matches **14** sites, not 12 — the two `lib/features/dev/simulation_service.dart` sites (`:164`, `:552`) are excluded by policy, so the test must exclude `lib/features/dev/` or stay red after the fix.
- [ ] **Step 2:** `ai_snapshot_builder.dart:82` is a 13th site (`?? ''`) invisible to a `'(\w+)'` regex. It is also the site decision 7 was justified by — feed it `effectiveItems`, not the tier string.
- [ ] **Steps 3–5:** `kDefaultEquipmentAccess = 'bodyweight'` + `equipmentAccessOf(Map)`; replace 12; `flutter analyze`; diagnose-doc; commit.

## Task 8: Library data and new exercises — **ONE ATOMIC COMMIT [R2]**

Round 1 had these as Tasks 7 and 8. Splitting them is what created the null-slot window. They land together.

- [ ] **Step 1:** Restore the 49 collapsed rows from `632a10b8^` through the design's §2 mapping. Use the scratchpad, **not `/tmp`** — Git-Bash `/tmp` is not what a Windows tool resolves.
- [ ] **Step 2: Resolve the four ambiguous OR-compounds by name.** §2's hand-mapping and `normalizeToken` disagree on exactly four: `Box or Bench`/`Bench or Box` (Copenhagen Plank), `Wall or Freestanding` (Handstand Hold), `Parallel Bars or Floor` (L-Sit Hold), `Bodyweight or Medicine Ball` (Lunge with Twist). The other four compounds agree. State which procedure is authoritative and write the four answers.
- [ ] **Step 3:** Three `Foam Roller`-only rows (E082, E163, E164) would become `[]`, which fails closed — substitute `['bodyweight']`.
- [ ] **Step 4: The audit, bounded by Gate B.** Work the 117 bodyweight-tier rows from Gate B's triage list. Known corrections: `Negative Pull Up` → `['pull-up bar']`, `Bench Dips` → `['elevated surface']`, `Doorframe Curl` → `['doorway']`, `Towel Row` → `['towel']` — all four were already wrong *before* the normalizer, so git cannot reach them, and each is its pattern's sole core-satisfying row.
- [ ] **Step 5:** The four over-tag corrections. None gets `home_dumbbells` — `tierItems['home_dumbbells']` has no `bench`.
- [ ] **Step 6:** Re-derive `equipment_tier`; reconcile `sot_registry.yaml:8532`'s **ADD-only** invariant text, which a re-derive breaks and no test catches. ⚠ No row may end with an empty `equipment_tier` (`equipment_tier_consistency_test.dart:51-60`).
- [ ] **Step 7: The new exercises — in this same commit.**
  - `vertical_pull` needs **three**, not one. **[R2]** The round-1 draft shipped only Prone Lat Pull, arguing the other two fail the un-excludable core — true but irrelevant to the ≥3 *baseline* assertion, which they satisfy, and Step 1 of its own test required 3. Ship **Prone Lat Pull** `['bodyweight']` (core-satisfying), **Sliding Lat Pull** `['towel']`, **Doorway Isometric Lat Pull** `['doorway']`.
  - `horizontal_pull` reaches **zero** core rows after Step 4. **The answer is in the library. [R2]** E261 Bodyweight Rear Delt Raise is already a prone scapular movement with `['bodyweight']`; author a prone row / reverse-snow-angel on the same shape with `movement_pattern: ['horizontal_pull']`. No new equipment concept, no product decision. (The round-1 self-review offered "an enumerated exemption like `vertical_pull`'s" — **that exemption does not exist**; decision 10 fills `vertical_pull` rather than exempting it.)
  - Backfill the rest to ≥3 baseline and ≥1 core per pattern. ~18 rows, 38 keys each; `injury_contraindications` a List, `primary_muscles` non-empty.
- [ ] **Step 8:** Update the pinned row count (`exercise_library_schema_contract_test.dart:69`); seed version **9 → 10** (`seed_service.dart:89`) or the retag is inert for every existing install.
- [ ] **Step 9:** Flip Gates A and B to hard-fail. **Step 10:** diagnose-doc, run suites, commit.

## Task 9: Flip the flag

- [ ] **Step 1:** Default ON; kill-switch becomes `disable_…`.
- [ ] **Step 2: Verify with the Task 5 behavioural test, NOT the scorecard. [R2]** The scorecard runs through the mirror and cannot read the flag — it is green in every world.
- [ ] **Step 3:** Confirm `missing == 0` via the real generator across bodyweight personas, phases 1–3.
- [ ] **Step 4: Check the three baselines Task 8 loads. [R2]** `total_fallback_picks ≤ 1184` (bodyweight already at 868, and 16 rows leave the tier), `meanOverall ≥ 87.0 - 0.05`, `missing == 0` hard. State before/after for each and require non-increase. Re-freezing a risen number is shipping the symptom and calling it the floor.
- [ ] **Step 5: Resolve the ship-dark entry. [R2]** §4.12.4 says it is removed once the flip-on commit's record shows the full ×2 + `bpass: accepted` — which this batch's review is. Add a `note:` recording the flip, following the `enable_equipment_exclusions` precedent in that file. No gate reads it, so nothing else will catch a stale row.
- [ ] **Step 6:** Commit.

## Task 10: Persistence

- [ ] Migration **124** (`user_profile.equipment_owned text[]`), 4-tag header, `applied_migrations.json` paired same commit. Apply to prod **before** any client writing the field ships — `user_repository.dart:721-724` upserts a spread and `_sanitize` does not whitelist, so a 400 rejects the entire profile row.
- [ ] Migration **125** for the cloud `exercise_library` re-seed — a **new** migration, not an edit to 074. 074 is recorded applied 2026-07-19 with a `hash:`; editing it invalidates that (OI-135: 60 of 125 ledger entries already drifted this way), and its inline `TRUNCATE` rollback is unsafe now that `promote-community-item` accretes onto the table. Use `ON CONFLICT DO UPDATE` on `equipment_needed`, covering Task 8's new rows. `beat-my-coach/index.ts:193` filters `equipment_needed.cs.{bodyweight}`.
- [ ] `sync_profile.dart:196-201` conditional-entry write. **Restore needs no code** — `_restoreUserProfile` (`:567-647`, bare `.select()` at `:574`, non-null merge at `:622-623`) is column-agnostic.
- [ ] Gate 19 `_alwaysOk += 'equipment_owned'`; regenerate `backups/live_schema_columns.json` (mandatory and unenforced — `check_schema_column_refs.dart` skips spreads and bare `select()`).

## Task 11: Profile UI

- [ ] **Step 1:** ⚠ By now Task 2 has populated `tierItems['bodyweight']`, so the Customize section is **shown with chips**, not hidden (`edit_profile_screen.dart:1310`). The round-1 draft predicted the opposite.
- [ ] **Steps 2–4:** Point Customize at `tierAskableItems`; add "I also have — tap anything you own" writing `equipment_owned`; add the field to `computePlanChanged` (`:1967`) so it joins the existing eight-field **"Reschedule Workouts?"** prompt, which already regenerates forward-only from today keeping completed workouts. No new regeneration behaviour.
- [ ] **Step 5:** Commit.

## Task 12: Records

- [ ] **Plan-review record** `docs/plan-reviews/oi89-bodyweight-floor.md` — `---` frontmatter with **`branch: oi89-bodyweight-floor`**, `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review:` naming a committed file with line-anchored `verdict: accepted`. Verified: the gate reads only these; `date:` and `blast_radius:` are not read.
- [ ] **Closure YAML `docs/audit/oi89-equipment-capability.closure.yaml`** — name the path; Gate 40 discovers by suffix and prints SKIP otherwise. Top-level `findings:`, per-entry `- id:`, per-state fields (`closed_in_commit` → `commit:` + `verification:`/`notes:`; `blocked_on_user` → `reason:`; `verified_clean` → `evidence:`/`notes:`; **`upstream_blocked` → `blocker:` + `reopen_when:` [R2]**), `total:` ±3, recomputed `closed_count:`. **Per-finding, not per-task.** ⚠ `total:`/`closed_count:` must not be interleaved inside `findings:` — the walk breaks at the first zero-indent key after the first finding.
- [ ] **SoT registry — a NEW entry for `equipment_owned`. [R2]** §4.5 requires one for a new writer/reader contract (profile write → generator + AI snapshot read → sync → migration). No gate can notice a contract never registered. It then needs a real `behavioral_test_path:` under strict Gate 42. Also fix that entry's stale writer note (`seed_service.dart` `7→8`; the file is at 9, going to 10).
- [ ] **OI-89 board** — `blast_radius` account→platform, strike "no migration, no schema" (`open_issues.md:1937`), `closes-oi: OI-89`.
- [ ] **Docs:** `plan_engine/CLAUDE.md:274`; `lib/features/train/CLAUDE.md`; `lib/features/profile/CLAUDE.md`; `lib/core/services/CLAUDE.md`; `docs/architecture/database.md` + `sync.md`; `docs/reference/exercise-library.md`; `docs/naming_conventions.md` §4.7 glossary.
- [ ] **§5 close-out:** root CLAUDE.md row **answered explicitly** (two candidate invariants: the required-parameter compile guarantee; the per-pattern un-excludable core replacing a per-token floor proof); `project_*.md` retrospective; `feedback_*.md`; harness `MEMORY.md`; worktree retirement; full-suite scope stated.
- [ ] **Skills:** `debugging/SKILL.md` — *an oracle reading the same field as its predicate proves threading, never truth*; and *hand-enumerating a mechanically-enumerable set fails once per review round*. `code-review/SKILL.md` — dated Tuning bullet in the same commit as any `docs/reviews/**.md`.

## Task 13: Correct the design document **[R2]**

The plan's header points at the design as its spec, and two of its statements are now known wrong. Fix in the design itself so the next reader does not inherit them: migration **122 → 124**, and `_restoreUserProfile` `:505/:512/:558-570` → **`:567-647` / `:574` / `:622-623`**. Also correct §2 point 3, which lists `yoga mat` among rows "shadowed the moment their key is promoted" — it is never promoted.

---

## Self-review

**Round-2 coverage.** All 5 P0s and 6 P1s addressed: ordering/atomicity (Ordering + Task 8), the scorecard blindness (Ordering + Task 9 Step 2), the OFF-state unsoundness (Task 5 Step 4), the fail-closed custom-exercise hole (Task 1 Step 4, keeping the two aliases), seam 11 with `equipmentNeeded` populated first (Task 6), Task 8's `vertical_pull` self-contradiction (Step 7), the invented exemption (struck, with the real answer from E261), the five `tierExcludableItems` readers (Task 2 Step 4), migration-125 authorization (Task 0 P0-c), the tier-miss branch (Task 3 Step 5), the three scorecard baselines (Task 9 Step 4), and the SoT entry (Task 12).

**Method change.** Task 4's two gates replace hand-enumeration for both the seam set and the library audit. Seams went 5→7→10→11 across four rounds; the audit went from "judge ~210 rows blind" to 117 rows of machine-triaged review. Neither is a guarantee, but both convert a judgement into a mechanism with a permanent detector, which is the §4.11 pattern.

**Still open, stated not buried:**
1. Task 2 Step 1's gym-tier chip decision — a genuine design-vs-implementation fork.
2. Task 8 Step 2's four OR-compound resolutions — a procedure choice, resolvable during implementation.
3. Gate B's false-positive rate is unmeasured beyond the 82/259 flag count.

**Deliberate under-specification:** Task 8 Step 4 judges rows from Gate B's triage output, which does not exist until Gate B runs. Task 8 Step 7's exact backfill set follows from Step 4's outcome.
