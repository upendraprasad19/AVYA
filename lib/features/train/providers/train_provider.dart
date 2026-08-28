import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/utils/exercise_display.dart';
import 'package:icanbefitter/core/utils/phase_completion.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/detraining.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import '../repositories/workout_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/core/constants/equipment_defaults.dart';

// ── Last Performance Data ────────────────────────────────────────

class LastPerformanceData {
  final double? lastWeight;
  final int? lastReps;
  final int? lastSets;
  final DateTime? lastDate;
  final double? suggestedWeight; // lastWeight + 2.5 (or null for bodyweight/timed/cardio)

  const LastPerformanceData({
    this.lastWeight,
    this.lastReps,
    this.lastSets,
    this.lastDate,
    this.suggestedWeight,
  });

  bool get hasData => lastWeight != null || lastReps != null;
}

/// OI-39 (audit-2026-05-17 Hermes C5) — delegates to
/// `WorkoutReadService.logsForExercise()`. Pre-fix this method
/// iterated `workoutBox.values` inline + filtered by `type == 'exercise_log'`
/// (depended on the writer stamping that string field). Now the read
/// service owns the cross-date scan + name match; this function only
/// extracts the latest row's per-set values for the pre-fill UI.
LastPerformanceData _getLastPerformance(String exerciseName) {
  final logs = WorkoutReadService.instance.logsForExercise(exerciseName);
  if (logs.isEmpty) {
    return const LastPerformanceData(
      lastWeight: null,
      lastReps: null,
      lastSets: null,
      lastDate: null,
      suggestedWeight: null,
    );
  }
  // logsForExercise returns chronologically sorted (oldest first); last
  // is most recent.
  final latest = logs.last;
  final dateStr = latest['date'] as String?;
  final latestDate = dateStr != null ? DateTime.tryParse(dateStr) : null;

  // Bug a8f1c2 (APK Test #15.3) — pre-fill UX needs FIRST SET values,
  // not workout aggregates. The top-level `reps_completed` / `weight_kg`
  // are SUM/MAX per WorkoutWriteService contract; reading them as
  // "per-set" pre-fills "85 reps" into every set on a 7-set session.
  // Legacy rows (pre-Test-#6) lack sets[] — fall through to null; UI
  // shows empty inputs / prescribed default.
  final sets = latest['sets'];
  double? lastWeight;
  int? lastReps;
  if (sets is List && sets.isNotEmpty) {
    final first = sets.first;
    if (first is Map) {
      lastWeight = (first['weight_kg'] as num?)?.toDouble();
      lastReps = (first['reps'] as num?)?.toInt();
    }
  }
  // Bug a8f1c2 sibling — `set_number` is canonical post-Test-#6,
  // `sets_completed` is legacy. Read both with fallback.
  final lastSets =
      (latest['set_number'] as int?) ?? (latest['sets_completed'] as int?);
  final loggingType = latest['logging_type'] as String?;

  double? suggested;
  if (lastWeight != null &&
      lastWeight > 0 &&
      (loggingType == 'weight_reps' || loggingType == 'weighted_bodyweight')) {
    suggested = lastWeight + 2.5;
  }

  return LastPerformanceData(
    lastWeight: lastWeight,
    lastReps: lastReps,
    lastSets: lastSets,
    lastDate: latestDate,
    suggestedWeight: suggested,
  );
}

final lastPerformanceProvider =
    Provider.family<LastPerformanceData, String>((ref, exerciseName) {
  return _getLastPerformance(exerciseName);
});

/// OI-39 (audit-2026-05-17 Hermes C5) — delegates to
/// `WorkoutReadService.logsForExercise()`. Pre-fix iterated workoutBox
/// inline; now reuses the canonical cross-date scan + name match.
final exerciseHistoryProvider =
    Provider.family<List<double>, String>((ref, exerciseName) {
  final logs = WorkoutReadService.instance.logsForExercise(exerciseName);
  final weights = <double>[];
  for (final log in logs) {
    final w = (log['weight_kg'] as num?)?.toDouble();
    if (w != null && w > 0) weights.add(w);
  }
  if (weights.length > 8) {
    return weights.sublist(weights.length - 8);
  }
  return weights;
});

// ── Data Classes ────────────────────────────────────────────────

/// Exercise data used within a workout day.
class ExerciseData {
  final String name;
  final String sets;
  final String reps;
  final String weight;
  final String rest;
  final String loggingType;
  final String? category;
  final List<String>? equipmentNeeded;
  final String? exerciseType; // 'compound' or 'isolation'
  final int? supersetGroup; // null = standalone, 0/1/2... = superset group index
  final String? muscleLabel; // experience-appropriate muscle label (e.g. "Back", "Lats", "Lats (Width)")
  final String? exerciseId; // W3.3 (Batch 11-A): library exercise id — forward-only, null on legacy/custom.

  const ExerciseData({
    required this.name,
    this.sets = '3',
    this.reps = '10',
    this.weight = '0kg',
    this.rest = '90s',
    this.loggingType = 'weight_reps',
    this.category,
    this.equipmentNeeded,
    this.exerciseType,
    this.supersetGroup,
    this.muscleLabel,
    this.exerciseId,
  });

  /// Shape-tolerant parse of a raw library `equipment_needed` value. It is a List
  /// on 249/258 rows but was a bare String on 9 (E252–E260 — fixed to Lists in the
  /// library + seed v6). A naive `as List?` cast THREW on the String, crashing the
  /// swap / add-exercise picker (swap_sheets). Never crashes: List → stringified
  /// list; non-empty String → single-element list; null/empty → const [].
  static List<String> parseEquipmentNeeded(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.trim().isNotEmpty) return [raw];
    return const [];
  }

  ExerciseData copyWith({
    String? name,
    String? sets,
    String? reps,
    String? weight,
    String? rest,
    String? loggingType,
    String? category,
    List<String>? equipmentNeeded,
    String? exerciseType,
    int? Function()? supersetGroup,
    String? Function()? muscleLabel,
    String? exerciseId,
  }) {
    return ExerciseData(
      name: name ?? this.name,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      rest: rest ?? this.rest,
      loggingType: loggingType ?? this.loggingType,
      category: category ?? this.category,
      equipmentNeeded: equipmentNeeded ?? this.equipmentNeeded,
      exerciseType: exerciseType ?? this.exerciseType,
      supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
      muscleLabel: muscleLabel != null ? muscleLabel() : this.muscleLabel,
      // W3.3 (Batch 11-A): PRESERVE the id — no copyWith changes `name`, so keeping
      // the id is always correct; dropping it would ship the WRITE largely inert.
      exerciseId: exerciseId ?? this.exerciseId,
    );
  }

  /// Whether this exercise is a compound movement (for warm-up auto-suggest).
  bool get isCompound {
    if (exerciseType?.toLowerCase() == 'compound') return true;
    final nameLower = name.toLowerCase();
    return nameLower.contains('bench') ||
        nameLower.contains('squat') ||
        nameLower.contains('deadlift') ||
        nameLower.contains('overhead press') ||
        nameLower.contains('barbell row') ||
        nameLower.contains('pull-up') ||
        nameLower.contains('dip');
  }
}

/// A single day in the workout plan.
class WorkoutDayData {
  final int dayNumber;
  final String name;
  final String subtitle;
  final String? dateLabel; // e.g. "Mon, Mar 24"
  final DateTime? date; // actual calendar date
  final bool isRest;
  final bool isDone;
  final List<ExerciseData> exercises;
  final List<ExerciseData> warmup;
  final List<ExerciseData> cooldown;

  const WorkoutDayData({
    required this.dayNumber,
    required this.name,
    this.subtitle = '',
    this.dateLabel,
    this.date,
    this.isRest = false,
    this.isDone = false,
    this.exercises = const [],
    this.warmup = const [],
    this.cooldown = const [],
  });

  int get exerciseCount => exercises.length;
  String get estimatedDuration {
    if (isRest) return '';
    final totalSets =
        exercises.fold<int>(0, (sum, e) => sum + (int.tryParse(e.sets) ?? 3));
    return '${(totalSets * 2.5).round()} min';
  }
}

// ── Swap exercise data ──────────────────────────────────────────

class SwapExerciseData {
  final String name;
  final String detail;
  final String emoji;

  /// W3.3 (Batch 11-A): the swapped-in exercise's library id, when the picker
  /// row carries one (`ExerciseRepository` seed rows do — the Hive key == id).
  /// null → the swap logs match history by name (forward-only fallback).
  final String? id;

  const SwapExerciseData({
    required this.name,
    required this.detail,
    this.emoji = '',
    this.id,
  });
}

// sampleSwapExercises removed — ExerciseSwapSheet queries Hive exerciseBox
// via ExerciseRepository.instance directly.

// ── Exercise map parser (shared for exercises, warmup, cooldown) ──

/// Parse a duration in seconds for a `timed` exercise.
///
/// Reads numeric fields first (`prescribed_time_secs`, `default_duration_secs`),
/// then falls back to parsing the `default_reps` text field which can take many
/// shapes in the bundled exercise library:
///   "30-60 sec"     → 45  (median of range)
///   "60 sec"        → 60
///   "3 min rounds"  → 180 (minutes → seconds)
///   "5-10 sec"      → 7
///   "45-60 sec each"→ 52
///   "varies"        → 30  (default fallback)
///
/// Returns 30 if everything fails. The UI must NEVER render `0s` for a timed
/// exercise — that's the Bug #16 regression we're guarding against.
int _parseTimedDurationSecs(Map<String, dynamic> m) {
  // 1. Prefer explicit numeric fields if present.
  final prescribed = m['prescribed_time_secs'];
  if (prescribed is int && prescribed > 0) return prescribed;
  if (prescribed is num && prescribed > 0) return prescribed.toInt();

  final defaultSecs = m['default_duration_secs'];
  if (defaultSecs is int && defaultSecs > 0) return defaultSecs;
  if (defaultSecs is num && defaultSecs > 0) return defaultSecs.toInt();

  // 2. Parse the text field (`reps`/`prescribed_reps`/`default_reps`).
  final raw = (m['reps'] as String?) ??
      (m['prescribed_reps'] as String?) ??
      (m['default_reps'] as String?) ??
      '';
  if (raw.isEmpty) return 30;

  final lower = raw.toLowerCase();
  // Extract all numbers in the text.
  final numbers = RegExp(r'\d+')
      .allMatches(lower)
      .map((m) => int.tryParse(m.group(0) ?? '') ?? 0)
      .where((n) => n > 0)
      .toList();
  if (numbers.isEmpty) return 30;

  // Compute the average (handles both single value and ranges like "30-60").
  final avg = numbers.reduce((a, b) => a + b) ~/ numbers.length;

  // Detect time unit. Default unit is seconds.
  if (lower.contains('min') || lower.contains('m ')) {
    // Minutes → seconds
    return avg * 60;
  }
  // Anything else (sec, s, "each", "rounds", bare number) → treat as seconds.
  return avg > 0 ? avg : 30;
}

