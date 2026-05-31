// lib/core/services/workout_schedule_read_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Split out of `workout_schedule_service.dart` (was ~1970 lines). This file
// owns:
//   - Plan generation orchestration (generateAndSchedule,
//     generateAndScheduleFromDate, autoGenerateNextPhaseIfNeeded, redoWeek4
//     stays in WriteService).
//   - Calendar / week queries (getScheduleForDate, getWeek,
//     getCurrentWeekNumber, getCurrentDayInPhase, isPhaseExpired,
//     getPlanStartDate, getPlanEndDate, getCurrentPlan, getCurrentPlanMap,
//     hasPlan, getCurrentCalendarWeek).
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

import 'dart:async';

import 'hive_service.dart';
import 'migrated_key.dart';
import 'seed_service.dart';
import 'singleton_lifecycle_registry.dart';
import 'sync_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
import '../utils/ist_date.dart';
import '../../features/profile/services/profile_write_service.dart';
import '../../shared/repositories/plan_generator.dart';

/// Read + plan-generation orchestrator portion of the former
/// `WorkoutScheduleService`. See file-level doc-comment for the split rationale.
class WorkoutScheduleReadService {
  WorkoutScheduleReadService._() {
    _registerLifecycle();
  }
  static final WorkoutScheduleReadService _instance =
      WorkoutScheduleReadService._();

