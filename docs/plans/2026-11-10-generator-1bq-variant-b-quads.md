# Generator Unit 1B-Q: the B leg day gets a quad compound (OI-475 L1, before the flip)

Plan v5, 2026-11-10 (v2: task 2 and the residue line rewritten to what was built; v3: review round 1 folded in; v4:
review round 2 folded in, the Glutes isolation slot moved behind Calves / Core, see section 5; every number
re-measured on the final tree; v5: review round 3 and the B-pass folded in, wording only). Branch `generator-step1-1b`. Part of generator step 1 (plan
`docs/plans/2026-11-08-generator-step1-core-list.md` section 9). Founder decision d13 (2026-11-10, task board): fix the
week-2 quad gap BEFORE the core-list flip, moved from step 2, so no plan loses quad work when the new picker goes live.
Execution: inline, one worktree (`.claude/worktrees/generator-step1-1b`), no subagent builders.

## 0. Why

The Unit 1B flip criterion "no plan worse than its live twin" (step-1 plan section 7) was measured on main cc8286ad
(2,304-plan audit, `test/plan_generator/plan_audit/`, live picker vs `enable_core_list_pool` ON):

| measure | live | core-list ON |
|---|---|---|
| plans with a major muscle at 0 sets in week 1, 2 or 3 | 92 | 278 |
| plans with a zero-set week their live twin does not have | - | 186 |

182 of the 186 are "Week 2: no sets at all for Quads" (2 more are Chest and Quads). Week 2 is variant B. The cause is
the split, not the picker:

- Writer: `lib/shared/repositories/plan_engine/split_resolver.dart` `_get3DayV4` Legs `slotsB` (the 3-day split is
  shared by build_muscle and strength), `_get4DayV4` build_muscle Legs `slotsB`, `_get5DayV4` build_muscle Legs
  `slotsB`. B is the posterior variant: in 3-day the Quads compound slot is priority 3 in sixth place; in 4-day and
  5-day B holds no Quads compound at all, only a Quads isolation slot (priority 4 and 3).
- Reader: `SessionSetAllocator.allocate` seats slots in split order up to the count band; a priority-3 / 4 slot in
  sixth or seventh place is not seated at 30-60 minutes, and a Quads row that also credits Glutes is refused by the
  Glutes session cap once the B hinge and bridge are seated (OI-475 finding 3).
- Why live hides it: the live cascade puts a quad-crediting row into a non-quad slot by accident (a Wall Sit or a
  lunge), so its week 2 shows quad sets. The core-list pool picks the slot's own row, so ON exposes the hole.

Bug history: OI-475 (open; measured 2026-11-07, memory note), OI-454 (6-day Legs B, fixed by a slot swap + credit
rule, diagnose of `quads_floor_6day_behavioral_test.dart`), OI-456 (count band). This is the OI-475 "L1" level
(variant B leads with a quad compound, no credit change), not L2/L3 (credit rule, Pull-day quad), which stay in step 2.

## 1. The change

In each of the three B leg days, one Quads `knee_dominant` `compound` slot at priority 1 sits SECOND, right after the
Hamstrings hip_dominant compound and before the Glutes hip_dominant compound:

- 3-day: the existing priority-3 Quads compound moves up (priority 3 -> 1, sixth -> second). Slot count unchanged (10).
- 4-day: the priority-4 Quads isolation slot becomes the priority-1 Quads compound (second). Count unchanged (9).
  A keeps its Quads compound and Quads isolation.
- 5-day: the priority-3 Quads isolation slot becomes the priority-1 Quads compound (second). Count unchanged (8).

In the same three B lists the Glutes `hip_isolation` slot (priority 2) moves from fourth to just behind the Calves slot
(3-day and 5-day) or behind the Calves and Core slots (4-day). Directly after the hinges it pushed Calves and Core past
the count band: measured on the round-2 tree, 51 live plans (strength and build_muscle 3-day, 45 to 90 min) lost every
Calves set in weeks 2 and 4, and 12 live 4-day plans (24 ON) lost every Core set. Both hinge rows still credit Glutes.
The Hamstrings curl moves up one seat with it.

Kill-switch `disable_variant_b_quad` (`PlanEngineFlags.variantBQuadEnabled`, default ON, CLAUDE.md section 4.6), read
once per `SplitResolver.selectV4` call (so `plan_generator.dart` is not touched): set, the three B lists return verbatim
to main's. Measured: with it set, all 998 golden personas hash equal to main cc8286ad's fixture. The switch and the old
lists are deleted by the step-2 OI-475 L2 change, which re-records these same splits (named on the OI-475 board).

