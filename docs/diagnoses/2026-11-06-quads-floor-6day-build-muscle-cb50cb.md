---
bug_id: cb50cb
date: 2026-11-06
batch: oi454-quads
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Intermediate build_muscle, full_gym, 6 days, 90 minutes trained Quads 8 weekly sets against a band of 12 to 16 (floor 12).
  Legs A held the only quad work (Barbell Back Squat, Leg Extension); Legs B (Hamstring + glute focus) had none. Glutes sat at
  16, their weekly top, and the allocator reported Hamstrings co_group_limited. Measured over 6-day build_muscle at 90 minutes
  before the fix: Quads 2 (beginner, three tiers) / 6 (beginner full gym), 5 / 5 / 3 / 8 (intermediate) and 5 / 5 / 3 / 8
  (advanced) for bodyweight / dumbbells / basic gym / full gym.
concept: quad_primary_glute_credit
sot_registry_entry: |
  quad_primary_glute_credit (docs/sot_registry.yaml) - added in this batch; behavioral test test/contracts/quads_floor_6day_behavioral_test.dart.
related_bugs: [d3b7f1]
recurrence: |
  NOT a recurrence of a recorded bug. It is the SBF-QUADS-FLOOR row of the set-budget flip (plan-engine-detail (d), measured
  2026-11-02 and left blocked on the founder). The nearest entry, d3b7f1 (rest by exercise type skewed the exercise counts),
  is the allocator's earlier count fix and does not touch which group refuses a set.
writers:
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "_get6DayV4 build_muscle Legs B (selected through SplitResolver.hasQuadLegsBSplit): the Glutes / hip_isolation slot became Quads / knee_dominant / compound, priority 2", line: 1004 }
  - { file: lib/shared/repositories/plan_engine/budget_muscle_groups.dart, method_or_widget: "creditedOf: drops Glutes from an exercise whose first listed muscle is Quads when quadPrimaryCreditsGlutes is false", line: 71 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4 SessionBudgetContext(quadPrimaryCreditsGlutes: false for build_muscle at 6 days)", line: 289 }
readers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_groupsOf -> BudgetLedger.fits / add (a set is refused when any credited group is at its top or cap)", line: 192 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "apply week-2 ledger credit", line: 174 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted groupsOf", line: 189 }
hive_key_prefix: "schedule_<date>.exercises[] (workoutBox); plan_json.workouts[].exercises (the plan blob)"
hive_key_formula: "PlannedExercise.sets -> WorkoutDay.toMap exercises[].sets"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); sets and names pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged)"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers (wrapUserScopedBox)."
forbidden_patterns_checked:
  - { pattern: "the Glutes-credit rule applied to a split other than 6-day build_muscle (a global rule changed 745 of 999 golden keys)", absent: true }
  - { pattern: "BudgetMuscleGroups.of used for an exercise's ledger credit in the allocator, apply or titration (must be creditedOf)", absent: true }
