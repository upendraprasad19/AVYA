import 'dart:async';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import 'session_budget.dart';

/// B2 Task 6b (docs/plans/2026-10-22-session-set-budget.md, Ruling 13; flag deleted
/// 2026-11-02, docs/plans/2026-11-02-session-set-budget-flip.md): the session
/// length the app DISPLAYS for a stored plan day.
///
/// The budget minutes of [planDay] (a `schedule_*` row), or null when the day has
/// no exercise map or could not be read; callers then use the ONE shared
/// unreadable-day fallback below ([fallbackDayMinutes] / [fallbackExerciseListSeconds]). One function serves Train (`WorkoutDayData`) and
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
/// (no exercise maps, or a stored day that could not be read). Also the
/// coach's `shortenDay` estimate, so a day it shortens to N minutes
/// shows about N minutes on Train and Home (B-pass R3 P2-2).
double? budgetedDaySeconds(Map<dynamic, dynamic>? planDay) {
  if (planDay == null) return null;
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

/// The unreadable-day fallback, shared by Home, Train and the coach's `shortenDay`
/// (the old `sets x 2.5` estimate, kept for a day [budgetedDaySeconds] cannot read:
/// no exercise map, or a corrupt stored day). About 2.5 minutes a set. [emptyDay]
/// is what a day with no sets shows (Home 45, Train 0).
int fallbackDayMinutes(int totalSets, {int emptyDay = 45}) =>
    totalSets > 0 ? (totalSets * 2.5).round() : emptyDay;

/// The fallback for the coach's `shortenDay` when [budgetedDaySeconds] is null:
/// `sets x 60 + sets x rest` seconds per exercise (3 sets and 60 s rest when absent).
int fallbackExerciseListSeconds(List<Map<String, dynamic>> exercises) {
  int total = 0;
  for (final ex in exercises) {
    final setsRaw = ex['sets'];
    final sets = setsRaw is num ? setsRaw.toInt() : 3;
    final restRaw = ex['rest_seconds'];
    final rest = restRaw is num ? restRaw.toInt() : 60;
    total += sets * 60 + sets * rest;
  }
  return total;
}

/// The minutes on Home's Today card for [schedule] (today's stored plan day):
/// [budgetedDayMinutes], else [fallbackDayMinutes] over the stored sets.
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
  return fallbackDayMinutes(totalSets);
}
