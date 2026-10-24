# Thin-day top-up (OI-401) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revision:** r3 (2026-10-24), CONVERGED after review round 2. Base moved from `1f1ea306` to `4c46e91d` (origin/main, 18 hook and process commits, none under `plan_engine`); one process delta: the B-pass tuning entry now lives inside the review file.
- **Round 1** (two context-blind lenses, session scratchpad `injury/review_t1_1_A.md`, `review_t1_1_B.md`): `not_converged`. Lens A 0 P0 / 2 P1 / 8 P2 / 6 M; lens B 0 P0 / 3 P1 / 8 P2 / 3 M. Five distinct P1s: the exercise-seam gate (both lenses), the slot's own pattern never retried, the Task 2 commit order against the diagnose gate, and an untested equipment leak. r2 resolves every finding (resolution map at the end) and re-measured the revised design on a second throwaway prototype (`injury/proto2.patch`).
- **Round 2** (two fresh lenses, `injury/review_t1_2_A.md`, `review_t1_2_B.md`): `converged`. Lens A 0 P0 / 0 P1 / 6 P2 / 4 M; lens B 0 P0 / 0 P1 / 9 P2 / 4 M. r3 applies every P2 and mechanical fix (second resolution map at the end). No design change.

**Approval (founder, 2026-10-23):**
- Option (b) for thin days: a day left with fewer than 3 exercises by injury filtering is topped up with safe moves for that day's own muscles from a neighbouring movement type, then with safe core moves, then stop. Recorded as OI-401.
- Order: injury re-check (PR #155, merged `1f1ea306`), then this plan, then B2 (session set budget), then Beat My Coach removal.
- Pairs of injuries may keep up to 4 empty days until this lands ("Ship, allow 4"). This plan removes them.
- Execution mode: **inline** (§4.12.7), branch `thin-day-topup`, base `1f1ea306`.

**Goal:** for every single injury and every pair among the six most-tagged injuries (the swept input set, see Measured), an injured user's generated day has at least 3 exercises whenever the stages below can reach 3. No pick is contraindicated and none needs equipment the user lacks. An uninjured user's plan is unchanged to the byte.

**Architecture:**
- A post-pass inside `ExerciseSelector`, run on the finished `List<PopulatedDay>` at the three places a day list leaves the selector: the end of `pickV4`'s cascade, the B1 `_pickCoreList` return, and the end of `buildPinnedDays`.
- Per variant (A and B separately): if `injuries` is non-empty and the variant has fewer than `ThinDayTopUp.floor` (3) exercises, add moves through the same `queryV4` filters the cascade uses (injury, capability, exclusions, experience):
  1. **Neighbour stage.** For each of the day's own (muscle, pattern) anchors in slot-priority order, try the anchor's OWN pattern first (A's own pattern is already known empty; B's is not, because B was built with A's names hard-excluded, and a repeat phase drops pins without touching the slot), then its neighbouring patterns, closest first. The first pattern with a candidate adds one move. Rounds repeat until the floor is reached or a whole round adds nothing.
  2. **Core stage.** Then the `core` pattern with no muscle anchor, one move at a time.
  3. Then stop. A day the stages cannot lift to the floor stays short (Ruling R8).
- In phase 1 every query first asks for `is_foundational` rows and falls back to any row, so a beginner gets Plank and Dead Bug before Farmers Carry.
- A `(pattern, muscle)` query that returns nothing is never repeated for that variant (candidates only shrink as moves are picked).
- Exactly ONE `repo.queryV4(` call site is added (the exercise-seam gate counts them; Ruling R10).
- `plan_generator.dart` is not edited (rule 14): both entry points it already calls do the work.
- Pure rules (floor, neighbour table, anchor ordering, trigger) live in a new `thin_day_topup.dart`; the orchestration needs `_selectCandidate` and `_buildExercise`, which are private to `ExerciseSelector`, so it stays there.
- Kill-switch `disable_thin_day_topup` (default ON).

**Tech Stack:** Flutter/Dart, Hive, `flutter_test`.

**Spec:** OI-401 in `docs/audit/open_issues.md` (founder option (b)); `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` for the programme. Evidence is in the session scratchpad `injury/` and does not survive the session, so Task 2's diagnose-doc copies the tables below into the repo: `proto_sweep1.log` / `proto2_sweep.log` (the five-block sweep, prototype 1 and 2), `proto_probe1.log` / `proto2_probe.log` (what the top-up adds), `proto_golden.log` / `proto2_golden.log`, `proto_wide.log`, `proto.patch` / `proto2.patch`, `_probe_thin_topup_test.dart.bak`.

**Blast radius:** `platform` (`lib/shared/repositories/plan_engine/**`). Full ×2 plan review, B-pass before merge, plan-review record in its own commit. Shipped ON with a kill-switch, so the full ×2 is this plan's (Ruling R3).

## Measured ground truth

Real `PlanGenerator.generateV4`, B1 flag OFF (the path users get), the five blocks of `injury_floor_sweep_test.dart` (7,200 runs). The input set: the 9 single injuries (3 and 5 days at phases 1 and 3, 4 and 6 days at phase 1), the 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip (phase 1, 3 to 6 days), the repeat phase for each single (phase 2 with phase 1's names pinned, 3 to 6 days); no equipment exclusions, no history, no plateau names, weeks 1 and 2 scanned; ankle, hamstring and neck appear in singles and repeat only.

| block | empty / thin(<3) / one-exercise BEFORE (main `1f1ea306`) | AFTER prototype 1 | AFTER prototype 2 (the design in this plan) |
|---|---|---|---|
| singles 3 and 5 days | 0 / 74 / 19 | 0 / 0 / 0 | 0 / 0 / 0 |
| singles 4 and 6 days | 1 / 75 / 13 | 0 / 0 / 0 | 0 / 0 / 0 |
| pairs 3 and 5 days | 4 / 531 / 197 | 0 / 2 / 0 | 0 / 2 / 0 |
| pairs 4 and 6 days | 6 / 647 / 241 | 0 / 6 / 0 | 0 / 6 / 0 |
| repeat phase 3 to 6 days | 0 / 768 / 310 | 0 / 0 / 0 | 0 / 0 / 0 |

- Unsafe picks 0, unresolved names 0 in every block (main picks and warm-up/cool-down), for both prototypes. The prototypes carried no equipment oracle, no duplicate counter and no kill-switch: whether the final code shows `unperformable == 0` and `duplicates == 0` is UNVERIFIED until Task 3.
- Prototype 2 changes what is added, not how many days stay short. The residual is identical: 8 scan days, all shoulder + lower_back, bodyweight, beginner (the 5-day build_muscle plan, and the 6-day lose_fat, strength and general_fitness plans), each holding `Plank, Dead Bug`. A scan day is one day in week 1 or week 2; the sweep scans two weeks, so these are 4 runs with one short day each, in 2,880 pair runs (the 6-day plans show variant A in both scanned weeks, because `useB` is false there, `periodization_engine.dart:82`; the 5-day plan shows A then B).
- What the top-up adds, singles 3/5 days plus the shoulder + lower_back pair at 3 to 6 days (1,056 runs, `proto2_probe.log`): 63 runs get any top-up (6%). Prototype 1 (neighbour then core): 41 neighbour adds, 106 core adds (72% core). Prototype 2 (own pattern, neighbour, core): 49 own, 30 neighbour, 68 core (46% core). Most-picked: Plank 48, Dead Bug 20, Reverse Fly 17, Bodyweight Rear Delt Raise 11, Wall Triceps Press 8, Reverse Lunge 8, Doorframe Curl 8. In this phase-1 probe Farmers Carry no longer appears (the foundational try-first is phase 1 only, so a phase 2 or 3 beginner can still receive it, R5). So part of prototype 1's "mostly core" was the stage list, and the own-pattern stage fixes it.
- Repeat phase, phase 2 with phase 1's names pinned (1,728 runs, `proto2_probe.log`): 302 runs (17%) get a top-up: 783 own-pattern adds, 189 neighbour, 93 core (73% own). 2,055 of 15,552 scanned days sit at exactly 3 after the top-up (13%, against 2.0% in singles): a pinned plan keeps its slots, so its dropped pins are mostly refilled from the same pattern, and 3 is where the floor stops.
- Generator golden (`test/plan_generator/generator_golden_test.dart`): 2 keys change for both prototypes: `injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1` and `|p2`. The 974 non-injury keys and the 22 other injury keys do not (998 keys in all).
- Widest generator test set (`test/plan_generator`, `test/plan_engine_v4`, `test/contracts`, 46 minutes), prototype 1 only: 6,562 passed, 4 skipped, 1 failed, the golden's 2 keys (`proto_wide.log`). Prototype 2 was not re-run on the wide set; Task 3 Step 1 runs it on the final code.
- Sweep wall time, five blocks: 10:11 solo on main (`sweep4_after.txt`: 2:25 + 1:17 + 2:14 + 2:35 + 1:39), 27:02 for the same blocks in the loaded full-suite run (`full_suite2.txt`: 14:06 + 6:28 + 2:14 + 2:35 + 1:39), 15:40 solo for prototype 1, 17:21 solo for prototype 2 (`proto2_sweep.log`: 6:07 + 2:07 + 3:39 + 3:20 + 2:08; the singles block alone was 2:25 on main). Different days and machine states, so this is UNVERIFIED as a code cost (the top-up touches about 6% of singles runs); Task 3 Step 5 times main and the final code back to back. Every block body is synchronous, so the file's 10-minute `@Timeout` cannot interrupt it (a 14:06 block passed under it in the loaded run).

## Global Constraints

- **Uninjured output is byte-identical.** `injuries.isEmpty` returns the SAME list instance. Proven by an `identical()` test on hand-built thin days with `injuries: []` (so dropping the early return reddens it) and by the golden's 974 non-injury keys. The plan does NOT claim "before any Hive read" is tested: the flag getter swallows a missing box, so the order of the two checks is invisible to a test; the early return is first by construction.
- **No contraindicated pick, ever.** Every candidate comes from `queryV4` with `injuryExclusions: injuries`; the stage never builds a pick from a hand-written name. The oracle reads the tags from `assets/data/exercise_library.json` (as the sweep does), never from production `_isContraindicated`.
- **Nothing the user cannot perform.** The same query passes `capability` and `exclusions`. New oracle in the behavioral file AND in the sweep scan: every picked main move satisfies `EquipmentCapability.canPerform(equipmentNeeded, capability)` and needs no excluded item; the sweep gates `unperformable == 0` (mutation M10b). The exclusions half (M10) is caught only by the named exclusions persona, because the sweep generates with no exclusions and the tier filter and the capability filter admit the same rows at every tier.
- **No duplicate move inside a variant.** The sweep gates `duplicates == 0` (mutation M11).
- **The generator never adds a custom exercise** (d4b8e1). `queryV4` reads the library box only; a test pins that a pinned custom is counted and none is added.
- **`plan_generator.dart` is not modified** (rule 14).
- **Hive-first, no network.** No new reads except the one `configBox` flag read (injured users only), and, in phase 2+ on a thin day only, one lazy `TrainingHistoryAnalyzer.demotedExercises()` call of its own (a scan of the `schedule_*` rows; `pickV4` makes a separate one at :617-619, so an OFF-path thin day in phase 2+ scans twice and the pinned exit gains one).
- **Canonical injury tokens** (`InjuryVocab`) arrive normalized from `generateV4`; the stage does not re-normalize.
- **Experience level kept.** `suitableFor` follows cascade attempts 2 to 4 (advanced = no filter). `is_foundational` is asked for first in phase 1 and then relaxed (Ruling R5).

## Out of scope, and why

- **`ExerciseSelector.pick` (V3):** zero callers in `lib/`, `test/`, `scripts/`; carries its own `hardFloor` broadening. Dead.
- **Coach regen, hotel planner, previews, phase advance:** every one goes through `generateV4`, so the two real exits cover them (`workout_schedule_read_service.dart`, `hotel_workout_planner.dart`, `regenerate_plan_planner.dart`, `preview_plan_provider.dart`, `phase2_preview_card.dart`).
- **`CascadeTracer`, `QueryV4Mirror`, `generator_matrix.dart`:** mirrors of per-slot cascade attempts that never call the selector; a top-up has no slot (Ruling R7).
- **The coach injury swap planner (`injury_swap_planner.dart`):** edits an existing plan and ignores tags; already filed as OI-403.
- **The cardio finisher:** takes no injuries; OI-396.
- **An uninjured user's thin day:** none was measured; topping it up would change uninjured output (Ruling R2).

## Review Focus

1. **A contraindicated or unperformable move reaches a user through some stage or exit.** The pinned-days exit (customs, names resolved by `getByExactName`), the B1 ON exit, the alias case. Pinned by the sweep for the OFF cascade and the pinned exit (injury oracle, equipment oracle, duplicates), and for the B1 ON exit by `B1 ON: …` in Task 2 (a named persona whose thin precondition the test asserts, so mutation M8 reddens it).
2. **Content parity of B and A.** When the input `exercisesB` IS `exercisesA` (no B slots, or an emptied variant copied from the other), the result keeps that identity AND B's names equal A's. `PeriodizationEngine` reads `exercisesB` content on weeks 2 and 4 (`periodization_engine.dart:82-88`); the only `identical(exercisesB, exercisesA)` read is L6 (`exercise_selector.dart:672`), which runs BEFORE every exit. A pinned B that merely EQUALS A in content is not an alias and is topped up on its own (harmless; stated in Ruling R6).
3. **A and B should differ where the library allows.** B soft-avoids A's (lower-cased) names unless the goal is `strength`; A soft-avoids B's whenever the day is not an alias and the goal is not `strength`; phase 2+ also soft-avoids the previous phase's picks, the plateau names and L6's `demoted` names.
4. **Repeat phases.** `buildPinnedDays` only refills a variant that is EMPTY; a variant left with 1 or 2 survivors was never refilled (310 one-exercise days). Its `fresh()` path calls `pickV4`, which already tops up; the final pass must not add a second time. "Not topped twice" has no direct observable (a variant at 3 or more is skipped, and a stuck one only repeats empty queries), so it is covered by an idempotence assertion and by a persona whose pins are ALL dropped (the `fresh()` path), both in Task 2; the idempotence assertion guards a future change and has no mutation.
5. **B2.** The added moves exist before `PeriodizationEngine.apply`, so B2's budget counts them (`docs/plans/2026-10-22-session-set-budget.md:73`, "injury-trimmed days"). Pinned by a test that the generated week-1 day holds the added names.
6. **Time.** The stage runs on the UI isolate (`preview_plan_provider.dart:95`, `phase2_preview_card.dart:94`) and the sweep file runs in a CI shard with a 20-minute cap. Task 3 records the heaviest persona's milliseconds and the sweep's shard time on the PR run.

---

## Rulings (mine unless marked; each says what it costs if wrong)

- **R1. Floor is 3 per variant.** The founder's rule ("fewer than 3"). One constant, `ThinDayTopUp.floor`. After the top-up the shortest day is 3 exercises, and many multi-injury days sit at 3 to 4. If the founder wants fuller days, raise the constant and re-run the sweep; no other code changes. Cost if wrong: injured users on the thinnest libraries get a 3-move session.
- **R2. The trigger is injuries non-empty AND a variant under the floor, whatever made it thin.** `injuries.isEmpty` is an instance-identical early return, so an uninjured user is untouched. An injured user whose day is thin because of an equipment exclusion is topped up too (harmless; the same filters apply). An uninjured thin day is out of scope (none measured). Cost if wrong: an uninjured user with heavy exclusions keeps a short day.
- **R3. Live, with a kill-switch, not ship-dark.** The empty and one-exercise days are the live result of PR #155 (its tags are live), so shipping this dark would leave them. §4.6 asks that a new generator path default CLOSED; this one ships OPEN, as `disable_injury_universal_filter` and `disable_warmup_injury_filter` do (`plan_engine_flags.dart:17-38`). Those two flags DROP moves from an injured user's plan; this one ADDS moves, each trusted on a tag set the founder has called under-tagged five batches running, and the flags file's own precedent for adding material is `holdWeeksEnabled`, default OFF (`:59-65`). The reason to ship ON anyway: the app is pre-launch and every account is a testing account (root CLAUDE.md §1), and the thin days exist today. The exposure is concentrated: Plank (48) and Dead Bug (20) are all 68 core top-ups in the probe, both tagged `[]` and both in #155's founder-approved untagged safe pool (`test/helpers/injury_safe_pool.dart:29-30`), so one tag error there would reach every core top-up. `configBox` flags are local to the device, so "kill-switch" means a build that writes `disable_thin_day_topup`; there is no remote rollback. Because it ships ON, the full ×2 review is this plan's, not a later flip's. Cost if wrong: ship a build.
- **R4. Three exits, one helper, no `plan_generator.dart` edit.** `pickV4` already reads a flag internally (`PlanEngineFlags.coreListPoolEnabled`, `exercise_selector.dart:583`), so reading this one inside the selector follows precedent. Cost if wrong: a new parameter threaded through `plan_generator.dart` would need the founder's rule-14 OK.
- **R5. Candidate rules follow cascade attempts 2 to 4, with a foundational try-first in phase 1.** Tier and capability as `queryV4` already combines them; experience kept. In phase 1 each query first asks `foundationalOnly: true` and, if that returns nothing, any row (the cascade does the same one attempt at a time). `queryV4` sorts compound first, so without the try-first a phase-1 beginner got Farmers Carry (non-foundational) before Plank and Dead Bug. Cost if wrong: a non-foundational move for a beginner in a top-up, as attempts 2 to 4 already allow.
- **R6. Soft avoid, and why it differs from the OFF cascade.** Every name is lower-cased inside `topUpDays` (`_preferNovel` compares lower-cased names, `exercise_selector.dart:1282`; plateau names are lower-cased there too). A avoids `prevA ∪ plateau ∪ demoted`, plus B's names whenever the day is not an alias and the goal is not `strength` (also when both variants are thin). B avoids `prevB ∪ plateau ∪ demoted` plus A's names (same condition). The OFF cascade hard-EXCLUDES A's names from B (`:653`) and passes only `prev ∪ plateau` as avoid names; the top-up SOFT-avoids the other variant on purpose (as the B1 ON path does, `:801-803`), so a B emptied only by that exclusion can repeat A's moves instead of falling to neighbours or core (this is what the own-pattern query is for), and it adds `demoted`, which OFF handles by an L6 swap (`:665-682`). The avoid is a soft re-order inside `_selectCandidate`: with `applyInjurySubstitutePreference` on (the default) and a curated substitute among the candidates, the pool is narrowed to the curated subs first (`:1251-1267`) and the avoid acts only inside that narrowed pool, so B may repeat a curated sub; the `B differs from A` test names its flag value (false in the direct case). The avoid-set union lives in `topUpDays`, not in `ThinDayTopUp`, so it is testable only through `topUpDays`. `demoted` is read lazily, once per call, in phase 2+ on a thin day. Alias rule: `alias = identical(input A, input B)` computed from the input day before anything is rebuilt; an alias day is topped up once and B is that list. A pinned B that merely EQUALS A in content (a `buildPinnedDays` day with `slotsB == null` and equal pins) is not an alias and is topped up on its own, so weeks 2 and 4 may differ from weeks 1 and 3 there; harmless. Mutations M5a to M5f each remove one part. Cost if wrong: weeks 2 and 4 repeat weeks 1 and 3 on a day the library cannot vary.
- **R7. The scorecard cannot see this; the sweep is the proof.** `CascadeTracer`/`QueryV4Mirror` mirror per-slot cascade attempts and never call the selector, and a top-up has no slot. Same position as the other post-pass features (`plan_engine/CLAUDE.md`: "scorecard cannot measure them"). The scorecard gate is re-run to show it does not move. Cost if wrong: none for correctness; the scorecard stays blind.
- **R8. The residual is the trimmed day plus the founder's stop rule.** After the stages, a bodyweight beginner with shoulder + lower_back injuries on a 5- or 6-day upper-body day holds `Plank, Dead Bug` (8 scan days = 4 runs with one short day each). The cause is not an empty library. `VolumeFilter.targetCount('beginner', 5|6)` is 4 (`volume_filter.dart:19-24`), so the day is trimmed to its first 4 slots BEFORE the selector runs and the arm slots are gone; the stages then start from the trimmed day's muscles, their neighbour patterns and core, and stop, as the founder's "then stop" says. Under the generator's own bodyweight capability set (`tierItems['bodyweight']` also grants wall, doorway, elevated surface, foot anchor and towel, `equipment_vocab.dart:291-294`) the library holds about 22 Beginner rows free of shoulder and lower_back tags (a reviewer's count by first movement pattern: 7 knee_dominant, 5 hip_isolation, 2 core, 5 elbow_flexion, 2 elbow_extension, 1 shoulder_isolation; my own filter gave 21 because Baithak lists `warmup` as a second pattern; 16 under the narrower `{none, bodyweight}` set), including 5 biceps and 2 triceps rows. Three ways to change it, none decided here: anchors from the UNTRIMMED split (needs an input from `plan_generator.dart`, rule 14, the founder's call); a last stage "any safe move" (an upper-body day would then hold leg work); Batch C rows. Terminal state `upstream_blocked`, blocker "VolumeFilter trims the beginner 5/6-day before the selector, plus the founder's stop rule", `reopen_when: the founder asks for untrimmed anchors or an any-safe-move stage`. Filed as a new OI (Task 0). The sweep keeps two ratchets, `kPairsThinBaseline` and `kPairs46ThinBaseline` (counts of SCAN days), tied to the persona by NAME (the thin keys must equal `{shoulder+lower_back}`), and gates every other thin and every one-exercise count at 0.
- **R9. B1 ON.** The top-up is path-independent and uses the OFF-path candidate rules, also when the core-list pool is ON. It does not apply B1's core-level rules or its community-row exclusion (`rankedPool`); it reads `queryV4` like the live path, so the exposure equals today's. Whether a top-up under B1 should be core-list-only belongs to B1's flip review: Task 5 adds the question to the `enable_core_list_pool` entry in `docs/ship_dark_pending_review.yaml` (the tracker the flip review reads), terminal state `upstream_blocked`, `reopen_when: enable_core_list_pool flip review`. The existing ON-world gate is `test/plan_generator/core_list_pool_gate_test.dart`: it runs the real generator with `enable_core_list_pool` ON over the 998 golden personas and hard-fails on a retired or skill/olympic pick (`:43-47`, `:262`) or a refill. Task 3 Step 1 runs it on the final code; expected green. If it is red, the red rows are top-up picks: record them as R9 evidence in the `enable_core_list_pool` entry and do not repoint the gate. Its multi-injury section is reported, not gated (`:6`, `:348`), so `core_list_pool_report.md` drifts on the next `WRITE_CORE_LIST_REPORT=1` and needs no re-record now.
- **R10. The exercise-seam allowlist moves 16 → 17.** `scripts/check_exercise_seams.dart` pins `exercise_selector.dart` at 16 seam sites (`scripts/exercise_seam_lib.dart:59`; counted 16 with the gate's own rule). The top-up adds exactly one `repo.queryV4(` (a single `addFrom` helper used by both stages), so Task 2 bumps the entry to 17 and extends its reason string. `thin_day_topup.dart` stays pure: no `getAll()`, no `PlannedExercise(`, no `queryV4(`.

- **R11. Build-time ruling (2026-10-24, after the full suite): L6 demoted names leave the candidate pool.** R6 listed them as a soft avoid. The full suite showed that is not enough: with the injury-substitute preference on, `_selectCandidate` narrows the pool to the curated subs BEFORE the soft avoid, so a swapped-out curated sub was topped back in while other safe rows existed, and the top-up runs after the cascade's own L6 post-pass (`_applyHistoryAdjustments`). `_topUpVariant` now takes a `demoted` set and drops those names from the candidates unless they are all that is left (L6's "never drop a slot"). Phase 1 has no demoted set and is the only phase that asks for foundational rows, so the two never combine. M5d now removes that filter; M18 removes only its fallback. Regression: `thin_day_topup_behavioral_test.dart`, "demoted + the injury-substitute preference (L6)", control first.
- **R12. Build-time ruling (2026-10-24): R9's fallback was unmergeable, so the gate attributes instead.** R9 said a red `core_list_pool_gate_test.dart` is evidence to record and the gate is not repointed. The suite did go red (16 built rows E234, E261, E271 in shoulder-injured bodyweight and home-dumbbells 4-day personas), and a red test cannot merge (rule 20). The gate stays on the shipped combination and keeps B1's own picks and any skill/olympic row hard; only a persona with a flagged id is re-run once with the top-up kill-switch set, and an id built ONLY with the top-up on is evidence, pinned exactly as `_r9TopUpRetired` (a fourth id fails, an empty list fails). `classifyBuilt` is pure and carries synthetic positive controls; M17a to M17c mutate it. Whether a top-up under B1 should be core-list-only is still the flip review's question (`docs/ship_dark_pending_review.yaml`).

## File structure

| File | Change |
|---|---|
| `lib/shared/repositories/plan_engine/thin_day_topup.dart` | Create. `ThinDayTopUp`: `floor`, `neighbours`, `applies`, `anchors`. Pure. |
| `lib/shared/repositories/plan_engine/exercise_selector.dart` | Modify. `topUpDays` (`@visibleForTesting`), `_topUpVariant`, three call sites. |
| `lib/shared/repositories/plan_engine/plan_engine_flags.dart` | Modify. `thinDayTopupEnabled`. |
| `scripts/exercise_seam_lib.dart` | Modify. `exercise_selector.dart` 16 → 17 and the reason string (R10). |
| `test/plan_engine_v4/thin_day_topup_test.dart` | Create. Pure rules. |
| `test/plan_engine_v4/thin_day_topup_flag_test.dart` | Create. The flag with no Hive (its own file, before any `Hive.init`). |
| `test/contracts/thin_day_topup_behavioral_test.dart` | Create. Real `generateV4` behaviour, the 3 exits, kill-switch, alias, identity, B1 ON, equipment oracle. |
| `test/plan_generator/injury_floor_sweep_test.dart` | Modify. Ceilings to thin/one-exercise gates; `unperformable` and `duplicates` counters; residual identity; header and constant comments. |
| `test/fixtures/generator_golden_hashes.json` | Re-record 2 keys. |
| `docs/sot_registry.yaml` (+ its "all five" capability note) | New concept `thin_day_topup`. |
| `docs/diagnoses/2026-10-24-thin-day-topup-2d04d7.md` | Create (Task 2 commit), mutation table filled in a later docs commit. |
| `docs/naming_conventions.md` | Rows: `disable_thin_day_topup`, `ThinDayTopUp`, "thin-day top-up" (an older informal "isolation top-up" exists at `training_history_analyzer.dart:30`; the new row says NOT that). |
| `lib/shared/repositories/plan_engine/CLAUDE.md`, `docs/architecture/plan-engine-detail.md` | Stage-3 bullet (short, points at the detail doc), the falsified lines, "seven" in the capability row. |
| `docs/audit/thin-day-topup.closure.yaml`, `docs/audit/library-injury-recheck.closure.yaml`, `docs/audit/open_issues.md`, `docs/audit/closed_issues.md`, `docs/ship_dark_pending_review.yaml` | Ledger, the two #155 entries, OI-401 closed and archived + residual OI, R9 question. |
| `.claude/skills/debugging/bug-classes.md` (+ SKILL.md row) | New class, the line it falsifies (`:1842`). The B-pass tuning entry goes INSIDE the review file (`## Tuning entry`); `tuning-history.md` is FROZEN since 2026-10-24 (merge-conflict-treadmill A1). |
| `backups/context_artifact_sizes.json` | `--record` if the L54 band moves (the nested CLAUDE.md has ~455 bytes of headroom). |

---

## Task 0: Housekeeping

- [ ] **Step 1:** Confirm the tree is clean (`git status --short` shows only the untracked plan; the prototype diffs are saved in the scratchpad `injury/proto.patch`, `proto2.patch`).
- [ ] **Step 2:** Mint the residual OI: `sh scripts/mint_oi.sh "Bodyweight beginner with shoulder + lower_back injuries has 2-exercise upper days (Plank, Dead Bug) after the thin-day top-up"`; body per R8 (the VolumeFilter trim cause, the about-22 safe rows including 5 biceps and 2 triceps, the 8 scan days = 4 runs, the three ways to change it, `reopen_when`).
- [ ] **Step 3:** Diagnose id `2d04d7` (checked unused in `docs/diagnoses/`).
- [ ] **Step 4:** Commit the plan file and the minted OI as a docs commit (`docs(plan): thin-day top-up plan r3 and the residual OI`) via `scripts/safe_commit.sh`.

## Task 1: Flag and pure rules

**Files:** `plan_engine_flags.dart`, `thin_day_topup.dart`, tests `test/plan_engine_v4/thin_day_topup_test.dart` and `thin_day_topup_flag_test.dart`.

**Interfaces:**
- Produces `PlanEngineFlags.thinDayTopupEnabled` → `bool`: `configBox.get('disable_thin_day_topup') != true`; `try/catch` → `true`.
- Produces `ThinDayTopUp.floor` (`int`, 3); `ThinDayTopUp.neighbours` (`Map<String, List<String>>`); `ThinDayTopUp.applies({required List<String> injuries, required int count})` → `bool` (`injuries.isNotEmpty && count < floor`; `topUpDays` calls it per variant, so it is live code, and it is also the second line of defence behind the early return); `ThinDayTopUp.anchors(List<MuscleSlot> slots)` → `List<({String muscle, String pattern})>`.

- [ ] **Step 1: Write the failing tests.**
  - `floor == 3`.
  - `applies`: `(injuries: [], count: 0)` false; `(['knee'], 2)` true; `(['knee'], 3)` false.
  - `neighbours`: every key and every value is in `kMovementPatterns` (`models.dart:253`, imported, not copied); `core` is neither key nor value; no pattern lists itself; no duplicates inside a list; all 10 non-core patterns are keys. (The own pattern is prepended in code, not in the table.)
  - `anchors`: slots `[Lats P2 vertical_pull, Mid Chest P1 horizontal_push, Core P1 core, Lats P3 vertical_pull]` give `[(Mid Chest, horizontal_push), (Lats, vertical_pull)]`: priority order, ties by original index (the implementation sorts on `(priority, index)`; Dart's `List.sort` is not documented stable), core dropped, de-duplicated by (muscle, pattern).
  - The flag, in its own file: no Hive opened → true (first, before any `Hive.init`, as `readiness_flag_no_hive_default_test.dart` does); then unset → true; `disable_thin_day_topup: true` → false.
- [ ] **Step 2:** Run: expected FAIL (symbols missing).
- [ ] **Step 3:** Implement. `neighbours` is Appendix A.
- [ ] **Step 4:** Run: PASS. No commit yet (Task 2 carries it).

## Task 2: Selector wiring (the first code commit)

**Files:** `exercise_selector.dart`, `scripts/exercise_seam_lib.dart`, `docs/sot_registry.yaml`, `docs/diagnoses/2026-10-24-thin-day-topup-2d04d7.md`, test `test/contracts/thin_day_topup_behavioral_test.dart`.

**Interfaces:**
- Consumes Task 1.
- Produces `ExerciseSelector.topUpDays(List<PopulatedDay> days, {required List<MuscleSlotDay> slotDays, required ExerciseRepository exerciseRepo, required String equipmentTier, required String effectiveExp, required int phase, required String goal, required List<String> injuries, required bool applyInjurySubstitutePreference, required Set<String> exclusions, required Set<String>? capability, Map<int, ({List<String> a, List<String> b})>? previousPhaseByDay, Set<String> plateauAvoidNames = const {}})` → `List<PopulatedDay>`, annotated `@visibleForTesting`.
- Private `_topUpVariant(...)` → `List<PlannedExercise>`; an inner `addFrom(pattern, muscle)` holding the ONE `repo.queryV4(` call (inside `for (final foundational in [if (phase == 1) true, false])`), then `_selectCandidate(cands, injuries:, applyInjurySubstitutePreference:, avoidNames:)`, then `_buildExercise(chosen)`. The query passes `movementPattern`, `targetMuscle`, `equipmentTier`, `suitableFor: effectiveExp == 'advanced' ? null : effectiveExp`, `foundationalOnly`, `excludeNames: picked`, `injuryExclusions: injuries`, `exclusions`, `capability`.

Behaviour of `topUpDays`:
1. `injuries.isEmpty` → return `days` (same instance).
2. `!PlanEngineFlags.thinDayTopupEnabled` → return `days`.
3. `days.length != slotDays.length` → return `days` (fail safe; tested with mismatched hand-built lists).
4. A day where `ThinDayTopUp.applies` is false for both variants is reused as is. `alias` is computed from the INPUT day first (`identical(day.exercisesA, day.exercisesB)`). A thin A is topped up with A's avoid set; an alias day sets B to the new A; otherwise a thin B is topped up with B's avoid set (B's slots are `slotsB ?? slotsA`). Avoid sets are R6, lower-cased.
5. If no day was thin, return `days` itself.

Call sites (line numbers on `1f1ea306`): `return _pickCoreList(...)` at :586 and `return result;` at :690 in `pickV4`, and `return result;` at :1054 in `buildPinnedDays` (the pinned call passes no `previousPhaseByDay`).

Named personas (all located in the sweep logs on main; each test ALSO proves its precondition by generating once with `disable_thin_day_topup` set and asserting the day is thin there, so a persona that stops being thin fails loudly instead of passing vacuously):
- `shoulder|bodyweight|build_muscle|advanced|4d|p1`, "Chest, shoulders, triceps" (empty on main).
- `knee+hip|bodyweight|build_muscle|intermediate|3d|p1`, "Quads, hamstrings, glutes", week 2 (the B variant, empty on main).
- `elbow|bodyweight|lose_fat|beginner|6d|p2-pinned`, "Upper pull + conditioning" (one exercise on main): phase 1 uninjured, then phase 2 with `namesByDay(first)` as pins, as `runRepeat` does.
- Exclusions persona: bodyweight, a single injury (shoulder or wrist) whose probe top-up reached `Doorframe Curl` (needs `doorway`) or a `Towel` row (needs `towel`), generated with `equipmentExclusions: ['doorway', 'towel']` (`floorSanitizedExclusions` strips only none, bodyweight and wall, `equipment_vocab.dart:247-250`, so both are excludable at the bodyweight tier). Precondition asserted: with NO exclusions the same run's added moves include a doorway or towel row, so mutation M10 provably reddens. The exact run is read off the probe during Step 1b.
- Foundational persona: a `home_dumbbells`-or-higher beginner with no wrist injury (lower_back only, or shoulder + lower_back), phase 1, whose core top-up picks Farmers Carry when the try-first is removed (Plank and Dead Bug are `calisthenics` and foundational; Farmers Carry needs dumbbells, is non-foundational, and is wrist-tagged). Located in Step 1b by running with M16 applied.
- knee+hip: the test pins the exact names the final code adds, recorded from its first run. For this persona B's final names are a subset of A's (the safe pool is four rows), so `B differs from A` is NOT asserted here.
- B1 ON: a hand-built `MuscleSlotDay` (a Chest `horizontal_push` slot and a Triceps `elbow_extension` slot), bodyweight, beginner, `['shoulder']`, `enable_core_list_pool` true, built with the `pick()` helper of `core_list_pool_behavioral_test.dart:185-210` against a seeded library; the precondition (thin with the kill-switch set) is asserted; Task 2 Step 2 reports whether such a persona exists. If none exists under ON on the real library, the library the test seeds is shaped to make one and the test says so.

- [ ] **Step 1: Write the failing tests** (names are the contract; each runs real `generateV4` unless it says "direct"):
  - `shoulder bodyweight advanced 4-day: no empty or thin day, no tagged pick, no unperformable pick`.
  - `knee+hip bodyweight intermediate 3-day: week-2 day is lifted and safe`.
  - `repeat: one surviving pin is lifted to 3, safe, with no duplicate name`.
  - `kill-switch: set gives the thin length recorded from main, unset gives >= 3` (one test, both halves, same persona).
  - `uninjured: identical list` (direct, hand-built thin days, `injuries: []`) and `uninjured plan equals the plan with the switch set` (a guard, labelled so: it is green on main).
  - `injured, no thin day: the same instance comes back` (direct).
  - `length mismatch returns the same instance` (direct).
  - `alias: B is the topped-up A, same identity and same names` (direct) and the same through `pickV4` with `slotsB: null` on the seeded-library shape of `injury_safe_omission_production_test.dart`.
  - `own pattern first: a B emptied by the A exclusion gets a move from its own slot pattern, not core` (the knee+hip persona's B, exact names pinned) and a direct case that does not depend on library depth: `slotsA` = a `horizontal_push` slot only, `slotsB` = a `vertical_pull` slot only, a thin B; the first add comes from B's pattern (this reddens M13 and M15 independently).
  - `pinned: a dropped pin's slot is refilled from its own pattern before any neighbour`.
  - `neighbour before core` and `core when no neighbour is safe` (direct, hand-built days over a seeded library).
  - `phase 1 prefers foundational: a beginner's core top-up is Plank or Dead Bug, not Farmers Carry`.
  - `B differs from A where the library allows` (direct, `applyInjurySubstitutePreference: false`; with it true a curated sub may repeat, R6); `strength does not soft-avoid`; `A avoids B's names whenever the day is not an alias and the goal is not strength` (also when both are thin).
  - `phase 2 avoid sets`: previous-phase names, plateau names and demoted names are each avoided when an alternative exists (direct, one per set; names given in mixed case). Demoted names are seeded by putting a `schedule_<date>` map in the workout box with a recent `date` and an `exercises` list whose row carries `swapped_from: <name>` (`training_history_analyzer.dart:316-359`).
  - `idempotent: topUpDays(topUpDays(x))` returns the first result's instance when nothing is thin, and equal names when a residual 2 remains (direct, hand-built days).
  - `repeat: all pins dropped (the fresh() path)`: a persona whose pins are all contraindicated; the day has length >= 3, no duplicate name, and equals a direct single-frame `pickV4` day.
  - Non-alias hand-built days use `<PlannedExercise>[...]`, never `const []` (two const empty lists are `identical` in Dart and would read as an alias).
  - `a pinned custom is counted and none is added`.
  - `B1 ON: pickV4 adds safe, performable moves to a thin day` (the persona above).
  - `a topped-up day reaches PeriodizationEngine: the week-1 day has >= 3 exercises, its length equals a direct pickV4's day length, and it contains the names the direct call added`.
  - `equipment oracle`: over the shoulder and shoulder+lower_back bodyweight personas and the exclusions persona, every ADDED move passes `EquipmentCapability.canPerform(equipmentNeeded, capability)` and needs no excluded item (oracle from the built `PlannedExercise.equipmentNeeded`, as `bodyweight_capability_leak_test.dart` does).
- [ ] **Step 1b:** Add `ExerciseSelector.topUpDays` as a stub that returns `days` (so the behavioral file compiles), call it at the three exits, and keep the Task 1 files in place.
- [ ] **Step 2:** Run the file against the stub: the persona tests fail on thin lengths and the direct tests on behaviour (the real red set). In this run: record whether a B1 ON thin persona exists on the real library (else shape the seeded library to make one and say so), read the exclusions persona's run off the probe, and locate the foundational persona.
- [ ] **Step 3:** Replace the stub with the implementation above.
- [ ] **Step 4:** Run: PASS. `dart run scripts/check_exercise_seams.dart` PASS after the 16 → 17 edit with the reason string extended ("16 -> 17 on 2026-10-24, OI-401: the thin-day top-up queries queryV4 once, in `_topUpVariant`; capability, exclusions and injuries are all passed as required parameters").
- [ ] **Step 5:** `flutter analyze` (the whole project with `--no-fatal-infos`, as `scripts/pre-push.sh` runs it; a `warning -` line in a new test file aborts a push) clean.
- [ ] **Step 6:** Write the diagnose-doc `2d04d7` (full template, `blast_radius: platform`, `touched_layers_checked`, `impact_analysis`, `regression_test_planned`, `status: open`, the measured tables from this plan copied in) and the SoT concept `thin_day_topup` with `behavioral_test_path: test/contracts/thin_day_topup_behavioral_test.dart`; they must exist and validate (`dart run scripts/validate_diagnose_doc.dart <path>`) BEFORE the commit, because `scripts/commit-msg.sh:99-113` and Gate 10 require them.
- [ ] **Step 7:** Commit `fix(plan-engine): thin-day top-up for injured users (OI-401)` with Tasks 1 and 2, the line `Regression test: test/contracts/thin_day_topup_behavioral_test.dart` and the trailer `closes-diagnose: 2d04d7`, via `scripts/safe_commit.sh "$(cat msg.txt)"`.

## Task 3: Sweep, golden, existing tests, time

- [ ] **Step 1:** Run the widest generator set (`test/plan_generator`, `test/plan_engine_v4`, `test/contracts`) and list every red; each is a legitimate repoint or a finding. The prototype's run (46 minutes) had exactly one red, the golden's 2 keys. Include `core_list_pool_gate_test.dart` by name (R9): expected green; a red there is R9 evidence, not a repoint.
- [ ] **Step 2:** `injury_floor_sweep_test.dart`:
  - Delete `kPairsEmptyBaseline`, `kPairs46EmptyBaseline`, `kSingles46EmptyBaseline` (read only in this file, lines 66, 69, 75, 311, 322, 333) and their doc comments; fix the header comment (it says "OI-401 owns the top-up").
  - Empty days gated at 0 in all five blocks; one-exercise days gated at 0 in all five; thin gated at 0 in singles (both) and repeat; `kPairsThinBaseline` and `kPairs46ThinBaseline` (R8; their doc comments say they count SCAN days and that the 6-day plans repeat variant A in weeks 1 and 2), plus `expect(t.thinBy.keys.toSet().difference({'shoulder+lower_back|shoulder+lower_back'}), isEmpty)` in both pairs blocks, and the thin report lists the persona labels.
  - New `scan` counters, both gated at 0 in every block: `unperformable` (a main pick that fails `EquipmentCapability.canPerform` for the run's tier, `equipmentNeeded` read from the library row) and `duplicates` (a name twice in one day's list).
- [ ] **Step 3:** Re-record the golden: `RECORD_GENERATOR_GOLDEN=1 TZ=Asia/Kolkata flutter test test/plan_generator/generator_golden_test.dart` with the Bash tool (PowerShell cannot use the `VAR=1 cmd` form); the switch rewrites the whole fixture sorted and keeps `_meta.recorded_on`, so diff the fixture afterwards and assert exactly the 2 keys `injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1` and `|p2` changed (a different persona from the sweep's `…|advanced|4d` case; do not expect the same one). `core_list_pool_behavioral_test.dart:255,528` read only `grid|…` keys.
- [ ] **Step 4:** Run `test/plan_generator/scorecard_gate_test.dart`: unchanged (R7).
- [ ] **Step 5:** Time, decided by number. Time the five-block sweep on main and on the final code back to back on the same machine state, and the heaviest persona's milliseconds (`shoulder+lower_back`, bodyweight, beginner, 6-day); record both in the diagnose-doc. If the final solo five-block total is over about 14 minutes (main 10:11 solo, 27:02 loaded; prototype 2 17:21), split the sweep in this same commit into `injury_floor_sweep_test.dart` (singles, singles46) and a second file (pairs, pairs46, repeat), so adjacent sorted files shard apart (`scripts/ci_test_partition.dart:5-8` puts sorted file `i` in shard `(i % total) + 1`, and the three new test files all sort before `test/plan_generator/`, so the sweep moves one shard back). The CI shard cap is 20 minutes (`.github/workflows/test.yml:117-121`): Task 6 reads the sweep's shard and its duration on the PR run and records them.
- [ ] **Step 6:** Commit `test(plan-engine): sweep gates for the thin-day top-up (OI-401)` (a `fix`, `bug` or `regression` subject would need `closes-diagnose` again).

## Task 4: Mutations (rule 21; once each, applied and confirmed with `grep -c`, restored from a saved copy and verified by sha1, never `git checkout --`). Save BOTH mutated files (`thin_day_topup.dart`, `exercise_selector.dart`) before the first mutation.

| # | Mutation | Which test must redden |
|---|---|---|
| M1 | `floor` to 0 | the persona tests |
| M2 | drop `injuryExclusions: injuries` from the query | sweep unsafe, persona safety |
| M3 | delete the early return AND the `injuries.isNotEmpty` clause of `ThinDayTopUp.applies` (either alone is an equivalent mutant) | `uninjured: identical list` (hand-built thin days) and the `applies` unit test |
| M4 | drop the alias branch (`b = a`) | the alias tests |
| M5a | drop A's names from B's avoid set (M5a′: drop the lower-casing) | `B differs from A` |
| M5b | drop previous-phase names | `phase 2 avoid sets` |
| M5c | drop plateau names | same |
| M5d | drop demoted names | same |
| M5e | drop B's names from A's avoid set | `A avoids B's names…` |
| M5f | invert the `strength` check for A only | `strength does not soft-avoid`, `A avoids B's names…` |
| M6 | drop the core stage | `core when no neighbour is safe` |
| M7 | remove the `buildPinnedDays` call | the repeat test |
| M8 | remove the `_pickCoreList` call | `B1 ON` |
| M9 | ignore the kill-switch | the kill-switch test (both halves) |
| M10 | pass `capability: null, exclusions: const {}` | the exclusions persona (the sweep cannot: it has no exclusions and the tier and capability filters admit the same rows at every tier) |
| M10b | pass `capability: null` AND `equipmentTier: ''` (an empty tier makes `tierLower` null, `exercise_repository.dart:292-294`, so no equipment filter runs) | sweep `unperformable` at every tier |
| M11 | drop `excludeNames: picked` | sweep `duplicates`, the no-duplicate assertion |
| M12 | swap the stage order (core first) | `neighbour before core` |
| M13 | use `slotsA` for B | the disjoint-slots direct test |
| M14 | drop the length guard | `length mismatch` |
| M15 | drop the own-pattern query (neighbours only) | the disjoint-slots direct test, `pinned: own pattern` |
| M16 | drop the foundational try-first | `phase 1 prefers foundational` |

The exhausted-key memo is a pure performance cache with no output effect, so it has no mutation that an output test can see; its proof is the Task 3 Step 5 timing. The idempotence assertion guards a future change and has no mutation either; the diagnose-doc says so, so the mutation count is not read as covering them. The diagnose-doc records how many tests each mutation reddened; a mutation that reddens nothing is a finding. The mutation table lands in a later `docs(diagnose)` commit.

## Task 5: Docs and records

- [ ] Nested `plan_engine/CLAUDE.md`: a short stage-3 bullet pointing at `plan-engine-detail.md` (keep the addition under about 450 bytes of the L54 headroom, or run `dart run scripts/check_context_artifact_budget.dart --record` and say so); reword the falsified lines (`:63` "NEVER crosses boundaries", the attempt-5 "fewer-but-safe" line, and the "all five" capability row to "seven", naming `pickV4`, `_pickCoreList`, `buildPinnedDays`, `_applyHistoryAdjustments`, `_fillSlots`, `_cascadeFill`, `topUpDays`: six declare `required Set<String>? capability` today, `topUpDays` is the seventh) and the two comments `exercise_selector.dart:544` / `:1289` ("movement_pattern is NEVER dropped") with a pointer to the post-pass.
- [ ] `docs/sot_registry.yaml` "all five" note → seven (same list); `docs/naming_conventions.md` rows; `plan-engine-detail.md` section.
- [ ] `.claude/skills/debugging/bug-classes.md`: a new class (a filter that drops a slot leaves a short day; d30de7 exposed it) with the regression test paths, and edit `:1842` ("OI-401 owns the top-up" becomes "closed by 2d04d7"); the SKILL.md row.
- [ ] Closure ledger `docs/audit/thin-day-topup.closure.yaml` (every item terminal; the residual `upstream_blocked`; R9 `upstream_blocked`); in `library-injury-recheck.closure.yaml` flip PAIRS-EMPTY-DAYS and THIN-DAYS to `closed_in_commit` with the labelled branch state `thin-day-topup@branch` (a merge SHA does not exist before the commit that carries the ledger; `scripts/validate_audit_closure.dart` accepts the `@branch` label, as `library-injury-recheck@branch` does), or repoint to the residual OI and fix the BPASS-F3 text that names the deleted constants.
- [ ] `docs/ship_dark_pending_review.yaml`: add the R9 question to the `enable_core_list_pool` note.
- [ ] OI-401: set Status CLOSED and archive to `closed_issues.md` in the commit that carries the trailer `closes-oi: OI-401` (`scripts/check_closes_oi_cited.dart`); the residual OI stays OPEN.
- [ ] Fill the mutation table in the diagnose-doc and set `status: fixed`.

## Task 6: Gates, review, merge

- [ ] Full gate loop (§4.12.8): `flutter analyze` (whole project, `--no-fatal-infos`, as the pre-push hook runs it), full `flutter test` with `TZ=Asia/Kolkata`, the pre-commit loop. Self-triggered `/code-review` B-pass, and the review file carries its own `## Tuning entry` section (SKILL.md section 1); `tuning-history.md` is frozen and a commit that adds a dated bullet to it is blocked (`scripts/check_skill_tuning_history.dart`). Plan-review record `docs/plan-reviews/thin-day-topup.md` (branch `thin-day-topup`; `recordSlug` leaves it unchanged) in its own later commit. Push over HTTPS with `safe_push.sh`, PR, monitor, merge with `safe_pr_merge.sh`, read the sweep shard's duration on the PR run (Task 3 Step 5), retire the worktree.

## Appendix A: neighbour table (closest first; the own pattern is tried before it)

| pattern | neighbours |
|---|---|
| horizontal_push | vertical_push, elbow_extension, shoulder_isolation |
| vertical_push | horizontal_push, shoulder_isolation, elbow_extension |
| horizontal_pull | vertical_pull, shoulder_isolation, elbow_flexion |
| vertical_pull | horizontal_pull, elbow_flexion, shoulder_isolation |
| knee_dominant | hip_dominant, hip_isolation |
| hip_dominant | knee_dominant, hip_isolation |
| elbow_flexion | horizontal_pull, vertical_pull |
| elbow_extension | horizontal_push, vertical_push |
| shoulder_isolation | vertical_push, horizontal_pull |
| hip_isolation | hip_dominant, knee_dominant |

The table is the prototypes', which produced the measurements above. It is a movement-pattern adjacency chosen by me, not a founder ruling.

## Resolution map (round 1)

| Finding | Resolution |
|---|---|
| A1 = B2 (P1) seam gate | R10, Task 2 Step 4, file table; single `queryV4` call site |
| A2 (P1) own pattern | Architecture stage 1, R6, tests `own pattern first`, `pinned: own pattern`, M15; numbers re-measured (prototype 2) |
| A3 (P2) R6 avoid sets | R6 rewritten; lower-casing; A avoids B; demoted; M5a to M5d; `phase` and `previousPhaseByDay`/`plateauAvoidNames` in the signature |
| A4 (P2) foundational | R5, M16, `phase 1 prefers foundational` |
| A5 (P2) R8 count and cause | R8 rewritten (scan days versus plan days, 16 safe rows outside the stage list, two causes, founder-visible) |
| A6 (P2) repeated queries, wall time | exhausted-key memo; Task 3 Step 5 timing; Review Focus 6 |
| A7 (P2) alias wording | R6 alias rule from the input; content parity test; pinned-equal-content stated |
| A8 = B9 part (P2) R3 | R3 cites §4.6 and the two precedents; rollback is a build |
| A9 (P2) other producers | "Out of scope, and why" |
| A10 (P2) goal wider than input set | Goal and Measured reworded; exclusions persona; R2 trigger wording |
| A M1 = B12 | 974 |
| A M2 | Task 0 Step 1 "confirm clean" |
| A M3 = B11 | personas named in Task 2 |
| A M4 | `(priority, index)` sort |
| A M5 | return `days` when unchanged |
| A M6 | Task 5 reworded lines; naming (`ThinDayTopUp` class, `thinDayTopupEnabled` getter, `disable_thin_day_topup` key) |
| B1 (P1) commit order | Task 2 Steps 6 and 7: diagnose-doc and SoT in the first code commit with `closes-diagnose: 2d04d7`; mutation table later |
| B3 (P1) equipment leak | Global Constraints, equipment oracle test, sweep `unperformable`, M10 |
| B4 (P2) "pinned by the sweep (3 exits)" false | Review Focus 1 reworded; B1-ON persona named with asserted precondition; R9 tracker entry |
| B5 (P2) tests green on main | kill-switch test asserts both halves; the Periodization test rewritten; the uninjured plan test labelled a guard |
| B6 (P2) mutation gaps | M3 rewritten, M11 to M16 added, M5 split; "before any Hive read" claim dropped |
| B7 (P2) residual is a count | thin keys must equal `{shoulder+lower_back}`; labels in the report |
| B8 (P2) stale text | Task 5 (closure entries, `bug-classes.md:1842`, naming rows, "six", L54 headroom, `ship_dark_pending_review.yaml`) |
| B9 (P2) process steps | `closes-oi` trailer, plan file committed in Task 0, tuning-history entry, evidence copied into the diagnose-doc |
| B10 (P2) sweep runtime | Task 3 Step 5, Task 6 |
| B11 (P2) test-design details | personas named; JSON tag oracle; flag no-Hive file; alias through `pickV4` |
| B13 (M) golden command | Task 3 Step 3 |
| B14 (M) `kMovementPatterns` | Task 1 |

## Resolution map (round 2)

| Finding | Resolution |
|---|---|
| A-r2 F1 (P2) R8 count and cause | R8 rewritten: VolumeFilter trim, about 22 rows incl. 5 biceps and 2 triceps, three ways to change it; Task 0 Step 2 |
| A-r2 F2 (P2) R3 precedents | R3 rewritten: the two flags DROP moves, `holdWeeksEnabled` is the adds-material precedent; the 70% Plank + Dead Bug exposure |
| A-r2 F3 = B-r2 F8 (P2) sweep time | Measured last bullet (sources, 27:02 loaded, synchronous `@Timeout`); Task 3 Step 5 decides by number (split over about 14 minutes), shard rotation named |
| A-r2 F4 (P2) R6 wording | R6: A avoids B's names whenever non-alias and non-strength; plateau lower-cased in `topUpDays`; flag value named in `B differs from A` |
| A-r2 F5 = B-r2 F5 (P2) fresh() test | Review Focus 4 reworded; idempotence test; all-pins-dropped persona test; no-mutation statement |
| A-r2 F6 (P2) demoted read | Global Constraints and R6: one extra lazy call |
| A-r2 M1 to M4 | R6 equal-content sentence; `<PlannedExercise>[...]` note; "if no day was thin"; avoid union in `topUpDays` |
| B-r2 F1 (P2) M10 equivalent | exclusions persona named with a precondition; M10 catcher changed; M10b added |
| B-r2 F2 (P2) M3 / `applies` | `topUpDays` calls `applies`; M3 deletes both |
| B-r2 F3 (P2) compile | Task 2 Step 1b stub; Step 2 reworded |
| B-r2 F4 (P2) knee+hip cannot see M13/M15 | exact names pinned; disjoint-slots direct test; M13 and M15 catchers |
| B-r2 F6 (P2) foundational persona | foundational persona and phase-1 scope in Measured |
| B-r2 F7 (P2) core_list_pool_gate | R9 and Task 3 Step 1 |
| B-r2 F9 (P2) demoted seed, M5e/M5f | seed shape in the test list; M5e, M5f |
| B-r2 F10 to F13 (M) | "seven"; analyze whole project, commit cites test path, `test(...)` subject, `thin-day-topup@branch`, record filename; scan-day wording; both files saved before mutating |
