# Generator overhaul step 1, Unit 1A: fix the core-list picker while it is still switched off (v7: v6 converged after review #6, plus one execution amendment)

Status: v6 (v1 + review #1: 5 P1 + 8 P2; v2 + review #2: 3 P1 + 6 P2 + 2 P3; v3 + review #3: 2 P1 + 5 P2 + 3 P3; v4 + review #4: 1 P1 + 3 P2 + 2 P3; v5 + review #5: 1 P1 + 1 P2 + 1 P3; v6 + review #6: 0 P1, 3 P3 (converged); all folded in, section 10),
2026-11-08, branch `generator-step1-core-list` (worktree of the same name, based on origin/main 0633a121).
Execution mode: INLINE (one worktree, one writer), decided at batch start per CLAUDE.md 4.12.7. Approved to
code by the founder (2026-11-08, "1 and 2 both approved"), converged after review #6; the code half (R2-R5, R9 (ii)
and (iii)) is this branch, and the data Tasks wait for the founder's R1 / R7 signature. Plan-review record: `docs/plan-reviews/generator-step1-core-list.md`. Merge
route: `sh scripts/land_pr.sh <pr>`. Blast radius: `platform` (plan_engine) and `account` (library asset,
`docs/blast_radius.yaml:525`), classified with `scripts/blast_radius_from_diff.dart` before the record; tier L.
Review tier: `ship_dark_build` is allowed (OFF byte-identical, section 5) but the unit takes the full x2 plus
B-pass (`bpass: accepted`, platform). Task board: https://claude.ai/artifact/QVpiDjC2KnfPSDh4wVdVEs.

**Why two units (CLAUDE.md 4.12.1).** Switching the pool on and deleting the old path touches 36 test files that
call `generateV4` / `pickV4`, the exercise-seam gate (`scripts/exercise_seam_lib.dart:59`, `SeamEntry(18, ...)` (17 before R4 added the hasCoreFields read)),
43 SoT registry lines, the `hasCoreFields` v12 guard and the founder's thin-day floor. So:

- **Unit 1A (this plan):** every core-list fix with the pool still OFF and OFF byte-identical; it measures the ON
  world the flip decision needs.
- **Unit 1B (its own plan, written on 1A's merged, measured tree):** the flip and everything in section 9.
  Every 1B item is an `upstream_blocked` entry in this unit's closure ledger (section 8), so nothing is dropped.

## 0. Why

The founder's 2026-11-08 review of 2,304 generated plans found household substitutes (Self-Resisted Curl,
Towel Row, Doorway Row) in 1,466 of 1,728 equipped plans live. The core-list pool (Batch B1, ship-dark since
2026-10-22) cuts that to 58 but has its own defects (OI-485) and open flip criteria (OI-436). Founder decisions
of 2026-11-08: fix the core-list path, rank by equipment fit, add the missing equipment variants (OI-148),
switch it on, delete the old path.

## 1. Measured baseline

Source: the 2,304-plan audit (session scratchpad `audit.py`; Task 1 commits it). Grid: 4 goals x 3/4/5/6 days x
3 levels x 4 tiers x 30/45/60/90 min x phases 1-3; no injuries, no history (so no previous-phase avoid set), no
focus.

| measure | live (OFF) | core-list (ON) | Unit 1A target (ON) |
|---|---|---|---|
| plans with a household substitute while the user has real equipment | 1,466 of 1,728 | 58 | 0, or each named |
| plans with an unloaded pick where a loaded row fits | 1,700 | 1,505 | a named residue (Task 4 lists it) |
| Strength 4-day gym OHP Day whose overhead slot is Pike Push Up | 36 of 56 | 56 of 56 | 0 |
| plans with a major muscle at 0 sets in week 1, 2 or 3 | 84 | 309 | no plan worse than its live twin |
| week-1 days opening with a non-compound | 4 plans | 310 plans (445 days, every one E193 Jump Squat) | no worse than live |
| plyometric rows in week 1 (E193, G3582; the gate also reports E066, and G1472 / G3361 are core jump rows too) | 0 | 1,273 (573 as the lead) | 0 |

Core-list gate report (`test/plan_generator/core_list_pool_report.md`; 998 golden personas = 960 grid across 4
tiers x 3 levels x 3-6 days x phases 1-5, plus 24 injury, 4 exclusion, 4 owned; plus the 576-run multi-injury
sweep): `emergencyAnyLevel` 2 personas (shoulder-injured bodyweight 4-day intermediate p1, p2) and 40 sweep runs;
`refilled` 16 runs; retired ids in built lists E271, E261, E254, E234; top-up retired additions E261, E271;
high-impact picks E193 x726, G3582 x288, E066 x24; E010 Pike Push Up x1,718; drop table (`:21-34`) as quoted in
OI-485.

## 2. Root causes (writer, reader by file:line)