Deload: week 4 is variant B. `VolumeFilter.filterDays` is passed `baseline` (plan_generator.dart:174), so the deload
"priority 1 only" rule does not run in `generateV4`; priority 1 matches variant A's Quads compound. The one other reader
of slot priority is `ThinDayTopUp.anchors` (thin_day_topup.dart:51-54, called from `ExerciseSelector.topUpDays` for an
INJURED user whose day falls under 3 exercises): it orders the top-up anchors by priority, so the Quads compound
becomes the second anchor of such a B day (harmless: an anchor only names which muscle a top-up row may train). Measured (build_muscle 3/4/5-day, intermediate, bodyweight and full_gym, 30 and 60 min):
the deload leg day keeps its exercise count; at full_gym it seats Front Squat where the old day took a Wall Sit through
another slot; no persona loses its last quad or hamstring set in week 4.

Performed order: `SequencingEngine.sequence` reorders each day after seating (compound first), so the seat order is not
the order the user performs; the hinge, squat, glute-hinge seat order does not force a squat between two deadlifts.

No credit rule changes; no picker, allocator or library change; `plan_generator.dart` is not touched (root CLAUDE.md
section 4.4 rule 14). The 6-day split already carries a Quads Legs B (OI-454) and is unchanged. Other goals' splits
(lose_fat, general_fitness) are unchanged.

### Order measured, not assumed

Two orders were prototyped over the full audit (both worlds):

| B order | ON plans with a zero-set week their live twin lacks | of which Quads |
|---|---|---|
| main today | 186 | 184 |
| Quads compound third (after both hinges) | 10 | 8 (advanced bodyweight / home 30 min: the Glutes session cap refuses Single Leg Squat after the hinge and bridge) |
| Quads compound second | 4 | 0 |
| **Quads compound second, Glutes isolation behind Calves / Core (this plan)** | **4** | **0** |

The four left are not quad and not this split, and all four were on main before this change (measured: the same
keys in the main audit; the first two read "Chest, Quads" there and "Chest" now):
`build_muscle|3|advanced|bodyweight|30|2` and `|3` (week 2 no Chest: the B Push day seats no chest row ON) and
`lose_fat` / `general_fitness` `|3|advanced|bodyweight|30|1` (no Hamstrings in weeks 1 to 3: the day's hip_dominant row
is Single Leg Glute Bridge E291, primary Glutes; the path that leaves the Hamstrings slot empty is NOT established).
They are in the dark ON world only. Registered as OI-489 and as item 1B-12 of the step-1 plan section 9, an entry
criterion of the 1B-1 flip.

## 2. Measured effect (final tree vs main cc8286ad)

Source: `PLAN_AUDIT_OUT=<dir> TZ=Asia/Kolkata flutter test test/plan_generator/plan_audit/plan_audit_dump_test.dart` on
main and on this tree (about 20 min each; `section1.md`, `audit_{off,on}.json`, `plan_dump_{off,on}.jsonl`). Counts
are plans. "Week-2 sets" are the audit's credited sets (`plan_dump` `w[1].v`, `BudgetMuscleGroups.creditedOf`), compared
plan by plan with main's.

| measure | live before | live after | ON before | ON after |
|---|---|---|---|---|
| verdict not suitable / needs work / suitable | 1502 / 637 / 165 | 1494 / 620 / 190 | 505 / 1368 / 431 | 307 / 1566 / 431 |
| plans with a major muscle at 0 sets (week 1, 2 or 3) | 92 | 28 | 278 | 32 |
| (plan, week, muscle) at 0 sets that was above 0 before, ANY muscle, any week | - | 0 | - | 0 |
| `ab_swing` plans (A vs B weekly sets differ by half or more) | 293 | 304 | 257 | 402 |
| `stretch_lift` plans | 203 | 224 | - | - |
| household substitute / unloaded where loaded fits | 1466 / 1700 | 1466 / 1700 | 274 / 441 | 275 / 440 |

Week-2 sets per plan, after vs before (fell / rose; the lowest value a falling plan reaches):

