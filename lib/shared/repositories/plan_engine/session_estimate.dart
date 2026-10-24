import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import 'plan_engine_flags.dart';
import 'session_budget.dart';

/// B2 Task 6b (docs/plans/2026-10-22-session-set-budget.md, Ruling 13): the
/// session length the app DISPLAYS for a stored plan day.
///
/// The budget minutes of [planDay] (a `schedule_*` row) when
/// `enable_session_set_budget` is ON, else null, and callers keep the old
/// `totalSets x 2.5`. Also null for a day with no exercise maps, so an empty day
/// keeps its old placeholder. One function serves Train (`WorkoutDayData`) and
/// Home ([homeCardMinutes]): the same day shows the same minutes on both.
///
/// Library rows are looked up by `exercise_id` (`getById`, one box read each), so
/// no full-library read happens per screen build.
int? budgetedDayMinutes(Map<dynamic, dynamic>? planDay) {
  if (planDay == null) return null;
  if (!PlanEngineFlags.sessionSetBudgetEnabled) return null;
  final raw = planDay['exercises'];
  if (raw is! List || !raw.any((e) => e is Map)) return null;
  final rowsById = <String, Map<String, dynamic>>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final id = e['exercise_id'];
    if (id is! String || rowsById.containsKey(id)) continue;
    try {
      final row = ExerciseRepository.instance.getById(id);
      if (row != null) rowsById[id] = row;
    } catch (_) {
      // No library box (pure unit test): the entry is priced from its own fields.
    }
  }
  return SessionBudget.estimateDayMinutesFromPlanDay(planDay, rowsById);
}

/// The minutes on Home's Today card for [schedule] (today's stored plan day).
///
/// Flag ON: [budgetedDayMinutes]. Flag OFF (or a day with no exercises): the old
/// estimate verbatim, about 2.5 minutes per set and 45 for a day with no sets.
int homeCardMinutes(Map<dynamic, dynamic>? schedule) {
  final budgeted = budgetedDayMinutes(schedule);
  if (budgeted != null) return budgeted;
  final exercises = schedule?['exercises'] as List? ?? [];
  int totalSets = 0;
  for (final ex in exercises) {
    if (ex is Map) {
      final sets = (ex['sets'] as int?) ??
          (ex['prescribed_sets'] as int?) ??
          (ex['default_sets'] as int?) ??
          3;
      totalSets += sets;
    }
  }
  return totalSets > 0 ? (totalSets * 2.5).round() : 45;
}
