---
adr_id: 0014
title: Canonical FitnessGoals source-of-truth for goal-derived targets, training, and cardio
status: accepted
date: 2026-06-07
deciders: Upendra
---

# ADR-0014: Canonical FitnessGoals source-of-truth

## Context

Fitness goal tokens (`user_profile.primary_goal`) were **stringly-typed with no
source of truth**. The same token had to be independently handled in
`BmrCalculator` (calorie/protein/fat), `SplitResolver` (training split),
`CardioFinisher` (cardio on/off), and four display readers — each with its own
`switch (goal) { … default: … }`.

This bit hard (audit F19, 2026-06-07): the onboarding flow added a **`recompose`**
token (the *pre-selected default* goal) to `plan_screen._mapGoal`, but never to
those consumers. So `'recompose'` silently hit every `default` — maintenance
calories + the lowest protein (1.6 g/kg) + the fat-loss split. The default goal
gave every tap-through user the *opposite* of a recomposition.

## Decision

Introduce **one canonical `FitnessGoals` source-of-truth**
(`lib/core/constants/fitness_goals.dart`): a const map keyed by token, each row
`{label, deltaMult, proteinPerKg, fatPercentage, planGoal, cardio}`. Every
consumer reads from it:

- `BmrCalculator` — `dailyCalories = tdee + deltaMult × paceDelta`; protein/fat
  from the spec (no goal `switch`).
- `PlanGenerator` — `planGoal` drives split + exercise selection (so the plan
  engine only ever sees `build_muscle` / `lose_fat` / `strength` /
  `general_fitness`; `recompose.planGoal = build_muscle`), `cardio` gates the
  finisher.
- Display readers — render `FitnessGoals.label(token)` via their `default`.

`FitnessGoals.of(unknown)` asserts in debug and falls back to `general_fitness`
in release. A gate (`scripts/check_goal_token_exhaustiveness.dart`) forces every
onboarding card key + every consumer to line up, so a token can never fall
through a `default` again. Recompose becomes a real first-class profile (modest
deficit `deltaMult -0.5`, protein 2.0, hypertrophy split, light cardio), and the
default onboarding goal switches to **Build** (wedge-thesis aligned).

## Alternatives considered

1. **Alias `recompose` → `lose_fat`.** Rejected — a cut is not a recomp (full
   deficit, no muscle-priority training). Recomp deserves its own profile.
2. **Add a `case 'recompose':` to each of the existing switches.** Rejected — it
   fixes this one token but the *next* new goal silently falls through again; it
   doesn't remove the drift class.
3. **A `FitnessGoal` enum with exhaustive `switch`es (no config map).** Rejected —
   Dart exhaustiveness on an enum helps the calculator, but the numbers (deltas,
   protein) would still live in N places. A single data map keeps every per-goal
   number in one row.

## Consequences

Good:
- Changing a goal's calories/protein/split/cardio is a **one-row edit**.
- Adding a goal is one row; the gate then forces every consumer + onboarding key
  to handle it — no silent `default` fallthrough.
- The plan engine never sees non-archetype tokens (recompose maps to its
  `planGoal`), so `split_resolver.dart` needed no change.

Bad / watch:
- The exhaustiveness gate's regexes key off specific files
  (`bmr_calculator.dart`, `plan_generator.dart`, `cardio_finisher.dart`,
  `goal_screen.dart`, `plan_screen._mapGoal`). If those move, update the gate.
- Touches `plan_generator.dart` (rule 14 — authorized by the approved batch plan).

## Status

Active. Shipped 2026-06-07 (audit-remediation Batch 1). Brainstorm-locked with
the founder (default → Build; first-class recomp profile; canonical SoT + gate).

## See also

- `lib/core/constants/fitness_goals.dart` (the SoT)
- `scripts/check_goal_token_exhaustiveness.dart` (the gate)
- `test/contracts/recompose_goal_targets_test.dart` (behavioral pin)
- `docs/diagnoses/2026-06-07-recompose-default-maintenance-f19a7c.md` (F19)
- ADR-0009 (plan-generator V4 local Dart)
