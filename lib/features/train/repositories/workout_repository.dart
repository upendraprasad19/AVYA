import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:uuid/uuid.dart';

/// A personal record for a single exercise, based on all-time best value.
class ExercisePR {
  final String exerciseName;
  final String loggingType; // weight_reps | bodyweight_reps | timed | cardio | distance
  final double bestValue;   // kg / reps / secs / km depending on type
  final DateTime date;      // date of the log that achieved this best

  const ExercisePR({
    required this.exerciseName,
    required this.loggingType,
    required this.bestValue,
    required this.date,
  });

  /// Human-readable best value label (e.g. "80 kg", "15 reps", "2m 30s").
  String get formattedValue {
    switch (loggingType) {
      case 'bodyweight_reps':
        return '${bestValue.toInt()} reps';
      case 'timed':
        final secs = bestValue.toInt();
        if (secs >= 60) {
          final m = secs ~/ 60;
          final s = secs % 60;
          return s > 0 ? '${m}m ${s}s' : '${m}m';
        }
        return '${secs}s';
      case 'cardio':
      case 'distance':
        // cardio bestValue is distance_km when > 0, else duration_seconds.
        // Values < 10 are km (e.g. 5.2 km); >= 60 are seconds (e.g. 1800 → 30 min).
        if (loggingType == 'cardio' && bestValue < 10) {
          return '${bestValue.toStringAsFixed(1)} km';
        }
        if (bestValue >= 60) return '${(bestValue / 60).round()} min';
        return '${bestValue.toStringAsFixed(1)} km';
      default: // weight_reps, weighted_bodyweight
        final kg = bestValue;
        return kg == kg.roundToDouble()
            ? '${kg.toInt()} kg'
            : '${kg.toStringAsFixed(1)} kg';
    }
  }

  /// Short date label: "1 Apr".
  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

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

  // ── Secondary date index (D7) ────────────────────────────────
  //
  // Lazy-built map from YYYY-MM-DD → list of exlog_* Hive keys.
  // Built once on first fallback miss; nulled out on every exlog write.
  // Eliminates the O(n) full-box scan in the getExerciseLogsForDate
  // fallback path for legacy entries that predate the primary index.
  Map<String, List<String>>? _exlogDateIndex;

  Map<String, List<String>> _ensureExlogDateIndex() {
    final cached = _exlogDateIndex;
    if (cached != null) return cached;
    final byDate = <String, List<String>>{};
    for (final key in _hive.workoutBox.keys) {
      final k = key.toString();
      if (!k.startsWith('exlog_')) continue;
      final raw = _hive.workoutBox.get(key);
      if (raw is! Map) continue;
      final dateStr = raw['date'] as String?;
      if (dateStr == null) continue;
      byDate.putIfAbsent(dateStr, () => []).add(k);
    }
    _exlogDateIndex = byDate;
    return byDate;
  }

  // ── Streak Calculation ───────────────────────────────────────

  /// Earliest date the user could legitimately have completed a workout.
  ///
  /// [calculateCurrentStreak] stops the walk-back at this anchor — dates
  /// BEFORE it are silently skipped (no penalty, no freeze consumption)
  /// because the user didn't have the app yet.
  ///
  /// Anchor = earliest of: onboarding_completed_at, first_workout_date.
  /// Returns null if neither is available → 365-day walk-back unchanged.
  DateTime? _earliestUserAnchor() {
    final profile = _hive.userBox.get('profile') as Map?;
    if (profile == null) return null;

    DateTime? earliest;

    void consider(String? iso) {
      if (iso == null || iso.isEmpty) return;
      final dt = DateTime.tryParse(iso);
      if (dt == null) return;
      // Anchor on the IST calendar-date midnight, not the raw instant. The
      // walk-back stop in _calculateStreak (`date.isBefore(anchor)`) is
      // date-granular and `date` carries the wall-clock time-of-day, so a
      // mid-day instant (onboarding_completed_at — now a durable Hive value,
      // diagnose c4d8a2) would exclude the onboarding-day workout whenever
      // onboarding's time-of-day exceeds the walk's. istMidnight is idempotent
      // for the wlog date-strings (already 00:00) and only ever moves the
      // anchor EARLIER, so it can include the onboarding day but never drop a
      // completed day. (B-pass Finding 1, docs/reviews/5a1ac3e1cb4d-review.md.)
      final dayStart = istMidnight(dt);
      if (earliest == null || dayStart.isBefore(earliest!)) {
        earliest = dayStart;
      }
    }

    consider(profile['onboarding_completed_at'] as String?);

    // Also check the earliest wlog_ entry so manual-import users are covered.
    String? earliestWlogDate;
    for (final key in _hive.workoutBox.keys) {
      if (!key.toString().startsWith('wlog_')) continue;
      final log = _hive.workoutBox.get(key);
      if (log is! Map) continue;
      final d = log['date'] as String?;
      if (d == null) continue;
      if (earliestWlogDate == null || d.compareTo(earliestWlogDate) < 0) {
        earliestWlogDate = d;
      }
    }
    consider(earliestWlogDate);

    return earliest;
  }

  /// Pure read of the current workout streak. Walks the schedule
  /// backwards and simulates freeze consumption locally to produce
  /// an accurate count, but does NOT persist any state changes.
  ///
  /// C-14 (audit-2026-05-11) — every display surface (RankService
  /// rank-gate check, streakProvider for home, rank_service_record_sheet,
  /// streak_explainer_sheet) calls this and must NOT trigger freeze
  /// consumption as a side effect. Pre-fix `calculateCurrentStreak`
  /// silently consumed freezes on every render — calling it 3× in a
  /// short window could consume 3 different freezes for the same
  /// missed day if the order of state writes raced.
  int currentStreak() => _calculateStreak(consume: false);

