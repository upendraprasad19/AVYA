# Generator overhaul step 2: the set allocator (v8, converged at review round 7)

Status: v4 (v1 + round 1: 2 P1, 6 P2, 6 P3; v2 + round 2: 2 P1, 3 P2, 6 P3; founder d26 took the full fix with its
measured costs; v3 + round 3: 2 P1, 4 P2, 9 P3; founder d27 exempts focus exercises; the sequencer change was removed;
v4 + round 4: 0 P1, 6 P2, 8 P3; founder d28 (d26's overrun corrected, kept) and d29 (the priority-1 opener clause
dropped); v5 + round 5: 0 P1, 3 P2, 6 P3; v6 + round 6: 0 P1, 4 P2, 10 P3; v7 + round 7: converged, 0 P1, 2 P2, 6 P3, no design
finding; all folded in, section 13), 2026-11-12 / 13, branch `generator-step2-allocator` (worktree of the same name, based on main 9fc3b043). Task
board: https://claude.ai/artifact/QVpiDjC2KnfPSDh4wVdVEs (step s2, cards t201-t207). Blast radius: `platform`
(plan_engine); tier L. Execution mode: INLINE (one worktree, one writer), decided at batch start (CLAUDE.md 4.12.7).
Merge route: `sh scripts/land_pr.sh <pr>` once the x2 review, the B-pass and CI pass (founder d7).

## 0. Scope and the unit split

Step 2 of the generator overhaul (founder d6, 2026-11-08) owns the allocator: OI-486 (lead lift first), OI-452 (a
3-exercise day floor), OI-453 (a repeat phase whose minutes go up), OI-475 / OI-477 (the quad floor, levels L2 and L3),
d14's weekly minimums (Triceps 86, Core 52, Biceps 36, Calves 9 of 2,304 plans with a zero-set week), d20's three audit
flags (starved leads, low weekly volume, sets swinging between weeks) and OI-501 (physique focus, t108). Step 1 grew from
13 to 26 cards because one plan carried everything; step 2 is split from the start, one PR per unit, each with its own
x2 review, B-pass and CI, in this order:

| unit | owns | why this order |
|---|---|---|
| **2A lead first** (this plan, sections 1-9) | OI-486, d20's starved-lead flag, OI-501's lead finding | every later unit adds or moves sets; they should build on a day whose lead already comes first |
| 2B day floor | OI-452 (d16 / d17 / d23 thin days) | needs 2A's fallback rule (a day never holds fewer exercises than today) as its starting point |
| 2C weekly minimums | d14, OI-475 L2 / L3, OI-477, OI-501's Calves and Core losses, d20's low-volume and swing flags | the largest design space; measured on 2A + 2B's tree |
| 2D repeat-phase minutes | OI-453 | independent of 2A-2C's rules; last because it pins lists the earlier units shape |

Sections 10-12 outline 2B-2D; each gets its own plan section, written on the previous unit's merged and measured tree,
and its own review rounds. Findings from one unit feed the next unit's plan, not new units (founder 2026-11-12).

## 1. Unit 2A: what happens today

Measured on main 9fc3b043 (no generator code change since cf122dd1; the no-focus `plan_dump.jsonl` is byte-identical to
t108's, sha256 5b3da296...), 2,304 plans (4 goals x 3-6 days x 3 levels x 4 tiers x 30 / 45 / 60 / 90 minutes x phases
1-3), no injuries, no history, no focus. "Day" below = one (plan, week, day) of the dump, 41,472 in all.

- `lead_starved` (the audit, week 1 only: a compound lead 2+ sets under an isolation): 2,284 flags in 1,084 plans.
- Days with an exercise at the lead's sets + 2 or more (any type and every week, wider than the audit's compound lead /
  non-compound biggest / week-1 test): 2,676 in
  week 1, 3,265 in week 2, 2,676 in week 3. Days with any exercise above the lead: 19,765. Week-1 days whose lead has 2
  sets: 5,720.