| muscle | live fell / rose | ON fell / rose |
|---|---|---|
| Quads | 52 / 274 (lowest 2) | 14 / 299 (lowest 2) |
| Hamstrings | 74 / 25 (lowest 2; 3 fell by 2 or more) | 73 / 28 (lowest 4) |
| Glutes | 94 / 4 (lowest 2; 34 fell by 2 or more) | 116 / 7 (lowest 4) |
| Calves | 28 / 16 (lowest 2) | 21 / 9 (lowest 3) |
| Core | 35 / 16 (lowest 2) | 8 / 36 (lowest 3) |

Costs, named (none reaches 0 for any muscle in any week, either world):
- **Quads, 52 live plans** (all build_muscle 4 and 5-day full_gym; 33 fall by 2 or more, e.g. 4 -> 2): the B day lost
  its Quads isolation slot, which had seated a Wall Sit; a loaded compound now sits second with fewer sets (example
  `build_muscle|4|beginner|full_gym|30|3`: Wall Sit 4 sets -> Goblet Squat 2). ON, 14 plans fall (8 by 2 or more,
  worst 5 -> 2 at `build_muscle|5|intermediate|full_gym|90|3`). Plans at 2 or fewer week-2 quad sets drop live
  224 -> 139 and ON 421 -> 367. Accepted: a loaded squat pattern for an
  isometric hold is the step-1 aim; the weekly floor is OI-475 L2 (step 2).
- **Glutes, 94 live / 116 ON plans** (34 live by 2 or more, worst 6 -> 2 in 2 plans; live plans at 4 or
  fewer week-2 Glutes sets 18 -> 42, at 2 or fewer 0 -> 2; ON at 4 or fewer 2 -> 19; concentrated in 30-minute plans): the Glutes isolation slot now sits
  behind Calves / Core, so at short minutes the day keeps the two hinge rows (both credit Glutes) and drops the
  isolation row. Accepted: Glutes stays above 0 every week, and the alternative cost Calves and Core whole weeks.
- **Hamstrings, 74 live / 73 ON plans** (mostly by 1): the Quads compound takes a seat ahead of the curl. On the
  round-2 tree (Glutes isolation still fourth) it was 108 live / 210 ON; moving the isolation slot back lifted the curl.
- **Calves 28 / 21 and Core 35 / 8 plans** fall by a set or two where the Quads compound takes a seat; none loses its
  last set (round 2 had 51 live / 8 ON Calves and 12 live / 24 ON Core whole-week zeros, now 0).
- `ab_swing` +11 live (new issues: Quads 118, Glutes 2; gone: Quads 162) and +145 ON (new: Quads 254, Glutes 6; gone:
  Quads 42): week 2 now holds quads where it held none, and the A/B difference in quad sets is still half or more.
  Step 2's weekly floor owns the balance.
- `stretch_lift` +21 live (a lunge or split squat on more B days).
- ON household substitutes 268 (round 2) -> 275 (main 274): seven strength 3-day home_dumbbells 30-min plans seat
  E292 Sliding Leg Curl in the Hamstrings curl slot (the step-1 plan's named E292 household residue, its section 1
  table and Task 4). Six of them did so on main too. One, `strength|3|advanced|home_dumbbells|30|1`, is new against
  main: its week-2 Legs day was Romanian Deadlift, Single Leg Glute Bridge, Dumbbell Glute Bridge, Hollow Body Hold
  (no quad set, an unloaded flag) and is now Romanian Deadlift, Step Up, Sliding Leg Curl, Hollow Body Hold (one
  `improvised` issue in place of the zero-quads and unloaded issues). That one plan is the whole household 274 -> 275
  and unloaded 441 -> 440 movement.

## 3. Tasks

