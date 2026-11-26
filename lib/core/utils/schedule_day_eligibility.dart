// OI-390 (diagnose dow-skip-rate) — U1: one rule for "was this scheduled day
// due, and was it done". The status-aware layer above the type-only rules in
// `phase_completion.dart` ([isTrainingDayType] / [isPhaseCompletionTrainingType]):
// those classify a row's TYPE; this classifies TYPE + STATUS + REASON.
//
// Callers: WorkoutRepository's day-of-week stats and getWorkoutAdherence (one
// walk). `lapseFacts` adopts it in Batch B (OI-397).

import 'phase_completion.dart';

/// How a `schedule_<date>` row counts toward "due and done".
enum ScheduleDayKind {
  /// Not due: no row, a rest/off day, travel, paused, moved, dropped,
  /// pre-onboarding, or an ad-hoc `logged` row that was never completed.
  excluded,

  /// Due and not completed.
  pending,

  /// Completed (any type, including `custom_template` and `logged`).
  completed,
}

const _excludedStatuses = {'rest', 'travel', 'paused', 'moved', 'dropped'};

/// Classifies one schedule row. Pure and total.
///
/// | Row | Kind |
/// |---|---|
/// | null | excluded |
/// | type `rest`/`off`, or status `rest` | excluded |
/// | status `travel` / `paused` / `moved` / `dropped` | excluded |
/// | `reason == 'pre_onboarding'` | excluded |
/// | status `completed`, any type | completed |
/// | type `logged`, not completed | excluded |
/// | anything else | pending |
///
/// A `logged` + `completed` row counts: the concurrent restore can stamp a
/// scheduled completion as `logged` (`sync_workout.dart`), and counting it can
/// only raise a rate.
ScheduleDayKind classifyScheduleDay(Map? row) {
  if (row == null) return ScheduleDayKind.excluded;
  final type = row['type'];
  final status = row['status'];
  if (!isTrainingDayType(type)) return ScheduleDayKind.excluded;
  if (_excludedStatuses.contains(status)) return ScheduleDayKind.excluded;
  if (row['reason'] == 'pre_onboarding') return ScheduleDayKind.excluded;
  if (status == 'completed') return ScheduleDayKind.completed;
  if (type == 'logged') return ScheduleDayKind.excluded;
  return ScheduleDayKind.pending;
}
