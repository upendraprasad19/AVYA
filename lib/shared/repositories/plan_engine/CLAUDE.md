---
scope: plan_engine
parent: ../../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Plan Engine V4 — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/shared/repositories/plan_engine/`.
> Root CLAUDE.md (../../../../CLAUDE.md) contains process invariants and a pointer index.

**File:** `lib/shared/repositories/plan_generator.dart`
**Model:** Hybrid — fixed workout structure per combo, dynamic exercises from Hive.

## Inputs
- `goal`: build_muscle | lose_fat | general_fitness | strength
- `equipment`: bodyweight | home_dumbbells | basic_gym | full_gym
- `daysPerWeek`: 3 | 4 | 5 | 6

## Process
1. Select workout split structure (e.g., 4-day muscle = Push/Pull/Legs/Upper)
2. For each day, query Hive exerciseBox:
   ```
   WHERE category = target_category
   AND equipment_needed matches user equipment
   AND suitable_for includes user experience
   ORDER BY exercise_type = 'compound' DESC
   LIMIT 6
   ```
3. Build 4-week phase with progressive overload defaults
4. Output: phase object with weeks, days, exercises, sets, reps, rest

## Output Shape
```dart
Phase {
  int phase;           // 1-12
  String name;         // "Foundation"
  String focus;        // "Movement patterns & baseline strength"
  String weeks;        // "1-4"
  int dailyCalories;
  int proteinGrams;
  List<WorkoutDay> workouts;
}
```

**FREE:** Phase 1 only (4 weeks). **PRO:** Generate new phases 2-12.

## V4 Pipeline (MuscleSlot Architecture)

**Key change:** CSpec (category-based) replaced by MuscleSlot (muscle-level targeting).

Pipeline stages:
1. **Split Resolver** → `MuscleSlotDay[]` with granular muscle slots per day (8-10 P1-P5 slots per day, ordered by priority)
2. **Volume Filter** → Trims slots to `targetCount(experience, daysPerWeek)` by `slots.take(N)` — depends on split_resolver ordering
3. **Exercise Selector** → 5-attempt cascade within movement patterns (NEVER crosses boundaries)
4. **Sequencing Engine** → Orders by priority, then compound-first
5. **Periodization Engine** → Uses exercise-specific `rep_range` + archetype-based wave
6. **Superset Pairer** → Unchanged
7. **Cardio Finisher** → Unchanged
8. **Warmup/Cooldown** → Now also auto-injects for custom templates

**Exercise count targets (per day):**

| Experience | 3-day | 4-day | 5-day | 6-day |
|---|---|---|---|---|
| Beginner | 6 | 5 | 4 | 4 |
| Intermediate | 8 | 7 | 6 | 6 |
| Advanced | 10 | 9 | 8 | 8 |

Inverse pattern: fewer training days → more exercises per session. More experience → more total volume. Defined in `VolumeFilter.targetCount(experience, daysPerWeek)`.

**Movement patterns (11):** horizontal_push, vertical_push, horizontal_pull, vertical_pull, knee_dominant, hip_dominant, core, elbow_flexion, elbow_extension, shoulder_isolation, hip_isolation

**Cascade attempts:**
1. `attempt1Exact` — all fields match (movement_pattern + target_focus + exercise_type + subFocus + suitable_for + foundational)
2. `attempt2DropSubFocus` — drop subFocus
3. `attempt3DropTypeAndTarget` — drop target_focus + exercise_type (keep movement_pattern only)
4. `attempt4DropEquipment` — drop equipment_tier
5. `universalPool` — hardcoded bodyweight fallback (`exercise_selector.dart:493-505`, mirrored in `cascade_tracer.dart`)

**Slot capacity rule:** No muscle/pattern/type triple should appear in more slots per week than its exercise library pool depth supports. E.g., Rear Delts/shoulder_isolation/isolation has 3 library exercises → max 3 slots/week. Over-allocation → `universalPool` picks (Pike Push Up for rear delt slots) or `(none)` failures.

**Beginner-foundational pool constraint:** For Phase 1, `queryV4` requires BOTH `suitable_for` contains "Beginner" AND `is_foundational: true`. When adding/removing exercises from these pools, audit with `dart run test/plan_generator/sample_plans_report.dart`.

**A/B variants:** slotsB alternates anterior/posterior emphasis weekly (e.g., A=chest-heavy push, B=shoulder-heavy push)

**Verification tools:**
- `test/plan_generator/sample_plans_report.dart` — generates all 12 combos (3×experience × 4×days) for build_muscle/full_gym, emits `sample_plans_output.md`. Target: 0 attempt3/universalPool/none.
- `test/plan_generator/v4_diagnostic_test.dart` — pure-Dart mirror of production cascade; run when changing `exercise_repository.queryV4` or `exercise_selector._cascadeFill`.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Plan generator picks wrong-target exercise | Cascade attempt3 drops `target_focus` + `exercise_type`, keeping only `movement_pattern` — results in a push instead of a chest-specific push. Root causes: (a) exercise library pool too shallow for the slot's triple, or (b) for Phase 1 beginners, `suitable_for` too restrictive (needs "Beginner" + `is_foundational: true`). Fix: either expand library `suitable_for` on the missing exercise OR adjust `split_resolver.dart` slot ordering so beginners don't hit the shallow pool at P1/P2. Verify with `dart run test/plan_generator/sample_plans_report.dart` (target: 0 attempt3/universalPool/none). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Plan generator returns wrong number of exercises | `VolumeFilter` uses `slots.take(targetCount(experience, daysPerWeek))` — depends on `split_resolver` emitting enough P1-P5 slots in priority order. If a split returns fewer slots than the advanced target (10 for 3-day), users get truncated output silently. When adding/reordering a split, count slots and confirm it covers the advanced case. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Pike Push Up assigned to rear delt slot | Sign that cascade exhausted `attempt1-4` and fell to `universalPool`. Indicates too many slots of the same muscle/pattern/type across the week — library pool depth insufficient. Cap rear delt slots to 3/week, lateral delt to 3/week, front delt to 1/week (current library depth). Fix in `split_resolver.dart`, NOT by editing the universal pool. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