1. The split change (above), as one edit per day.
2. Behavioral test `test/contracts/variant_b_quads_behavioral_test.dart` (66 tests):
   (a) for build_muscle 3, 4, 5 days and strength 3 days, `SplitResolver.selectV4` gives one Legs day with a B variant;
   `slotsB.length` is 10 / 10 / 9 / 8 (unchanged), `slotsB[0]` is Hamstrings / hip_dominant / compound, `slotsB[1]` is
   Quads / knee_dominant / compound / priority 1, `slotsB[2]` is the Glutes hinge, B holds exactly one Quads compound,
   and the Glutes isolation slot sits behind the Calves slot (4-day: and the Core slot); the 6-day 'Legs B' keeps
   `slotsB == null` (not touched);
   (b) real `generateV4`, both worlds (pool OFF and ON), build_muscle 3, 4 and 5 days x {bodyweight, full_gym} x {30,
   60 min}, intermediate, phase 1, plus strength 3-day full_gym 60: week 2 carries quad sets (oracle: the library row's
   `primary_muscles` contains Quads, restated from the raw JSON, never the production credit helper or the allocator
   ledger);
   (c) mirror: on the same personas the week-2 Legs day still holds a row whose first primary muscle is Hamstrings
   (B keeps its posterior lead; the change must not turn B into a copy of A).
   (d) kill-switch: `variantBQuad: false` returns each old B list exactly (restated slot by slot) with A unchanged, and
   the Hive key set makes `selectV4` and `generateV4` follow it;
   (e) week 4 (deload, variant B) holds quad sets on the grid, and week 2 holds Hamstrings sets;
   (f) the eight audit personas that measured "second, not third" (advanced bodyweight / home 30 min) hold week-2 quads;
   (g) seven audit personas that measured whole-week Calves / Core zeros with the Glutes isolation slot fourth hold
   that muscle in weeks 2 and 4, both worlds (oracle: primary muscle `Calves` or `Calves (...)`, `Core` / `Abs` /
   `Obliques`, from the raw JSON).
   66 tests = 9 split shape + 1 kill switch + 28 per world. Mutations (run on the final tree by script from a saved
   copy, restored and `cmp`-checked): the new lists replaced by the old 28 red; Quads
   compound third 12 (4 shape + the 8 personas ON); priority 4 instead of 1 4 (shape only: no generation path reads it
   for an uninjured persona, see section 1); the kill-switch ignored 1; the old list edited 2; the Glutes isolation slot
   back in fourth place (the round-2 tree) 13 (4 shape + 9 persona runs; each of the seven personas reddens in at least
   one world).
3. Tests that pin the old B slot lists: the inventory (`grep -rn slotsB test/`) found none that pins the B shape
   (the others build their own slot lists or read generically); the only edited test is the same-movement gate floor.
4. Golden (`test/fixtures/generator_golden_hashes.json`): re-record with attribution: every changed key must be a
   3/4/5-day plan of a goal whose split changed (build_muscle 3/4/5, strength 3); a counterfactual run with the edit
   reverted returns 0 changed keys. Result: 242 of 998 keys change (build_muscle 3d 44, 4d 86, 5d 60; strength 3d 52;
   none elsewhere); with the kill-switch set the fixture equals main's (the OFF branch is main's list verbatim). Scorecard gate and core-list gate green; `same_movement_day_gate_test` green.
5. Docs: the plan-engine nested CLAUDE.md (one line under the Quads floor item), OI-475 board text (L1 landed; L2/L3
   stay step 2), sot_registry new concept `variant_b_leg_quad_compound`, OI-489 + step-1 item 1B-12.
6. Full gate loop (analyze whole project, full suite, pre-commit), B-pass, record, commit, PR, merge.

## 4. Closure

Ledger `docs/audit/generator-step1-1bq.closure.yaml`: the split change, the kill-switch, the golden attribution, the
same-movement floor, the audit, the named costs (section 2: Quads 52 live, Glutes 94 live / 116 ON, Hamstrings 74 / 73,
Calves and Core small falls, `ab_swing`, `stretch_lift`, the seven E292 plans, one of them new against main).
Section 2 is the one full cost list; the board paragraph, diagnose and registry carry a summary and point here, and the four ON plans (OI-489, `upstream_blocked` on the
1B-1 flip criterion item 1B-12).

## 5. Review log

**Round 1 (2 Sonnet seats, context-blind, on v2; 0 P0, 0 P1, 8 P2, 7 P3; not converged).** Folded in v3:
- No kill-switch for a plan-generator change (section 4.6): added `disable_variant_b_quad`, byte identity measured.
- Deload side effect unmeasured: measured; the claimed "priority-1-only deload" does not run in `generateV4` (seat A's
  premise checked against plan_generator.dart:174); week 4 pinned.
- The 39 Hamstrings plans and the `ab_swing` rise not ledgered: re-measured on the final tree and named; a new cost
  found while doing so (58 OFF plans with fewer week-2 quad sets) is named in section 2 and the ledger.
- The residue ledgered `upstream_blocked` on an undefined "1B-F": registered as OI-489 and step-1 item 1B-12, measured
  present on main.
- "Second, not third" not pinned behaviourally: the eight audit personas added; the third-place mutation reddens them.
- Unqualified "no plan gains a zero-set week" and an unfinished board clause: fixed; section 2 numbers re-measured from
  the final tree with the command to regenerate them.
