// ══════════════════════════════════════════════════════════════════
// PUBLIC DATA CLASSES — Plan Generator V3
// ══════════════════════════════════════════════════════════════════

/// Parse a library `rep_range` string ("lo-hi", e.g. "8-12") → `(lo, hi)` with
/// BOTH positive ints and `lo <= hi`; null/malformed/reversed/single/timed →
/// null (callers fall back to their default). The SINGLE shared parser for the
/// plan engine — used by `PeriodizationEngine._applyWave` (wave reps) and
/// `ProgressionResolver` (W2.1 rep-range banding) so a second hand-rolled
/// `split('-')` can't drift (the #1 recurring bug class). On real library data
/// every rep-based `rep_range` is a clean "N-M" with lo<hi, so this is
/// behavior-preserving vs the old per-part parse (pinned by
/// `periodization_wave_reps_invariant_test.dart`).
(int, int)? parseRepRange(String? range) {
  if (range == null || !range.contains('-')) return null;
  final parts = range.split('-');
  if (parts.length != 2) return null;
  final lo = int.tryParse(parts[0].trim());
  final hi = int.tryParse(parts[1].trim());
  if (lo == null || hi == null || lo <= 0 || hi <= 0 || lo > hi) return null;
  return (lo, hi);
}

class Phase {
  final int phase;
  final String name;
  final String focus;
  final String weeks;
  final int dailyCalories;
  final int proteinGrams;
  final List<WorkoutDay> workouts; // backward compat: week 1
  final List<WeekPlan> weekPlans;
  final List<int>? preferredDays;

  const Phase({
    required this.phase,
    required this.name,
    required this.focus,
    required this.weeks,
    required this.dailyCalories,
    required this.proteinGrams,
    required this.workouts,
    required this.weekPlans,
    this.preferredDays,
  });

  Map<String, dynamic> toMap() => {
        'phase': phase,
        'name': name,
        'focus': focus,
        'weeks': weeks,
        'daily_calories': dailyCalories,
        'protein_grams': proteinGrams,
        'workouts': workouts.map((w) => w.toMap()).toList(),
        'week_plans': weekPlans.map((w) => w.toMap()).toList(),
        if (preferredDays != null) 'preferred_days': preferredDays,
      };
}

class WeekPlan {
  final int weekNumber;
  final int weekInPhase;
  final String overloadNotes;
  // baseline | overreach | peak | deload — plus `working`, written back by
  // deload_evaluator.dart:231 when a deload is lifted. The generator only ever
  // emits the first four; the fifth arrives by rewrite.
  final String weekCharacter;
  final List<WorkoutDay> workoutDays;

  const WeekPlan({
    required this.weekNumber,
    required this.weekInPhase,
    required this.overloadNotes,
    this.weekCharacter = 'baseline',
    required this.workoutDays,
  });

  Map<String, dynamic> toMap() => {
        'week_number': weekNumber,
        'week_in_phase': weekInPhase,
        'overload_notes': overloadNotes,
        'week_character': weekCharacter,
        'workout_days': workoutDays.map((d) => d.toMap()).toList(),
      };
}

class WorkoutDay {
  final int dayNumber;
  final String name;
  final String focus;
  final List<PlannedExercise> exercises;
  final List<PlannedExercise> warmup;
  final List<PlannedExercise> cooldown;
  final List<PlannedExercise> finisher; // V3: cardio finisher (between exercises and cooldown)

  const WorkoutDay({
    required this.dayNumber,
    required this.name,
    required this.focus,
    required this.exercises,
    this.warmup = const [],
    this.cooldown = const [],
    this.finisher = const [],
  });

  Map<String, dynamic> toMap() => {
        'day_number': dayNumber,
        'name': name,
        'focus': focus,
        'exercises': exercises.map((e) => e.toMap()).toList(),
        if (warmup.isNotEmpty)
          'warmup': warmup.map((e) => e.toMap()).toList(),
        if (cooldown.isNotEmpty)
          'cooldown': cooldown.map((e) => e.toMap()).toList(),
        if (finisher.isNotEmpty)
          'finisher': finisher.map((e) => e.toMap()).toList(),
      };
}

class PlannedExercise {
  final String exerciseId;
  final String exerciseName;
  final String loggingType;
  final int sets;
  final String reps;
  final int restSeconds;
  final int? durationSeconds;
  final String? notes;
  final String? exerciseType;
  final int? supersetGroup;
  final String? category;
  final List<String>? equipmentNeeded;
  // V2 fields
  final String intensityProfile; // strength | hypertrophy | endurance
  final String? weightCue;
  final String variant; // A | B
  final List<String>? primaryMuscles;
  // V3 fields
  final double? suggestedWeight; // from ProgressionResolver (kg)
  final bool warmupSet; // true for set 1 of compounds (annotation)
  // V4 fields
  final String? repRange; // exercise-specific range from library e.g. "8-12", "5-8", "30-60"
  // ⑥ 7-B-1 (W2.4): pre-wave working (peak-equivalent) sets/reps stashed at
  // GENERATION on the deload week (weekIdx 3, flag-ON) so a triggered deload can be
  // un-deloaded losslessly (the deload cut is non-invertible). Null except on the
  // flag-ON week-4 exercise; rides plan_json jsonb (no migration). MUST be threaded
  // through copyWith so the superset pairer (stage 6, AFTER periodization) doesn't wipe it.
  final int? workingSets;
  final String? workingReps; // matches `reps` (String; may be a range like "8-12")