  /// Prefer `ref.read(workoutScheduleReadServiceProvider)`.
  @Deprecated(
      'Use ref.read(workoutScheduleReadServiceProvider) — singleton path will be removed after full migration')
  static WorkoutScheduleReadService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register(
        'WorkoutScheduleReadService', _onUserChanged);
  }

  void _onUserChanged() {
    // No in-memory state — all schedule state lives in workoutBox / userBox
    // via MigratedKey.
  }

  // ── Keys (kept in sync with WorkoutScheduleWriteService / SwapService) ──

  static const String _planKey = 'current_plan';
  static const String _schedulePrefix = 'schedule_';
  static const String _planStartKey = 'plan_start_date';
  static const String _planEndKey = 'plan_end_date';

  // ── Generate & Schedule ─────────────────────────────────────────

  /// Generates a plan and maps it to calendar dates starting from [startDate].
  Future<Phase> generateAndSchedule({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime startDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );

    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);
    final workoutBox = _hive.workoutBox;
    final monday = _normalizeToMonday(startDate);
    final endDate = monday.add(const Duration(days: 27));

    await MigratedKey.write(_planStartKey, monday.toIso8601String());
    await MigratedKey.write(_planEndKey, endDate.toIso8601String());
    await workoutBox.put(_planKey, plan.toMap());
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());
    if (preferredDays != null) {
      await MigratedKey.write('preferred_training_days', preferredDays);
    }

    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final isWorkoutDay = dayPattern.contains(dayOfWeek);

        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'workout',
              'workout_day_index': workoutDayIndex,
              'workout_name': workoutDay.name,
              'workout_focus': workoutDay.focus,
              'exercises':
                  workoutDay.exercises.map((e) => e.toMap()).toList(),
              if (workoutDay.warmup.isNotEmpty)
                'warmup':
                    workoutDay.warmup.map((e) => e.toMap()).toList(),
              if (workoutDay.cooldown.isNotEmpty)
                'cooldown':
                    workoutDay.cooldown.map((e) => e.toMap()).toList(),
              if (workoutDay.finisher.isNotEmpty)
                'finisher':
                    workoutDay.finisher.map((e) => e.toMap()).toList(),
              'week_character': weekPlan.weekCharacter,
              'status': 'planned',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
          workoutDayIndex++;
        } else {
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'rest',
              'workout_name': 'Rest Day',
              'workout_focus': 'Recovery & mobility',
              'exercises': <Map<String, dynamic>>[],
              'week_character': weekPlan.weekCharacter,
              'status': 'rest',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    return plan;
  }

  /// Regenerates plan + reschedules from [fromDate] forward.
  Future<Phase> generateAndScheduleFromDate({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    required DateTime fromDate,
    String experienceLevel = 'beginner',
    int phase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    final exerciseBox = _hive.exerciseBox;
    if (exerciseBox.isEmpty) {
      await SeedService.instance.seedIfNeeded();
    }

    final plan = PlanGenerator.instance.generate(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      phase: phase,
      experienceLevel: experienceLevel,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );

    final workoutBox = _hive.workoutBox;
    final today = istMidnight(fromDate);
    final planEndStr = MigratedKey.read<String>(_planEndKey);
    final planEnd =
        planEndStr != null ? DateTime.parse(planEndStr) : today.add(const Duration(days: 28));

    for (var d = today; !d.isAfter(planEnd); d = d.add(const Duration(days: 1))) {
      final dateKey = _dateKey(d);
      final key = '$_schedulePrefix$dateKey';
      final displacedKey = 'displaced_$dateKey';
      final existing = workoutBox.get(key);
      if (existing != null) {
        final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
        final status = map['status'] as String? ?? '';
        if (status != 'completed') {
          await workoutBox.delete(key);
        }
      }
      if (workoutBox.containsKey(displacedKey)) {
        await workoutBox.delete(displacedKey);
      }
    }

    final monday = _normalizeToMonday(today);
    final endDate = monday.add(const Duration(days: 27));

    final existingStart = MigratedKey.read<String>(_planStartKey);
    final isFirstGeneration = existingStart == null;
    if (isFirstGeneration) {
      await MigratedKey.write(_planStartKey, monday.toIso8601String());
      await MigratedKey.write(_planEndKey, endDate.toIso8601String());
    }
    await workoutBox.put(_planKey, plan.toMap());
    unawaited(SyncService.instance.syncWorkoutData());
    unawaited(SyncService.instance.pushSnapshot());
    if (preferredDays != null) {
      await MigratedKey.write('preferred_training_days', preferredDays);
    }

    if (isFirstGeneration) {
      await ProfileWriteService.instance.updateField(
        'phase_started_at',
        today.toUtc().toIso8601String(),
      );
    }

    if (isFirstGeneration) {
      for (var d = monday;
          d.isBefore(today);
          d = d.add(const Duration(days: 1))) {
        final dateKey = _dateKey(d);
        final scheduleKey = '$_schedulePrefix$dateKey';
        if (workoutBox.get(scheduleKey) == null) {
          await WorkoutWriteService.instance.upsertScheduled(
            date: d,
            entry: {
              'date': dateKey,
              'week': 1,
              'day_of_week': d.weekday - 1,
              'type': 'rest',
              'workout_name': 'Joined later',
              'workout_focus': 'You joined AVYA mid-week',
              'exercises': <Map<String, dynamic>>[],
              'week_character': '',
              'status': 'rest',
              'reason': 'pre_onboarding',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    final dayPattern = preferredDays ?? _getDayPattern(daysPerWeek);

    for (int week = 0; week < 4; week++) {
      final weekPlan = week < plan.weekPlans.length
          ? plan.weekPlans[week]
          : plan.weekPlans.last;
      final weekStart = monday.add(Duration(days: week * 7));
      int workoutDayIndex = 0;

      for (int dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) {
        final date = weekStart.add(Duration(days: dayOfWeek));
        final dateKey = _dateKey(date);
        final scheduleKey = '$_schedulePrefix$dateKey';

        if (date.isBefore(today)) {
          if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
            workoutDayIndex++;
          }
          continue;
        }

        final existing = workoutBox.get(scheduleKey);
        if (existing != null) {
          final map = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
          if (map['status'] == 'completed') {
            if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
              workoutDayIndex++;
            }
            continue;
          }
        }

        final isWorkoutDay = dayPattern.contains(dayOfWeek);
        if (isWorkoutDay && workoutDayIndex < weekPlan.workoutDays.length) {
          final workoutDay = weekPlan.workoutDays[workoutDayIndex];
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'workout',
              'workout_day_index': workoutDayIndex,
              'workout_name': workoutDay.name,
              'workout_focus': workoutDay.focus,
              'exercises':
                  workoutDay.exercises.map((e) => e.toMap()).toList(),
              if (workoutDay.warmup.isNotEmpty)
                'warmup':
                    workoutDay.warmup.map((e) => e.toMap()).toList(),
              if (workoutDay.cooldown.isNotEmpty)
                'cooldown':
                    workoutDay.cooldown.map((e) => e.toMap()).toList(),
              'week_character': weekPlan.weekCharacter,
              'status': 'planned',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
          workoutDayIndex++;
        } else {
          await WorkoutWriteService.instance.upsertScheduled(
            date: date,
            entry: {
              'date': dateKey,
              'week': week + 1,
              'day_of_week': dayOfWeek,
              'type': 'rest',
              'workout_name': 'Rest Day',
              'workout_focus': 'Recovery & mobility',
              'exercises': <Map<String, dynamic>>[],
              'week_character': weekPlan.weekCharacter,
              'status': 'rest',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            },
            source: WriteSource.planGenerator,
          );
        }
      }
    }

    return plan;
  }

  /// PRO-only: if current Phase expired, generate next Phase starting today.
  Future<bool> autoGenerateNextPhaseIfNeeded({
    required String goal,
    required String equipment,
    required int daysPerWeek,
    String experienceLevel = 'intermediate',
    int currentPhase = 1,
    List<int>? preferredDays,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    int? sessionDuration,
    String? cardioPreference,
  }) async {
    if (!isPhaseExpired()) return false;
    if (currentPhase >= 12) return false;

    // Theme H fix (diagnose <id>) — was `DateTime.now()` directly. Now
    // computes max(today, currentPhaseEnd + 1) Monday-normalized so the
    // new phase doesn't overwrite the just-completed phase's final week.
    final startDate = nextPhaseStartDate();
    await generateAndSchedule(
      goal: goal,
      equipment: equipment,
      daysPerWeek: daysPerWeek,
      startDate: startDate,
      experienceLevel: experienceLevel,
      phase: currentPhase + 1,
      preferredDays: preferredDays,
      injuries: injuries,
      bodyFocus: bodyFocus,
      sessionDuration: sessionDuration,
      cardioPreference: cardioPreference,
    );
    return true;
  }

  // ── Queries ─────────────────────────────────────────────────────

  /// Get scheduled data for a specific date.
  Map<String, dynamic>? getScheduleForDate(DateTime date) {
    final key = '$_schedulePrefix${_dateKey(date)}';
    final data = _hive.workoutBox.get(key);
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data as Map);

    if (map['status'] == 'completed') {
      final completedAt = map['completed_at'] as String?;
      if (completedAt != null) {
        final completedDate = DateTime.tryParse(completedAt);
        if (completedDate != null) {
          final requestedDateStr = _dateKey(date);
          final completedDateStr = _dateKey(completedDate);
          if (completedDateStr.compareTo(requestedDateStr) < 0) {
            final safe = Map<String, dynamic>.from(map);
            safe['status'] = 'planned';
            safe['completed_at'] = null;
            return safe;
          }
        }
      }
    }

    return map;
  }

  /// Get all scheduled days for a given week number (1-4).
  List<Map<String, dynamic>> getWeek(int weekNumber) {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return [];

    final planStart = DateTime.parse(startStr);
    final weekStart = planStart.add(Duration(days: (weekNumber - 1) * 7));
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      }
    }
    return days;
  }

  /// Current week number (1-4) based on today.
  int getCurrentWeekNumber() {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return 1;

    final planStart = DateTime.parse(startStr);
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final diff = today.difference(planStart).inDays;
    return (diff ~/ 7 + 1).clamp(1, 4);
  }

  /// 1-based day number within the current Phase.
  int getCurrentDayInPhase() {
    final start = getPlanStartDate();
    if (start == null) return 0;
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final startMidnight = DateTime(start.year, start.month, start.day);
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return todayMidnight.difference(startMidnight).inDays + 1;
  }

  /// True if current Phase has run its course (today > plan_end_date).
  bool isPhaseExpired() {
    final end = getPlanEndDate();
    if (end == null) return false;
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    return today.isAfter(end);
  }

  /// Plan start date (Monday of Week 1).
  DateTime? getPlanStartDate() {
    final startStr = MigratedKey.read<String>(_planStartKey);
    if (startStr == null) return null;
    return DateTime.parse(startStr);
  }

  /// Plan end date (inclusive — last day of current Phase).
  DateTime? getPlanEndDate() {
    final endStr = MigratedKey.read<String>(_planEndKey);
    if (endStr == null) return null;
    return DateTime.tryParse(endStr);
  }

  /// Current plan deserialized (TODO — currently returns null).
  Phase? getCurrentPlan() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    return null;
  }

  /// Raw current-plan map.
  Map<String, dynamic>? getCurrentPlanMap() {
    final data = _hive.workoutBox.get(_planKey);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// True if a plan has been generated.
  bool hasPlan() {
    return _hive.workoutBox.containsKey(_planKey);
  }

  /// All dates in the current calendar week (Mon–Sun).
  List<Map<String, dynamic>> getCurrentCalendarWeek() {
    final today = nowWall(); // seam-aware (dev time-travel / year-sim)
    final monday = _normalizeToMonday(today);
    final days = <Map<String, dynamic>>[];

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final schedule = getScheduleForDate(date);
      if (schedule != null) {
        days.add(schedule);
      } else {
        days.add({
          'date': _dateKey(date),
          'day_of_week': i,
          'type': 'none',
          'workout_name': '',
          'status': 'none',
        });
      }
    }
    return days;
  }

  /// Day pattern (which weekdays are workout days).
  List<int> getDayPattern(int daysPerWeek) => _getDayPattern(daysPerWeek);

  /// Normalise a date to Monday of its week.
  DateTime normalizeToMonday(DateTime date) => _normalizeToMonday(date);

  /// Computes the start date for a NEW phase.
  ///
  /// Bug 2026-05-22 (Theme H, obs 11) — graduation_screen + autoGenerateNext
  /// previously passed `DateTime.now()` directly into [generateAndSchedule],
  /// which normalizeToMonday-ed it to THIS week's Monday. For a user mid-
  /// Phase-1-Week-4 tapping unlock on Wed, that overwrote Phase 1 W4
  /// (Mon-Sun of current week) with a fresh Phase 2 W1 — visibly corrupting
  /// the completed-history view.
  ///
  /// Correct semantic: new phase starts the MONDAY AFTER the current phase
  /// ends. Reads `plan_end_date` (already stored by every [generateAndSchedule]
  /// call at line 104) and returns `(plan_end + 1 day)` Monday-normalized.
  /// Falls back to `max(today, today)` if `plan_end_date` is missing
  /// (defensive — every code path that calls this should have generated
  /// a phase first).
  ///
  /// The `max(today, currentPhaseEnd + 1)` guard handles the edge case
  /// where a user lets Phase 1 expire (e.g. inactivity) — start the new
  /// phase from THIS Monday, not retroactively from the historical end.
  DateTime nextPhaseStartDate({DateTime? now}) {
    final today = now ?? nowWall(); // seam-aware (dev time-travel / year-sim)
    final endStr = MigratedKey.read<String>(_planEndKey);
    if (endStr != null) {
      final end = DateTime.tryParse(endStr);
      if (end != null) {
        final candidate = end.add(const Duration(days: 1));
        final useDate = candidate.isAfter(today) ? candidate : today;
        return _normalizeToMonday(useDate);
      }
    }
    return _normalizeToMonday(today);
  }

  /// Format date as YYYY-MM-DD.
  String dateKey(DateTime date) => _dateKey(date);

  // ── Helpers ─────────────────────────────────────────────────────

  List<int> _getDayPattern(int daysPerWeek) {
    switch (daysPerWeek) {
      case 3:
        return [0, 2, 4];
      case 4:
        return [0, 1, 3, 5];
      case 5:
        return [0, 1, 2, 4, 5];
      case 6:
        return [0, 1, 2, 3, 4, 5];
      default:
        return [0, 1, 3, 5];
    }
  }

  DateTime _normalizeToMonday(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  String _dateKey(DateTime date) => formatDateKey(date);
}
