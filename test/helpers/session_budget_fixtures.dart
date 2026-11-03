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

/// A budget context for a test that drives `PeriodizationEngine.apply` /
/// `VolumeTitration.applyToWeeks` over a hand-built day. No library rows, so every
/// exercise is priced at the default archetype and, unless named in [names], is
/// NOT budgeted (so the titration leaves it alone); [minutes] defaults to the F2
/// resolution of an empty profile (60). Added with the flip (2026-11-02), when the
/// unbudgeted bodies those tests used to call were deleted.
SessionBudgetContext testBudget({
  int minutes = 60,
  String goal = 'build_muscle',
  String level = 'intermediate',
  bool lighter = false,
  Set<String> focus = const {},
  Iterable<String> names = const [],
}) =>
    SessionBudgetContext(
      minutes: minutes,
      planGoal: goal,
      level: level,
      lighterPhase: lighter,
      focusGroups: focus,
      // [names] are priced at archetype 'B' and therefore count as BUDGETED rows
      // (`SessionBudget.isBudgeted` needs the name in this map).
      archetypeByName: {for (final n in names) n.toLowerCase(): 'B'},
    );