  /// Explicit mutating variant — same walk-back logic, but actually
  /// consumes available freezes for missed days and persists the new
  /// state to Hive + cloud. Called from:
  ///   - `train_provider.completeWorkout` (the canonical mutation
  ///     surface where a missed day BEFORE today legitimately needs a
  ///     freeze consumed).
  ///   - A future daily roll-over service if/when one lands.
  ///
  /// Returns the post-consumption streak count so callers can save
  /// it back to user_progress in the same write.
  int consumeMissedDayIfFreezeAvailable() =>
      _calculateStreak(consume: true);

  bool _reckonInFlight = false;

  /// D2 (f9d2e7) — the SINGLE streak-decay reckon site. Runs the schedule
  /// walk-back and PERSISTS any freeze consumption for missed days, but ONLY
  /// when it is safe to do so. Called from the two legitimate decay triggers:
  ///   - `DayRolloverObserver` (every app-open / midnight rollover) so an idle
  ///     user's missed days are reconciled even WITHOUT completing a workout.
  ///     Pre-D2 consume fired ONLY on completeWorkout, so the read-only
  ///     `currentStreak()` display (which SIMULATES consumption) and the
  ///     persisted freeze count silently diverged — the founder's "streak 1 /
  ///     freeze 1 after two idle days" symptom.
  ///   - `train_provider.completeWorkout` (the canonical mutation surface).
  ///
  /// GATES (both must hold to PERSIST; otherwise returns a read-only count):
  ///   1. `restoreCompletedTick > 0` — never decay before the cloud restore has
  ///      confirmed the real completion history. A returning user's cold start
  ///      restores `schedule_*` rows whose `status` may lag; reckoning first
  ///      would read completed days as missed → spurious consume / streak break.
  ///   2. non-empty schedule — a cold-start-empty device has nothing to decay
  ///      (the anchor already bounds the walk; this is belt-and-braces so a
  ///      pre-restore empty box never decays).
  /// In-process reentrancy guard so overlapping triggers can't double-persist.
  ///
  /// Returns the current streak count either way (read-only when gated off) so
  /// callers always get an accurate number to store.
  int reckonStreakDecayAndPersist() {
    if (_reckonInFlight) return currentStreak(); // reentrancy guard
    _reckonInFlight = true;
    try {
      final restoreSettled =
          SyncService.instance.restoreCompletedTick.value > 0;
      if (restoreSettled && _hasAnyScheduleRow()) {
        final streak = consumeMissedDayIfFreezeAvailable(); // persist freezes + count
        _persistCurrentStreakDays(streak); // OBS-8b: keep cloud count fresh on decay
        return streak;
      }
      // Gated off — read-only count, no persist. Breadcrumb (Hermes L37, f9d2e7)
      // so a founder debugging "streak/freeze didn't update after idle days" can
      // see WHY decay was suppressed (debug-only; not release telemetry noise).
      debugPrint('[WorkoutRepository] reckon GATED-OFF: '
          'restoreSettled=$restoreSettled hasSchedule=${_hasAnyScheduleRow()}');
      return currentStreak();
    } finally {
      _reckonInFlight = false;
    }
  }

  /// OBS-8b (2026-06-25) — persist the freshly-computed streak to
  /// `user_progress.current_streak_days`. Pre-fix the reckon stamped ONLY the
  /// freeze fields, so a streak that DECAYED via the day-rollover reckon (no
  /// workout logged) left the cloud count stale: current_streak_days was stamped
  /// ONLY by train_provider on workout COMPLETION (~train_provider.dart:1450). The
  /// AI snapshot (ai_snapshot_builder) + predictions (prediction_service) read this
  /// cloud value, so they saw the old count (the founder's "streak 1 after idle
  /// days" cloud symptom; Home reads a LIVE count so was unaffected). Stamp Hive +
  /// push via syncProgressNow. No-op when already correct (no sync churn). NOT
  /// monotonic — current_streak_days SHOULD decay (unlike lifetime/peak fields,
  /// which need only-increment guards — feedback_monotonic_field_recompute_demotion).
  void _persistCurrentStreakDays(int streak) {
    final progress =
        UserRepository.instance.getProgress() ?? <String, dynamic>{};
    // num-safe cast: a restored / simulated value may deserialize as double.
    if ((progress['current_streak_days'] as num?)?.toInt() == streak) return;
    // updateProgress writes Hive AND fires syncProgressNow() itself
    // (user_repository.dart:146) — call it ONCE; don't double-push the upsert.
    unawaited(
        UserRepository.instance.updateProgress({'current_streak_days': streak}));
  }

  /// True when the local workout box holds at least one `schedule_*` row —
  /// the D2 reckon's non-empty-schedule gate.
  bool _hasAnyScheduleRow() {
    for (final key in _hive.workoutBox.keys) {
      if (key.toString().startsWith('schedule_')) return true;
    }
    return false;
  }

  // `calculateCurrentStreak()` was DELETED here (OI-44 Unit 6, 2026-08-02).
  //
  // It was the C-14 (audit-2026-05-11) back-compat shim: a query-named method
  // delegating straight to the mutating `consumeMissedDayIfFreezeAvailable()`,
  // which is what silently consumed a streak freeze on every render — three
  // display surfaces called it, so three renders could burn three freezes for
  // one missed day. The shim carried that name (and therefore that trap)
  // forward for three months with zero remaining `lib/` callers.
  //
  // Reintroduction is blocked by `scripts/check_cqrs_query_naming.dart`, which
  // resolves same-file delegation transitively — this exact two-hop shape
  // (`calculate* -> consume* -> _calculateStreak(consume: true)`) is the gate's
  // worked example.
  //
  // Use `currentStreak()` for a pure read, or
  // `consumeMissedDayIfFreezeAvailable()` when you actually mean to consume.

