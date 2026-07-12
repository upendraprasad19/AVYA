---
review: coach-phase-stamp B-pass (item ② + COACH-1)
branch: coach-phase-stamp
date: 2026-07-12
reviewer: context-blind adversarial subagent (B-pass, §4.3)
blast_radius: account
verdict: accepted
---

# B-pass — coach plan-generation phase demotion + phase row-stamp (9c3e7a)

Context-blind adversarial review of the diff (`regenerate_plan_planner.dart`,
`hotel_workout_planner.dart`, `coach_regen_phase_stamp_behavioral_test.dart`).
Verdict: **ACCEPTED — no material issues.** Every angle verified against live code
+ the live DB schema:

1. **Item ② functional fix — CORRECT.** `generate(phase: resolvedPhase)`
   (regenerate_plan_planner.dart:189) compiles against `generate({int phase = 1})`
   and threads to `generateV4 → effectiveLevel + _getPhaseMeta`. High phase numbers
   already exercised in prod (graduation `phase: nextPhase`).
2. **COACH-1 stamp persists END-TO-END — CONFIRMED (highest-risk gap).** Traced past
   the planner: `_executeRegeneratePlanBlock`/`_executeSwitchGoal`/`_executeGenerateHotelWorkout`
   pass `entry: Map.from(schedule)` (the whole map) → `upsertScheduled` writes
   `{...entry, ...}` (workout_write_service.dart:549), so `phase` reaches the Hive row.
3. **switchGoal covered for free** — shares the same planner sink; no separate path
   calls `generate()` with a default phase.
4. **`_restEntry` threading — CORRECT.** Both call sites updated, arg order matches.
5. **`as int?` cast — SAFE.** Live `user_progress.current_phase` is `int4`; all lib/
   writers store ints; the read is byte-identical to ~15 existing readers on hot
   paths — a non-int would already crash the app at launch.
6. **Hotel decoupling — CORRECT.** `generate()` stays foundation content (phase omitted
   → 1); only the row stamp uses `resolvedPhase` (scheduling identity).
7. **Behavior-change safety + test non-vacuous.** Phase-6 zero-history user seeded with
   the real library; empty weekPlans would throw StateError → test fails. Assertions
   (`isNotEmpty` + per-row `phase==6` + `any(workout)` + `any(rest)`) guard vacuity and
   prove the rest-row path stamped too.
8. **Completeness — no other coach schedule-writer gap.** reschedule/pause MOVE rows
   (carry existing `phase`); scheduleTemplate days inherit via bucketPastRows
   nearest-preceding-stamp carry-forward. Stamping the REAL phase (not literal 1) is
   correct — a `1` stamp would mint a phantom phase-1 bucket.

**Minor (non-blocking):** the behavioral test asserts on planner output; the
upsertScheduled round-trip is proven by inspection (the `{...entry}` spread) + existing
contract tests. Optional Hive round-trip assertion, not required.
