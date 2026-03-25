import 'exercise_repository.dart';

/// Local Dart plan generator. Queries Hive exerciseBox — zero API cost.
///
/// Generates a 4-week workout phase based on user's goal, equipment, and
/// available training days. Phase 1 is ALWAYS free. Phases 2-12 require PRO.
///
/// DO NOT modify this file without explicit instruction.
class PlanGenerator {
  PlanGenerator._();
  static final PlanGenerator _instance = PlanGenerator._();
  static PlanGenerator get instance => _instance;

  final ExerciseRepository _exerciseRepo = ExerciseRepository.instance;

  /// Generates a workout phase.
  ///
  /// - [goal]: build_muscle | lose_fat | general_fitness | strength
  /// - [equipment]: bodyweight | home_dumbbells | basic_gym | full_gym
  /// - [daysPerWeek]: 3 | 4 | 5 | 6
  /// - [phase]: Phase number (1-12). Phase 1 is free; 2-12 require PRO.
  /// - [experienceLevel]: beginner | intermediate | advanced
  Phase generate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    int phase = 1,
    String experienceLevel = 'beginner',
  }) {
    final split = _getSplitStructure(goal, daysPerWeek);
    final equipmentList = _getEquipmentList(equipment);
    final phaseMeta = _getPhaseMeta(phase, goal);

    final workoutDays = <WorkoutDay>[];

    for (int dayIndex = 0; dayIndex < split.length; dayIndex++) {
      final dayConfig = split[dayIndex];
      final exercises = <PlannedExercise>[];

      for (final category in dayConfig.categories) {
        final candidates = _exerciseRepo.query(
          category: category,
          equipment: equipmentList,
          suitableFor: experienceLevel,
          limit: 6,
        );

        // Pick exercises: compounds first, then isolations.
        final selected = _selectExercises(
          candidates,
          maxCount: dayConfig.exercisesPerCategory,
          phase: phase,
        );

        for (final exercise in selected) {
          exercises.add(_buildPlannedExercise(
            exercise: exercise,
            phase: phase,
            goal: goal,
            experienceLevel: experienceLevel,
          ));
        }
      }

      workoutDays.add(WorkoutDay(
        dayNumber: dayIndex + 1,
        name: dayConfig.name,
        focus: dayConfig.focus,
        exercises: exercises,
      ));
    }

    // Auto-pair exercises as supersets within each workout day.
    // Skip the first 2 exercises (main compounds — done solo), then pair
    // exercises at indices [2,3] as superset group 0, and [4,5] as group 1.
    for (int dayIndex = 0; dayIndex < workoutDays.length; dayIndex++) {
      final day = workoutDays[dayIndex];
      final exercises = day.exercises;
      if (exercises.length >= 4) {
        // Pair exercise[2] with exercise[3] as superset group 0
        final updatedExercises = List<PlannedExercise>.from(exercises);
        updatedExercises[2] = updatedExercises[2].copyWith(supersetGroup: () => 0);
        updatedExercises[3] = updatedExercises[3].copyWith(supersetGroup: () => 0);

        // Pair exercise[4] with exercise[5] as superset group 1 (if they exist)
        if (exercises.length >= 6) {
          updatedExercises[4] = updatedExercises[4].copyWith(supersetGroup: () => 1);
          updatedExercises[5] = updatedExercises[5].copyWith(supersetGroup: () => 1);
        }

        workoutDays[dayIndex] = WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: updatedExercises,
        );
      }
    }

    // Build 4 weeks with progressive overload.
    final weeks = _buildWeeks(workoutDays, phase);

    return Phase(
      phase: phase,
      name: phaseMeta.name,
      focus: phaseMeta.focus,
      weeks: '${(phase - 1) * 4 + 1}-${phase * 4}',
      dailyCalories: phaseMeta.dailyCalories,
      proteinGrams: phaseMeta.proteinGrams,
      workouts: workoutDays,
      weekPlans: weeks,
    );
  }

  // ── Split structures ────────────────────────────────────────

  /// Returns the workout split based on goal and training days.
  List<_DayConfig> _getSplitStructure(String goal, int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return _get3DaySplit(goal);
      case 4:
        return _get4DaySplit(goal);
      case 5:
        return _get5DaySplit(goal);
      case 6:
        return _get6DaySplit(goal);
      default:
        return _get4DaySplit(goal);
    }
  }

  List<_DayConfig> _get3DaySplit(String goal) {
    if (goal == 'lose_fat' || goal == 'general_fitness') {
      return [
        _DayConfig('Full Body A', 'Compound focus', ['Push', 'Pull', 'Legs'], 2),
        _DayConfig('Full Body B', 'Strength + cardio', ['Push', 'Pull', 'Legs'], 2),
        _DayConfig('Full Body C', 'Volume + core', ['Legs', 'Core', 'Cardio'], 2),
      ];
    }
    // build_muscle / strength
    return [
      _DayConfig('Push + Core', 'Chest, shoulders, triceps', ['Push', 'Core'], 3),
      _DayConfig('Pull + Core', 'Back, biceps', ['Pull', 'Core'], 3),
      _DayConfig('Legs', 'Quads, hamstrings, glutes', ['Legs'], 5),
    ];
  }

  List<_DayConfig> _get4DaySplit(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DayConfig('Push', 'Chest, shoulders, triceps', ['Push'], 6),
        _DayConfig('Pull', 'Back, biceps', ['Pull'], 6),
        _DayConfig('Legs', 'Quads, hamstrings, glutes', ['Legs'], 6),
        _DayConfig('Upper', 'Chest, back, shoulders', ['Push', 'Pull'], 3),
      ];
    }
    if (goal == 'strength') {
      return [
        _DayConfig('Squat Day', 'Squat + accessories', ['Legs'], 5),
        _DayConfig('Bench Day', 'Bench + upper push', ['Push'], 5),
        _DayConfig('Deadlift Day', 'Deadlift + pull', ['Pull', 'Legs'], 3),
        _DayConfig('OHP Day', 'Overhead press + accessories', ['Push', 'Core'], 3),
      ];
    }
    // lose_fat / general_fitness
    return [
      _DayConfig('Upper Push', 'Chest, shoulders, triceps', ['Push'], 5),
      _DayConfig('Lower Body', 'Legs + cardio', ['Legs', 'Cardio'], 3),
      _DayConfig('Upper Pull', 'Back, biceps', ['Pull'], 5),
      _DayConfig('Full Body + Core', 'Total body + core', ['Legs', 'Core', 'Cardio'], 2),
    ];
  }

  List<_DayConfig> _get5DaySplit(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DayConfig('Chest', 'Chest focus', ['Push'], 6),
        _DayConfig('Back', 'Back focus', ['Pull'], 6),
        _DayConfig('Shoulders + Arms', 'Delts, bi, tri', ['Push', 'Pull'], 3),
        _DayConfig('Legs', 'Quads, hams, glutes', ['Legs'], 6),
        _DayConfig('Weak Points', 'Lagging muscles', ['Push', 'Pull', 'Core'], 2),
      ];
    }
    // Default 5-day
    return [
      _DayConfig('Push', 'Chest, shoulders, triceps', ['Push'], 6),
      _DayConfig('Pull', 'Back, biceps', ['Pull'], 6),
      _DayConfig('Legs', 'Quads, hamstrings, glutes', ['Legs'], 6),
      _DayConfig('Upper', 'Chest, back, shoulders', ['Push', 'Pull'], 3),
      _DayConfig('Lower + Core', 'Legs, core, conditioning', ['Legs', 'Core', 'Cardio'], 2),
    ];
  }

  List<_DayConfig> _get6DaySplit(String goal) {
    if (goal == 'build_muscle') {
      return [
        _DayConfig('Push A', 'Heavy chest focus', ['Push'], 6),
        _DayConfig('Pull A', 'Heavy back focus', ['Pull'], 6),
        _DayConfig('Legs A', 'Quad dominant', ['Legs'], 6),
        _DayConfig('Push B', 'Volume shoulders', ['Push'], 6),
        _DayConfig('Pull B', 'Volume back + biceps', ['Pull'], 6),
        _DayConfig('Legs B', 'Hamstring + glute focus', ['Legs', 'Core'], 4),
      ];
    }
    // Default 6-day PPL
    return [
      _DayConfig('Push', 'Chest, shoulders, triceps', ['Push'], 6),
      _DayConfig('Pull', 'Back, biceps', ['Pull'], 6),
      _DayConfig('Legs', 'Quads, hamstrings, glutes', ['Legs'], 6),
      _DayConfig('Push + Core', 'Upper push + core', ['Push', 'Core'], 4),
      _DayConfig('Pull + Cardio', 'Upper pull + conditioning', ['Pull', 'Cardio'], 4),
      _DayConfig('Legs + Core', 'Lower body + core', ['Legs', 'Core'], 4),
    ];
  }

  // ── Exercise selection ──────────────────────────────────────

  List<Map<String, dynamic>> _selectExercises(
    List<Map<String, dynamic>> candidates, {
    required int maxCount,
    required int phase,
  }) {
    if (candidates.isEmpty) return [];
    if (candidates.length <= maxCount) return candidates;
    return candidates.sublist(0, maxCount);
  }

  PlannedExercise _buildPlannedExercise({
    required Map<String, dynamic> exercise,
    required int phase,
    required String goal,
    required String experienceLevel,
  }) {
    final loggingType =
        exercise['logging_type'] as String? ?? 'weight_reps';
    final defaultSets = exercise['default_sets'] as int? ?? 3;
    final defaultReps = exercise['default_reps'] as String? ?? '10';
    final defaultRest = exercise['default_rest_secs'] as int? ?? 60;
    final defaultDuration = exercise['default_duration_secs'] as int?;

    // Progressive overload: increase sets/intensity with phases.
    int sets = _adjustSets(defaultSets, phase, goal);
    String reps = _adjustReps(defaultReps, phase, goal);
    int rest = _adjustRest(defaultRest, goal);

    return PlannedExercise(
      exerciseId: exercise['id'] as String? ?? '',
      exerciseName: exercise['name'] as String? ?? 'Unknown',
      loggingType: loggingType,
      sets: sets,
      reps: reps,
      restSeconds: rest,
      durationSeconds: defaultDuration,
      notes: _generateNotes(exercise, experienceLevel),
      exerciseType: exercise['exercise_type'] as String?,
    );
  }

  int _adjustSets(int base, int phase, String goal) {
    // Gradual volume increase across phases.
    int phaseBonus = ((phase - 1) * 0.5).floor();
    if (goal == 'strength') {
      return (base + phaseBonus).clamp(3, 5);
    }
    if (goal == 'build_muscle') {
      return (base + phaseBonus).clamp(3, 5);
    }
    return (base + phaseBonus).clamp(2, 4);
  }

  String _adjustReps(String base, int phase, String goal) {
    // Parse the default reps (could be "10", "8-12", "30s", etc.)
    final numericMatch = RegExp(r'(\d+)').firstMatch(base);
    if (numericMatch == null) return base;

    final baseReps = int.parse(numericMatch.group(1)!);

    if (goal == 'strength') {
      final adjusted = (baseReps - phase + 1).clamp(3, 8);
      return '$adjusted';
    }
    if (goal == 'build_muscle') {
      // Hypertrophy range: 8-12, slight variation per phase.
      final low = (baseReps - 2).clamp(6, 10);
      final high = (baseReps + 2).clamp(8, 15);
      return '$low-$high';
    }
    if (goal == 'lose_fat') {
      final adjusted = (baseReps + 2).clamp(10, 20);
      return '$adjusted';
    }
    return base;
  }

  int _adjustRest(int base, String goal) {
    switch (goal) {
      case 'strength':
        return base.clamp(120, 300); // 2-5 min for strength
      case 'build_muscle':
        return base.clamp(60, 120); // 1-2 min for hypertrophy
      case 'lose_fat':
        return base.clamp(30, 60); // 30-60s for fat loss
      default:
        return base.clamp(45, 90);
    }
  }

  String? _generateNotes(Map<String, dynamic> exercise, String level) {
    final cues = exercise['coaching_cues'];
    if (cues is List && cues.isNotEmpty) {
      return cues.first.toString();
    }
    return null;
  }

  // ── Week builder with progressive overload ──────────────────

  List<WeekPlan> _buildWeeks(List<WorkoutDay> workoutDays, int phase) {
    return List.generate(4, (weekIndex) {
      return WeekPlan(
        weekNumber: (phase - 1) * 4 + weekIndex + 1,
        weekInPhase: weekIndex + 1,
        overloadNotes: _getOverloadNotes(weekIndex),
        workoutDays: workoutDays,
      );
    });
  }

  String _getOverloadNotes(int weekIndex) {
    switch (weekIndex) {
      case 0:
        return 'Baseline week — learn the movements, find working weights.';
      case 1:
        return 'Add 1 rep to each set OR increase weight by 2.5 kg.';
      case 2:
        return 'Push intensity — increase weight by 2.5-5 kg where possible.';
      case 3:
        return 'Deload week — reduce weight by 10%, focus on form and recovery.';
      default:
        return '';
    }
  }

  // ── Equipment mapping ───────────────────────────────────────

  List<String> _getEquipmentList(String equipment) {
    switch (equipment) {
      case 'bodyweight':
        return ['none', 'bodyweight'];
      case 'home_dumbbells':
        return ['none', 'bodyweight', 'dumbbells', 'resistance band'];
      case 'basic_gym':
        return [
          'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
          'pull-up bar', 'cables', 'resistance band',
        ];
      case 'full_gym':
        return [
          'none', 'bodyweight', 'dumbbells', 'barbell', 'bench',
          'pull-up bar', 'cables', 'machines', 'smith machine',
          'resistance band', 'kettlebell', 'ez-bar',
        ];
      default:
        return ['none', 'bodyweight'];
    }
  }

  // ── Phase metadata ──────────────────────────────────────────

  _PhaseMeta _getPhaseMeta(int phase, String goal) {
    // Phase 1 metadata.
    if (phase == 1) {
      return _PhaseMeta(
        name: 'Foundation',
        focus: 'Movement patterns & baseline strength',
        dailyCalories: 0, // Calculated by BMR calculator, not here.
        proteinGrams: 0,
      );
    }

    // Higher phases get progressively harder names/focuses.
    final phaseNames = [
      '', // 0 (unused)
      'Foundation',
      'Adaptation',
      'Building',
      'Intensification',
      'Strength Peak',
      'Volume Block',
      'Power Phase',
      'Hypertrophy Focus',
      'Conditioning',
      'Peak Performance',
      'Mastery',
      'Elite',
    ];

    final phaseFocuses = [
      '',
      'Movement patterns & baseline strength',
      'Increasing work capacity & form refinement',
      'Progressive overload & muscle growth',
      'Increasing intensity & strength gains',
      'Peak strength development',
      'High volume training block',
      'Power & explosive movements',
      'Maximum muscle growth',
      'Work capacity & endurance',
      'Performance optimization',
      'Advanced techniques & periodization',
      'Elite programming',
    ];

    return _PhaseMeta(
      name: phase < phaseNames.length ? phaseNames[phase] : 'Phase $phase',
      focus: phase < phaseFocuses.length ? phaseFocuses[phase] : 'Advanced training',
      dailyCalories: 0,
      proteinGrams: 0,
    );
  }
}