  /// Calculates the current workout streak by scanning the schedule backwards.
  ///
  /// Schedule-aware: rest days are invisible and never break the streak.
  /// Only missed *scheduled workout days* cause a break.
  /// Handles schedule changes, template swaps, and cross-week boundaries.
  ///
  /// [consume] — when true, persist freeze consumption to Hive + sync to
  /// cloud. When false, the walk produces the same count but does not
  /// mutate state. C-14 audit-2026-05-11.
  int _calculateStreak({required bool consume}) {
    int streak = 0;
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)

    // B2: stop walk-back before the user's earliest anchor (signup /
    // first workout). Schedule rows before that date are plan-generator
    // artefacts — the user couldn't have completed them.
    final anchor = _earliestUserAnchor();

    // Load freeze data for consumption during streak calculation
    final progress = UserRepository.instance.getProgress() ?? {};
    int freezesAvailable =
        (progress['streak_freezes_available'] as int?) ?? 0;
    final int freezesAvailableBefore = freezesAvailable;
    final usedDatesRaw =
        progress['streak_freeze_used_dates'] as List? ?? <String>[];
    final usedDates = List<String>.from(usedDatesRaw);
    bool freezeConsumedThisCalc = false;
    // Bug 2026-05-19 (B2 telemetry) — capture the dates the walk-back
    // newly flagged as missed in THIS pass so the commitConsume telemetry
    // can record which day the algorithm penalised. If founder reports
    // "I didn't miss that day" we'll know exactly which Hive row to audit.
    final List<String> newlyConsumedDates = <String>[];
    final String walkStartDateStr = formatDateKey(today);

    // Perf: single pass over box.keys to build an in-memory schedule map.
    // Replaces up to 365 sequential box.get('schedule_<date>') calls (~250ms
    // cold on a year-old account) with a single iteration + O(1) map lookups.
    final box = _hive.workoutBox;
    final Map<String, dynamic> scheduleCache = {};
    for (final key in box.keys) {
      final k = key.toString();
      if (!k.startsWith('schedule_')) continue;
      final date = k.substring('schedule_'.length);
      final v = box.get(key);
      if (v != null) scheduleCache[date] = v;
    }

    for (int i = 0; i < 365; i++) {
      final date = today.subtract(Duration(days: i));

      // B2: stop before user's onboarding anchor — pre-account schedule rows
      // must never penalise or consume freezes.
      if (anchor != null && date.isBefore(anchor)) {
        break;
      }

      final dateStr = formatDateKey(date);
      final raw = scheduleCache[dateStr];

      if (raw == null) {
        // No schedule entry — before plan start or gap
        if (streak > 0) break;
        continue;
      }

      final schedule = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final type = schedule['type']?.toString() ?? '';
      final status = schedule['status']?.toString() ?? '';

      // Rest days and travel days are invisible — skip them entirely
      if (type == 'rest' || type == 'off') continue;
      if (status == 'travel') continue;

      // Workout day
      if (status == 'completed') {
        streak += 1;
      } else if (i == 0) {
        // Today's workout not done YET — don't penalize
        continue;
      } else if (usedDates.contains(dateStr)) {
        // Diagnose 2026-05-31 (5e8a1c): this missed day was ALREADY protected
        // by a freeze consumed (and persisted) on an earlier walk. A spent
        // freeze protects its day permanently — treat it as covered, skip it,
        // and never break or double-consume here. Pre-fix the only branch that
        // referenced usedDates was the consume guard (`freezesAvailable > 0 &&
        // !usedDates.contains(dateStr)`); an already-used day failed that guard
        // and fell through to the `else → break`, so every read-only recompute
        // collapsed the streak back at the first historically-frozen day. That
        // silently capped streaks (founder saw "streak only 3" despite full
        // adherence) and starved the sailor-track rank gates (SD1 streak>=7 /
        // LS streak>=14 never qualified → rank stuck at SD2 after Phase 1).
        continue;
      } else if (freezesAvailable > 0) {
        // Fresh missed day — consume a streak freeze if one is available.
        freezesAvailable -= 1;
        usedDates.add(dateStr);
        newlyConsumedDates.add(dateStr);
        freezeConsumedThisCalc = true;
        // Don't increment streak, but don't break — continue checking
        continue;
      } else {
        // Missed scheduled workout day, no freeze left — streak breaks
        break;
      }
    }

