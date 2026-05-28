---
adr_id: 0009
title: Plan generator V4 — local Dart, no AI inference
status: accepted
date: 2026-04-30
deciders: Upendra
---

# ADR-0009: Plan generator V4 — local Dart, no AI inference

## Context

Every user gets a personalized 12-phase training plan generated from
their profile (goal, experience, days/week, equipment access, body
metrics, injuries, etc.). The plan generation runs on the user's
device after onboarding and on every phase advance.

Two architectural options:
1. **AI-generated** — call an LLM (Gemini / Claude / GPT) with the
   user profile and ask for a structured workout plan.
2. **Local rule-based** — deterministic Dart code that queries the
   on-device `exercise_library` Hive box and assembles a plan.

The plan must:
- Run offline (Hive-first ADR-0001).
- Be free (no per-user inference cost at our ₹349/mo PRO price).
- Be deterministic (a user re-running the generator with the same
  profile gets the same plan; supports regression testing).
- Cover 4 archetypes (Hypertrophy / Strength / Endurance /
  Athletic) × experience levels × equipment access × injury
  modifications.

## Decision

**Plan generator V4 is local Dart code** living at
`lib/shared/repositories/plan_engine/`. It queries the Hive
`exerciseBox` (1.4K+ exercises with tags) and assembles plans via
explicit rules.

The pipeline:
1. **Archetype selection** from goal + body metrics.
2. **Phase ladder** (12 phases, each 2-4 weeks, progressive
   intensity).
3. **Exercise selection** per phase via tag-match queries against
   `exercise_library`.
4. **Set/rep/RIR prescription** by archetype + phase + experience.
5. **Constraint resolution** (equipment, injuries, time budget).

Encoded in CLAUDE.md rule 8 + rule 14.

**Never modify `plan_generator.dart` without explicit instruction**
(CLAUDE.md rule 14). The file is load-bearing.

## Alternatives considered

1. **Server-side AI generation (Gemini / Claude).** Rejected.
   - Per-user inference cost. At PRO ₹349/mo and target 30%+
     gross-margin, every paid feature's marginal cost matters.
     A monthly regeneration × 1000 users × Gemini Flash pricing is
     real money.
   - Non-deterministic — the same user gets different plans on
     re-run. Hard to regression-test.
   - Requires network at plan-generation time. Violates Hive-first
     (ADR-0001).
   - Prompt drift over time would change plans for the same user;
     bad UX.

2. **Hand-curated plan templates.** Rejected.
   - Combinatorial explosion: 4 archetypes × 3 experience levels
     × 4 equipment tiers × N injury modifications = hundreds of
     hand-curated plans.
   - Not personalized — same template for users with different body
     metrics.

3. **Hybrid: AI for initial, local for adjustments.** Rejected at
   this time.
   - Still hits the cost + determinism issues at initial generation.
   - Mental model split ("when does it call AI?") adds complexity.

4. **Open-source plan engines (Fitbod-style rule engine).** Not
   found at suitable license / quality at decision time. Building
   our own keeps it tunable to the wedge thesis ("Become a Lt"
   muscle-gain track).

## Consequences

Good:
- **Zero marginal inference cost** per plan generation.
- **Offline-capable.** New device, no network → plan still
  generates as soon as exercise_library restore completes.
- **Deterministic.** Same input → same plan. Regression-testable.
- **Tunable.** When founder observes "Phase 5 reps too high for
  beginners," it's a parameter change in code, not a prompt-engineering
  exercise.

Bad:
- **All complexity in code, not prompts.** ~2K lines of Dart in the
  plan engine. Adding a new archetype = code change + tests, not
  just a prompt tweak.
- **Tag-quality dependency.** Plan quality depends on
  `exercise_library` tag completeness. If `pull_compound` tag isn't
  applied to lat-pulldown, the engine misses it. Curation is
  ongoing.
- **No conversational planning UX.** A user can't say "I'm injured,
  swap leg day for upper body" mid-flow; they go through onboarding
  re-entry or use AI Coach's swap-exercise tool to mutate.
  Acceptable tradeoff.
- **Won't beat a top-tier LLM at edge cases.** A 90th-percentile
  weird user profile (e.g., powerlifter with a torn rotator cuff
  training for a Spartan race) will get a less-tuned plan than
  Gemini might produce.

## Status

Active. V4 has been stable since 2026-04-30. **No modifications
without explicit instruction** (CLAUDE.md rule 14) — the engine has
many small heuristics that interact non-obviously, and ad-hoc
"improvements" have historically regressed other archetypes.

## See also

- CLAUDE.md rule 8 (local plan generator)
- CLAUDE.md rule 14 (don't modify without instruction)
- `lib/shared/repositories/plan_engine/CLAUDE.md`
- `project_plan_generator_v3.md` — V3 retrospective; V4 details in
  CLAUDE.md §12
- ADR-0001 (Hive-first) — why local generation is required
