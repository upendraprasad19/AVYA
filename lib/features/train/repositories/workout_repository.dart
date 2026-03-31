import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';

/// Repository for all workout-related Hive reads/writes.
///
/// Wraps [WorkoutScheduleService] and direct Hive access so that
/// providers and widgets never touch Hive or the schedule service directly.
class WorkoutRepository {
  WorkoutRepository._();
  static final WorkoutRepository _instance = WorkoutRepository._();
  static WorkoutRepository get instance => _instance;

  final WorkoutScheduleService _schedule = WorkoutScheduleService.instance;
  final HiveService _hive = HiveService.instance;

  // ── Plan Queries ──────────────────────────────────────────────

  /// Whether a workout plan has been generated and saved to Hive.
  bool hasPlan() => _schedule.hasPlan();

  /// Raw plan metadata map from Hive workoutBox.
  Map<String, dynamic>? getCurrentPlanMap() => _schedule.getCurrentPlanMap();

  /// Plan start date, or null if no plan exists.
  DateTime? getPlanStartDate() => _schedule.getPlanStartDate();

  // ── Schedule Queries ──────────────────────────────────────────

  /// Get the schedule entry for a specific date.
  ///
  /// Returns a map with keys: date, week, day_of_week, type, workout_name,
  /// workout_focus, exercises, status, completed_at, is_swapped, original_date.
  /// Returns null if date is outside the plan range.
  Map<String, dynamic>? getScheduleForDate(DateTime date) {
    return _schedule.getScheduleForDate(date);
  }

  /// Get today's schedule entry.
  Map<String, dynamic>? getTodaySchedule() {
    return _schedule.getScheduleForDate(DateTime.now());
  }

  /// Get today's workout if it's a workout day (not rest).
  ///
  /// Returns null on rest days or if no plan exists.
  Map<String, dynamic>? getWorkoutForDate(DateTime date) {
    final schedule = _schedule.getScheduleForDate(date);
    if (schedule == null) return null;
    if (schedule['type'] != 'workout') return null;
    return schedule;
  }

  /// Get all 7 days for a given week number (1-4).
  List<Map<String, dynamic>> getWeek(int weekNumber) {
    return _schedule.getWeek(weekNumber);
  }

  /// Current week number based on today's date relative to plan start.
  int getCurrentWeekNumber() => _schedule.getCurrentWeekNumber();

  /// Get the current calendar week (Mon-Sun) with schedule data.
  List<Map<String, dynamic>> getCurrentCalendarWeek() {
    return _schedule.getCurrentCalendarWeek();
  }

  // ── Completion ────────────────────────────────────────────────

  /// Mark a scheduled workout as completed for the given date.
  Future<void> markWorkoutCompleted(DateTime date) async {
    await _schedule.markCompleted(date);
  }

  /// Mark a scheduled workout as skipped for the given date.
  Future<void> markWorkoutSkipped(DateTime date) async {
    await _schedule.markSkipped(date);
  }

  // ── Workout Logs ──────────────────────────────────────────────

  /// Save a workout log entry after completing an active workout.
  Future<String> saveWorkoutLog({
    required String workoutName,
    required int setsCompleted,
    required int durationSeconds,
    required DateTime completedAt,
    List<Map<String, dynamic>>? exerciseLogs,
  }) async {
    final dateStr = _formatDate(completedAt);
    final logId = 'wlog_${completedAt.millisecondsSinceEpoch}';

    await _hive.workoutBox.put(logId, {
      'id': logId,
      'type': 'workout_log',
      'workout_name': workoutName,
      'date': dateStr,
      'completed_at': completedAt.toIso8601String(),
      'sets_completed': setsCompleted,
      'duration_seconds': durationSeconds,
      'exercise_logs': ?exerciseLogs,
    });

    return logId;
  }

  /// Get all workout logs, optionally filtered by date range.
  List<Map<String, dynamic>> getWorkoutLogs({
    DateTime? from,
    DateTime? to,
  }) {
    final logs = <Map<String, dynamic>>[];

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['type'] != 'workout_log') continue;

      if (from != null || to != null) {
        final dateStr = map['date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        if (from != null && date.isBefore(from)) continue;
        if (to != null && date.isAfter(to)) continue;
      }

      logs.add(map);
    }

