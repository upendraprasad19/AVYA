import 'models.dart';

/// Stage 3: Reorders exercises within each workout day by 6 rules.
///
/// Rules applied:
/// 1. Compound before isolation
/// 2. Bilateral before unilateral (within compounds)
/// 3. Highest CNS demand first (within same tier)
/// 4. No same movement pattern on consecutive days (advisory — handled by split design)
/// 5. Antagonist supersets for intermediate+ (handled by SupersetPairer, Stage 5)
/// 6. First-set warmup annotation on compound exercises
class SequencingEngine {
  /// Default CNS demand ratings for common exercise patterns.
  static const _defaultCnsDemand = <String, int>{
    'deadlift': 5, 'sumo deadlift': 5, 'trap bar deadlift': 5,
    'romanian deadlift': 4,
    'squat': 5, 'barbell squat': 5, 'back squat': 5, 'front squat': 5,
    'goblet squat': 4,
    'bench press': 4, 'barbell bench press': 4, 'dumbbell bench press': 4,
    'incline bench press': 4, 'decline bench press': 4,
    'overhead press': 4, 'barbell overhead press': 4, 'military press': 4,
    'push press': 4,
    'barbell row': 3, 'bent-over row': 3, 'pendlay row': 3,
    't-bar row': 3, 'dumbbell row': 3,
    'pull-up': 3, 'chin-up': 3, 'lat pulldown': 3,
    'hip thrust': 3, 'barbell hip thrust': 3,
    'lunge': 2, 'walking lunge': 2, 'bulgarian split squat': 3,
    'leg press': 3,
    'dip': 3, 'weighted dip': 3,
  };

  /// Apply sequencing rules to all workout days across all weeks.
  static List<WeekPlan> sequence(List<WeekPlan> weeks) {
    return weeks.map((week) {
      final days = week.workoutDays.map((day) {
        final reordered = _reorderDay(day.exercises);
        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: reordered,
          warmup: day.warmup,
          cooldown: day.cooldown,
          finisher: day.finisher,
        );
      }).toList();

      return WeekPlan(
        weekNumber: week.weekNumber,
        weekInPhase: week.weekInPhase,
        overloadNotes: week.overloadNotes,
        weekCharacter: week.weekCharacter,
        workoutDays: days,
      );
    }).toList();
  }

  /// Reorder a single day's exercises by the 6 rules.
  static List<PlannedExercise> _reorderDay(List<PlannedExercise> exercises) {
    if (exercises.length <= 1) return exercises;

    // Separate into compounds and isolations
    final compounds = <PlannedExercise>[];
    final isolations = <PlannedExercise>[];

    for (final ex in exercises) {
      if (_isCompound(ex)) {
        compounds.add(ex);
      } else {
        isolations.add(ex);
      }
    }

    // Rule 2: Within compounds, bilateral before unilateral
    // Rule 3: Within same bilateral/unilateral group, sort by CNS demand DESC
    compounds.sort((a, b) {
      final bilA = _isBilateral(a) ? 0 : 1;
      final bilB = _isBilateral(b) ? 0 : 1;
      if (bilA != bilB) return bilA.compareTo(bilB);
      return _cnsDemand(b).compareTo(_cnsDemand(a));
    });

    // Rule 3: Sort isolations by CNS demand DESC
    isolations.sort((a, b) => _cnsDemand(b).compareTo(_cnsDemand(a)));

    // Rule 1: Compounds first, then isolations
    final result = [...compounds, ...isolations];

    // Rule 6: Warmup annotation on first set of each compound
    for (int i = 0; i < compounds.length && i < result.length; i++) {
      result[i] = result[i].copyWith(warmupSet: true);
    }

    return result;
  }

  /// Check if exercise is compound based on exercise_type field.
  static bool _isCompound(PlannedExercise ex) {
    final type = ex.exerciseType?.toLowerCase() ?? '';
    if (type == 'compound') return true;
    if (type == 'isolation') return false;
    // Heuristic fallback: if no type, check CNS demand > 2
    return _cnsDemand(ex) >= 3;
  }

  /// Check if exercise is bilateral.
  /// Heuristic: if name contains "single-leg", "single-arm", "unilateral",
  /// "one-arm", "one-leg", or specific unilateral patterns → unilateral.
  static bool _isBilateral(PlannedExercise ex) {
    final name = ex.exerciseName.toLowerCase();
    const unilateralMarkers = [
      'single-leg', 'single leg', 'single-arm', 'single arm',
      'one-arm', 'one arm', 'one-leg', 'one leg',
      'unilateral', 'split squat', 'lunge', 'step-up', 'step up',
      'pistol', 'bulgarian',
    ];
    return !unilateralMarkers.any((m) => name.contains(m));
  }

  /// Get CNS demand rating (1-5) for an exercise.
  static int _cnsDemand(PlannedExercise ex) {
    final name = ex.exerciseName.toLowerCase();

    // Check direct match first
    if (_defaultCnsDemand.containsKey(name)) {
      return _defaultCnsDemand[name]!;
    }

    // Check partial match
    for (final entry in _defaultCnsDemand.entries) {
      if (name.contains(entry.key)) return entry.value;
    }

    // Fallback by exercise type
    final type = ex.exerciseType?.toLowerCase() ?? '';
    if (type == 'compound') return 3;
    if (type == 'isolation') return 1;
    return 2;
  }
}
