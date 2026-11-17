# Delete the 3A and 3C kill switches (OI-514, OI-516)

Version 3.1, 2026-11-17 (v1 + review rounds 1-3, all folded in; round 3 converged; log at the end).

- **Branch:** `generator-killswitch-3a3c`, base main 421cd2d2.
- **Blast radius:** platform (plan engine).
- **Execution mode:** inline, two commits: the base-tree recording (§4 step 1), then the deletion (§4 step 2).
- **Review:** x2 before the build (CLAUDE.md §4.12.4: removing a kill switch takes the full review again), then a
  B-pass.

## 0. Why now, and what gates the merge

- **OI-514 (`disable_goal_training`, Unit 3A) and OI-516 (`disable_cardio_finisher_shown`, Unit 3C):** each is
  "done when the founder's device check passes" (board t308).
- **The founder's check, 2026-11-17 (PRO account):**
  - Passed: the goal list; the 90-minute chip leaving at Intermediate; Cut / Maintain reps, accessories at 15; the
    finisher on two days.
  - Still open: the Strength focus (range floor, +30 s rest at 60+); Train == Home minutes with the finisher; the
    finisher's injury rule; hold weeks.
- **Rule:** build, reviews and CI run now. The MERGE waits until the founder reports the open 3A / 3C items. Hold
  weeks (3D) have no switch here.
- **Also in this commit:** `docs/audit/generator-step5.closure.yaml` S5-A / S5-B go `blocked_on_user` ->
  `verified_clean` (founder d84 / d85, 2026-11-17).

## 1. The one technique: a two-tree oracle for every re-recorded fixture

Several tests set our switches only to keep a fixture equal to an older main, or to measure their own unit without the
finisher. A re-record on the deletion tree would pin whatever that tree emits (round 1 P1-4: self-referential).
Instead, every fixture this plan re-records is produced on the BASE tree (421cd2d2, before any lib/ edit):

1. Remove (or replace, §3.4) only the test lines that set our two keys.
2. Record.
3. Commit that recording.
4. Make the lib/ deletion.
5. The deletion tree must reproduce every recorded fixture byte for byte.

**Why this works.** On the base tree, "both keys unset" is the default world. The deletion's claim is that the default
world does not change. So a reproduced fixture proves the deletion changed nothing that fixture sees.

**Byte-identity reasoning** (round 1 P2-3, verified):

- `shown ?? flag` and the flag getters both default to true.
- `goalTrainingFromProfile`'s catch returns `const GoalTraining()` in both trees.
- `_bands` and `_goalBands` have the same 4 keys, so `_goalKey` is unchanged.
- `weeklyBand`'s default already selects `_goalBands`.
- `FinisherShowContextReader.read()`'s catch already returns `enabled: true`.

## 2. lib/ changes

### 2.1 OI-514 (goal training)