    // Sort newest first.
    logs.sort((a, b) {
      final aDate = a['completed_at'] as String? ?? '';
      final bDate = b['completed_at'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    return logs;
  }

  /// Get exercise logs actually logged on a specific date.
  /// Returns entries with type 'exercise_log' matching the date.
  List<Map<String, dynamic>> getExerciseLogsForDate(DateTime date) {
    final dateStr = formatDateKey(date);

    // Try indexed lookup first — O(k) where k = exercises logged that day.
    // Index written by completeWorkout() for new data.
    final indexKey = 'exercise_log_index_$dateStr';
    final index = _hive.workoutBox.get(indexKey);
    if (index is List && index.isNotEmpty) {
      final logs = <Map<String, dynamic>>[];
      for (final id in index) {
        final raw = _hive.workoutBox.get(id);
        if (raw is Map) {
          logs.add(Map<String, dynamic>.from(raw));
        }
      }
      if (logs.isNotEmpty) return logs;
    }

    // Fallback: full scan for pre-index data (before this optimisation).
    final logs = <Map<String, dynamic>>[];
    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['type'] != 'exercise_log') continue;
      if (map['date'] != dateStr) continue;
      logs.add(map);
    }

    return logs;
  }

  // ── Swap ──────────────────────────────────────────────────────

  /// Swap two workout days within the same week.
  ///
  /// Returns null on success, or an error message string.
  Future<String?> swapDays(
    DateTime dateA,
    DateTime dateB, {
    required bool isPro,
  }) {
    return _schedule.swapDays(dateA, dateB, isPro: isPro);
  }

  // ── Travel Mode ───────────────────────────────────────────────

  /// Activate travel mode for a date range (PRO only, max 7 days).
  Future<String?> activateTravelMode(DateTime start, DateTime end) {
    return _schedule.activateTravelMode(start, end);
  }

  /// Check if a date is in travel mode.
  bool isTravelDay(DateTime date) => _schedule.isTravelDay(date);

  // ── PRs ──────────────────────────────────────────────────────

  /// Loads personal records for the key compound lifts from workout logs.
  ///
  /// Returns a map with keys: bench, squat, deadlift, ohp.
  /// Each value is a map with 'current' and 'previous' doubles.
  Map<String, Map<String, double>> loadKeyLiftPRs() {
    final prMap = <String, Map<String, double>>{
      'bench': {'current': 0, 'previous': 0},
      'squat': {'current': 0, 'previous': 0},
      'deadlift': {'current': 0, 'previous': 0},
      'ohp': {'current': 0, 'previous': 0},
    };

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final exerciseName =
          (log['exercise_name'] as String? ?? '').toLowerCase();
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (weight <= 0) continue;

      String? prKey;
      if (exerciseName.contains('bench press')) {
        prKey = 'bench';
      } else if (exerciseName.contains('squat') &&
          !exerciseName.contains('split')) {
        prKey = 'squat';
      } else if (exerciseName.contains('deadlift') &&
          !exerciseName.contains('romanian')) {
        prKey = 'deadlift';
      } else if (exerciseName.contains('overhead press') ||
          exerciseName.contains('ohp')) {
        prKey = 'ohp';
      }

      if (prKey != null && weight > prMap[prKey]!['current']!) {
        prMap[prKey] = {
          'current': weight,
          'previous': prMap[prKey]!['current']!,
        };
      }
    }

