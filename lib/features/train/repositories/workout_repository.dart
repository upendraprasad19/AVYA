import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

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
      if (exerciseLogs != null) 'exercise_logs': exerciseLogs,
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

  // ── Helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
