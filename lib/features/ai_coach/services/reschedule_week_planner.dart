import '../../../core/services/hive_service.dart';

/// Action to take for one entry in the target week.
enum RescheduleAction { keep, move, drop }

/// One planned move in a `reschedule_week` intent.
///
/// `keep` — workout stays on its current date (already on an available day,
///   or was completed/paused and must not be touched).
/// `move` — workout is relocated from `fromDate` to `toDate`.
/// `drop` — workout is removed entirely (no available day had space).
class RescheduleMove {
  final String fromDate;
  final String? toDate;
  final RescheduleAction action;
  final String workoutName;

  /// Original `status` field from the schedule entry, if any. Used by the
  /// planner so the diff can call out "(completed)" / "(paused)" entries.
  final String? completedStatus;

  const RescheduleMove({
    required this.fromDate,
    this.toDate,
    required this.action,
    required this.workoutName,
    this.completedStatus,
  });
}

/// Plans a week-reshuffle for a `reschedule_week` intent.
///
/// Reads the target week's `schedule_<date>` entries from Hive workoutBox
/// and computes a per-day move plan that fits all upcoming workouts onto
/// the user's available training days. Mirrors the [InjurySwapPlanner]
/// two-phase contract:
///   1. Diff widget calls [plan] in `initState`, then [cache].
///   2. On user Confirm, dispatcher reads [getCached] and applies moves.
///   3. [clearCache] is called after execution.
///
/// Strategy:
///   - Workouts already on an `daysAvailable` day stay (`keep`).
///   - Misplaced workouts are reassigned to the nearest unused available
///     day (`move`).
///   - If no unused available day has space → `drop` (no merging — too
///     risky to combine workouts without coach review).
///   - Completed / paused entries are protected — always kept on their
///     current date regardless of whether that day is in `daysAvailable`.
class RescheduleWeekPlanner {
  RescheduleWeekPlanner._();
  static final RescheduleWeekPlanner instance = RescheduleWeekPlanner._();

  final Map<String, List<RescheduleMove>> _cache = {};

  Future<List<RescheduleMove>> plan({
    required List<int> daysAvailable,
    String? weekStart, // YYYY-MM-DD Monday
  }) async {
    final monday = weekStart != null
        ? DateTime.parse(weekStart)
        : _currentWeekMonday();
    final available = daysAvailable.toSet();
    final moves = <RescheduleMove>[];

    // Read all 7 days of the target week.
    final dateStrs = <String>[];
    for (var i = 0; i < 7; i++) {
      dateStrs.add(_fmt(monday.add(Duration(days: i))));
    }

    // weekday (1-7, Mon-Sun) → schedule entry for that day.
    final scheduled = <int, Map<String, dynamic>>{};
    for (var i = 0; i < 7; i++) {
      final entry =
          HiveService.instance.workoutBox.get('schedule_${dateStrs[i]}');
      if (entry is Map) {
        scheduled[i + 1] = Map<String, dynamic>.from(entry);
      }
    }

    // Track which available days already host a kept/moved workout.
    final freeAvailableDays = available.toList()..sort();
    final usedAvailableDays = <int>{};

    bool isWorkoutEntry(Map<String, dynamic> s) {
      final type = s['type']?.toString();
      // Skip rest days — they don't need to be moved.
      return type != 'rest' && type != 'none';
    }

    // First pass: protect completed/paused entries + keep workouts already
    // on an available day.
    for (final entry in scheduled.entries) {
      final weekday = entry.key;
      final s = entry.value;
      if (!isWorkoutEntry(s)) continue;

      final status = s['status']?.toString();
      final name = (s['workout_name'] ?? s['name'] ?? 'Workout').toString();

      if (status == 'completed' || status == 'paused') {
        // Don't touch completed or paused entries — they're sacred.
        moves.add(RescheduleMove(
          fromDate: dateStrs[weekday - 1],
          action: RescheduleAction.keep,
          workoutName: name,
          completedStatus: status,
        ));
        if (available.contains(weekday)) usedAvailableDays.add(weekday);
        continue;
      }

      if (available.contains(weekday)) {
        moves.add(RescheduleMove(
          fromDate: dateStrs[weekday - 1],
          action: RescheduleAction.keep,
          workoutName: name,
        ));
        usedAvailableDays.add(weekday);
      }
    }

    // Second pass: workouts NOT on available days — try to relocate them.
    for (final entry in scheduled.entries) {
      final weekday = entry.key;
      final s = entry.value;
      if (!isWorkoutEntry(s)) continue;

      final status = s['status']?.toString();
      if (status == 'completed' || status == 'paused') continue;
      if (available.contains(weekday)) continue;

      final name = (s['workout_name'] ?? s['name'] ?? 'Workout').toString();

      // Find the nearest unused available day.
      int? targetWeekday;
      for (final d in freeAvailableDays) {
        if (!usedAvailableDays.contains(d)) {
          targetWeekday = d;
          break;
        }
      }

      if (targetWeekday != null) {
        usedAvailableDays.add(targetWeekday);
        moves.add(RescheduleMove(
          fromDate: dateStrs[weekday - 1],
          toDate: dateStrs[targetWeekday - 1],
          action: RescheduleAction.move,
          workoutName: name,
        ));
      } else {
        moves.add(RescheduleMove(
          fromDate: dateStrs[weekday - 1],
          action: RescheduleAction.drop,
          workoutName: name,
        ));
      }
    }

    return moves;
  }

  void cache(String intentId, List<RescheduleMove> moves) {
    _cache[intentId] = moves;
  }

  List<RescheduleMove>? getCached(String intentId) => _cache[intentId];

  void clearCache(String intentId) => _cache.remove(intentId);

  DateTime _currentWeekMonday() {
    final now = DateTime.now();
    final daysSinceMonday = (now.weekday - 1) % 7;
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysSinceMonday));
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
