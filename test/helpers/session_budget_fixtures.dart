// Shared crafted fixtures for the B2 session-set-budget tests (allocator and the
// consumers that take its context). Pure Dart: no Hive, no repository.
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

/// Crafted library rows, keyed by lowercased name like the production map.
class Fx {
  final rows = <String, Map<String, dynamic>>{};

  void row(String name, List<String> muscles,
      {String type = 'compound', String reps = '8-12', String logging = 'weight_reps'}) {
    rows[name.toLowerCase()] = {
      'name': name,
      'primary_muscles': muscles,
      'exercise_type': [type],
      'rep_range': reps,
      'logging_type': logging,
    };
  }

  /// A planned exercise as the selector emits it (sets = the library default).
  PlannedExercise ex(String name,
      {int sets = 3, String logging = 'weight_reps', int rest = 75, String? customOrigin}) {
    final r = rows[name.toLowerCase()];
    return PlannedExercise(
      exerciseId: name.toLowerCase(),
      exerciseName: name,
      loggingType: logging,
      sets: sets,
      reps: '10',
      restSeconds: rest,
      exerciseType: r == null ? 'compound' : (r['exercise_type'] as List).first as String,
      repRange: r?['rep_range'] as String?,
      primaryMuscles: r == null ? null : List<String>.from(r['primary_muscles'] as List),
      customOrigin: customOrigin,
    );
  }

  PopulatedDay day(String intensity, List<PlannedExercise> a, {List<PlannedExercise>? b}) =>
      PopulatedDay(
        name: 'D',
        focus: 'F',
        dayType: 'push',
        intensity: intensity,
        exercisesA: a,
        exercisesB: b ?? a,
      );

  SessionBudgetContext ctx(
    List<PopulatedDay> days, {
    int minutes = 60,
    String goal = 'build_muscle',
    String level = 'intermediate',
    bool lighter = false,
    Set<String> focus = const {},
  }) =>
      SessionBudgetContext(
        minutes: minutes,
        planGoal: goal,
        level: level,
        lighterPhase: lighter,
        focusGroups: focus,
        archetypeByName: {
          for (final e in rows.entries) e.key: SessionBudget.archetypeOfRow(e.value),
        },
        dayIntensities: [for (final d in days) d.intensity],
      );

  List<PopulatedDay> run(
    List<PopulatedDay> days, {
    int minutes = 60,
    String goal = 'build_muscle',
    String level = 'intermediate',
    bool lighter = false,
    Set<String> focus = const {},
    bool is6Day = true,
  }) =>
      SessionSetAllocator.allocate(
        days: days,
        ctx: ctx(days,
            minutes: minutes, goal: goal, level: level, lighter: lighter, focus: focus),
        rowsByName: rows,
        is6Day: is6Day,
      );
}

/// (name, sets) of a variant's exercises, in order.
List<(String, int)> setsOf(PopulatedDay d, {bool b = false}) => [
      for (final e in (b ? d.exercisesB : d.exercisesA)) (e.exerciseName, e.sets),
    ];