| Site | Change |
|---|---|
| `plan_engine_flags.dart:80-89` `goalTrainingEnabled` + its doc (which also describes `quadPrimaryCreditsGlutes`'s default read) | deleted |
| `session_budget.dart` `GoalTraining.enabled`, `GoalTraining.off`, the class doc `:636-638` | deleted; `GoalTraining({strengthFocus})` stays |
| `session_budget.dart` `_bands` (`:506-527`), its mention in the `_goalBands` doc (`:538`) | deleted; `_goalKey` reads `_goalBands.containsKey` |
| `session_budget.dart:570-571` `weeklyBand(..., {bool goalTraining})` | parameter deleted; always `_goalBands` |
| `session_budget.dart:443` doc, `:449-456` `restForGoal` | the switch sentence and `gt.enabled &&` removed |
| `session_budget.dart:683`, `session_set_allocator.dart:1664`, `volume_titration.dart:203` | the `goalTraining:` argument removed |
| `goal_reps.dart:46-58` `GoalReps.base({required bool enabled})` | parameter, its doc sentence and `!enabled ||` removed |
| `periodization_engine.dart:293` doc, `:312`, `:327` | `enabled:` argument and `gt.enabled &&` removed |
| `split_resolver.dart:423-428` `quadPrimaryCreditsGlutes({bool? goalTraining})` | parameter deleted; the 4-day Maintain arm unconditional |
| `training_history_analyzer.dart:121-135` `goalTrainingFromProfile()` | name and return type kept (callers `plan_generator.dart:337`, `swap_service.dart:561`); the switch read, `GoalTraining.off` return and doc sentence removed |

### 2.2 OI-516 (finisher shown)

| Site | Change |
|---|---|
| `plan_engine_flags.dart:66-76` `cardioFinisherShownEnabled` + doc | deleted |
| `cardio_finisher.dart:31` doc, `:62-64` doc, `:70-92` `plan({bool? shown})` | parameter and the `!enabled` branch deleted; docs rewritten |
| `finisher_safety.dart:17-26` `shownFinisherMaps({required bool enabled})`, `:42`, `:58-64` `FinisherShowContext.enabled` | the parameter and field deleted |
| `finisher_show_context.dart:18-34` `read()` | no switch read; catch returns `FinisherShowContext(injured: true)` |
| `lib/features/train/providers/preview_plan_provider.dart:166-176` (round 1 P1-1) | `enabled:` argument and the "switch off -> 0" comment removed |
| `session_budget.dart:612-615` doc | "the switch" removed from the reasons a map is empty |
| `CardioFinisher.debugReserve` | stays: a test seam, now also the finisher-free measuring world of §3.4 |

**Stored rows.** A plan generated while the switch was set stored today's finisher, unreserved. Today it shows nothing
(the reader checks `enabled`). After this commit it shows that finisher under the injury rule. That reaches only a
device where someone set the dev key. Pre-launch, every account is a testing account (CLAUDE.md §1), and a regenerate
rewrites the rows. Stated, not built. Outside plan_engine, no reader names the key: `lib/features`, `lib/core` and
`supabase/functions` were grepped (round 1 P2-4). Every display goes through `FinisherShowContextReader`.

### 2.3 `plan_generator.dart` (rule 14)

`:335-336` is a comment naming `disable_goal_training`; the call is unchanged. The comment-only edit needs the founder's
waiver, as in d83. Granted by the founder on 2026-11-17 ("1. Ok"). Without it, the comment stays and the plan-engine CLAUDE.md says it is stale.

### 2.4 Docs

- **Per-concept docs:**
  - `docs/naming_conventions.md:307-308,313`: both key rows are marked retired; the `GoalTraining` glossary row
    drops `enabled`.
  - `docs/sot_registry.yaml`: in `goal_training`, the description `:12450-12460`, the `goalTrainingEnabled` writer
    `:12470`, the readers that name `goalTraining:` (`split_resolver`, the `weeklyBand` readers) or `semantic: flag-check`
    (`finisher_safety`, `finisher_show_context`) and the reader `goal_training_gate_test.dart`'s semantic ("ON vs OFF" becomes "against the recorded
    pre-3A baseline"); in `cardio_finisher_shown`, the prose `:10886-10888`.
- **CLAUDE.md files:**
  - Plan-engine `CLAUDE.md`: the 3C bullet (stage 7), the 3A bullet (including `Fx(goalTraining: GoalTraining.off)`).
  - `lib/features/train/CLAUDE.md`: the `cardio_finisher_shown` row loses "switch off -> none".
- **Closure and OI records:**
  - `docs/audit/generator-step3a.closure.yaml:46` gets a note that `goal_training_kill_switch_golden_test` was deleted
    with the switch (this commit).
  - OI-514 and OI-516 are archived to `closed_issues.md` (append only).
- **Not needed:** no `ship_dark_pending_review.yaml` row (both switches were default ON from the start); no script,
  blast-radius or gate-ledger entry names the deleted files (round 1 grep).

## 3. Tests

### 3.1 Deleted

- `goal_training_kill_switch_golden_test.dart` + `generator_golden_hashes_goal_training_off.json`.
- `finisher_kill_switch_golden_test.dart` + `generator_golden_hashes_finisher_off.json`.
- `finisher_attribution_golden_test.dart` (round 1 P2-2). Its claim (1) compares against the OFF world, and its
  claim (2) attributed 3C's re-record, which is done. `debugReserve` stays a seam and is used by §3.4 and
  `cardio_finisher_shown_pure_test.dart:175`.

### 3.2 Cases deleted, everything else kept

| File | What goes |
|---|---|
| `cardio_finisher_shown_pure_test.dart` | `enabled: false` assertions (`:80-110`); the `shown: false` cases (`_plan(shown: false)` `:158`, `:194`, the "off hiit" fixture); `enabled:` dropped elsewhere |
| `finisher_display_behavioral_test.dart` | `:205` "the switch hides it everywhere"; `:216` `enabled:`; the `:149`, `:157` deletes of the key become no-ops and are removed |
| `cardio_finisher_reservation_behavioral_test.dart` | cases setting the key (`:165`, `:202`, `:225-227`, `:247-249`) and the `:83`, `:91` deletes |
| `coach_injury_profile_write_behavioral_test.dart:201` | `enabled: ctx.enabled` dropped |
| `goal_reps_behavioral_test.dart` | the helper's `enabled` parameter `:15-17`; `:74` (`base(... enabled: false)`); `:86`, `:116`, `:136`, `:321` (`GoalTraining(enabled: false, ...)`); `:87` (`GoalTraining.off`); `:151-153`; `:282-283` (`gt: GoalTraining.off`); `:328` (the `q(..., false)` case) |
| `session_budget_test.dart:255-256` | the `goalTraining: false` arm |
| `balanced_week_behavioral_test.dart:515-530` (round 1 P1-2) | the S2 sweep stops passing `goalTraining: false`; `_creditRule` gains the 4-day general_fitness arm (any minutes, either `quadLegsB`, either switch); the `falses` count is recomputed from the rule; the comment "held off here" is rewritten |
| `swap_exercise_rest_follows_incoming_archetype_test.dart:188-191` | the case writing `disable_goal_training` |
| `test/helpers/session_budget_fixtures.dart:9-10` | the doc line about `GoalTraining.off` |
| `plan_audit_dump_test.dart:81`, `:119`; `history_sim_dump_test.dart:168`; `titration_plateau_gate_test.dart:164` | `goalTraining: PlanEngineFlags.goalTrainingEnabled` dropped; the `PLAN_AUDIT_DISABLE` example names another key |
| `generator_golden_test.dart:17`, `:22`; `lead_first_gate_test.dart:49-50` | comments naming the key or the deleted golden; hashes untouched |

### 3.3 Crafted fixtures re-derived on the goal bands (round 1 P1-3)

The 8 sites build on a pre-3A band. Moving them to another goal or level changes the cap, the bottom and the credit,
so each expectation is recomputed in place on the goal band:

| Site | Today's arithmetic | On the goal band (Maintain beginner 7-8, intermediate 8-11) | Shape change |
|---|---|---|---|
| `day_floor_behavioral_test.dart:272`, `:298` | Maintain beginner 10-10; five later days at 2 sets = Chest 10 | top 8: five later days at 2 = 10 > 8, cannot occur | four later days -> three (or 2 + 2 + 2 + 2 = 8), so the day count, `is6Day` and the A / B variants change; every `seats` expectation re-derived |
| `day_floor_behavioral_test.dart:365` | Chest top 10, "Back 10 from days 1-5", weekly 14 | top 8 | as above: fewer later days |
| `session_set_allocator_behavioral_test.dart:67` (rank-0 reservation) | `[3, 3, 2, 2]`, weekly Chest 10 | top 8 | sets re-derived; the reservation still decides |
| `session_set_allocator_behavioral_test.dart:111` | four later days at 2 = 8, day 0 "2 then 5" | top 8 leaves day 0 nothing | three later days |
| `allocator_timed_hold_eviction_behavioral_test.dart:519` | days 1-5 seat Quads at 2 (week 10), then the forced day | top 8 | four days (week 8), then the forced day |
| `exercise_count_band_behavioral_test.dart:245` (round 2 P2-3: Maintain BEGINNER, Chest top 10, cap 6) | `weekly['Chest'] == 10`, floored `10 + 4 x 2 = 18` | top 8 | re-derived as SEATS, not sets (round 3 P2-2): the first pass seats 4 at 2 (top 8; rows by the test's own shape, lead-first seating at 3 may change it), the floor's seats counted from the rows the test builds; the build runs the test and states the rows in the comment |
| `session_set_budget_consumers_test.dart:220` (Maintain intermediate, top 12) | 3 + 3 + 4 = 10 leaves two sets, one to each rank-0 lift | top 11: one set left, the mechanism is gone | start from 3 + 3 + 3 = 9 so two sets remain; `[4, 3]` / `[5]` recomputed |

None of the 8 looks impossible (round 2). Per site, three steps:

1. Restate the arithmetic in the comment with the new numbers.
2. Change the fixture's sets or the asserted values so the SAME mechanism decides the outcome. For example,
   `:220`'s rank-major test keeps two lifts competing for room by starting from 3 + 3 + 3 = 9.
3. Apply one mutation of the mechanism the test names and record that it turns red (§5).

A site whose mechanism cannot be reproduced on a goal band is reported in the diagnose doc, not loosened.

### 3.4 Tests that set our keys to measure something else (rounds 1 and 2)

**A. Other units' kill-switch OFF goldens.**

- Files: `lead_first_kill_switch_golden_test.dart:54,56`, `loaded_wins_kill_switch_golden_test.dart`,
  `balanced_week_kill_switch_golden_test.dart:53,55`. Each sets our two keys so that its OFF digest equals main at that
  unit's merge.
- None has a record mode (they compare at `:71-78` / `:72-79` / `:69-76`). Loaded-wins' fixture was written by
  `generator_golden_test` on a past tree.
- In the base-tree commit, each gets an env-guarded writer (`RECORD_KILL_SWITCH_OFF=1`), the two lines are removed,
  and the fixture (`generator_golden_hashes_{lead_first,loaded_wins,balanced_week}_off.json`) is recorded.
- The deletion commit removes the writers. The header changes from "equals main at the unit's merge" to "equals the
  OFF world recorded on 421cd2d2 with our two keys unset".
- Per file, the diagnose doc records: the keys that moved against the old fixture, and the keys equal to the ON
  golden.

**B. The day-floor kill-switch test and the day-floor gates.**

- `day_floor_kill_switch_test.dart` (`RECORD_DAY_FLOOR_HASHES=main|on`, `setFlags` `:53-55`). `main` mode records
  `digest|block|tier` with no flags. `on` mode records `fl_on` keys, recorded with the 3A / 3C keys set. Its
  `expect(changed, 18)` (`:145`) can move once both sides are in the live 3A / 3C world: re-measured on the base tree
  and re-pinned in the base commit.
- `day_floor_gate_lib.dart`:
  - `_gen(goalTrainingOff:)` (`:93-118`): the goal-training key write goes. The finisher key becomes
    `CardioFinisher.debugReserve = false` (§3.4 C).
  - The pins (`:260-284`, generated live with `disable_balanced_week`, `disable_goal_training` and
    `disable_cardio_finisher_shown` set): the goal-training write goes, the finisher becomes the seam, and
    `disable_balanced_week` stays.
  - The gate's own OFF digests come from `_gen(floor: false, ...)`, which the existing record mode does not produce
    (round 2 P1-3). `finish()` gains an env-guarded record path (`RECORD_DAY_FLOOR_GATE=1`) in the base commit; the
    deletion commit removes it.
- The gates `day_floor_gate_rep30_test.dart`, `day_floor_gate_pairs_p1_test.dart`, `day_floor_gate_pairs_p4_test.dart`:
  their `_expected` tuples (runs, day-weeks, thin OFF, gained, knock-on, lead + 2 OFF, 2C-b swaps) move, because the
  pins and the OFF world now carry goal training (round 2 P1-2).
  - The tuples are re-measured on the base tree (§6) and edited in the base commit, with each moved column explained
    in the header the way 3C's knock-on change was.
  - The `finish()` reason and the lib header stop saying "= main 8a2e1c5a".

**C. Gates that measure another unit without the finisher's reserved time.**

| Gate | Where it sets the key |
|---|---|
| `repeat_minutes_gate_lib.dart` | `:93` |
| `oi489_timed_hold_real_engine_test.dart` | `:91` |
| `goal_training_gate_test.dart` | `:117`, `:403` (its d81 block runs the live world: the seam `true`) |
| `weekly_minimum_gate_test.dart` | `:90`, plus its tearDown list `:95` (round 2 P1-1) |

- The key becomes `CardioFinisher.debugReserve = false` / reset `true`.
- After the deletion, `debugReserve` is read only by the `reserved:` fields, and `reserved` only by `secondsByDay`, so
  this is the switch-set allocation with ON-shaped finisher maps (round 2 checked).
- Measured: §6.

**Round 3 P3 details:**

- `day_floor_kill_switch_test.dart:51-63`: `clearFlags()` resets `debugReserve = true`.
- `weekly_minimum_gate_test`: resets the seam in `tearDownAll`; its key list loses `disable_cardio_finisher_shown`.
- `goal_training_gate_test`: `identical(off).length == 92` is asserted only inside the record path.
- Comments naming the keys are reworded at `day_floor_gate_lib.dart:105-106` and `:259-262`.
- `day_floor_kill_switch_test`: its header and `_write`'s `_meta` string are reworded ("recorded on main 8a2e1c5a",
  "OI-506").
- The loaded-wins writer produces the same key set as the existing fixture; this is checked and stated in the
  diagnose doc.

**D. Gates that set no key** (`lead_first_gate_test.dart`, `balanced_week_gate_test.dart`): no change beyond comments.

**E. `goal_training_gate_test.dart`'s OFF world becomes a frozen baseline** (rounds 1 and 2).

- **The fixture.** One fixture, `test/fixtures/goal_training_gate_baseline.json`, recorded on the BASE tree in the OFF
  world, by the gate itself under `RECORD_GOAL_TRAINING_BASELINE=1`. The OFF world is the switch set plus
  `debugReserve = false`. The record path is deleted in the deletion commit. It holds:
  - item 1, byte-exact: the sha256 of the OFF `plan.toMap()` for each of the 1,152 build_muscle and strength keys
    (about 150 KB);
  - item 5: per key and week 1-3, a bitmask of the groups with sets > 0, computed with the OFF credit
    (`goalTraining: false`, as `shape()` does at `:150-151`);
  - item 6: the scalar `maxOver(off)`;
  - item 2: the OFF identical-pair count (92).
- **The Strength-focus test** compares against the same OFF grid (`newlyAtZero(off, focus)`, `maxOver(off)`), so the
  one baseline serves it.
- **Deleted:** its final block `:343-361` (the 48 plans proving "the switch overrides the focus") and the item-7
  sentence "With the switch set the focus changes nothing".
- **Unchanged:** items 3 and 4 need no OFF. Item 8's two ON digests are re-recorded on the base tree (§6: they moved
  only by the finisher maps).