List<ExerciseData> _parseExerciseMaps(List? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw.map((e) {
    final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
    final equipList = ExerciseData.parseEquipmentNeeded(m['equipment_needed']);

    String? category = m['category'] as String?;
    if (category == null || category.isEmpty) {
      final name = (m['exercise_name'] as String? ?? '').toLowerCase();
      final exId = m['exercise_id'] as String?;
      if (exId != null && exId.isNotEmpty) {
        final libEx = ExerciseRepository.instance.getById(exId);
        category = libEx?['category'] as String?;
      }
      if (category == null || category.isEmpty) {
        final results = ExerciseRepository.instance.search(name);
        if (results.isNotEmpty) {
          category = results.first['category'] as String?;
        }
      }
    }

    final loggingType = m['logging_type'] as String? ?? 'weight_reps';

    // For timed exercises, normalise `reps` to a clean numeric string of seconds
    // so downstream UI can parse it without re-deriving from the messy text.
    // Fixes Bug #16: Plank/Dead Bug previously rendered as "0s" because their
    // default_reps was "30-60 sec" which int.tryParse() returned null on.
    final String repsValue;
    if (loggingType == 'timed') {
      repsValue = '${_parseTimedDurationSecs(m)}';
    } else {
      repsValue = m['reps'] as String? ??
          m['prescribed_reps'] as String? ??
          m['default_reps'] as String? ??
          '10';
    }

    // Resolve muscle label using the exercise library entry when available,
    // falling back to the parsed category so beginners at minimum see "Back".
    String? muscleLabel;
    final exerciseName = (m['exercise_name'] as String? ?? m['name'] as String? ?? '').toLowerCase();
    Map<String, dynamic>? libEntry;
    final exId = m['exercise_id'] as String?;
    if (exId != null && exId.isNotEmpty) {
      libEntry = ExerciseRepository.instance.getById(exId);
    }
    libEntry ??= ExerciseRepository.instance.search(exerciseName).firstOrNull;
    if (libEntry != null) {
      muscleLabel = ExerciseDisplay.formatMuscleLabel(libEntry);
    } else if (category != null && category.isNotEmpty) {
      // No library entry — synthesise a minimal map so formatMuscleLabel
      // can still return the category-level label for beginner/intermediate.
      muscleLabel = ExerciseDisplay.formatMuscleLabel({'category': category, 'target_focus': ''});
    }

    return ExerciseData(
      name: m['exercise_name'] as String? ?? m['name'] as String? ?? 'Unknown',
      sets: '${m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3}',
      reps: repsValue,
      weight: '0kg',
      rest: '${m['rest_seconds'] ?? 60}s',
      loggingType: loggingType,
      category: category,
      equipmentNeeded: equipList,
      exerciseType: m['exercise_type'] is List
          ? ((m['exercise_type'] as List).isNotEmpty
              ? (m['exercise_type'] as List).first.toString()
              : null)
          : m['exercise_type'] as String?,
      supersetGroup: m['superset_group'] as int?,
      muscleLabel: muscleLabel,
      // W3.3 (Batch 11-A): thread the library exercise id from the schedule row.
      exerciseId: m['exercise_id'] as String?,
    );
  }).toList();
}

// ── Current Plan ─────────────────────────────────────────────────

class CurrentPlanData {
  final int phase;
  final String phaseName;
  final int currentWeek;
  final String focus;
  final List<List<WorkoutDayData>> weeks;
  final bool hasPlan;
  final bool isGenerating; // true when plan generation is in progress

  const CurrentPlanData({
    this.phase = 1,
    this.phaseName = 'Foundation',
    this.currentWeek = 1,
    this.focus = 'Movement patterns & baseline strength',
    this.weeks = const [],
    this.hasPlan = false,
    this.isGenerating = false,
  });

  /// Get workouts for a specific week (1-indexed).
  List<WorkoutDayData> getWeek(int weekNumber) {
    final index = weekNumber - 1;
    if (index < 0 || index >= weeks.length) return [];
    return weeks[index];
  }

  /// Get today's workout (first non-rest, non-done workout in current week).
  WorkoutDayData? get todayWorkout {
    final weekDays = getWeek(currentWeek);
    final todayStr = istTodayStr();

    // First, try to find the workout for today's actual date.
    for (final day in weekDays) {
      if (day.date != null) {
        final dayStr = formatDateKey(day.date!);
        if (dayStr == todayStr && !day.isRest && !day.isDone) return day;
      }
    }

    // Fallback: first non-rest, non-done workout in current week.
    // ⚠ This can return a day whose `date` is in the PAST (today had no match).
    // Fine for DISPLAY ("your next unfinished workout"), but never treat the
    // returned day's `date` as the session date — see the clamp in
    // `completeWorkout`, and prefer `workoutDayForDate` when the caller needs
    // "the workout scheduled for THIS date".
    for (final day in weekDays) {
      if (!day.isRest && !day.isDone) return day;
    }
    return null;
  }
}

/// Pure: resolves the date a COMPLETED session must be logged under.
///
/// A session belongs to the day it was PERFORMED. [scheduledDate] (the plan-day
/// being performed) is honoured ONLY when it already IS today —
/// [CurrentPlanData.todayWorkout]'s fallback can hand back a PAST day, and
/// logging to it wrote `exlog_<pastDate>`/`wlog_<pastDate>` and marked the PAST
/// schedule row completed while today's row stayed `planned` forever,
/// corrupting every downstream reader of the log date (streak, PRs,
/// ProgressionResolver, e1RM history, adherence).
///
/// Extracted pure so the guard is behaviorally testable without driving the
/// whole `completeWorkout` side-effect chain — same pattern as
/// `RankService.shouldPromote` (rule 21 / `feedback_source_grep_false_confidence`).
DateTime resolveSessionDate({
  required DateTime? scheduledDate,
  required DateTime now,
}) {
  if (scheduledDate == null) return now;
  return formatDateKey(scheduledDate) == formatDateKey(now)
      ? scheduledDate
      : now;
}

/// Resolves the weekly-streak identity, the `streaks` row key, and the day
/// counts for ONE completion — the four values `completeWorkout` needs to
/// reckon the weekly streak.
///
/// Two defects live in the block this replaces (diagnose `<6hex>`):
///
///  1. **The streak was dead during a hold week.** `getCurrentWeekNumber()`
///     clamps to `[1,4]` and a hold starts at `plan_start + 28`, so the dedup
///     gate was `4 != 4` → `current_streak_weeks` froze for the whole hold, and
///     the row key was always week 4's Monday → every hold completion
///     OVERWROTE that one row (cloud `streaks` is `UNIQUE(user_id, week_start)`).
///  2. **`planned` and `completedCount` filtered differently.** `planned` took
///     `type == 'workout'` while the numerator took no type filter at all. At
///     100% template conversion `planned == 0`, and the caller gates BOTH the
///     increment and the row write on `planned > 0` — so a PRO user with a
///     fully self-built week and perfect adherence got zero streak credit and
///     no cloud row. Both sides now share [isTrainingDayType].
///
/// ⚠️ The two arms use DIFFERENT week numbers, and conflating them is a live
/// regression. The NON-HOLD arm must stay CLAMPED: `redoWeek4` extends only
/// `plan_end` (it never writes `plan_start`), so a user who has rolled week 4
/// sits at a true date-index ≥ 5 while `getCurrentWeekNumber()` reports 4.
/// Feeding an unclamped index to `getWeek()` would hand them a different week's
/// rows and a different row key — with the flag OFF. The unclamped index exists
/// ONLY in the hold arm and must never reach `getWeek()`.
///
/// ⚠️ [planStart] MUST equal the Hive `plan_start_date`. Both arms re-read it
/// internally (`getCurrentWeekNumber`, `getWeek`), so a disagreeing value
/// yields a coherent-looking but meaningless record. Production hoists it from
/// `getPlanStartDate()`; tests must seed both consistently.
///
/// [holdOrdinal] is `null` when not holding — the caller sources it from
/// `holdStatusProvider`, which returns `HoldStatusData.empty` whenever
/// `enable_hold_weeks` is OFF. That keeps the flag check in ONE place per the
/// `hold_display_read_path` contract; this function never reads
/// `PlanEngineFlags`.
///
/// Extracted (both arms, not just the hold math) so every assertion is testable
/// without driving `completeWorkout`, which needs full `startWorkout` state and
/// fans out to Sync/Rank/Badge — same pattern as [resolveSessionDate].
({int streakWeekId, DateTime? weekStartDate, int planned, int completedCount})
    resolveStreakWeekState({
  required WorkoutScheduleReadService readSvc,
  required DateTime? planStart,
  required int? holdOrdinal,
  required DateTime workoutDate,
}) {
  // The INJECTED ordinal is the FLAG GATE only — it is null whenever
  // enable_hold_weeks is OFF, because holdStatusProvider returns
  // HoldStatusData.empty in that case. The ordinal that actually drives the
  // COUNTS is re-derived from workoutDate, because the two can disagree:
  // holdStatusProvider computes todayHoldOrdinal from nowWall() at provider-
  // BUILD time and is cached until currentPlanProvider invalidates, which
  // completeWorkout does only at its very last statement. A session left
  // foregrounded across a Sunday→Monday midnight rollover (a late workout with
  // the screen awake — DayRolloverObserver fires only on resumed/paused, never
  // mid-foreground) therefore carries an ordinal for the PREVIOUS hold week
  // while workoutDate is already in the next one. Trusting it would key the
  // row to one week and populate it from another. Re-deriving makes the
  // identity, the row key and the counts describe the SAME week by
  // construction. A null here means workoutDate is not a hold day at all (the
  // hold elapsed, or the user rolled out of it) → take the clamped arm.
  final effectiveOrdinal = (holdOrdinal == null || planStart == null)
      ? null
      : readSvc.holdOrdinalForDate(workoutDate);

  if (effectiveOrdinal == null || planStart == null) {
    // NON-HOLD — CLAMPED. Value-identical to the pre-fix behaviour except that
    // both counts now share one predicate.
    final weekNum = readSvc.getCurrentWeekNumber();
    final weekDays = readSvc.getWeek(weekNum);
    return (
      streakWeekId: weekNum,
      weekStartDate: planStart?.add(Duration(days: (weekNum - 1) * 7)),
      planned: weekDays.where((d) => isTrainingDayType(d['type'])).length,
      completedCount: weekDays
          .where((d) =>
              isTrainingDayType(d['type']) && d['status'] == 'completed')
          .length,
    );
  }

  // HOLD — UNCLAMPED date-week index, derived BY DATE. Never `4 + ordinal`:
  // `holdWeek()` places the hold in the calendar week containing today, so a
  // late return leaves a real gap (ordinal 1 can sit at date-week 8) and the
  // ordinal is a LABEL, not a date offset. Never `HoldWeekInfo.weekStart`
  // either — that is the first SURVIVING hold date, so a missing Monday row
  // makes it a Tuesday, which is wrong for a row key.
  final holdMonday = readSvc.normalizeToMonday(workoutDate);
  final ps = DateTime(planStart.year, planStart.month, planStart.day);
  // Date-sourced via `_holdDatesByOrdinal` → `getScheduleForDate`, so the
  // completed-in-future normalization guard applies; and it already skips rest
  // rows BEFORE incrementing either counter, so this arm is symmetric by
  // construction and needs no separate numerator filter.
  final sessions = readSvc.holdWeekSessionProgress(effectiveOrdinal);
  return (
    streakWeekId: (holdMonday.difference(ps).inDays ~/ 7) + 1,
    weekStartDate: holdMonday,
    planned: sessions.total,
    completedCount: sessions.completed,
  );
}

