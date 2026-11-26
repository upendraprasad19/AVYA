// docs/plans/train-past-week-in-place.md (D2/D3/D5): the PURE pieces behind the Train screen's
// past-week view. No Hive, no Riverpod: `pastWeekDaysProvider` (train_provider.dart) feeds these the
// rows it read through the schedule read service.

import 'package:icanbefitter/core/services/workout_write_service.dart'
    show kPlaceholderWorkoutNames;
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

final RegExp _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// A [DateTime] for the stored IST date string [ymd] (`yyyy-MM-dd`) that maps back to the SAME IST date
/// on every device: UTC noon. `DateTime.parse('2026-10-12')` is LOCAL midnight, which
/// `istDateStr` (UTC + 5:30) reads as the previous day on a device east of IST, so the schedule read
/// keyed by that date would return the wrong day's row.
DateTime pastWeekDateTime(String ymd) {
  final m = _ymd.firstMatch(ymd);
  if (m == null) throw FormatException('not a yyyy-MM-dd date', ymd);
  return DateTime.utc(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), 12);
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The date range a past week chip stands for: week [weekInPhase] (1-based) of a group whose first
/// stored row is [phaseStart] (`yyyy-MM-dd`, NOT always a Monday), `startDate + (w-1)*7` for 7 days.
/// `Oct 12–18` within a month, `Oct 26–Nov 1` across one. The ONE implementation behind the chip, the
/// label line above the list and the chip's Semantics label (three readers, no drift).
String pastWeekRangeLabel(String phaseStart, int weekInPhase) {
  final m = _ymd.firstMatch(phaseStart);
  if (m == null) throw FormatException('not a yyyy-MM-dd date', phaseStart);
  final start = DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!))
      .add(Duration(days: (weekInPhase - 1) * 7));
  final end = start.add(const Duration(days: 6));
  if (start.month == end.month) {
    return '${_months[start.month - 1]} ${start.day}–${end.day}';
  }
  return '${_months[start.month - 1]} ${start.day}–'
      '${_months[end.month - 1]} ${end.day}';
}

/// A usable workout title: non-blank and not one of the placeholder names the app writes when it knows
/// no real one (`kPlaceholderWorkoutNames`, compared trim + lower-case).
String? usableWorkoutName(Object? name) {
  if (name is! String) return null;
  final t = name.trim();
  if (t.isEmpty || kPlaceholderWorkoutNames.contains(t.toLowerCase())) return null;
  return t;
}

/// Whether [row] needs its `wlog_<date>` name looked up: a COMPLETED row always (its title follows the
/// log) and any row with no usable name of its own.
bool pastDayWantsLogName(Map<String, dynamic> row) =>
    row['status'] == 'completed' || usableWorkoutName(row['workout_name']) == null;

/// One past day ready for `workoutDayDataFromScheduleRow`.
class PastDayView {
  const PastDayView({required this.row, this.loggedCount});

  /// A copy of the stored row with `workout_name` resolved.
  final Map<String, dynamic> row;

  /// The logged-exercise count for `N EX`, set ONLY when the row stores no exercises.
  final int? loggedCount;
}

/// The f4e1d9 / `completed_title_follows_log` rules for a restored past row (the schedule row can arrive
/// name-less and exercise-less):
/// - name of a COMPLETED row: the `wlog_<date>` name, else the row's own, else the generic;
/// - name of a NOT-done row: the row's own, else the wlog name, else the generic;
/// - generic: `Rest Day` for a rest-type row, `Workout` otherwise (the Train builder upper-cases it);
/// - count: [loggedCount] only when the row stores no `exercises` (null otherwise, the builder counts them).
/// [wlogName] and [loggedCount] are read by the caller ONLY when needed ([pastDayWantsLogName], the date
/// holds logs), so this function never asks for them.
PastDayView pastDayView(
  Map<String, dynamic> row, {
  String? wlogName,
  int? loggedCount,
}) {
  final own = usableWorkoutName(row['workout_name']);
  final log = usableWorkoutName(wlogName);
  final isRest =
      PlanEngineFlags.isRestDayConsideringLogged(row['type'] as String? ?? 'rest');
  final generic = isRest ? 'Rest Day' : 'Workout';
  final completed = row['status'] == 'completed';
  final name = completed ? (log ?? own ?? generic) : (own ?? log ?? generic);
  final copy = Map<String, dynamic>.from(row)..['workout_name'] = name;
  final ex = row['exercises'];
  final hasExercises = ex is List && ex.isNotEmpty;
  return PastDayView(row: copy, loggedCount: hasExercises ? null : loggedCount);
}