proposed_fix: |
  Cause (measured): Legs B had no quad slot, and a quad slot alone changes nothing because the allocator refuses a set when ANY
  group the exercise credits is at its weekly top or session cap (BudgetLedger.fits) and a squat, lunge or leg press lists
  ['Quads', 'Glutes']: Glutes (filled by Deadlift, Romanian Deadlift and Glute Bridge) is at its top, so the quad work is
  dropped (the 2026-11-03 spike). Replacing the glute isolation slot alone lifted Quads only to 9 to 12.
  Fix, the founder's option (a) in one batch: (D1) Legs B swaps Glutes / hip_isolation (priority 2) for Quads / knee_dominant /
  compound (priority 2), still 8 slots; (D2) a co-group policy, `SessionBudgetContext.quadPrimaryCreditsGlutes` (default true),
  false for planGoal build_muscle with 6 days only: `BudgetMuscleGroups.creditedOf` drops Glutes from an exercise whose FIRST
  listed muscle is Quads, so the Glutes top and cap do not refuse it. The allocator, PeriodizationEngine.apply (week 2) and
  VolumeTitration build their ledger credit through that one function so they agree. A global rule was prototyped first and
  rejected: 745 of 999 golden keys changed, far outside the OI's 6-day build_muscle scope.
  Result, week 1, 90 minutes: founder case Quads 8 -> 12, Glutes 16 -> 13 (credited), Hamstrings 11 -> 12. By level and tier
  (bodyweight / dumbbells / basic gym / full gym): beginner 2 / 2 / 2 / 6 -> 10 / 10 / 10 / 10 (floor 10, met), intermediate
  5 / 5 / 3 / 8 -> 12 / 12 / 10 / 12 (floor 12; basic gym cap_limited), advanced 5 / 5 / 3 / 8 -> 12 / 13 / 9 / 12 (floor 14; the
  90-minute day is full).
  STATED COST: the glute work a squat does no longer counts toward the Glutes band in this split. A beginner's glute volume
  counting every listed muscle in full reads about 21 sets (bodyweight, 60 minutes) against a credited top of 12; the credited
  figure stays in band. In the founder case, counting every listed muscle in full, Glutes read 22 (Back Squat 5 + 4, Deadlift 4 + 3, Romanian Deadlift 3, Glute Bridge 3) against a credited 13 and a top of 16. The alternative, partial glute credit, needs a half-set ledger and would touch every plan.
  RESIDUE, stated: (1) the OI's clause "the other 6-day build_muscle personas reach the floor" is only PARTLY met: at 90
  minutes 5 of 12 personas are short and at the 60-minute default 9 of 12, each with its allocator label: intermediate basic
  gym 10 of 12 `cap_limited` (the squat holds the 5-set per-exercise maximum on both leg days), advanced bodyweight 12 of 14
  `co_group_limited` (Lateral Lunge, Sumo Squat and Curtsey Squat list another muscle before Quads and so keep crediting
  Glutes), advanced dumbbells 13, basic gym 9 and full gym 12 of 14 `time_limited` (the 90-minute day is full; no minutes were
  added); the labels are pinned at 90 minutes in the sweep. Filed as OI-477. (2) The rule is "first listed muscle is Quads and
  the exercise does not also credit Hamstrings": 77 library rows list Quads first with Glutes, 7 list Quads and Glutes with
  another muscle first (Box Squat, Lateral Lunge, Sumo Squat, Cossack Squat, Weighted Cossack Squats, Curtsey Squat, Skater
  Hops) and keep crediting Glutes; Trap Bar Deadlift (Quads first, Hamstrings listed, hip_dominant) keeps its Glutes credit
  on purpose (review #1: the heaviest glute lift in the pool must not escape the Glutes top). (3) A knee-injured user: no
  library row matching the new slot (66 knee_dominant compound Quads-target rows) is knee-safe, while 11 of 12 glute
  isolation rows were, so the slot resolves through the cascade's broader attempts to a knee-safe knee_dominant row and Legs
  B loses its glute isolation for that user; the 6-day injury sweeps and `kThinCeilings` did not move and the new knee test
  pins no knee-tagged exercise and at least 3 exercises on Legs B. (4) The Legs B quad slot can resolve to the same squat as
  Legs A (frequency, as Push A / Push B). (5) A repeat phase replays a pre-change plan's pinned names by day index, so an
  old Legs B (no quad exercise) is repeated until a fresh advance. (6) 3, 4 and 5-day build_muscle plans have their own Quads
  shortfalls with different causes, OI-475. (7) The generated snapshots `test/plan_generator/sample_plans_output.md`,
  `v4_diagnostic_output.md` and `session_set_budget_report.md` still show the old Legs B (they are regenerated by their own
  tools, not by the suite).
contract_test_path: test/contracts/quads_floor_6day_behavioral_test.dart
regression_test_planned: |
  - test/contracts/quads_floor_6day_behavioral_test.dart (13 tests, real generateV4, production path with the core-list pool
    OFF): (D1) the slot and the credit flag share one predicate (`selectV4` returns a `Legs B` day exactly when
    `SplitResolver.hasQuadLegsBSplit` is true, over 4 goals x 4 day counts x 3 levels), Legs B carries exactly one Quads
    knee_dominant compound slot at priority 2 and no Glutes hip_isolation slot and still 8 slots, Legs A and the default
    PPL keep their glute isolation slot; (D2) the `creditedOf` truth table (squat, lunge, a leading Adductors or Glute
    Medius token, a hip hinge listing Hamstrings, empty and quad-only lists, the focus mapper unchanged), named library rows
    (the squat and lunge family drops Glutes, the 7 not-quad-first rows, the hinges and the glute lifts keep it), the
    context default; the generated plan: the founder case weeks 1 to 3 (Quads 12 to 16, credited Glutes 12 to 16,
    Hamstrings 12 to 16, a knee_dominant quad-first exercise on Legs B), a 24-persona sweep (3 levels x 4 tiers x {60, 90}
    minutes) that pins Quads at or above the measured figure and above the old one, credited Glutes at the level floor,
    Hamstrings not below the old figure, every group under its credited weekly top and session cap in all four weeks, every
    day inside its minutes, and the allocator's label for each Quads shortfall at 90 minutes; phases 2 to 5 (lighter
    phase 4, a beginner budgeted as advanced at 5) for tops, caps, minutes and the slot; a glutes body focus (cap 12, top
    25); the `recompose` goal at 6 days; a knee-injured 6-day plan (no knee-tagged exercise, Legs B at least 3 exercises);
    a control over 8 plan shapes (every shape must hold a squat or lunge) that the allocator's Glutes ledger equals the
    full count everywhere except 6-day build_muscle and 6-day recompose, where it equals the count under the rule.
  - test/contracts/quads_credit_flag_consumers_test.dart (4 tests, crafted rows): the same input under both flag values for
    the allocator (Quads 4 vs 16), a quad-first row listing Hamstrings that keeps its Glutes credit, PeriodizationEngine.apply
    week 2 (no gain vs gain) and VolumeTitration (leg press vs squat).
  - the gate oracle in test/plan_generator/session_set_budget_gate_test.dart restates the rule (`_credited`); before the
    restatement its caps zero failed on 6 tests (Glutes counted in full), which is the evidence it reads the rule.
  - SCORECARD AND THIN DAYS: `scorecard_gate_test.dart` and the injury sweeps (`kThinCeilings`, exact in both directions)
    were run on the changed tree and PASS without a re-freeze, so no baseline or ceiling moved.
  - NO RUNTIME FLAG (root CLAUDE.md 4.6, the platform tier lists `feature_flag`): like OI-458 this ships always on. The
    revert is two lines (the `quadPrimaryCreditsGlutes` argument in `generateV4`, which is the negation of
    `SplitResolver.hasQuadLegsBSplit`, and the Legs B slot), both pinned by the predicate test, and the B-pass is the
    reviewer of that choice. A plan already on a tester device is not changed until it regenerates or advances a phase.
  MUTATION PROOF (final tree, the two new test files asserted GREEN first in the same run, every anchor confirmed present
  exactly once, a compile error counted as NOT a kill, the source tree compared byte for byte with a snapshot afterwards):
  20 mutants, 20 red, 0 survived (tests red in brackets). P1 policy off (4); P2 predicate true for every build_muscle day
  count (2); P3 predicate true for every goal at 6 days (2); P4 predicate always false (5); S1 the Legs B glute isolation slot
  restored (6); S2 the quad slot at priority 3 (1); S3 the quad slot an isolation (2); B1 creditedOf flag inverted (10); B2
  drops Glutes whenever Quads is listed anywhere (3); B3 drops Calves instead of Glutes (10); B4 first-muscle check and flag
  dropped (5); B5 hip-hinge guard removed, Trap Bar Deadlift loses Glutes (3); H1 the Legs B hamstring curl slot removed,
  caught by the Hamstrings sweep (3); G1 the Legs A glute isolation slot removed, caught by the Glutes floor (2); L1 the
  `time_limited` label renamed, caught by the label pin (1); B6 creditedOf skips an unmapped leading token (3); C1 context
  default false (1); A1 allocator ignores the flag (6); W1 PeriodizationEngine.apply ignores the flag (1); T1 VolumeTitration
  ignores the flag (1). Not mutated, stated: the gate oracle's restatement (`_credited`): the evidence is that the gate's
  caps zero failed on 6 tests before it was restated and passed after; and the generator golden, which covers the slot and
  the flag at the byte level but was not part of the mutation loop. The review-1 edit to
  session_set_budget_wiring_test.dart (a credit-aware helper) is NOT a catch: that test passes with and without it.