/// Builds a [WorkoutDayData] for [date] directly from that date's `schedule_*`
/// row — the SAME source Home's Today card renders from
/// (`todayWorkoutProvider` → `getScheduleForDate`) — so the workout that
/// STARTS is always the workout that was DISPLAYED.
///
/// Deliberately NOT [CurrentPlanData.todayWorkout]: that getter's fallback
/// returns "first non-rest, non-done workout in the current week" when today
/// has no match, which can be a different (past) day than the card showed.
///
/// Returns null for a rest day, a row with no exercises, or no row at all —
/// callers should not offer START in those states.
WorkoutDayData? workoutDayForDate(DateTime date) {
  final row = WorkoutScheduleService.instance.getScheduleForDate(date);
  if (row == null) return null;

  final type = row['type'] as String? ?? 'rest';
  if (type != 'workout' && type != 'custom_template') return null;

  final exercises = _parseExerciseMaps(row['exercises'] as List?);
  if (exercises.isEmpty) return null;

  final week = (row['week'] as int?) ?? 1;
  final dayOfWeek = (row['day_of_week'] as int?) ?? 0;

  return WorkoutDayData(
    dayNumber: (week - 1) * 7 + dayOfWeek + 1,
    name: (row['workout_name'] as String? ?? 'Workout').toUpperCase(),
    subtitle: '${row['workout_focus'] ?? ''} · ${exercises.length} exercises',
    date: date,
    isRest: false,
    isDone: (row['status'] as String?) == 'completed',
    exercises: exercises,
    warmup: _parseExerciseMaps(row['warmup'] as List?),
    cooldown: _parseExerciseMaps(row['cooldown'] as List?),
  );
}

class CurrentPlanNotifier extends Notifier<CurrentPlanData> {
  /// Auto-generates a workout plan from local Hive profile data.
  ///
  /// Fire-and-forget async: after the plan is written to Hive,
  /// [ref.invalidateSelf()] triggers a rebuild so the UI picks up the new data.
  /// Also ensures exerciseBox is seeded before generation.
  void _autoGeneratePlan(
      Map<String, dynamic> profile, Map<String, dynamic>? progress) {
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final equipment =equipmentAccessOf(profile);
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    final experience = profile['fitness_experience'] as String? ?? 'beginner';
    final phase = (progress?['current_phase'] as int?) ?? 1;
    // U4: thread injuries so the auto-regenerated plan excludes contraindicated
    // exercises (vocab canonicalized centrally in generateV4).
    final injuries = InjuryVocab.fromProfile(profile['injuries']);

    // Fire-and-forget async: generation writes to Hive, then invalidateSelf
    // triggers build() to re-run with the newly written plan data.
    () async {
      try {
        // Guard: ensure exercise data is seeded before generation.
        final exerciseBox = HiveService.instance.exerciseBox;
        if (exerciseBox.isEmpty) {
          await SeedService.instance.seedIfNeeded();
          // If still empty after seeding, abort — no exercises to build a plan from.
          if (exerciseBox.isEmpty) return;
        }

        // Read saved preferred training days (user-selected day picker).
        final savedDays = MigratedKey.read<List>('preferred_training_days');
        final preferredDays = savedDays is List
            ? savedDays.cast<int>()
            : null;

        await WorkoutScheduleService.instance.generateAndSchedule(
          goal: goal,
          equipment: equipment,
          daysPerWeek: daysPerWeek,
          startDate: DateTime.now(),
          experienceLevel: experience,
          phase: phase,
          preferredDays: preferredDays,
          injuries: injuries, // U4
        );

        // KEY FIX: Invalidate self AFTER generation completes so build()
        // re-runs and reads the freshly written plan from Hive.
        ref.invalidateSelf();
        // Also refresh home calendar so newly scheduled days appear immediately.
        ref.invalidate(calendarWeekProvider);
      } catch (e) {
        // Log but don't crash — plan generation failure is non-fatal.
        // User will see empty state and can retry via pull-to-refresh.
      }
    }();
  }

  @override
  CurrentPlanData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress();
    final phase = (progress?['current_phase'] as int?) ?? 1;
    // Use calendar-based week (derived from plan_start_date + today) so the
    // "Week N hasn't started yet" message is always accurate.  Falls back to
    // the Hive-stored value when no plan is scheduled yet.
    final calendarWeek = WorkoutScheduleService.instance.getCurrentWeekNumber();
    final week = calendarWeek > 0
        ? calendarWeek
        : ((progress?['current_week'] as int?) ?? 1);

    final planExists = repo.hasPlan();
    if (!planExists) {
      // No plan generated yet — try to auto-generate from local profile.
      final profile = UserRepository.instance.getProfile();
      if (profile != null && profile['primary_goal'] != null) {
        // Profile exists locally — generate plan silently (async).
        // After generation completes, ref.invalidateSelf() triggers rebuild.
        _autoGeneratePlan(profile, progress);
        return CurrentPlanData(
          phase: phase,
          phaseName: 'Generating',
          currentWeek: week,
          focus: 'Generating your personalised workout plan...',
          weeks: const [],
          hasPlan: false,
          isGenerating: true,
        );
      }
      return CurrentPlanData(
        phase: phase,
        phaseName: 'No Plan',
        currentWeek: week,
        focus: 'Complete onboarding to generate your personalised plan.',
        weeks: const [],
        hasPlan: false,
      );
    }

    // Check if schedule entries are intact (plan metadata exists but
    // schedule_* entries were lost — e.g., partial Hive/IndexedDB clear).
    final week1Days = repo.getWeek(1);
    final hasWorkoutDays = week1Days.any((d) => d['type'] == 'workout');
    if (!hasWorkoutDays) {
      // Plan metadata exists but schedule is empty — regenerate.
      final profile = UserRepository.instance.getProfile();
      if (profile != null) {
        _autoGeneratePlan(profile, progress);
        // Return generating state while async regeneration runs.
        return CurrentPlanData(
          phase: phase,
          phaseName: 'Regenerating',
          currentWeek: week,
          focus: 'Rebuilding your workout schedule...',
          weeks: const [],
          hasPlan: false,
          isGenerating: true,
        );
      }
    }

    // Read plan metadata for phase name/focus.
    final planMap = repo.getCurrentPlanMap();
    // Phase name is derived from the phase NUMBER (canonical cycle) so it never
    // drifts from current_phase — the plan blob's `name` can be stale/polluted
    // (diagnose 2026-06-06; banner/letterhead used to read a hardcoded
    // "Foundation"). focus still comes from the plan.
    final phaseName = WorkoutScheduleService.instance.phaseName(phase);
    final focus =
        planMap?['focus'] as String? ?? 'Movement patterns & baseline strength';

    // Determine the actual number of weeks in the plan.
    // Phase 1 (Foundation) is always exactly 4 weeks.
    // PRO phases (2-12) may have more weeks — scan Hive for the max.
    final int totalWeeks;
    if (phase <= 1) {
      totalWeeks = 4;
    } else {
      int scanned = 4;
      for (int w = 5; w <= 12; w++) {
        if (repo.getWeek(w).isEmpty) break;
        scanned = w;
      }
      totalWeeks = scanned;
    }

    // Build weeks from Hive schedule data.
    final weeks = <List<WorkoutDayData>>[];
    for (int w = 1; w <= totalWeeks; w++) {
      final weekDays = repo.getWeek(w);
      final dayDataList = <WorkoutDayData>[];

      for (final dayMap in weekDays) {
        final type = dayMap['type'] as String? ?? 'rest';
        final isRest = type != 'workout' && type != 'custom_template';
        final status = dayMap['status'] as String? ?? 'planned';
        final exercises = _parseExerciseMaps(dayMap['exercises'] as List?);
        final warmup = _parseExerciseMaps(dayMap['warmup'] as List?);
        final cooldown = _parseExerciseMaps(dayMap['cooldown'] as List?);

        // Parse date for label and actual DateTime.
        final dateStr = dayMap['date'] as String?;
        String? dateLabel;
        DateTime? parsedDate;
        if (dateStr != null) {
          parsedDate = DateTime.tryParse(dateStr);
          if (parsedDate != null) {
            const dayNames = [
              'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
            ];
            const monthNames = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];
            dateLabel =
                '${dayNames[parsedDate.weekday - 1]}, ${monthNames[parsedDate.month - 1]} ${parsedDate.day}';
          }
        }

        dayDataList.add(WorkoutDayData(
          dayNumber:
              (w - 1) * 7 + (dayMap['day_of_week'] as int? ?? 0) + 1,
          name: (dayMap['workout_name'] as String? ?? 'Rest Day')
              .toUpperCase(),
          subtitle: isRest
              ? 'Recovery & mobility'
              : '${dayMap['workout_focus'] ?? ''} \u00b7 ${exercises.length} exercises',
          dateLabel: dateLabel,
          date: parsedDate,
          isRest: isRest,
          isDone: status == 'completed',
          exercises: exercises,
          warmup: warmup,
          cooldown: cooldown,
        ));
      }

      // If no schedule data for this week, add placeholder days.
      if (dayDataList.isEmpty) {
        for (int d = 0; d < 7; d++) {
          dayDataList.add(WorkoutDayData(
            dayNumber: (w - 1) * 7 + d + 1,
            name: 'NO PLAN',
            subtitle: 'Generate a plan first',
            isRest: true,
          ));
        }
      }

