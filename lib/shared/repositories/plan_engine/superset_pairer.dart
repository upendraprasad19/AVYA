import 'models.dart';

/// Stage 5: Pairs exercises by antagonist muscles within each workout day.
///
/// Extracted from V2 _SupersetPairer — logic is identical.
class SupersetPairer {
  /// Antagonist muscle pair map.
  static const _antagonists = <String, List<String>>{
    'chest':         ['lats', 'back', 'upper back', 'full back', 'rhomboids'],
    'upper chest':   ['lats', 'back', 'upper back'],
    'lower chest':   ['lats', 'back'],
    'lats':          ['chest', 'upper chest', 'lower chest'],
    'back':          ['chest', 'upper chest'],
    'upper back':    ['chest'],
    'front deltoid': ['rear deltoid', 'shoulders (rear)'],
    'deltoids':      ['rear deltoid'],
    'side deltoid':  ['rear deltoid'],
    'rear deltoid':  ['front deltoid', 'deltoids', 'side deltoid'],
    'biceps':        ['triceps'],
    'triceps':       ['biceps'],
    'quads':         ['hamstrings'],
    'quadriceps':    ['hamstrings'],
    'hamstrings':    ['quads', 'quadriceps'],
    'abs':           ['lower back', 'erector spinae'],
    'core':          ['lower back'],
    'lower back':    ['abs', 'core'],
    'hip flexors':   ['glutes'],
    'glutes':        ['hip flexors'],
  };

  /// Day types that get supersets.
  static const _supersetDays = {'legs', 'upper', 'full_body', 'shoulders_arms'};

  /// Pair exercises by antagonist muscles within each workout day.
  static List<WeekPlan> pair(List<WeekPlan> weeks) {
    return weeks.map((week) {
      final days = week.workoutDays.map((day) {
        final dayType = inferDayType(day);
        if (!_supersetDays.contains(dayType)) return day;

        final exercises = List<PlannedExercise>.from(day.exercises);
        if (exercises.length < 4) return day;

        int groupIdx = 0;
        final paired = <int>{};

        for (int i = 2; i < exercises.length; i++) {
          if (paired.contains(i)) continue;
          final musclesI = _normalize(exercises[i].primaryMuscles);

          for (int j = i + 1; j < exercises.length; j++) {
            if (paired.contains(j)) continue;
            final musclesJ = _normalize(exercises[j].primaryMuscles);

            if (_areAntagonists(musclesI, musclesJ)) {
              exercises[i] = exercises[i].copyWith(supersetGroup: groupIdx);
              exercises[j] = exercises[j].copyWith(supersetGroup: groupIdx);
              paired.addAll([i, j]);
              groupIdx++;
              break;
            }
          }
        }

        return WorkoutDay(
          dayNumber: day.dayNumber,
          name: day.name,
          focus: day.focus,
          exercises: exercises,
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

  static List<String> _normalize(List<String>? muscles) =>
      muscles?.map((m) => m.toLowerCase()).toList() ?? [];

  static bool _areAntagonists(List<String> a, List<String> b) {
    for (final muscleA in a) {
      final antags = _antagonists[muscleA];
      if (antags == null) continue;
      for (final muscleB in b) {
        if (antags.contains(muscleB)) return true;
      }
    }
    return false;
  }

  /// Infer dayType from the workout day name.
  static String inferDayType(WorkoutDay day) {
    final n = day.name.toLowerCase();
    if (n.contains('full body')) return 'full_body';
    if (n.contains('upper')) return 'upper';
    if (n.contains('shoulder') || n.contains('arms')) return 'shoulders_arms';
    if (n.contains('legs') || n.contains('lower') || n.contains('squat') || n.contains('deadlift')) return 'legs';
    if (n.contains('push') || n.contains('bench') || n.contains('chest') || n.contains('ohp')) return 'push';
    if (n.contains('pull') || n.contains('back')) return 'pull';
    return 'upper';
  }
}