impact_analysis: |
  MEASURED, same personas before / after: see proposed_fix. GOLDEN: test/fixtures/generator_golden_hashes.json re-recorded,
  60 of 999 keys changed, every one `grid|<tier>|build_muscle|6d|<level>|p<phase>` (4 tiers x 3 levels x 5 phases); no other
  goal, no 3 / 4 / 5-day plan. The key list is at the end of this document.
  Existing plans on tester devices are not regenerated; only new generations and phase advances carry the change (testers
  only, root CLAUDE.md section 1).
  Value semantics (4.1.5.3): no stored value changes meaning (names, sets and reps keep their shape). Swept lib/, test/ and
  supabase/functions/ for BudgetMuscleGroups.of / Legs B / "Hamstring + glute": only the three ledger sites, the gate oracle
  and the split tests; no Edge Function reads a day's exercise list.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "split_resolver.dart Legs B slot, budget_muscle_groups.dart creditedOf, session_budget.dart flag, the three ledger sites, plan_generator.dart one argument; mutation table in regression_test_planned." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "generation only; no Hive key or box layout changes, the stored plan keeps its shape." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no column, migration or Edge Function touched." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "the symptom was reproduced with the real PlanGenerator.generateV4 over the shipped library; no cloud read or write." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the plan push passes sets and names through untouched (user_progress.plan_json); no server reader of a day's exercise list." }
---

# Quads below their weekly floor in the 6-day build_muscle plan (OI-454)

## What the founder saw
The founder case (intermediate, full gym, 6 days, 90 minutes) trained Quads 8 weekly sets against a floor of 12.

## Cause (writers and readers by file:line)
See `writers:` / `readers:` and `proposed_fix`. One sentence: Legs B had no quad exercise, and a quad exercise lists Glutes
too, so the allocator refused it while Glutes sat at its weekly top.