      weeks.add(dayDataList);
    }

    return CurrentPlanData(
      phase: phase,
      phaseName: phaseName,
      currentWeek: week,
      focus: focus,
      weeks: weeks,
      hasPlan: true,
    );
  }

  /// Refresh plan data (e.g. after onboarding or workout completion).
  void refresh() {
    ref.invalidateSelf();
  }

  /// Copy one week's scheduled workouts to another week in Hive workoutBox.
  ///
  /// Delegates to [WorkoutScheduleService.copyWeek] so that WorkoutScheduleService
  /// remains the sole schedule writer (T2.3 naming-drift fix 2026-05-10).
  Future<void> copyWeek(int sourceWeek, int targetWeek) async {
    if (sourceWeek == targetWeek) return;
    if (sourceWeek < 1 || sourceWeek > 4) return;
    if (targetWeek < 1 || targetWeek > 4) return;

    final startStr = MigratedKey.read<String>('plan_start_date');
    if (startStr == null) return;

    await WorkoutScheduleService.instance.copyWeek(
      sourceWeek: sourceWeek,
      targetWeek: targetWeek,
      planStartDateIso: startStr,
    );

    // Refresh the plan so the UI reflects the copied week
    ref.invalidateSelf();
  }
}

final currentPlanProvider =
    NotifierProvider<CurrentPlanNotifier, CurrentPlanData>(
        CurrentPlanNotifier.new);

// ── ⑥ Batch 7-A (W3.2): Phase Arc ────────────────────────────────

/// Read-only data for the Train-screen phase arc: the current phase's periodization
/// wave characters (baseline→overreach→peak→deload) + which week is "now". `null`
/// when the flag is OFF (ship-dark) or there is no materialized plan → the strip
/// renders nothing. Rebuilds when the plan (re)materializes (watches
/// [currentPlanProvider]); no engine coupling — pure display of stamped data.
class PhaseArcData {
  final List<String> waves; // week_character per week, ordered week 1..N
  final int currentWeek; // 1-based
  const PhaseArcData({required this.waves, required this.currentWeek});
}

final phaseArcProvider = Provider<PhaseArcData?>((ref) {
  ref.watch(currentPlanProvider); // rebuild on (re)materialize
  if (!PlanEngineFlags.phaseArcEnabled) return null;
  final waves = WorkoutScheduleService.instance.currentWaveCharacters();
  if (waves.length < 2) return null; // no / degenerate plan → render nothing
  final week = WorkoutScheduleService.instance.getCurrentWeekNumber();
  return PhaseArcData(waves: waves, currentWeek: week);
});

/// Batch 10 (W3.1 explainability): the one-line deload "why" for the current
/// phase's week-4 decision, or null. Kept SEPARATE from [phaseArcProvider] so the
/// arc data shape is untouched. Null unless the deload feature is ON (gated in the
/// read service on `triggeredDeloadEnabled`) AND a reason was stamped; the strip
/// renders it only on the deload week (week 4).
final deloadReasonProvider = Provider<String?>((ref) {
  ref.watch(currentPlanProvider); // rebuild on (re)materialize / rollover un-deload
  return WorkoutScheduleService.instance.currentDeloadReason();
});

// ── Free-tier "Hold the Line" display state ──────────────────────

/// Read-only display state for the free-tier hold mechanic (ship-dark behind
/// `enable_hold_weeks`).
///
/// This is the **single branch point** every hold-aware UI surface reads —
/// widgets never touch `PlanEngineFlags` or Hive directly. When the flag is OFF
/// this is always [HoldStatusData.empty], so every consumer renders exactly what
/// it rendered before the hold surfaces existed (the byte-identical-when-OFF
/// property the ship-dark tier rests on; pinned by the `ship-dark` group in
/// `test/contracts/hold_display_read_path_test.dart`, which reads THIS provider
/// through a ProviderContainer with hold rows present and the flag OFF).
///
/// Hold weeks deliberately do NOT flow through `CurrentPlanData.currentWeek` /
/// `getCurrentWeekNumber()`, which stay clamped to the phase's 1-4. Hold rows are
/// stamped `week = 4 + ordinal`, and `CurrentPlanData.weeks` only holds 4 entries
/// for phase 1, so `getWeek(5)` is empty — holds are addressed by ORDINAL and
/// DATE instead. See `docs/plan-reviews/free-tier-hold-findings.md`.
class HoldStatusData {
  /// True when TODAY falls inside a materialized hold week.
  final bool isHolding;

  /// The hold number covering today (H1, H2, …), or null when not holding.
  final int? todayHoldOrdinal;

  /// Every materialized hold week, ordinal-ascending — the H-chip strip.
  final List<HoldWeekInfo> holds;

  /// Completed / scheduled workout days within TODAY's hold week (0/0 when not
  /// holding) — the "4 / 5 SESSIONS" readout.
  final int sessionsCompleted;
  final int sessionsTotal;

  const HoldStatusData({
    this.isHolding = false,
    this.todayHoldOrdinal,
    this.holds = const [],
    this.sessionsCompleted = 0,
    this.sessionsTotal = 0,
  });

  /// The flag-OFF / never-held state.
  static const HoldStatusData empty = HoldStatusData();

  /// Fraction of this hold week's sessions completed, in `[0, 1]`. 0 when the
  /// week has no scheduled workout days (guards a divide-by-zero on an all-rest
  /// week).
  double get sessionProgress =>
      sessionsTotal == 0 ? 0 : sessionsCompleted / sessionsTotal;
}

final holdStatusProvider = Provider<HoldStatusData>((ref) {
  ref.watch(currentPlanProvider); // rebuild on (re)materialize / hold write

  final readService = ref.read(workoutScheduleReadServiceProvider);
  // `activeHoldWeeks()` / `activeHoldOrdinalFor()` ARE the `enable_hold_weeks`
  // gate (FOB-1): they return empty/null whenever the flag is OFF, so this
  // provider no longer restates the check itself. One gate, in the service,
  // shared with `weekIdentity()` — see WorkoutScheduleReadService.
  final holds = readService.activeHoldWeeks();
  if (holds.isEmpty) return HoldStatusData.empty;

  // `nowWall()` (not DateTime.now()) so the dev time-travel / year-sim seam that
  // holdWeek() writes against also drives what "today" means when reading back.
  final todayOrdinal = readService.activeHoldOrdinalFor(nowWall());
  if (todayOrdinal == null) {
    // Past holds exist but today isn't one of them (e.g. the user advanced, or
    // the hold week has elapsed). Show the chips; don't claim to be holding.
    return HoldStatusData(holds: holds);
  }

  final progress = readService.holdWeekSessionProgress(todayOrdinal);
  return HoldStatusData(
    isHolding: true,
    todayHoldOrdinal: todayOrdinal,
    holds: holds,
    sessionsCompleted: progress.completed,
    sessionsTotal: progress.total,
  );
});

/// The honest week identity for today, reactive to plan (re)materialization —
/// the widget-side entry point to [WeekIdentity]. Non-widget callers
/// (`ai_snapshot_builder`, repositories) use
/// `WorkoutScheduleReadService.weekIdentity()` directly; both share the ONE
/// flag gate in the service.
///
/// Watches `currentPlanProvider` for the same reason `holdStatusProvider` does:
/// taking a hold writes schedule rows, and a stale identity would print the
/// pre-hold week counter until something else happened to invalidate.
final weekIdentityProvider = Provider<WeekIdentity>((ref) {
  ref.watch(currentPlanProvider);
  return ref.read(workoutScheduleReadServiceProvider).weekIdentity();
});

// ── Selected Week ────────────────────────────────────────────────

class SelectedWeekNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    // Default to the calendar week that contains today so the chip for
    // the current date range is highlighted when the Train tab opens.
    // Falls back to the stored progress week if no plan is scheduled yet.
    final calendarWeek = WorkoutScheduleService.instance.getCurrentWeekNumber();
    if (calendarWeek > 0) return calendarWeek;
    final progress = UserRepository.instance.getProgress();
    return (progress?['current_week'] as int?) ?? 1;
  }

  void select(int week) {
    state = week;
  }
}

final selectedWeekProvider =
    NotifierProvider<SelectedWeekNotifier, int>(SelectedWeekNotifier.new);

// ── Workout Stats (PRs) ────────────────────────────────────────

/// Provider for key lift PRs — watched by StatsGrid so it refreshes
/// automatically after workout completion via ref.invalidate().
final workoutStatsProvider =
    Provider<Map<String, Map<String, double>>>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  return WorkoutRepository.instance.loadKeyLiftPRs();
});

// ── Expanded Day ────────────────────────────────────────────────

class ExpandedDayNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void toggle(int dayIndex) {
    state = state == dayIndex ? null : dayIndex;
  }

  void collapse() {
    state = null;
  }
}

final expandedDayProvider =
    NotifierProvider<ExpandedDayNotifier, int?>(ExpandedDayNotifier.new);

// ── Active Workout State ─────────────────────────────────────────

/// Input values captured for a single set.
class SetInputValues {
  final double? weight;
  final int? reps;
  final int? durationSeconds;
  final double? distanceKm;

  const SetInputValues({this.weight, this.reps, this.durationSeconds, this.distanceKm});
}

class ActiveWorkoutData {
  final WorkoutDayData? workoutDay;
  final List<ExerciseData> exercises;
  final int elapsedSeconds;
  final Map<String, bool> checkedSets; // "exerciseIndex-setIndex" -> true
  final Map<String, SetInputValues> setInputValues; // "exerciseIndex-setIndex" -> values
  final Map<String, bool> warmUpSets; // "exerciseIndex-setIndex" -> true if warm-up
  final bool isComplete;
  final bool isSaved; // true once completeWorkout() has written to Hive
  final List<String> detectedPRs; // PR descriptions detected on save
  // Superset manual grouping (session-only override, not persisted)
  final int? supersetGroupingSourceIndex; // exercise index being grouped
  final bool isSupersetGroupMode; // true when user is picking a partner
  // ⑦(b) session-time detraining resume cut (session-only, NOT persisted).
  // 1.0 = no cut; <1.0 scales the last-logged-weight prefill for a user
  // resuming after a training gap. MUST be threaded through copyWith or the
  // 1×/sec timer's copyWith(elapsedSeconds:) resets it to 1.0 within a frame.
  final double sessionDetrainingFactor;
  // ⑥ Batch 6 (W2.3) today's readiness level (Green/Yellow/Red) or null
  // (flag OFF / no check-in). Set once at startWorkout; MUST be threaded
  // through copyWith or the 1×/sec elapsed-timer reverts it (⑦b F1 footgun).
  // The Red isolation SET-DROP is baked into `exercises` at startWorkout (6-A);
  // this field drives the merged session banner. The Yellow/Red LOAD cut is 6-B.
  final ReadinessLevel? readinessLevel;

  const ActiveWorkoutData({
    this.workoutDay,
    this.exercises = const [],
    this.elapsedSeconds = 0,
    this.checkedSets = const {},
    this.setInputValues = const {},
    this.warmUpSets = const {},
    this.isComplete = false,
    this.isSaved = false,
    this.detectedPRs = const [],
    this.supersetGroupingSourceIndex,
    this.isSupersetGroupMode = false,
    this.sessionDetrainingFactor = 1.0,
    this.readinessLevel,
  });