- Diagnose citations (function lines, `pickV4` line, missing `SequencingEngine` reader, OI-475 parent): fixed.
- P3s: same-movement floor comment states OFF re-measured and that the six moved placements were not traced; step-1
  plan E043 sentence updated; tasks 3 and 5 now report results. Kept: the golden `_meta.recorded_on` text is written by
  the recorder (generator_golden_test.dart:87) and is not this unit's.

**Round 2 (2 Sonnet seats, context-blind, on v3 and the staged diff; 0 P0, 0 P1, 3 P2, 8 P3; not converged).** Folded
in v4:
- (P2, both seats) The Hamstrings cost was the `ab_swing` share (39), not the plans with fewer week-2 Hamstrings sets
  (108 live, 210 ON on that tree): re-measured plan by plan from `plan_dump` and named in section 2, live world included.
- (P2, seat A) "No plan gains a zero-set muscle" held for the six major muscles only: 51 live plans lost every Calves
  set in weeks 2 and 4, 12 live / 24 ON every Core set. Fixed in code, not ledgered: the Glutes isolation slot moved
  behind Calves / Core (section 1), measured over the full audit (any muscle, any week: 0 new zeros in both worlds),
  pinned by test group (g) and the shape test; the costs it brings (Glutes) are named. The same-movement ON floor
  re-measured 977 -> 931 (N19 Dumbbell Glute Bridge seated on fewer B days).
- (P3) "Priority is not read": `ThinDayTopUp.anchors` reads it for injured users' thin days; reworded (section 1,
  nested CLAUDE.md, diagnose). Test counts and mutation numbers re-run and aligned (66 tests). `disable_variant_b_quad`
  (and the missing sibling `disable_quad_legs_b`) added to `docs/naming_conventions.md`. OI-489 cross-references OI-485.
  The board's "the L2 change below" pointer fixed. The registry's "182 -> 0" aligned to 184. The plan-review record is
  written before the merge and the ledger's commit field stamped after it, as S1b-2 / S1b-3 did.
- (P3, seat B, injured users) The injury personas are not in the audit. The golden's 24 injury keys change (knee and
  lower_back); the full suite's injury sweeps (contraindication) stay green. Not measured: whether an injured user's
  week-2 Legs day keeps a quad row; the slot's exposure is the same as the old isolation slot's, filled by the same
  injury cascade.

**Round 3 (2 Sonnet seats, context-blind, on v4 and the staged diff after the full gate loop; 0 P0, 0 P1, 1 P2, 6 P3;
seat A converged, seat B not, on the P2 alone).** Both seats re-derived every section 2 number from the audit dumps
and matched them, the 242 golden keys and their split, the 66 tests, the N19 1444 -> 1289 placements and every
citation. Folded in:
- P2 (seat B): "seven ON plans seat E292 again, as on main" was wrong for one plan. Re-measured (`improvised` sets in
  `audit_1b`, `audit_1bq_final`, `audit_1bq_d` ON): final minus main is exactly `strength|3|advanced|home_dumbbells|30|1`.
  Section 2, section 4 and the ledger now name it and its days.
- P3 (seat B): costs differ by document. Section 4 now says section 2 is the one full list; the diagnose
  `impact_analysis` gains `stretch_lift` and the E292 plan.
- P3 (seat B): the ON Quads fall (14 plans) and the round-2 8 ON Calves zeros are named in section 2 and the ledger.
- P3 (seat B): Glutes and Quads low-end counts added to section 2.
- P3 (seat B): the plan-review record is written before the commit, and the ledger's commit field is stamped after it.
- P3 (seat A): group (g)'s comment now says it guards the Glutes slot position and does not detect a no-op (on main 6
  of its 7 personas pass); the `quadSets` comment now says it counts the exact `Quads` spelling, stricter than `setsOf`.
- Seat A's unmeasured exposure (injury / body focus) is the round-2 P3 already named in diagnose tier 12.
Converged: no P0, P1 or P2 is open after the fold.

**B-pass (2 fresh Sonnet seats, code / tests and documents; 0 P0, 0 P1, 1 P2, 3 P3; both accept).** Record
`docs/reviews/generator-step1-1b-bpass.md`. The P2 (live-world persona tests do not detect a no-op) was already stated
in the test header and group (g)'s comment and is covered by the shape and pool-ON tests (28 red when the feature is
reverted); the board now defines L1 / L2 / L3 on first use, the diagnose says "pool OFF / pool ON", and the board names
the 14 ON Quads plans.