  const PlannedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.loggingType,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    this.durationSeconds,
    this.notes,
    this.exerciseType,
    this.supersetGroup,
    this.category,
    this.equipmentNeeded,
    this.intensityProfile = 'hypertrophy',
    this.weightCue,
    this.variant = 'A',
    this.primaryMuscles,
    this.suggestedWeight,
    this.warmupSet = false,
    this.repRange,
    this.workingSets,
    this.workingReps,
  });

  PlannedExercise copyWith({
    int? sets,
    String? reps,
    int? restSeconds,
    String? notes,
    int? supersetGroup,
    String? intensityProfile,
    String? weightCue,
    String? variant,
    List<String>? primaryMuscles,
    double? suggestedWeight,
    bool? warmupSet,
    String? repRange,
    int? workingSets,
    String? workingReps,
  }) {
    return PlannedExercise(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      loggingType: loggingType,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      restSeconds: restSeconds ?? this.restSeconds,
      durationSeconds: durationSeconds,
      notes: notes ?? this.notes,
      exerciseType: exerciseType,
      supersetGroup: supersetGroup ?? this.supersetGroup,
      category: category,
      equipmentNeeded: equipmentNeeded,
      intensityProfile: intensityProfile ?? this.intensityProfile,
      weightCue: weightCue ?? this.weightCue,
      variant: variant ?? this.variant,
      primaryMuscles: primaryMuscles ?? this.primaryMuscles,
      suggestedWeight: suggestedWeight ?? this.suggestedWeight,
      warmupSet: warmupSet ?? this.warmupSet,
      repRange: repRange ?? this.repRange,
      workingSets: workingSets ?? this.workingSets,
      workingReps: workingReps ?? this.workingReps,
    );
  }

  Map<String, dynamic> toMap() => {
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'logging_type': loggingType,
        'sets': sets,
        'reps': reps,
        'rest_seconds': restSeconds,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (notes != null) 'notes': notes,
        if (exerciseType != null) 'exercise_type': exerciseType,
        if (supersetGroup != null) 'superset_group': supersetGroup,
        if (category != null) 'category': category,
        if (equipmentNeeded != null) 'equipment_needed': equipmentNeeded,
        'intensity_profile': intensityProfile,
        if (weightCue != null) 'weight_cue': weightCue,
        'variant': variant,
        if (primaryMuscles != null) 'primary_muscles': primaryMuscles,
        if (suggestedWeight != null) 'suggested_weight': suggestedWeight,
        if (warmupSet) 'warmup_set': warmupSet,
        if (repRange != null) 'rep_range': repRange,
        if (workingSets != null) 'working_sets': workingSets,
        if (workingReps != null) 'working_reps': workingReps,
      };
}

// ══════════════════════════════════════════════════════════════════
// INTERNAL PIPELINE DATA CLASSES
// ══════════════════════════════════════════════════════════════════

/// Valid V4 movement patterns — the 11 irreducible categories.
const kMovementPatterns = <String>{
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'knee_dominant',
  'hip_dominant',
  'core',
  'elbow_flexion',
  'elbow_extension',
  'shoulder_isolation',
  'hip_isolation',
};

/// Category spec for exercise queries.
class CSpec {
  final String category;
  final int count;
  final List<String>? targetMuscles;
  final List<String>? excludeMuscles;

  const CSpec(this.category, this.count, {
    List<String>? target,
    List<String>? exclude,
  }) : targetMuscles = target, excludeMuscles = exclude;
}

/// V4: Muscle-level exercise slot with cascading fallback support.
/// Replaces CSpec for trainer-quality exercise selection.
class MuscleSlot {
  final String targetMuscle;    // e.g., 'Lats', 'Biceps', 'Quads'
  final String? subFocus;       // e.g., 'width', 'short_head', 'thickness'
  final String movementPattern; // e.g., 'vertical_pull' — NEVER dropped in cascade
  final String exerciseType;    // 'compound' | 'isolation'
  final int priority;           // 1=primary, 2=secondary, 3=accessory
  final int count;              // exercises to fill for this slot (usually 1)

  const MuscleSlot({
    required this.targetMuscle,
    this.subFocus,
    required this.movementPattern,
    required this.exerciseType,
    required this.priority,
    this.count = 1,
  });

  @override
  String toString() =>
      'MuscleSlot($targetMuscle${subFocus != null ? "/$subFocus" : ""}, '
      '$movementPattern, $exerciseType, P$priority, x$count)';
}

/// V4: A workout day defined by MuscleSlots instead of CSpecs.
class MuscleSlotDay {
  final String name;
  final String focus;
  final String dayType;     // push, pull, legs, upper, full_body, shoulders_arms
  final String intensity;   // strength, hypertrophy, endurance
  final List<MuscleSlot> slotsA;
  final List<MuscleSlot>? slotsB; // null = same as A

  const MuscleSlotDay({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.slotsA,
    this.slotsB,
  });
}

/// A day slot in the split plan.
class DaySlot {
  final String name;
  final String focus;
  final String dayType;     // push | pull | legs | upper | full_body | shoulders_arms
  final String intensity;   // strength | hypertrophy | endurance
  final List<CSpec> specsA;
  final List<CSpec>? specsB; // null = same as A (variety via exclusion or 6-day)

  const DaySlot({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.specsA,
    this.specsB,
  });
}

/// Populated day with selected exercises for both variants.
class PopulatedDay {
  final String name;
  final String focus;
  final String dayType;
  final String intensity;
  final List<PlannedExercise> exercisesA;
  final List<PlannedExercise> exercisesB;

  const PopulatedDay({
    required this.name,
    required this.focus,
    required this.dayType,
    required this.intensity,
    required this.exercisesA,
    required this.exercisesB,
  });
}

/// Phase metadata (name + focus).
class PhaseMeta {
  final String name;
  final String focus;
  final int dailyCalories;
  final int proteinGrams;

  const PhaseMeta({
    required this.name,
    required this.focus,
    required this.dailyCalories,
    required this.proteinGrams,
  });
}
