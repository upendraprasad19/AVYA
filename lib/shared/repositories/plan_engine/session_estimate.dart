import 'dart:async';

import 'package:icanbefitter/core/services/error_telemetry.dart';
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
/// Library rows are looked up by `exercise_id` (`getById`, one box read each), and,
/// for an entry whose id is absent or unknown (a template-built day carries none),
/// by its EXACT name, as the engine keys archetypes. No full-library read happens
/// per screen build. A corrupt stored day degrades to null (the old numbers) after a
/// non-fatal report, never to a thrown error in a screen build.
int? budgetedDayMinutes(Map<dynamic, dynamic>? planDay) {
  final seconds = budgetedDaySeconds(planDay);
  return seconds == null ? null : (seconds / 60).round();
}

/// [budgetedDayMinutes] before rounding: the modelled seconds of [planDay], or null
/// (flag OFF, no exercise maps, or a stored day that could not be read). Also the
/// coach's `shortenDay` estimate under the flag, so a day it shortens to N minutes
/// shows about N minutes on Train and Home (B-pass R3 P2-2).
double? budgetedDaySeconds(Map<dynamic, dynamic>? planDay) {
  if (planDay == null) return null;
  if (!PlanEngineFlags.sessionSetBudgetEnabled) return null;
  final raw = planDay['exercises'];
  if (raw is! List || !raw.any((e) => e is Map)) return null;
  try {
    final rowsById = <String, Map<String, dynamic>>{};
    final rowsByName = <String, Map<String, dynamic>>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['exercise_id'];
      Map<String, dynamic>? row;
      if (id is String) {
        row = rowsById[id];
        if (row == null) {
          row = _libraryRow(() => ExerciseRepository.instance.getById(id));
          if (row != null) rowsById[id] = row;
        }
      }
      if (row != null) continue;
      final name = e['exercise_name'] ?? e['name'];
      if (name is! String) continue;
      final key = name.toLowerCase();
      if (rowsByName.containsKey(key)) continue;
      final byName = _libraryRow(() => ExerciseRepository.instance.getByExactName(name));
      // An alias match is another exercise's row: only the row of this exact name counts.
      if (byName != null && '${byName['name']}'.trim().toLowerCase() == key.trim()) {
        rowsByName[key] = byName;
      }
    }
    return SessionBudget.estimateDaySecondsFromPlanDay(planDay, rowsById, rowsByName: rowsByName);
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'session_estimate_day_minutes'));
    return null;
  }
}

/// A library lookup that treats "no library box" (a pure unit test) as "no row", so
/// the entry is priced from its own fields.
Map<String, dynamic>? _libraryRow(Map<String, dynamic>? Function() lookup) {
  try {
    return lookup();
  } catch (_) {
    return null;
  }
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