    return prMap;
  }

  /// Returns the number of workouts logged per week for the last 4 weeks.
  ///
  /// Index 0 = this week, 1 = last week, 2 = 2 weeks ago, 3 = 3 weeks ago.
  List<int> getWeeklyWorkoutCounts() {
    final now = DateTime.now();
    final weekCounts = <int>[0, 0, 0, 0];

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'workout_log') continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final daysAgo = now.difference(date).inDays;
      if (daysAgo < 7) {
        weekCounts[0]++;
      } else if (daysAgo < 14) {
        weekCounts[1]++;
      } else if (daysAgo < 21) {
        weekCounts[2]++;
      } else if (daysAgo < 28) {
        weekCounts[3]++;
      }
    }

    return weekCounts;
  }

  // ── Exercise PR History ────────────────────────────────────────

  /// PR history for a specific exercise over time.
  ///
  /// Scans workoutBox for exercise_log entries matching [exerciseName]
  /// within [days] and returns each unique max weight+reps by date.
  /// Returns `[{date, weight_kg, reps, sets}]` ordered by date ascending.
  List<Map<String, dynamic>> getExercisePRHistory(
    String exerciseName, {
    int days = 90,
  }) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final nameLC = exerciseName.toLowerCase();

    // Group by date, track max weight per date.
    final dateMap = <String, Map<String, dynamic>>{};

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      // Match exercise_log entries or workout_log exercise sub-entries
      final logName =
          (log['exercise_name'] as String? ?? '').toLowerCase();
      if (!logName.contains(nameLC)) continue;

      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (weight <= 0) continue;

      final existing = dateMap[dateStr];
      if (existing == null ||
          weight > (existing['weight_kg'] as double)) {
        dateMap[dateStr] = {
          'date': dateStr,
          'weight_kg': weight,
          'reps': (log['reps_completed'] as num?)?.toInt() ?? 0,
          'sets': (log['sets_completed'] as num?)?.toInt() ?? 0,
        };
      }
    }

    // Also scan exercise_logs embedded in workout_log entries.
    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final wlog = Map<String, dynamic>.from(raw);
      if (wlog['type'] != 'workout_log') continue;
      final exerciseLogs = wlog['exercise_logs'];
      if (exerciseLogs is! List) continue;

      final dateStr = wlog['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      for (final eRaw in exerciseLogs) {
        if (eRaw is! Map) continue;
        final elog = Map<String, dynamic>.from(eRaw);
        final eName =
            (elog['exercise_name'] as String? ?? '').toLowerCase();
        if (!eName.contains(nameLC)) continue;

        final weight = (elog['weight_kg'] as num?)?.toDouble() ?? 0;
        if (weight <= 0) continue;

        final existing = dateMap[dateStr];
        if (existing == null ||
            weight > (existing['weight_kg'] as double)) {
          dateMap[dateStr] = {
            'date': dateStr,
            'weight_kg': weight,
            'reps': (elog['reps_completed'] as num?)?.toInt() ??
                (elog['reps'] as num?)?.toInt() ??
                0,
            'sets': (elog['sets_completed'] as num?)?.toInt() ??
                (elog['sets'] as num?)?.toInt() ??
                0,
          };
        }
      }
    }

    final results = dateMap.values.toList()
      ..sort((a, b) =>
          (a['date'] as String).compareTo(b['date'] as String));
    return results;
  }

  // ── Weekly Volume ────────────────────────────────────────────────

  /// Weekly volume totals (sum of weight x reps across all exercises).
  ///
  /// Returns `{weekStartDate: totalVolumeKg}` for the last [weeks] weeks.
  /// Only counts `weight_reps` type entries.
  Map<String, double> getWeeklyVolume({int weeks = 8}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: weeks * 7));
    final volumeMap = <String, double>{};

    // Initialize week buckets.
    for (int w = 0; w < weeks; w++) {
      final weekStart = _getWeekStart(
        now.subtract(Duration(days: w * 7)),
      );
      volumeMap[_formatDate(weekStart)] = 0;
    }

    // Scan all exercise-level data.
    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null || date.isBefore(cutoff)) continue;

      // Direct exercise entries.
      final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      final reps = (log['reps_completed'] as num?)?.toInt() ?? 0;
      if (weight > 0 && reps > 0) {
        final weekKey = _formatDate(_getWeekStart(date));
        volumeMap[weekKey] =
            (volumeMap[weekKey] ?? 0) + (weight * reps);
      }

      // Embedded exercise_logs in workout_log entries.
      if (log['type'] == 'workout_log') {
        final exerciseLogs = log['exercise_logs'];
        if (exerciseLogs is List) {
          for (final eRaw in exerciseLogs) {
            if (eRaw is! Map) continue;
            final elog = Map<String, dynamic>.from(eRaw);
            final eWeight =
                (elog['weight_kg'] as num?)?.toDouble() ?? 0;
            final eReps = (elog['reps_completed'] as num?)?.toInt() ??
                (elog['reps'] as num?)?.toInt() ??
                0;
            if (eWeight > 0 && eReps > 0) {
              final weekKey = _formatDate(_getWeekStart(date));
              volumeMap[weekKey] =
                  (volumeMap[weekKey] ?? 0) + (eWeight * eReps);
            }
          }
        }
      }
    }

    return volumeMap;
  }

  // ── Workout Adherence ────────────────────────────────────────────

  /// Workout adherence stats for a date range.
  ///
  /// Counts schedule entries (planned, completed, skipped/missed).
  /// Returns `{planned: X, completed: Y, missed: Z, rate_percent: N}`.
  Map<String, int> getWorkoutAdherence({int days = 30}) {
    final now = DateTime.now();
    int planned = 0;
    int completed = 0;
    int missed = 0;

    for (int i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final schedule = _schedule.getScheduleForDate(date);
      if (schedule == null) continue;
      if (schedule['type'] != 'workout') continue;

      planned++;
      final status = schedule['status'] as String? ?? 'planned';
      if (status == 'completed') {
        completed++;
      } else if (date.isBefore(DateTime(now.year, now.month, now.day))) {
        // Past workout days that are not completed count as missed.
        missed++;
      }
    }

    final rate = planned > 0 ? (completed * 100 ~/ planned) : 0;
    return {
      'planned': planned,
      'completed': completed,
      'missed': missed,
      'rate_percent': rate,
    };
  }

  // ── Extended Weekly Workout Counts ───────────────────────────────

  /// Returns the number of workouts logged per week for the last [weeks] weeks.
  ///
  /// Index 0 = this week, 1 = last week, etc.
  /// Supports configurable range (default 12, overriding the original 4).
  List<int> getExtendedWeeklyWorkoutCounts({int weeks = 12}) {
    final now = DateTime.now();
    final weekCounts = List<int>.filled(weeks, 0);

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'workout_log') continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final daysAgo = now.difference(date).inDays;
      final weekIndex = daysAgo ~/ 7;
      if (weekIndex >= 0 && weekIndex < weeks) {
        weekCounts[weekIndex]++;
      }
    }

    return weekCounts;
  }

  // ── Day-of-Week Completion Rates ─────────────────────────────────

  /// Day-of-week completion rates over last [weeks] weeks.
  ///
  /// For each day of the week, counts total scheduled workouts vs completed.
  /// Returns `{Monday: 0.85, Friday: 0.40, ...}`.
  Map<String, double> getDayOfWeekCompletionRates({int weeks = 8}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: weeks * 7));
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final scheduled = <String, int>{};
    final completedMap = <String, int>{};
    for (final name in dayNames) {
      scheduled[name] = 0;
      completedMap[name] = 0;
    }

    // Walk each day in the range.
    for (int i = 0; i < weeks * 7; i++) {
      final date = now.subtract(Duration(days: i));
      if (date.isBefore(cutoff)) break;

      final schedule = _schedule.getScheduleForDate(date);
      if (schedule == null) continue;
      if (schedule['type'] != 'workout') continue;

      final dayName = dayNames[date.weekday - 1]; // weekday: 1=Mon
      scheduled[dayName] = (scheduled[dayName] ?? 0) + 1;

      if (schedule['status'] == 'completed') {
        completedMap[dayName] = (completedMap[dayName] ?? 0) + 1;
      }
    }

    final rates = <String, double>{};
    for (final name in dayNames) {
      final total = scheduled[name] ?? 0;
      final done = completedMap[name] ?? 0;
      rates[name] = total > 0 ? done / total : 0;
    }

    return rates;
  }

  // ── Days Since Last Workout ──────────────────────────────────────

  /// Returns the number of days since the last logged workout.
  ///
  /// Returns -1 if no workouts have been logged.
  int getDaysSinceLastWorkout() {
    final now = DateTime.now();
    DateTime? lastDate;

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'workout_log') continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      if (lastDate == null || date.isAfter(lastDate)) {
        lastDate = date;
      }
    }

    if (lastDate == null) return -1;
    return now.difference(lastDate).inDays;
  }

  // ── Workouts in Last N Days ──────────────────────────────────────

  /// Counts workouts logged within the last [days] days.
  int getWorkoutsInLastDays({int days = 7}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    int count = 0;

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'workout_log') continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      if (!date.isBefore(cutoff)) count++;
    }

    return count;
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime date) => formatDateKey(date);

  /// Returns the Monday of the week containing [date].
  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1; // Monday=1 -> 0
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }
}