1. **No equipment fit (OI-484).** Order writer: `CoreListSelector.rankedPool` keys
   `core_list_selector.dart:272-281`, tie by id `:288`; reader: `_pickCoreList` -> `_selectCandidate`
   (`exercise_selector.dart:843-847`) -> `_preferNovel` (`:1585-1596`), which returns the first candidate NOT in
   the avoid set (previous phase, plateau, upper-day feeders, B's soft avoid, demoted; `:820-824`). E010 and E011
   tie on every key, E010 wins on id. The improvised FILTER (`:254-266`) covers 5 patterns (`:63-69`). Because
   `_preferNovel` walks past the ranking, an ORDERING key cannot keep a row out of a pick; only a pool
   partition can (review #2 G1).
2. **No non-jumping squat for advanced home and bodyweight users (OI-485 a).** Data: `core_levels` (E rows in
   `assets/data/exercise_library.json`; G and N rows in `scripts/data/library_batch_c_source.json`, imported by
   `scripts/add_library_batch_c_v15.js`). Reader: `rankedPool` core pool `:215-221`; D6 keeps a lower level's row
   out (spec `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md`, D6, founder 10-21).
3. **No hinge above beginner for bodyweight users (OI-485 b).** Bodyweight hinge rows (hip_dominant, the
   Hamstrings compound slot, priority 1 on most legs days) on a list: E253, N11, `[beginner]`. The Hamstrings
   curl slot (knee_dominant isolation, priority 2-4, e.g. `split_resolver.dart:508,569,643`) is a family fill
   today (E230, N08, E046), not a drop (review #2 G5).
4. **Jump rows compete as strength rows, and E193 is the only bodyweight calf row above beginner (OI-485 c).**
   No `high_impact` / `plyometric` term in `rankedPool`. E193 lists Calves; G1373 is `[beginner]`, G1387, G0742,
   G1490 are on no list. `_pickCoreList` builds with `typeOverride: CoreListSelector.typeFor(...)`
   (`exercise_selector.dart:848-849`, stored at `:1815`), which always returns `compound` or `isolation`
   (`core_list_selector.dart:101-106`), so `SequencingEngine._isCompound` decides on the type
   (`sequencing_engine.dart:98-100`): E193 in a Quads compound slot is a compound, bilateral, CNS 5 by name, and
   leads the day.
5. **The top-up adds retired rows (OI-401 R9 question).** `topUpDays` (`exercise_selector.dart:1183`) and
   `_topUpVariant` search with `queryV4` (`:1304`, inside the `[foundational, relaxed]` loop at `:1302`), so they
   add E261 / E271 for injured users. Three exits call it: ON return (`:614`), OFF cascade tail (`:731`),
   `buildPinnedDays` (`:1141`).
6. **OI-436.** A day of the shoulder-injured bodyweight 4-day intermediate build empties both variants and reaches
   the any-level emergency (`_pickCoreList` `:890-900`).
7. **Thin bodyweight sessions above beginner (D6 gaps).** Bodyweight-only users above beginner have only improvised
   biceps / delt rows, none on an intermediate or advanced list, so those slots drop (drop table). Accepted by D6 on
   10-21; the flip criteria still need the founder's call.

## 3. Rulings

**R1 Core-list data (founder signs; coaching choice).** Add a level only where `suitable_for` holds it,
`discipline: strength`, `requires_coaching: false` (verified for every row by review #2), and a measured gap is
filled:

| row | slot it serves | today | add |
|---|---|---|---|
| E038 Goblet Squat, G0413 Dumbbell Squat, G0336 Dumbbell Lunge, G0381 Dumbbell Rear Lunge, E044 Step Up | Quads compound (dumbbells) | beg, int | adv |
| E042 Walking Lunge | Quads compound (bodyweight) | beg, int | adv |
| E143 Skater Squat, G1476 Single Leg Squat | Quads compound (bodyweight) | none | adv |
| G0411 Dumbbell Single Leg Squat | Quads compound (dumbbells) | none | adv |
| N11 Backpack Romanian Deadlift, E253 Bodyweight Good Morning | Hamstrings hinge (bodyweight) | beg | int, adv |
| E292 Sliding Leg Curl | Hamstrings curl (towel) | beg | int, adv |
| N08 Hamstring Walkout | Hamstrings curl (bodyweight) | none | int, adv |
| E046 Nordic Curl | Hamstrings curl (foot anchor; hard eccentric, founder call) | none | adv |
| G1373 Bodyweight Standing Calf Raise | Calves (bodyweight) | beg | int, adv |
| G1387 Single Leg Floor Calf Raise, G1490 Staircase Calf Raise | Calves (bodyweight / elevated surface) | none | int, adv |
| E291 Single Leg Glute Bridge | Glutes hinge (bodyweight) | beg, int | adv | new in v5 (review #4 J4): without it the bodyweight advanced Glutes slot pool is [E253, N11], two hinges |

G1490 is new in v3 (review #2 G1): with two calf rows, variant B's soft avoid of A's two calf picks and phase 2's
avoid set used both up. With R2's partition the jump row is out of the pool anyway, but three rows keep B and
phase 2 from repeating A. G and N rows change in the Batch C source (`_meta.derived.core` moves, checked by
`library_batch_c_rows_contract_test.dart:243-250`), E rows in the library JSON; importer `--check`; the core-field
counts (`exercise_library_core_fields_contract_test.dart:140-147`) are re-derived from the data.

**R2 Jump rows are partitioned out (replaces v2's ordering key, review #2 G1).** In `rankedPool`, BEFORE the
improvised filter (review #3 H7: a lone plyo-box implement row such as E066 Box Jump must not survive the
improvised filter and leave a jump-only pool): when the pool holds at least one row that is neither `high_impact == true` nor
`discipline == 'plyometric'`, remove the jump rows. Same shape as the improvised filter, so `_preferNovel` cannot
reach them. A pool of only jump rows keeps them (never empties a slot); after R1 no pool on the gate's personas is
jump-only (review #2's simulation), and R9 (i) makes any jump pick a CI failure. `typeFor` is unchanged: with the
partition a jump row is never in a mixed pool, and retyping would change rest pricing (`session_budget.dart:219`)
for no case that remains. (v2's sentence about the name-table fallback was wrong for the ON path and is removed.)

**R3 Equipment fit, as a filter and a key (review #2 G1, G3, G6).**
(a) Filter, like-for-like only (narrowed after review #3 H2, H4). The existing filter on `_implementPatterns` is
unchanged. NEW: in an isolation slot of any other pattern except `core`, for a user whose capability holds an
implement: when the pool (after R2) holds a like-for-like implement row, one whose `exercise_type` contains
`isolation` AND whose first `primary_muscles` entry names the slot's muscle: lower-cased, it equals the slot's
`targetMuscle` lower-cased, or it is `<target> (<head>)` where `<head>` is in an explicit same-muscle head table,
`{calves: {gastrocnemius, soleus}}`, compared lower-cased as a full match of the string `<target> (<head>)`, never a prefix (v6, review #5 K1: under raw equality E051 Standing Calf Raise "Calves
(Gastrocnemius)" and E052 Seated Calf Raise "Calves (Soleus)" were dropped and the soleus slot lost its only soleus
row). Nothing else is stripped: "Glutes (medius)" is a different muscle's job and deliberately does not match
"glutes". The pool is
REDUCED TO the like-for-like implement rows (v5, review #4 J2: removing only the improvised rows left compound
rows such as Goblet Squat and Leg Press behind Leg Extension, and E110 behind E109, which variant B or phase 2 then
picked once the first row was avoided). A one-row pool is accepted: variant B and phase 2 repeat that row, which
Task 4 reports per cell. Otherwise the pool is left as it is.
Two slots of the same muscle on one day (Calves, then Calves `soleus`, `split_resolver.dart:568,573`) share the
day's `picked` set (`exercise_selector.dart:813-819`): when the first slot takes the only like-for-like row, the
second slot's pool holds none, is not reduced, and can take a household row (review #5 K2: home_dumbbells beginner
and advanced, basic_gym beginner; the live world gives the same G1373 there, so it is not a regression). R9 (ii)'s
`likeForLikeImplement == false` exempts that slot correctly; Task 4 reports these cells. Measured against the data (v4 check): Quads
isolation keeps Wall Sit at home and basic gym (no isolation implement row lists Quads first there), and becomes
Leg Extension at full gym; the Glutes isolation slot keeps Glute Kickback for beginners at home and in a gym,
because E110 Lateral Band Walk lists "Glutes (medius)" first (a glute-medius move is not a like-for-like
replacement), and becomes E109 Glute Kickback (Cable) for gym intermediate and advanced; the full-gym hamstring
curl becomes G0599 Machine Seated Leg Curl instead of E292 Sliding Leg Curl; calf slots take a loaded calf raise
where one exists. Why the narrowing: removing a household row with no like-for-like survivor turned the Quads
isolation slot into a second squat (`typeFor` retypes the survivor `compound`, H2) and a glute-max kickback into a
glute-medius band walk (H4). Under the core list today the household picks for equipped users are only E292
Sliding Leg Curl (58 plans) and Towel Lateral Raise (32, already an `_implementPatterns` slot); Task 4 lists what
remains and why. The match is data-dependent (review #4 J3, review #5 K1), so a data-contract test pins, per
(tier, level, slot) on the gate's grid, the cells where the like-for-like condition holds and which rows qualify
(E051 and E052 included, through the head table), with a negative case ("Calves (Peroneus)" does not match); a library edit that turns a cell off or drops a row fails it. Known cell, reported not claimed (review #6 L1): at full gym beginner the first Calves slot takes E052 Seated Calf Raise (E051 is intermediate and up), so the soleus slot gets E258 Dumbbell Calf Raise, as it does live today.
(b) Key, for compound slots: 0 when the row's `equipment_needed` holds a capability token that is not an
`improvisedTokens` member, else 1; `capability == null` uses `EquipmentVocab.tierItems[tier]` (as
`needsImplementPreference`, `core_list_selector.dart:90-96`). Placed directly before `priority_tier`, i.e. AFTER
the phase-1 foundational key, so phase 1 keeps its foundational rule (`plan_engine/CLAUDE.md`). Review #2 re-ran
this placement: Barbell Overhead Press in basic and full gym intermediate and advanced, Dumbbell Shoulder Press or
Arnold Press for dumbbell users, no Pike Push Up. A bodyweight-only capability scores every row 1 (order
unchanged; a test pins it).
**v7 amendment (found by the gate in execution, 2026-11-08).** The R3 (b) key alone was not enough for
`vertical_push`: R9 (iii) failed on 7 home_dumbbells advanced phase-1 personas. The pool ranked E104 Arnold Press
first, but once variant B (or a second shoulder slot) avoided it, `_preferNovel` walked to E010 Pike Push Up, which
is foundational and so sorts ahead of the non-foundational dumbbell presses G0414 / G0361 in phase 1 (the phase-1
key precedes the fit key). The same lesson as review #2 G1: only a partition keeps a row out. Fix: `vertical_push`
joins `_implementPatterns`, so the existing improvised filter (OI-387/388) removes Pike Push Up and Elevated Pike
Push Up whenever an implement press remains; a bodyweight user is unchanged. Test: "variant B of a dumbbell user
walks to the other press, never to Pike"; gate mutation G2 in diagnose c756b4.

Named coaching consequence of (a): an equipped user's isolation slots never get a household row while a real one
remains (e.g. full-gym hamstring curl is a machine curl, not Sliding Leg Curl). Task 4 lists every changed pick.
Known limit, not a regression: the curated injury-substitute narrowing in `_selectCandidate`
(`exercise_selector.dart:1553-1578`) re-sorts the pool for shoulder, knee, lower_back and wrist injuries; it
picks from the already-filtered pool, so (a) and R2 hold for injured users too, and only (b)'s order is bypassed.

**R4 Top-up prefers core rows and keeps the floor (review #2 G4, review #3 H5).** New REQUIRED parameter
`coreListOnly` on `topUpDays` (no default: the selector's own comments at `exercise_selector.dart:570,1518,1614`
record that a defaulted parameter is how `buildPinnedDays` stayed unfloored; one test call,
`thin_day_topup_behavioral_test.dart:216`, and three production calls change). Callers: the ON return (`:614`,
reached only with the flag ON) passes `true`; `buildPinnedDays` (`:1141`) passes
`PlanEngineFlags.coreListPoolEnabled && CoreListSelector.hasCoreFields(exerciseRepo.getAll())`, which
short-circuits to `false` with the flag OFF; the OFF tail (`:731`) passes `false`. Mechanism, two passes over the
existing ladder in `_topUpVariant`: pass 1 runs the whole ladder (own pattern, neighbours, core) with the core
filter applied INSIDE the `[foundational, relaxed]` loop (`:1296-1312`), before the `cands.isNotEmpty` break, keeping
only candidates with a `core_levels` entry at the user's level or an easier one (easier levels are intended: the
same rule as the Ruling 12 emergency, and better than a retired row); pass 2, only if the variant is still under
the floor, runs today's ladder unchanged with a FRESH `exhausted` memo (`:1282`), so a key that had no core
candidate is retried. Implemented as a filter over the `cands` list of the existing `queryV4` call, so no new seam
(the seam gate stays at 17). The floor holds by construction: the reachable candidates depend on the anchor
patterns, not on what was picked, so pass 1 plus pass 2 fill to the same `min(floor, reachable)` as today; pass 1
takes core rows first, so the retired-row count cannot rise, but pass 2 may pick a different retired id than
today, so the gate records the measured set rather than asserting a subset. Tests that move: gate
`core_list_pool_gate_test.dart:364-371` and `:386` (`topUpRetiredIds isNotEmpty`, `attributionReruns > 0`) become
"the measured set, each id listed with its persona, count no higher than today's"; `thin_day_topup_behavioral_test.dart:361-381`
(the B1 ON case) is re-checked; `kThinCeilings` (`test/helpers/injury_floor_sweep_lib.dart:265`) is OFF-world and
does not move. This answers the question the thin-day plan reserved for the flip review
(`docs/plans/2026-10-24-thin-day-topup.md:98`); the `ship_dark_pending_review.yaml` note records it.

**R5 Glutes slot prefers a glute-first row, as the LAST tie-break (review #2 G5, narrowed after review #3 H1).**
R1 puts E253 and N11 on bodyweight intermediate and advanced lists; both list Glutes in `target_focus`, so the
Glutes hip_dominant compound slot could take a second hinge instead of a bridge. New key in `rankedPool`, for
slots whose `targetMuscle` is `Glutes` and pattern `hip_dominant` only, placed LAST, directly before the id tie:
0 when the row's first `primary_muscles` entry contains "glute", else 1. Being last, it only breaks ties. Every
change to the Glutes slot's TOP-RANKED pool row (review #4 and #5, full grid, phases 1-2; in a real day the
priority-1 Hamstrings slot takes E021 first and the Glutes slot loses it to the day's dedup, so there the real change
is E045 -> E047, and Task 4 measures real picks): (1) bodyweight beginner and intermediate Glutes slot E253 -> E291
Single Leg Glute Bridge (with R1, advanced too, via the E291 row added in v5); (2) basic and full gym intermediate
and advanced Glutes slot E021 Deadlift -> E047 Hip Thrust (they tie on every earlier key and E021 won on id): an
intended coaching change, named for the founder, because a slot that targets glutes should hold a glute-first
lift; the Deadlift stays in every Hamstrings hip_dominant slot (unchanged, E021 first), so Strength's Deadlift Day,
whose lead slot is Hamstrings, keeps it. Behavioral tests pin both: gym Hamstrings hinge = E021, gym Glutes hinge =
E047. Nothing else changes.

**R6 The full flip criteria, measured here, decided in 1B.** `emergencyAnyLevel == 0` on the 998 personas; over the
576-run sweep `refilled == 0` and no retired or skill/olympic id in the built lists; and the founder's call on
promoted and injured thin sessions (R7). Task 4 reports each miss with its persona. `refilled` (16) can only reach 0
when 1B removes the last-resort fallback or the founder accepts each run; ledgered `upstream_blocked` (reopen at
1B). If OI-436's persona still empties a day after R1, Task 4 proposes shoulder-safe bodyweight rows; those are
`blocked_on_user` until the founder signs, then ship in 1A if signed before 1A's review loop, else in 1B (the ledger
says which).

**R7 Bodyweight gaps above beginner (founder call per slot).** (a) accept (D6 as decided); (b) put the household
rows on the intermediate and advanced lists for Biceps, Lateral / Rear / Front Delts. Review #2 verified (b) cannot
reach equipped users: those rows are in `_implementPatterns`, so the improvised filter removes them whenever an
implement row remains; they reach a pick only when every implement row is contraindicated or excluded, which makes
that user bodyweight for that slot. Recommendation: (b) for those four slots; (a) for Lower Chest; Hip / Glutes
hip_isolation advanced is a gym list gap too (Hip x208 at basic and full gym) and Task 4 lists candidate gym rows for
the founder.

**R8 OI-146 closes as already fixed.** Commit ad896b42 (seed v12) merged the duplicates; the seven retired ids and the
widened pairs are gone (E016 carries `merged_ids ['E241']`). `verified_clean`.

**R9 CI zeros in `core_list_pool_gate_test.dart`, each mutation-proven, defined on the trace (review #2 G3, Q8).**
Evaluated over every persona, both variants, all phases (the gate runs phases 1-5; Task 3 checks whether its phase
2+ runs pass `previousPhaseByDay` and, if not, adds a phase-2 persona with an avoid set and a strength Squat Day
persona to the behavioral file):
(i) no picked row with `high_impact` or `discipline: plyometric`, unless that slot's pool was jump-only; needs two
new `CoreListTraceSlot` fields, `jumpRemoved` and `jumpOnlyPool` (the picked row's own flags come from a library
lookup by `pickedId`);
(ii) in `_implementPatterns` slots, and in other non-`core` isolation slots whose pool held a like-for-like implement
row (R3 (a)), no improvised pick for a capability holding an implement, unless the slot's pool held no implement row
(`nonImprovisedInPool == 0`); needs one new trace field, `likeForLikeImplement`; both counts are taken on the
post-R2 pool (review #4 J5: otherwise E066 Box Jump, a plyo-box implement row, would count);
(iii) for a capability holding barbell or dumbbells, no vertical_push slot picks E010 while its pool held a
non-improvised row (an injured persona may have E011 / E012 / E104 contraindicated);
(iv) for every bodyweight intermediate / advanced and home_dumbbells advanced persona, every trace slot of kind
Quads compound and Hamstrings hip_dominant compound is filled (source `core` or `fill`, not `drop`).
(i) and (iv) hold only with R1's data (review #3 simulated 8 jump-only (tier, level, slot) combinations without
it), so R1's data and the zeros land in the same commit. The gate's phase 2+ runs do not pass
`previousPhaseByDay` (review #3 grep), so Task 3 adds a phase-2 persona with an avoid set and a strength Squat Day
persona to the behavioral file, and Task 4 reports B-repeats-A per cell (R3 (a) shrinks some equipped pools to one
row, review #3 H3; variant B and phase 2 then repeat, which is reported, not hidden).

## 4. Where R1-R5 apply

R1 data, R2, R3 and R5 are read only by `core_list_selector.dart` (and the trace). R4 runs on the OFF path only
through `coreListOnly`, which is `false` there. No R7 code in 1A beyond data, if the founder picks (b).

## 5. OFF identity

`core_levels`, `high_impact`, `variant_family` are read in `lib/` only by the core-list code; `discipline` also at
`exercise_selector.dart:1315` (top-up skill/olympic skip), unchanged. Proof: the 998-persona golden
(`test/fixtures/generator_golden_hashes.json`, 999 keys with `_meta`; it includes the 24 injury personas that
exercise the OFF top-up, so it covers R4's `false` path) and `scorecard_gate_test.dart` are unchanged with the pool
OFF.

## 6. Tasks (Unit 1A)

1. **Commit the audit harness** under `test/plan_generator/plan_audit/`: a dump test that runs only with
   `PLAN_AUDIT_OUT` set (never in CI), and the verdict rules in Dart with a unit test on fixtures. It writes the
   section 1 table for OFF and ON.
2. **R1 (and R7 if (b)) data** after the founder signs: source and library edits, importer `--check`, counts
   re-derived.
3. **Code R2, R3, R4, R5** with behavioral tests in `test/contracts/core_list_pool_behavioral_test.dart` (one per rule,
   variant A and B, phase 1 and a phase-2 avoid set, and a strength Squat Day; each fails without its rule; each rule
   mutated once, `grep -c` that the mutation applied, reddened tests recorded); the R9 zeros in the gate. Re-check the
   ON-world tests review #2 named: `keep_all_slots_selection_test.dart`, `cross_day_variety_behavioral_test.dart:202-327`,
   `session_set_budget_gate_test.dart:471`, `thin_day_topup_behavioral_test.dart:361-381`, the gate's `:364-371`, `:386`.
4. **Measure**: gate report (`WRITE_CORE_LIST_REPORT=1`), multi-injury sweep, the audit OFF and ON; write section 7: every
   pick R3 and R5 change, R4's remaining retired additions, R6 misses with personas, residual drops.
5. **Diagnose docs** (4.4 rule 22): OI-484 (ranking / filter) and OI-485 (data, jump partition, glute key), plus a note
   for R4 (it changes injured users' top-up); bug-history lookup cited (prior c1d7a4 core rows missing, b1c4e7 floor on
   name paths, d3a8f5 / a9e3c7 equipment tier, c2d5e8 / f4c1e8 injury tags; none a recurrence of this class),
   `touched_layers_checked`. Commits carry `closes-diagnose:`; NO `closes-oi:` for OI-484 / OI-485 (they close at 1B).
6. **Docs and registry**: `plan_engine/CLAUDE.md` core-list item, `plan-engine-detail.md`, `docs/sot_registry.yaml`
   (`core_list_pool`, `thin_day_topup` for R4), `docs/ship_dark_pending_review.yaml` (new numbers, R4's answer; stays
   pending), board text of OI-436 / OI-484 / OI-485 with the numbers.
7. **Ledger** `docs/audit/generator-step1a.closure.yaml` (section 8).
8. **Gate loop** (4.12.8: whole `flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test`, pre-commit loop),
   `/code-review` B-pass, plan-review record, PR, `land_pr.sh`.

## 7. Measured results (Task 4 fills this)

Measured 2026-11-08 on this branch (plan v7), R1 / R7 data NOT in (they wait on the founder's signature).

**Audit, 2,304 plans** (`test/plan_generator/plan_audit/`, `PLAN_AUDIT_OUT` set; the "ON before" column is the same grid
on main 0633a121):

| measure | live (OFF) | ON before | ON after 1A |
|---|---|---|---|
| verdict not suitable / needs work / suitable | 1,502 / 637 / 165 | - | 358 / 1,581 / 365 |
| household substitute while the user has real equipment | 1,466 | 58 | 44 |
| unloaded pick where a loaded row fits | 1,700 | 1,505 | 468 |
| Strength 4-day gym OHP Day with Pike Push Up | 36 of 56 | 56 of 56 | 0 of 56 |
| major muscle at 0 sets in week 1, 2 or 3 | 84 | 309 | 330 |
| week-1 days opening with a non-compound (plans / days) | 4 / 4 | 310 / 445 | 310 / 445 |
| jump rows in week 1 (as the lead) | 0 (0) | 1,273 (573) | 1,273 (573) |
| lead lift 2+ sets under an isolation | 876 | - | 1,005 |

Read: the equipment rows (R3, v7) meet their targets: OHP Pike 0, improvised 44 and unloaded 468 are the residue
the R1 rows and the 1B variants (OI-148) cover. Jump rows and isolation-first days do not move: every remaining
jump pick sits in a jump-only pool (advanced home_dumbbells / bodyweight knee_dominant), which R2 keeps on purpose
until R1 adds non-plyometric rows; R9 (i) lands with that data.

**Zero-set weeks.** 330 - 309 = +21 net: 21 week-2 Quads zeros in build_muscle gym plans (mostly 30 minutes), 11
of them also at 0 live. Cause: Box Jump in the variant-B Legs day's Calves slot (priority 3) credited Quads; R2
removed it, and the B Quads compound slot is also priority 3 and is not seated at 30 minutes. One more (v7):
`build_muscle|3|advanced|home_dumbbells|30|1` week 2 Chest, because Pike Push Up credited Chest and the dumbbell
press does not. Both are step 2's allocator (OI-475 board text). Plans with a zero-set week their live twin does
not have: 246 (245 before v7). By muscle-week: Hamstrings 322, all bodyweight (beginner 62 = phase 3 at the
intermediate list, intermediate 186, advanced 74): R1 hinges; Quads 122, all week 2, gym 56 and home_dumbbells 66:
OI-475; Chest 5 (bodyweight advanced 2: R7 Lower Chest; home_dumbbells advanced 3: OI-475). So "no plan worse than
its live twin" is NOT met in 1A; it is a 1B flip criterion after R1 and step 2.

**Picks R3 / R5 / v7 changed** (ON world, day-weeks over all 2,304 plans; 1,558 plans changed; one-for-one swaps):
Pike Push Up -> Barbell Overhead Press 3,988, -> Dumbbell Shoulder Press 1,304, -> Arnold Press 1,022 (R3 (b), v7);
Glute Kickback -> Glute Kickback (Cable) 1,592 (R3 (a)); Romanian Deadlift -> Hip Thrust 908, Deadlift -> Hip Thrust
480 (R5; Romanian Deadlift is the real-day loser, as R5 predicted); Barbell Overhead Press -> Dumbbell Shoulder Press
608, -> Arnold Press 528, Dumbbell Shoulder Press -> Arnold Press 352, Arnold Press -> Dumbbell Standing Alternate
Overhead Press 264 (variant B now walks to the next loaded press); Standing Single Leg Curl -> Dumbbell Lying Hamstring
Curl 336 (R3 (a)); Bodyweight Good Morning -> Single Leg Glute Bridge 260 (R5, E253 -> E291), -> Cable Pull-Through 100,
-> Dumbbell Deadlift 64 (R3 (b)); Incline Pike Push Up -> Dumbbell Seated Shoulder Press 256, -> Dumbbell Single Arm
Shoulder Press 128 (v7); Single Leg Glute Bridge -> Dumbbell Deadlift 234, -> Dumbbell Stiff Leg Deadlift 48 (R3 (b));
Donkey Calf Raise -> Band Single Leg Calf Raise 80 (R3 (a) calf heads); Hip Thrust -> Romanian Deadlift 54 (the day's
dedup after R5); Walking Lunge -> Step Up 32; Nordic Curl -> Dumbbell Lying Hamstring Curl 30; Front Squat / Goblet
Squat -> Leg Extension 24 each (the Quads isolation slot now holds an isolation row); smaller: Forward Angled Calf Raise
-> Band Single Leg Reverse Calf Raise 16, Bodyweight Standing Calf Raise -> Dumbbell Calf Raise 12, Dumbbell Rear
Lateral Raise -> Barbell Curl 12 (a day-level dedup shift), Box Jump -> Dumbbell Single Leg Calf Raise 6, Wall Sit ->
Dumbbell Calf Raise 6 / Machine Seated Leg Curl 2. Multi-row day changes add Hip Thrust 996, Glute Kickback (Cable)
696, Dumbbell Lying Hamstring Curl 642, Barbell Overhead Press 512 and remove Romanian Deadlift 812, Glute Kickback
648, Standing Single Leg Curl 584, Pike Push Up 520, Deadlift 184.

**B repeats A.** R3 (a) reduces 17 of the 31 like-for-like cells to one row (`core_list_like_for_like_data_test.dart`:
the home_dumbbells / basic_gym beginner calves E258, home_dumbbells advanced calves G0409 and Glutes G0980, the gym
Glutes hip_isolation E109, basic_gym Hamstrings knee_dominant G0339, full_gym beginner Hamstrings G0599, the full_gym
Quads isolation E043); variant B and phase 2 repeat that row there (since Unit 1B-Q the 4 and 5-day build_muscle B
leg day has no Quads isolation slot, so E043 is no longer repeated there). Over the audit, week-1 vs week-2 same-day
repeats went from 52,953 to 53,196 (+243, 0.5 percent). Reported, not hidden; the 1B variants (OI-148) are the remedy.

**Gate report** (`test/plan_generator/core_list_pool_report.md`, 998 personas + 576-run sweep), against the committed report of
2026-10-26 (that one predates the 2026-11-04 count band, so the strength-per-day and B-repeats-A columns move for
that reason too and are not attributed here):
- R4: top-up retired additions E271 x4, E261 x8 (2 personas) -> none (gate mutation G3, pass 1 off, brings them back).
- Pike Push Up picks 1,718 -> 355 (R9 (iii) holds at 0: none of the 355 is a barbell / dumbbell user's
  `vertical_push` slot whose pool held a non-improvised row); Romanian
  Deadlift 992 -> 706 (R5); Box Jump 24 -> 0, Jump Squat 726 -> 682, Lunge with Jump 288 -> 288 (jump-only pools,
  R1); Towel Row 34 -> 28.
- Drops: bodyweight advanced Glutes hip_isolation 232 -> 224; every other drop line unchanged (R1 / R7 data).
- Sub-focus matches: isolation 297 -> 345, soleus 100 -> 117 (R3 (a) head table); long_head 1,468 -> 1,417 and
  obliques 1,558 -> 1,542 (the reduced pools hold fewer head-specific rows).
- **R6 misses (flip criteria, decided in 1B):** `emergencyAnyLevel` 2 personas
  (`injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1`, `p2`, unchanged) and 40 sweep runs (unchanged);
  `refilled` 16 sweep runs (unchanged; 1B-6); retired ids in the sweep's built lists E271, E261, E254, E234 -> E261;
  skill / olympic none. Ledger `OI-436-R6`.

## 8. Closure ledger entries (Unit 1A)

- OI-146: `verified_clean` (R8).
- OI-484, OI-485: `upstream_blocked`, blocker "the fixed path goes live at the Unit 1B flip", `reopen_when: Unit 1B flip`.
- OI-436 and R6's criteria: `upstream_blocked` (reopen at 1B) for `refilled` and retired ids; `blocked_on_user` for any
  persona whose rows the founder must sign.
- Founder decisions: R1 table, R7 per slot, Nordic Curl: `blocked_on_user` until signed (then `closed_in_commit`).
- Each section 9 item: `upstream_blocked`, `reopen_when: Unit 1B plan`.

## 9. Unit 1B scope (its own plan, after 1A merges; one ledger entry each)

1B-1 Flip `enable_core_list_pool` with the full x2 review + B-pass and the `ship_dark_pending_review.yaml` entry moved
to `resolved:`.
1B-2 Delete the old path: `pickV4`'s cascade branch and `_applyHistoryAdjustments`, with the inventory of the 36 test
files that call `generateV4` / `pickV4` (each re-pointed, kept as a fallback pin, or deleted with its replacement).
1B-3 The exercise-seam gate: `scripts/exercise_seam_lib.dart:59` `SeamEntry(18, ...)` and
`test/scripts/exercise_seam_lib_test.dart`.
1B-4 The 43 `docs/sot_registry.yaml` lines citing `pickV4`, `_cascadeFill`, `_fillSlots`, `_applyHistoryAdjustments` or
the flag.
1B-5 The `hasCoreFields` v12 guard and the fixtures that seed rows without core fields (decide: delete the guard and
re-seed fixtures, or keep it with a stated reason).
1B-6 The last-resort `_fillSlots` fallback (R6 `refilled`).
1B-7 The Ruling 4 overlay copy and its pins (`exercise_library_core_fields_contract_test.dart:128-138`,
`exercise_library_schema_contract_test.dart`, `library_depth_rule_test.dart`, `test/helpers/library_depth.dart`).
1B-8 OI-148 rows (founder-signed list; the original 23-row list was never committed), each with its pattern and a
same-movement link for variety; the key name must not reuse "twin" (`docs/naming_conventions.md` gives it to the Batch
C2b replacement rows); the schema allow-list (`exercise_library_schema_contract_test.dart:72,111-118`) takes the key.
1B-9 OI-147: retire E053 Donkey Calf Raise.
1B-10 Core-vs-`suitable_for` disagreements the gate reports: E010 Pike Push Up x1,718, E045 Romanian Deadlift x992,
E255 Towel Row x34, E134 Copenhagen Plank x16.
1B-11 Seed v21 and the cloud re-seed migration, with its own live-apply go.
1B-12 OI-489 (added 2026-11-10 by Unit 1B-Q): the four ON plans with a zero-set muscle their live twin lacks
(`build_muscle|3|advanced|bodyweight|30|2` and `|3` no Chest in week 2; `lose_fat` and `general_fitness`
`|3|advanced|bodyweight|30|1` no Hamstrings in weeks 1 to 3). An entry criterion of the 1B-1 flip.

Amended by Unit 1B-F (2026-11-11, `docs/plans/2026-11-10-generator-1bf-flip.md`): Unit 1B ran as 1B-F, which closes
1B-1 to 1B-6 and 1B-12 (1B-9 closed by S1b-3, 1B-10's E010 / E045 by S1b-2; 1B-8 and the rest of 1B-10 per the
1B-F closure ledger, `docs/audit/generator-step1-1bf.closure.yaml`). Items 1B-7 (the overlay copy) and 1B-11
(its seed and cloud re-seed migration) were split out under §4.12.1 into Unit 1B-F2 (OI-495, its plan in section 11
of the 1B-F plan), which starts when 1B-F merges.

## 10. Review log

**Review #1 (Sonnet, context-blind):** 5 P1, 8 P2, P3s; folded in v2 (scope split, R1 rows by slot, calf rows, top-up
keeps the floor, R6 founder call per slot, explicit twins, CI zeros, diagnose docs, record, merge route).

**Review #2 (Sonnet, context-blind, on v2):** 3 P1, 6 P2, 2 P3; folded in v3:
G1 an ordering key cannot keep rows out because `_preferNovel` walks past it (R2 is now a partition, R3 (a) a filter,
G1490 added); G2 v2's `typeFor` reasoning was wrong for the ON path (corrected, decision restated in R2); G3 R9 (ii)
ill-defined (now on the trace, implement and isolation slots, `core` exempt, and R3 (a) removes the leaking rows);
G4 R4 order, `buildPinnedDays`, default parameter, extra asserts, seam (R4 rewritten); G5 E253 / N11 would take the glute
slot (R5 glute-first key; section 2.3 corrected); G6 R3 placement (after the phase-1 key); G7 OI-436 / refilled routing
(R6, section 8); G8 closure terms (section 8, no `closes-oi:` in 1A); G9 key name collision and schema allow-list (moved
to 1B, section 9); G10 ON-world tests named (Task 3).

**Review #3 (Sonnet, context-blind, on v3):** no P0, 2 P1, 5 P2, 3 P3; folded in v4:
H1 R5 before type and priority demoted the gym Deadlift (R5 now Glutes slots only, last key, Deadlift pinned);
H2 widening the improvised filter turned the Quads isolation slot into a second squat (R3 (a) is like-for-like only);
H3 one-row pools after the filter (reported per cell in Task 4); H4 Glute Kickback -> Lateral Band Walk swap (prevented
by the like-for-like rule); H5 R4 details (required parameter, fresh memo, filter inside the loop, floor by
construction, measured retired set, `exerciseRepo.getAll()`, easier levels intended); H6 trace fields and conditions
for the zeros, R1 in the same commit, phase-2 persona; H7 R2 before the improvised filter; H8 section 9 itemised,
other core-vs-`suitable_for` rows, jump-row list.
The v4 changes are narrowings of v3 rules (R3 (a), R5) and specifications (R4, R9); no new mechanism was added.

**Review #4 (Sonnet, context-blind, on v4):** no P0, 1 P1, 3 P2, 2 P3; folded in v5: J1 R5 also changes gym Glutes
hinge E021 -> E047 (accepted and named as a coaching change, pinned; Hamstrings keep E021); J2 like-for-like filter
now reduces the pool to like-for-like rows (no compound or glute-medius row left behind for B / phase 2); J3
data-contract test for the like-for-like cells; J4 E291 Single Leg Glute Bridge to advanced (R1, founder-signed);
J5 counts on the post-R2 pool; J6 raw-string equality stated. Reviewer verdict: one short round should converge.

**Review #5 (Sonnet, context-blind, on v5):** no P0, 1 P1, 1 P2, 1 P3; folded in v6: K1 raw equality dropped E051 /
E052, the real calf machines (same-muscle head table `{calves: {gastrocnemius, soleus}}`; the data-contract test pins
E051 and E052 as like-for-like); K2 two same-muscle slots on one day (stated, reported, R9 exemption confirmed);
K3 R5 wording (top-ranked pool vs real pick). Reviewer verdict: "one short fix converges; I expect no further rounds".

**Review #6 (Sonnet, context-blind, on v6):** no P0, no P1, 3 P3; verdict "converged". The head table fixes the calf cells and changes no other slot (0 non-calf differences against raw equality over the grid); every other `<target> (<x>)` first muscle in the library (Triceps / Biceps heads, Chest (inner), Core (anti-rotation), Quads (eccentric), Glutes (medius)) sits in a slot R3 (a) does not touch or is excluded on purpose. Folded: L1 the full-gym beginner soleus cell is reported; L2 lower-cased full-match compare and a negative pin; L3 K2's cell list confirmed.

## 11. Task t108: the plan review with a physique focus (2026-11-12)

Founder call 2026-11-12: t108 covers physique focus only; the simulated phase-1 history moves to step 4's t404 (the same
work), and what t108 finds goes into step 2's plan, not a new step-1 unit. Injuries were covered earlier (every pair of
6 injuries at 30 / 45 / 60 minutes and the 46,512-run grid of 3-9 injuries, in Unit 1B-F's record).

- **Harness.** `plan_audit_dump_test.dart` takes `PLAN_AUDIT_FOCUS=glutes_legs | chest_shoulders_arms` and passes that
  token's muscles as `bodyFocus` (what `TrainingHistoryAnalyzer.resolveBodyFocus` returns for a profile holding it with
  no history); keys are unchanged, so a focus run compares with the no-focus run key by key. A focus run's dump also
  records the focus groups (`fg`), and `plan_audit_lib.dart`'s `over_top` uses `SessionBudget.focusWeeklyTop` (25) for
  them, as the generator's ledger does (the first run counted focus groups against the normal top: 1,296 / 1,339 false
  over_top flags). The no-focus dump and audit are byte-identical to Unit 1B-F2's (sha256 5b3da296... / 345e11a7...).
- **Results** (main cf122dd1, 2,304 plans each): filed as **OI-501**, an input to step 2. `glutes_legs`: suitable
  513 -> 710, starved leads 2,284 -> 1,274, but Calves (a focus group) fall and reach 0 in 80 plan-weeks (6-day general
  fitness at 30 minutes), unloaded picks 58 -> 99. `chest_shoulders_arms`: suitable 513 -> 484, starved leads 2,284 ->
  2,690. No focus group gains a set in 722 / 977 plans (mostly 30-45 minutes). Days over their minutes: only the 1-minute
  rounding the no-focus run has too.
- **Not a duplicate of Unit 1B-F's focus grid.** `test/plan_generator/focus_grid_dump_test.dart` (5,760 plans, 30 and
  45 minutes) checks one allocator guard (a hold that credits a focus group gives way only to a slot that brings a
  major group); t108 runs the whole suitability audit with a focus at 30-90 minutes. `PLAN_AUDIT_FOCUS` is classified
  beside `PLAN_AUDIT_OUT` (`spawn_env_manifest_test.dart`, `scripts/regression_catalog_lib.dart`: stripped from a
  child, which would otherwise audit focus plans under a no-focus label).