## 4. Order of work

1. **Commit 1, the base tree** (no lib/ edit):
   1. the §3.4 A-E test edits, plus the four temporary record paths (`RECORD_KILL_SWITCH_OFF`,
      `RECORD_DAY_FLOOR_GATE`, `RECORD_GOAL_TRAINING_BASELINE`, and the existing `RECORD_DAY_FLOOR_HASHES`);
   2. record every fixture, in this order (round 3 P2-1):
      1. `day_floor_kill_switch_test` `RECORD_DAY_FLOOR_HASHES=main` combos, with its `digest|` loop SKIPPED (on the
         base tree `h.gen` with no flag is floor ON, not the gate's OFF);
      2. then the `on` combos;
      3. then the three day-floor gates, one file at a time (`--concurrency=1`): `writeDayFloorFixtureEntries`
         read-merge-writes one shared file;
      4. then the three OFF goldens and the goal-training baseline;
      5. finally, re-measure and edit the day-floor tuples and `changed`;
   3. run every touched test green;
   4. commit.
2. **Commit 2, the deletion:**
   1. the lib/ deletions (§2), the test edits (§3.1-3.3), the record paths removed;
   2. every touched test passes with no fixture, tuple or digest edited, and the 1,010-persona ON golden is unchanged.
3. Mutations (§5), the gate loop, the PR, CI, the B-pass, then the merge after the founder's checks.

## 5. Verification

1. **Fixtures:** `generator_golden_test.dart` passes with its fixture untouched, and every §3.4 fixture recorded in
   step 1 is reproduced in step 2.
2. **Mutations, each confirmed applied (`grep -c`) and each turning a named test red:**
   - (a) `weeklyBand` returns the old Maintain intermediate row (10-12);
   - (b) `GoalReps.base` returns `todayBase` for a main lift;
   - (c) the accessory clamp removed;
   - (d) `restForGoal` without the +30 s;
   - (e) `quadPrimaryCreditsGlutes` without the 4-day Maintain arm;
   - (f) `CardioFinisher.plan` ignores injuries;
   - (g) `shownFinisherMaps` always `[]`;
   - (h) the short finisher under 60 removed;
   - (i)-(p) one per §3.3 site, the mechanism the test names.
3. **Absence grep:**
   `git grep -n -e disable_goal_training -e disable_cardio_finisher_shown -e goalTrainingEnabled -e cardioFinisherShownEnabled -e 'GoalTraining.off' -e 'GoalTraining(enabled' -e 'FinisherShowContext(enabled' lib/ test/ scripts/`
   returns only `plan_generator.dart:336` (without the waiver); `flutter analyze` catches every other use.
4. **Gate loop and CI:** whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, then CI on the
   PR.
5. **Audit identity:** the 2,304-plan audit equals step 5's no-focus dump byte for byte.

## 6. Measured on the base tree (rounds 1 and 2)

§3.4 C on 421cd2d2 (scratch edits; `debugReserve = false` in place of the key, the d81 live block on `true`):

| Gate | Result |
|---|---|
| `oi489_timed_hold_real_engine_test` | 7 / 7 pass, unchanged |
| `repeat_minutes_gate_test` | 16 / 16 pass, unchanged |
| `goal_training_gate_test` | every count equals 3A's recorded line; only the two digests fail |

The `goal_training_gate_test` counts, all equal to 3A's:

- build changed 0;
- identical OFF 92, ON the two d63 pairs;
- mains 14,547, of which 3,601 at their bound;
- accessories 12,360, 0 misses;
- newly at 0: 0;
- max over the session OFF 6, ON 6;
- d81 green.

The two digests fail: the grid ON digest (`5fd58773...` -> `07aa902a...`) and the Strength focus digest
(`fd31107f...` -> `56672a99...`). They hash the plan maps, whose `finisher` entries now take the ON shape (round
rests, d76's short finisher). That is exactly 3C's attribution claim (1). The digests are re-recorded on the base tree
(§1) and must reproduce on the deletion tree.

**Second measurement** (after round 2), with the §3.4 B / C edits as scratch on 421cd2d2. The goal-training writes
were removed and the finisher became the seam, in `day_floor_gate_lib` (both `_gen` and the pins) and in
`weekly_minimum_gate_test`.

| Gate | Hard checks | Counts | Digest |
|---|---|---|---|
| `weekly_minimum_gate_test` | new majors 0; only Calves newly 0; row diff empty; max over <= 6; the fallback set | equal to the pinned (ON 657 / 495; OFF 587 / 537 / 28; Calves 143; zero weeks ON / OFF) | ON digest moved (`1c37a806...` -> `328f7b13...`) |
| `day_floor_gate_pairs_p1` | thin ON 0; bad {}; pins differ 0 | the four `_expected` tuples unchanged | OFF digests moved |
| `day_floor_gate_pairs_p4` | thin ON 0; bad {}; pins differ 0 | the four `_expected` tuples unchanged | OFF digests moved |
| `day_floor_gate_rep30` | thin ON 0; bad {}; pins differ 0 | tuples moved (below) | OFF digests moved |

The `rep30` tuples moved because its pins are now Cut / Maintain plans with goal training. Its pins come from the
uninjured 30-minute plan.

| Tier | Thin OFF = gained | Knock-on |
|---|---|---|
| bodyweight | 240 -> 148 | 55 -> 64 |
| home_dumbbells | 428 -> 392 | 66 -> 89 |
| basic_gym | 304 -> 272 | 41 -> 57 |
| full_gym | 128 -> 88 | 31 -> 35 |

- **What it means:** fewer pinned days are thin with the floor off, the floor gains exactly those, and more days give a
  set to a floor seat. The invariant "the floor loses nothing, no day under 3" holds.
- **The re-pin:** these four tuples are re-pinned in commit 1, explained in the rep30 header.
- **Also in commit 1:** the `day_floor_kill_switch_test` `changed` count is re-measured there.

Every measured gate keeps every hard zero in the post-deletion world. What moves is digests (finisher maps, or Cut /
Maintain plans with goal training) and one set of counts, which is explained.

## 7. Review log

- **Round 1** (2026-11-17, one context-blind Sonnet seat, on v1): not converged, 5 P1. All folded into v2:
  - P1-1: four missed `enabled` sites, including `preview_plan_provider.dart`, which would not have compiled.
  - P1-2: `balanced_week_behavioral_test`'s S2 sweep and `goal_reps_behavioral_test:321`.
  - P1-3: "move the fixture" is unworkable; recompute on the goal bands.
  - P1-4: self-referential re-records, replaced by the two-tree oracle (§1).
  - P1-5: the gate list was wrong, and `goal_training_gate`'s OFF oracle is kept on a frozen baseline.
  - P2-1: measure before building (§6).
  - P2-2: attribution test deleted.
  - P2-5, P2-6, P3: line lists.
- **Round 2** (2026-11-17, one context-blind Sonnet seat, on v2): not converged, 3 P1. All folded into v3:
  - P1-1: `weekly_minimum_gate_test` does set the finisher key.
  - P1-2: the day-floor gates' tuples move with the pins.
  - P1-3: no existing record path for the day-floor gate's OFF digests.
  - P2-1: record paths for the three OFF goldens.
  - P2-2: goal_reps lines.
  - P2-3 / P2-4: §3.3 arithmetic and shape changes.
  - P2-5: the baseline encodings, plus deletion of the focus-override block.
  - P3: two commits; sot reader entries `semantic: flag-check`; `lead_first_gate` comment.
  - Checked fine: the two-tree soundness, `debugReserve`, the §2 line references and lib/ completeness.
- **Round 3** (2026-11-17, one context-blind Sonnet seat, on v3): **converged** (no P0 / P1). Folded into v3.1:
  - P2-1: record order, the `main` digest loop skipped, one gate file at a time.
  - P2-2: `exercise_count_band:245` re-derived as seats.
  - P3: the `clearFlags` seam reset, the weekly-minimum teardown, the `92` literal, comments and headers, the
    loaded-wins key set.
  - Checked fine: the oracle soundness, the goal-training baseline covering every OFF use, the 8 fixture sites, the
    scratch edits matching §3.4.

## 8. Results (commit 2)

- **Two-tree oracle:** every touched test passes with no fixture, tuple or digest edited since commit 1 (c16ce1ea): the
  24 test files run by name: the 23 `_test.dart` files commit 2 modifies (`git diff --name-status c16ce1ea acc64f6a -- test`
  also shows 2 helpers modified and 5 files deleted) plus `generator_golden_test`, which it leaves unchanged. The modified ones are the day-floor kill switch, rep30 / p1 / p4, the three OFF goldens,
  the goal-training gate, the weekly-minimum gate, oi489, repeat-minutes, and the contract tests that lost switch cases.
- **Audit identity (§5.5):** the 2,304-plan audit with no focus, with the Strength focus, and the history simulation
  equal step 5's dumps byte for byte (`plan_dump.jsonl`, `audit.json`, `history_sim.jsonl`).
- **Mutations, each confirmed applied (`grep -c`) and each red in a named test:**
  - (a) Maintain intermediate band 8-11 -> 10-12: `goal_reps_behavioral_test` bands (1). `session_budget_test` pins
    only the beginner and advanced Maintain bands, so it stays green on this one.
  - (b) `GoalReps.base` returns `todayBase` for a main lift: 5 tests. (c) accessory clamp off: 2. (d) +30 s Strength-focus
    rest removed: 6 in `goal_reps` plus the swap test (1). (e) 4-day Maintain Glutes credit off: `goal_reps` (1),
    `balanced_week` S2 (1). (f) `CardioFinisher.plan` ignores injuries: 1 + 3. (g) `shownFinisherMaps` shows a jumping
    finisher to an injured user: 2 + 4 (a first version failed to compile and was discarded). (h) the short finisher
    under 60 removed: 2 + 2.
  - (i)-(p), one per §3.3 site: the rank-0 reservation `2 *` -> `0 *` (2 tests; the first fixture also pins
    `leadWorld == 'lead'`, because 2A's capped-world fallback seated the same sets), week 2 rank-major -> day-major (1),
    the empty-day guard's room check (2), the floor candidate filters (1 / 3 / 21), pass A2's weekly-top check (2).
- **A fixture that a fallback can reproduce needs a pin on which path ran** (the reservation case above).
- **Absence grep (§5.3):** `plan_generator.dart:335-336` (a comment) was reworded under the founder's comment-only
  waiver of 2026-11-17 (rule 14; the code is unchanged); the deleted names remain only in retired-name docs and in the `_meta` text of two fixtures
  (`generator_golden_hashes.json` `recorded_on`, byte-pinned; `goal_training_gate_baseline.json`, which names them on purpose).
