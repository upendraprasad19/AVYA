# Plan Generator V3 — Full Design Specification

## Context

The current plan generator (`lib/shared/repositories/plan_generator.dart`, ~1560 lines) is a working 5-stage pipeline that generates 4-week workout phases. However, it lacks critical trainer-wisdom features: beginner-specific programming, injury awareness, exercise sequencing rules, body focus customization, log-aware progression, cardio finishers, and proper periodization across phases. This redesign upgrades the engine from a "basic algorithm" to a "₹25,000/month personal trainer" experience while maintaining the zero-API-cost, fully local architecture.

**Source of requirements:** `Knowledgebase/WORKOUT_GENERATOR_SPEC.md` (Upen's trainer wisdom brainstorm)

**Calisthenics:** Deferred — not in MVP scope.

---

## Architecture: Approach B — Modular Multi-File Split

### File Structure

```
lib/shared/repositories/plan_engine/
  ├── plan_generator.dart           # Orchestrator — public API, calls stages in order
  ├── split_resolver.dart           # Stage 1: goal + days + level → split structure
  ├── exercise_selector.dart        # Stage 2: constraint-based exercise picker
  ├── sequencing_engine.dart        # Stage 3: 6 ordering rules [NEW]
  ├── periodization_engine.dart     # Stage 4: 4 archetypes + volume wave
  ├── superset_pairer.dart          # Stage 5: antagonist muscle pairing
  ├── cardio_finisher.dart          # Stage 6: HIIT finishers [NEW]
  ├── warmup_cooldown.dart          # Stage 7: warmup + cooldown
  ├── progression_resolver.dart     # Stage 0: reads Hive logs [NEW]
  └── models.dart                   # All data classes
```

### Migration Strategy

1. Create `plan_engine/` directory
2. Extract `models.dart` first (Phase, WeekPlan, WorkoutDay, PlannedExercise, helpers)
3. Extract each private class to its own public file
4. Old `lib/shared/repositories/plan_generator.dart` becomes a **thin re-export shim**:
   ```dart
   export 'plan_engine/plan_generator.dart';
   export 'plan_engine/models.dart';
   ```
   This prevents import breakage across the entire app.
5. Add new stages (sequencing_engine, cardio_finisher, progression_resolver)
6. Each file is independently unit-testable

### Pipeline Flow

```
User Inputs → Stage 0 (Progression) → Stage 1 (Split) → Stage 2 (Exercise Select)
  → Stage 3 (Sequencing) → Stage 4 (Periodization) → Stage 5 (Supersets)
  → Stage 6 (Cardio Finisher) → Stage 7 (Warmup/Cooldown) → Phase Output
```

### New `generate()` Signature

```dart
Phase generate({
  required String goal,            // build_muscle | lose_fat | general_fitness | strength
  required String equipment,       // bodyweight | home_dumbbells | basic_gym | full_gym
  required int daysPerWeek,        // 3 | 4 | 5 | 6
  int phase = 1,
  String experienceLevel = 'beginner',
  List<int>? preferredDays,
  // ── NEW parameters ──
  List<String> injuries = const [],          // ["shoulder", "knee", "lower_back", ...]
  List<String> bodyFocus = const [],         // max 2: ["chest", "arms"]
  int? sessionDuration,                      // 30 | 45 | 60 | 90 (minutes, guideline not hard cap)
  String? cardioPreference,                  // running | hiit | cycling | jump_rope | hate_cardio
  Map<String, double>? previousWeights,      // from ProgressionResolver (Phase 2+ only)
})
```

---

## Stage 0: Progression Resolver [NEW]

**File:** `progression_resolver.dart`

**When:** Called only for Phase 2+ (Phase 1 has no history to read).

**Input:** Phase number, exercise names from the new phase.

**Logic:**
1. Read exercise logs from Hive `workoutBox` for the last 4 weeks (previous phase period)
2. For each exercise name: find the best (max) weight logged across all sets
3. Apply progression increment:
   - Upper body exercises: +2.5 kg
   - Lower body exercises: +5.0 kg
   - Bodyweight exercises: no weight suggestion (progression is reps-based)
4. Return `Map<String, double>` mapping exercise name → suggested starting weight

**Output:** Passed as `previousWeights` to `generate()`, which stamps `suggestedWeight` onto each `PlannedExercise`.

**Edge cases:**
- Exercise not found in logs (new exercise in Phase 2) → no suggested weight, use "find working weight" cue
- Exercise was substituted (different name but same substitution group) → match by substitution group if available, else no suggestion
- User skipped most workouts → still use whatever was logged; sparse data is better than no data

---

## Stage 1: Split Resolver [MODIFIED]

**File:** `split_resolver.dart`

**Changes from current:**
- **Beginner-aware splits** — new split paths for beginners
- Intermediate and advanced splits remain as current (well-tested, working)

### Beginner Splits (3-4 days → Full Body)

```
3 days:
  Day 1: Full Body A — Push-focused (2 push + 1 pull + 1 legs + 1 core)
  Day 2: Full Body B — Pull-focused (1 push + 2 pull + 1 legs + 1 core)
  Day 3: Full Body C — Legs-focused (1 push + 1 pull + 2 legs + 1 core)

4 days:
  Day 1: Full Body A — Push-focused (2 push + 1 pull + 1 legs + 1 core)
  Day 2: Full Body B — Pull-focused (1 push + 2 pull + 1 legs + 1 core)
  Day 3: Full Body C — Legs-focused (1 push + 1 pull + 2 legs + 1 core)
  Day 4: Full Body D — Balanced   (1 push + 1 pull + 1 legs + 2 core)
```

**Non-negotiables:** Squats (or bodyweight squat variant) and push-ups (or knee push-ups) are guaranteed in EVERY beginner full-body session. The exercise selector injects them before filling remaining slots.

### Beginner Splits (5-6 days → Modified PPL)

```
5 days: Push / Pull / Legs / Upper / Lower (same as intermediate but with 3 sets)
6 days: PPL × 2 (same as intermediate but with 3 sets)
```

### Intermediate/Advanced Splits (Unchanged)

Existing split logic retained exactly as-is.

---

## Stage 2: Exercise Selector [MODIFIED]

**File:** `exercise_selector.dart`

### A. Injury Exclusion Filter (new)

Added as the FIRST filter in the query pipeline:

```
shoulder → exclude exercises where primary_muscles ∩ {Shoulder, Deltoid, Rotator Cuff}
           AND movement_pattern is overhead_press, upright_row, or behind_neck
knee     → exclude: deep squats, lunges, leg extensions, box jumps
lower_back → exclude: conventional deadlift, good mornings, hyperextensions
wrist    → exclude: barbell exercises with heavy wrist load
hip      → exclude: deep hip flexion exercises, heavy lunges
ankle    → exclude: high-impact plyometrics, box jumps, depth jumps
```

**Implementation:** New `injury_contraindications: List<String>` field per exercise.

### B. Body Focus: +1 Isolation Exercise (new)

Append 1 additional isolation exercise for focus muscle groups on relevant days.

### C. Beginner Non-Negotiables (new)

Inject Bodyweight Squat and Push-Up into every beginner full-body day before filling remaining slots.

### D. Session Duration Guidance (new)

30 min → 4 exercises, 45 min → 5, 60 min → 6 (default), 90 min → 7-8. Body focus can override.

### E. Existing Logic Preserved

A/B alternation, broadening chain, universal pool, hard floor of 5, equipment/experience filtering — all unchanged.

---

## Stage 3: Sequencing Engine [NEW]

**File:** `sequencing_engine.dart`

### 6 Rules

1. **Compound before isolation** — sort by exercise_type
2. **Bilateral before unilateral** — new `is_bilateral` field
3. **Highest CNS demand first** — new `cns_demand` field (1-5)
4. **No same movement pattern on consecutive days** — cross-day validation
5. **Antagonist supersets for intermediate+** — existing SupersetPairer
6. **First set annotation** — mark compound set 1 as "warm-up weight (50-60%)"

### Algorithm

```
1. Separate into: compounds[], isolations[]
2. Sort compounds by: is_bilateral DESC, cns_demand DESC
3. Sort isolations by: cns_demand DESC
4. Concatenate: compounds + isolations
5. Annotate compound set 1 with warmupSet: true
```

---

## Stage 4: Periodization Engine [MODIFIED]

**File:** `periodization_engine.dart`

### 4 Phase Archetypes (Cycling)

| Archetype | Phases | Reps | Sets (Inter+) | Sets (Beginner) | C:I Ratio |
|-----------|--------|------|---------------|-----------------|-----------|
| Hypertrophy | 1, 5, 9 | 8-12 | 4 | 3 | 2:1 |
| Strength | 2, 6, 10 | 5-8 | 4-5 | 4 | 3:1 |
| Metabolic | 3, 7, 11 | 12-15 | 4 | 3 | 1:1 |
| Deload | 4, 8, 12 | 8-12 | 3 | 2 | 2:1 |

### Volume Progression

Cycle 1 (Phases 1-4): 1.0x, Cycle 2 (Phases 5-8): 1.1x, Cycle 3 (Phases 9-12): 1.2x

### 4-Set Minimum for Intermediate+

All rep-based exercises for intermediate/advanced get minimum 4 sets. Exception: Deload can go to 3.

### Weekly Volume Wave (Unchanged)

Week 1: Baseline → Week 2: Overreach (+1 set) → Week 3: Peak (-2 reps, heavier) → Week 4: Deload (60% volume)

### Body Focus: +1 Set

Exercises matching bodyFocus muscles get +1 set on top of wave-adjusted value.

---

## Stage 5: Superset Pairer [EXTRACTED, UNCHANGED]

**File:** `superset_pairer.dart` — Logic identical to current `_SupersetPairer`.

---

## Stage 6: Cardio Finisher [NEW]

**File:** `cardio_finisher.dart`

**When:** `goal == 'lose_fat' || goal == 'general_fitness'`

Pick 2 of N workout days (non-consecutive). Append finisher based on cardioPreference:
- running → Treadmill intervals (~8 min)
- cycling → Stationary bike sprints (~8 min)
- hiit → Bodyweight circuit (~10 min)
- jump_rope → Jump rope intervals (~7.5 min)
- hate_cardio/null → Mini HIIT (~5 min)

Equipment-aware: bodyweight-only users get bodyweight substitutes.

---

## Stage 7: Warmup & Cooldown [EXTRACTED, UNCHANGED]

**File:** `warmup_cooldown.dart` — Logic identical to current `_WarmupCooldownSelector`.

---

## Data Model Changes

### PlannedExercise — New Fields
- `suggestedWeight: double?` — from ProgressionResolver
- `warmupSet: bool` — annotation for compound set 1
- `finisherType: String?` — for cardio finisher exercises

### WorkoutDay — New Field
- `finisher: List<PlannedExercise>` — cardio finisher (between exercises and cooldown)

### Exercise Library — New Fields Per Exercise
- `injury_contraindications: List<String>` — injuries that make this unsafe
- `is_bilateral: bool` — bilateral vs unilateral
- `cns_demand: int` (1-5) — CNS load rating
- `substitution_group: String` — links equivalent exercises (future use)

---

## Decisions Log

| # | Decision | Choice |
|---|----------|--------|
| 1 | Beginner non-negotiables | Squats + push-ups only |
| 2 | Advanced programming | Volume increase only |
| 3 | Phase depth | 4 archetypes cycling |
| 4 | Progression | Log-aware with resolver |
| 5 | Injuries | Hard exclusion |
| 6 | Data strategy | Engine first, data after |
| 7 | Body focus | +1 set AND +1 isolation |
| 8 | Session duration | Guideline, focus overrides |
| 9 | Fat loss cardio | All lifting + finishers |
| 10 | 4-set rule | Minimum 4 for intermediate+ |
| 11 | Sequencing | All 6 rules enforced |
| 12 | Beginner split | Full body 3-4d, PPL 5-6d |
| 13 | Non-negotiable ordering | Always included, engine orders |
| 14 | Architecture | Modular multi-file split |
| 15 | Calisthenics | Deferred |
| 16 | Rest timers | Not shown in UI |

---

## Implementation Order

1. Extract models.dart (data classes — zero risk)
2. Extract existing stages to separate files (mechanical refactor)
3. Add re-export shim in old plan_generator.dart location
4. Run existing tests to verify extraction didn't break anything
5. Implement split_resolver changes (beginner full-body splits)
6. Implement exercise_selector changes (injury filter, body focus, non-negotiables)
7. Implement sequencing_engine (new file, 6 rules)
8. Implement periodization_engine changes (4 archetypes, 4-set floor, body focus +1 set)
9. Implement cardio_finisher (new file)
10. Implement progression_resolver (new file, Hive integration)
11. Update exercise_library.json with new fields
12. Thread new parameters through WorkoutScheduleService
13. Write unit tests for each file
14. Integration test: full end-to-end generation

---

## Verification Plan

### Unit Tests (per file)
- split_resolver_test.dart — beginner splits, intermediate/advanced unchanged
- exercise_selector_test.dart — injury exclusion, body focus, non-negotiables
- sequencing_engine_test.dart — 6 ordering rules
- periodization_engine_test.dart — 4 archetypes, 4-set floor, volume wave
- cardio_finisher_test.dart — finisher types, equipment awareness
- progression_resolver_test.dart — Hive reads, weight increments

### Integration Test
- Generate Phase 1 for beginner/4-day/full_gym/muscle_gain with shoulder injury and chest focus
- Verify: full body split, no shoulder exercises, extra chest isolation, squats+push-ups present

### Manual Verification
- Complete onboarding → verify Phase 1 plan
- Add injury in profile → regenerate → verify exclusion
- Phase 2 → verify suggested starting weights
