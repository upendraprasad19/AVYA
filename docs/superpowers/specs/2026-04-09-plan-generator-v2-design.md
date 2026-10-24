# Plan Generator V2 — Smart Periodization Upgrade

**Date:** 2026-04-09
**Author:** Upendra + Claude
**Status:** Design Approved — Phase A (Periodization)
**Scope:** Phase A = features 1-5 (periodization + smart programming). Phase B = coaching DNA (warm-up/cool-down, hybrid splits, Indian/yoga exercises) — deferred.

---

## Context

The current plan generator (`lib/shared/repositories/plan_generator.dart`, 691 lines) produces static workout plans: all 4 weeks are identical copies, deload is cosmetic (text note only), supersets are position-based, exercise selection is deterministic, and training days are hardcoded. Analysis of Upendra's real client plans (Chandni, Phase I Home, Subhasis Das) revealed the generator doesn't capture his coaching style — particularly A/B workout variation (Chandni's Bench-lead vs Shoulder-lead upper days), experience-appropriate exercise selection, and genuine week-to-week periodization.

This upgrade transforms the generator into a **pipeline architecture** that produces 4 genuinely distinct weeks per phase, with daily undulating periodization, A/B exercise alternation, real deload, smart superset pairing, and user-selectable training days.

---

## Architecture: Layered Pipeline

The `generate()` method becomes an orchestrator over 5 composable stages:

```
generate(goal, equipment, daysPerWeek, phase, experience, preferredDays?)
  |
  +-- 1. SplitSelector.select(goal, daysPerWeek)
  |     -> SplitPlan { days: [DaySlot(name, focus, categorySpecs, variantASpecs, variantBSpecs)] }
  |
  +-- 2. ExerciseSelector.pick(splitPlan, equipment, experience, phase)
  |     -> PopulatedSplit { days: [DaySlot with exercisesA[] + exercisesB[]] }
  |
  +-- 3. PeriodizationEngine.apply(populatedSplit, goal, phase)
  |     -> PeriodizedPlan { weeks: [Week1..4], each with distinct sets/reps/rest per day }
  |
  +-- 4. SupersetPairer.pair(periodizedPlan)
  |     -> same structure, exercises now have supersetGroup assigned by muscle antagonism
  |
  +-- 5. WeekBuilder.build(periodizedPlan, preferredDays?)
        -> Phase { weekPlans: [4 distinct WeekPlan objects], dayPattern }
```

Each stage is a **static method or private class** within `plan_generator.dart` — pure input->output, no global state. No new files; all stages live in the existing file to respect CLAUDE.md rule #14.

**Key output change:** 4 distinct `WeekPlan` objects instead of 4 copies.

---

## Feature 1: Hybrid Periodization (DUP + Weekly Volume Wave)

### Within-Week: Daily Undulating Periodization (DUP)

Each day slot receives an **intensity profile** that drives its set/rep/rest parameters:

| Profile | Sets | Reps | Rest | Character |
|---------|------|------|------|-----------|
| **Strength** | 4-5 | 4-6 | 120-180s | Heavy, low rep, long rest |
| **Hypertrophy** | 3-4 | 8-12 | 60-90s | Moderate, classic muscle-building |
| **Endurance** | 2-3 | 15-20 | 30-45s | Light, metabolic, shorter rest |

**Profile assignment by split:**

```
3-day:  Day1=Strength, Day2=Hypertrophy, Day3=Endurance
4-day:  Day1=Strength, Day2=Hypertrophy, Day3=Strength, Day4=Endurance
5-day:  Day1=Str, Day2=Hyp, Day3=End, Day4=Str, Day5=Hyp
6-day (PPLx2): A-days(1-3)=Strength, B-days(4-6)=Hypertrophy
```

### Across-Week: Volume Wave

| Week | Volume Modifier | Reps Modifier | Weight Cue | Character |
|------|----------------|---------------|------------|-----------|
| 1 | 100% (baseline sets) | Standard | "Find working weight" | BASELINE |
| 2 | +1 set per exercise | Same reps | "Same weight, more volume" | OVERREACH |
| 3 | Same as Week 1 | -1-2 reps | "+2.5kg if Week 2 felt good" | PEAK |
| 4 | sets x 0.6 (rounded) | reps x 0.8 | "Same as Week 3, recovery focus" | DELOAD |

### Combined Example (Barbell Bench Press, Hypertrophy profile)

| Week | Sets | Reps | Weight Cue |
|------|------|------|------------|
| 1 | 3 | 10 | Find working weight |
| 2 | 4 | 10 | Same weight, more volume |
| 3 | 3 | 8 | +2.5kg if Week 2 felt good |
| 4 | 2 | 8 | Same as Week 3, recovery focus |

---

## Feature 2: Real Volume Deload (Week 4)

Week 4 applies actual parameter changes (not just a text note):

- **Sets:** Reduced by 40% (multiply by 0.6, round down, min 1)
- **Reps:** Reduced by 20% (multiply by 0.8, round to nearest int)
- **Weight:** Stays the same (user maintains strength stimulus)
- **Rest:** Can be slightly shorter (recovery is faster with lower volume)
- **Overload note:** "Recovery week — maintain weight, reduce volume. Focus on form and mind-muscle connection."

---

## Feature 3: A/B Workout Alternation

Each day slot generates **two exercise variants**. Week 1 & 3 use Variant A; Week 2 & 4 use Variant B.

### A/B Focus Shift Logic

**For Strength goal:** Primary lift stays FIXED in both A and B (Squat, Bench, Deadlift, OHP). Only secondary/accessory exercises rotate.

**For all other goals:** Primary compound shifts focus between A and B:
- Push A = Chest-lead (Bench Press) -> Push B = Shoulder-lead (OHP)
- Pull A = Lat-lead (Pulldown) -> Pull B = Row-lead (Seated Row)
- Legs A = Quad-lead (Squat) -> Legs B = Posterior-lead (RDL/Deadlift)
- Upper A = Horizontal emphasis (Bench + Row) -> Upper B = Vertical emphasis (OHP + Pulldown)

### Exercise Selection for A/B

```
For each day slot:
  1. Query exercises for Variant A focus (e.g., Chest-targeted Push)
  2. Select compounds + accessories -> exercisesA
  3. Query exercises for Variant B focus (e.g., Shoulder-targeted Push)
  4. Select compounds + accessories, EXCLUDING exercisesA names -> exercisesB
  5. If not enough unique exercises for B, allow overlap on compounds only
```

### Full A/B Mapping

#### 3-Day Splits

**Build Muscle / Strength (PPL):**
- Push A: Chest-lead (Bench, Incline DB, Cable Fly, Tricep Pushdown, OH Ext)
- Push B: Shoulder-lead (OHP, Arnold Press, Lateral Raise, Close-Grip Bench, Skull Crushers)
- Pull A: Lat-lead (Pulldown, Barbell Row, Face Pull, Curl, Hammer Curl)
- Pull B: Row-lead (Seated Row, Pull-up, Rear Delt, Incline Curl, Preacher Curl)
- Legs A: Quad-lead (Squat, Leg Press, Extension, RDL, Calf)
- Legs B: Posterior-lead (Deadlift, Bulgarian Split, Leg Curl, Hip Thrust, Calf)

**Lose Fat / General (Full Body x3):**
- A variant: Bench, Row, Squat focused compounds
- B variant: OHP, Pulldown, Leg Press focused compounds

#### 4-Day Splits

**Build Muscle (Push/Pull/Legs/Upper):**
- Push A: Chest-focused (6 exercises) -> Push B: Shoulder-focused (6 exercises)
- Pull A: Width-focused (lat emphasis) -> Pull B: Thickness-focused (row emphasis)
- Legs A: Quad-dominant (squat lead) -> Legs B: Posterior-dominant (deadlift lead)
- Upper A: Horizontal (bench + row) -> Upper B: Vertical (OHP + pulldown)

**Strength (Squat/Bench/Dead/OHP):**
- Primary lift FIXED in both A and B
- Squat Day A: Back Squat + Front Squat + accessories -> B: Back Squat + Pause Squat + different accessories
- Bench Day A: Bench + Close-Grip + accessories -> B: Bench + Spoto Press + different accessories
- (Spoto Press only shown for intermediate+ per experience filtering)

**Lose Fat / General (Upper/Lower x2):**
- Upper Push A/B: Different compound leads + accessories
- Lower A/B: Squat-dominant vs hinge-dominant

#### 5-Day Splits

**Build Muscle (Chest/Back/Shoulders+Arms/Legs/Weak Points):**
- Each body part day has A and B exercise selections
- Weak Points day adapts to user's logged data (future Phase B enhancement — for now, targets Core + smaller muscles)

#### 6-Day Splits

**Build Muscle (PPL x2):**
- Natural A/B: First 3 days (Push A, Pull A, Legs A) = Strength profile, Last 3 days (Push B, Pull B, Legs B) = Hypertrophy profile
- DUP is baked into the split structure
- **6-day A/B exception:** Since the split already has two variants per week (A-days and B-days), the week-to-week A/B exercise alternation does NOT apply. Instead, the A and B exercise lists are used within EACH week (A-days get exercisesA, B-days get exercisesB). Week-to-week variation comes purely from the volume wave (baseline/overreach/peak/deload).

### Calendar Mapping

```
Week 1 (Baseline)  -> Variant A exercises + baseline volume
Week 2 (Overreach) -> Variant B exercises + overreach volume
Week 3 (Peak)      -> Variant A exercises + peak intensity
Week 4 (Deload)    -> Variant B exercises + deload volume
```

No two weeks are the same: different exercises AND different volume.

---

## Feature 4: Experience-Aware Exercise Selection

### Effective Experience Level

```dart
String effectiveLevel(String experience, int phase) {
  if (experience == 'advanced') return 'advanced';
  if (experience == 'intermediate') {
    return phase >= 4 ? 'advanced' : 'intermediate';
  }
  // beginner
  if (phase >= 5) return 'advanced';       // 20+ weeks: unlock all
  if (phase >= 3) return 'intermediate';   // 12+ weeks: unlock intermediate
  return 'beginner';                       // Phase 1-2: beginner only
}
```

### Filtering Rules

| Effective Level | Exercises Shown |
|-----------------|----------------|
| beginner | `suitable_for` includes "Beginner" + `is_foundational=true` (Phase 1 only) |
| intermediate | `suitable_for` includes "Beginner" OR "Intermediate" |
| advanced | All exercises |

This ensures beginners never see Svend Press, Spoto Press, or other advanced movements until they've progressed through multiple phases.

### Exercise Count Per Workout

Varies by split frequency and experience:

| Split Days | Beginner | Intermediate | Advanced |
|------------|----------|--------------|----------|
| 3-day | 5 | 6 | 6 |
| 4-day | 5 | 5 | 6 |
| 5-day | 4 | 5 | 5 |
| 6-day | 4 | 4 | 5 |

Logic: More training days = fewer exercises per session (volume spread across week). Values are deterministic — use the exact count in the table. Both Variant A and Variant B use the same count per day slot.

---

## Feature 5: Smart Antagonist Superset Pairing

### Antagonist Pair Map

```
Chest       <->  Back (Lats)
Front Delt  <->  Rear Delt
Biceps      <->  Triceps
Quads       <->  Hamstrings
Abs         <->  Lower Back (Erector)
Hip Flexors <->  Glutes
```

### Algorithm

```
pairByAntagonist(exercises, dayType):
  1. First 1-2 exercises = ALWAYS standalone (main compounds need full recovery)
  2. If dayType is Push or Pull -> NO supersets (straight sets only)
  3. If dayType is Upper, Full Body, or Legs:
     a. From remaining exercises (position 3+), scan primary_muscles
     b. For each unpaired exercise, find another unpaired with antagonist primary_muscles
     c. If found -> assign same supersetGroup
     d. If no antagonist match -> stays standalone
  4. Return exercises with supersetGroup assigned
```

### Day Type Rules

| Day Type | Superset? | Examples |
|----------|-----------|---------|
| Push | NO (straight sets) | N/A |
| Pull | NO (straight sets) | N/A |
| Legs | YES (quad/hamstring pairs) | Leg Extension + Leg Curl |
| Upper | YES (push/pull pairs) | Bench + Row, OHP + Pulldown |
| Full Body | YES (any antagonist pair) | Bench + Row, Curl + Pushdown |
| Shoulders+Arms | YES (bicep/tricep) | Barbell Curl + Tricep Pushdown |

---

## Feature 6: User-Selectable Training Days

### Current Defaults (Kept as Fallback)

```
3-day -> [0, 2, 4]          (Mon, Wed, Fri)
4-day -> [0, 1, 3, 5]       (Mon, Tue, Thu, Sat)
5-day -> [0, 1, 2, 4, 5]    (Mon, Tue, Wed, Fri, Sat)
6-day -> [0, 1, 2, 3, 4, 5] (Mon-Sat)
```

### New Flow

1. User selects `daysPerWeek` (3-6)
2. User taps specific days on a 7-day grid (must select exactly `daysPerWeek` days)
3. If user skips -> fall back to defaults above

### Smart Spacing Warnings (soft, dismissable)

| Scenario | Warning |
|----------|---------|
| 3+ consecutive training days | "Consider adding a rest day between [X] and [Y] for better recovery" |
| All days bunched at start/end | "Spreading workouts across the week improves consistency" |

### Implementation

- Changes **WorkoutScheduleService**, not PlanGenerator
- `generateAndSchedule()` receives `preferredDays: List<int>?` (0=Mon, 6=Sun)
- If null -> use default patterns (backward compatible)
- If provided -> map Day 1 -> first preferred day, Day 2 -> second, etc.
- Persisted: `configBox.put('preferred_training_days', [0, 2, 4])`

---

## Data Model Changes

### PlannedExercise (updated)

```dart
class PlannedExercise {
  // existing fields...
  final String exerciseId;
  final String exerciseName;
  final String loggingType;
  final int sets;
  final String reps;
  final int restSeconds;
  final int? durationSeconds;
  final String? notes;
  final String exerciseType;
  final int? supersetGroup;
  final String category;
  final List<String> equipmentNeeded;

  // NEW fields
  final String intensityProfile;  // 'strength' | 'hypertrophy' | 'endurance'
  final String? weightCue;        // "Find working weight", "+2.5kg if Week 2 felt good"
  final String variant;           // 'A' | 'B'
}
```

### WeekPlan (updated)

```dart
class WeekPlan {
  final int weekNumber;
  final int weekInPhase;
  final String overloadNotes;
  final String weekCharacter;     // NEW: 'baseline' | 'overreach' | 'peak' | 'deload'
  final List<WorkoutDay> workoutDays;  // NOW DISTINCT per week (not shared)
}
```

### Phase (updated)

```dart
class Phase {
  // existing fields...
  final List<int>? preferredDays;  // NEW: user's selected training days
}
```

---

## Files Modified

| File | Changes |
|------|---------|
| `lib/shared/repositories/plan_generator.dart` | Full refactor into pipeline architecture. ~691 lines -> ~800-900 lines (restructured, not bloated) |
| `lib/shared/repositories/exercise_repository.dart` | Add `effectiveLevel()` filter, update `query()` to accept effective level |
| `lib/core/services/workout_schedule_service.dart` | Accept `preferredDays` parameter, update `generateAndSchedule()` |
| `lib/features/train/providers/train_provider.dart` | Pass `preferredDays` through to schedule service |
| `lib/core/services/hive_service.dart` | Store `preferred_training_days` in configBox |

No new files created. No schema migrations needed (all changes are local/Hive).

---

## Backward Compatibility

- Existing users with active Phase 1 plans: No change until plan regeneration
- On next plan generation (Phase 2 unlock, profile change, manual regen): New pipeline activates
- `preferredDays: null` -> falls back to current default patterns
- Hive schedule entries retain the same key format (`schedule_YYYY-MM-DD`)
- All existing exercise log data, workout logs, and streak data unaffected

---

## Phase B (Deferred)

These features are designed but not included in this implementation:

1. **Warm-up/cool-down sections** per workout day (YouTube-linked)
2. **Gym+Home hybrid splits** (alternating gym/home days, like Subhasis's plan)
3. **Indian/yoga exercise prioritization** on bodyweight days + Yoga+Cardio day type
4. **Coaching voice** (motivational notes per workout)
5. **Form-first progression** (adaptive progression cues based on readiness)

---

## Verification Plan

1. **Unit tests:** Test each pipeline stage independently
   - `SplitSelector`: Verify correct split for each goal x daysPerWeek combo
   - `ExerciseSelector`: Verify A/B exercise lists are non-overlapping, experience filtering works
   - `PeriodizationEngine`: Verify volume wave math (baseline/overreach/peak/deload)
   - `SupersetPairer`: Verify no supersets on Push/Pull days, correct antagonist pairing on Upper/Legs
   - `WeekBuilder`: Verify 4 distinct weeks, day pattern mapping
2. **Integration test:** Generate a full plan for each goal x equipment x daysPerWeek x experience combo, assert no crashes and valid output
3. **Regression test:** Existing test in `test/bmr_calculator_test.dart` still passes (unrelated but sanity check)
4. **Manual test on device:** Generate a plan via the app, verify Train screen shows different exercises/volume per week