- Example (main, `build_muscle|3|beginner|basic_gym|60|3`, week 1, Legs): Barbell Back Squat 2, Deadlift 2, Goblet Squat
  2, Glute Kickback (Cable) 2, Standing Calf Raise 5, Dumbbell Lying Hamstring Curl 5. Under 2A: Back Squat 3, Deadlift
  3, Glute Kickback 2, Calf Raise 4, Hamstring Curl 4, Cable Hip Adduction 3 (Goblet Squat leaves: one of d26's swaps).
  OI-486's own examples no longer reproduce on main: no day holds Barbell Bench Press with Bench Dips, and the Strength
  OHP Day opens with Barbell Overhead Press in 56 of 56 gym plans.

**Writers** (line numbers on 9fc3b043).
- `session_set_allocator.dart`: pass A (`:384-465`) seats every budgeted slot at 2 sets (`const k = 2`, `:420`), rank
  by rank across the week, so every accessory of every day is seated before any lead grows; pass B (`:572-586`) grows
  seated slots to the base 3 in rank order, but pass A's accessories have already spent the time, session cap or weekly
  top the lead needed; passes C and D (`grow`, `:589-612`, called at `:615` and `:618`) add +1 rounds per group below its
  target, and a single-group isolation keeps growing after a multi-group compound has hit a cap.
- `periodization_engine.dart`: `_weekTwoGains` (`:152-217`, `tryGain` `:194`) gives week 2 +1 set per exercise where a
  fresh ledger fits, rank by rank, then the not-budgeted rows (`:214`); `apply` writes week sets (`:80`, `:97-102`: week
  2 = sets + gain, week 4 = `min(sets, max(2, floor(0.6 x sets)))`; `:80` builds the gains). A lead refused its week-2 set by a cap sits under a
  single-group accessory that took one.
- `sequencing_engine.dart` `_reorderDay` (`:59-95`) orders compounds by a bilateral flag and a name-keyed CNS table
  (`:87` builds the result), so the split's first slot does not always open the day.

**Readers** (what R1-R3 and R5 change for each, section 3; the sequencer's order does not change):
- `PeriodizationEngine.apply` (`plan_generator.dart:301`): reads the allocator's baseline sets for weeks 1-4.
- `VolumeTitration.applyToWeeks` / plateau rung 2 (`plan_generator.dart:320-333`, `volume_titration.dart:163`): a ±1 per
  major group on the first exercise crediting it, so a -1 can take a 3-set lead to 2 and a +1 can take an accessory past
  lead + 1. Both are OFF by default (`enable_volume_titration`, `enable_plateau_escalation`, opt-in per call) and nothing
  re-applies R2 after them: 2A does not change them; stated in the nested CLAUDE.md as a known gap for when either flips.
- `SequencingEngine.sequence` (`plan_generator.dart:336`), then `SupersetPairer.pair` (`:339`, `superset_pairer.dart:35`):
  the order rules are unchanged; which rows a day holds can change (section 4), so pairs can change with them; the
  audit's minutes are measured after pairing (section 3's totals include it).
- `SwapService.shortenDay` (`lib/core/services/swap_service.dart:614-720`): drops rows by priority tier, then index;
  the rule changes the set counts and the time a lead's extra set costs, not the order.
- The audit (`plan_audit_lib.dart:306-316`): the day's first exercise after sequencing is its lead.
- `AllocationStats` (`session_set_budget_gate_test.dart:392-436`): `firstLifts` is rank 0 even when not admitted; R2's
  lead is the first ADMITTED slot (section 3); the gate's lead-lift check keeps reading rank 0.
- The repeat phase: `buildPinnedDays` (`plan_generator.dart`, before `:293`) feeds the same `allocate` call, so a
  repeated phase's set counts follow R1-R3 and R5 like a fresh one (its exercise list is pinned; 2D owns its minutes).
- `PeriodizationEngine.apply`'s week-2 note: `overloadNotes` reads `_waveNotes[0]` when no row gained (`:~139`); R5
  refuses more gains, so more weeks can carry that note.
- `WarmupCooldownSelector`: reads the minutes only, no set counts: unchanged.
- The user (Train / Home show the sequenced day and `budgetedDaySeconds`).

**Bug history (CLAUDE.md 4.1.5).** The stated consequence of OI-456 piece B (`plan_engine/CLAUDE.md`, "a lead can end at
2 sets"); filed as OI-486 from the 2026-11-08 audit; d20 shipped the flip with the flag at 1,678 -> 2,281 for step 2.
Not a recurrence of a fixed bug: no earlier fix touched the lead's share.

## 2. Unit 2A: prototypes measured

Prototype switches in a scratch copy of the allocator, `_weekTwoGains`, the sequencer and the audit dump test (not
committed: saved as a patch in the session scratchpad, `step2/prototype.patch`; the worktree's prototype edits are reset
before the build, which re-implements the chosen rule), each over the 2,304 plans, compared with main key by key. "Zero
cells" = (plan, week, muscle) cells with sets on main and 0 now; "below floor" = days under
`SessionBudget.countFloor` (5 from 45 minutes, 4 from 25), 0 on main. Starved-lead counts are the audit's (week 1).

| run | rule | starved-lead plans (flags) | suitable | zero cells | below floor | no-deload plans |
|---|---|---|---|---|---|---|
| p0 | main | 1,084 (2,284) | 513 | - | 0 | 54 |
| p1 | accessory <= lead (cap only) | 142 (294) | 493 | 0 | 0 | 205 |
| q9 | accessory <= lead + 1 (cap only) | 159 (311) | 544 | 0 | 0 | 54 |
| p3 | cap + lead seated at 3 in pass A | 121 (164) | 649 | 410 | 408 | 0 |
| q31 | + lead + 1, time look-ahead, sequencer change | 66 (115) | 748 | 98 | 408 | 36 |
| r79 | same-day trial (floor and groups) | 74 (127) | 748 | 0 | 276 | 36 |
| s143 | lead + 1, seat at 3, sequencer change, per-variant fallback to main | 146 (367) | 762 | 0 | 0 | 24 |
| s135 | s143 with the strict cap | 140 (361) | 728 | 0 | 0 | 24 |
| t399 | s143, the fallback tries the capped world before main | 50 (66) | 763 | 0 | 0 | 24 |
| u4 | the sequencer change alone | 1,078 (2,303) | 513 | 0 | 0 | 54 |
| u1935 | v911 + "no group under its weekly floor loses sets" in the fallback | 1,008 (2,178) | 544 | 0 | 0 | 54 |
| w525 | the safe piece: lead + 1 cap, week-2 cap, sequencer change (R4), no lead seat | 136 (267) | 547 | 0 | 0 | 54 |
| c6665 | the safe piece without R4: lead + 1 cap and week-2 cap, the lead = the opener, no seat, no fallback | 132 (279) | 548 | 0 | 0 | 54 |
| v911 | t399 + week-2 cap + B against main's B + the sequencer change keyed on the first budgeted row | 50 (66) | 763 | 0 | 0 | 24 |
| x2955 | v911 with the lead = the sequencer's opener and NO sequencer change | 50 (60) | 789 | 0 | 0 | 24 |
| y7051 | x2955 + focus exercises exempt from the cap (d27) + B's third branch to main | 50 (60) | 789 | 0 | 0 | 24 |
| **z7051** | **y7051 with the allocator's lead fallback = `openerOf` over the admitted slots (as week 2)** | **47 (57)** | **789** | **0** | **0** | **24** |

What the runs taught:
- The cap alone (p1, q9) leaves leads at 2 (time or a cap stops them) and then holds every accessory at 2 too: volume
  falls (Calves -11,147 sets in p1) and no-deload rises (a week of 2-set rows cannot deload).
- Seating the lead at 3 in pass A spends time and weekly top that later slots needed: whole exercises fall off (30-minute
  full-body days lose their lunge, 410 zero cells) and days drop under their count floor.
- A same-day check cannot see the week (r79's 276 below-floor days: pass A seats rank by rank across days). The kept
  rule has the same kind of change inside a day's row count (section 4, exercise changes).
- Week 2 undoes week 1 unless `_weekTwoGains` follows the same cap (t399: 66 week-1 days at lead + 2, 2,006 in week 2).
- Changing the sequencer to open with the split's first row (u4 alone: 1,468 plans, 8,704 days with a different first
  exercise; in v911 5,498 days open with a unilateral lift, 374 on main, and Deadlift / Back Squat / Romanian Deadlift
  lose the opener) breaks the sequencer's own rules (bilateral first, heaviest first); review round 3. Taking the
  sequencer's opener as the lead instead (x2955) changes no day's first exercise and measures better (789 suitable
  against 763).
- Capping focus exercises halves the physique focus's extra work (x2955: arms focus +4,037 biceps sets against +8,197 on
  main); founder d27 exempts them (y7051: +9,620, the figure d27 was decided on; z7051: +9,632).
- A weekly-floor term in the fallback (u1935) sends most variants back to main and gives up the gain.

## 3. Unit 2A: the rule

**The lead.** A day's lead is the budgeted row the sequencer will open the day with: `SequencingEngine.openerOf(rows)`
(new, pure: the same order `_reorderDay` gives, compounds before isolations, bilateral before unilateral, highest CNS
demand first) over the day's budgeted rows, taken before allocation. If that row is not admitted, the lead is
`openerOf` over the day's ADMITTED budgeted slots (the row the sequencer will open with), the same definition
`_weekTwoGains` uses (`openerOf` over `ranked[d]`, the admitted budgeted rows), so weeks 1 and 2 cap against the same
row. `openerOf` and `_reorderDay` share one private comparator and both keep `List.sort` (no new dependency: package
`collection` is only transitive in `pubspec.lock`); today's `List.sort` is insertion sort, stable, below 32 elements,
and no day holds 32 rows, so ties resolve the same way in both and `_reorderDay`'s output is unchanged byte for byte
(the golden proves it). The dependency on that stability is named in a comment and pinned by a test (a day of tied rows
in a known order). The sequencer itself is unchanged. A hold (not budgeted) can still open the day ahead of the lead
(the named residue, section 4).

- **R1 (lead seat).** In pass A, the lead slot is seated at `SessionBudget.baseSets` (3) at its own rank when that fits:
  time, session cap, weekly top, the day's count target (`levelMax - nonBudgeted[d]`, at least 0, checked first as for
  every slot) and, when the lead is rank 0, the rank-0 reservation (`reserved(3)`: computed, as today, from each later
  day's RANK-0 slot (`byDay[d2].first.groups`), not its opener: every later day whose rank 0 credits the same group keeps
  2 sets of weekly top; a lead at a later rank has no reservation, as today). Else it is handled exactly as on main (the 2-set seat
  with Ruling 5's eviction, or removal; `reserveBlocked`; the empty-day guard). The seat at 3
  never evicts a hold (Ruling 5's `evictFor` runs only for the 2-set seat), so a lead that fits at 3 only after an
  eviction is seated at 2.
- **R2 (accessory cap).** In pass C a budgeted slot that is not its day's lead never grows past the lead's sets + 1. In
  pass D (the focus pass) the cap does not apply (founder d27). Pass B is not capped (it grows to 3 and the lead is at
  least 2, so the cap could not bind).
- **R3 (fallback, per variant).** Variant A is allocated three ways: L = R1 + R2, C = R2 only, M = main. A keeps L when L
  is not worse than M; else C when C is not worse than M; else M. "Worse" = a day holds fewer rows than min(`countFloor`,
  M's rows for that day), or a group with weekly sets in M has 0. Variant B (not 6-day): M_B is main's B over main A's
  copied days; L_B and C_B copy the CHOSEN A's days and are compared with M_B the same way; when both are worse, the
  whole plan falls back to main (A = M, B = M_B; A's stats become M's), so the kept B is never an unchecked mix. "Worse"
  is a pure `@visibleForTesting` function, `SessionSetAllocator.worldIsWorse(rows, weekly, mainRows, mainWeekly,
  floor)` (rows per day and weekly sets per group, both worlds), unit-tested directly; the allocator calls it. Rows
  count holds too, so a world that drops a hold and keeps one more budgeted row (or the reverse) passes at an equal
  count. The kept world's
  `AllocationStats` is the variant's stats (B's `copyFrom` is A's kept stats), and a new field `leadWorld` ('lead' |
  'capped' | 'main') names it. In the 6-day path B = A, as today. Measured: A kept L in 2,084 plans and C in 220, never
  M; B (1,728 non-6-day plans) kept L in 1,718 and C in 10; the same shape in both focus grids.
- **R5 (week 2).** In `_weekTwoGains` a row that is not the day's lead and does not credit a focus group, a hold
  included, gains its week-2 set only while its week-2 sets stay at most the lead's week-2 sets + 1. The rank loop tries
  rank 0 of every day, then rank 1, and so on; a lead at a later rank is tried after the rows ranked before it, which are
  then held to the lead's sets before its own gain + 1 (stricter, never looser). A focus row is not capped
  (d27). R5 applies in every world, `main` included: `apply` cannot see `leadWorld` without a `plan_generator.dart`
  change, and in a main-world variant R5 only withholds an accessory's week-2 set. So R3's guarantee is about the
  allocator's rows, not week 2's gains. (No variant kept main in any measured grid; only the behavioral tests reach it.)
- **What "never worse than main" means**, exactly: in each variant, no day holds fewer rows than min(count floor, main's
  rows), and no group that main trains in the week is at 0 (B relative to main's B). It does NOT say a group's weekly sets
  stay near main's, that a day keeps its exercises (a swap of one exercise for another passes it), that a day keeps every
  group it had, or that a day stays inside its minutes: section 4 gives those numbers. An injured user's thin day (under
  the floor on main) keeps at least main's rows within one generation. **Corrected by the build (2026-11-13):** a pinned
  repeat starts from the previous phase's plan, which 2A changed, so `kThinCeilings` CAN rise: `f_repeat_pairs30`
  home_dumbbells 120 -> 121, basic_gym 94 -> 96, full_gym 21 -> 22 (lower_back + elbow pairs; pins from a switch-off
  phase 1 give exactly the old counts). Re-recorded with the cause; unit 2B's input (diagnose d4a7e2).
- **The audit.** `plan_audit_lib.dart`'s `lead_starved` skips rows that credit a focus group when it looks for the
  biggest row (d27); no other audit rule changes.
- **Kill switch** `disable_lead_first` (`PlanEngineFlags.leadFirstEnabled`, default ON) turns R1-R3 and R5 off together.
  Read the way Unit 1B-Q reads its flag: `allocate(..., bool? leadFirst)` and `PeriodizationEngine.apply(...,
  bool? leadFirst)` take an optional argument that defaults to the flag, so `plan_generator.dart` is untouched (rule 14).
  Two reads of one Hive key per generation (each falls back to ON on a Hive error, as every `PlanEngineFlags` getter
  does); a flag flipped between them would give one generation an ON allocation with an OFF week 2 (harmless: a week-2
  gain the cap would have withheld). The doc comments that call the stages pure change with them:
  `session_set_allocator.dart:120` ("Pure: no Hive, no flag read") and `periodization_engine.dart:67` ("this stage
  stays pure (no Hive read)"). OFF = main byte for byte (golden fixture
  `test/fixtures/generator_golden_hashes_lead_first_off.json`, recorded on main; the OFF golden test sets the Hive flag,
  since `generateV4` has no parameter for it).

Measured (z7051; the build re-measures the clean code and must reproduce these numbers or explain each difference):

| measure (2,304 plans, no focus) | main | 2A |
|---|---|---|
| starved-lead plans / flags (audit, week 1) | 1,084 / 2,284 | 47 / 57 |
| days with an exercise at lead + 2 or more, weeks 1 / 2 / 3 | 2,676 / 3,265 / 2,676 | 58 / 59 / 58 |
| days with any exercise above the lead | 19,765 | 10,865 |
| days whose first exercise changed | - | 0 |
| verdicts suitable / needs work / not suitable | 513 / 1,763 / 28 | 789 / 1,487 / 28 |
| plans whose verdict improves / gets worse | - | 304 / 28 (suitable -> needs work) |
| no-deload plans | 54 | 24 |
| other audit flags (plans): over_top / unused_time / unloaded / band_in_gym | 416 / 754 / 46 / 64 | 418 / 724 / 42 / 36 |
| sets swinging between weeks (plans) | 402 | 308 |
| low weekly volume (plans) | 1,740 | 1,421 |
| week-1 days whose lead has 2 sets | 5,720 | 815 |
| total sets, weeks 1 / 2 / 3 / 4 | 185,530 / 189,773 / 185,530 / 149,843 | 187,127 / 190,872 / 187,127 / 142,742 |
| zero cells / days below their count floor | - / 0 | 0 / 0 |
| plans where a group has sets in some weeks and 0 in others: Calves / Biceps / Triceps / Core | 5 / 14 / 19 / 44 | 57 / 16 / 19 / 42 |
| days that lose an exercise main's day had (of which same or more rows: a swap) | - | 12,090 (7,224) |
| days over the user's minutes by more than 1 / 2 / 3 minutes (the gate's limit is 2) | 0 / 0 / 0 | 1,973 / 1,073 / 581 |
| days over the user's minutes at all / worst ratio | 3,553 / 1.033 | 5,857 / 1.133 |
| total planned minutes | 1,889,683 | 1,883,543 |
| plans changed | - | 2,076 |

Costs (sets summed over every plan-week): Calves 33,807 -> 30,433 (-3,374), Shoulders -2,490, Glutes -1,768, Back -1,033,
Core -390, Triceps -292; Hamstrings +4,637, Quads +1,747, Biceps +98, Chest +57. Week 4 (the deload) holds 4.7% fewer
sets: a 3-set lead deloads to 2 like a 2-set one. Zero cells count only (plan, week, muscle) cells that main trained;
the row above counts the other direction (round 5): in 52 more plans Calves are trained in one variant's weeks and not
the other's (53 of the 57 go from 0 in every week on main to 2 sets in weeks 1 and 3, or in weeks 2 and 4): one variant
seats a calf row main dropped and the other does not, which R3 cannot see because it compares each variant with main.
That is d14's zero-set-week class; unit 2C owns it, and 2C's baseline is the post-2A tree. Focus grids: Calves 5 -> 69
(`glutes_legs`) and 5 -> 53 (`chest_shoulders_arms`); phases 4-5: Calves 8 -> 54, Biceps 5 -> 10.

With a focus (z7051 against main's focus dumps, byte-identical to t108's, both audited with the focus skip, d27):

| measure | `glutes_legs` main -> 2A | `chest_shoulders_arms` main -> 2A |
|---|---|---|
| starved-lead plans / flags | 672 / 973 -> 45 / 55 | 1,004 / 1,611 -> 47 / 57 |
| suitable | 706 -> 840 | 531 -> 886 |
| plans improving / getting worse | 206 / 72 | 383 / 28 |
| extra sets the focus adds over no focus, same tree | main: Glutes +27,751, Quads +10,118, Hamstrings +7,755, Calves -4,628; 2A: Glutes +31,133, Quads +9,513, Hamstrings +3,626, Calves -837 | main: Chest +10,227, Shoulders +20,265, Triceps +2,506, Biceps +8,197; 2A: Chest +11,082, Shoulders +21,356, Triceps +2,290, Biceps +9,632 |

Phases 4 and 5 (1,536 plans, the same grid at phases 4 and 5: phase 4 is the lighter phase, where every weekly top is
the band bottom; phase 5 raises the effective level), main -> 2A: starved-lead plans 670 -> 10, suitable 367 -> 480,
no-deload 63 -> 0, zero cells 0, days below their floor 0; costs of the same kind: 10,962 days lose an exercise (3,830
swaps), 7,132 hold fewer rows (6,472 one fewer, 660 two fewer), 660 cells halved in weeks 1-3 and 309 in week 4, 496
week-1 days lose every set of a major group (Shoulders 185, Chest 153, Hamstrings 139), 518 days more than 10% over,
49 plans suitable -> needs work and 162 improve; 64 days get a different first exercise, every one because its old opener
left the day; week 4 holds 6.5% fewer sets (111,719 -> 104,483); sets per group: Shoulders -1,564, Biceps -1,154,
Calves -1,056, Core -693, Back -185; days over the user's minutes by more than 1 / 2 / 3 minutes: 1,590 / 823 / 518 (main:
0 / 0 / 0). The focus grids: 1,973 / 1,073 / 581, as without a focus. A kept L in 1,474 of 1,536 plans and C in 62; B (1,152 non-6-day) L 1,135, C 17.