  ActiveWorkoutData copyWith({
    WorkoutDayData? workoutDay,
    List<ExerciseData>? exercises,
    int? elapsedSeconds,
    Map<String, bool>? checkedSets,
    Map<String, SetInputValues>? setInputValues,
    Map<String, bool>? warmUpSets,
    bool? isComplete,
    bool? isSaved,
    List<String>? detectedPRs,
    int? Function()? supersetGroupingSourceIndex,
    bool? isSupersetGroupMode,
    double? sessionDetrainingFactor,
    ReadinessLevel? readinessLevel,
  }) {
    return ActiveWorkoutData(
      workoutDay: workoutDay ?? this.workoutDay,
      exercises: exercises ?? this.exercises,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      checkedSets: checkedSets ?? this.checkedSets,
      setInputValues: setInputValues ?? this.setInputValues,
      warmUpSets: warmUpSets ?? this.warmUpSets,
      isComplete: isComplete ?? this.isComplete,
      isSaved: isSaved ?? this.isSaved,
      detectedPRs: detectedPRs ?? this.detectedPRs,
      supersetGroupingSourceIndex: supersetGroupingSourceIndex != null
          ? supersetGroupingSourceIndex()
          : this.supersetGroupingSourceIndex,
      isSupersetGroupMode: isSupersetGroupMode ?? this.isSupersetGroupMode,
      sessionDetrainingFactor:
          sessionDetrainingFactor ?? this.sessionDetrainingFactor,
      readinessLevel: readinessLevel ?? this.readinessLevel,
    );
  }

  // ⑥ Batch 6 (W2.3 / 6-B) — the effective load-prefill factor for [ex],
  // combining ⑦b's session detraining cut with the readiness cut via
  // LARGER-CUT-WINS (min factor): never double-dips, never applies a SMALLER cut
  // than either mechanism alone. The readiness cut is COMPOUND-only (isolation
  // gets the Red set-drop instead, 6-A). Flag OFF / green / no check-in →
  // readinessLevel is null → returns sessionDetrainingFactor verbatim (⑦b,
  // byte-identical). Applied at the SINGLE load multiplication (exercise_card).
  // Semantics of the log→next-session baseline: a deload day logs at the cut
  // (correct — the day WAS lighter, no false PR); the next session's prefill
  // then starts from that log and RECOVERS the moment the user logs their real
  // weight — identical to ⑦b's accepted gap-cut behaviour (a conservative
  // one-session suggestion, not a permanent re-anchor).
  double effectiveLoadFactor(ExerciseData ex) {
    final rf = _readinessLoadFactor(ex);
    return rf < sessionDetrainingFactor ? rf : sessionDetrainingFactor;
  }

  double _readinessLoadFactor(ExerciseData ex) {
    final isCompound = ex.exerciseType == 'compound';
    switch (readinessLevel) {
      case ReadinessLevel.red:
        return isCompound ? 0.90 : 1.0; // −10% compound loads
      case ReadinessLevel.yellow:
        return isCompound ? 0.93 : 1.0; // −7% compound loads
      case ReadinessLevel.green:
      case null:
        return 1.0;
    }
  }

  int get totalSets =>
      exercises.fold<int>(0, (sum, e) => sum + (int.tryParse(e.sets) ?? 3));

  int get completedSets => checkedSets.keys
      .where((key) => !warmUpSets.containsKey(key))
      .length;

  double get progressPercent =>
      totalSets > 0 ? completedSets / totalSets : 0.0;

  String get timerFormatted {
    final mins = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  bool isSetChecked(int exerciseIndex, int setIndex) {
    return checkedSets.containsKey('$exerciseIndex-$setIndex');
  }

  bool isSetWarmUp(int exerciseIndex, int setIndex) {
    return warmUpSets.containsKey('$exerciseIndex-$setIndex');
  }

  bool isExerciseDone(int exerciseIndex) {
    final exercise = exercises[exerciseIndex];
    final numSets = int.tryParse(exercise.sets) ?? 3;
    for (int i = 0; i < numSets; i++) {
      if (!isSetChecked(exerciseIndex, i)) return false;
    }
    return true;
  }

  /// Get all exercise indices in the same superset group as [exerciseIndex].
  List<int> getSupersetPartners(int exerciseIndex) {
    final group = exercises[exerciseIndex].supersetGroup;
    if (group == null) return [];
    final partners = <int>[];
    for (int i = 0; i < exercises.length; i++) {
      if (i != exerciseIndex && exercises[i].supersetGroup == group) {
        partners.add(i);
      }
    }
    return partners;
  }

  /// Live total volume (kg) from completed working sets (excludes warm-ups).
  double get liveVolumeKg {
    double vol = 0;
    for (final entry in checkedSets.entries) {
      if (warmUpSets.containsKey(entry.key)) continue;
      final vals = setInputValues[entry.key];
      if (vals == null) continue;
      vol += (vals.weight ?? 0) * (vals.reps ?? 0);
    }
    return vol;
  }

  /// Color for a superset group index.
  static Color supersetColor(int groupIndex) {
    // AH.C1 — first slot uses the Wardroom accent (Campaign Gold) so
    // superset A matches the primary CTA colour. Other slots stay as
    // distinct chart hues (purple / orange / green / blue).
    final colors = [
      AppColors.accent,
      AppColors.chartPurple,
      AppColors.chartOrange,
      AppColors.chartGreen,
      AppColors.chartBlue,
    ];
    return colors[groupIndex % colors.length];
  }
}

class ActiveWorkoutNotifier extends Notifier<ActiveWorkoutData> {
  Timer? _timer;
  DateTime? _workoutStartTime;

  @override
  ActiveWorkoutData build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    ref.onDispose(() => _timer?.cancel());
    return const ActiveWorkoutData();
  }