// ── Data classes ────────────────────────────────────────────────

class Phase {
  final int phase;
  final String name;
  final String focus;
  final String weeks;
  final int dailyCalories;
  final int proteinGrams;
  final List<WorkoutDay> workouts;
  final List<WeekPlan> weekPlans;

  const Phase({
    required this.phase,
    required this.name,
    required this.focus,
    required this.weeks,
    required this.dailyCalories,
    required this.proteinGrams,
    required this.workouts,
    required this.weekPlans,
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
      };
}

class WeekPlan {
  final int weekNumber;
  final int weekInPhase;
  final String overloadNotes;
  final List<WorkoutDay> workoutDays;

  const WeekPlan({
    required this.weekNumber,
    required this.weekInPhase,
    required this.overloadNotes,
    required this.workoutDays,
  });

  Map<String, dynamic> toMap() => {
        'week_number': weekNumber,
        'week_in_phase': weekInPhase,
        'overload_notes': overloadNotes,
        'workout_days': workoutDays.map((d) => d.toMap()).toList(),
      };
}

class WorkoutDay {
  final int dayNumber;
  final String name;
  final String focus;
  final List<PlannedExercise> exercises;

  const WorkoutDay({
    required this.dayNumber,
    required this.name,
    required this.focus,
    required this.exercises,
  });

  Map<String, dynamic> toMap() => {
        'day_number': dayNumber,
        'name': name,
        'focus': focus,
        'exercises': exercises.map((e) => e.toMap()).toList(),
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
  final String? exerciseType; // 'compound' or 'isolation'
  final int? supersetGroup; // null = standalone, 0/1/2... = superset group index

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
  });

  PlannedExercise copyWith({int? Function()? supersetGroup}) {
    return PlannedExercise(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      loggingType: loggingType,
      sets: sets,
      reps: reps,
      restSeconds: restSeconds,
      durationSeconds: durationSeconds,
      notes: notes,
      exerciseType: exerciseType,
      supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
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
      };
}

// ── Private helpers ─────────────────────────────────────────────

class _DayConfig {
  final String name;
  final String focus;
  final List<String> categories;
  final int exercisesPerCategory;

  const _DayConfig(this.name, this.focus, this.categories, this.exercisesPerCategory);
}

class _PhaseMeta {
  final String name;
  final String focus;
  final int dailyCalories;
  final int proteinGrams;

  const _PhaseMeta({
    required this.name,
    required this.focus,
    required this.dailyCalories,
    required this.proteinGrams,
  });
}