The `glutes_legs` focus's Hamstrings bring-up falls (+7,755 -> +3,626): with the lead first, the no-focus tree already
holds 51,494 Hamstrings sets against main's 46,857, so less is left to add under the weekly top. OI-501's Calves loss under `glutes_legs` mostly closes (-4,628 -> -837); unit 2C owns the rest. The 72 `glutes_legs`
plans that go from suitable to needs work gain `low_volume` (58), `unused_time` (8) or `ab_swing` (6): volume costs,
unit 2C's.

## 4. Unit 2A: decisions and what they accepted

- **D-2A-1 (founder d26): the full fix, with its measured costs.** Offered after round 2 against the safe piece alone
  (w525: starved leads 1,084 -> 136 plans, no exercise removed or swapped, no longer sessions, but planned minutes -2.46%
  (1,889,683 -> 1,843,174; the unused share of the users' own minutes 19.0% -> 21.0%, z7051 19.3%), Calves -7,874 sets, suitable 513 -> 547). w525 carried R4, since removed; the same safe piece with the opener as the
  lead (c6665, round 7) measures the same: starved leads 132 plans (279 flags), suitable 548, minutes 1,839,660 (-2.65%),
  Calves -7,900 sets, days with an exercise at lead + 2 or more 282 in each of weeks 1-3, no exercise removed or
  swapped, first exercise changed on 0 days. Against it, R1 + R3 (z7051) buy 85 fewer starved plans, 241 more suitable
  plans, 43,883 planned minutes back and 4,526 Calves sets back, at the cost of the 12,090 days that lose an exercise
  (section 4). The cap is lead + 1 (R2, R5): the strict cap measured
  worse with the fallback to main (s135 against s143: Calves -2,954 sets and 34 fewer suitable plans for 6 fewer
  starved-lead plans, 146 -> 140; days with an exercise above the lead 6,235 strict, 10,984 lead + 1). OI-486's "done
  when" is re-worded: "no accessory more than 1 set above its lead, focus exercises excepted (d26, d27)"; its clause "4
  sets with the Strength focus of OI-487" belongs to step 3 (goals), "0 starved leads" becomes the named residue, and
  "the day's priority-1 slot leads the day" is dropped (**d29**: the day keeps the sequencer's order, bilateral and
  heaviest first, and that opener is the lead; on at least 8,704 of 41,472 days the opener is not the split's priority-1 row: u4 moved only a first budgeted row
  that is a compound).
- **D-2A-2 (d26): exercise changes and time.** 12,090 days lose an exercise main's day had. 4,866 hold fewer rows (4,762
  one fewer, 104 two fewer: advanced 7 -> 6 2,742, 8 -> 7 804, 6 -> 5 330, 8 -> 6 80, 5 -> 4 56, 7 -> 5 24; intermediate
  6 -> 5 480, 5 -> 4 84; beginner 6 -> 5 136, 5 -> 4 130; by minutes 45: 2,500, 60: 1,048, 90: 1,048, 30: 270); 7,224
  swap one exercise for another (a mid-rank slot no longer fits and a cheaper later slot of another group does). In
  weeks 1-3, 422 (plan, week, muscle) cells fall to half of main's sets or less (main 4 or more; Triceps 147, Hamstrings
  102, Core 76, Quads 53, Biceps 29), e.g. `build_muscle|4|advanced|basic_gym|45|1` Legs loses its Dumbbell Lying
  Hamstring Curl, Push its Barbell Overhead Press and Pull its Barbell Bent Over Row; 331 more in week 4; 945 of the
  rows lost in week 1 are compounds (Barbell Bent Over Row 86, Band Close Grip Pulldown 86, Push Up to Side Plank 85,
  Deadlift 56, Lateral Lunge 56, Step Up 56, Goblet Squat 56, Dumbbell Bench Press 50); cells above 2 sets on main that fall to 2 or
  fewer: 181 in weeks 1 and 3, 197 in week 2 (none to 1); 377 week-1 days lose every set of a major group on that day
  (Shoulders 192, Hamstrings 89, Chest 69). 28 plans go from suitable to needs work (22 gain a `low_volume` flag, 6 an
  `ab_swing` flag: volume costs, unit 2C's), 304 improve. Days over the user's
  minutes 3,553 -> 5,857; 581 days more than 10% over (all 30-minute plans; 204 in each of weeks 1 and 3, 173 in week
  2), worst 1.133 (34 minutes for 30). Against the gate's own limit (`limitMin = effMinutes + 2`,
  `session_set_budget_gate_test.dart:307`): main has 0 days more than 1 minute over; 2A has 1,973 more than 1, 1,073
  more than 2 (beyond the limit, all 30-minute) and 581 more than 3. d26 was first put with "590 days 3-4 minutes over";
  the corrected count was put again and d26 stands (**d28**). These counts are the dump's rounded minutes
  (`session_budget.dart:337`), not the gate's own: the gate compares exact seconds (`:307`, `:341`) and already excuses
  a count-forced day up to `maxForcedOverSeconds` (300 s) plus its 2-minute slack (`countExplained`, `:362-369`).
  Mechanism (read): R1 seats the lead only through `ledger.fits`, so only pass A2's count-floor force and the empty-day
  guard (Ruling 5c; the gate holds `capForcedFirst` at 0) can pass the clock, and the gate already excuses both. So the build first runs the gate on the 2A tree with its own accounting
  (`daySeconds`, `countForced`); the limit is raised (d28's approval) only if days the gate does not already excuse
  remain, to their exact measured seconds, with a ratchet test that fails if they grow; otherwise nothing is loosened.
  The gate's grid is phases 1, 4 and 5 (`session_set_budget_gate_test.dart:61`), so the ratchet is taken on that grid.
  **Build result (2026-11-13):** the gate is green on the 2A tree with its limits unchanged, so no limit is raised and
  no ratchet test is added.
- **D-2A-3 (founder d27): focus exercises are exempt from the cap** (pass D and week 2), and the audit's lead check skips
  them. Section 3 gives the focus numbers; the rejected alternative (x2955, focus capped) is in section 2. Core under
  `glutes_legs` loses more than on main (-2,022 -> -2,458 sets against no focus); unit 2C owns it.
- **The named residue.** 57 starved-lead flags, every one a hold: 43 with Hollow Body Hold at 4 sets as the biggest row
  beside a budgeted compound lead at 2 (e.g. Dand (Hindu Pushup), Band Kneeling Single Arm Pulldown, Romanian Deadlift;
  so "a hold" does not mean the lead is not at 2), and 14 opening with Doorway Isometric Row at 3 beside Sliding Lat Pull
  at 5 (holds are not budgeted: the allocator prices their time and never sizes them, so R2 and R5 never reach them in
  week 1). The focus
  grids: 55 and 57, phases 4-5: 10, the same two classes. OI-486 closes with them named.
- **Not explained:** of the 815 week-1 leads still at 2, 384 are 30-minute days (45: 163, 60: 134, 90: 134) and 625
  beginner days (advanced 118, intermediate 72); the cause for the 45-90-minute ones (a cap, a weekly top or the
  reservation) was not traced, and the rate differs by day index (5.9% to 10.5% on t399's days 0-5). `firstLifts` reads rank 0, which is not
  the opener on many days, so the build adds a per-opener stat to `AllocationStats` (`leadSeats`: day, slot, sets, and
  what bound it: a group's weekly top, the session cap, the count target or the clock) and names the cause per day.

## 5. Unit 2A: tests

Existing tests R1-R3 and R5 move (each re-read; a changed pin is re-recorded with its measured value and the reason, never
loosened silently): `session_set_allocator_behavioral_test.dart`, `exercise_count_band_behavioral_test.dart`,
`allocator_timed_hold_eviction_behavioral_test.dart`, `quads_floor_6day_behavioral_test.dart` (the `_quadsAfter` /
`_quadsLabel90` tables: Quads move), `quads_credit_flag_consumers_test.dart`, `rest_by_type_behavioral_test.dart`,
`plateau_rotation_behavioral_test.dart`, `session_set_budget_consumers_test.dart`, `test/helpers/session_budget_fixtures.dart`
(reads the allocator), `plan_audit_lib_test.dart` (the focus skip), and the other `PeriodizationEngine.apply` callers (R5
is ON by default): `test/plan_engine_v4/{hypertrophy_archetype,strength_archetype,shared_contracts,session_budget}_test.dart`
and `test/plan_engine_v4/_helpers.dart`; `physique_focus_bringup_test.dart` (the allocator's focus pass through
`session_budget_fixtures.dart`, which d27 touches). Named by round 6 and re-read too: `variant_b_quads_behavioral_test.dart`
(week 2 holds quad sets; the Glutes session cap is its failure mode, and R1 seats an opener at 3 under that cap: the one
most at risk), `thin_day_topup_behavioral_test.dart`, `volume_titration_behavioral_test.dart`,
`plateau_escalation_behavioral_test.dart`, `repeat_phase_pinned_selection_behavioral_test.dart`,
`deload_working_base_stash_behavioral_test.dart`, `oi489_timed_hold_real_engine_test.dart`,
`same_movement_day_gate_test.dart`, `focus_grid_dump_test.dart`, `test/plan_engine_v4/mixed_archetype_test.dart`,
`periodization_wave_reps_invariant_test.dart`. The list is a floor: the build greps `test/` for every caller of
`generateV4`, `PeriodizationEngine.apply`, `SessionSetAllocator` and `SequencingEngine` and re-reads each. Second golden:
`loaded_wins_kill_switch_golden_test.dart` (`generator_golden_hashes_loaded_wins_off.json`) is re-recorded with 2A ON and
loaded-wins OFF. `docs/sot_registry.yaml`'s existing `session_set_budget` entries have
their line ranges re-derived from anchors after the edit (the shifted-range trap), as well as the new `lead_first`
concept's. `boundBy` and `belowFloor` labels: a lead seated at
3 reads `boundBy` null; a group held only by R2 is labelled `cap_limited` (no new `_Why`: `_whyFlags` cannot name the
lead cap; stated in the nested CLAUDE.md).

Behavioral (`test/contracts/lead_first_allocator_behavioral_test.dart`, fixtures built like
`session_set_allocator_behavioral_test.dart`):
1. The lead: `openerOf` picks the bilateral compound over a unilateral one and the higher CNS demand within a tier, and
   an isolation only when the day has no compound (each against `_reorderDay`'s first row on the same list); a sweep
   over every library row name pairs each with each other row of its pattern and checks `openerOf` equals
   `_reorderDay`'s first row; a day whose opener is removed takes `openerOf` of the admitted slots as its lead.
2. R1: a lead at rank 0 and one at rank 2 are each seated at 3 when they fit, at 2 when the clock, the lead's cap or
   (rank 0) the reservation refuses; no other slot is seated at 3 in pass A; seating the lead at 3 counts once against
   the day's target (a day at its target seats no extra row).
3. R2: with the lead at 3, an accessory below its weekly floor stops at 4 in pass C (not 3, not 5); a lead at 2 caps at
   3; a focus-group accessory in pass D passes the cap, and the same accessory in pass C does not; the lead itself is
   never capped.
4. R3: `worldIsWorse` directly: a day at exactly min(floor, M's rows) is not worse, one row fewer is; a thin day (M's
   rows under the floor) compares against M's rows, not the floor; a group at 0 that M trains is worse, a group M does
   not train is not (the loop reads M's groups, not the world's). Through `allocate`: L zeroing a group is not kept; C kept
   when L is worse and C is not; M when both are; for B, a fixture where A keeps L and both B worlds are worse sends the
   whole plan to M (A and B); B's baseline is main's B; `leadWorld` names each; the kept stats are the kept world's; the
   6-day path allocates B as A (a mutant that allocates B separately turns it red); after the whole-plan fallback A's
   stats are M's (a mutant keeping L's A stats while A's rows are M's turns it red).
5. R5: a lead refused its week-2 set holds an accessory and a hold to lead + 1; a focus row is not held; with the lead
   gaining, the accessory may gain too; a day whose opener is at rank 2 caps a rank-1 accessory against the opener, not
   rank 0, in week 1 and week 2 alike (the two leads agree).
6. Kill switch: OFF reproduces the OFF golden fixture byte for byte (`lead_first_kill_switch_golden_test.dart`, the
   Hive flag set to OFF).

Whole-engine (real `generateV4`):
- A new assertion test (`test/plan_generator/lead_first_gate_test.dart`): over the 1,010 golden personas, every day of
  every week has NO non-focus budgeted row at the lead's sets + 2 or more, the lead being `openerOf` over the day's
  budgeted rows, with no exception: hold-opened days are included (a hold is not budgeted, so it is never the lead or the
  row compared). Measured on the prototype: 0 such rows in z7051, both focus grids and phases 4-5. 1,232 day-weeks open
  with a hold, as on main. A day's first exercise equals the OFF world's whenever the OFF world's first exercise is still
  in the day; and the `leadWorld` counts over the golden personas are pinned. It fails on a wrong build; the audit
  numbers are a measurement.
- `generator_golden_test.dart` re-recorded (1,010 personas); every changed key is a 2A key (the OFF fixture equals main's
  hashes).
- `session_set_budget_gate_test.dart`: the lead-lift precondition, counters and overrun accounting re-read (section 4).
- The injury sweeps (`injury_floor_sweep_lib.dart`, `kThinCeilings`): an exact-equality ratchet (`expectNoThin`, `:354-362`,
  fails on a fall too). A block that falls is re-recorded with the measured value and the reason. (The build found
  three `f_repeat_pairs30` blocks rising through the repeat phase's pins, section 3: re-recorded with the cause.)
- `plan_audit_dump_test.dart` with no focus and both focus values, and phases 4-5: section 3's numbers.
- Timing: R3 runs the allocator twice per variant in the common case (L and M; four runs against today's two) and at most
  six per plan (A: M, L, C; B: M, L, C; the whole-plan fallback reuses M and M_B); `generateV4` over the golden personas
  timed before and after, recorded in the diagnose doc.

Mutations (each must redden at least one test; rule 21): R1's `baseSets` back to 2; R1 on rank 0 instead of the opener;
R1 without its count against the target; R2's `+ 1` removed and set to `+ 2`; R2's lead taken as rank 0 even when not
admitted; R2 applied in pass D; R3's floor term dropped, `min(floor, M rows)` replaced by `floor`, its zero-group term
dropped, the zero-group loop over the world's groups instead of M's, C's branch skipped, B compared with the chosen A's baseline, the whole-plan fallback replaced by main's B over
the chosen A, L's stats kept when M wins; `openerOf` returning the first compound in list order, `openerOf` with its own copy of the comparator changed, `openerOf`
fed every row including holds (a fixture where a hold would sort first); `reserved(3)` changed to `reserved(2)`; the lead
seat priced at 2 sets in its fits check; the reservation's `later` read from a later day's opener instead of its rank-0
slot (a fixture where they differ); B's L / C copying main's A days instead of the chosen A; the focus exemption dropped in
world C only (a focus fixture that keeps C); the gate's ratchet (if a limit is raised) removed; R5's lead taken as `ranked[d].first` (rank 0) instead of `openerOf`;
the allocator's fallback taken as the first admitted slot in rank order; the focus exemption applied in pass C as well;
`openerOf` with a different tie order from `_reorderDay` (the tied-rows test); R2's lead taken as rank 0 in world C only
(a fixture that keeps C with its opener not at rank 0); B's `copyFrom` given L's stats while A kept C (B's `countForced`
and `belowCount` must come from the kept A world); the explicit `leadFirst` argument ignored in favour of the flag (direct
tests, flag ON with argument false and flag OFF with argument true, for `allocate` and `apply`); R5's lead read from
`exercisesA` when `useB` (a week-2 fixture on a B list); a wrong `leadWorld` choice (the pinned golden counts). The main branch of R3
is never reached in any measured grid, so its mutants rest on the behavioral fixtures alone; R5 removed, R5 on
budgeted rows only (holds gain freely), R5 capping focus rows; the audit's focus skip removed; the kill switch's default
flipped. Equivalent, so not counted: R2 applied to the lead (`lead.sets + 1 <= lead.sets + 1`) and R2 in pass B.

The week-2 rows R5 refuses keep week 1's `weightCue` (existing behaviour for a refused row), and a week in which no row
gains carries `_waveNotes[0]` (`periodization_engine.dart:136`). The dump records neither, so the build counts both on
the golden personas, main against 2A (t399's 457 came from a superseded rule and is dropped).

## 6. Unit 2A: files

`session_set_allocator.dart` (R1-R3, `leadWorld`, the doc comment), `periodization_engine.dart` (R5, the optional
`leadFirst`, the doc comment), `sequencing_engine.dart` (`openerOf` and the comparator it shares with `_reorderDay`, whose output is unchanged),
`plan_engine_flags.dart` (the flag), `test/plan_generator/plan_audit/plan_audit_lib.dart` (the focus skip), the tests
above, `test/fixtures/generator_golden_hashes*.json`, `docs/sot_registry.yaml` (new concept `lead_first`, writers and
readers above, `behavioral_test_path`), `lib/shared/repositories/plan_engine/CLAUDE.md` (the session set budget item: "a
lead can end at 2 sets" replaced by the rule; titration / plateau's ±1 named as not re-capped),
`docs/architecture/plan-engine-detail.md`, `docs/naming_conventions.md` (`leadWorld`, `disable_lead_first`,
`openerOf`), diagnose doc `docs/diagnoses/2026-11-1x-generator-lead-first-<id>.md`, closure ledger
`docs/audit/generator-step2-2a.closure.yaml`, OI-486 closed in the merge (with d26 / d27 and the residue), OI-501 updated
(its lead and focus-cap findings closed by 2A; Calves to 2C). `plan_generator.dart` is not touched. Blast radius
`platform`.

## 7. Unit 2A: review and landing

Context-blind review rounds on this plan (2A only; 2B-2D get their own) until one converges, then the build, the full
gate loop and CI on the draft PR before the B-pass (CLAUDE.md 4.12.8), then `land_pr.sh`. Plan-review record
`docs/plan-reviews/generator-step2-allocator.md` (review_rounds >= 2, ground_truth_verified, converged, bpass accepted).
Board: t202 (reviews), t203 (build), t204 (re-run audit), t205 (code review and CI), t206 (merge) for 2A; 2B-2D add
their own cards when their plan sections are written.

## 8. Unit 2A: open questions, answered

- Per variant or per day: per variant, measured (no variant falls back to main in any grid; A falls to the capped world
  in 220 of 2,304 plans). A per-day fallback is not measured and not proposed.
- The lead when its slot is not admitted: `openerOf` over the admitted slots (as week 2); the gate's `firstLifts` keeps
  reading rank 0, so the two can differ on such a day (test 1; `leadSeats` reports the opener).
- Downstream readers: section 1 (titration and plateau rung 2 are OFF and not re-capped; the pairer and `shortenDay` see
  new set counts and times, and no new order, since the sequencer is unchanged).

## 9. Unit 2A: not in scope

Holds' sets (D-2A-3), the weekly minimums and quad floor (2C), thin days (2B), repeat minutes (2D), reps per goal
(step 3).

## 10. Unit 2B outline: the 3-exercise day floor (OI-452)

Input: 2A's tree. Founder direction (2026-11-03): a hard floor of 3 exercises per day; a day below it may exceed the
weekly band by a few sets, only for those days, with its own stats. Measured today on the injury grid (d16 / d17 / d23):
2,286 thin day-weeks and 94 one-exercise days over 46,512 runs; 30-minute thin days 520. The first attempt (restore slots
over the weekly top) broke `session_set_allocator_behavioral_test` (weekly top 16 -> 26) and the budget gate, so 2B
restates the weekly-top invariant with its exception before any code. Written on 2A's merged tree.

## 11. Unit 2C outline: weekly minimums and the quad floor

Inputs: d14 (zero-set weeks: Triceps 86, Core 52, Biceps 36, Calves 9 plans), OI-475 L2 (the credit rule) and L3 (a
quad hit on another day), OI-477 (6-day personas short of the Quads floor; Hamstrings counted too), OI-501 (Calves -4,628
and Core -2,022 sets under `glutes_legs`; inert focus in 722 / 977 plans at 30-45 minutes), d20's low-volume (1,740 ->
1,421 after 2A) and swing flags (402 -> 308 after 2A). Written on 2B's merged tree.

## 12. Unit 2D outline: repeat-phase minutes (OI-453)

Founder design (2026-11-03): keep the pinned compounds; when minutes rise, spend the spare time first on extra sets (up
to the per-session cap), then on appended accessories from the normal selector; a repeat with the same minutes stays
byte-identical. Written on 2C's merged tree.

## 13. Review log

**Round 1 (context-blind Sonnet, 2026-11-12): 2 P1, 6 P2, 6 P3, not converged; all folded into v2.**
- P1-1 week 2 re-created starved leads (t399: 66 week-1 days at lead + 2, 2,006 in week 2): R5 added (`_weekTwoGains`
  capped, holds included); every-week counts in section 3 (69 / 90 / 69).
- P1-2 "never worse than main" overstated: B's baseline is now main's B; section 3 states exactly what the fallback
  guarantees; weekly halvings (476), day-level group losses (389) and the 22 verdict regressions are in D-2A-2; a
  weekly-floor term was measured (u1935) and rejected.
- P2-1 residue composition and `leadWorld` counts in section 3 / D-2A-3. P2-2 the fewer-exercise breakdown corrected
  (5,002 one fewer, 104 two fewer, per level and transition). P2-3 focus numbers re-run on the chosen rule (v911). P2-4
  D-2A-1's numbers labelled by run (s143 / s135) and the days-above-lead counts added. P2-5 the lead defined once; R4 keyed
  on the first budgeted row (a hold no longer leads); u4 measures R4 alone; OI-486's stale OHP example noted. P2-6 readers
  traced in section 1 (titration / plateau, pairer, `shortenDay`, `firstLifts`), per-week totals in section 3.
- P3: pass B's cap dropped (it cannot bind); test 2's mirror uses a 3-set lead; tests for stats, B's baseline and week
  2 added; the count target and `reserved(3)`'s day-order bias stated in R1; the doc-comment change, the three flag reads
  and the OFF golden's Hive flag stated in section 3.

**Round 2 (fresh context-blind Sonnet, 2026-11-12): 2 P1, 3 P2, 6 P3, not converged.** P1-1 (11,938 days lose an
exercise; 6,832 are swaps R3 cannot see; r79's Back-day loss is in v911 too) and P1-2 (days over minutes 3,553 -> 5,607,
590 more than 10% over, all 30-minute) were put to the founder with the safe piece (w525) as the alternative; d26 took
the full fix with these costs, now stated in section 4 and the section 3 table. P2-1 R4 / R5 apply in every world, stated
with the consequence for R3's guarantee; tests force the main branch. P2-2 the eight existing test files and the label
behaviour listed in section 5. P2-3 the run count corrected (2 per variant usually, 7 per plan at most). P3: the
lead + 2 count's test named as wider than the audit's; the 838 leads at 2 attributed to time; equivalent mutants named
and a rank-0-removed mutant added; `shortenDay`'s tie order; cells falling to 2 sets or fewer (212 / 219 / 212); OI-486's 4-set clause
to step 3.

**Round 3 (fresh context-blind Sonnet, 2026-11-12): 2 P1, 4 P2, 9 P3, not converged.** P1-1 the sequencer change (R4) had
an unstated cost (8,704 days with a new first exercise, unilateral openers 374 -> 5,498, heavy lifts losing the opener):
R4 removed; the lead is now the sequencer's own opener (x2955 / y7051: 0 days change their first exercise, 789 suitable).
P1-2 the cap halved the physique focus's extra work: put to the founder, d27 exempts focus exercises (pass D, week 2,
the audit's lead check). P2-1 B's unchecked third branch: the whole plan falls back to main. P2-2 the decisions are
labelled again in section 4. P2-3 a whole-engine assertion test, the `min(floor, M rows)` / boundary / target / 6-day
fixtures and the opener tests added. P2-4 the leads still at 2 are stated as partly unexplained. P3: the consumers test
file name, the helpers file, 1,010 personas, the prototype reset before the build, both purity comments, the two flag
reads, the gate loosening named as founder-approved, the `:80` cite, the week-2 cue growth.

**Round 4 (fresh context-blind Sonnet, 2026-11-12): 0 P1, 6 P2, 8 P3, not converged.** P2-1 the leads still at 2 re-split
on y7051 (384 / 625). P2-2 the overrun stated against the gate's limit (0 -> 1,073 days beyond it); the corrected count put
to the founder: d26 stands (d28), the gate's limit raised for 30-minute plans. P2-3 main's focus dumps re-audited with the
focus skip (same dumps). P2-4 phases 4-5 measured (1,536 plans). P2-5 the priority-1 opener clause put to the founder and
dropped (d29). (Round 5 then made the gate's raise conditional: only for days the gate does not already excuse.) P2-6 "worse" is a pure function, tested directly. P3: 945 compound rows lost in week 1 named; one lead
definition (`openerOf` over admitted slots); the 28 regressions' causes; the other `apply` callers' tests; the
reservation's rank-0 wording; the whole-plan fallback stats case; R1-R3 / R5 labels; `openerOf` shares `_reorderDay`'s
comparator, with a library sweep.

**Round 5 (fresh context-blind Sonnet, 2026-11-13): 0 P1, 3 P2, 6 P3, not converged.** P2-1 the lead's fallback had three
definitions: the allocator now uses `openerOf` over its admitted slots, as week 2 does; re-measured as z7051 (5 plans and
12 days differ from y7051; phases 4-5: 21 plans, 42 days); every number in sections 2-4 re-taken from z7051. P2-2 the
gate: measured with its own accounting first, loosened (d28) only for days it does not already excuse, exact seconds, a
ratchet test. P2-3 the cross-variant zero-set weeks (Calves 5 -> 57 plans) stated, owned by 2C. P3: mutations added
(reservation, lead pricing, opener fed holds, B copying main's A, focus exemption in world C); a stable sort in the shared
comparator; d29's count is a lower bound; `physique_focus_bringup_test.dart` and the SoT range re-derivation named; the
other audit flags in the table; phases 4-5's week 4 (-6.5%); the `glutes_legs` regressions' causes.

**Round 6 (fresh context-blind Sonnet, 2026-11-13): 0 P1, 4 P2, 10 P3, not converged; no design finding.** P2-1 no new
dependency: `List.sort` kept, its stability named and pinned. P2-2 mutants for R5's lead at rank 0 and the rank-order
fallback, and a test with the opener at rank 2. P2-3 eleven more test files named, the list stated as a floor with the
build's grep, the loaded-wins OFF golden re-recorded. P2-4 `kThinCeilings` is exact equality: a fall is re-recorded. P3: a
measured example replaces OI-486's stale ones; section 6 matches section 3 on `_reorderDay`; the repeat phase, the week-2
note and the empty-day guard named; R1 never evicts a hold; the pass C focus mutant; phase 4-5 and focus overrun counts
and phase 4-5 set costs; the -2.46% base; the residue described exactly; `volume_titration.dart:163`; holds count in R3's
rows.

**Round 7 (fresh context-blind Sonnet, 2026-11-13): converged; 0 P1, 2 P2, 6 P3, no design finding.** P2-1 the
whole-engine assertion test has no hold exception (0 rows in every measured grid; 1,232 hold-opened day-weeks, as on
main). P2-2 the safe piece w525 carried the removed sequencer change (R4), so the cap alone with the opener as the lead
was measured (c6665, section 4, D-2A-1). P3: a per-opener stat (`leadSeats`) for the leads still at 2; R1's else-branch
is "handled exactly as on main"; the week-2 cue and note counted on the build (the 457 dropped); Core under
`glutes_legs` named for 2C; D-2A-3 points at x2955; the round-4 entry notes the conditional raise; five mutants added
(R2's lead in world C, B's stats copy, the `leadFirst` argument against the flag, R5's lead on a B list, `leadWorld`).
