# Generator Unit 1B-F: switch the core-list picker on, delete the old picker

Plan v19, 2026-11-11 (v2: review round 1 folded in; v3: review round 2, the allocator rule narrowed to the defect
(prototype D); v4: review round 3, the count-floor guard fixed (prototype D3) and the overlay copy split into Unit
1B-F2 (section 11, §4.12.1); v5: review round 4, majors over minors (prototype E); v6: review round 5, the minor-muscle residue's mechanism and the
count-refused case measured, prototype F (eviction on a count refusal) measured and rejected; v7: review round 6, the week term (prototype G) and
the injured-pair sweep widened to every goal and phases 1-3; v8: review round 7, kept holds count as week credit
(prototype H), the injured-pair evidence widened to 15 pairs and every sweep block; v9: review round 8, the second-row
guard (prototype J) rejected, the full live baseline measured, d16 re-asked with it (OI-452 next), the hard test re-cut
and costed; v10: review round 9, focus holds never give way (prototype H2), the CI hard test cut to the 1,077 runs R6
refilled with the full grid env-gated, Ruling 5's share of the thin days measured as zero; v11: review round 10, focus holds
give way only to a major (prototype H3), R6's reach measured over 26,928 more runs and its 1,465 runs added to the
CI hard test; v12: review round 11, H4 measured and rejected, the extension's rise asked as d17, the
stale `plan_generator.dart` comments widened as d18; v13: review round 12, hip-unsafe jump rows (Ruling 12, d19),
the audit flags (d20) and every stale comment (d21) decided, the CI cost restated; v14: review round 13, Ruling 12's
touch list completed, d19's cost shown (d22), the 30- and 45-minute session legs measured and the 30-minute thin days
ruled (d23); v15: review round 14, the 30-minute mechanism corrected (188 picker / 144 pinned repeat), the CI ratchet moved
to a pinned-repeat-pairs block, S1b-2's demoted-twin rule kept on the core path; v16: review round 15, H3's 30-minute trade on injured users
measured both ways, S1b-2's soft variant-B test kept on the core path; v17: review round 16, the 30-minute trade's
class named, the demoted-twin widening extended to the top-up; v18: review round 17 converged, its five wording
items folded; v19: a build finding in Task 2, Ruling 5c (the empty-day guard's clock), with its review round; see
section 9). Branch `generator-step1-1bf` (worktree
`.claude/worktrees/generator-step1-1bf`, from main ea37ed59). Part of
generator step 1. Parent plan: `docs/plans/2026-11-08-generator-step1-core-list.md`, section 9 (items 1B-1 to 1B-12).
Founder approvals: the generator overhaul plan steps 1-5 and board d7 (commit, PR and merge per step after reviews
and CI); d13 (2026-11-10, task board; its second sentence): a bodyweight shoulder + wrist user gets a core day on Push day once
the old picker is deleted. (d13's first sentence, the week-2 quad gap, is Unit 1B-Q's and is what the repo's 1B-Q
records cite; this unit's closure records the second.) Execution mode: inline, one worktree, no subagent builders (§4.12.7). Tier L (plan engine), blast radius
`platform`. Not ship-dark: this is the flip and the removal of the kill switch, so the full x2 review applies
(§4.12.4) and the `enable_core_list_pool` entry leaves `docs/ship_dark_pending_review.yaml`. No live step in this unit
(the cloud re-seed belongs to Unit 1B-F2). Pre-launch (only testing accounts exist), so §4.6 step 3's manual check is
the founder's device check after the build (section 6); there is no existing-user population to protect first.

## 0. Why

The generator has two exercise pickers. The old one (the cascade: `ExerciseSelector.pickV4`'s body, `_fillSlots`,
`_cascadeFill`, `universalPoolV4`, the L6 post-pass `_applyHistoryAdjustments`) serves every user today. The new one
(the core-list pool: `_pickCoreList`, `CoreListSelector.rankedPool`) is behind `enable_core_list_pool`, default OFF.
The 2026-11-08 audit found the old picker's household picks, file-order ties and starved lead lifts; step 1A and the
S1a / S1b library batches built the new one's rules and data. §4.6 step 4: the batch that rolls the gate deletes the
old path.

## 1. Measured state (main ea37ed59, 2,304-plan audit `plan_audit_dump_test.dart`, both worlds)

Audit grid: 4 goals x 3/4/5/6 days x 3 levels x 4 tiers x 30/45/60/90 min x phases 1-3, no injuries, no history.

| measure | live (OFF) | core-list (ON) |
|---|---|---|
| verdicts suitable / needs work / not suitable | 190 / 620 / 1494 | 431 / 1566 / 307 |
| `improvised` (household substitute) issues | 3016 | 307 |
| `unloaded` issues | 6225 | 695 |
| `lead_starved` issues | 1678 | 2287 |
| `low_volume` issues | 1287 | 1767 |
| `ab_swing` issues | 341 | 493 |
| plans with a major muscle at 0 sets, weeks 1-3 | 28 | 32 |
| week-1 jump-row leads / jump rows, uninjured (OI-485 (1); injured: Ruling 12) | 0 / 0 | 0 / 0 |
| plans with a week of 0 Hamstrings sets (OI-485 (2)) | 0 | 2 |
| `iso_first` plans (OI-485 (3), the audit's classifier) | 4 | 12 |
| days with 0 rows / under 3 rows, weeks 1-3 | 0 / 0 | 0 / 0 |
| ON plans with a MAJOR muscle at 0 where the live twin has sets (parent plan section 1's flip row) | | 4 (OI-489) |
| ON plans with ANY of 10 muscles at 0 where the live twin has sets | | 167 |

The 28 ON plans with a major muscle at 0 in weeks 1-3 (after Ruling 5) are the same 28 plans as live.

Three issue codes rise under the flip and ship with it (prototype H ON against live): `lead_starved` 1678 -> 2281,
`low_volume` 1287 -> 1767, `ab_swing` 341 -> 495, while the verdicts move 190 / 620 / 1494 -> 431 / 1570 / 303. They
are accepted with the flip (founder d20, section 10) and owned: `lead_starved` by OI-486 (a day's main lift starved, step 2), `low_volume` and
`ab_swing` by step 2's weekly floor (the same owner as the minor-muscle residue, section 4). Ruling 5 moves them by
-6 / 0 / +2 against main ON.

Core-list gate report (`WRITE_CORE_LIST_REPORT=1 core_list_pool_gate_test.dart`, today's library, 998 golden
personas over the 4 goals, flag ON): `emergencyAnyLevel` 0 personas, `refilled` 0, no retired or skill / olympic pick.
Its multi-injury sweep (576 runs: build_muscle only, every pair of knee / shoulder / lower_back / wrist, phases 1-2):
`emergencyAnyLevel` 16 runs, `refilled` 16, one retired row (E261) in the built lists.

## 2. OI-489 (item 1B-12): the mechanism

Measured with a probe on the four keys and a temporary print in the allocator (not committed).

- The picker is not the cause. `_pickCoreList` (exercise_selector.dart:773) picks E253 Bodyweight Good Morning for
  the Hamstrings hinge of `lose_fat|3|advanced|bodyweight|30|1` and `general_fitness|3|advanced|bodyweight|30|1`
  (Full Body A and B, same days and rows in both goals), and Hindu Pushup (G3662) and Decline Push Up (E103) for the
  chest slots of the B Push day of `build_muscle|3|advanced|bodyweight|30|2` and `|3`.
- Writer: `SessionSetAllocator._variant` (session_set_allocator.dart:220-250) spends the time of every NOT-budgeted
  row (a timed hold: Hollow Body Hold E177, Copenhagen Plank E134, Isometric Lateral Raise E289, Doorway Isometric Row
  E275) BEFORE pass A seats any budgeted slot in rank order. Reader: pass A (`// 3. Pass A`), which refuses a slot that
  does not fit the clock. On a 30-minute advanced bodyweight day the core-list picker hands over more holds than the
  old picker (week 2, 216 days per world, holds per day: OFF 0:93 / 1:102 / 2:15 / 4:3 / 5:3, ON 0:39 / 1:82 / 2:57 / 3:31 /
  4:7), so the clock is
  gone before rank 0: the B Push day kept Isometric Lateral Raise, Hollow Body Hold, Standing Towel Pull Apart,
  Copenhagen Plank and dropped Elevated Pike Push Up (its lead), Hindu Pushup and Decline Push Up; Full Body B dropped
  Good Morning (rank 2, priority 1) and kept Doorway Isometric Row and Hollow Body Hold.
- Bug history: no diagnose names this ordering (the B2 `session_set_budget` and OI-456 piece A / B diagnoses price a
  timed row at its own rest, Ruling 8 of B2, and count it toward the count band; neither orders it against the rank).
  Not a recurrence; same family as OI-486 (a day's main lift starved), a step-2 item.

## 3. Rulings

**Ruling 1, the flip.** `enable_core_list_pool` and `PlanEngineFlags.coreListPoolEnabled` are deleted. `pickV4` keeps
its name and signature minus the dead parameter, and `buildPinnedDays` loses the same parameter (declared at
exercise_selector.dart:1042, passed on to `fresh()` at :1125; d15 names both call sites) (`pickV4`'s two callers: `plan_generator.dart:208` and `buildPinnedDays`'s
`fresh()`, exercise_selector.dart:1113), and its body becomes the delegation to `_pickCoreList`, which keeps its name
and stays a separate function (the registry cites it by name; smallest diff). `_pickCoreList` also takes
`applyInjuryUniversalFilter` (exercise_selector.dart:782, read only by the R6 block at :933 / :946) and loses it with R6. `plan_generator.dart` IS edited, at
two call sites only (lines 201-202 and 216-217 pass `applyInjuryUniversalFilter`, which dies in Ruling 2); founder
d15 (section 10) is the rule-14 instruction, named in the commit.
`test/contracts/injury_safe_omission_production_test.dart:139` passes the same parameter and is handled in Ruling 7.

**Ruling 2, the old path.** Deleted: the cascade body of `pickV4` (everything after the core-list delegation), `_fillSlots`,
`_cascadeFill`, `universalPoolV4`, `_applyHistoryAdjustments`, `_patternForPick`, the legacy V3 `pick` and its helpers
(`_selectForSpecs`, `_broadenSelection`, `_appendBodyFocusIsolation`, `_capSpecs`, `resolveMaxPerDay`,
`defaultExerciseCounts`, `hardFloor`, `_durationExerciseCounts`: no reader outside the file), the private members
left with no caller once those go (`_injectNonNegotiables`, called only from `pick`; `_buildUniversalFallback`, called
only from the cascade; `_focusToCategory`, `_broadenCategories`, `_timedUniversal`, `_categoryForUniversalName`: an
`unused_element` warning aborts pre-push; round 8), including the
`_universalPool` const (zero callers, but `library_batch_c2_name_readers_test.dart:44-61` reads it
by source, see Ruling 7), the v12 `hasCoreFields` guard (Ruling 4), and `applyInjuryUniversalFilter` with the kill
switch `disable_injury_universal_filter` (its only consumer is the universal pool). Kept: `topUpDays` (it reads
`queryV4` and `_selectCandidate`, never the cascade); `coreListOnly` becomes always true and the parameter is
removed; `_selectCandidate` / `_preferNovel` (used by the core path and the top-up). The kill switch
`disable_injury_substitute_pref` stays: `plan_generator.dart:203` / `:218` pass `applyInjurySubstitutePreference` and
the core path (`_selectCandidate`, exercise_selector.dart:863) and `_topUpVariant` read it. `_muscleTokens` and `_buildCustomExercise` (`:1531`, used by `buildPinnedDays` at
`:1097`; both inside the `_applyHistoryAdjustments` to `_fillSlots` span, `:1444-1610`) are kept: the custom-row path
needs them (round 12, seat A). Line cites in this plan are to `HEAD` (ea37ed59); the
temporary probe switch Ruling 3's dry run added to `exercise_selector.dart` (`debugProbeNoR6`) has been reverted (the
file equals `HEAD`); `test/_probe/` is deleted before Task 2.

**Ruling 3, R6 (`refilled`, item 1B-6).** The last-resort `_fillSlots` call inside `_pickCoreList` (the
"Last resort: what OFF brings today" block) is deleted. A day whose both variants are empty after the any-level emergency then
goes to `topUpDays`, which acts for injured users only and only with defaults (kill switch `disable_thin_day_topup`
unset, `PlanEngineFlags.thinDayTopupEnabled` in `topUpDays`). For an uninjured user that would be an empty day: measured 0 in the 998 golden
personas and 0 empty days in the 2,304-plan audit. The evidence for injured users is the injury floor sweep (Ruling 8,
Task 5): 20 blocks of real `generateV4` over the 9 single injuries, pairs over 6 injuries, 4 tiers, 4 goals, 3 levels,
days 3-6 and a repeat-phase block, which already hard-asserts 0 empty days (`injury_floor_sweep_lib.dart:241`). The floor sweep's pair
blocks are phase 1 only (`injury_floor_sweep_lib.dart:325-345`), and the 576-run multi-injury sweep is the only one
with injured pairs at phase 2, where some of today's 16 `refilled` runs sit (Task 5 lists them by phase). So after the
flip: the core-list gate keeps its hard zero "no empty day" over the 998 golden personas (defaults;
`core_list_pool_gate_test.dart:377` already asserts it), and two new tests cover where R6 used to act (round 9 re-cut,
seat A: CI per-run cost is 0.2-0.6 s inside a shard, not the 0.13 s of a single process, measured from the injury
sweep files' spans in CI run 42853871573, so a 10,656-run CI test would add 35-100 minutes):
- the CI hard test, `test/plan_generator/r6_removed_runs_{build_muscle,general_fitness,lose_fat,strength}_test.dart`:
  exactly the 1,077 runs whose built plan R6 refilled before the flip, found by a pre-code probe over 19,584 runs (the
  15 pairs of the floor sweep's 6 injuries x 4 tiers x 4 goals x 3 levels x 3-6 days x phases 1-3 and the pinned repeat;
  every triple of the six on bodyweight; every pair of the 9 injuries x exclude-everything on bodyweight; flag on, HEAD
  selector): build_muscle 321, general_fitness 225, lose_fat 225, strength 306; phases 1 / 2 / 3 = 328 / 404 / 345;
  triples 602, pairs x exclude-everything 172, pairs 227, pinned repeat 76 (bodyweight 1,002 of them); plus (round 10,
  seat A) the 95 further runs of the 15-pair grid that hold a thin day at phases 2-3 or in the repeat on H (97 runs, 2
  already in the R6 set), so every d16 rise beyond phase 1 has a CI ratchet too (phase 1 is the floor sweep's); plus
  (round 10, seat A's P2: the domain left out the injury sets with more than one tier's worth of reach) the 1,465 runs
  R6 refilled in a second pre-code probe over 26,928 more runs (`r6_ext`, HEAD selector, flag on, every goal, level,
  3-6 days and phases 1-3): every triple of the six on home_dumbbells / basic_gym / full_gym (8,640 runs, R6 fired in
  220), every pair that holds ankle, neck or hamstring on those three tiers (9,072 runs, fired in 0), every quad of
  the six on all 4 tiers (8,640 runs, fired in 1,104) and all 9 injuries together on all 4 tiers (576 runs, fired in
  141); by goal build_muscle 492, general_fitness 301, lose_fat 301, strength 371; phases 500 / 500 / 465. Regenerated
  without R6, those 1,465 runs hold 0 empty days, 6 one-exercise days (below) and 182 thin day-weeks, where with R6 they
  held 0 / 0 / 700. The total hides a rise (round 11, seat B; per run against the R6 baseline): 43 runs are worse
  without R6, 94 thin and 6 one-exercise day-weeks more (all 9 injuries on bodyweight 38 runs, +84 thin, +6
  one-exercise; all 9 on home_dumbbells 3 runs, +6 thin; equipment triples on home_dumbbells 2 runs, +4 thin), while
  the triples on home_dumbbells / basic_gym (-144 / -92), the quads on home_dumbbells / basic_gym (-204 / -136) and all
  9 on home_dumbbells / basic_gym (-12 / -24) lose 612 thin day-weeks, because R6's refills there were short lists.
  Retired, skill and olympic ids without R6 over the 1,465 runs (round 11, seat A; `r6_ext_flag.txt`, final allocator
  H3): 0. All 9 injuries x exclude-everything on bodyweight (144 runs, the worst cell of the exclusion axis): R6 fires in
  the same 86 runs as all 9 on plain bodyweight, with the same no-R6 counts run for run (0 empty, 6 one-exercise, 84
  thin, 0 flagged ids; with R6 every one of the 86 holds retired E261), so the bodyweight floor makes the two cells one
  and the fixture's all-9 bodyweight runs hold it. Session length (round 13, seat B's P2-1): every count above ran at
  the 60-minute default. Over the whole 46,512-run domain at 30 and at 45 minutes (H3, the 14-row library,
  `len_r6_30.txt`; at 45 minutes three goal shards merged into `len_r6_45_all.txt`, the build_muscle + lose_fat shard
  a stopped run with no totals line, so 45 minutes' run total is per-shard: strength and general_fitness 11,628 each,
  the other two the same cells as at 30 minutes) R6 fires in 2,542 runs, the same count as at 60 minutes (1,077 + 1,465); without
  R6 they hold 0 empty days, 6 one-exercise days and 184 (30) / 188 (45) thin day-weeks, with R6 812 / 802; the runs
  worse without R6 are d17's own: 41 at 30 minutes (the 38 all-9 bodyweight, +84 thin, +6 one-exercise; the 3 all-9
  home_dumbbells, +6) and the same 43 at 45 minutes (plus the 2 home_dumbbells triples, +4); 0 retired, skill, olympic
  or tagged-hip ids at either length. So d17's record holds at every length and the fixture's run keys need no
  length axis. The run
  keys are a fixture in the test files with that provenance (2,637 runs in all). Assertions per run: 0 empty days; no retired id (the gate's own
  definition, `core_list_pool_gate_test.dart:51`: empty `core_levels` AND no `variant_family`, 10 rows; the other 632
  `core_levels: []` rows enter by family fill by design), skill or olympic id; none of Ruling 12's 14 tagged ids in a
  run whose injuries include hip; per file, the thin and one-exercise
  day counts (weeks 1-2) as exact ratchets recorded on the final tree. One `test()` per tier inside each file, a
  file-level `@Timeout(Duration(minutes: 10))` and `library;` like the sweep files. Eight files: the four above for
  the round-9 domain (1,172 runs) and `test/plan_generator/r6_removed_runs_ext_{build_muscle,general_fitness,lose_fat,strength}_test.dart`
  for the round-10 extension (1,465 runs); CI cost about 2,637 x 0.2-0.6 s = 9-26 minutes in all, under 5 minutes per
  file (build_muscle's extension file, 492 runs, is the largest). Task 6 runs `scripts/ci_test_partition.dart` on the final tree (adding
  8 files and deleting the old-path tests shifts every later file's shard, so no name chosen now holds) and renames the
  files so the eight land two per shard (round 12, seat A: one run's 19:40 / 12:51 / 12:48 / 8:35 is runner speed, not
  skew; `test.yml:117-127` records medians of 13.4-14.1 minutes per shard over 13 `main` runs, the slowest completed
  shard 19.3 minutes, and a 30-minute shard timeout), checked against `ci_test_partition.dart`'s round-robin over the
  sorted path list on the final tree. The per-run cost is measured cleanly only for `injury_sweep_c_pairs46` (77-102 s
  per 360-run tier, 0.22-0.28 s); at that rate the 2,637 runs add 9.7-12.3 minutes in all, about +2.5-3 minutes per
  shard (median about 17, the slowest observed about 22, under the 30-minute timeout); at the 0.6 s margin, +6.6 per
  shard, the slowest observed shard would reach about 26. CI does get longer: the closure records the PR run's four
  shard times against those medians, and a shard above 25 minutes on the PR run moves the extension files' runs that
  hold no thin day in either world (the empty-day and retired-id assertions only) to the env-gated grid before merge. Mutants (rule 21):
  an R6-like refill restored (the retired-id assertion reddens), a ratchet that reads another file's count, the empty-day
  check commented out on a fixture run forced empty.
- the full measurement, `test/plan_generator/injured_grid_dump_test.dart`, skipped unless `INJURED_GRID_OUT` names a
  directory (like `plan_audit_dump_test.dart`, so CI never runs it): the whole 19,584-run domain above plus the
  26,928-run extension (46,512 runs, about 3 hours at the probe's 0.22 s per run), one line per day
  for weeks 1-2. Task 5 runs it on the final tree and the closure records its table against the live baseline and
  section 9's round-8 numbers (the extension against the `r6_ext` no-R6 counts above); a rise is Ruling 3's stop. The floor sweep keeps phase 1 of the 15 pairs and the singles
  in CI.
- the 6 one-exercise days of the extension (round 10, measured): all 9 injuries, bodyweight, general_fitness,
  advanced, 6 days, phases 1, 2 and 3, the Legs + Core day (day 6) in weeks 1 and 2, holding only Pelvic Tilt Into
  Bridge. The selector hands the allocator 3 rows for that day in both modes (`AllocationStats.rowsSeen` and
  `slotsSeen` = 3; Pelvic Tilt Into Bridge, Clamshell, Glute Bridge). With R6, the Push and Pull days (days 1-2, both
  variants empty after the emergency pass) were refilled with retired E261 Bodyweight Rear Delt Raise (Rear Deltoid,
  credits Shoulders). Without R6 the top-up seats Bird Dog there (N01, Core + Glutes), which spends the Glutes weekly
  top (14 for general_fitness advanced, `SessionBudget.weeklyBand`) before day 6, and pass A drops day 6's Clamshell
  and Glute Bridge against that top. Writer: the allocator's pass A (`session_set_allocator.dart`, the weekly-top
  check at `SessionBudgetLedger.fits`, `session_budget.dart:571`) in (rank, day) order; reader: the day list the plan
  shows. It is Ruling 8's mechanism, the OI-452 class (the weekly top spent before a late day), and the counts are
  the same on main's allocator and on H3 (a day-by-day dump of the 36 general_fitness bodyweight all-9 runs at 5-6
  days is byte-identical, so Ruling 5 adds none). They ship under d17 on OI-452 (section 10) with the 2,637-run CI
  ratchet holding them; the one-exercise ceiling of `r6_removed_runs_ext_general_fitness_test.dart` is 6.
Single injuries at phase 2 and at 4 / 6 days at phase 3 sit in no sweep; R6 never fired for a single injury in any
measured block, and an injury filter is monotone (a single injury's eligible rows include every row of each pair that
contains it), so a day that is not empty for every pair containing an injury is not empty for that injury alone (the
emergency and top-up passes act on a superset pool). The same argument bounds every injury set by all 9 (round 11,
seat A): R6 fires only when both variants are empty before the top-up, which is monotone in the injury set, and the
576 all-9 runs (every tier, goal, level, 3-6 days, phases 1-3) are measured, so a cell that holds no empty day for
all 9 injuries holds none for any smaller non-empty set (round 12, seat A: the first slot's pool, the emergency pool
and the top-up pool are supersets, `pickedNames` matters only after a pick, and the allocator's empty-day guard never
empties a day holding a budgeted slot). It does not reach the empty set: `topUpDays` returns early for an uninjured
user (`exercise_selector.dart:1232`), so the uninjured case rests on the 2,304-plan audit, the 998 golden personas
and the 48 exclude-everything runs (all 0 empty days). The kill switch `disable_thin_day_topup` has no writer outside
tests (`git grep` over `lib/`, `supabase/`, `scripts/`); with it set on a device a both-empty injured day would now stay
empty where R6 refilled it, which is a test-only state. The gate's report keeps its 576-run section with the OFF half deleted with the flag; the
floor sweep keeps its own.

Measured before any code (a temporary switch that skips the R6 block, `test/_probe/`, the prototype E tree (G and H only narrow
E's evictions; Task 5 repeats the sweep on the final tree), both modes over the same 3,456 runs, 12 min 38 s for both): with R6, `refilled` fires in 86 runs (109 day-variants), every one a
bodyweight shoulder + wrist user (build_muscle 25, strength 25, lose_fat 18, general_fitness 18), and each of the 86
built lists holds retired E261, which only R6's cascade brings; without R6, the same 86 runs have 0 empty, 0
one-exercise and 0 under-3 days and no retired, skill or olympic id, and the whole grid holds none in either mode
(`emergencyAnyLevel` 86 runs in both). So deleting R6 costs no day in this grid and removes the only retired row. Removed with R6: the trace field
`CoreListTrace.refilled` (core_list_selector.dart:63), its gate readers (`core_list_pool_gate_test.dart:354` (the provenance loop), ~371-372, :550
and the report loop) and `core_list_pool_behavioral_test.dart:600, 624-627`; and the now-dead
`CoreListSelector.hasCoreFields` function (with the seam-gate text at `scripts/exercise_seam_lib.dart:73`). If the
post-flip sweeps show an empty day, a one-exercise day or a thin-day count above a block's recorded ceiling, the unit
stops and this plan comes back with the mechanism (writer and reader) and a ruling before more code. That stop fired
before any code, in round 7: the 3,456-run grid lacked elbow and hip, and the wider measurement (the 15-pair grid above,
the 20 floor-sweep blocks ON with and without R6, and four extra blocks: pairs at phases 2-3, pairs in the pinned repeat,
every triple of the six injuries on bodyweight, and the pairs of all 9 injuries x exclude-everything on
bodyweight) found one-exercise days and a thin-day rise, nearly all shoulder + elbow. Their writer and reader are
Ruling 8's, the guard tried for them is Ruling 5b (rejected), and the founder's d16 ships them on OI-452. With R6 kept
the pair blocks are thinner still (H, `a_pairs` 24 / 34 thin at home / basic gym) and E261 returns, so R6 still goes. Not true, and so stated: the seed runs after `runApp`
(`main.dart:97` defers it to `splash_screen.dart:160`), a failed upgrade seed retries next launch
(`seed_service.dart:309-313`), and the generation pre-checks test `exerciseBox.isEmpty` only
(`workout_schedule_read_service.dart:216, 384`, `regenerate_plan_planner.dart:211`, `train_provider.dart:783`,
`onboarding_provider.dart:562`); `preview_plan_provider.dart:95`, `phase2_preview_card.dart:94` and
`hotel_workout_planner.dart:117` (through the `PlanGenerator.generate` facade, `plan_generator.dart:62`) call
`generateV4` with no check at all. An install whose library is still below v13
(or a box that is empty) used to fall back to the cascade (non-library placeholder rows via `_buildUniversalFallback`);
after the flip its uninjured days are empty. The seed is awaited at `splash_screen.dart:160`, so a first install is not
affected. Pre-launch, every install is a tester's and is at seed v24, so per CLAUDE.md §1
this is parked `upstream_blocked`, `reopen_when: store launch` (a "library needs re-seed" predicate in those
pre-checks), on the closure and the board.

**Ruling 4, the v12 guard (item 1B-5).** Deleted. Every seeded library since v13 carries `core_levels`; a box without
them (a fixture) would now pick nothing. The hand-seeded fixtures without `core_levels` (Ruling 7's table) get
`core_levels`; none is deleted without a named replacement. Also `equipment_exclusion_filter_behavioral_test.dart:
250-289`, whose injected `community_test_row` has no `core_levels` and would be absent for the wrong reason: it gains
`core_levels` and a positive control (picked without the exclusion). To cover the extreme the deleted att5 floor invariant
covered, the golden personas gain one exclude-everything persona per tier and level, 12 in all, each `build_muscle`, 4 days, phase 1,
no injury (capability = the floor
`{none, bodyweight, wall}`, `equipment_vocab.dart:247-253`); the no-empty-day zero runs over them, and their thin days
are counted (the floor has no core row for pull and elbow-extension slots above beginner, so some were expected). Measured
before code over a wider probe that bounds them (`test/_probe/r8_probe_test.dart:42-68`: bodyweight tier excluding every
bodyweight item, 4 goals x 3 levels x 3-6 days, phase 1, 48 runs; the tier label changes nothing once the capability is
the floor): 0 thin, 0 one-exercise, 0 empty, 0 `emergencyAnyLevel` (section 6).

**Ruling 5, the allocator (OI-489).** Timed rows still spend their time first, so a day that is not starved is
unchanged. The rule targets the defect only: when pass A refuses a budgeted slot on time alone (its groups fit their
caps and tops, the rank-0 reservation holds) AND the slot would give the WEEK its first credit for one of its muscle
groups so far (no seated slot and no kept hold that day credits it, the variant's ledger holds 0 sets for it at that
moment, `ledger.week(g) == 0`, and no kept library timed row on ANY day of the variant credits it: holds enter the
ledger with no groups, so the ledger alone cannot see them; pass A goes rank by rank across the days, so a group only a
later rank on another day would credit still counts as absent), library timed rows (`logging_type == 'timed'`) ranked
AFTER the slot may give way, the last-ranked first, under four guards: (a) a hold never gives way when it is the
day's only credit for one of its own groups (counting the kept holds, the seated slots and the incoming slot); (b)
majors over minors: a hold that credits a major group (Chest, Back, Shoulders, Quads, Hamstrings, Glutes, the flip
row's six) gives way only to a slot whose new credit includes a major group; (c) the evictions are decided before
anything is changed, and happen only if together they make the slot fit (the same arithmetic with a 1e-6 tolerance in
the decision and the final check); (d) the day's reach (its kept holds plus every slot the selector supplied) after
the evictions stays at or above `SessionBudget.countFloor`, and pass A2 and `selectorThin` read the reach from BEFORE
any eviction; (e) focus after majors: a hold that credits one of the user's focus groups (`SessionBudgetContext.focusGroups`,
built from their body focus at `plan_generator.dart:289`) gives way only to a slot whose new credit includes a major
group, as guard (b) does for a major hold (round 9, seat B: H let a laggard Core user's Core holds go to minor trades,
prototype H2 protected them outright; round 10, seat B: H2 then kept the OI-489 Chest zero for that user, so prototype
H3 orders it majors, then focus, then the other minors). Each eviction frees its count seat. Never evicted: a user's custom row, a row with no library match, a
row whose `logging_type` is not `timed` (so `cardio` and `distance` rows; the eviction keys on `loggingType == 'timed'`,
the timed-row collection in `_variant` (final tree; on HEAD the classify loop holds no such test), so a timed row of category cardio, flexibility, warm-up or cool-down, such as E063
Jump Rope or E139 Battle Ropes, would be evictable, but the core path never picks one: only 13 timed names appear in
weeks 1-2 of the 2,304 ON plans, none of them a cardio, flexibility or warm-up row). A variant-B day that copies A's allocation copies A's evictions. A repeat-phase pinned library
hold follows the same rule as a fresh one; a hold the user swapped in by hand on an earlier phase is a library row
with no `custom_origin`, so it does too (accepted: a pinned budgeted lift could already lose its seat to the clock).
The week term is round 6's (seat B, P2): prototype E tested the day only, so 43 of its 51 changed plans healed no
weekly zero cell and a major hold could give way to a major group the week already had; 68 cells already below live
went lower (Shoulders 30, Chest 20, Quads 18, by up to 4 sets, in 20 plans; 14 changed plans worse on their summed
major shortfall against live). Prototype G (E plus `ledger.week(g) == 0`) changed 14 ON plans, 9 of which heal a zero
cell, with no deepened cell and no worse plan; round 7 (seat B) found that the ledger does not see holds, so 3 of G's
trades gave a Core hold for a group the week already held through a hold on another day. Prototype H (G
plus the kept-holds term, `audit_1bf_pH`) changes 12 ON plans: the same 9 heal a zero cell (the same healed cells as
G), 2 are the Upper-day clock case below, and 1 is pass A's rank order (`general_fitness|6|advanced|home_dumbbells|30|1`:
a curl ranked later on another day had not yet been seated, so Biceps read as absent; Biceps +8, Back +3, Core -11
set-weeks; accepted, since seeing a later rank would need a whole-week pre-pass the rule does not have). The rank-order
limit is variant A's: variant B enters its copied days into the ledger before pass A, so B's week term already sees
those days' later ranks (an A/B asymmetry, not measured apart; `ab_swing`'s +2 is not it: diffing `audit_on.json`, the +2 is exactly
`build_muscle|3|advanced|bodyweight|30|2` / `|3`, whose healed Chest (0 -> 2 in week 2) now reads "6 sets in week 1 but
only 2 in week 2", and the `lead_starved` -6 is one fewer in each of six plans: `build_muscle|4|advanced|home_dumbbells|30|1`, `lose_fat` and
`general_fitness` `|3|advanced|bodyweight|30|1`, and `lose_fat` / `general_fitness` / `strength` `|6|advanced|home_dumbbells|30|1`;
the Upper-day plans change no `lead_starved` count). Focus, rounds 9-10
(prototype H3 = H plus guard (e); the 2,304-plan audit has no body focus, so its dumps are H's: by construction, since
the condition reads an empty set, and confirmed for H2 by a re-run). The production focus sets are the two
`physique_focus` sets (`TrainingHistoryAnalyzer.physiqueFocusToBodyFocus`, `training_history_analyzer.dart:127`:
glutes / quads / hamstrings / calves, or chest / shoulders / triceps / biceps) or, failing those, one or two laggard
muscles from `weakMuscles()` at phase 2+ with logged history; a Core focus is reachable only as a laggard. Measured over a
focus grid (5 focus sets: Core, Chest, Biceps and the two physique sets; 4 goals x 3-6 days x 3 levels x 4 tiers x 30 /
45 minutes x phases 1-3 = 1,152 plans each, flag on) against main's allocator, focus-group set-weeks / plans with fewer
focus sets / OI-489 major zero week-cells:
  | focus set | H | H2 | H3 (the ruling) |
  |---|---|---|---|
  | Core | -95 / 11 / 4 -> 0 | +4 / 0 / 4 -> 4 | -46 / 6 / 4 -> 0 |
  | Chest | +10 / 0 / 4 -> 0 | +10 / 0 / 4 -> 0 | +10 / 0 / 4 -> 0 |
  | Biceps | +23 / 1 / 4 -> 0 | +28 / 0 / 4 -> 0 | +28 / 0 / 4 -> 0 |
  | glutes, quads, hamstrings, calves | +40 / 0 / 4 -> 0 | +40 / 0 / 4 -> 0 | +40 / 0 / 4 -> 0 |
  | chest, shoulders, triceps, biceps | +47 / 1 / 4 -> 0 | +52 / 0 / 4 -> 0 | +52 / 0 / 4 -> 0 |
H3's Core-focus cost (-46 set-weeks in 6 plans, 16 week-cells lower, none at 0) splits three ways (round 11, seat B):
-12 in `core|build_muscle|3|advanced|bodyweight|30|2` / `|3` (Core 20 -> 16 in week 2, 10 -> 8 in week 4, each) heal the four Chest zero week-cells (weeks 2 and 4); -28 in
`core|lose_fat|3|advanced|bodyweight|30|1` and `core|general_fitness|3|...|1` keep Back at main's level (11-12, the
alternative evicts the Doorway Isometric Row and leaves 8, band bottom 12) while healing Hamstrings 0 -> 2 in weeks
1-4 (8 cells, which H2 also heals); -10 in `core|build_muscle|4|advanced|bodyweight|30|2` / `|3` give the Upper day's
lead its seat (Chest 4 -> 5, Shoulders 11 -> 12 in week 2: no zero cell; the alternative evicts the Towel Lateral
Raise and leaves Shoulders 8, band bottom 14); `core|strength|3|intermediate|...|1` gains Core 0 -> 2 (+4). Counting the
flip's major zero week-cells, not only the OI-489 Chest cells: main 12 (Chest 4, Hamstrings 8), H 0, H2 4, H3 0 (every
world also holds the 28 3-day basic / full gym 30-minute plans, 14 `lose_fat` and 14 `general_fitness`, with Shoulders at 0 in all 4 weeks, 112 cells,
the same 28 plans as live in section 1, unchanged by every prototype). Measured and
rejected (round 11): prototype H4, the same guard with non-focus holds evicted before focus holds (seat B's
suggestion; `ssa.protoH4`, `focus5_dump_H4.txt`): Core-focus cost -8 (2 plans), the other four sets equal to H3, but
12 major week-cells go below main in 4 plans (Back 8 cells to 8 or 6, Shoulders 4 cells to 8 or 6; on main every one sits
at or under its band bottom and H4 takes it 2-4 sets further under), which turns "majors first, then focus" around for a major at or below its floor. Every
other focus set loses nothing under H3. Guards (b) and (e) read the week as pass A has built it so far, so for a
rank-0 compound lead on an early day "the week lacks this major group" is almost always true: in practice neither
guard protects a hold against a day's lead lift (round 11, seat B; Task 1 pins it). Reachability (round 12, seat B): a
Core focus comes only from `weakMuscles()` at phase 2+ with logged history, so 3 of the 7 changed Core-focus plans (the
two `|3|advanced|bodyweight|30|1` Hamstrings plans and `strength|3|intermediate|...|1`, phase 1) cannot occur; they hold
the -28, the +4, the 8 Hamstrings heal cells and all 8 of H4's Back cells. A reachable Core-focus user (the 4
`build_muscle|3` / `|4` plans at phases 2-3) pays Core -22 under H3, against -12 under H4 with 4 Shoulders week-cells
below main (11 -> 8, 8 -> 6, band bottom 14); the same phase-1 caveat applies to the Chest and Biceps rows, which are
reachable only as laggards too (the two physique sets come from onboarding at any phase). The trade is closer than the
whole grid shows, and H4 still turns "majors first" around, so H3 stands. H3 is the ruling.

The count band does not evict: a slot refused by `seated >= target` is left out as before. Measured with a temporary
print in the allocator over the 2,304 ON plans (on E and again on G, the same figures; H changes no count-path code): 397 count-refused slots would
bring the day a new muscle group while a later hold is seated, in 190 plans (172 of the 397 slots bring a major, in 103 plans). Prototype F (E plus
the same eviction on that path, under the same guards; an eviction there must free a seat and make the slot fit the
clock) heals the same zero cells as E and no more: in the 78 Biceps residue cells of this class (section 4) every
later hold credits Back, and guard (b) keeps a major hold from giving way to a Biceps-only slot, so F measured the
count path only with (b) in force. It costs more than E: 153 ON plans changed (E 51), 36 cells newly below live in 17
plans (E 24 in 9; Biceps 14, Glutes 18, Core 4, depth 3 appears), 103 deepened cells, net set-weeks vs main ON Core
-363, Biceps -111, Quads -52 (E -189, +15, +14) for Chest +439 and Hamstrings +284. Rejected; the count path stays as it
is, and Task 5 re-measures the 397 / 190 on the final tree (a different count is explained). Cross-day effects on the
weekly top are the "cells newly below live", "deepened cells" and per-plan shortfall measures, all in Task 5.

Eviction and the empty-day guard: a day with no seated slot whose lead is refused by the clock may evict a later hold
to seat the lead inside the clock, where without it the guard (`// 4. Empty-day guard`) would force the lead past the
clock. `build_muscle|4|advanced|bodyweight|30|2` and `|3`, Upper day, variant B: in week 2 main seats Hindu Pushup at
2 sets beside 4 holds in 33 minutes of a 30-minute day and H evicts Hollow Body Hold, ending Hindu Pushup 3 sets +
Doorway Isometric Row, Doorway Isometric Curl, Towel Lateral Raise in 29 minutes; week 4 (the deload) goes 24 -> 21
minutes. No hold credits Core afterwards: the day's Core credit is Hindu Pushup's own (its primary muscles are Chest,
Shoulders, Triceps, Core), which guard (a) counts through the incoming slot's groups, so a 4-set Core hold gives way to
an incidental Core credit (part of H's Core -95 set-weeks). These are the "lose a row" day-weeks below. Accepted: the
day comes back inside its minutes and keeps every group. Task 1 pins it. Implementation (the final code, not the
prototype): evictions keyed by (day, row index); a copied B day replays A's evictions by (name, occurrence);
`stats.rowsSeen` counts the selector's rows before eviction in both variants; the final tree's 2,304-plan dumps must
equal prototype H's (`audit_1bf_pH`) byte for byte, or every difference is explained; `stats.rowsSeen` is not in
the dump, so `plateau_rotation_behavioral_test` (Task 2) and a Task 1 test pin it for a copied B day.

What it fixes, and what not: it restores the muscle the day had no work for (OI-489). It does not seat a starved lead
as such: in `build_muscle|3|advanced|bodyweight|30|2` week 2 the Push + Core day becomes Hindu Pushup, Tricep Dips
Floor, Isometric Lateral Raise, Hollow Body Hold (main: Isometric Lateral Raise, Hollow Body Hold, Standing Towel Pull
Apart, Copenhagen Plank); Elevated Pike Push Up, the lead, stays out because the kept lateral raise already credits
Shoulders. Starved leads are OI-486 (step 2); Task 1's tests use a lead whose group the day lacks.

Measured, eight prototypes against main (`audit_1bq_d`; prototype H is this ruling, `audit_1bf_pH`; cells are
muscle-weeks over all 4 weeks and 10 muscles; "below live" = the ON prototype under the live twin where main ON was
not; "deepened" = main ON already under live and the prototype lower still; "worse plans" = changed plans whose summed
major-muscle shortfall against live grows; scratchpad comparators `cmp2.py` / `cmp4.py` / `cmp5.py`):

| | A (every timed row at its rank) | B (any later hold gives way to any slot) | C (an H / M slot evicts) | D3 (first credit for the day, any group) | E (D3 + majors over minors) | F (E + the count path) | G (E + the week term) | H (G + kept holds count as week credit; equal to H3, the ruling, on this no-focus audit) |
|---|---|---|---|---|---|---|---|---|
| OFF plans changed (never ships: the old picker is deleted in the same commit) | 654 | 303 | 166 | 198 | 19 | 49 | 0 | 0 |
| ON plans changed vs main ON | 527 | 200 | 153 | 111 | 51 | 153 | 14 | 12 |
| ON changed plans that heal a zero cell | 66 | 49 | 28 | 45 | 8 | 8 | 9 | 9 |
| ON plans with a major at 0 where live has sets, weeks 1-3 (main 4) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| ON major-zero plans weeks 1-3 (main 32, live 28) | 28 | 28 | 28 | 28 | 28 | 28 | 28 | 28 |
| zero cells newly vs live (any muscle) | 4 (Core) | 4 (Core) | 0 | 0 | 0 | 0 | 0 | 0 |
| cells newly below live | 673 in 242 plans | 331 in 98 | 152 in 57 | 179 in 56 | 24 in 9 | 36 in 17 | 2 in 1 | 2 in 1 |
| deepened cells | 452 in 158 plans | 170 in 52 | 196 in 61 | 160 in 49 | 68 in 20 | 103 in 38 | 0 | 0 |
| worse plans (of the changed) | 213 | 90 | 66 | 67 | 14 | 14 | 0 | 0 |
| ON plans with a zero cell (any muscle) where live has sets (main 167) | 119 | 134 | 151 | 131 | 161 | 161 | 161 | 161 |
| ON `lead_starved` issues (main 2287) | 2239 | 2218 | 2255 | 2274 | 2275 | 2278 | 2279 | 2281 |
| ON verdict suitable / needs work / not suitable (main 431 / 1566 / 307) | 441 / 1558 / 305 | 438 / 1561 / 305 | 438 / 1563 / 303 | 435 / 1566 / 303 | 435 / 1566 / 303 | 435 / 1566 / 303 | 431 / 1570 / 303 | 431 / 1570 / 303 |

Prototype H: the one cell pair newly below live is `strength|3|intermediate|bodyweight|30|1`, Biceps weeks 2 and 4,
live 4 -> H 2 (main 5 and 4): on the Pull + Core day Russian Twist, the week's first Core credit (no hold anywhere in
the week credits Core), takes the place of Doorway Isometric Curl, a Biceps hold the day's Self-Resisted Bicep Curl also
credits; it heals the plan's Core zero weeks 2 and 4. Net set-weeks vs main ON Chest +10, Back +13, Shoulders +4, Quads
+2, Hamstrings +16, Glutes +18, Biceps +23, Triceps +10, Calves +4, Core -95. The OI-489 keys:
`build_muscle|3|advanced|bodyweight|30|2` / `|3` Chest weeks 2 and 4 0 -> 2; `lose_fat` / `general_fitness`
`|3|advanced|bodyweight|30|1` Hamstrings weeks 1-4 0 -> 2. Healed zero cells: Chest 4, Hamstrings 8, Biceps 10, Triceps
4, Core 2, Calves 2. Weeks 1-2, the holds evicted: Hollow Body Hold 14 day-weeks, Copenhagen Plank 2, Doorway Isometric
Curl 1; a budgeted slot that lost its seat to the time an eviction freed: Standing Towel Pull Apart 2 (in
`build_muscle|3|advanced|bodyweight|30|2` / `|3`, where Hindu Pushup and Tricep Dips Floor took the time); what came in:
Dumbbell Alternate Bicep Curl 7, Bodyweight Good Morning 4, Hindu Pushup 2, Tricep Dips Floor 2, Russian Twist 1,
Bodyweight Standing Calf Raise 1. No day lost a muscle group against main, but 32 day-weeks go from two Core-crediting
rows to one (Hollow Body Hold 28, Copenhagen Plank 4 evicted; round 10, seat B): the Pull + Core day of `lose_fat` /
`general_fitness` / `strength` `|6|advanced|home_dumbbells|30|1` weeks 1-4 (12; Renegade Row's incidental Core credit
stays; weekly Core 22 -> 19), the Push + Core day of `build_muscle|3|advanced|bodyweight|30|2` / `|3` weeks 2 and 4
(4), Full Body B of `lose_fat` / `general_fitness` `|3|advanced|bodyweight|30|1` (8), the Upper day of `build_muscle|4`
(6) and the `strength|4|advanced|bodyweight` Squat Day (2), the day's Core sets falling 6 -> 2 or 4 -> 2 where the
hold was its only dedicated core row; no Core weekly zero; the merge report names them all; 4 day-weeks lose a row (the Upper day above,
weeks 2 and 4 of 2 plans) and none gains one; minimum rows per day 4. The maxima of day minutes per session length (30 / 45 / 60 / 90) are unchanged
(34 / 46 / 61 / 91); 12 day-weeks grow by 1-4 minutes, within the day's time budget. Main's OFF world is unchanged (0
plans). Issue codes vs main ON: `lead_starved` -6, `low_volume` 0, `ab_swing` +2. Rejected: A (too broad), B and D3 (a
later Back or Shoulders hold gave way to arm work: D3 Back -639, Shoulders -594 set-weeks for Biceps +584, Triceps +296),
C (an archetype gate let Bench Dips evict lateral raises; Core -375), E (the day-only test: 68 deepened cells, 14 worse
plans), F (above), G (blind to holds: 3 trades for a group the week already held). A stated limit: guard (d) means a selector-thin day
(its reach below `countFloor`) never evicts, so Ruling 5 does not act there; such days are injured pools, which Ruling 8
and OI-452 cover.

**Ruling 5b, a second-row guard: tried and rejected (rounds 7-8, prototype J).** J (H plus a pass after A2: a day
left with one row seats its first slot refused by a weekly top at 2 sets past it) removed every one-exercise day in the
sweeps and left the 2,304-plan audit byte-identical, but three existing tests fail on it,
`session_set_allocator_behavioral_test.dart` "weekly top: a non-focus group stays at 16" (20), "lighter phase: every
weekly total stays at the band bottom" (16 against 12) and the 220-plan seeded sweep (12 against a top of 10, so the
guard fires on uninjured random plans too), and `session_set_budget_gate_test.dart` (which passed on J) asserts the weekly top as a hard
zero. That is how OI-452's first attempt failed (restore removed slots over the top: "broke
`session_set_allocator_behavioral_test` (weekly top 16 to 26) and the budget gate, so it was reverted"); OI-452 holds the
founder's chosen design (a 3-exercise day floor that may exceed the weekly band by a few sets, its own stats, the
weekly-top invariant restated) and "needs a plan, not a tweak". So no guard ships here: the allocator is prototype H3 (H plus Ruling 5's focus guard (e)),
the one-exercise and thin days are Ruling 8's, and the founder ruled on them with the full numbers (d16): ship, OI-452
next with its own plan. Prototype I (fewest rows first within a rank) was measured and rejected before J: at basic gym
Back's top of 10 seats five rows at 2 sets, and three Back days need six to hold two each, so some day keeps one.

**Ruling 5c, the empty-day guard's clock (build finding, Task 2, plan v19).** `session_set_budget_gate_test.dart`,
run with every goal on the core-list pool for the first time (Ruling 7), failed its time zero twice:
`lose_fat` and `general_fitness|4|advanced|bodyweight|30|1`, the Upper Pull day (weeks 1-4), 32.6 minutes against
30 + 2. Writer: the not-budgeted holds' time is spent first (`session_set_allocator.dart`, step 1): Doorway Isometric
Row, Single Arm Isometric Lat Pull, Doorway Isometric Curl and Hollow Body Hold take 1,344 of the day's 1,440 seconds.
The day's only budgeted slot, Sliding Lat Pull (256.8 s), is refused by the clock; Ruling 5 lets a hold give way only
to a slot bringing the week a FIRST credit, and Back is already credited by the Back holds, so nothing goes. Reader:
the empty-day guard (step 4) then forces the lead past the clock. Main's allocator builds the identical day on the core
path; these goals never ran there before, so H3 did not cause it and Ruling 5 named only its first-credit subset.
Rule: before the guard forces its pick past the clock, the holds ranked after the pick give way under pass A's
guards except the first-credit condition (the lead is admitted either way, so the only question is whether the day ends
inside its minutes): never a hold whose groups the day would then lack, never below the count floor, a major or focus
hold only for a pick that credits a major, all or nothing, last first. One helper (`evictFor`) now serves pass A and the
guard. Effect: the Upper Pull day loses Single Arm Isometric Lat Pull, Sliding Lat Pull grows to 3 sets, 29.6 minutes.
Measured: the 998 golden personas are unchanged (and the flipped tree's hashes equal the pre-flip H3 ON hashes on all
998, so Task 2's deletions changed none of them); the budget gate's grid is green. Residue: a forced minor pick beside
major holds, or a day at its floor, still runs past the clock (two fixtures pin it). The guard's pick is forced by the
clock (the first slot with weekly room) or by the weekly top (no slot has room, so rank 0): both run the scan, so a
cap-forced lead also evicts. A day whose evicted hold freed a seat may then grow, so its `belowCount` label can move
from `clock` to `cap_top` or leave (counted in `AllocationStats`, no golden key changes). Tests and mutants in Task 1's
file, group "the empty-day guard (Ruling 5c)" (forced lead, only credit, major vs minor, ranked before, the floor, all
or nothing, focus, a cap-forced lead; reviewer seat round 18), and the real-engine pin in
`oi489_timed_hold_real_engine_test.dart`.

**Ruling 6, the injured Push day (d13).** A bodyweight shoulder + wrist user's Push day gets core-pattern rows from
the top-up's core pass (exercise_selector.dart:1396-1421) once R6 is gone (inventory section 7, by reading). Task 5
measures it and pins it with a behavioral test; if the measured day is not a core day, the plan comes back with the
mechanism before any code for it. Measured before code (round 7, no R6, the 15-pair grid; prototypes H and J agree here): every bodyweight shoulder + wrist
Push-type day (Push, Push + Core, Upper Push, Push B) is core rows only, e.g. Plank, Dead Bug, Hollow Body Hold.

**Ruling 7, tests and mirrors.** (Line numbers in this ruling are the pre-flip tree's, `ea37ed59`; the final tree's are in
the registry and the diagnose doc.) Every test in the inventory's sections 2.1 to 2.3 is handled in Task 2; the files
that pin the OLD path get this disposition (protection, then its home after the flip):

| file | protection | after the flip |
|---|---|---|
| `bodyweight_capability_leak_test.dart` | OI-89: a bodyweight user never gets an equipment row, on the production path | rewritten on the core path: the hand fixture rows gain `core_levels`; same assertions |
| `injury_safe_omission_production_test.dart` | U2: an all-contraindicated pool omits the slot, never a contraindicated row | rewritten on the core path (`rankedPool`'s hard filter drops; the slot is empty, then the top-up); the dead parameter at :139 removed |
| `universal_pool_capability_behavioral_test.dart` | capability through the universal pool and through repeat pins | pool tests deleted with the pool (the fallback that bypassed `queryV4` no longer exists); the `buildPinnedDays` capability tests kept |
| `injury_substitute_preference_behavioral_test.dart` | 11-C re-rank keeps a contraindicated row out | re-pointed to `_pickCoreList` / the top-up, the surviving callers of `_selectCandidate` |
| `l2_no_custom_autoadd_behavioral_test.dart` test (4) | L6 still swaps a demoted pick | re-pointed to the core path's L6 partition (`demotedNames`) |
| `equipment_exclusion_filter_behavioral_test.dart:291` | att5 floor: every pool pattern keeps a bodyweight row | deleted with the pool; the file's exclusion tests on the core path stay |
| `plan_generator_targetcount_cascade_test.dart` | test 1 (:13-26): `volume_filter.dart` has no `targetCount` and keeps the deload rule; test 2 (:28-44): source-grep for the cascade | test 2 deleted (its subject is deleted); test 1 kept in the same file (nothing else pins that the table stays deleted; the behavioural twins are `session_set_budget_consumers_test.dart:729-757` and `plan_engine_v4_test.dart:45`) |
| `universal_pool_mirror_test.dart` | tracer pool == production pool | deleted (both sides deleted) |
| `library_batch_c2_name_readers_test.dart` | names quoted in production resolve | the universal-pool and `_universalPool` entries removed; the mutation test's base set (`q['universalPoolV4']!`, line 118) moves to a surviving reader's names (`InjurySubstitutes`); the rest kept |
| `keep_all_slots_selection_test.dart` | OFF half via `CascadeTracer`, ON half real `pickV4` | OFF half deleted, ON half kept |
| `core_list_pool_behavioral_test.dart` :255, :526, :539, :624 | OFF is the golden; a stale library delegates to OFF; a mixed library delegates (`hasCoreFields`'s `any()`); R6 | deleted with what they pin; replaced by "no empty day" and "a library without `core_levels` picks nothing" |
| `v4_diagnostic_test.dart`, `plan_generator/injury_safe_omission_test.dart`, `scorecard_gate_test.dart` and the mirror family (`cascade_tracer.dart`, `query_v4_mirror.dart`, `generator_matrix.dart`, `plan_scorecard.dart`, `sample_plans_report.dart`, `generate_baseline.dart`, `dump_all_picks.dart`, `markdown_writer.dart`, and the files only
they use: `v4_diagnostic/library_integrity.dart`, `combos.dart`, `library_loader.dart`, `baseline/baseline_scorecard.json`,
`baseline/baseline_plans.md`, `sample_plans_output.md`) | the scorecard's hard `== 0` equipment violations over 606 personas; a mirror-level check of `queryV4` | deleted. The equipment `== 0` moves to the core-list gate, which runs the real `generateV4` and checks `canPerform` over the 998 golden personas (4 goals, gate lines 282-284); Task 3 compares the two persona sets and extends the gate's grid if the scorecard covered a day count or tier it does not. `queryV4` keeps its own repository tests (Task 3 names them); the mirror-level check of it is gone, stated. `v4_diagnostic_test`'s small library data-sanity check (tiers, the 11 patterns) is dropped on purpose: the library's own contract tests (`exercise_library_schema_contract_test`, `equipment_tier_consistency_test`) hold the data. The
scorecard's other pins: `missing == 0` (no empty slot) is replaced, as a weakening, by the gate's per-slot drop cap
(at most 1 drop per gym list, `core_list_pool_gate_test.dart:365`) and the no-empty-day zero: a dropped slot the top-up
or the day's other slots cover no longer fails a test (round 12, seat A); `unsafe <= baseline` to the gate's `isContraindicated` check and the sweep's unsafe assertion; `fallback <=
baseline` has no subject (no fallback pool exists); the mean score is dropped on purpose (a mirror metric). The
library-removal scripts that cite the scorecard as their depth check (`library_batch_c2_removals_gen.js:39-40`, the
removals JSON) are history and keep their text |
| BOTH-world files (`thin_day_topup`, `cross_day_variety`, `same_movement`, `same_movement_day_gate`, `session_set_budget_gate`, `variant_b_quads`) | each feature in both worlds | the OFF halves deleted; `session_set_budget_gate` runs every goal on the core path |
| `test/contracts/same_movement_behavioral_test.dart` (round 14, seat A's P2; round 15, seat A's P2 and P3s) | S1b-2's same-movement rules (`docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md:93`, acceptance :165) | test 1 (`queryV4`) and test 3 (ON same day) stay; test 2 (OFF same day) goes, its home is test 3 and `same_movement_day_gate_test.dart`; test 5 goes with the universal pool (Ruling 2). Test 4 is KEPT and run ON at `level: 'beginner'` (S1b-2's "ON B avoids it softly" has no other test: `same_movement_day_gate_test.dart:62-79` checks one built day, never B against A): rows E147, N14, X001 on the dumbbell tier give A = Dumbbell Sumo Squat and B = Test Squat through `softFor` (`exercise_selector.dart:897`, `sameMovement.expand`); mutant: `softFor` stops expanding, B = Sumo Squat (red); the file's header "Mutations" line is updated. Tests 6 and 7 (L6: a demoted original is not replaced by its own loaded version; MIRROR: a demoted loaded version does not demote its original) are protection the OFF `_applyHistoryAdjustments` alone gives today (it passes `pickedNames` holding the demoted pick); the core path only sorts a demoted row last (`core_list_selector.dart:398`), so with E147 demoted it would hand the user N14. Re-implemented on the core path: `_pickCoreList` widens the demoted set by the loaded versions of each demoted ORIGINAL (rows whose `same_movement_as` names a demoted row's id; row-level, since `SameMovement` is symmetric), one direction only, before `rankedPool` and the `avoidNames` set (`exercise_selector.dart:795-798`, :840-844). Tests 6 and 7 run ON at `level: 'beginner'` (E147's `core_levels` is beginner only; at the file's default intermediate the core pool is {N14, X001}, E147 is never a candidate and test 7 is red without any change). Mutants (Task 2): widening both ways (test 7 red, only); dropping the widening (tests 6 and 6b red); widening `rankedPool`'s demoted set but not `avoidNames` (test 6b red, only), test 6b being new: `previousPhaseByDay` carries 'test squat' with E147 demoted at beginner, so with the widening in `avoidNames` every candidate is avoided and `_preferNovel` falls back to `pool.first` (X001), without it N14 (no loaded version is in any `InjurySubstitutes` list, so an injured-substitute case could not separate this mutant). This amends S1b-2's Decision 2 row "Demoted names ... per-exercise preference ... no" (`...s1b2-loaded-versions.md:90`) for the ON path, the top-up included (round 16, seat A's P3-2): one helper widens the demoted set, and both `_pickCoreList` (:795-798) and `topUpDays` (its lowercased `demoted` at :1258-1259, filtered in `_topUpVariant` at :1384) read the widened set, so the top-up ladder cannot hand an injured user N14 with E147 demoted; a fourth mutant (the top-up reads the unwidened set) reddens a new test 6c (an injured beginner day whose core slot is emptied so the top-up fills it, E147 demoted, expects no N14). No history means an empty demoted set, so the audit and the golden are untouched. The diagnose doc and S1b-2's plan (an amendment line under its Decision 2 table and under its acceptance line :165-166, "a demoted or plateau name's partner is NOT avoided for that reason alone", which now holds for plateau names only) record it, and Task 6 rewrites the five places that state the old rule (listed in Task 6). Mutant sites (round 17): mutants 1-3 are applied at `_pickCoreList`'s call of the helper, mutant 4 at `topUpDays`'s (a helper-level mutant would also redden 6c). Test 6c's recipe: injury `shoulder` (E147 and N14 both carry `hip` and `knee`, which would drop them and pass vacuously), phase 2 (`demoted` is read only when `phase >= 2`, :1259), `home_dumbbells`, a hand-built day holding 2 non-squat rows (with 0 rows the floor forces the demoted rows back in as sole candidates), rows E147, N14 and X001 seeded; widened: X001, unwidened: N14 |

Also: `plan_audit_dump_test.dart:155` asserts the deleted flag (the harness becomes one-world; its baseline is the
pre-flip tree's dumps, regenerated from a worktree at ea37ed59 with the same command, never committed: they are 2,304
plans x 2 worlds of build output); `thin_day_topup_behavioral_test.dart:215-229, 983-987, 996, 1055-1073` use `coreListOnly: false` or the flag OFF as a control (the helper
loses the parameter and the control test is deleted with it, its subject gone). The att5 floor invariant
(`equipment_exclusion_filter_behavioral_test.dart:291`) is gone with the pool it pinned: the core path has no
name-picked fallback that bypasses the filters, and the empty-day zero of Ruling 3 is its replacement guard.

`plan_engine/CLAUDE.md`'s verification tools (`sample_plans_report.dart`, `v4_diagnostic_test.dart`) are replaced by
the audit harness and the core-list gate in the same edit.

**Ruling 8, the injury floor sweep.** The 5 sweep blocks (`plan_generator/injury_sweep_{a_pairs,b_singles,c_pairs46,
d_repeat,e_singles46}_test.dart`, `test/helpers/injury_floor_sweep_lib.dart`) run the cascade today and the core path
after the flip. They keep their hard zero on empty days; `kThinCeilings` (lib lines 265-300, an exact ratchet that
fails above and below) is re-recorded once on the final tree, DOWNWARD only (the lib's own rule, near line 255: a ceiling
moves down freely, a rise needs a recorded decision); a rise is Ruling 3's stop, not a re-record. Each changed block
is named with its old and new count and the cause. The parent plan's line 193 ("`kThinCeilings` is OFF-world and does not move") held for 1A and is
superseded here. Acceptance: 0 empty days, no retired, skill or olympic id in a built list (the sweep lib gains that
assertion; today it checks unsafe, unresolved, unperformable, duplicate and empty only), thin and one-exercise days at the
counts below (d16). Retired rows (the gate's definition, 10 rows, Ruling 3) can in principle still enter through the top-up's pass 2, the non-core ladder (`_topUpVariant`'s pass 2
filters skill and olympic only). The flip criterion is the `enable_core_list_pool` entry in
`docs/ship_dark_pending_review.yaml` ("no retired or skill / olympic id in the BUILT lists over the multi-injury
sweep"), and step 1A's ledger entry `OI-436-R6` allows "or the founder accepts each run"; OI-436's own "Done when"
covers only the `emergencyAnyLevel` path. Measured without R6 (Ruling 3): 0 retired ids over 3,456 runs, and again over the 11,520-run grid (E261, today's
only one, came through R6). So the criterion is held as a hard zero: Task 5 counts retired ids per floor-sweep block and
the CI hard test and the env-gated grid assert none; a count above 0 is Ruling 3's stop, not a listing.

Measured before code (rounds 7-8, prototype H, ON without R6, weeks 1-2, the sweep lib's own `scan`,
`r6_wide_noR6.txt`): every block has 0 empty, 0 unsafe, 0 unperformable, 0 duplicate days and 0 retired, skill or olympic
ids. `a_pairs` thin days home dumbbells 10 -> 20, basic gym 22 -> 30, full gym 14 -> 20, one-exercise days 0 -> 2, 0 -> 2,
0 -> 0 (a RISE); `c_pairs46` 12 / 8 / 4 -> 0; the bodyweight repeat 2 -> 0; every other block 0 -> 0 (block total 72 ->
70 thin, 0 -> 4 one-exercise). Every `a_pairs` thin day is shoulder + elbow (Upper 40, Pull 20, Push 8, Shoulders + Arms 2
day-weeks; all 5-day splits: beginner 46, intermediate 20, advanced 4). Beyond the sweep's reach, the full live baseline
(a detached worktree at ea37ed59, the old picker with R6 and main's allocator) against H over the 15-pair grid at phases
1-3 and the pinned repeat (11,520 runs, weeks 1-2): thin day-weeks 341 -> 352 (phase 1 70 -> 70, phase 2 70 -> 70, phase
3 20 -> 44, repeat 181 -> 168), one-exercise day-weeks 8 -> 20; per pair, phase and tier in section 9's round-8 entry. Ruling 5's share (round 9, seat B): the same grid with the flag on and MAIN's allocator (no Ruling 5) gives the same row
count on all 103,680 day-weeks as H (thin 352, one-exercise 20, 0 empty), so every one of these days is the picker's,
not the eviction rule's.
Writers and readers (single-persona probes with an allocator input print), every case the same class, a weekly top
spent by the week's other rows before a later day's third row:
- shoulder + elbow, phases 1-3 and the repeat (the 12 new one-exercise day-weeks: `general_fitness` beginner 5-day,
  home dumbbells and basic gym, the Upper day). Writer: the picker and the top-up. Every press, lateral-raise and arm
  slot has an empty pool (trace `drop`, pool 0); live filled the Push day with retired rows that credit Chest (E234
  Floor Press; E261 Bodyweight Rear Delt Raise), ON fills it from the top-up's `shoulder_isolation` neighbour (Band Pull
  Apart, Reverse Fly, Face Pull), rows that credit Shoulders AND Back, so Push, Pull and Upper all hand the allocator Back
  rows. Reader: `SessionSetAllocator._variant` pass A seats by (rank, day) against Back's weekly top (10 at
  `general_fitness` beginner, 14 at phase 3); the Upper day keeps its lead lift (rank-0 reservation) and its later rows
  are refused by the top alone; pass A2 never passes a top. Of the 187 day-weeks that get thinner in the two dominant
  pairs, 69 are days whose live version held a retired row (Floor Press 44, Chest Squeeze Press 12, Bodyweight Rear
  Delt Raise 13); the other 118 are Upper / Pull days and repeat days that lose a third row to a top a retired-free week
  spends earlier. 117 of live's thin day-weeks there get fuller ON.
- shoulder + lower_back, the repeat (home dumbbells 0 -> 20, basic gym 2 -> 14 thin). Writer: the repeat pins the ON
  phase-1 uninjured plan, so every Full Body day hands the allocator Goblet Squat, Resistance Band Seated Straight Back
  Row and a lunge (Walking Lunge / Step Up / Band Squat Row). Reader: the Quads and Glutes weekly top (12 at
  build_muscle beginner) is spent by days A and B, so days C and D keep two rows.
- the pre-existing one-exercise day (live 8, H 8): the bodyweight shoulder + lower_back beginner 4-day repeat's Full Body D
  (Walking Lunge alone), the same reader.
Ruled by the founder with these numbers (d16, section 10): the flip ships with them, recorded on OI-452 (its chosen design,
a 3-exercise day floor that may pass the weekly band by a few sets, is the fix), which gets its own plan right after the
flip. The three `a_pairs` ceilings are raised to 20 / 30 / 20 thin and 2 / 2 / 0 one-exercise with that cause beside
them in the lib; every other block is re-recorded downward.

Session length (round 13, seat B's P2-1; d23; corrected in round 14). Every number above ran at 60 minutes: the sweep
lib's `gen` passes no `sessionDuration`, so `generateV4` takes its default. Re-measured on the 15-pair grid with the
length set (103,680 day-weeks each, weeks 1-2; `pairs_dump_{OFF,ON_H3}_m30.txt`, `pairs_dump_{OFF,ON_H3}_m45.txt`,
main's allocator at 30 minutes in `pairs_dump_ON_main_m30_rerun.txt`):

| length | live thin | flip thin (H3) | flip thin (main's allocator) | one-exercise live -> flip | empty |
|---|---|---|---|---|---|
| 30 min | 427 | 520 | 520 | 8 -> 20 | 0 |
| 45 min | 341 | 344 | not run | 8 -> 20 | 0 |
| 60 min | 341 | 352 | 352 (`pairs_dump_ON_main.txt` and `pairs_dump_ON_H.txt` are byte-identical) | 8 -> 20 | 0 |

The 30-minute main-allocator cell (round 14, seat B's P2-1: the first run's file was overwritten by a stopped chain's
next leg, 168 lines left; the cell cites the re-run, 103,680 day-weeks): thin 520, one-exercise 20, and the SAME 520 thin
day-weeks as H3, with identical picks on the 332 new ones. Ruling 5 does act at 30 minutes on injured users: H3 changes
the picks of 1,713 day-weeks against main's allocator (355 change their exercise count, 232 up by one and 123 down by
one; 400,901 rows against 400,792), none of them across the 3-exercise line. So the 30-minute rise is the picker's and
the pins', not Ruling 5's. What those 1,713 day-weeks do, both directions (round 15, seat B's P2-1; major groups, run-week
cells, `BudgetMuscleGroups` credit over `lib.hip14.json`, bands from `session_budget.dart`; `1bf_sym.py`): H3 lowers 441
major cells (-598 sets; Glutes 150, Back 129, Quads 77, Chest 64, Shoulders 21) and raises 1,410 (+2,224 sets); 56 cells
drop below the band bottom where main was at or above it, 63 rise to it from below; H3 empties 2 major cells main had
(Shoulders, shoulder + lower_back, home_dumbbells, general_fitness advanced 6-day repeat, weeks 1 and 2, 4 sets to 0, a
shoulder-injured user) and fills 429 that main left at zero (the OI-489 class, Ruling 5's purpose); 93 day-weeks lose
main's first row (Push Up 32, Doorway Isometric Row 24, Resistance Band Seated Straight Back Row 18) and 91 keep a
first row main lost, so the lead count is level; 53 changed day-weeks lose a major group main's day held (primary-muscle
credit, day-weeks whose name order differs; round 16 seat B, correcting round 15's 65) (example: knee +
lower_back bodyweight lose_fat beginner 3-day phase 3 Full Body B, main's only Chest row Push Up replaced by the
top-up's Self-Resisted Bicep Curl and Prone T Raise). At 60 minutes main and H3 are byte-identical on this grid.
The 56 down-crossings are one class (round 16, seat B): Back 48, Glutes 7, Chest 1; advanced 42; bodyweight 30 and
home_dumbbells 26; 35 of 11,520 plans (0.3%), each 1-4 sets under the band bottom, at 30 minutes only, none offset by an
up-crossing in the same run. Mechanism: a Back row (Resistance Band Seated Straight Back Row, Doorway Isometric Row,
Band Standing Rear Delt Row) gives way to a row that fills an empty group (Dumbbell Alternate Bicep Curl, Bodyweight
Good Morning), so Ruling 5's zero-cell floor outranks Back's band bottom there. Accepted as Ruling 5's measured trade on
injured users at 30 minutes (net +1,626 major sets, 427 fewer zero cells). This acceptance is the plan's own call, not
part of d23 (which ruled the thin days only), and it sits in the class OI-452's day floor and step 2's weekly floor
(d14, d20) own. No ratchet targets it; Task 5 re-measures it on the final tree with the same script and records the
Back-below-bottom count for injured 30-minute runs beside it, so a later change has a baseline.

At 30 minutes the flip makes 332 day-weeks thin and heals 239 (net +93); at 45 minutes 193 and 190 (+3); at 60 minutes
201 and 190 (+11). By phase (thin day-weeks, live 30 / flip 30 / flip 45 / flip 60): phase 1 70 / 70 / 70 / 70, phase 2
70 / 70 / 70 / 70, phase 3 20 / 44 / 44 / 44, pinned repeat 267 / 336 / 160 / 168 (live 60: 181). So the whole
30-minute-specific rise is the pinned repeat. The 332 split into two writers, one reader:
- 188 day-weeks hold 2 exercises at 30, 45 and 60 minutes (already in d16's 352). Writer: the picker; a slot whose
  core-list rows all fail the injury filter gets no row where live fills it from the whole library (live rows absent
  from these 188 days: Floor Press, a retired row, 44; Face Pull 38; Band Pull Apart 30; over all 332, Floor Press 158,
  Band Single Arm Standing Low Row 42, Face Pull 38, Band Pull Apart 33, the other 114 Floor Press days being among
  the 144), and the top-up's neighbour rows credit Back, so the reader below refuses them.
- 144 day-weeks hold 3 or more exercises at 45 and 60 minutes (142 hold 3, 2 hold 5) and 2 at 30; every one is a pinned repeat day (139 beginner).
  Writer: the repeat's pins, `namesByDay` of the user's phase-1 uninjured plan generated at the SAME length. At 60
  minutes that plan holds 5 or more rows on these days (139 hold 5, 4 hold 6, 1 holds 8), including a core row
  (Russian Twist) that every pair allows; at 30 it holds 4 (`SessionBudget.countFloor(30)` = 4, `countMax` caps the
  day; no picker read of the length) and fewer core rows (128 of the 144 pin days hold none), so the injured repeat
  day's substitutes for its unsafe pins (push, lunge) are mostly Back rows. Traced (`rep30_trace.log`, knee +
  wrist bodyweight general_fitness beginner 3-day; shoulder + elbow home_dumbbells 4-day): the allocator sees 3 rows on
  the day at both lengths (`rowsSeen` 3), keeps 3 at 60 and 2 at 30 (the first persona's third row at 60 is Russian
Twist; the second persona's day D already holds Russian Twist at 30, and its third row at 60 is Bicycle Crunch). Of the rows these
  days hold at 60 and lose at 30, Russian Twist is 124 of 144.
- Reader (both): `SessionSetAllocator._variant` pass A's weekly top (Back 10 at `general_fitness` beginner) and pass
  A2's `canForce` (the same top), the OI-452 class: a weekly top spent by earlier days refuses a later day's third row.
Ruled by the founder (d23): ship, OI-452 next (its 3-exercise day floor fixes both groups). The founder was asked with
the first writer only; the 144's corrected mechanism was reported to the founder after round 14 with the same counts.

CI ratchet (round 14, seat B's P2-3/P2-4): `a_pairs` (phase 1) shows no length effect (70 thin at 30 and 60) and
`d_repeat` pins single injuries, so neither carries the 30-minute rise. A new block,
`test/plan_generator/injury_sweep_f_repeat_pairs30_test.dart`, runs the pinned repeat over the 15 pairs at 30 minutes,
beginner only (301 of the 336 thin repeat day-weeks, 139 of the 144), every goal, 3-6 days and every tier: 960 runs
(15 x 4 x 4 x 4) plus 64 uninjured phase-1 plans for the pins, one `test()` per tier, a file-level
`@Timeout(Duration(minutes: 10))` and `library;`. The sweep lib's `gen` gains an optional `minutes` argument that BOTH of
`runRepeat`'s calls take (the pin plan and the phase-2 plan; seat A's P3-3), a new `runRepeatPairs(tier, minutes)`
iterates the pairs, and its block name `f_repeat_pairs30` gets its own `kThinCeilings` entries (thin and one-exercise
per tier), recorded once on the final tree under d23 (Task 5); a null `minutes` keeps every 60-minute run and ceiling
as it is. Cost: 960 runs at CI's measured 0.18-0.39 s per run (pairs 0.18-0.27, repeat 0.22-0.39, bodyweight the
slowest) plus 64 shared pin plans = about 3-6 minutes in one file; with Ruling 3's eight files the
partition check in Task 6 places it, and a shard over 25 minutes on the PR run moves it to the env-gated grid with
the no-thin extension runs (Ruling 3's rule).

**Ruling 9, docs and gates.** The `docs/sot_registry.yaml` lines that name deleted things (item 1B-4) are re-pointed or
removed (the concept `universal_pool_fallback` is removed whole: its subject and its `behavioral_test_path`,
`universal_pool_mirror_test.dart`, are deleted, and Gate 42 resolves that path on disk), found by shape, not by a fixed symbol list: 29 lines match the seven deleted symbols (`_fillSlots`, `_cascadeFill`,
`_applyHistoryAdjustments`, `universalPoolV4`, `hasCoreFields`, `enable_core_list_pool`, `coreListPoolEnabled`; 49 with the
kept `pickV4`; round 16 seat A, correcting 48), and a sweep for the
deleted file names (`cascade_tracer.dart`, `query_v4_mirror.dart`, `v4_diagnostic`, `scorecard`), `hasCoreFields`, the V3
injury-filter cites and attempt-5 prose finds more (53 lines on a widened grep; the parity and completeness gates check
only blocks with a `line_range`, so a stale citation elsewhere passes silently); every remaining
`exercise_selector.dart` and `session_set_allocator.dart` range is recomputed from its anchor on the final tree; the seam gate's `SeamEntry(22, ...)` (scripts/exercise_seam_lib.dart:59, item 1B-3) is recounted (7 library reads remain, by
round 8's reading of HEAD: the lines at 594, 807, 1054, 1242, 1355, 1540 and 1870; the final tree's count is what is recorded);
`plan_engine/CLAUDE.md` and `docs/architecture/plan-engine-detail.md` lose the cascade text; `docs/naming_conventions.md`
rows for the deleted keys move to their retired form; `dart run scripts/check_context_artifact_budget.dart` (then `--record` if intended; `plan_engine/CLAUDE.md` is
budgeted); also `README.md:217` ("5-attempt cascading fallback per slot"), `docs/architecture/functionality-flow.md:178` (TRAIN-27, "5-attempt cascade"),
`docs/reference/directory-structure.md:96, 214, 238`; the code comments that name the deleted flag or the cascade
(`core_list_selector.dart:2-5, 62`, `plan_engine_flags.dart:15-20, 171, 337, 345, 353, 374, 380, 393, 450` (the
`[injuryUniversalFilterEnabled]` dartdoc at :450 dangles), `seed_service.dart:110, 153`, `injury_vocab.dart:10`, `injury_substitutes.dart:5`,
`equipment_vocab.dart:243`, `same_movement.dart:5`, `training_history_analyzer.dart:320`; round 8 adds `models.dart:285`,
`injury_substitutes.dart:3, 10, 16`, `plan_engine_flags.dart:13, 185, 432-435`, `core_list_selector.dart:143`, the
stale `pickV4` dartdoc at `exercise_selector.dart:545-548` and `plan_engine/CLAUDE.md`'s line on the V3 `pick`) are rewritten; Task 6's
last step greps the tree for the deleted names once more. `plan_generator.dart:98, 137, 182` ("null -> verbatim pickV4 cascade") are rewritten as comments only, under d18
(section 10), and under d21 every other stale comment in the file (lines 97-99, 109 "the cascade avoids
repeating", 135-136 "att5 pool / L6 swap", 181-184, 252 "exercise-selection cascade"); nothing else in that file
changes beyond d15's two call sites. `warmup_cooldown.dart`'s `mainCascadeOverlapMoves` keeps its name (it names the
main block's moves, not the deleted picker; Task 6's prose grep lists it as reviewed). `test/plan_generator/v4_diagnostic_output.md`'s entries
(`.gitignore:123`, `gitignore_classification_test.dart:283`, `retire_worktree_lib.dart:282` and its test at
`retire_worktree_lib_test.dart:283-309`) stay: old worktrees, the primary included, still hold the file, and removing
the entry would make it non-regenerable there. The ship-dark entry moves to `resolved:` with a note on Unit 1B-F2 (the overlay copy B1 Ruling 4
assigned to "the flip commit", split out under §4.12.1), on the OI-401 question (the top-up under the pool is
core-list-first since 1A's R4), and on the retired-id criterion, met as a hard zero (Ruling 8; measured 0 over the 11,520-run
pair grid and every floor-sweep block without R6, asserted by the new test).

Ruling 5 reverses the session set budget's "a timed row keeps its sets and is never removed" (B2 plan
`docs/plans/2026-10-22-session-set-budget.md:346`): updated in the same commit are `plan_engine/CLAUDE.md` (the session
set budget item, and the thin-day line that a day "may end with 1-2 exercises"), `docs/architecture/plan-engine-detail.md`
(the timed-row paragraph near :362), the `session_set_budget` description in `docs/sot_registry.yaml`, the
`SessionSetAllocator.allocate` doc comment, and OI-489's diagnose names the B2 statement it amends.

**Ruling 10, the overlay copy (item 1B-7, item 1B-11).** Split out of this unit as Unit 1B-F2 (section 11).

**Ruling 11, the golden.** `generator_golden_hashes.json` hashes the live world today. It is re-recorded once, after
every code and data change, and attributed: each changed key is explained by the flip (its plan equals the ON-world
plan of the pre-flip tree with Ruling 5 applied, recorded in Task 1 before Task 2 deletes the flag), by Ruling 5,
or named. The golden persona set grows by the
exclude-everything personas of Ruling 4 (new keys, recorded).

**Ruling 12, hip-unsafe jump rows (d19, round 12, seat A's P2).** Scope check (round 14, seat A's P3-4: a scan of
all 870 rows for `high_impact` and jump / hop / plyo / burpee / run / skip names gives the same 18 candidates): reviewed
and left, because none lands from flight, which is d19's criterion: E201 Spot Jogging (`[ankle, knee]`, the in-place
warm-up), G0550 Kettlebell Thruster and G3305 Barbell Thruster (squat-to-press, `knee`, `shoulder`), E140 Kettlebell
Swing (a hinge, `lower_back`); G1353 is one of the four upper-body throws below. Measured on the 15-pair grid (H3, flag on, no R6):
a hip-injured user's day opens with a jump row in 3,189 day-weeks (Jump Squat 2,896, Box Jump 247, Skater Hops 24, Forward Jump 22; live 541) and holds
one in 4,300 (live 1,318), all in the four hip pairs. Writer: the library tags, where Jump Squat (E193), Box Jump
(E066), Forward Jump (G1472) and Skater Hops (G3361) carry only `ankle` / `knee` (Lunge with Jump, G3582, already
carries `hip`); with a hip injury the knee_dominant pool holds only jump rows, and `CoreListSelector.rankedPool` keeps a
jump-only pool rather than empty the slot (`core_list_selector.dart:322-330`). Reader: `_pickCoreList` through
`_selectCandidate` (`exercise_selector.dart:863`). Fix (data, not code, so the contraindication contract keeps one
source): the 14 lower-body jump rows that lack `hip` gain it, E063 Jump Rope, E065 Burpee, E066, E193, E202 Jumping
Jacks, G1473 Backward Jump, G1472, G0053 Barbell Jump Squat, G0371 Dumbbell Plyo Squat, G3219 Scissor Jumps, G3361,
G3222 Semi Squat Jump, G1201 Dumbbell Burpee, G3656 Short Stride Run (Time); the 4 upper-body plyometric rows (G1750,
G0492, G1273, G1353) are not tagged. Measured before code with all 18 tagged (a superset of removals; `pairs_dump_ON_Hhipjump.txt`):
jump-led day-weeks 3,189 -> 0, any jump row 4,300 -> 0, thin 352 / one-exercise 20 / empty 0 unchanged, every non-hip
run identical; hip days now open with Romanian Deadlift, Good Morning, Band Hip Lift, Backpack Romanian Deadlift and
the like. Cost, measured on the same grid (round 13, seat B; founder d22 kept d19 with it shown): for the 1,920 hip x
bodyweight run-weeks, median weekly Quads sets live 5 / flip 5 / d19 0, run-weeks with no quad work 501 / 622 / 1,518,
Wall Sit the only quad row left; gym and dumbbell tiers unchanged; Calves sets over all hip runs 59,179 -> 49,374. The
alternatives the founder saw and declined are in section 10 (d22). Task 5 re-measures the 14-row tree and the closure
carries the cost table under d22. No migration and no live step: `injury_contraindications` has no cloud
column (`backups/live_schema_columns.json`; `175_reseed_exercise_library.sql:10-21`; the cloud tuple,
`scripts/seed_exercise_library.js` `tupleOf`, carries no injury field; v21 and v22 were bundle-only bumps too). Touch list:
- E-rows (E063, E065, E066, E193, E202): kept verbatim by the importer (`scripts/add_library_batch_c_v15.js:432-440`), so
  a hand edit would pass `--check`; instead a fourth importer stage beside the E230 retag, core-levels and suitable_for
  stages applies a `{id, before, after}` record, `scripts/data/library_injury_additions_v25.json` (already `account`
  tier through `docs/blast_radius.yaml:526`'s glob; `blast_radius_library_data_account_test.dart` gains a case), so a
  hand edit of the asset goes red under `--check`; the stage refuses a `before` that does not match the row.
- G-rows: their tags are sorted(source tags UNION table tokens) (`add_library_batch_c_v15.js:147-150`). With E066, E193,
  E202 and E065 carrying `hip`, the builder's family floor (`build_library_injury_additions_v15.js:70-76`, oracle
  `test/helpers/library_injury_floor.dart:60-66`) becomes ankle+hip+knee for `jump` and gains `hip` for `burpee`, so the
  9 floor-class rows of those families (G1473, G1472, G0053, G0371, G3219, G3361, G3222, G1201, and G3582 Lunge with
  Jump, whose raw tags already hold `hip` but whose committed table row reads `[ankle, knee]` with the old floor reason,
  `library_injury_additions_v15.json:4895`; round 13, seat A) are rebuilt by the builder and the founder-approved table
  `scripts/data/library_injury_additions_v15.json` takes the builder's own output, or the from-scratch test
  (`library_batch_c_injury_coverage_test.dart:583`) goes red; G3656 (judgement class, no E-row in `cardio_run`) gets
  `tokens: ['hip']` by hand with a reason naming d19. Family membership: `jump` = E066, E193, E202 + the 8 G rows above
  (G3582 included), `burpee` = E065 + G1201, `cardio_jump_rope` = E063 only, `cardio_run` = G3656 only. Order: record
  and importer stage, importer run (the E-rows change), builder `--drop <id>` for each of the 9 and a re-run (it reads
  the E-rows from the asset), importer run again (the G-rows take the table), then `--check` for both. d19 supersedes
  the v14 choice (`library_injury_additions_v14.json`, d30de7, founder 2026-10-23) that gave E203 High Knees `hip` but
  not E202 Jumping Jacks, E063 or E065 ("matches the warm-up list"); the frozen v14 table keeps its text and its
  "every table token is in the library row" check still holds (round 13, seat A).
- Seed v25 (`seed_service.dart:172`, a v25 comment block in the v24 style; `_seedExercises` `putAll`s by id, so no code)
  and `test/contracts/library_seed_v25_upgrade_behavioral_test.dart` on the v24 model: the v24 bundle rebuilt from the
  current asset with the 14 lists restored from a committed fixture `test/fixtures/library_hip_tags_v24.json` (restated,
  never read from git), pinned at sha256 `5470450a61073fbd6e2683dd323b1f38f6319b43123144d1c306eecda2b2ab13` (computed
  from HEAD's asset by the method that reproduces v23's `d858d26b...`); a v24 box ends at v25 with the 14 rows rewritten
  and every other row unchanged, and a box already at v25 is not rewritten; a precondition that the 14 carry `hip` and
  the 4 upper-body rows do not.
- Red tests and their edits (repoint, never loosen): `exercise_library_frozen_reference_test.dart` (the 5 E-rows hash
  `injury_contraindications`): re-record with `RECORD_LIBRARY_REFERENCE_IDS=E063,E065,E066,E193,E202`, the diagnose
  names them; `library_seed_v23_upgrade_behavioral_test.dart` and `library_seed_v24_upgrade_behavioral_test.dart`
  rebuild older bundles from the current asset, so their `_v23Bundle()` helpers restore the 14 lists from the same
  fixture first (digests unchanged, the chain stays proven); `library_batch_c_injury_coverage_test.dart` (the
  from-scratch test at :583 and the floor checks) is green once the table is rebuilt; `warmup_library_injury_mirror_test.dart:55-77`
  requires `warmup_cooldown.dart`'s `_moveInjuries` to equal the library, so `'Jumping Jacks'` (:44) becomes
  `{'knee', 'ankle', 'hip'}` and `'Jump Rope'` (:46) `{'knee', 'ankle', 'wrist', 'hip'}`, with
  `warmup_injury_filter_behavioral_test.dart:167-170`'s pin and its comment (:140) updated, and `warmup_cooldown.dart:26`'s
  "pinned for all 27" comment corrected to 26.
- The seed bump reddens every earlier upgrade test that hard-codes the current version (round 13, seat A; the S1b-3 v24
  bump edited the same set): the 14 `as int, 24)` final-version asserts (v18 1, v19 1, v20 3, v21 3, v22 2, v23 2, v24 2),
  v16's `const _currentVersion = 24` (:31) and its comment, and the five MIRROR tests that mark a box at 24 and expect it
  untouched (v20:107, v21:102, v22:89, v23:122, v24:106) are repointed to 25 (never loosened); the v24 test's "a v23 box
  ends at v24" `others` snapshot excludes the 14 ids (their v24 state comes from the fixture); `library_seed_prune` and
  `library_seed_v15` are re-checked as S1b-3 did; the registry's `behavioral_test_path_v24` text ("a v24 box left alone")
  moves to v25.
- Effect beyond the core path: `queryV4` (`exercise_repository.dart:420-429`) drops the 14 for a hip user in every
  pool it serves (the top-up, swap lists); the warm-up loses Jumping Jacks and Jump Rope for a hip user (bodyweight keeps
  Spot Jogging, gym keeps Cycling; floor Slow Walking, `warmup_cooldown.dart:236-240`). The cardio finisher takes no
  injuries at all (hard-coded names, `cardio_finisher.dart:152-215`): that is OI-396, open with its founder decision
  (2026-10-22: an injured gym user gets Stationary Bike Sprints, a home user no finisher), not widened here.
- Naming (§4.7): `docs/naming_conventions.md` gains rows beside the retag / core-levels records (:272-274) for the
  injury-tag record `library_injury_additions_v25.json` (a `{id, before, after}` record for kept rows, unlike the v14 /
  v15 tables of tokens added to new rows) and the fixture `library_hip_tags_v24.json` (round 13, seat A).
- Docs: `docs/sot_registry.yaml` concept `exercise_injury_tags` (:11612-11690) gains the v25 paragraph and the record /
  stage writer, the `library` concept a "Library v25" paragraph and `behavioral_test_path_v25`, and the warm-up note's
  "27 keys" is corrected to 26; the diagnose doc (full template) names the 5 re-recorded ids and the measurement.
- Sweeps: the floor sweep's `kThinCeilings` are exact ratchets, and hip sits in the singles, the pairs and the repeat
  blocks, so Task 5's re-record covers them under Ruling 8 (a rise is Ruling 3's stop); the golden has no hip persona
  (`generator_golden_personas.dart:125`), so Ruling 11's attribution expects no d19 key; the scorecard's hip singles
  are deleted with the scorecard (Ruling 7).

## 4. Items with no work left, and items carried

- 1B-9 (E053 retired, S1b-3), 1B-10 (no `core_levels` outside `suitable_for`; E010 / E045 widened in S1b-2; E255 has
  no `core_levels`, E134 is advanced-only in both fields): no work. 1B-7 (the overlay copy) and 1B-11 (the seed and cloud re-seed it
needs): Unit 1B-F2, section 11.
- 1B-8 (OI-148 rows): nine loaded versions shipped in S1b-2. OI-148's board text is refreshed; its three weighted
  rows stay `upstream_blocked` on the selection-skew answer OI-148 already names, `reopen_when` Batch D's plan.
- OI-485 (3), `iso_first`: 12 ON plans, all `strength|4|advanced|bodyweight|*`, flagged because the Squat Day
  opens with E143 Skater Squat before Bodyweight Good Morning. Mechanism: production builds the pick with
  `typeOverride: CoreListSelector.typeFor(chosen, slot)` (exercise_selector.dart:869), which returns the slot's type
  when the row lists neither compound nor isolation (E143 is `calisthenics`), so the Squat Day's Quads compound slot
  makes it `compound` and `SequencingEngine` orders it as one. The audit's `iso_first` classifier
  (`plan_audit_lib.dart:99-100, 301-304`) reads the library row's type instead. Fix in this batch: the audit dump records each
  row's BUILT type (`PlannedExercise.exerciseType` after `typeOverride`, per row, not the per-name header map) and the
  classifier reads it; measured in Task 5; expected 12 -> 0. `test/plan_generator/plan_audit/plan_audit_lib_test.dart:132`
  (a CI test of the library-type classifier) moves to the built-type field with a case where the two disagree
  (E143: library `calisthenics`, built `compound`; round 12, seat A).
  OI-485's "a high-impact row ranks below a strength row" clause: 0 jump rows ON for uninjured users (the audit),
  measured; for injured users the 15-pair grid held 3,189 jump-led day-weeks ON (541 live), all hip pairs, closed by
  Ruling 12 (d19); `closed_in_commit` once Task 5 measures 0 on the final tree.
- The parent's last flip criterion, the founder's call on promoted and injured thin sessions (D6 gaps, parent R6 /
  R7, `docs/ship_dark_pending_review.yaml:285`), is answered: founder d9 / d11 (2026-11-08, closure `S1A-R7-GAPS`:
  household rows at intermediate / advanced for Biceps and Lateral / Rear Delts, Lower Chest as is), d12 (2026-11-09,
  `S1A-FRONT-DELTS`: the bodyweight Front Delts gap accepted), and the injured thin days (`SBF-THIN-DAYS`, the founder's
  call on the session budget's thin days). The `resolved:` note cites them.
- OI-436's sweep `emergencyAnyLevel` runs: 16 in the gate's 576 (build_muscle, phases 1-2), 86 in the 3,456-run grid
  of Ruling 3, every one a bodyweight shoulder + wrist user (the d13 persona); in the wider round-7 blocks 151 (pairs at
  phases 2-3), 76 (pairs repeat), 602 (bodyweight triples) and 172 (pairs x exclude-everything), not only that pair. The
  closure states it as a class with counts per block (an injured bodyweight user whose slot has no core row at their
  level takes a core row of any level; its "Done when"), not run by run.
- Minor-muscle zero weeks against live (prototype H; E's and G's figures are the same): ON plans with a minor muscle at 0 in a week where the live
  twin has sets: Triceps 308 cells / 86 plans, Core 132 / 52, Biceps 116 / 36, Calves 18 / 9. Main ON has them too
  (Biceps 124 / 38 there): this unit creates none (0 zero cells newly vs live) and heals few. H's (and E's and G's) residue is LARGER than
  prototype D's, whose counts the founder was shown when d14 was asked (Triceps 62, Core 42, Biceps 21 plans): guard
  (b) keeps the major-group holds D evicted for arm work. The founder was told in chat on 2026-11-10 and the board's
  d14 carries these counts; the merge report repeats them.
  Writer: `SessionSetAllocator._variant` pass A (`// 3. Pass A`): the count band (`seated[d] >= target[d]`), the clock
  refusal, and Ruling 5's guards. Reader: the week's per-muscle sets (the periodized plan the user trains; the audit
  dump's `v`). Measured with a temporary print in prototypes E and G over the 2,304 ON plans (not committed; the same table on both,
  and the probe agrees with the audit dumps on every cell); each residue
  cell is classed by the refused slots that credit its muscle in that variant (a copied B day takes A's reason):

  | cause | Triceps | Core | Biceps | Calves |
  |---|---|---|---|---|
  | no hold on the slot's day: the clock alone (16 Triceps cells also a session cap) | 128 | 60 | 0 | 18 |
  | a hold ranked AHEAD of the slot in the split's order (`t.before <= r`), alone or with guard (b) | 160 | 64 | 20 | 0 |
  | guard (a) only-credit, or (a) with (b) / rank (the hold is the day's only credit for its own group) | 20 | 8 | 18 | 0 |
  | the count band refused the slot while a later hold sat on the day | 0 | 0 | 78 | 0 |

  None is OI-489's defect (a hold ranked AFTER a slot taking its time first): a hold ranked ahead is the split's own
  priority; guards (a) and (b) are measured trades (prototypes B and D3: Back -639, Shoulders -594 set-weeks for arm
  work); the count path was measured as prototype F (Ruling 5) and heals none of these cells. What the residue needs is
  a weekly minimum per muscle that outranks a day's rank order, which is step 2's weekly floor, the owner under d14 on a
  minted OI. OI-489's own "Done when" is read on major muscles, as the parent plan's flip row is (section 1), and its
  board text is edited to say "major" when it closes.
- Between this unit and Unit 1B-F2 the picker reads the overlay labels and `queryV4` (the top-up's non-core ladder)
  the old ones on 13 / 19 rows: the mixed-label state 1B-F2 removes. Nothing in 1B-F needs the copy; Task 5's sweeps
  measure the injured users who reach that ladder.
- OI-148: its selection-skew blocker is answered by the same-movement rule (S1b-2); 9 versions shipped, the 3
  weighted rows wait on Batch D (d11), and the other 11 of the 23 were not in d10's approved list. Its board text is
  refreshed to say so; it stays open for those 11.

## 5. Tasks

1. Allocator (Ruling 5), then record the golden personas' ON-world hashes before the flip (Ruling 11), with tests: a starved slot that brings the day's first credit for a group seats after a
   later hold gives way (a rank-0 lead; a priority-1 hinge); a slot whose groups the day already credits never
   evicts; a major-group hold never gives way to a minor-only new credit; a hold that is the day's only credit for a
   group never gives way; a day holding the same hold twice; no eviction when the slot still would
   not fit, and the fit boundary at equality; no second eviction under the count floor; a custom, a non-library row
   and a cardio / distance row never give way; a copied B day mirrors A; a single-day fixture with no starved slot is
   unchanged; a pinned library hold follows the rule. Mutations: the first-credit condition, the week term
   (`ledger.week(g) == 0`), the kept-holds term, the `t.before > r` guard, the only-credit guard, the decide-before-mutate check, the tolerance, the floor guard, the timed-only
   filter, the copy mirror, the custom guard, the count-seat bookkeeping, the last-first order, the output filter.
   Also: a hold whose group the incoming slot also credits may give way (the `s.groups` term); the `reserved(k)` and
   caps-and-tops preconditions; a hold with no muscle groups; the kept-holds term of the first-credit test; a
   selector-thin day (3 slots + 1 hold at 30 minutes) keeps its floor and label. Round 5 additions: a slot refused by
   the count band never evicts (the count path, Ruling 5); the count seat an eviction frees seats a later slot (the
   `target[d]++` bookkeeping, observed through a day that reaches its count maximum only because of it); a hold
   ranked AFTER the slot gives way and the same hold ranked BEFORE it does not (every existing allocator fixture lists
   the plank first, so the `t.before > r` guard has no cover today); a day with no seated slot evicts a later hold
   to seat its lead inside the clock, where the empty-day guard would force it past (Ruling 5's Upper day). Round 6:
   the week term: the same starved slot does not evict when an earlier day already holds sets for its group in this
   variant, and does when that day's credit sits at a later rank (pass A's rank order); round 7: the same slot does not
   evict when a kept library timed row on another day of the variant credits its group (the kept-holds term); the incidental-credit case of
   guard (a) (a Core hold gives way to a compound whose primary muscles include Core); rounds 9-10: guard (e), with Core a focus
group the same Core hold does NOT give way to a minor-only slot, DOES give way to a slot that brings the week a major group
it lacks, and a non-focus hold on that day still gives way to a minor slot (mutants: the focus clause removed; the
`!bringsMajor` term dropped, which is H2; `focusGroups` read from the slot instead of the hold; `bringsMajor` read from
`s.groups` instead of `newGroups`, red on a fixture whose slot's major group the week already holds while its new
credit is minor-only; `t.groups.any` turned into `every`, red on a focus hold that also credits a non-focus group;
round 11), and a rank-0 lead on the first day evicts a later focus hold (the guards read the week so far). The focus
   fixture ranks the focus hold LAST in its day (eviction scans last-first) with a non-focus evictable hold ranked
   before it, so a `continue` -> `break` mutant in guard (e) or (b) reddens (rounds 12-13; the real-engine pin below
   reddens only for H2, since H also heals that Chest, so guard (e) deleted outright is caught by this fixture and the
   env-gated grid). The "never evicted" fixture uses `logging_type` `cardio` and `distance` rows. And the OI-489 pin on the real
   engine (its "Done when"): `build_muscle|3|advanced|bodyweight|30|2` and `|3` hold Chest sets in weeks 2 and 4, and
   `lose_fat` / `general_fitness` `|3|advanced|bodyweight|30|1` hold Hamstrings sets in weeks 1-4, red without Ruling 5
   (mutated per rule 21); plus one real-engine focus pin in CI (round 12, seat B: the focus grid is env-gated):
   `build_muscle|3|advanced|bodyweight|30|2` with body focus Core holds Chest sets in weeks 2 and 4, red with H2's
   guard (e) (`!bringsMajor` dropped).
2. Flip and delete (Rulings 1-4, 7), with the unused `dart:math` import the V3 `pick` deletion leaves removed (an
   analyzer warning aborts pre-push); `test/_probe/` deleted first; code first, then every test in the inventory's sections 2.1-2.3 (2.3's 21
   OLD-implicit files run once on the flipped tree; a pinned number that moves is re-derived and explained). Also run
   once, named: `coach_regen_phase_stamp_behavioral_test.dart`, `oi166_unit2_regen_content_cycling_behavioral_test.dart`,
   `oi189_plan_end_bound_behavioral_test.dart`, `pro_phase_advance_behavioral_test.dart`,
   `pro_phase_ensure_current_behavioral_test.dart`, `lapse_gap_freeze_reset_advance_test.dart`,
   `lapse_gap_policy_behavioral_test.dart`, `l2_repeat_pins_strip_test.dart`, `repeat_content_scheduling_test.dart`
   (round 13: it generates fresh phases on the real library through `generateAndSchedule`) (each generates from the real library JSON
   and is in no inventory list); the allocator's own callers `exercise_count_band_behavioral_test.dart`,
   `quads_floor_6day_behavioral_test.dart`, `session_set_budget_consumers_test.dart`, `rest_by_type_behavioral_test.dart`;
   and `plateau_rotation_behavioral_test.dart` (~205-235, "a day never loses a row", `rowsSeen` at :212, :218 and the
   exercise-count `delta inInclusiveRange(0, 1)` at ~:226-233: Ruling 5 can now change a day's row count, and `rowsSeen`
   must read the selector's rows before eviction in both variants). About 35 `thin_day_topup_behavioral_test.dart`
   cases call its `topUp` helper with the default `coreListOnly: false` against the real library; with the parameter
   gone they run core-first, so their pinned picks are re-derived and explained, not only :215-229 and the controls.
   Golden persona counts: `generator_golden_test.dart:168` (`expect(personas.length, 998)`) and :87 move with Ruling 4's
   new personas, as do the "998" comments in `core_list_pool_gate_test.dart` and `same_movement_day_gate_test.dart`;
   `equipment_exclusion_filter_behavioral_test.dart:225` ("exclude EVERYTHING ... >= 80% of baseline") is re-derived
   on the flipped tree. The golden test's new-row rules (`library_injury_floor.dart` `newRowPickViolations`, run in
   every `golden: <group>` test: (i) no picked new row is plyometric, high-impact or requires-coaching; (ii) floor,
   family and twin tokens) now run on ON picks; Task 2 runs them on the flipped tree before the golden is re-recorded
   and lists any violation with its row (round 12, seat A).
   The inventory's "every CI test that executes the OLD picker" sentence is dropped; the Task 6 full suite is the net.
2b. Hip-unsafe jump rows (Ruling 12, d19), before the golden is re-recorded: the red tests and fixtures first (the v25
   upgrade test, the fixture `library_hip_tags_v24.json`, the v23 / v24 helpers, the warm-up pins, an importer-stage test
   with mutants: the stage removed, a `before` mismatch accepted, the record ignored by `--check`), watched red; then the
   record and importer stage, the 5 E-rows, the 9 table rows rebuilt by the builder (G3582 included) and G3656 by hand, seed v25 (with the earlier upgrade tests repointed),
   `warmup_cooldown.dart`'s two entries, the frozen-reference re-record of the 5 ids; then importer `--check`, the builder's
   check and the injury coverage test green. Mutation per rule 21: one of the 14 rows' `hip` removed reddens the v25
   precondition, the coverage test (G-row) or the importer `--check` (E-row).
3. Mirrors (Ruling 7): persona-set comparison of scorecard vs core-list gate. `queryV4`: before `v4_diagnostic_test`
   is deleted, each rule `QueryV4Mirror` checks (the tier rule, `suitableFor`, the compound-first sort, the same-movement
   `excludeNames` partner) is matched to a real-`queryV4` test that covers it, from `same_movement_behavioral_test`,
   `equipment_owned_widens_test`, `injury_recheck_v14_contract_test`, `injury_safety_tags_v13_behavioral_test`,
   `library_label_typo_behavioral_test`, `exercise_alias_lookup_behavioral_test`; a rule with none gains a real-`queryV4`
   test in this unit (the top-up's ladder serves injured users).
4. Exclude-everything golden personas (Ruling 4) and the CI hard test over the 2,637 runs of Ruling 3 (the 1,077 and
   1,465 runs R6 refilled plus the 95 thin runs: eight files, four by goal per domain, one `test()` per tier) with the
   thin and one-exercise ratchets per file, and the env-gated
   `injured_grid_dump_test.dart` (46,512 runs, run in Task 5) and, beside it, `focus_grid_dump_test.dart` (the
   five-set focus grid of Ruling 5, 5,760 plans, skipped unless `FOCUS_GRID_OUT` is set; Task 5 runs it on the final tree
   and its dump must equal prototype H3's byte for byte (the closure records both files' sha256, since the prototype's
   dump is a scratchpad file), the only whole-grid check of guard (e), since
   the 2,304-plan audit has no focus and Task 1's CI focus pin covers one key; `FOCUS_GRID_OUT` is classified with `INJURED_GRID_OUT`), its new `INJURED_GRID_OUT` read classified as stripped
   beside `PLAN_AUDIT_OUT` in `test/contracts/spawn_env_manifest_test.dart:59` and `scripts/regression_catalog_lib.dart:112`
   (`spawn_env_manifest_test` scans `test/` and reds an unclassified read); the committed
   `test/plan_generator/core_list_pool_report.md` is regenerated on the final tree and committed (its OFF column and its
   576-run "refilled in 16" line die with the flag and R6), and its two citations, `docs/ship_dark_pending_review.yaml:330`
   and `docs/sot_registry.yaml:11698`, are edited to match; mutants for the floor sweep lib's new retired / skill / olympic
   assertion (a retired row injected into one built list reddens it) and for the exclude-everything personas' empty-day
   zero (one persona forced empty); the floor sweep lib re-recorded per Ruling 8 (three raised ceilings under d16 with
   their cause beside them, the rest downward) and given the one-exercise and retired / skill / olympic assertions.
5. Measure on the final tree: the audit (ON world vs main's OFF and ON), the core-list gate report, the injury floor
   sweep (Ruling 8, with the new `f_repeat_pairs30` block recorded under d23), the 15-pair grid against the live
   baseline at 30, 45 and 60 minutes, H3 against main's allocator at 30 minutes both ways with the Back-below-bottom
   count for injured 30-minute runs (Ruling 8's baseline), (Ruling 8's tables), the injured Push day (Ruling 6), `iso_first` (section 4), the count-refused slots (Ruling 5),
   the same-movement gate, the golden (Ruling 11), the cross-day measures (cells newly below live per muscle and depth,
   net set-weeks per muscle against main ON), and the minor-muscle residue per cause (section 4's table).
6. Before the commit: mint Unit 1B-F2 (`sh scripts/mint_oi.sh`, start condition "starts when 1B-F merges", its plan
   section 11 here) and the minor-muscle residue OI (d14, owner step 2's weekly floor); append the flip's measured thin
   and one-exercise days (Ruling 8's tables at 30, 45 and 60 minutes, d16 and d23, and the R6 extension's, d17) to OI-452; amend the parent plan's section
   9 to name 1B-F2 for items 1B-7 / 1B-11; grep the tree for every deleted name (Ruling 9) and for the prose "cascade",
   "OFF path" and "attempt" in surviving code (exercise_selector.dart ~765-772 (`_pickCoreList`'s doc: "only then the
   OFF cascade", "OFF L6 post-pass"), ~800, 973, 981, 992-1011 (`buildPinnedDays`' doc: "att-5 universal pool", the
   `applyInjuryUniversalFilter` kill switch), 1020, 1057, 1109, 1169, 1195-1197, 1335, 1347-1348, 1378: the
   `buildPinnedDays`, `topUpDays` and `_topUpVariant` docs), plus three comment-only hits outside the selector (round 14,
   seat A's P3-5), each reworded in place: `integration_test/flows/plan_generator_to_first_workout_test.dart`
   (`attempt3` / `universalPool` comments), `scripts/check_naming_conventions.dart:87` (the deleted
   `plan_generator/v4_diagnostic/` directory), `test/contracts/readiness_flag_no_hive_default_test.dart:7`
   (`generator_matrix.dart`); and the five statements of S1b-2's old demoted rule (Ruling 7's same_movement row, round
   17): `same_movement.dart:6`, `lib/shared/repositories/plan_engine/CLAUDE.md:66`, `exercise_selector.dart:1239`,
   `docs/sot_registry.yaml:11737` (concept `same_movement`'s description) and `docs/architecture/plan-engine-detail.md:324`
   (its "Demoted and plateau names stay per exercise" sentence), each saying a demoted original's loaded versions are
   demoted with it on the core path and the top-up. Then the full gate loop
   (§4.12.8), review rounds on the staged diff, B-pass, record, commit, PR, land; the board gets the founder's device
   check and Unit 1B-F2.

## 6. Acceptance

- 0 ON plans with a major muscle at 0 in weeks 1-3 where the live twin (main's OFF audit) has sets.
- 0 ON plans with a week of 0 Hamstrings sets (OI-485 (2); main ON 2, prototype H 0); OI-485 (2) closes on it.
- The focus grid (Ruling 5) equal to H3's dump; its costs as stated there (Core focus -46 set-weeks in 6 plans for the
  four healed Chest zero week-cells; every other focus set no plan lower).
- 0 zero cells (any of 10 muscles, any week) that main's ON world does not already have; the minor-muscle residue
  against live at most section 4's named counts, under the founder's d14 (section 10).
- The cells newly below live (Ruling 5's table: 2 in 1 plan for prototype H), the deepened cells (H 0) and the worse
  plans (H 0) re-measured on the final tree and named per muscle and depth in the closure; a rise above the
  prototype's count is explained or fixed.
- 0 empty days in the audit, the golden personas (the 48 exclude-everything runs measured 0 empty, 0 thin, 0
  one-exercise, 0 `emergencyAnyLevel`), the injury floor sweep, the CI hard test and the env-gated grid; no retired (gate definition),
  skill or olympic id in any built list; thin and one-exercise days at most Ruling 8's measured counts (`a_pairs` 20 / 30
  / 20 thin and 2 / 2 / 0 one-exercise, every other block 0; the hard test's per-file ratchets, the round-10 extension's
  at most its no-R6 measurement: 182 thin and 6 one-exercise day-weeks, the 6 the all-9 Legs + Core day of Ruling 3), under d16 and d17.
- `emergencyAnyLevel` 0 over the golden personas.
- 0 jump rows (high impact or plyometric) in any hip-injured run of the 15-pair grid, the floor sweep, the CI hard test and
  the env-gated grid (Ruling 12): none of the 14 tagged ids (the 4 upper-body plyometric rows stay allowed and are not
  counted; 0 of them in the 15-pair grid in any world); the CI hard test files assert it per run and Task 5 confirms it
  on the 14-row tree.
- Every deleted test has its row in Ruling 7's table.
- The OI-489 real-engine pin (Task 1) green on the final tree, red with Ruling 5 reverted.
- Costs named per plan, every muscle, every week.
- Runtime: the founder's device check of a generated plan after the build of 1B-F's merge, before 1B-F2 lands, so it
  covers the mixed-label state testers will run in that window; 1B-F2's own plan carries a second check (CLAUDE.md
  §5 row; §4.6 step 3), on the
  board as a task before the merge is reported done.

## 7. Closure

Ledger `docs/audit/generator-step1-1bf.closure.yaml`, every entry with its terminal state named here: one entry per item
1B-1 to 1B-12 and d13 (`closed_in_commit` unless stated); OI-436, OI-485 (three
clauses), OI-489 (closed on majors, with the reading stated; its board text's "weeks 1 to 3" Hamstrings and "week 2"
Chest are corrected to the measured weeks 1-4 and weeks 2 and 4, and its first hypothesis, the Single Leg Glute Bridge
`target()` filter, is recorded as superseded by section 2); OI-436 (`closed_in_commit`; its "Done when" asks for a
record per remaining persona, read here as a class with counts per block, section 4, because the wider blocks hold
about a thousand runs and the round-10 extension another 1,465; the run keys are in the hard test's fixture, Ruling 3;
its board text gains the same note as OI-489's: "read as a class, counts per block, run keys in the eight
`r6_removed_runs_*` fixtures"); 1B-8 / OI-148 (the 3 weighted rows `upstream_blocked` on Batch D's plan; the other 11 of
the 23 `blocked_on_user`, reason: d10's approved list did not include them, so adding them is the founder's pick); the minor-muscle zero cells per cause (`upstream_blocked`, blocker the minted residue OI, `reopen_when`: step 2's weekly
floor, under d14); the injured thin and one-exercise days (Ruling 8's table, `upstream_blocked`, blocker OI-452,
`reopen_when`: OI-452's plan lands, under d16; the R6 extension's 182 thin and 6 one-exercise day-weeks
named beside Ruling 8's table, under d17);
the Ruling 5 costs (below-live and deepened cells, per-plan major shortfall, net set-weeks; `closed_in_commit` with the
measured figures as the accepted trade); approved community rows (`source: community`, no `core_levels`) leave generation with the cascade (the core path
never picks them, `core_list_pool_behavioral_test.dart` "community and custom rows never selected"; a product change of
the flip, `closed_in_commit` with that note); the stale-library case (Ruling 3, `upstream_blocked`,
store launch); `plan_generator.dart`'s stale comments (Ruling 9; `closed_in_commit` under d18 and d21); 1B-7 and 1B-11 `upstream_blocked` on Unit
1B-F2, a separate unit with its own minted board entry (start condition: 1B-F merged), split under §4.12.1 because three review rounds kept finding overlay
pins; its plan starts right after the 1B-F merge, and nothing in 1B-F needs the copy (the picker reads the overlay
labels, the mixed-label state is stated in section 4) (blocker: Unit 1B-F2's minted entry, whose own cloud
migration then waits on the founder's live-apply go; `reopen_when`: 1B-F merged; the split is the recorded §4.12.1
process decision of round 3, section 9), with 1B-F2 minted on the board and the parent plan's section 9
amended to name it. That entry's state says in its own words that it is a process split under §4.12.1 into
this unit's sibling, names the minted 1B-F2 OI, and the `enable_core_list_pool` `resolved:` note records that the flip
commit does NOT copy the overlay although B1 Ruling 4 said it would (Ruling 9).

## 8. Diagnose

`docs/diagnoses/2026-11-12-generator-1bf-timed-hold-clock-39eb2a.md` for OI-489 (Ruling 5), Ruling 5c and Ruling 12:
writer `SessionSetAllocator._variant` (step 1, the holds' time; `evictFor`), reader pass A and the empty-day guard,
contract test `test/contracts/allocator_timed_hold_eviction_behavioral_test.dart` (the name the build used), SoT
registry concept `session_set_budget`.

## 9. Review log

**Round 1 (2 Sonnet seats on v1, context-blind; 0 P0, 1 P1, 7 P2, 15 P3; not converged).** Folded into v2:
- P1 (seat A): the injury floor sweep (20 blocks, 9 injuries, 4 goals, repeat phase) was missing from the R6 evidence
  and the tasks, and its exact `kThinCeilings` ratchet will move. Ruling 8 added.
- P2 (seat A): the multi-injury sweep is report-only, not a gate. Ruling 3 now says which gate holds what.
- P2 (seat A): the OLD-explicit tests had no dispositions. Ruling 7's table added.
- P2 (seat A): item 1B-7 dropped B1's Ruling 4 copy without a ruling. Ruling 10 restores it, with the migration.
- P2 (seat B): prototype B let any later hold give way to any slot: 331 cells in 98 plans fell below live (Shoulders
  154, Back 74), and Pull days traded Back holds for curls. Re-designed (compound-only evictor, only-credit guard)
  and re-measured as prototype C: 152 cells in 57 plans, 0 new zero cells.
- P2 (seat B): evictions were not rolled back and could over-evict. Prototype C decides before it changes anything.
- P2 (seat B): OI-489's literal "Done when" (any muscle) was narrowed silently. Section 4 states the reading and
  files the minor zeros.
- P2 (seat B): OI-485 (3) `iso_first`, the same-28 major-zero plans and OI-485 (2) 2 -> 0 were missing. Added.
- P2 (seat B): pinned library holds and unmeasured worlds. Ruling 5 states the pinned rule; Task 1 tests it; Ruling
  8's sweep measures injured users and the repeat phase.
- P3s folded: the definite `plan_generator.dart` edit (Ruling 1); `queryV4` mirror protection (Ruling 7); the top-up
  kill switch default (Ruling 3); OI-436 emergency runs (section 4); `_universalPool` source reader (Ruling 2, 7);
  count-refused slots and cross-day coupling (Ruling 5); the verdict header order (section 1); prototype A compared
  like with like (Ruling 5 table); the mutation list (Task 1); OI-148 carried with its blocker (section 4).

**Round 2 (2 Sonnet seats on v2, context-blind; 0 P0, 0 P1, 6 P2, 22 P3; not converged).** Every round-1 answer was
verified real in code or data. Folded into v3:
- P2 (seat B): the "compound-only evictor" was an archetype gate, and archetype M includes calisthenics: Bench Dips
  (typed compound and calisthenics), Tricep Dips Floor and Kneeling Tricep Extension evicted lateral raises. P2 (seat
  B): the only-credit guard protects presence, not amount (lose_fat Full Body A Core 16 -> 8). The rule kept drawing
  P2s, so it was narrowed to the defect itself (a slot that would give the day its FIRST credit for a group) and
  re-measured as prototype D: 111 ON plans changed, 0 new zero cells, Core -25 (C: -375).
- P2 (seat A): the overlay pins and writers (8 files plus 2 scripts' data) had no disposition. Ruling 10's table.
- P2 (seat A): the `iso_first` mechanism was wrong (E143 is built `compound` by `typeFor`; the audit classifier reads
  the library type). Section 4 states the mechanism and fixes the classifier in this batch.
- P2 (seat A): the acceptance read absolutely and contradicted the carried residue. Section 6 rewritten; the
  residue is a founder question (section 10).
- P2 (seat A): the D6 thin-session flip criterion was missing. Section 4 cites the founder's d9 / d11 / d12 and
  `SBF-THIN-DAYS`.
- P3s folded: the injury-substitute kill switch stays (answered); `_muscleTokens` kept; Ruling 3's stop clause; the
  sweep's skill / olympic assertion and the retired-row count; the att5 floor's replacement; the two missing test
  files; the context budget; v12 -> v13; the hold-count buckets; prototype A 773 -> 673; the count floor, tolerance
  and timed-only guards in the rule; the count-band threshold; the runtime check; OI-489's board wording.
- Not changed: seat A's P3-9 (rule-14 authority for the two `plan_generator.dart` call sites) is asked in section 10.

**Round 3 (2 Sonnet seats on v3, context-blind; 0 P0, 0 P1, 5 P2, 15 P3; not converged).** Every round-2 answer was
verified real; every number in Ruling 5's table reproduced. Seat B's verdict: the design (prototype D) holds. Folded
into v4:
- P2 (seat B): guard (c) checked only a second eviction, so a selector-thin day (3 slots + 1 hold at 30 minutes) could
  end under the floor, mislabelled `selectorThin`. Fixed as prototype D3 (reach after eviction; the floor and the
  label read the pre-eviction reach). A first attempt (D2: rows seated so far) over-corrected and undid the OI-489 chest
  fix (2 plans worse than live again), so the guard reads reach, not seated rows. D3's dumps equal D's.
- P2 (seat B): OI-489's "Done when" asks for a test pinning the four keys in the ON world. Added to Task 1.
- P2 (seat A): the floor sweep's pair blocks are phase 1 only, so "the floor sweep covers a wider set" was false at
  phase 2. Ruling 3: the 576-run sweep becomes a hard empty-day test.
- P2 (seat A, two findings): three more tests break on the overlay copy (the frozen-reference hashes, the v13 tag
  control E127, the N19 / E048 comparison). The overlay copy kept surfacing missed pins in every round, it is
  separable (data plus its own live migration), so it is split out as Unit 1B-F2 under §4.12.1; its pins table, with
  these three rows, is in section 11.
- P3s folded: `iso_first` OFF is 4, not 0; the inverted row label; the trade's major / minor set-weeks and the rows
  gained; the extra Task 1 tests; identity and duplicate-name robustness and `rowsSeen`; the exclude-everything
  personas (att5's extreme); `refilled` and `hasCoreFields` removals named; the retired-id reading in the `resolved:`
  note; three doc and two gitignore-list mentions; user-swapped holds accepted; §4.6 step 3 pre-launch; the seed runs
  before `runApp`.

**Round 4 (2 Sonnet seats on v4, context-blind; 0 P0, 0 P1, 2 P2, 16 P3; not converged).** Every round-3 answer was
verified real; D3's dumps equal D's; every number reproduced. Folded into v5:
- P2 (seat B): D3 makes the trade the plan cites to reject B (Back holds for curls: D3 Back -639, Shoulders -594
  set-weeks), and no founder decision covers it. Guard (b), majors over minors, added and measured as prototype E:
  51 ON plans changed, 24 cells below live in 9 plans (D3: 179 in 56), net majors +195.
- P2 (seat A): "the seed runs before `runApp`" was false. Ruling 3 states the stale-library case and parks it for
  store launch (CLAUDE.md §1).
- P3s folded: what Ruling 5 fixes (the missing muscle, not the starved lead); "no day's minutes grow" corrected; the
  prototype's identity and name keys versus the final code (dumps must equal E's); the pass-A line cite; the split's
  board owner and the mixed-label state; the vacuous exclusion fixture; the v4 diagnostic output entries kept; the
  scorecard's four pins mapped; the ceiling re-recorded downward only; the attribution baseline scheduled; citations by
  symbol; the built type in the audit dump; `dart:math` and the probe; OI-148's other 11.

**Round 5 (2 Sonnet seats on v5, context-blind; 0 P0, 0 P1, 2 P2, 14 P3; seat A converged, seat B not).** Every
round-4 answer was verified real; every number in sections 1, 2 and Ruling 5's table reproduced. Folded into v6:
- P2 (seat B): the minor-muscle residue had no writer or reader, and its cells sat in hold weeks far above the base
  rate. Measured with a temporary print in prototype E: section 4's cause table; no cell is OI-489's defect; step 2's
  weekly floor named as the owner with the reason. E's residue stated as larger than D's (the counts d14 was asked
  with), and the founder told.
- P2 (seat B): the count-refused case was left for Task 5 with a zero-tolerance stop. Measured now (397 slots in 190
  plans); prototype F (the same eviction on the count path) measured and rejected (Ruling 5); Task 5 re-measures.
- P3s folded: eviction versus the empty-day guard (Ruling 5, Task 1); the count-path, `target[d]++` and
  hold-ranked-after tests and `plateau_rotation_behavioral_test` (Tasks 1, 2); cross-day measures in Task 5; the three
  rising issue codes named and owned (section 1); "4 plans"; the 1B-F2 closure wording (section 7); the three
  real-library tests in no list (Task 2); `buildPinnedDays` losing the parameter (Ruling 1); stale flag and cascade
  comments (Ruling 9); two line cites (Ruling 3); the `queryV4` rule-to-test map (Task 3); OI-485 (2) as an acceptance
  line (section 6); the device check's timing against 1B-F2 (section 6).

**Round 6 (2 Sonnet seats on v6, context-blind; 0 P0, 0 P1, 2 P2, 16 P3; neither converged).** Every round-5 answer
was verified real; the cause table, the count-refused figures and prototype F reproduce from the probe files. Folded
into v7:
- P2 (seat B): Ruling 5's cost left out cells already below live that E lowered further (68 in 20 plans; 14 changed
  plans worse on summed major shortfall; 43 of 51 changed plans healed nothing): the first-credit test read the day,
  not the week. Prototype G adds the week term (`ledger.week(g) == 0`) and is the ruling: 14 ON plans changed, 0
  deepened cells, 0 worse plans, 2 cells newly below live in 1 plan, the same healed cells plus Calves 2, main's OFF
  world unchanged. The deepened-cell and worse-plan measures join the table, section 6 and Task 5 for every prototype.
- P2 (seat A): the injured-pair empty-day evidence covered build_muscle at phases 1-2 only. Measured before any code
  over every goal, tier, level, day count, phases 1-3 and the 6 pairs (3,456 runs) with and without R6: 0 empty, 0
  one-exercise, 0 under-3 days and 0 retired ids without R6 (Ruling 3); the hard test covers that grid, four files.
- P3s folded: F's reason (guard (b) keeps Back holds; the count path measured only with (b)); the Upper-day sentences
  (week 4 minutes; the Core credit is Hindu Pushup's own); the documents Ruling 5's reversal of "a timed row is never
  removed" touches (Ruling 9); "day-weeks"; terminal states for every closure entry and 1B-F2 minted with a start
  condition (section 7, Task 6); symbol cites and the `exercise_selector.dart` probe switch reverted;
  the dump baseline regenerated, not committed (Ruling 7); the registry swept by shape (Ruling 9); d13's second
  sentence cited; `core_list_pool_behavioral_test.dart:539`; the mirror family's orphans and the dropped data-sanity
  check (Ruling 7); the retired-id criterion's real source, held as a hard zero (Ruling 8); the stale-comment list
  (Ruling 9); the R6 dry run done before code (Ruling 3); the probe figures labelled as such and re-measured in Task 5.

**Round 7 (2 Sonnet seats on v7, context-blind; 0 P0, 0 P1, 2 P2, 11 P3; neither converged).** Every round-6 answer
was verified real; the section 1 table, G's column, the residue cause table and the R6 dry run reproduce. Folded into
v8:
- P2 (seat B): G's week term ignored holds (a not-budgeted row enters the ledger with no group), so G traded a Core hold
  for a group a kept hold on another day already credited (5 of its 14 changed plans healed nothing: 2 the designed Upper-day case, 3 such trades). Prototype H adds
  "no kept library timed row on any day credits it": 12 ON plans changed, 9 heal, 0 deepened, 0 worse (Ruling 5); the
  hold-elsewhere test joins Task 1.
- P2 (seat A): the R6 dry run's grid had 4 injuries, so elbow and hip pairs, phases 2-3 for them, triples, injured
  exclude-everything and injured pairs in the repeat were unmeasured. Measured before code over all of them plus the 20
  floor-sweep blocks ON (seat A's P3 on the hard zero): Ruling 3's stop fired. The one-exercise days (shoulder + elbow
  Upper day; the pre-existing repeat Full Body D) got a writer, a reader and a rule (Ruling 5b, prototype J, audit
  byte-identical to H); the thin-day rise got its writer and reader (Ruling 8) and the founder's d16. The hard test grid
  is now the 15 pairs over phases 1-3 and the repeat (11,520 runs) with a thin-day ratchet.
- P3s folded: the targetcount test's first test kept (Ruling 7); `injury_substitutes.dart:5` (Ruling 9); the V3 helpers
  named (Ruling 2); `pickV4` delegates to `_pickCoreList` (Ruling 1); concept `universal_pool_fallback` removed whole
  (Ruling 9); the thin_day_topup OFF controls at 983-987 and 1055-1073 (Ruling 7); the churn count beside "9 of 14";
  Standing Towel Pull Apart relabelled a slot, not a hold; F's OFF count 49 and its blank cells; the prototype-to-final
  differences (doc comment, (name, occurrence) replay, `rowsSeen`) in Tasks 1-2; the review loop's allocator
  concentration (seat B advised freezing after H; Ruling 5b is a separate pass found by the sweep, not a change to the
  eviction rule).

**Round 8 (2 Sonnet seats on v8, context-blind; 0 P0, 0 P1, 5 P2, 10 P3; neither converged).** Every round-7 answer
and every number in sections 1-2, Ruling 5's table and Ruling 8's first figures reproduced. Folded into v9:
- P2 (both seats): d16 covered only the phase-1 pair block, while the plan's own grid showed rises at phase 3 and in the
  repeat (shoulder + lower_back too), and 118 of the 187 thinner day-weeks were not retired-row cases. Measured the full
  live baseline (a detached worktree at ea37ed59, all 15 pairs, phases 1-3 and the repeat, 11,520 runs, weeks 1-2)
  against prototype H; named the writers and readers of the repeat and phase-3 cases (Ruling 8); re-asked d16 with the
  full numbers (section 10). Live -> H, thin 341 -> 352, one-exercise 8 -> 20 (only cells with a day-week either side):
  | pair | phase | tier | thin live -> H | one-exercise live -> H |
  |---|---|---|---|---|
  | knee+lower_back | repeat | basic_gym | 2 -> 0 | 0 -> 0 |
  | knee+lower_back | repeat | bodyweight | 13 -> 0 | 0 -> 0 |
  | knee+lower_back | repeat | full_gym | 2 -> 0 | 0 -> 0 |
  | knee+lower_back | repeat | home_dumbbells | 12 -> 4 | 0 -> 0 |
  | knee+shoulder | repeat | basic_gym | 0 -> 2 | 0 -> 0 |
  | knee+shoulder | repeat | home_dumbbells | 0 -> 2 | 0 -> 0 |
  | lower_back+elbow | repeat | basic_gym | 2 -> 2 | 0 -> 0 |
  | lower_back+elbow | repeat | bodyweight | 12 -> 0 | 0 -> 0 |
  | lower_back+elbow | repeat | full_gym | 2 -> 2 | 0 -> 0 |
  | lower_back+elbow | repeat | home_dumbbells | 2 -> 2 | 0 -> 0 |
  | lower_back+hip | repeat | basic_gym | 2 -> 0 | 0 -> 0 |
  | lower_back+hip | repeat | bodyweight | 13 -> 0 | 0 -> 0 |
  | lower_back+hip | repeat | full_gym | 2 -> 0 | 0 -> 0 |
  | lower_back+hip | repeat | home_dumbbells | 12 -> 4 | 0 -> 0 |
  | lower_back+wrist | repeat | bodyweight | 5 -> 0 | 0 -> 0 |
  | shoulder+elbow | 1 | basic_gym | 30 -> 30 | 0 -> 2 |
  | shoulder+elbow | 1 | full_gym | 18 -> 20 | 0 -> 0 |
  | shoulder+elbow | 1 | home_dumbbells | 22 -> 20 | 0 -> 2 |
  | shoulder+elbow | 2 | basic_gym | 30 -> 30 | 0 -> 2 |
  | shoulder+elbow | 2 | full_gym | 18 -> 20 | 0 -> 0 |
  | shoulder+elbow | 2 | home_dumbbells | 22 -> 20 | 0 -> 2 |
  | shoulder+elbow | 3 | basic_gym | 4 -> 18 | 0 -> 0 |
  | shoulder+elbow | 3 | full_gym | 4 -> 12 | 0 -> 0 |
  | shoulder+elbow | 3 | home_dumbbells | 12 -> 14 | 0 -> 0 |
  | shoulder+elbow | repeat | basic_gym | 31 -> 36 | 0 -> 2 |
  | shoulder+elbow | repeat | full_gym | 20 -> 25 | 0 -> 0 |
  | shoulder+elbow | repeat | home_dumbbells | 22 -> 25 | 0 -> 2 |
  | shoulder+hip | repeat | basic_gym | 0 -> 2 | 0 -> 0 |
  | shoulder+hip | repeat | home_dumbbells | 0 -> 2 | 0 -> 0 |
  | shoulder+lower_back | repeat | basic_gym | 2 -> 14 | 0 -> 0 |
  | shoulder+lower_back | repeat | bodyweight | 23 -> 26 | 8 -> 8 |
  | shoulder+lower_back | repeat | full_gym | 2 -> 0 | 0 -> 0 |
  | shoulder+lower_back | repeat | home_dumbbells | 0 -> 20 | 0 -> 0 |
- P2 (seat B): Ruling 5b's guard passes a weekly top that `session_set_budget_gate_test` and two seeded sweeps assert.
  Ran them on J: three reds in `session_set_allocator_behavioral_test.dart` (the uninjured seeded sweep among them), the
  same failure as OI-452's reverted first attempt. J rejected (Ruling 5b); the allocator is H; the days go to OI-452.
- P2 (seat A): the 11,520-run hard test was not costed against CI. Re-cut (phase 1 is the floor sweep's), split into 10
  files with one `test()` per tier, the shard arithmetic stated (Ruling 3).
- P2 (seat A): nothing kept a guard where R6 fired most (bodyweight triples 602 runs, injured exclude-everything 172).
  Both join the hard test as build_muscle slices (Ruling 3); the top-up kill switch's reach stated.
- P2 (seat A): the hard test's thin ratchet had no live baseline. It now has one (the table above).
- P3s folded: six dead private members and the seam count 7 (Ruling 2, Ruling 9); more stale comments (Ruling 9); the
  retired-row definition is the gate's (10 rows), not `core_levels: []` (Rulings 3, 8); the exclude-everything personas
  measured (48 runs: 0 empty, 0 thin, 0 one-exercise, 0 `emergencyAnyLevel`; section 6); the c2 name-readers mutation
  test's base set (Ruling 7); OI-436 closed as a class with counts per block (section 4); "gains" -> "keeps" for the
  gate's empty-day zero (Ruling 3); J's wording, its stats copy and its "16 day-weeks" are moot with J rejected; G's
  non-healing count (5 of 14) and the minutes maxima label corrected; guard (d)'s limit stated (Ruling 5).

**Round 9 (2 Sonnet seats on v9, context-blind; 0 P0, 0 P1, 3 P2, 16 P3; neither converged).** Every round-8 answer
reproduced (the 33-cell live-vs-H table, the attribution, the retired definition, the seam count 7, the dead members,
the exclude-everything personas, J's gate log and the OI-452 history). Folded into v10:
- P2 (seat B): the eviction rule never read the user's focus muscles. Measured on a 2,304-plan focus grid (Core or
  Chest focus) against main's allocator: H lowered the focus group in 11 plans (-85 set-weeks). Prototype H2 adds guard
  (e), a focus-group hold never gives way: +14, 0 plans lower; the 2,304-plan audit is byte-identical to H (re-run).
- P2 (seat A): the R6-heavy slices covered one goal and the quoted R6 counts were four-goal figures; P2 (seat A): the
  CI cost assumed 0.13 s per run and a balanced shard deal. Measured CI's real per-run cost from the sweep files'
  spans (0.2-0.6 s), recorded the exact 1,077 runs R6 refills over a 19,584-run domain (every goal and phase), made those
  the CI hard test (four files) and the whole domain an env-gated measurement for Task 5; the shard loads are computed
  in Task 6.
- P3s folded: Ruling 5's share of the thin days (main's allocator with the flag on gives the same row count on all
  103,680 day-weeks); the "+ Core" days that lose a dedicated core row (16 day-weeks, named); the A/B ledger asymmetry;
  the J gate wording; the CI layout claim (moot after the re-cut); "172 of the 397 slots"; the `_variant` cite; the
  header version; `_pickCoreList`'s parameter; OI-489's board weeks and superseded hypothesis; the gate's `refilled`
  readers at :354 / :550; ten more real-library and allocator tests in Task 2 with the plateau `delta` assertion; the
  golden persona counts and the exclude-everything 80% test; the closure states (OI-148's 11 and the stale
  `plan_generator.dart` comments `blocked_on_user` (superseded by d18), OI-436 read as a class); the prose sweep words; single injuries
  (monotone pools, stated); the unguarded generate callers and the empty-box behaviour; the community-row cite; the
  `topUp` helper's real-library cases.

**Round 10 (2 Sonnet seats on v10, context-blind; 0 P0, 0 P1, 2 P2, 12 P3; neither converged).** Every round-9 answer
reproduced (H2's audit byte-identical to H, the focus grid, the 1,077 R6 keys, the CI per-run cost from the shard logs,
main-ON's equal row counts on the 103,680 day-weeks). Folded into v11:
- P2 (seat B): guard (e) as H2 wrote it ("a focus hold never gives way") also blocks a slot that brings the week a
  major group it lacks, so a Core-focus user keeps 4 major zero cells (the OI-489 Chest zero) that H heals. Measured over five focus sets
  (Core, Chest, Biceps, physique lower, physique upper; `focus5_dump_*`, 5,760 plans each) against main: H3 lets a
  focus hold give way only to a slot whose new credit includes a major group (majors, then focus, then the other
  minors). H3 heals the 4 zero cells (Core focus: -46 focus set-weeks in 6 plans, where H costs -95 in 11), and on
  the other four sets equals H2 (+10 / +28 / +40 / +52, 0 plans lower). The audit has no focus, so H3 equals H there.
  The allocator is H3 (Ruling 5's guard (e) and focus table, Task 1's tests, Task 4's env-gated
  `focus_grid_dump_test.dart` that must equal H3's dump byte for byte, section 6).
- P2 (seat A): the R6 domain held only the 6 floor-sweep injuries in pairs, bodyweight triples and the 9-injury
  pairs x exclude-everything, so R6's reach for equipment triples, quads, ankle / neck / hamstring pairs and all 9
  injuries was unmeasured. Measured (`r6_ext`, 26,928 runs): R6 fires in 1,465; without R6 they hold 0 empty days, 182
  thin and 6 one-exercise day-weeks (with R6 0 / 700 / 0). The 6 are the all-9 bodyweight Legs + Core day, with their
  writer and reader named (Ruling 3: retired E261 leaves the Push and Pull days, Bird Dog takes them and spends the
  Glutes weekly top before day 6) and the same counts on main's allocator; they ship under d16 on OI-452 (section 10; superseded by d17).
  The 1,465 runs join the CI hard test (four more files, 2,637 runs, 9-26 minutes) and the env-gated grid grows to
  46,512 runs (Ruling 3, Task 4, section 6).
- P3s folded (seat A): `INJURED_GRID_OUT` / `FOCUS_GRID_OUT` classified in `spawn_env_manifest_test.dart:59` and
  `regression_catalog_lib.dart:112`; `core_list_pool_report.md` regenerated with its two citations; the hard test's
  mutants; its `@Timeout` and `library;`; the shard rename rule; the 95 thin runs at phases 2-3 and the repeat; the
  hotel planner reaches `generate` through the facade at :62; Ruling 4's personas worded as measured 0; the 1B-F2
  split worded as a §4.12.1 process split.
- P3s folded (seat B): the dedicated-Core-row day-weeks are 32, named; `ab_swing` +2 measured as the two
  `build_muscle|3` healing plans; the audit table's H column labelled as equal to H3 on a no-focus audit; laggard
  focus (the only route to Core focus) worded in Ruling 5.

**Round 11 (2 Sonnet seats on v11, context-blind; 0 P0, 0 P1, 2 P2, 11 P3; seat A converged, seat B not).** Every
round-10 answer reproduced (H3's single changed condition, H3 = H on the no-focus audit, the five-set focus table, the
1,465 R6 extension runs and their counts, the all-9 mechanism from `all9_detail_*` and `all9_stats.log`, the 2,637 and
46,512 arithmetic). Folded into v12:
- P2 (seat B): H3's Core-focus cost was attributed wholly to the Chest heal; 38 of the 46 set-weeks heal nothing H2
  does not. Measured seat B's fix as prototype H4 (non-focus holds evicted first): Core cost -8, but 12 major
  week-cells go below main in 4 plans (Back and Shoulders, each already at or under its band bottom), so H4 is
  rejected and the cost is restated in three parts with what each buys (Ruling 5).
- P2 (seat B): v11 read the extension's one-exercise days as inside d16 and quoted only the falling thin total. The
  rise is stated per block (43 runs, +94 thin, +6 one-exercise, against -612 elsewhere) and asked as d17: ship
  (section 10).
- P3s folded (seat B): guards (b) and (e) do not protect a hold against a rank-0 lead on an early day (Ruling 5, a
  Task 1 fixture); two more guard mutants (`bringsMajor` from `s.groups`, `any` -> `every`); the `lead_starved` -6
  plans named.
- P3s folded (seat A): retired / skill / olympic ids measured over the extension without R6 (0) and the all-9 x
  exclude-everything cell measured (equal to all 9 on bodyweight run for run; Ruling 3); the 12 exclude-everything
  personas defined and the 48-run probe worded as their bound (Ruling 4); the CI files placed by current shard load
  and the 0.6 s figure labelled a margin (Ruling 3); d17 named in the closure and Task 6; OI-436's board note; the
  three `plan_generator.dart` comments rewritten under d18; four more stale-prose lines (Task 6); the community-row
  closure note; the monotone argument extended to every injury set via the measured all-9 cell (Ruling 3).

**Round 12 (2 Sonnet seats on v12, context-blind; 0 P0, 0 P1, 2 P2, 14 P3; seat B converged, seat A not).** Every
round-11 answer reproduced (H4's 12 major cells and its rejection, the per-block rise, the 0 flagged ids, the
all-9 x exclude-everything equality, the 2,637 / 46,512 arithmetic). Folded into v13:
- P2 (seat A): the flip leads hip-injured days with jump rows, 3,189 day-weeks against 541 live, while section 1 and
  section 4 measured jump rows only on the uninjured audit. Measured the data fix (jump rows tagged `hip`): 0 jump rows,
  no thin change. Asked as d19: in this flip. Ruling 12 (14 rows, no live step), Task 2b, the hard test's per-run
  assertion and an acceptance line; section 1's row and section 4's clause say "uninjured".
- P2 (seat A): "without lengthening CI" rested on one run's shard spread, which `test.yml:117-127` records as runner
  speed. Restated: two files per shard, +2.5-3 minutes per shard at the measured rate, the PR run's shard times in the
  closure, and a 25-minute trigger that moves the no-thin extension runs to the env-gated grid (Ruling 3).
- P3s folded (seat B): the Chest-heal part of H3's Core cost is -12, not -8; the zero-cell count excludes the 28
  persistent Shoulders-zero plans by name; the phase-1 focus plans are unreachable (Core -22 under H3 for a reachable
  user, against H4's -12 and 4 Shoulders cells below main); "never evicted" keyed on `logging_type`; the focus fixture's
  hold ranked last (a `continue` -> `break` mutant) and one real-engine focus pin in CI; d17's 2 triple runs named.
- P3s folded (seat A): `plan_generator.dart`'s other stale comments (d21) and `mainCascadeOverlapMoves` kept; the
  `iso_first` classifier test; the golden's new-row rules on ON picks; the two superseded log lines marked; the
  monotone argument's limit (the empty set); `_buildCustomExercise` kept; the rising audit flags asked as d20; the
  scorecard's `missing == 0` replacement labelled a weakening; OI-436's board note (already in v12).

**Round 13 (2 Sonnet seats on v13, context-blind; 0 P0, 0 P1, 4 P2, 13 P3; neither converged).** Every round-12 answer
reproduced (the 3,189 / 541 jump-led day-weeks, the 0 jump rows and unchanged thin counts with the tags, the v23 and
v24 digests, the shard arithmetic). Folded into v14:
- P2 (seat A): Ruling 12's touch list under-counted. G3582 is a ninth jump floor row that the builder's `--drop` rebuild
  must cover (`library_batch_c_injury_coverage_test.dart:583` rebuilds every non-judgement row); seed v25 reddens 14
  `as int, 24)` asserts, the 5 MIRROR tests (v20:107, v21:102, v22:89, v23:122, v24:106) and v16's `_currentVersion`.
  All listed in Ruling 12 and Task 2b, with the v23 / v24 helpers restoring the old tags from a fixture.
- P2 (seat B): d19 was asked with its benefit only. Its cost measured (bodyweight hip Quads median 5 -> 0, 1,518 of 1,920
  run-weeks with no quad work) with two alternatives; asked as d22: "d19 as decided".
- P2 (seat B): every injured measurement ran at the harness's 60-minute default. Re-measured at 30 and 45 minutes (Ruling
  8's session-length table, the R6 domain at 30 and 45 in Ruling 3): thin days at 30 minutes rise 427 -> 520 (the
  picker's, identical under main's allocator), 341 -> 344 at 45 minutes, one-exercise and empty days unchanged, R6's
  worse runs are d17's at both lengths; asked as d23: "Ship, OI-452 next".
  The sweep's `a_pairs` and `d_repeat` blocks gain 30-minute legs as the CI ratchet (superseded in round 14 by the
  `f_repeat_pairs30` block).
- P3s folded (both seats): `exercise_selector.dart:1232` (was :1235) and the coverage test :583 (was :569); the H3 Core
  arithmetic; Ruling 4's personas defined (12, build_muscle, 4 days, phase 1); the "28 plans" wording; the d18 / d21
  comment lines; `README.md:217`; `warmup_cooldown.dart:44,46` (Jumping Jacks and Jump Rope gain `hip`, the :26 count)
  and `warmup_injury_filter_behavioral_test.dart:167-170`; `naming_conventions` and `sot_registry` rows; the finisher gap
  left on OI-396.

**Round 14 (2 Sonnet seats on v14, context-blind; 0 P0, 0 P1, 5 P2, 6 P3; neither converged).** Every round-13 answer
reproduced (Ruling 12's touch list: G3582, the 14 `as int, 24)` asserts, the 5 MIRRORs, v16's const, the v24 digest;
the thin / one / empty counts per length; the R6 counts at 30 and 45). Folded into v15:
- P2 (seat B): the main-allocator 30-minute cell cited a file a crashed leg of another chain had overwritten (168 lines).
  Re-run to `pairs_dump_ON_main_m30_rerun.txt`: the same 520 thin day-weeks; Ruling 5 changes 1,713 other day-weeks
  at 30 minutes, none across the 3-exercise line (stated); the 60-minute main and H dumps are byte-identical (stated).
- P2 (seat B) and P3 (seat A): the mechanism sentence was wrong for 144 of the 332 (no "3 slots" at 30 minutes,
  `countFloor(30)` = 4): those are pinned repeat days whose pins come from a 30-minute uninjured plan without a core row,
  refused by the weekly top (traced, `rep30_trace.log`). Ruling 8 splits the 332 into 188 and 144 with writer and reader
  each; d23's record carries the correction, and the founder was told it with the same counts.
- P2 (seat B): the CI ratchet measured the wrong domain (`a_pairs` phase 1 has no length effect; the whole 30-minute rise
  is the pinned repeat over pairs). Replaced by the `f_repeat_pairs30` block (960 runs, beginner, 15 pairs).
- P2 (seat B): its CI cost unstated; stated (3.5-4.5 minutes, one file, Ruling 3's 25-minute shard rule).
- P2 (seat A): the flip drops S1b-2's "L6 with E147 demoted never substitutes N14" (only the OFF L6 gives it). A Ruling 7
  row for `same_movement_behavioral_test.dart`: tests 2, 4, 5 go with named homes, tests 6 and 7 run ON, and the core
  path widens the demoted set by a demoted original's loaded versions, one direction, with three mutants.
- P3s folded: d23's text caveat (seat B); the 45-minute R6 total per shard (seat B); both `runRepeat` calls take the
  length (seat A); Ruling 12's reviewed-and-left rows (seat A); three comment-only files in Task 6's grep list (seat A).

**Round 15 (2 Sonnet seats on v15, context-blind; 0 P0, 0 P1, 2 P2, 7 P3; neither converged).** Every round-14 answer
reproduced (the re-run's 520 and same thin set; the 188 / 144 split; the per-phase table; the 960 / 64 block arithmetic;
Ruling 12's scope rows; the three comment-only files). Folded into v16:
- P2 (seat B): H3's 30-minute effect on injured users was disclosed only as "no thin change". Measured both directions
  (441 major cells lower, 1,410 higher, +1,626 sets net; 2 zero cells made, 429 healed; leads 93 lost, 91 kept) and
  accepted in Ruling 8 as Ruling 5's trade, re-measured in Task 5.
- P2 (seat A): deleting test 4 left S1b-2's "ON B avoids it softly" untested. Test 4 is kept and run ON at beginner, with
  a `softFor` mutant.
- P3s folded: tests 6 and 7 at `level: 'beginner'` (seat A); the third mutant's recipe replaced by test 6b (seat A); the
  S1b-2 Decision 2 amendment stated (seat A); the dropped-row counts scoped to the 332 and the 188 (seat B); the 144's
  pin plans "fewer core rows, 128 none" and the second traced persona (seat B); 142 / 2 day sizes (seat B); the CI rate
  range (seat B).

**Round 16 (2 Sonnet seats on v16, context-blind; 0 P0, 0 P1, 1 P2, 5 P3; seat A converged, seat B not).** Every round-15
answer reproduced (the two-direction numbers, test 4's ON recipe and its `softFor` mutant, tests 6 / 7 / 6b at beginner).
Folded into v17:
- P2 (seat B): the 30-minute trade's acceptance did not name its class or its owner. Named (Back, advanced, 35 plans, 1-4
  sets under the bottom), labelled the plan's own call outside d23, and a Back-below-bottom baseline added to Task 5.
- P3s folded: "65" corrected to 53 with its definition (seat B); the drop-the-widening mutant reddens 6 and 6b (seat A);
  the widening reaches the top-up through one helper, with test 6c and a fourth mutant, and S1b-2's acceptance line and
  three comments rewritten (seat A); the registry count 29 (seat A). Not folded: seat A's P3-3 (`CSpec` unread after
  the V3 `pick` goes): `split_resolver.dart` still constructs it and tests read `DaySlot.specsA` / `SplitResolver.select`
  (`beginner_full_body_test.dart:57,71`, `shared_contracts_test.dart:85`); the V3 chain had no production caller before
  this batch, so it stays as the tests' fixture, outside this unit's deletion list (round 17's wording).

**Round 17 (1 Sonnet seat on v17, narrow confirmation of the round-16 folds; 0 P0, 0 P1, 0 P2, 5 P3; converged).** The
56 down-crossings' class, the 53, the registry's 29, the mutant mapping and test 6c's constructibility reproduced. Folded
into v18 (wording and sweep only): `same_movement.dart:6` (not 7-8) and two more statements of the old rule (the SoT
concept description and `plan-engine-detail.md:324`) in Task 6's body; the mutant sites; test 6c's injury, phase, tier
and day shape; the Back-below-bottom baseline in Task 5's own list; the `CSpec` rebuttal reworded.

**Round 18 (1 Sonnet seat on Ruling 5c, the v19 build finding, with its diff; 0 P0, 0 P1, 0 P2, P3s only;
converged).** The seat reproduced the 32.6-minute day, the helper's guards and the golden's silence. Folded: three guard
tests the group lacked (all or nothing, focus through the guard, a lead forced by the weekly top), `pick.rank` for the
pick's rank (it is the slot's index in its day), and Ruling 5c's text on the cap-forced lead and the `belowCount` label.

**Task 2 build record (plan v19).** Findings while flipping, each with its evidence in the diagnose doc:
- Ruling 5c (above): a real overrun the budget gate found once every goal ran on the core-list pool; fixed in this unit,
  13 mutants red (5c, pass A, and the shared helper's guards).
- Re-derived on the core path (the old personas were picked on the cascade): `thin_day_topup_behavioral_test.dart`'s
  week-2 day (now "Shoulders, back, arms": Backpack Bent-Over Row, Dead Bug, V-Up), its exclusions persona (5 days),
  its foundational persona (the "Upper push + core" day); a strong exclusions mutant (capability and exclusions both
  dropped) because the capability already folds exclusions in, so dropping exclusions alone is equivalent.
- Ratchets moved: cross-day variety 70 / 38 plans -> 75 / 17 (69 are home_dumbbells Upper days with a shallow core
  pool); keep-all-slots ceilings tightened to the measured 19 / 6 / 0 / 0 (from 123 / 69 / 36 / 34); the same-movement
  gate's 931 placements unchanged.
- The top-up's injury-substitute preference had no test that reddened when its `_selectCandidate` call dropped the
  preference (the picker's call did); `thin_day_topup_behavioral_test.dart` gains "curated sub that sorts last".
- Test 6b first passed a capitalised previous-phase name; production lowercases it
  (`WorkoutScheduleReadService.previousPhaseNamesByDay`), so mutant 3 survived on a wrong input. Fixed; mutant 3 red.

**Tasks 3-5 build record (2026-11-12, the final tree).** Findings while building, each with its evidence in the diagnose
doc (`39eb2a`) and the closure:
- Task 3: `query_v4_rules_behavioral_test.dart`'s sort test passed with the foundational sort key removed. A Hive box
  iterates its keys sorted, so the ids `P2F` < `P2NF` already gave the expected order ("box order cannot pass it" was
  false); the ids now make key order the exact reverse of the expected order, with a precondition assert. All 7 mutants
  (4 filters off, 3 sort keys removed) red. The gate's scorecard group runs 26 personas (30 minus 4 golden keys).
- Task 4: the gate's oracle read the raw exclusion tokens for the 12 exclude-everything personas, so its first run
  flagged 488 bodyweight picks as excluded; the generator never excludes the floor (`floorSanitizedExclusions`), and the
  oracle now reads that set. The hard test's ceilings were recorded from one serial run on the final tree: r9 284 thin /
  16 one-exercise, ext 182 / 6 (equal to the no-R6 measurement of Ruling 3 / d17); `f_repeat_pairs30` 60 / 8, 120 / 2,
  94 / 2, 27 / 0. Mutants: a retired row injected, another tier's ratchet, a forced empty day (red); the same with the
  empty-day assertion removed stays green (that assertion is the only guard); one exclude-everything persona forced
  empty in the gate (red).
- Task 5, found at a re-check of this plan against the tree: the `iso_first` built-type change (section 4) and Ruling 6's
  behavioral test had not been built. Both are in this unit: the audit dump records each row's built type (`x[7]`) and
  `iso_first` reads it (12 -> 0; three lib-test cases, 2 mutants red), and `injured_push_day_core_test.dart` pins the
  shoulder + wrist bodyweight Push day (48 runs; the top-up switched off reddens it).
- Task 5 measurements: the 2,304-plan audit equals prototype H in all but 5 plans, every one Ruling 5c's (a day of 32-34
  minutes ends at 29-30 with one hold fewer): cells newly below live 6 in 4 plans (H's 2 plus 5c's 4 Back cells in 3
  plans), deepened 0, worse plans 3 (5c's), zero cells newly against main ON 0, majors at 0 in weeks 1-3 where live has
  sets 0, weeks of 0 Hamstrings 0, the minor residue equal to H's (section 4), issue codes equal to H's, 0 empty days.
  The focus grid differs from H3's dump in 70 of 103,680 lines, all in the same 5 plan keys (closure `FOCUS_GRID`, both
  sha256). The golden: every one of the 998 keys equals main's pre-flip ON world (Rulings 5, 5c and 12 change none) plus
  the 12 exclude-everything keys.
- Task 5, injured grids (closure `INJURED_GRID`, tables on OI-452): the 15-pair grid at 30 / 45 / 60 minutes holds 0
  empty days, thin 520 / 344 / 352 and one-exercise 20 at each (live 427 / 341 / 341 and 8), equal to H3 and main ON on
  every count, and no hip pair gets a jump row (live 1,529 / 1,321 / 1,318). The nine-block grid (46,512 runs): 0 empty,
  0 unsafe, 0 hip jump rows; thin 2,286, one-exercise 94, OI-452's.
- B-pass (`docs/reviews/generator-step1-1bf-bpass.md`): 0 P0 / P1, 9 P2, 11 P3, each fixed or answered; the allocator
  change (guard (c)'s 1e-6 tolerance in one helper, `rowsSeen` on a copied B day) moves no plan: the 2,304-plan audit
  re-run is byte-identical and the golden unchanged.

## 10. Founder decisions (asked once each, 2026-11-10 and 2026-11-11; d16 asked twice, d17 and d23 asked with an explanation, d19-d21 asked together)

1. d14: the minor-muscle residue (section 4) ships with the flip; a minted OI carries it, owned by step 2's weekly
   floor. Answer: "Ship now, fix in step 2".
2. d15: `plan_generator.dart` (rule 14): the two call sites that pass the dead `applyInjuryUniversalFilter` (lines
   201-202, 216-217) are edited to drop it, nothing else in the file. Answer: "Yes, remove the two lines".
3. d16 (2026-11-11, asked twice the same day; the second answer stands): the injured thin and one-exercise days
   (Ruling 8: over the 15-pair grid at phases 1-3 and the repeat, thin 341 -> 352 and one-exercise 8 -> 20 day-weeks,
   the 12 new one-exercise day-weeks all the shoulder + elbow `general_fitness` beginner 5-day Upper day) ship with
   the flip, recorded on OI-452, which gets its own plan right after. Answer: "Ship, OI-452 next". (The first ask
   quoted only the phase-1 pair block and a guard, prototype J, since rejected; answer then "Ship, fix in step 2".)
   Round 10's R6 extension (Ruling 3) found 6 more one-exercise day-weeks, all 9 injuries on bodyweight
   (general_fitness advanced 6-day, phases 1-3, the Legs + Core day), with the same writer and reader (the weekly top
   spent before a late day) and the same counts on main's allocator; they are d17's.
4. d17 (2026-11-11, round 11, seat B's P2: v11 had read them as inside d16 without asking): over the R6 extension's
   1,465 runs, removing R6 leaves 43 runs worse than live, +94 thin and +6 one-exercise day-weeks (all 9 injuries on
   bodyweight: +84 thin, +6 one-exercise; all 9 on home_dumbbells +6; equipment triples on home_dumbbells +4), while the
   other runs lose 612 thin day-weeks and every R6 refill there held retired E261. Asked whether to ship them with the
   flip on OI-452 or hold the flip until OI-452 is built; after an explanation the founder answered: "So users having 9
   injuries will get thin days right? But that's unlikely, I think any user having more than 3 injuries will take rest
   and not workout so that should be fine." Read as: ship with the flip; the days are listed on OI-452 beside d16's and
   held by the extension files' ratchets. The founder's reason names users with more than 3 injuries; the question quoted
   the whole rise (+94 thin), so the answer also covers its 2 equipment-triple runs (3 injuries, home_dumbbells, +4 thin,
   no one-exercise day), which are listed on OI-452 with the rest (round 12, seat B).
5. d18 (2026-11-11, round 11, seat A's P3): widen d15 to the three stale comments at `plan_generator.dart:98, 137, 182`
   (comments only). Answer: "Yes, fix the comments".
6. d19 (2026-11-11, round 12, seat A's P2): the flip leads a hip-injured user's day with a jump row (Jump Squat, Box
   Jump) in 3,189 of the 15-pair grid's 103,680 day-weeks (live 541), because the jump rows carry only ankle / knee
   (Lunge with Jump already carries hip) and a hip user's knee pool holds only jump rows. Asked: tag the jump rows
   unsafe for hip in this flip, in 1B-F2, or leave them. Answer: "In this flip, 1B-F". The question said 18 rows and a
   cloud re-seed; both were corrected after the answer and the correction reported to the founder: the field is
   bundle-only (no cloud column, so no migration and no live step), and 4 of the 18 are upper-body plyometrics with
   no landing load on the hip (G1750, G0492, G1273, G1353), so 14 rows are tagged (Ruling 12).
7. d20 (2026-11-11, round 12, seat A's P3): the three audit flags that rise with the flip (`lead_starved` 1678 -> 2281,
   `low_volume` 1287 -> 1767, `ab_swing` 341 -> 495 issues over the 2,304 plans, verdicts 190 / 620 / 1494 -> 431 /
   1570 / 303) ship with it, owned by step 2 (OI-486 and the weekly floor). Answer: "Ship, step 2 fixes".
8. d21 (2026-11-11, round 12, seat A's P3): widen d18 to every stale comment in `plan_generator.dart` (lines 97-99, 109,
   135-136, 181-184, 252 besides 98 / 137 / 182), comments only. Answer: "Yes, all stale comments".
9. d22 (2026-11-11, round 13, seat B's P2: d19 was asked with its benefit only). The cost, measured on the 15-pair
   grid's 1,920 hip x bodyweight run-weeks (weeks 1-2): median weekly Quads sets live 5, d19 0 (Wall Sit the only quad
   row left); run-weeks with no quad work live 501, flip without d19 622, d19 1,518. Two alternatives measured and
   shown: opening Wall Sit (every level) and Sissy Squat (advanced) in the core lists (median 4, 476 zero run-weeks,
   but 1,171 uninjured audit plans change, Wall Sit replacing loaded squats and lunges, `unloaded` +479, suitable 431 ->
   353: rejected before asking); and a per-slot easier-level fallback for injured users only (median 3, 622 zero
   run-weeks, ~3,500 more filled slots for other injured users, uninjured untouched, a new code path). Asked: d19 +
   fallback, d19 as decided, or undo d19. Answer: "d19 as decided".
10. d23 (2026-11-11, round 13, seat B's P2-1: every injured measurement ran at the harness's 60-minute default). The
   15-pair grid at 30 minutes (`PROBE_MINUTES=30`, 103,680 day-weeks): thin days (under 3 exercises) live 427, flip
   520 on H3 and 520 on main's allocator (the same thin day-weeks; picks identical on the 332 new ones; round 14's
   re-run, Ruling 8), so the rise is the core-list pool's, not Ruling 5's; one-exercise days 8 -> 20 and empty days 0 at both lengths, as at 60 minutes
   (341 -> 352); at 45 minutes 341 -> 344. Mechanism: a slot whose core-list rows all fail the injury filter stays empty under the flip where live
   fills it from the whole library (Floor Press, a retired row, 158 of the dropped rows, Band Single Arm Standing Low Row 42, Face Pull
   38, Band Pull Apart 33); at 45 and 60 minutes an extra core or accessory slot hides the gap (of the 332, 188 hold 2
   exercises at 60 minutes too, already in d16's 352), at 30 minutes the day has 3 slots and 144 days drop from 3
   exercises to 2. [Corrected in round 14, Ruling 8: the 144 are pinned repeat days whose pins come from a 30-minute
   uninjured plan with no core row, so the allocator's weekly top refuses their third row; there is no "3 slots" at 30
   minutes (`countFloor(30)` = 4). Same counts, same OI-452 fix; the founder was told the corrected mechanism.] The R6 domain at 30 minutes (46,512 runs, 2,542 fired): without R6 0 empty, 6 one-exercise, 184
   thin; the 41 worse runs are d17's all9 cases (38 bodyweight, 3 home_dumbbells), no flagged id. Asked in plain
   terms with the per-length table; answer: "Ship, OI-452 next". The 30-minute counts join Ruling 8's ratchet (the
   `f_repeat_pairs30` block) and OI-452's board entry.

## 11. Unit 1B-F2: the overlay copy (its own plan, next in step 1)

Split out of 1B-F under §4.12.1 (three review rounds each found overlay pins the previous one missed). It lands after
1B-F merges, with its own plan, x2 review and B-pass, and its cloud migration applied only on the founder's explicit
go. Its content as reviewed so far:

B1 Ruling 4 (`docs/plans/2026-10-22-library-core-list-pool.md:83`) assigned it to the flip; 1B-F2 copies `slot_pattern` into `movement_pattern` (13 rows) and `slot_focus` into `target_focus` (19
rows), then deletes both keys; `CoreListSelector` reads `movement_pattern` / `target_focus` (core_list_selector.dart
:190, 229, 231). Reason it was an overlay: the cascade (`queryV4`) and `exercise_display.dart:11-26` read the old
labels; after the flip `queryV4` serves the top-up only and the top-up then reads the same labels as the picker, which
removes the mixed-label state an injured user's day would otherwise have. Display labels change on the 19 / 13 rows
(for advanced users E114 reads "Shoulders, Front Delts, Upper Chest", E264 "Lats, Mid Back": `formatMuscleLabel` joins all of `target_focus`). No row in the set carries a `warmup` pattern, so warm-up eligibility
is unchanged (checked: E064 Rowing Machine loses `horizontal_pull`, keeps `cardio`). Data path: library JSON, the
importer, seed v27 (v25 is this unit's, Ruling 12; v26 is Unit 1B-R's, G0355 at beginner), and a cloud re-seed migration (cloud stores `movement_pattern`, first element; `target_focus` is
not a cloud column): minted with `scripts/mint_migration.sh`, rehearsed in the local docker postgres inside BEGIN ...
ROLLBACK, applied live only on the founder's explicit go, ledgered in `backups/applied_migrations.json`.

Pins and writers of the overlay keys, each changed in the same edit:

| file | what it does | after the copy |
|---|---|---|
| `exercise_library_core_fields_contract_test.dart:131-141` | pins the ids carrying the keys | pins that no row carries them, and the copied values on the 13 / 19 rows |
| `exercise_library_schema_contract_test.dart:41-45` | key allow-list | the two keys leave the allow-list |
| `library_s1b2_loaded_versions_test.dart:65-71` | E048 keeps its overlay, N20 carries `slot_pattern` | E048 / N20 `movement_pattern` is `hip_dominant` |
| `core_list_pool_behavioral_test.dart:494, 502` | `slot_pattern` fills the Front Delts isolation slot | the same through `movement_pattern` (E015) |
| `scripts/add_library_batch_c_v15.js:101` (`LINK`), `scripts/data/library_batch_c_source.json` (N20), `test/scripts/library_media_importer_test.dart:753-762`, `library_batch_c_rows_contract_test.dart:37-39` | the importer passes the key through | N20's source carries `movement_pattern: [hip_dominant]`; `LINK` and the two tests drop the key; a from-scratch importer run reproduces the library |
| `scripts/add_library_core_fields_v13.js`, `scripts/data/library_core_fields_v13.json`, `library_e230_retag_test.dart:23` | the v13 table that wrote the overlay | the table's overlay columns become the target fields; `--check` reproduces the library |
| `scripts/library_batch_c2_removals_gen.js:85, 232`, `library_batch_c2_removals_file_test.dart:108` | names the key | key dropped; `--check` green |
| `core_list_selector.dart:176-231` | `slot_* ?? ...` fallbacks | read `movement_pattern` / `target_focus` directly |
| `library_depth_rule_test.dart`, `test/helpers/library_depth.dart` | depth rule on the shipped library | simulated: 0 violations before and after; the frozen base fixture keeps its own keys |

12 of the 13 `slot_pattern` rows change their cloud `movement_pattern` first element (E064's stays `cardio`).
| `exercise_library_frozen_reference_test.dart:36` (fixture `exercise_library_v12_row_hashes.json`) | hashes every pre-existing key of 26 of the 27 overlay rows | re-recorded with `RECORD_LIBRARY_REFERENCE_IDS=<ids>`, each id named in 1B-F2's diagnose |
| `injury_safety_tags_v13_behavioral_test.dart:83-92` | `queryV4('hip_isolation')` contains E127 Reverse Hyper | the pair moves to `hip_dominant` |
| `library_s1b2_loaded_versions_test.dart:33, 65` | N19 copies E048's `movement_pattern` | N19 carve-out for `movement_pattern` (E048 becomes `hip_dominant`, N19 stays `hip_isolation`, founder 2026-11-09) |
| `exercise_library_schema_contract_test.dart` (optional-key count), `scripts/data/library_batch_c2_removals.json:12`, `library_batch_c2_removals_gen.js:203`, `scripts/seed_exercise_library.js:448` | name the old keys | updated in the same edit |
