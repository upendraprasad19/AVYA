# OI-166 Unit 2 — plan review round 1 (two context-blind reviewers)

**Date:** 2026-09-09 · **Plan:** `docs/audit/oi166-unit2-plan.md`
**Verdicts:** design reviewer **not-converged** · ground-truth reviewer **not-verified**

Two agents, no conversation context: one on design feasibility, one on ground truth. Every finding
below was re-verified against source by the author before being accepted — none is taken on the
reviewer's word.

---

## P0 — the builder as specified CANNOT express what caller C already does

**The single blocking finding.** The plan's `buildScheduleRows(...)` has **no weeks parameter**, and
`ScheduleRow.week` is documented "1..4, plan-relative". But C (`RegeneratePlanPlanner`) writes
**1..12** weeks today:

- `regenerate_plan_planner.dart:143` — `final n = weeks.clamp(1, 12);`
- `:211` — `for (var weekIdx = 0; weekIdx < n; weekIdx++)`
- `:278` — `'week': weekIdx + 1`

This is not a latent path. It is a **live server contract**, exercised by two tools:

- `supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts:5` — `z.number().int().min(1).max(12)`
- `supabase/functions/_shared/tools/plan/switchGoal.ts:14` — same bound

And C already has DEFINED behaviour beyond week 4 that the plan never captured —
`regenerate_plan_planner.dart:211-213`: *"PlanGenerator returns 4 weekPlans per phase. For weeks
beyond the 4th, repeat the last week."*

**Consequence:** step 4 (wire C to the shared builder) as written would be a REGRESSION, not a
de-duplication — a coach request for 8 or 12 weeks has no expressible path through the builder.

**The plan also contradicts itself**, which is the tell that should have been caught before dispatch:
§7 commits to testing "`rawWeek` 1..4 **and >4**" while §8 lists **OI-175 (`rawWeek > 4` semantics,
founder Q5)** as explicitly out of scope. The test plan promises to exercise the behaviour the
exclusions section says is undecided.

## P1 — `currentWaveCharacters()[3]` can RangeError on the cold-launch path

§4 step 1 says to read `currentWaveCharacters()[3]` literally. That method is documented crash-safe
and returns `const []` for a missing/short/malformed blob (`workout_schedule_read_service.dart:1330-1338`),
so a bare `[3]` throws.

The code being REPLACED already guards this — `deload_evaluator.dart:242`:
`if (weeks is List && weeks.length >= 4 && weeks[3] is Map)`. So the plan is strictly worse than the
status quo for the short-blob case: a guard-without-its-mirror regression introduced by the fix.
The sibling method guards identically at `:1317`.

Fix: `final waves = currentWaveCharacters(); final w4 = waves.length > 3 ? waves[3] : null;` and a
test for the short-blob case at the CALLER, which §7 currently scopes only to the pure builder.

## P1 — the blast-radius header contradicts the plan's own design

Header says "expected `account`" and names `lib/core/services/sync/**` as the only elevator. But
§2 P1-3 puts the `liftExerciseFromStash` extraction "in the plan-engine layer", and
`docs/blast_radius.yaml:67` pins `lib/shared/repositories/plan_engine/** → platform` — declared
early, and the file states first-match-wins (`:14`). So the design as written measures `platform`,
pulling in the `feature_flag` requirement.

⚠ This is a VARIANT OF THE EXACT MISTAKE the header warns about two paragraphs above it. Unit 1's
header justified `account` with a control that its own scope later invalidated; this header names
one elevator and its own design walks into a different one.

**Resolution: do not put it in the plan-engine layer.** `_liftExercise` is deload-domain logic, not
plan-generation logic — its natural home is `lib/core/services/` (account), where
`deload_evaluator.dart` already lives. Putting it under `plan_engine/` would be wrong-domain AND
tier-elevating. A small pure file imported by both keeps the builder's purity claim intact.

## P2 — C never touches `plan_start_date` / `plan_end_date`, and the plan is silent

`tool_dispatcher.dart`'s `_executeRegeneratePlanBlock` writes neither key, while A and B both stamp
them (`workout_schedule_read_service.dart:225-226`, `:385-386`). §6 discusses only the DELETE range
for `switch_goal`. Once C can write weeks 5-12, rows exist beyond a `plan_end_date` that no longer
describes them. Must be either explicitly out of scope (byte-identical to today) or specified.

## P2 — the inventory carries a claim Unit 1 already falsified

`docs/audit/oi166-regen-implementation-inventory.md` still says `template_service.dart:115-120`
"re-derives the week number inline". It does not — Unit 1 replaced it with the shared
`rawWeekNumberFor`, and the code carries an explicit comment saying so
(`template_service.dart:113-125`). The plan itself is not fooled (it lists the extraction under
"What Unit 1 already shipped"), but the inventory would mislead anyone reading it standalone.

## P3 — two stale line citations in the inventory

- `workout_name` for B cited at `:478`; actually `:477`.
- the `['warmup']` positive control cited at `template_service.dart:189`; actually `:193`
  (the COUNT, 3, is correct).

---

## What both reviewers independently confirmed as correct

- Every plan citation resolved exactly: `workout_schedule_read_service.dart:252`,
  `deload_evaluator.dart:206-216`/`:223`/`:264`/`:294`, `regenerate_plan_planner.dart:250`/`:266`/
  `:274`/`:291-293`, `periodization_engine.dart:164`, `currentWaveCharacters` `:1330`.
- The §3 `finisher` finding, all four parts, with a working positive control (`['warmup']` → 3 at
  `template_service.dart:193`, `train_provider.dart:629`, `:792`; `['finisher']` → 0).
- The "15 differences, 7 legitimate" arithmetic (17 rows − 2 withdrawn = 15; 8 DRIFT + 7 SEAM).
  11 of 15 rows spot-checked against real code, all correct.
- **No fourth phase-layout builder exists** — the gate's own heuristic re-run repo-wide in both
  literal and index-assignment forms matches exactly the three allowlisted files.
- All five carried-forward P1s verified against source.
- `disable_shared_schedule_builder` and `schedule_row_builder.dart` confirmed not to exist yet.
- `RegeneratePlanDay`'s required fields ARE all derivable from the proposed `ScheduleRow` — P1-4's
  answer holds, independent of the P0.
- The one-flag sequencing concern is NOT a real exposure: §5's one-branch/one-push decision means
  the partial-wiring state never exists in a shipped build.

## Author's read

The P0 is a scope error, not a citation error — it says the unit as drawn is the wrong shape,
because C is not "A/B with different side effects". C has a capability A and B do not: variable
1..12-week blocks with a defined repeat-last-weekPlan rule. That was never in the plan.

§4.12.1's remedy for this is to split and ship the smallest converged piece, not to run another
round on the same scope. The scope question is a founder decision because it changes what ships
before the APK, so it goes to them rather than being resolved here.
