import '../../../core/services/hive_service.dart';

/// One day in a pause-plan window (display-only).
///
/// `willPause` is true when the day has a non-completed schedule entry that
/// the dispatcher will mutate to `status='paused'`. Otherwise the day is
/// either already completed (sacred history) or has no schedule at all
/// (rest day or outside plan window) — both shown as "skip" rows.
class PausePlanDay {
  final String date;
  final String? workoutName; // null if no schedule for that date
  final bool willPause; // false if completed or no schedule
  final String? skipReason; // 'completed' | 'no_schedule'

  const PausePlanDay({
    required this.date,
    this.workoutName,
    required this.willPause,
    this.skipReason,
  });
}

/// Aggregate result for a pause-plan window.
class PausePlanResult {
  final List<PausePlanDay> days;
  final int willPauseCount;
  final int skipCompletedCount;
  final int skipNoScheduleCount;

  const PausePlanResult({
    required this.days,
    required this.willPauseCount,
    required this.skipCompletedCount,
    required this.skipNoScheduleCount,
  });
}

/// Plans a pause window for the AI coach `pausePlan` tool (Phase D.4).
///
/// Two-phase contract (mirrors D.3 [RegeneratePlanPlanner], simpler — no
/// PlanGenerator call):
///   1. Diff widget calls [plan] in `initState`, then [cache].
///   2. On user Confirm, dispatcher reads the original payload (start_date +
///      days + reason) and calls [WorkoutScheduleService.pauseRange]
///      directly. The plan cache is informational only — the dispatcher
///      doesn't need it to perform the write (unlike D.3 which caches the
///      full schedule to write).
///   3. [clearCache] runs after execution.
///
/// Strategy:
///   - Walks `days` consecutive dates from `startDate`.
///   - Reads each `schedule_<date>` entry from workoutBox.
///   - Categorizes each day: willPause / skip-completed / skip-no-schedule.
///   - Returns counts + per-day display rows.
class PausePlanPlanner {
  PausePlanPlanner._();
  static final PausePlanPlanner instance = PausePlanPlanner._();

  final Map<String, PausePlanResult> _cache = {};

  Future<PausePlanResult> plan({
    required DateTime startDate,
    required int days,
  }) async {
    final box = HiveService.instance.workoutBox;
    final result = <PausePlanDay>[];
    var willPauseCount = 0;
    var skipCompletedCount = 0;
    var skipNoScheduleCount = 0;

    for (var i = 0; i < days; i++) {
      final d = startDate.add(Duration(days: i));
      final dateStr = _fmt(d);
      final entry = box.get('schedule_$dateStr');

      if (entry is! Map) {
        result.add(PausePlanDay(
          date: dateStr,
          willPause: false,
          skipReason: 'no_schedule',
        ));
        skipNoScheduleCount++;
        continue;
      }

      final status = entry['status']?.toString();
      final workoutName =
          (entry['workout_name'] ?? entry['name'] ?? 'Workout').toString();

      if (status == 'completed') {
        result.add(PausePlanDay(
          date: dateStr,
          workoutName: workoutName,
          willPause: false,
          skipReason: 'completed',
        ));
        skipCompletedCount++;
      } else {
        result.add(PausePlanDay(
          date: dateStr,
          workoutName: workoutName,
          willPause: true,
        ));
        willPauseCount++;
      }
    }

    return PausePlanResult(
      days: result,
      willPauseCount: willPauseCount,
      skipCompletedCount: skipCompletedCount,
      skipNoScheduleCount: skipNoScheduleCount,
    );
  }

  void cache(String intentId, PausePlanResult plan) {
    _cache[intentId] = plan;
  }

  PausePlanResult? getCached(String intentId) => _cache[intentId];

  void clearCache(String intentId) => _cache.remove(intentId);

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