## What was proven and what was not
- Proven: the table in `proposed_fix`, measured on the real generator before and after; 20 mutants of the new code (below).
- Measured, not fixed: the 6-day personas still short (OI-477), the 3 / 4 / 5-day splits (OI-475).
- NOT done: a device check of a 6-day plan (the founder's next build).

## Process
Plan `docs/plans/2026-11-06-oi454-quads-floor.md`, record `docs/plan-reviews/oi454-quads.md`. The earlier row SBF-QUADS-FLOOR (`docs/audit/set-budget-flip.closure.yaml`, blocked_on_user) is resolved here; one fix, so no new closure ledger (rule 4.2 asks for one from four items).

## Golden keys re-recorded (60 of 999; all 6-day build_muscle grid keys)

`test/fixtures/generator_golden_hashes.json`, re-recorded with `RECORD_GENERATOR_GOLDEN=1`:

```
grid|basic_gym|build_muscle|6d|advanced|p1
grid|basic_gym|build_muscle|6d|advanced|p2
grid|basic_gym|build_muscle|6d|advanced|p3
grid|basic_gym|build_muscle|6d|advanced|p4
grid|basic_gym|build_muscle|6d|advanced|p5
grid|basic_gym|build_muscle|6d|beginner|p1
grid|basic_gym|build_muscle|6d|beginner|p2
grid|basic_gym|build_muscle|6d|beginner|p3
grid|basic_gym|build_muscle|6d|beginner|p4
grid|basic_gym|build_muscle|6d|beginner|p5
grid|basic_gym|build_muscle|6d|intermediate|p1
grid|basic_gym|build_muscle|6d|intermediate|p2
grid|basic_gym|build_muscle|6d|intermediate|p3
grid|basic_gym|build_muscle|6d|intermediate|p4
grid|basic_gym|build_muscle|6d|intermediate|p5
grid|bodyweight|build_muscle|6d|advanced|p1
grid|bodyweight|build_muscle|6d|advanced|p2
grid|bodyweight|build_muscle|6d|advanced|p3
grid|bodyweight|build_muscle|6d|advanced|p4
grid|bodyweight|build_muscle|6d|advanced|p5
grid|bodyweight|build_muscle|6d|beginner|p1
grid|bodyweight|build_muscle|6d|beginner|p2
grid|bodyweight|build_muscle|6d|beginner|p3
grid|bodyweight|build_muscle|6d|beginner|p4
grid|bodyweight|build_muscle|6d|beginner|p5
grid|bodyweight|build_muscle|6d|intermediate|p1
grid|bodyweight|build_muscle|6d|intermediate|p2
grid|bodyweight|build_muscle|6d|intermediate|p3
grid|bodyweight|build_muscle|6d|intermediate|p4
grid|bodyweight|build_muscle|6d|intermediate|p5
grid|full_gym|build_muscle|6d|advanced|p1
grid|full_gym|build_muscle|6d|advanced|p2
grid|full_gym|build_muscle|6d|advanced|p3
grid|full_gym|build_muscle|6d|advanced|p4
grid|full_gym|build_muscle|6d|advanced|p5
grid|full_gym|build_muscle|6d|beginner|p1
grid|full_gym|build_muscle|6d|beginner|p2
grid|full_gym|build_muscle|6d|beginner|p3
grid|full_gym|build_muscle|6d|beginner|p4
grid|full_gym|build_muscle|6d|beginner|p5
grid|full_gym|build_muscle|6d|intermediate|p1
grid|full_gym|build_muscle|6d|intermediate|p2
grid|full_gym|build_muscle|6d|intermediate|p3
grid|full_gym|build_muscle|6d|intermediate|p4
grid|full_gym|build_muscle|6d|intermediate|p5
grid|home_dumbbells|build_muscle|6d|advanced|p1
grid|home_dumbbells|build_muscle|6d|advanced|p2
grid|home_dumbbells|build_muscle|6d|advanced|p3
grid|home_dumbbells|build_muscle|6d|advanced|p4
grid|home_dumbbells|build_muscle|6d|advanced|p5
grid|home_dumbbells|build_muscle|6d|beginner|p1
grid|home_dumbbells|build_muscle|6d|beginner|p2
grid|home_dumbbells|build_muscle|6d|beginner|p3
grid|home_dumbbells|build_muscle|6d|beginner|p4
grid|home_dumbbells|build_muscle|6d|beginner|p5
grid|home_dumbbells|build_muscle|6d|intermediate|p1
grid|home_dumbbells|build_muscle|6d|intermediate|p2
grid|home_dumbbells|build_muscle|6d|intermediate|p3
grid|home_dumbbells|build_muscle|6d|intermediate|p4
grid|home_dumbbells|build_muscle|6d|intermediate|p5
```