    // Persist freeze state if any were consumed AND the caller asked
    // for the mutating variant. C-14 (audit-2026-05-11) — read-only
    // call sites must never mutate. The simulated `freezesAvailable`
    // / `usedDates` are still used above to produce an accurate
    // count, but the persist + sync only fires on `consume: true`.
    //
    // C-15 (audit-2026-05-11) — routed through StreakProgressService
    // as the sole writer. Both refill (home_provider) and consume
    // (here) use commitRefill/commitConsume. Cross-device race
    // protected by migration 056's update_streak_progress RPC.
    if (consume && freezeConsumedThisCalc) {
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: freezesAvailable,
        usedDatesAfterConsume: usedDates,
        freezesAvailableBeforeConsume: freezesAvailableBefore,
        newlyConsumedDates: newlyConsumedDates,
        walkStartDate: walkStartDateStr,
      );
    }

    return streak;
  }

  /// Returns the completion rate (0.0..1.0) of scheduled workout days
  /// over the rolling window of the last `windowWeeks` weeks ending today
  /// (IST). Rest days and pre-onboarding placeholders are excluded from
  /// both numerator and denominator.
  ///
  /// Empty window (no scheduled workouts in range) → 0.0.
  ///
  /// Used by `RankService._qualifies` for ranks with
  /// `completionRateMinimum` (MCPO + officer track per spec §10.4).
  double completionRateOverWindow(int windowWeeks) {
    if (windowWeeks <= 0) return 0.0;
    final box = _hive.workoutBox;
    // IST is UTC+5:30; today derived from IST midnight upper-bound.
    final nowUtc = nowWall().toUtc(); // seam-aware (dev time-travel / year-sim)
    final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));
    final istToday = DateTime(istNow.year, istNow.month, istNow.day);
    final windowStart = istToday.subtract(Duration(days: windowWeeks * 7));

    int scheduled = 0;
    int completed = 0;
    for (var d = windowStart;
        !d.isAfter(istToday);
        d = d.add(const Duration(days: 1))) {
      final dateStr =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final entry = box.get('schedule_$dateStr') as Map?;
      if (entry == null) continue;
      final status = entry['status']?.toString();
      final reason = entry['reason']?.toString();
      // Exclude rest days + pre-onboarding placeholders from both sides.
      if (status == 'rest') continue;
      if (reason == 'pre_onboarding') continue;
      scheduled++;
      if (status == 'completed') completed++;
    }
    if (scheduled == 0) return 0.0;
    return completed / scheduled;
  }

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
    return _schedule.getScheduleForDate(nowWall()); // seam-aware
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
  Future<void> markWorkoutCompleted(DateTime date, {int durationSeconds = 0}) async {
    await _schedule.markCompleted(date, durationSeconds: durationSeconds);
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
      'exercise_logs': exerciseLogs,
    });

    return logId;
  }

  /// Bug #12 — Returns the hour-of-day (0-23) for the most recent [limit]
  /// completed workouts, newest first. Used by the smart streak warning to
  /// compute a personalised "general workout time" via median (more robust
  /// than mean against outliers like one late-night session).
  ///
  /// Empty list = user hasn't logged enough workouts yet → caller should
  /// fall back to a sensible default (19:00 IST per Bug #12 spec).
  List<int> getRecentWorkoutCompletionHours({int limit = 10}) {
    final hours = <int>[];
    final logs = getWorkoutLogs();
    for (final log in logs) {
      final completedAtRaw = log['completed_at'] as String?;
      if (completedAtRaw == null || completedAtRaw.isEmpty) continue;
      final completedAt = DateTime.tryParse(completedAtRaw);
      if (completedAt == null) continue;
      hours.add(completedAt.toLocal().hour);
      if (hours.length >= limit) break;
    }
    return hours;
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
  /// Returns entries with their Hive key injected as `id` so consumers
  /// can drive edits, deletions, etc.
  ///
  /// APK Test #15.1 / Bug F — pre-fix, returned maps did NOT carry the
  /// Hive key, so EditWorkoutLogSheet's `where(log['id'] is String)`
  /// filter stripped every row + showed "No exercise logs for this day"
  /// even when the data was present. Bug class: writer↔reader contract
  /// drift introduced when Test #6 WriteService rewrite never set an
  /// `'id'` value field on the entry map (the id IS the Hive key).
  /// Pre-Test-#6 readers iterated `box.toMap()` directly and saw the
  /// key; the indexed-path readers introduced afterward lost that
  /// visibility.
  ///
  /// Fix: inject the Hive key as `id` on the returned map (both indexed
  /// path AND legacy fallback). Also drops the legacy `type ==
  /// 'exercise_log'` filter — current WriteService doesn't write that
  /// field; use exercise_name presence as the type-discriminator.
  ///
  /// closes-diagnose: 2026-05-12-edit-log-id-injection-f4c9e1
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
          final m = Map<String, dynamic>.from(raw);
          // Bug F — Hive key is the id; inject so consumers can edit/delete.
          m['id'] = id;
          logs.add(m);
        }
      }
      if (logs.isNotEmpty) return logs;
    }

    // Fallback: pre-index data (legacy entries without exercise_log_index_$date).
    // Use the lazily-built secondary date index instead of scanning the entire box.
    final cachedKeys = _ensureExlogDateIndex()[dateStr] ?? const [];
    final logs = <Map<String, dynamic>>[];
    for (final key in cachedKeys) {
      final raw = _hive.workoutBox.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      // Bug F — discriminator is exercise_name presence, NOT a 'type'
      // field. The Test #6 WriteService stopped writing 'type'.
      if (map['exercise_name'] == null) continue;
      // Bug F — inject Hive key as `id` so the legacy-fallback returned
      // shape matches the indexed-path shape.
      map['id'] = key;
      logs.add(map);
    }

    return logs;
  }

  /// Sum of `volume_kg` across every `exlog_*` row in Hive — the user's
  /// lifetime kg lifted across every recorded weight_reps / weighted
  /// bodyweight set. Used by Test #10 obs 2 lifetime ladder summary tile.
  ///
  /// Falls back to `weight_kg × reps_completed` for legacy rows missing
  /// `volume_kg` (pre-Test #6 logs). Bodyweight / timed / cardio logs
  /// have no weight component and are skipped by the volume_kg=0 check.
  double totalLifetimeVolumeKg() {
    var total = 0.0;
    final all = _hive.workoutBox.toMap();
    for (final entry in all.entries) {
      final key = entry.key;
      if (key is! String || !key.startsWith('exlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final stored = (raw['volume_kg'] as num?)?.toDouble() ?? 0.0;
      if (stored > 0) {
        total += stored;
        continue;
      }
      // Legacy fallback — derive from weight × reps.
      final weight = (raw['weight_kg'] as num?)?.toDouble() ?? 0.0;
      final reps = (raw['reps_completed'] as num?)?.toDouble() ?? 0.0;
      if (weight > 0 && reps > 0) total += weight * reps;
    }
    return total;
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

  /// Loads personal records for ALL exercises the user has ever logged.
  ///
  /// Single pass over workoutBox `exlog_*` keys. Groups by exercise name,
  /// tracks best per-set value. Returns sorted by most recent date first.
  ///
  /// audit-2026-05-16 reader-side / R2 — fixed compounded drift:
  /// 1. Filter changed from `raw['type'] != 'exercise_log'` (modern
  ///    `WorkoutWriteService.logExercise` never stamps `type`) to key-
  ///    prefix `exlog_*` (consistent with `_getPersonalRecords` post-
  ///    Test #8 / Theme D fix).
  /// 2. Per-set MAX is now read from canonical `sets[]` array — not from
  ///    the fictional `best_single_set_reps` / `best_single_set_duration`
  ///    fields that the writer never produces.
  /// 3. The legacy fallback `reps_completed / sets_completed.clamp(1,999)`
  ///    is gone — `reps_completed` is SUM (Test #6 writer contract),
  ///    `sets_completed` is null on modern rows → was returning SUM as
  ///    "best per-set" (live bug surfaced as Push Up 100 reps,
  ///    Hanging Leg Raise 85 reps, Jump Rope 5m).
  /// closes-diagnose: 2026-05-16-pr-cumulative-bug
  List<ExercisePR> loadAllExercisePRs() {
    final bestMap = <String, ExercisePR>{};

    final entries = _hive.workoutBox.toMap();
    for (final entry in entries.entries) {
      final keyStr = entry.key.toString();
      if (!keyStr.startsWith('exlog_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      final name = (log['exercise_name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final nameKey = name.toLowerCase();

      final loggingType = (log['logging_type'] as String? ?? 'weight_reps');
      final createdAt = log['created_at'] as String? ?? log['date'] as String? ?? '';
      final date = DateTime.tryParse(createdAt) ?? DateTime(2020);

      // OI-02 / OI-08 (closes-diagnose: 2026-05-17-oi-02-read-services) —
      // per-set MAX semantic delegated to canonical WorkoutReadService.
      // Pre-fix the math was inline here AND duplicated in
      // train_screen.dart `_bestPerSetReps`/`_bestPerSetDuration`.
      double value;
      switch (loggingType) {
        case 'weight_reps':
        case 'weighted_bodyweight':
          value = WorkoutReadService.bestPerSetWeight(log);
          break;
        case 'bodyweight_reps':
          value = WorkoutReadService.bestPerSetReps(log).toDouble();
          break;
        case 'timed':
          value = WorkoutReadService.bestPerSetDuration(log).toDouble();
          break;
        case 'cardio':
          // Cardio: cumulative distance IS the meaningful metric.
          // Read top-level `distance_km` (writer denormalizes the total).
          //
          // Drift-fix 2026-05-24 / T6 — the duration fallback now goes
          // through `WorkoutReadService.bestPerSetDuration` because
          // `WorkoutWriteService` does NOT emit top-level
          // `duration_seconds` on exlog rows (per-set lives at
          // `sets[].duration_sec`). The helper returns max-per-set,
          // sufficient for the PR `value` slot when distance is zero.
          final dist = (log['distance_km'] as num?)?.toDouble() ?? 0;
          final dur =
              WorkoutReadService.bestPerSetDuration(log).toDouble();
          value = dist > 0 ? dist : dur;
          break;
        case 'distance':
          value = (log['distance_km'] as num?)?.toDouble() ?? 0;
          break;
        default:
          value = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      }

      if (value <= 0) continue;

      final existing = bestMap[nameKey];
      if (existing == null || value > existing.bestValue) {
        bestMap[nameKey] = ExercisePR(
          exerciseName: name,
          loggingType: loggingType,
          bestValue: value,
          date: date,
        );
      }
    }

    final result = bestMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

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
  ///
  /// e7a2c4: anchored on the IST calendar date (seam-aware via [istTodayStr])
  /// and bucketed by WHOLE IST calendar days — both `today` and each row's
  /// `date` are reduced to UTC-midnight so the diff is pure day arithmetic with
  /// no timezone or time-of-day drift. Pre-fix it anchored on raw
  /// `DateTime.now()` (device-local wall clock, with its time-of-day) vs a
  /// local-parsed midnight, so the "This Week" count (reports tile + 4-week
  /// frequency chart) could be off by a day near midnight or for a device in a
  /// non-IST timezone, and ignored the dev time-travel / year-sim clock seam.
  List<int> getWeeklyWorkoutCounts() {
    final weekCounts = <int>[0, 0, 0, 0];
    final today = _dayUtc(istTodayStr()); // seam-aware IST "today"
    if (today == null) return weekCounts;

    for (final raw in _hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'workout_log') continue;
      final dateStr = log['date'] as String?;
      if (dateStr == null) continue;
      final date = _dayUtc(dateStr);
      if (date == null) continue;

      final daysAgo = today.difference(date).inDays;
      if (daysAgo < 0) continue; // future-dated row — not in any past week
      // Sliding 7-day windows: daysAgo 0..6 = this week, 7..13 = last week, etc.
      // (a workout exactly 7 days ago is "last week" — intentional). B-pass P2.
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

  /// UTC-midnight DateTime for a `YYYY-MM-DD` string — used for timezone-neutral
  /// whole-day arithmetic (e7a2c4). Returns null on unparseable input.
  static DateTime? _dayUtc(String ymd) {
    final p = DateTime.tryParse(ymd);
    if (p == null) return null;
    return DateTime.utc(p.year, p.month, p.day);
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
          // Unit 7 / OI-50 round-2 — this read ONLY the legacy key, so every
          // cloud-restored `exlog_*` row (which carries `set_number`, never
          // `sets_completed` — sync_workout.dart:762-763) reported 0 sets.
          // Consumers are the AI snapshot builder and the pattern detector,
          // so a restored user's coach reasoned over zeroed set history.
          'sets': WorkoutReadService.aggregateSetCount(log),
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
    // Seam-aware (dev time-travel / year-sim), matching this file's other date
    // reads (:287/:418/:468) — missed in the earlier seam sweep. ⑦(b)'s session
    // resume cut triggers off this gap, so its behavioral test drives it via
    // setTestClockTo; release-identical to DateTime.now().
    final now = nowWall();
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

  // ── Deprecated delegation shims (Theme D1 — Test #11) ───────────
  //
  // These methods previously wrote exlog_* entries directly to Hive using
  // the LEGACY field schema (sets_completed / sets_detail). They now delegate
  // to WorkoutWriteService.logExercise (the single source of truth per
  // docs/architecture/sync.md) which writes the CANONICAL schema (set_number / sets).
  //
  // Marked @Deprecated so callers are flagged for migration to
  // WorkoutWriteService directly. Will be removed in Test #12.

  /// Logs a single exercise's completed sets.
  ///
  /// **Deprecated:** Use [WorkoutWriteService.logExercise] directly.
  /// This shim translates the legacy (exerciseId, weightKg, reps, sets)
  /// parameter shape into a single [ExerciseSet] and delegates to the
  /// canonical writer.
  @Deprecated(
    'Use WorkoutWriteService.logExercise directly. '
    'This method delegates for now; will be removed after Test #12 '
    'once all callers migrated.',
  )
  Future<WriteResult> logExercise({
    required String exerciseId,
    required String exerciseName,
    required double weightKg,
    required int reps,
    required int sets,
    String? loggingType,
    DateTime? date,
    bool fireSyncImmediately = true,
  }) async {
    final effectiveDate = date ?? DateTime.now();
    final setsList = List.generate(
      sets,
      (_) => ExerciseSet(
        weightKg: weightKg,
        reps: reps,
        durationSec: (loggingType == 'timed') ? reps : null,
      ),
    );
    return WorkoutWriteService.instance.logExercise(
      date: effectiveDate,
      exerciseName: exerciseName,
      sets: setsList,
      source: WriteSource.legacyRepository,
    );
  }

  /// Updates an existing exercise log entry identified by [logKey].
  ///
  /// **Deprecated:** Use [WorkoutWriteService.editLog] directly.
  /// This shim delegates to the canonical edit path.
  @Deprecated(
    'Use WorkoutWriteService.editLog directly. '
    'This method delegates for now; will be removed after Test #12 '
    'once all callers migrated.',
  )
  Future<WriteResult> updateExerciseLog({
    required String logKey,
    required Map<String, dynamic> updates,
  }) async {
    return WorkoutWriteService.instance.editLog(
      logKey: logKey,
      updates: updates,
      source: WriteSource.legacyRepository,
    );
  }

  // ── Custom Exercise Creation ─────────────────────────────────

  /// Creates a new custom exercise in the user's library.
  ///
  /// Mirrors the write performed by `CreateCustomExerciseSheet._save()` so
  /// AI-coach-created customs are byte-identical to UI-created customs:
  ///   - Deterministic v5 UUID per docs/architecture/database.md
  ///     (namespace `5a1f0b0c-9dad-11d1-80b4-00c04fd430c8`,
  ///     name = `<user_id>|exercise|<lower(name)>`).
  ///   - Same map shape (id / name / category / logging_type / default_sets
  ///     / default_reps? / default_duration_seconds? / primary_muscles /
  ///     equipment_needed / is_custom / type / submitted_to_library /
  ///     approved_for_library / created_at).
  ///   - Stored under `custom_exercise_<millisSinceEpoch>` in customBox.
  ///   - Fires `syncCustomItemsNow()` (writes the
  ///     `user_custom_exercises` row) and `pushSnapshot()` (refreshes the
  ///     AI coach context — without this, the new exercise is invisible
  ///     to the coach until next app launch — see CLAUDE.md "Custom
  ///     exercise invisible to AI coach" bug).
  ///
  /// Returns the deterministic exercise ID. Throws
  /// [CreateCustomExerciseException] for invalid input or duplicate name.
  Future<String> createCustomExercise({
    required String name,
    required String category,
    required String equipment,
    required String loggingType,
    List<String>? primaryMuscles,
    int defaultSets = 3,
    int? defaultReps,
    int? defaultDurationSeconds,
    bool submittedToLibrary = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const CreateCustomExerciseException(
        'invalid_input',
        'Exercise name cannot be empty.',
      );
    }
    if (trimmed.length > 60) {
      throw const CreateCustomExerciseException(
        'invalid_input',
        'Exercise name must be 60 characters or less.',
      );
    }

    // Deterministic v5 UUID per docs/architecture/database.md. Same algorithm as
    // CreateCustomExerciseSheet._save() — keeps cross-device upserts
    // idempotent so AI- and UI-created customs collapse correctly.
    const customNs = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
    final userId = SupabaseService.instance.currentUser?.id ?? 'anon';
    final id = const Uuid()
        .v5(customNs, '$userId|exercise|${trimmed.toLowerCase()}');

    // Duplicate-name guard — scan customBox for an existing entry with the
    // same deterministic ID (different keys, same logical exercise).
    final customBox = _hive.customBox;
    for (final k in customBox.keys) {
      final v = customBox.get(k);
      if (v is Map && v['id'] == id) {
        throw CreateCustomExerciseException(
          'duplicate_name',
          'A custom exercise named "$trimmed" already exists.',
        );
      }
    }

    final key = 'custom_exercise_${DateTime.now().millisecondsSinceEpoch}';
    final exercise = <String, dynamic>{
      'id': id,
      'name': trimmed,
      'category': category,
      'logging_type': loggingType,
      'default_sets': defaultSets,
      // Match the sheet's conditional shape: only store reps when
      // logging_type is rep-based; only store duration when timed.
      'default_reps': ?defaultReps?.toString(),
      'default_duration_seconds': ?defaultDurationSeconds,
      'primary_muscles': primaryMuscles ?? <String>[],
      // ⑥ slice A: normalize the caller-supplied (AI/free-text) equipment to the
      // canonical vocab so a custom exercise's equipment_needed matches the
      // library's (and slice B's item-filter can read it). May be [] if the
      // token is unmappable — [] = no equipment requirement (never over-excludes).
      'equipment_needed': EquipmentVocab.normalize(<String>[equipment]),
      'is_custom': true,
      'type': 'exercise',
      'submitted_to_library': submittedToLibrary,
      'approved_for_library': false,
      'created_at': DateTime.now().toIso8601String(),
    };

    // Audit 2026-05-20 / A3: route through WorkoutWriteService
    // .upsertCustomExercise (was direct customBox.put + duplicated sync
    // fanout). Service handles lock, telemetry pair, sync fan-out.
    await WorkoutWriteService.instance.upsertCustomExercise(
      key: key,
      exercise: exercise,
      source: WriteSource.manual,
    );

    return id;
  }

  // ── Custom Template Creation (Phase D.6) ─────────────────────

  /// Creates one or more custom workout templates in the user's library
  /// (Phase D.6 — `createCustomTemplate` AI coach tool).
  ///
  /// Mirrors the write performed by [TemplatesNotifier.saveTemplate] so
  /// AI-coach-created templates are byte-identical to UI-created ones:
  ///   - Hive key: `tmpl_<millisSinceEpoch>` (with per-day suffix when
  ///     more than one day is supplied).
  ///   - Map shape: `{id, name, description?, exercises[], exercise_count,
  ///     workout_type:'custom', type:'template', created_at, assigned_days?,
  ///     group_id, group_day_index}` — `group_id`/`group_day_index` are
  ///     extra metadata so the multi-day grouping survives across tools
  ///     (e.g. Phase D.7's `scheduleTemplate` can fan out by group).
  ///   - Deterministic v5 UUID per docs/architecture/database.md
  ///     (namespace `5a1f0b0c-9dad-11d1-80b4-00c04fd430c8`,
  ///     name = `<user_id>|template|<lower(name)>` for the group ID).
  ///
  /// Because the existing Hive shape is single-day-per-template (the
  /// Template Builder UI is single-day), each `days[]` entry becomes its
  /// own `tmpl_*` row named `"<name> - <dayName>"`. This keeps the existing
  /// readers ([TemplatesNotifier], `_syncWorkoutTemplates`,
  /// `WorkoutScheduleService.assignTemplateToDate`) working unchanged.
  ///
  /// Each `days[i]` map MUST contain:
  ///   - `dayName` (String)
  ///   - `exercises` (List<Map>) where each exercise has:
  ///       `exerciseId`, `exerciseName`, `sets`, `reps`,
  ///       optional `restSeconds`, optional `durationSeconds`
  ///
  /// Fires `unawaited(SyncService.instance.syncWorkoutData())` and
  /// `unawaited(SyncService.instance.pushSnapshot())` so the cloud
  /// `workout_templates`/`template_exercises` rows AND the AI coach
  /// snapshot pick up the new templates immediately (CLAUDE.md
  /// "Custom exercise invisible to AI coach" precedent — same fix
  /// applies to templates).
  ///
  /// Returns the deterministic group ID. Throws
  /// [CreateTemplateException] for invalid input or duplicate name.
  Future<String> createTemplate({
    required String name,
    String? description,
    required List<Map<String, dynamic>> days,
    List<int>? assignedDays,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const CreateTemplateException(
        'invalid_input',
        'Template name cannot be empty.',
      );
    }
    if (trimmed.length > 60) {
      throw const CreateTemplateException(
        'invalid_input',
        'Template name must be 60 characters or less.',
      );
    }
    if (days.isEmpty) {
      throw const CreateTemplateException(
        'invalid_input',
        'Template must contain at least one day.',
      );
    }

    // Deterministic v5 UUID — same algorithm as createCustomExercise
    // (docs/architecture/database.md). Keeps cross-device upserts idempotent and lets the
    // `tmpl_*` group survive a re-create on another device.
    const customNs = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
    final userId = SupabaseService.instance.currentUser?.id ?? 'anon';
    final groupId = const Uuid()
        .v5(customNs, '$userId|template|${trimmed.toLowerCase()}');

    // Duplicate-name guard — scan workoutBox for any existing template
    // sharing this group_id (a re-run of the same AI tool against the same
    // template name would otherwise create a parallel set of `tmpl_*`
    // rows that look identical to the user).
    final box = _hive.workoutBox;
    for (final k in box.keys) {
      final v = box.get(k);
      if (v is Map &&
          v['type'] == 'template' &&
          v['group_id'] == groupId) {
        throw CreateTemplateException(
          'duplicate_name',
          'A template named "$trimmed" already exists.',
        );
      }
    }

    final createdAt = DateTime.now().toIso8601String();
    final assignedDaysSorted = assignedDays != null
        ? (List<int>.from(assignedDays)..sort())
        : null;

    // One Hive `tmpl_*` row per day. Ordered keys (added 1ms apart) so
    // the templates list reflects the AI's intended day order.
    int writtenDays = 0;
    for (int i = 0; i < days.length; i++) {
      final day = Map<String, dynamic>.from(days[i]);
      final dayName = (day['dayName'] as String?)?.trim() ?? 'Day ${i + 1}';
      final rawExercises = (day['exercises'] as List?) ?? const [];

      // Translate the tool's per-exercise shape to the Hive shape that
      // `_syncWorkoutTemplates` and the active-workout flow already
      // understand (`exercise_id` / `exercise_name` / `sets` / `reps` /
      // `rest_seconds`).
      final exercises = <Map<String, dynamic>>[];
      for (final raw in rawExercises) {
        if (raw is! Map) continue;
        final ex = Map<String, dynamic>.from(raw);
        final exerciseId = ex['exerciseId']?.toString();
        final exerciseName = ex['exerciseName']?.toString();
        if (exerciseId == null ||
            exerciseId.isEmpty ||
            exerciseName == null ||
            exerciseName.isEmpty) {
          continue;
        }
        final mapped = <String, dynamic>{
          'exercise_id': exerciseId,
          'exercise_name': exerciseName,
          'sets': (ex['sets'] as num?)?.toInt() ?? 3,
          'reps': ex['reps']?.toString() ?? '10',
          'rest_seconds': (ex['restSeconds'] as num?)?.toInt() ?? 60,
        };
        final dur = (ex['durationSeconds'] as num?)?.toInt();
        if (dur != null && dur > 0) {
          mapped['time_secs'] = dur;
          mapped['logging_type'] = 'timed';
        }
        exercises.add(mapped);
      }

      if (exercises.isEmpty) {
        // Skip empty days silently rather than throwing — the model
        // sometimes emits a placeholder day without exercises and we'd
        // rather create what we can than refuse the whole template.
        continue;
      }

      final perDayName = days.length == 1 ? trimmed : '$trimmed - $dayName';
      final perDayId =
          'tmpl_${DateTime.now().millisecondsSinceEpoch + i}';

      final templateMap = <String, dynamic>{
        'id': perDayId,
        'name': perDayName,
        'exercises': exercises,
        'exercise_count': exercises.length,
        'workout_type': 'custom',
        'type': 'template',
        'created_at': createdAt,
        // Multi-day grouping metadata — extra fields are tolerated by
        // both `templatesProvider` and `_syncWorkoutTemplates`.
        'group_id': groupId,
        'group_day_index': i,
        'group_total_days': days.length,
        'group_name': trimmed,
        'day_name': dayName,
        if (description != null && description.isNotEmpty)
          'description': description,
        // Mirror the Template Builder behaviour — a single weekday is
        // attached when the AI provided a 1:1 days/assignedDays mapping.
        if (assignedDaysSorted != null &&
            i < assignedDaysSorted.length)
          'assigned_days': <int>[assignedDaysSorted[i]],
      };

      await box.put(perDayId, templateMap);
      writtenDays++;
    }

    if (writtenDays == 0) {
      throw const CreateTemplateException(
        'invalid_input',
        'Template had no valid exercises in any day.',
      );
    }

    // Fire-and-forget — push the new templates to cloud and refresh the
    // AI snapshot so the coach can reference them on the very next turn.
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());

    return groupId;
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime date) => formatDateKey(date);

  /// Returns the Monday of the week containing [date].
  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1; // Monday=1 -> 0
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  /// Sum of `volume_kg` across every exercise log in Hive. Returned
  /// as a list of doubles so callers can sum / aggregate. Reads
  /// raw box once — O(n) over the workoutBox key set, called only
  /// from Profile Service Record on screen build (rare).
  List<double> getAllExerciseLogKeysForLifetimeSum() {
    final out = <double>[];
    for (final v in _hive.workoutBox.values) {
      if (v is! Map) continue;
      final type = v['type']?.toString();
      if (type != 'exercise_log') continue;
      final raw = v['volume_kg'];
      if (raw is num) out.add(raw.toDouble());
    }
    return out;
  }
}

/// Thrown by [WorkoutRepository.createCustomExercise] for input validation
/// failures or duplicate names. [code] is one of:
///   - `invalid_input` — name empty / too long / other validation
///   - `duplicate_name` — an exercise with the same deterministic ID
///     already exists in the user's library
///   - `other` — unexpected
class CreateCustomExerciseException implements Exception {
  final String code;
  final String message;
  const CreateCustomExerciseException(this.code, this.message);
  @override
  String toString() => 'CreateCustomExerciseException($code): $message';
}

/// Thrown by [WorkoutRepository.createTemplate] (Phase D.6 createCustomTemplate)
/// for input validation failures or duplicate names. [code] is one of:
///   - `invalid_input` — name empty / too long / no days / no valid exercises
///   - `duplicate_name` — a template with the same deterministic group ID
///     already exists in the user's library
///   - `other` — unexpected
class CreateTemplateException implements Exception {
  final String code;
  final String message;
  const CreateTemplateException(this.code, this.message);
  @override
  String toString() => 'CreateTemplateException($code): $message';
}