  void startWorkout(WorkoutDayData day, {ReadinessLevel? readiness}) {
    _timer?.cancel();

    _workoutStartTime = DateTime.now();

    // ⑦(b) session-time detraining cut: a user resuming after a training gap
    // restarts lighter. Compute ONE session factor from the global days-since-
    // last-workout; ship-dark behind enable_session_detraining_cut. Applied ONLY
    // to the last-logged-weight prefill (never the ⑦a-decayed prescription).
    double sessionFactor = 1.0;
    if (PlanEngineFlags.sessionDetrainingCutEnabled) {
      sessionFactor = detrainingFactorForGap(
          WorkoutRepository.instance.getDaysSinceLastWorkout());
    }

    // ⑥ Batch 6 (W2.3) readiness. Prefer the passed level (a fresh check-in);
    // else re-apply today's STORED check-in (app-kill re-entry → never re-prompt
    // / re-derive — read the single source: the healthBox row). Flag OFF →
    // always null → no adjustment → byte-identical to today.
    ReadinessLevel? level;
    if (PlanEngineFlags.readinessEnabled) {
      level = readiness ??
          HealthReadService.instance.readinessForDate(nowWall())?.level;
    }
    var exercises = List<ExerciseData>.from(day.exercises);
    if (level == ReadinessLevel.red) {
      exercises = _applyReadinessSetDrop(exercises);
    }

    state = ActiveWorkoutData(
      workoutDay: day,
      exercises: exercises,
      elapsedSeconds: 0,
      checkedSets: {},
      warmUpSets: const {},
      sessionDetrainingFactor: sessionFactor,
      readinessLevel: level,
    );

    // Use wall-clock elapsed time so the timer survives phone lock / app pause.
    // The Timer only triggers rebuilds; actual duration = now − startTime.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_workoutStartTime != null) {
        final elapsed = DateTime.now().difference(_workoutStartTime!).inSeconds;
        state = state.copyWith(elapsedSeconds: elapsed);
      }
    });
  }

  /// ⑥ Batch 6 (W2.3) Red-day adjustment: trim ONE set from the FIRST isolation
  /// exercise that has >1 set (compounds untouched). Floored at 1 set — a muscle
  /// never drops to 0 sets/day (the "never drop a muscle to 0 sets" guard is
  /// automatic, mirroring `removeLastSet`). Returns a NEW list; never mutates.
  List<ExerciseData> _applyReadinessSetDrop(List<ExerciseData> exercises) {
    final out = List<ExerciseData>.from(exercises);
    for (var i = 0; i < out.length; i++) {
      final ex = out[i];
      if (ex.exerciseType != 'isolation') continue;
      final sets = int.tryParse(ex.sets) ?? 3;
      if (sets <= 1) continue;
      out[i] = ex.copyWith(sets: '${sets - 1}');
      break; // drop ONE set total across the session
    }
    return out;
  }

  /// Allow manual override of elapsed seconds (e.g. user edits duration on finish).
  void setElapsedSeconds(int seconds) {
    state = state.copyWith(elapsedSeconds: seconds);
  }

  /// Reopen a completed workout for review without re-saving.
  /// Sets isComplete = false so the workout screen shows again.
  /// isSaved remains true to prevent double-logging.
  void reopenWorkout() {
    _timer?.cancel();
    _timer = null;
    _workoutStartTime = null;
    state = state.copyWith(isComplete: false);
  }

  void toggleSet(int exerciseIndex, int setIndex) {
    final key = '$exerciseIndex-$setIndex';
    final newChecked = Map<String, bool>.from(state.checkedSets);
    if (newChecked.containsKey(key)) {
      newChecked.remove(key);
    } else {
      newChecked[key] = true;
    }
    state = state.copyWith(checkedSets: newChecked);
  }

  /// Record input values for a specific set (called from UI controllers).
  void recordSetValues(int exerciseIndex, int setIndex, SetInputValues values) {
    final key = '$exerciseIndex-$setIndex';
    final newValues = Map<String, SetInputValues>.from(state.setInputValues);
    newValues[key] = values;
    state = state.copyWith(setInputValues: newValues);
  }

  /// Replace the exercise at [exerciseIndex] with [newExercise].
  ///
  /// APK Test #12 / Theme A-4 — checked sets, warm-up flags, and typed
  /// input values for the OLD exercise are wiped. Otherwise: a user who
  /// checks set 1 of "Bench Press" (5 reps × 60kg), then swaps to
  /// "Push Up" (bodyweight), would see the new "Push Up" slot pre-loaded
  /// with the old weight/reps and treated as already-done — eventually
  /// logging Push Up @ 60kg × 5 reps. The clean-on-swap rule keeps the
  /// new exercise pristine.
  ///
  /// APK Test #12 / Theme D-1 — runs the new exercise's `loggingType`
  /// through [LoggingTypeResolver] so swap-from-timed → weight_reps (and
  /// vice versa) actually flips the slot UI. The picker sometimes returns
  /// an exercise without a `logging_type` field; the resolver looks it up
  /// in `exerciseBox` / `customBox` by name before falling back to
  /// `weight_reps`.
  void swapExercise(int exerciseIndex, ExerciseData newExercise) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;

    // Resolve correct logging_type for the incoming exercise.
    final hive = HiveService.instance;
    final resolvedLoggingType = LoggingTypeResolver.resolve(
          exercise: <String, dynamic>{
            'name': newExercise.name,
            'logging_type': newExercise.loggingType,
          },
          exerciseLibrary: hive.exerciseBox.toMap(),
          customLibrary: hive.customBox.toMap(),
        ) ??
        'weight_reps';
    final resolved = newExercise.loggingType == resolvedLoggingType
        ? newExercise
        : ExerciseData(
            name: newExercise.name,
            sets: newExercise.sets,
            reps: newExercise.reps,
            weight: newExercise.weight,
            rest: newExercise.rest,
            loggingType: resolvedLoggingType,
            category: newExercise.category,
            equipmentNeeded: newExercise.equipmentNeeded,
            // W3.3 (Batch 11-A): preserve the swap-in's id (or null → name fallback).
            exerciseId: newExercise.exerciseId,
          );

    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = resolved;

    // APK Test #12 / Theme A-4 — wipe per-slot ephemeral state so the
    // new exercise starts clean.
    final prefix = '$exerciseIndex-';
    final newChecked = Map<String, bool>.fromEntries(
      state.checkedSets.entries.where((e) => !e.key.startsWith(prefix)),
    );
    final newWarmUps = Map<String, bool>.fromEntries(
      state.warmUpSets.entries.where((e) => !e.key.startsWith(prefix)),
    );
    final newInputValues = Map<String, SetInputValues>.fromEntries(
      state.setInputValues.entries.where((e) => !e.key.startsWith(prefix)),
    );

    state = state.copyWith(
      exercises: newExercises,
      checkedSets: newChecked,
      warmUpSets: newWarmUps,
      setInputValues: newInputValues,
    );
  }

  void addExercise(ExerciseData exercise) {
    state = state.copyWith(
      exercises: [...state.exercises, exercise],
    );
  }

  void removeExercise(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    if (state.exercises.length <= 1) return; // Don't allow removing last exercise
    final newExercises = List<ExerciseData>.from(state.exercises)
      ..removeAt(exerciseIndex);
    // Clean up checked sets and warm-up flags for removed and shifted exercises
    final newChecked = <String, bool>{};
    final newWarmUps = <String, bool>{};
    final newInputValues = <String, SetInputValues>{};
    for (final entry in state.checkedSets.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newChecked[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newChecked['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    for (final entry in state.warmUpSets.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newWarmUps[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newWarmUps['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    for (final entry in state.setInputValues.entries) {
      final parts = entry.key.split('-');
      final exIdx = int.tryParse(parts[0]) ?? -1;
      final setIdx = parts.length > 1 ? parts[1] : '';
      if (exIdx < exerciseIndex) {
        newInputValues[entry.key] = entry.value;
      } else if (exIdx > exerciseIndex) {
        newInputValues['${exIdx - 1}-$setIdx'] = entry.value;
      }
    }
    state = state.copyWith(
      exercises: newExercises,
      checkedSets: newChecked,
      warmUpSets: newWarmUps,
      setInputValues: newInputValues,
    );
  }

  /// Add one set to the exercise at [exerciseIndex].
  void addSet(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    final ex = state.exercises[exerciseIndex];
    final current = int.tryParse(ex.sets) ?? 3;
    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = ex.copyWith(sets: '${current + 1}');
    state = state.copyWith(exercises: newExercises);
  }

  /// Remove the last set from the exercise at [exerciseIndex] (min 1 set).
  void removeLastSet(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= state.exercises.length) return;
    final ex = state.exercises[exerciseIndex];
    final current = int.tryParse(ex.sets) ?? 3;
    if (current <= 1) return; // Keep at least 1 set
    final newSetCount = current - 1;
    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[exerciseIndex] = ex.copyWith(sets: '$newSetCount');

    // Remove checked/warm-up/input data for the deleted last set
    final lastSetKey = '$exerciseIndex-$current'; // 0-based: set index = current-1
    final removedKey = '$exerciseIndex-${current - 1}';
    final newChecked = Map<String, bool>.from(state.checkedSets)
      ..remove(removedKey)
      ..remove(lastSetKey);
    final newWarmUps = Map<String, bool>.from(state.warmUpSets)
      ..remove(removedKey)
      ..remove(lastSetKey);
    final newInputValues = Map<String, SetInputValues>.from(state.setInputValues)
      ..remove(removedKey)
      ..remove(lastSetKey);

    state = state.copyWith(
      exercises: newExercises,
      checkedSets: newChecked,
      warmUpSets: newWarmUps,
      setInputValues: newInputValues,
    );
  }

  /// Toggle warm-up flag for a specific set.
  void toggleWarmUp(int exerciseIndex, int setIndex) {
    final key = '$exerciseIndex-$setIndex';
    final newWarmUps = Map<String, bool>.from(state.warmUpSets);
    if (newWarmUps.containsKey(key)) {
      newWarmUps.remove(key);
    } else {
      newWarmUps[key] = true;
    }
    state = state.copyWith(warmUpSets: newWarmUps);
  }

  /// Enter superset group mode: user long-pressed on exercise [exerciseIndex].
  void startSupersetGrouping(int exerciseIndex) {
    state = state.copyWith(
      isSupersetGroupMode: true,
      supersetGroupingSourceIndex: () => exerciseIndex,
    );
  }

  /// Cancel superset group mode.
  void cancelSupersetGrouping() {
    state = state.copyWith(
      isSupersetGroupMode: false,
      supersetGroupingSourceIndex: () => null,
    );
  }

  /// Pair [targetIndex] with the source exercise in a superset.
  /// Persists the superset_group changes to Hive workoutBox schedule entry.
  void pairSuperset(int targetIndex) {
    final sourceIndex = state.supersetGroupingSourceIndex;
    if (sourceIndex == null || sourceIndex == targetIndex) {
      cancelSupersetGrouping();
      return;
    }

    // Find the next available group index
    int maxGroup = -1;
    for (final ex in state.exercises) {
      if (ex.supersetGroup != null && ex.supersetGroup! > maxGroup) {
        maxGroup = ex.supersetGroup!;
      }
    }

    // If source already has a group, add target to same group (triset)
    final sourceGroup = state.exercises[sourceIndex].supersetGroup;
    final newGroupIndex = sourceGroup ?? (maxGroup + 1);

    final newExercises = List<ExerciseData>.from(state.exercises);
    newExercises[sourceIndex] = newExercises[sourceIndex].copyWith(
      supersetGroup: () => newGroupIndex,
    );
    newExercises[targetIndex] = newExercises[targetIndex].copyWith(
      supersetGroup: () => newGroupIndex,
    );

    state = state.copyWith(
      exercises: newExercises,
      isSupersetGroupMode: false,
      supersetGroupingSourceIndex: () => null,
    );

    // Persist superset_group changes to Hive schedule entry
    _persistSupersetGroups(newExercises);
  }

  /// Write superset_group values back to the Hive schedule entry for the
  /// current workout day so they survive app restarts.
  void _persistSupersetGroups(List<ExerciseData> exercises) {
    final workoutDate = state.workoutDay?.date;
    if (workoutDate == null) return;

    final hive = HiveService.instance;
    final dateKey = istDateStr(workoutDate);
    final scheduleKey = 'schedule_$dateKey';
    final entry = hive.workoutBox.get(scheduleKey);
    if (entry == null || entry is! Map) return;

    final entryMap = Map<String, dynamic>.from(entry);
    final storedExercises = entryMap['exercises'] as List?;
    if (storedExercises == null) return;

    // Update superset_group for each exercise in the stored schedule
    for (int i = 0; i < storedExercises.length && i < exercises.length; i++) {
      final exMap = storedExercises[i];
      if (exMap is Map) {
        final mutable = Map<String, dynamic>.from(exMap);
        mutable['superset_group'] = exercises[i].supersetGroup;
        storedExercises[i] = mutable;
      }
    }

    entryMap['exercises'] = storedExercises;
    // Audit 2026-05-20 / A3: route through WorkoutWriteService.upsertScheduled
    // (was direct workoutBox.put). Service handles IST stamping + sync fanout
    // + telemetry pair.
    unawaited(WorkoutWriteService.instance.upsertScheduled(
      date: workoutDate,
      entry: entryMap,
      source: WriteSource.activeWorkout,
    ));
  }

  Future<void> completeWorkout() async {
    _timer?.cancel();
    _timer = null;
    _workoutStartTime = null;

    // If already saved (user reopened workout to review), just mark complete
    // again without re-writing to Hive — prevents duplicate exercise logs.
    if (state.isSaved) {
      state = state.copyWith(isComplete: true);
      return;
    }

    final repo = WorkoutRepository.instance;
    final hive = HiveService.instance;
    // `nowWall()` (not DateTime.now()) so the dev/test clock seam reaches the
    // session date below. Byte-identical to DateTime.now() in release
    // (ist_date.dart:56-57). The year-sim is unaffected — it bypasses this
    // method entirely and calls WorkoutWriteService directly
    // (simulation_service.dart:444/452), driving dates via setTestClockTo.
    final now = nowWall();

    // PR detection: single-scan cache of exercise → best weight + best per-set reps
    // (O(n) once, then O(1) per exercise).
    // For reps: use best_single_set_reps when available (new logs), else
    // estimate per-set average from cumulative reps/sets (old logs).
    final bestWeightMap = <String, double>{};
    final bestRepsMap = <String, int>{};
    final bestDurationMap = <String, int>{};
    for (final raw in hive.workoutBox.values) {
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'exercise_log') continue;
      final name = (log['exercise_name'] as String? ?? '').toLowerCase();
      if (name.isEmpty) continue;
      final w = (log['weight_kg'] as num?)?.toDouble() ?? 0;
      if (w > (bestWeightMap[name] ?? 0)) bestWeightMap[name] = w;
      // Per-set best reps: prefer stored best, fallback to estimated average
      final bestSetReps = (log['best_single_set_reps'] as int?);
      // Drift-fix 2026-05-24 / T16 orphan — WorkoutWriteService.logExercise
      // emits canonical `set_number`; legacy `sets_completed` lingers on
      // older rows only. Dual-name read with canonical-first preference
      // (same pattern as line 86 + ExerciseSet.fromMap duration_sec/_seconds).
      // Unit 7 / OI-50 B-pass F1 — the divisor was a hand-rolled FIRST-NON-NULL
      // of set_number/sets_completed, blind to the per-set array length. For the
      // documented APK Test #12.1 shape (BOTH count keys present AND 0 while
      // `sets[]` is populated) `??` never fires, the divisor is 0, the `> 0`
      // gate fails, and `r` collapses to 0 — silently suppressing a genuine PR
      // from the workout-finish banner. `best_single_set_reps` is written ONLY
      // by the edit sheet, so this fallback is the COMMON path, not an edge
      // case. Now the same shared reader every other surface uses.
      final setCount = WorkoutReadService.aggregateSetCount(log);
      final totalReps = (log['reps_completed'] as int?) ?? 0;
      final r = bestSetReps ??
          (totalReps > 0 && setCount > 0 ? totalReps ~/ setCount : 0);
      if (r > (bestRepsMap[name] ?? 0)) bestRepsMap[name] = r;
      // Per-set best duration: canonical helper reads `sets[].duration_sec`
      // first, falls back to top-level `duration_seconds` for single-set
      // legacy rows only.
      //
      // Drift-fix 2026-05-24 / T6 — pre-fix this read fictional
      // `best_single_set_duration` (writer never emits) with a fallback
      // to top-level `duration_seconds` (also never emitted on exlog
      // rows). Both were dead reads silently returning 0 for every
      // modern row. Same class as the PR-cumulative bug fixed in
      // loadAllExercisePRs (closes-diagnose 2026-05-16-pr-cumulative-bug).
      final d = WorkoutReadService.bestPerSetDuration(log);
      if (d > (bestDurationMap[name] ?? 0)) bestDurationMap[name] = d;
    }

    final prDescriptions = <String>[];
    for (int exIdx = 0; exIdx < state.exercises.length; exIdx++) {
      final exercise = state.exercises[exIdx];

      // Scan checkedSets keys for this exercise to handle dynamically added sets.
      int maxSet = int.tryParse(exercise.sets) ?? 3;
      for (final key in state.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSet) maxSet = s + 1;
        }
      }

      // Weight PR (weight_reps, weighted_bodyweight)
      if (exercise.loggingType == 'weight_reps' ||
          exercise.loggingType == 'weighted_bodyweight') {
        double currentWeight = 0;
        for (int s = 0; s < maxSet; s++) {
          final key = '$exIdx-$s';
          if (state.checkedSets.containsKey(key) && !state.warmUpSets.containsKey(key)) {
            final vals = state.setInputValues[key];
            if (vals?.weight != null && vals!.weight! > currentWeight) {
              currentWeight = vals.weight!;
            }
          }
        }
        if (currentWeight <= 0) continue;

        final bestPrevious = bestWeightMap[exercise.name.toLowerCase()] ?? 0;
        if (currentWeight > bestPrevious && bestPrevious > 0) {
          prDescriptions.add(
              '${exercise.name}: ${currentWeight.toStringAsFixed(1)}kg (was ${bestPrevious.toStringAsFixed(1)}kg)');
        }
      }

      // Rep PR (bodyweight_reps — e.g. push-ups, pull-ups, dips)
      if (exercise.loggingType == 'bodyweight_reps') {
        int currentReps = 0;
        for (int s = 0; s < maxSet; s++) {
          final key = '$exIdx-$s';
          if (state.checkedSets.containsKey(key) && !state.warmUpSets.containsKey(key)) {
            final vals = state.setInputValues[key];
            if (vals?.reps != null && vals!.reps! > currentReps) {
              currentReps = vals.reps!;
            }
          }
        }
        if (currentReps <= 0) continue;

        final bestPrevious = bestRepsMap[exercise.name.toLowerCase()] ?? 0;
        if (currentReps > bestPrevious && bestPrevious > 0) {
          prDescriptions.add(
              '${exercise.name}: $currentReps reps (was $bestPrevious reps)');
        }
      }
    }

    // A session is dated by WHEN IT WAS PERFORMED — never by the plan-day being
    // performed. `state.workoutDay.date` can be a PAST date: `todayWorkout`
    // (:453-456) falls back to "first non-rest, non-done workout in the current
    // week" when today has no match, so a user completing a missed day wrote
    // exlog_<pastDate>/wlog_<pastDate> and marked the PAST schedule row
    // completed, while today's row stayed `planned` forever. That corrupted
    // every downstream reader of the log date (streak, PRs, ProgressionResolver,
    // e1RM history, adherence). `completeWorkout` has exactly ONE caller —
    // finish_dialog.dart:163, a live user finishing right now — so today is
    // always the correct date. Clamped rather than blanket-replaced so the
    // healthy path (scheduled == today) is provably unchanged.
    final workoutDate = resolveSessionDate(
      scheduledDate: state.workoutDay?.date,
      now: now,
    );

    // Compute date key once — used by streak math below.
    final dateStr = formatDateKey(workoutDate);

    // Plan A Task A-13: route per-exercise saves through WorkoutWriteService.
    // The service handles exlog_<date>_<hash> Hive write, exercise_log_index_<date>
    // append, chronological is_pr rescan, and fire-and-forget sync. The
    // pre-loop `prDescriptions` list above stays — it drives the success-state
    // UI; the service's internal rescan is what persists is_pr to Hive.
    for (int exIdx = 0; exIdx < state.exercises.length; exIdx++) {
      final exercise = state.exercises[exIdx];

      // Aggregate values from per-set input data.
      // Scan checkedSets for dynamically added sets beyond template count.
      int maxSetLog = int.tryParse(exercise.sets) ?? 3;
      for (final key in state.checkedSets.keys) {
        if (key.startsWith('$exIdx-')) {
          final s = int.tryParse(key.split('-').last) ?? 0;
          if (s + 1 > maxSetLog) maxSetLog = s + 1;
        }
      }

      // Build per-set ExerciseSet list. Skip warm-up sets — they're not
      // counted toward PRs / volume.
      final exerciseSets = <ExerciseSet>[];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (int s = 0; s < maxSetLog; s++) {
        final key = '$exIdx-$s';
        if (!state.checkedSets.containsKey(key)) continue;
        if (state.warmUpSets.containsKey(key)) continue;
        final vals = state.setInputValues[key];
        if (vals == null) continue;

        // APK Test #12.5 / Class 4 — diagnostic. WorkoutWriteService
        // strips phantom durationSec post-resolve, but we want to know
        // WHEN this happens at the source so we can find + fix the
        // controller-leak path. Logged in debug builds only — pure
        // observation, no behavior change.
        final slotType = exercise.loggingType;
        if (kDebugMode &&
            vals.durationSeconds != null &&
            vals.durationSeconds! > 0 &&
            slotType != 'timed' &&
            slotType != 'cardio') {
          debugPrint(
              '[durationCtl-leak] exercise="${exercise.name}" '
              'slotType="$slotType" setIdx=$s '
              'duration=${vals.durationSeconds} reps=${vals.reps} '
              'weight=${vals.weight}');
        }

        exerciseSets.add(ExerciseSet(
          weightKg: vals.weight ?? 0,
          reps: vals.reps ?? 0,
          durationSec: vals.durationSeconds,
          // Stagger loggedAtMs by set index so dedup never collapses
          // legitimate consecutive sets typed in the same UI tick.
          loggedAtMs: nowMs + s * 1000,
        ));
      }

      // Skip exercises with no completed working sets — service rejects
      // empty sets[] anyway.
      if (exerciseSets.isEmpty) continue;

      final result = await WorkoutWriteService.instance.logExercise(
        date: workoutDate,
        exerciseName: exercise.name,
        exerciseId: exercise.exerciseId, // W3.3 (Batch 11-A) forward-only id
        sets: exerciseSets,
        source: WriteSource.activeWorkout,
        // Don't pass ref here — we trigger our own provider invalidations
        // at the end of completeWorkout (broader than the service default).
      );
      if (!result.success) {
        // Non-fatal: log and continue. The user has still seen the success
        // state via `state.isComplete=true` below; a stuck save would be
        // recoverable via their next workout.
        // ignore: avoid_print
        debugPrint(
            '[completeWorkout] logExercise failed for ${exercise.name}: ${result.errorMessage}');
      }
    }

    // Plan A Task A-13: schedule completion + wlog_<date> via service.
    // Replaces repo.saveWorkoutLog + repo.markWorkoutCompleted.
    await WorkoutWriteService.instance.markCompleted(
      date: workoutDate,
      workoutName: state.workoutDay?.name ?? 'Workout',
      durationSec: state.elapsedSeconds,
    );

    // Update user progress + streak.
    final progress = UserRepository.instance.getProgress() ?? {};
    final totalDone = ((progress['total_workouts_done'] as int?) ?? 0) + 1;

    // ── Daily streak (schedule-aware — skips rest days) ──
    // Calculated on-the-fly by scanning schedule backwards.
    // Handles rest days, schedule changes, and template swaps correctly.
    //
    // C-14 (audit-2026-05-11) — completeWorkout is the canonical mutation
    // surface for streak state. D2 (f9d2e7): route through the SINGLE gated
    // reckon site instead of calling consume directly. For a real
    // completeWorkout (post-restore, has schedule) reckon persists missed-day
    // freeze consumption exactly as before; the gates only suppress the
    // pre-restore / empty-box edge (where consuming would be unsafe), still
    // returning an accurate read-only count to store.
    final streakDays = repo.reckonStreakDecayAndPersist();

    // ── Weekly streak (kept for badge logic — not shown in UI) ───
    //
    // Hold state comes from holdStatusProvider — the SINGLE flag-OFF guarantee
    // point (`hold_display_read_path`), so nothing here reads PlanEngineFlags or
    // Hive directly. Only `isHolding`/`todayHoldOrdinal` are taken from it:
    // its session COUNTS are stale at this point, because this method does not
    // invalidate currentPlanProvider until the end and the awaited
    // markCompleted above invalidates nothing (it was handed no ref). A cached
    // HoldStatusData therefore predates the completion just written and would
    // under-count by exactly this session — fatal at the 80% threshold.
    // `isHolding`/`todayHoldOrdinal` cannot go stale that way (a completion
    // never changes hold membership, and markCompleted preserves is_hold /
    // hold_ordinal — it merges three keys, it does not replace the row).
    // NOTE: no test can demonstrate that staleness — a fresh ProviderContainer
    // computes the provider on first read — so do NOT "simplify" this back to
    // holdStatus.sessionsCompleted on the strength of a green suite.
    final planStart = WorkoutScheduleService.instance.getPlanStartDate();
    final holdStatus = ref.read(holdStatusProvider);
    final streakWeek = resolveStreakWeekState(
      readSvc: ref.read(workoutScheduleReadServiceProvider),
      planStart: planStart,
      holdOrdinal: holdStatus.isHolding ? holdStatus.todayHoldOrdinal : null,
      workoutDate: workoutDate,
    );
    final planned = streakWeek.planned;
    final completedCount = streakWeek.completedCount;
    int streakWeeks = (progress['current_streak_weeks'] as int?) ?? 0;
    final lastStreakWeek = (progress['last_streak_week'] as int?) ?? -1;
    if (planned > 0 &&
        completedCount >= (planned * 0.8).ceil() &&
        streakWeek.streakWeekId != lastStreakWeek) {
      streakWeeks += 1;
    }

    await UserRepository.instance.updateProgress({
      'total_workouts_done': totalDone,
      'current_streak_days': streakDays,
      'last_workout_date': dateStr,
      'current_streak_weeks': streakWeeks,
      // Still an int. Widens from {1..4} to {1..N} during a hold — verified
      // safe: this field has exactly one reader (the cast above), no cloud
      // column, and no badge/rank consumer.
      'last_streak_week': streakWeek.streakWeekId,
    });

    // ── Create/update per-week streak row for Supabase streaks table ──
    final weekStartDate = streakWeek.weekStartDate;
    if (weekStartDate != null && planned > 0) {
      final weekStartStr = formatDateKey(weekStartDate);
      final streakId = 'streak_$weekStartStr';

      final healthBox = HiveService.instance.healthBox;
      final existing = (healthBox.get('streaks') as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
      final idx = existing.indexWhere((s) => s['local_id'] == streakId);

      final row = <String, dynamic>{
        'local_id': streakId,
        'week_start': weekStartStr,
        'workouts_planned': planned,
        'workouts_completed': completedCount,
        'is_streak_maintained': completedCount >= (planned * 0.8).ceil(),
      };

      if (idx >= 0) {
        existing[idx] = row;
      } else {
        existing.add(row);
      }
      await healthBox.put('streaks', existing);
    }

    state = state.copyWith(isComplete: true, isSaved: true, detectedPRs: prDescriptions);

    // Check badge unlocks after workout completion.
    BadgeService.instance.checkAll();

    // Fire-and-forget progress sync. WorkoutWriteService already fired
    // syncWorkoutData + pushSnapshot during logExercise/markCompleted —
    // we only need progress (separate row) + rank evaluation here.
    unawaited(SyncService.instance.syncProgressNow());
    // APK Test #3 / Obs 1: re-evaluate rank on every workout. Idempotent —
    // upsert with onConflict on (user_id, rank_code). Catches in-session
    // promotions (e.g. SD1 firing on workout 7) the moment they qualify.
    unawaited(RankService.instance.evaluateAndPromote());

    // Refresh all affected providers. Riverpod batches invalidations within
    // the same synchronous frame — these won't cause separate rebuilds.
    // Each is independent (no transitive dependencies between them).
    ref.invalidate(currentPlanProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(allExercisePRsProvider);
    ref.invalidate(aiInsightProvider);  // F5 — refresh home insight after complete
    // Note: weightHistoryProvider not invalidated — workout completion
    // doesn't change weight data (weight is logged separately).
  }

  void cancelWorkout() {
    _timer?.cancel();
    _timer = null;
    state = const ActiveWorkoutData();
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutData>(
        ActiveWorkoutNotifier.new);

// ── Rest Timer State ─────────────────────────────────────────────

class RestTimerData {
  final bool isActive;
  final int secondsRemaining;
  final int totalSeconds;
  final String nextExerciseName;

  const RestTimerData({
    this.isActive = false,
    this.secondsRemaining = 0,
    this.totalSeconds = 90,
    this.nextExerciseName = '',
  });

  RestTimerData copyWith({
    bool? isActive,
    int? secondsRemaining,
    int? totalSeconds,
    String? nextExerciseName,
  }) {
    return RestTimerData(
      isActive: isActive ?? this.isActive,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      nextExerciseName: nextExerciseName ?? this.nextExerciseName,
    );
  }

  double get progress =>
      totalSeconds > 0 ? secondsRemaining / totalSeconds : 0.0;

  Color get timerColor {
    // AH.C1 — token-aligned timer colours. > 30s shows the Wardroom
    // accent (Campaign Gold), the 10–30s window stays amber (warn),
    // under 10s turns red (bad).
    if (secondsRemaining > 30) return AppColors.accent;
    if (secondsRemaining > 10) return AppColors.warn;
    return AppColors.bad;
  }
}

class RestTimerNotifier extends Notifier<RestTimerData> {
  Timer? _timer;

  @override
  RestTimerData build() {
    ref.onDispose(() => _timer?.cancel());
    return const RestTimerData();
  }

  void start(int seconds, String nextExercise) {
    _timer?.cancel();
    state = RestTimerData(
      isActive: true,
      secondsRemaining: seconds,
      totalSeconds: seconds,
      nextExerciseName: nextExercise,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.secondsRemaining <= 1) {
        skip();
      } else {
        state =
            state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  void skip() {
    _timer?.cancel();
    _timer = null;
    state = const RestTimerData();
  }

  void addTime(int seconds) {
    state = state.copyWith(
      secondsRemaining: state.secondsRemaining + seconds,
      totalSeconds: state.totalSeconds + seconds,
    );
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerNotifier, RestTimerData>(RestTimerNotifier.new);

// ── Templates ────────────────────────────────────────────────────

class TemplatesNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
    final box = HiveService.instance.workoutBox;
    final templates = <Map<String, dynamic>>[];

    for (final raw in box.values) {
      if (raw is! Map) continue;
      final w = Map<String, dynamic>.from(raw);
      if (w['type'] == 'template') {
        templates.add(w);
      }
    }

    return templates;
  }

  Future<void> saveTemplate(Map<String, dynamic> template) async {
    // Audit 2026-05-20 / A3: routes through WorkoutWriteService.upsertTemplate
    // (was direct workoutBox.put). Service handles ID stamping, sync fan-out,
    // telemetry pair, and invalidation.
    final id = (template['id'] as String?) ??
        'tmpl_${DateTime.now().millisecondsSinceEpoch}';
    await WorkoutWriteService.instance.upsertTemplate(
      templateId: id,
      template: template,
      source: WriteSource.manual,
    );
    ref.invalidateSelf();
  }

  Future<void> updateTemplate(
      String templateId, Map<String, dynamic> template) async {
    // Audit 2026-05-20 / A3: routes through WorkoutWriteService.upsertTemplate.
    final hive = HiveService.instance;
    final existing = hive.workoutBox.get(templateId);
    if (existing == null) return;
    final merged = Map<String, dynamic>.from(existing as Map)
      ..addAll({
        'name': template['name'],
        'exercises': template['exercises'],
        'exercise_count': template['exercise_count'],
      });
    if (template.containsKey('assigned_days')) {
      merged['assigned_days'] = template['assigned_days'];
    }
    await WorkoutWriteService.instance.upsertTemplate(
      templateId: templateId,
      template: merged,
      source: WriteSource.manual,
    );
    ref.invalidateSelf();
  }

  /// Delete a saved template AND clean up its future schedule entries.
  ///
  /// Uses the same backup-restore pattern as the edit flow — any
  /// future `schedule_<date>` entry owned by this template has its
  /// displaced original restored before the template row itself is
  /// deleted. Completed workouts are never touched, so history
  /// survives intact even if the template is gone.
  ///
  /// Invalidates every consumer and fires pushSnapshot so the AI
  /// coach stops referencing the deleted template immediately.
  Future<void> deleteTemplate(String templateId) async {
    final hive = HiveService.instance;

    // Step 1: clean-sync wipes future entries for this template and
    // restores displaced originals where applicable.
    await WorkoutScheduleService.instance
        .cleanSyncTemplateSchedule(templateId);

    // Step 2: delete the template row itself.
    await hive.workoutBox.delete(templateId);

    // Step 3: refresh every consumer.
    ref.invalidateSelf();
    ref.invalidate(currentPlanProvider);
    ref.invalidate(calendarWeekProvider);
    ref.invalidate(todayWorkoutProvider);
    ref.invalidate(workoutStatsProvider);
    ref.invalidate(streakProvider);

    // Step 4: fire-and-forget cloud sync + snapshot push.
    // C-11 (audit-2026-05-11) — pre-fix only pushSnapshot fired here.
    // Without syncWorkoutData the cloud `workout_templates` row stays
    // on prod forever (next restore re-imports the "deleted" template).
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());
  }
}

final templatesProvider =
    NotifierProvider<TemplatesNotifier, List<Map<String, dynamic>>>(
        TemplatesNotifier.new);

// ── Graduation Stats ────────────────────────────────────────────

/// PR record for graduation display.
class PrRecord {
  final String exerciseName;
  final String value;
  const PrRecord({required this.exerciseName, required this.value});
}

class GraduationStatsData {
  final int totalWorkouts;
  final int streakWeeks;
  final int totalSets;
  final int personalRecords;
  final List<PrRecord> topPrs;

  const GraduationStatsData({
    this.totalWorkouts = 0,
    this.streakWeeks = 0,
    this.totalSets = 0,
    this.personalRecords = 0,
    this.topPrs = const [],
  });
}

final graduationStatsProvider = Provider<GraduationStatsData>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final hive = HiveService.instance;
  final progress = UserRepository.instance.getProgress() ?? {};

  final totalWorkouts = (progress['total_workouts_done'] as int?) ?? 0;
  final streakWeeks = (progress['current_streak_weeks'] as int?) ?? 0;

  // Bug 2026-05-22 / diagnose <id> — 10th writer/reader drift instance.
  // Pre-fix this provider iterated workoutBox.values, filtered by
  // log['type'] == 'exercise_log' (a field WorkoutWriteService never
  // writes), and read log['sets_completed'] (legacy field name; the
  // canonical writer field has been `set_number` since Test #6 per
  // hive_field_name_exlog SoT). Result: totalSets = 0 for every user
  // on every phase unlock since #6. The `is_pr` per-log flag is
  // similarly stale — `allExercisePRsProvider` is the canonical
  // single source for the PR set (per lib/features/home/CLAUDE.md +
  // exercise_personal_records SoT).
  //
  // Fix: aggregate sets by iterating `exlog_*` keys directly (the
  // same shape `loadAllExercisePRs` uses) reading `set_number` with
  // `sets_completed` fallback for legacy rows. Delegate PR count +
  // top PRs to allExercisePRsProvider.
  int totalSets = 0;
  final entries = hive.workoutBox.toMap();
  for (final entry in entries.entries) {
    final keyStr = entry.key.toString();
    if (!keyStr.startsWith('exlog_')) continue;
    final raw = entry.value;
    if (raw is! Map) continue;
    final log = Map<String, dynamic>.from(raw);
    final n = (log['set_number'] as int?) ??
        (log['sets_completed'] as int?) ??
        0;
    if (n > 0) totalSets += n;
  }

  final allPrs = ref.watch(allExercisePRsProvider);

  // Top PRs sorted by bestValue descending. We don't filter by
  // logging_type — graduation display shows mixed types and
  // ExercisePR.formattedValue already renders the right unit
  // (kg / reps / seconds / km).
  final topPrs = (allPrs.toList()..sort((a, b) => b.bestValue.compareTo(a.bestValue)))
      .take(3)
      .map((pr) => PrRecord(
            exerciseName: pr.exerciseName,
            value: pr.formattedValue,
          ))
      .toList();

  return GraduationStatsData(
    totalWorkouts: totalWorkouts,
    streakWeeks: streakWeeks,
    totalSets: totalSets,
    personalRecords: allPrs.length,
    topPrs: topPrs,
  );
});
