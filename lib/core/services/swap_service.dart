// lib/core/services/swap_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Owns swap-related schedule mutations + travel mode:
//   - swapDays: the ONE day-swap engine for Train drag / ⇅, Home and the
//     coach (spec 2026-09-26-day-swapper-design §5; rules in day_swap/)
//   - weekStates / preview: what the picker and the confirm sheet show
//   - swapExerciseInDay (single-exercise swap with library lookup)
//   - shortenDay (trim accessory work to a target duration)
//   - activateTravelMode / isTravelDay
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'day_swap/day_swap_allowance.dart';
import 'day_swap/day_swap_copy.dart';
import 'day_swap/day_swap_result.dart';
import 'day_swap/day_swap_rules.dart';
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'singleton_lifecycle_registry.dart';
import 'sync_service.dart';
import 'template_service.dart' show LoggingTypeResolver;
import 'workout_read_service.dart';
import 'workout_schedule_read_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
import '../utils/ist_date.dart';
import '../../shared/repositories/plan_engine/equipment_capability.dart';
import '../../shared/repositories/plan_engine/training_history_analyzer.dart';

/// Result returned by [SwapService.swapExerciseInDay].
class SwapExerciseResult {
  final String date;
  final String fromExerciseId;
  final String fromExerciseName;
  final String toExerciseId;
  final String toExerciseName;
  final int positionInWorkout;

  const SwapExerciseResult({
    required this.date,
    required this.fromExerciseId,
    required this.fromExerciseName,
    required this.toExerciseId,
    required this.toExerciseName,
    required this.positionInWorkout,
  });
}

/// Typed failure modes for [SwapService.swapExerciseInDay].
class SwapExerciseException implements Exception {
  final String code;
  final String message;
  const SwapExerciseException(this.code, this.message);
  @override
  String toString() => 'SwapExerciseException($code): $message';
}

/// Result returned by [SwapService.shortenDay].
class ShortenDayResult {
  final String date;
  final int originalExerciseCount;
  final int trimmedExerciseCount;
  final int estimatedOriginalMinutes;
  final int estimatedTrimmedMinutes;
  final List<String> droppedExerciseNames;

  const ShortenDayResult({
    required this.date,
    required this.originalExerciseCount,
    required this.trimmedExerciseCount,
    required this.estimatedOriginalMinutes,
    required this.estimatedTrimmedMinutes,
    required this.droppedExerciseNames,
  });
}

/// Typed failure modes for [SwapService.shortenDay].
class ShortenDayException implements Exception {
  final String code;
  final String message;
  const ShortenDayException(this.code, this.message);
  @override
  String toString() => 'ShortenDayException($code): $message';
}

/// Swap + travel-mode portion of the former WorkoutScheduleService.
class SwapService {
  SwapService._() {
    _registerLifecycle();
  }
  static final SwapService _instance = SwapService._();

  /// Prefer `ref.read(swapServiceProvider)`.
  @Deprecated(
      'Use ref.read(swapServiceProvider) — singleton path will be removed after full migration')
  static SwapService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('SwapService', _onUserChanged);
  }

  void _onUserChanged() {
    // No in-memory caches.
  }

  static const String _schedulePrefix = 'schedule_';
  static const String _travelStartKey = 'travel_start';
  static const String _travelEndKey = 'travel_end';

  // ── Day swap (spec §5) ──────────────────────────────────────────

  /// Test seam: replaces the plan push that follows a successful swap.
  @visibleForTesting
  static void Function()? debugOnPlanPushForTests;

  /// Test seam: replaces the atomic write (the rules still run inside
  /// `build`). Lets a test force a write failure or throw.
  @visibleForTesting
  static Future<WriteResult> Function({
    required DateTime dateA,
    required DateTime dateB,
    required ScheduledDaySwapWrite? Function(ScheduledDaySwapLive live) build,
  })? debugSwapWriteForTests;

  /// Test seam: replaces [DaySwapAllowance.recordSwap]. Lets a test force
  /// the post-write allowance count to throw without a real Hive failure.
  @visibleForTesting
  static Future<DayAllowance> Function(String weekStart,
      {required bool isPro})? debugRecordSwapForTests;

  Map<String, dynamic>? _row(String date) {
    final raw = _hive.workoutBox.get('$_schedulePrefix$date');
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// Sets are stamped with the IST date they are logged on, and a past date
  /// is locked as PAST before `started` is asked, so only TODAY can be
  /// "started" by a logged set. Skipping the other six dates avoids six
  /// exercise-log scans per call.
  bool _hasLoggedSets(String date, String today) {
    if (date != today) return false;
    final wlog = _hive.workoutBox
        .get(WorkoutWriteService.wlogKey(DaySwapRules.utcDate(date)));
    if (wlog != null) return true;
    return WorkoutReadService.instance.exerciseLogsForIstDate(date).isNotEmpty;
  }

  DaySwapRefused? _firstLock(
    String dateA,
    Map<String, dynamic>? rowA,
    String dateB,
    Map<String, dynamic>? rowB, {
    required String today,
    String? inProgressDate,
  }) {
    for (final (date, row) in [(dateA, rowA), (dateB, rowB)]) {
      final lock = DaySwapRules.lockOf(
        date: date,
        row: row,
        today: today,
        hasLoggedSets: _hasLoggedSets(date, today),
        inProgressDate: inProgressDate,
      );
      if (lock != null) return DaySwapRefused(reason: lock, date: date);
    }
    return null;
  }

  /// Mon–Sun states of the week containing [anyDateInWeek] (spec §6.1,
  /// §6.3). Reads only; logs nothing.
  List<DaySwapDayState> weekStates(String anyDateInWeek,
      {String? inProgressDate}) {
    final today = istTodayStr();
    return [
      for (final date in DaySwapRules.weekDates(anyDateInWeek))
        _stateOf(date, _row(date),
            today: today, inProgressDate: inProgressDate),
    ];
  }

  DaySwapDayState _stateOf(String date, Map<String, dynamic>? row,
          {required String today, String? inProgressDate}) =>
      DaySwapDayState(
        date: date,
        row: row,
        lock: DaySwapRules.lockOf(
          date: date,
          row: row,
          today: today,
          hasLoggedSets: _hasLoggedSets(date, today),
          inProgressDate: inProgressDate,
        ),
        isMoved: DaySwapRules.isMoved(row),
        title: DaySwapCopy.titleOf(row),
      );

  /// What swapping [dateA] and [dateB] would do right now. DISPLAY ONLY:
  /// [swapDays] re-checks everything against live rows at confirm time.
  DaySwapPreview preview({
    required String dateA,
    required String dateB,
    required bool isPro,
    String? inProgressDate,
  }) {
    final allowance = DaySwapAllowance.instance
        .current(DaySwapRules.mondayOf(dateA), isPro: isPro);
    final pair = DaySwapRules.pairRefusal(dateA, dateB);
    if (pair != null) return DaySwapPreview(allowance: allowance, refusal: pair);
    final rows = <String, Map<String, dynamic>?>{
      for (final d in DaySwapRules.weekDates(dateA)) d: _row(d),
    };
    final lock = _firstLock(dateA, rows[dateA], dateB, rows[dateB],
        today: istTodayStr(), inProgressDate: inProgressDate);
    return DaySwapPreview(
      allowance: allowance,
      refusal: lock?.reason ??
          (allowance.spent ? DaySwapRefusal.allowanceSpent : null),
      warning: DaySwapRules.restRunWarning(
          weekDates: rows.keys.toList(),
          rows: rows,
          dateA: dateA,
          dateB: dateB),
    );
  }

  /// The ONE day-swap entry point (spec §5.1): Train drag, Train ⇅, Home
  /// long-press and the coach all land here. Every check runs NOW, against
  /// rows re-read inside the two-date write lock; a swap is counted only
  /// after its write succeeded; the plan backup is pushed right after
  /// (spec decision 8).
  Future<DaySwapResult> swapDays({
    required String dateA,
    required String dateB,
    required DaySwapOrigin origin,
    required bool isPro,
    String? inProgressDate,
  }) async {
    final pair = DaySwapRules.pairRefusal(dateA, dateB);
    if (pair != null) {
      return _refused(DaySwapRefused(reason: pair, date: dateA), origin);
    }
    final weekStart = DaySwapRules.mondayOf(dateA);
    final today = istTodayStr();
    final nowMs = nowWall().millisecondsSinceEpoch;
    DaySwapRefused? refusal;
    RestRunWarning? warning;

    ScheduledDaySwapWrite? build(ScheduledDaySwapLive live) {
      if (DaySwapAllowance.instance.current(weekStart, isPro: isPro).spent) {
        refusal = DaySwapRefused(
            reason: DaySwapRefusal.allowanceSpent, date: dateA);
        return null;
      }
      final lock = _firstLock(dateA, live.rowA, dateB, live.rowB,
          today: today, inProgressDate: inProgressDate);
      if (lock != null) {
        refusal = lock;
        return null;
      }
      final rows = <String, Map<String, dynamic>?>{
        for (final d in DaySwapRules.weekDates(dateA))
          d: d == dateA ? live.rowA : (d == dateB ? live.rowB : _row(d)),
      };
      warning = DaySwapRules.restRunWarning(
          weekDates: rows.keys.toList(),
          rows: rows,
          dateA: dateA,
          dateB: dateB);
      return DaySwapRules.buildSwap(
        dateA: dateA,
        dateB: dateB,
        rowA: live.rowA!,
        rowB: live.rowB!,
        displacedA: live.displacedA,
        displacedB: live.displacedB,
        nowMs: nowMs,
      );
    }

    final write =
        debugSwapWriteForTests ?? WorkoutWriteService.instance.swapScheduledDays;
    final WriteResult result;
    try {
      result = await write(
        dateA: DaySwapRules.utcDate(dateA),
        dateB: DaySwapRules.utcDate(dateB),
        build: build,
      );
    } catch (e, st) {
      // Nothing was written (the write function owns its own atomicity),
      // so nothing was counted and nothing to push. Never let a swap
      // request surface an uncaught exception to the UI.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_swap_write_threw'));
      return const DaySwapFailed();
    }

    final refused = refusal;
    if (refused != null) return _refused(refused, origin);
    if (!result.success) {
      unawaited(ErrorTelemetry.logEvent('day_swap_failed',
          message: 'origin=${origin.name} error=${result.errorMessage}'));
      return const DaySwapFailed();
    }

    // The write already succeeded — the swap DID happen. If recording the
    // allowance throws, the swap is still reported as done (never claim a
    // done swap failed); the allowance simply reads back whatever is
    // currently stored, which may under-count this swap by one. That is
    // the safe direction: never double-charge, never lose the write.
    DayAllowance after;
    try {
      final recordSwap =
          debugRecordSwapForTests ?? DaySwapAllowance.instance.recordSwap;
      after = await recordSwap(weekStart, isPro: isPro);
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_swap_record_threw'));
      after = DaySwapAllowance.instance.current(weekStart, isPro: isPro);
    }
    _pushPlan();
    unawaited(ErrorTelemetry.logEvent('day_swap_done',
        message:
            'origin=${origin.name} week=$weekStart used=${after.used}/${after.limit}'));
    return DaySwapDone(
        dateA: dateA, dateB: dateB, allowanceAfter: after, warning: warning);
  }

  DaySwapRefused _refused(DaySwapRefused r, DaySwapOrigin origin) {
    unawaited(ErrorTelemetry.logEvent('day_swap_refused',
        message: 'origin=${origin.name} reason=${r.reason.code}'));
    return r;
  }

  void _pushPlan() {
    final hook = debugOnPlanPushForTests;
    if (hook != null) {
      hook();
      return;
    }
    unawaited(SyncService.instance.pushWorkoutPlanForSyncDomain());
  }

  /// Swap a single exercise within a day's scheduled workout.
  Future<SwapExerciseResult> swapExerciseInDay({
    required String date,
    required String fromExerciseId,
    required String toExerciseId,
  }) async {
    final scheduleKey = '$_schedulePrefix$date';
    final raw = _hive.workoutBox.get(scheduleKey);
    if (raw is! Map) {
      throw SwapExerciseException(
        'no_schedule',
        'No scheduled workout found for $date',
      );
    }
    final scheduleMap = Map<String, dynamic>.from(raw);

    if (scheduleMap['status'] == 'completed') {
      throw SwapExerciseException(
        'workout_completed',
        'Cannot swap exercise in a completed workout — use the Edit log path instead',
      );
    }

    final exercisesRaw = scheduleMap['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
            .map((e) => e is Map
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    int matchIndex = -1;
    for (int i = 0; i < exercises.length; i++) {
      final ex = exercises[i];
      final id = (ex['exercise_id'] as String?) ?? '';
      final name = (ex['exercise_name'] as String?) ?? '';
      if (id == fromExerciseId || name == fromExerciseId) {
        matchIndex = i;
        break;
      }
    }
    if (matchIndex == -1) {
      throw SwapExerciseException(
        'exercise_not_in_workout',
        'Exercise "$fromExerciseId" is not scheduled on $date',
      );
    }

    Map<String, dynamic>? newLib;
    // custom-picker-fix (B-pass F4): provenance is knowable HERE — whether
    // the target resolved from the library or from the user's customBox
    // scan below. The picker exemption policy
    // (EquipmentCapability.canOfferInPicker) applies identically: a
    // user-authored custom with an UNVERIFIABLE equipment requirement is a
    // valid swap target; library rows stay fail-closed.
    bool targetIsCustom = false;
    final libRaw = _hive.exerciseBox.get(toExerciseId);
    if (libRaw is Map) {
      newLib = Map<String, dynamic>.from(libRaw);
    } else {
      for (final key in _hive.customBox.keys) {
        if (key is! String || !key.startsWith('custom_exercise_')) continue;
        final candidate = _hive.customBox.get(key);
        if (candidate is! Map) continue;
        final candMap = Map<String, dynamic>.from(candidate);
        final candId = (candMap['id'] as String?) ?? '';
        final candName = (candMap['name'] as String?) ?? '';
        if (candId == toExerciseId || candName == toExerciseId) {
          newLib = candMap;
          targetIsCustom = true;
          break;
        }
      }
    }
    if (newLib == null) {
      throw SwapExerciseException(
        'exercise_not_found',
        'Exercise "$toExerciseId" not found in library or custom exercises',
      );
    }

    // ⑦ OI-89 seam 9: this service had NO equipment check, and the AI coach's
    // `swap_exercise` tool drives it (tool_dispatcher.dart:275, :588) without
    // ever opening the swap sheet — so filtering that sheet does not cover this
    // path. WorkoutScheduleService.swapExerciseInDay delegates here too, so one
    // check covers both entry points.
    //
    // Refuses rather than silently substituting: the caller ASKED for a specific
    // exercise, and quietly giving them a different one is worse than saying no.
    // The AI coach surfaces the message to the user.
    final capability = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
    if (capability != null &&
        !EquipmentCapability.canOfferInPicker(
            newLib['equipment_needed'], capability,
            isCustom: targetIsCustom)) {
      throw SwapExerciseException(
        'equipment_unavailable',
        '"${(newLib['name'] as String?) ?? toExerciseId}" needs equipment you '
            'have not told us you have. Add it under Profile > Equipment, or '
            'pick another exercise.',
      );
    }

    final original = exercises[matchIndex];
    final replacement = <String, dynamic>{
      'exercise_id': (newLib['id'] as String?) ?? toExerciseId,
      'exercise_name': (newLib['name'] as String?) ?? toExerciseId,
      'logging_type': LoggingTypeResolver.resolve(
            exercise: Map<String, dynamic>.from(newLib),
            exerciseLibrary: HiveService.instance.exerciseBox.toMap(),
            customLibrary: HiveService.instance.customBox.toMap(),
          ) ??
          (original['logging_type'] as String?) ??
          'weight_reps',
      'sets': original['sets'] ?? newLib['default_sets'] ?? 3,
      'reps': (original['reps'] ?? newLib['default_reps'] ?? '8-12')
          .toString(),
      'rest_seconds':
          original['rest_seconds'] ?? newLib['default_rest_secs'] ?? 60,
      if (original['superset_group'] != null)
        'superset_group': original['superset_group'],
      if (newLib['category'] != null) 'category': newLib['category'],
      if (newLib['exercise_type'] != null)
        'exercise_type': newLib['exercise_type'],
      if (newLib['equipment_needed'] != null)
        'equipment_needed': newLib['equipment_needed'],
      if (newLib['target_focus'] != null)
        'target_focus': newLib['target_focus'],
      if (newLib['priority_tier'] != null)
        'priority_tier': newLib['priority_tier'],
      if (newLib['coaching_cues'] != null)
        'coaching_cues': newLib['coaching_cues'],
      'swapped_via': 'ai_coach',
      // Persist the name we swapped AWAY from so LEVER 6
      // (TrainingHistoryAnalyzer.demotedExercises) can deprioritize it in
      // future generated plans. Without this the original name was discarded
      // on swap and the analyzer's `swapped_from` read was dead (drift).
      'swapped_from': (original['exercise_name'] as String?) ??
          (original['exercise_id'] as String?),
    };

    exercises[matchIndex] = replacement;
    scheduleMap['exercises'] = exercises;
    await WorkoutWriteService.instance.upsertScheduled(
      date: DateTime.parse(date),
      entry: scheduleMap,
      source: WriteSource.schedSwap,
    );

    return SwapExerciseResult(
      date: date,
      fromExerciseId: (original['exercise_id'] as String?) ??
          (original['exercise_name'] as String?) ??
          fromExerciseId,
      fromExerciseName: (original['exercise_name'] as String?) ??
          (original['exercise_id'] as String?) ??
          fromExerciseId,
      toExerciseId: (newLib['id'] as String?) ?? toExerciseId,
      toExerciseName: (newLib['name'] as String?) ?? toExerciseId,
      positionInWorkout: matchIndex,
    );
  }

  /// Trim a scheduled workout to fit a target session duration.
  Future<ShortenDayResult> shortenDay({
    required String date,
    required int targetMinutes,
  }) async {
    final scheduleKey = '$_schedulePrefix$date';
    final raw = _hive.workoutBox.get(scheduleKey);
    if (raw is! Map) {
      throw ShortenDayException(
        'no_schedule',
        'No scheduled workout found for $date',
      );
    }
    final scheduleMap = Map<String, dynamic>.from(raw);

    if (scheduleMap['status'] == 'completed') {
      throw ShortenDayException(
        'workout_completed',
        'Cannot shorten a completed workout',
      );
    }

    final exercisesRaw = scheduleMap['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
            .map((e) => e is Map
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    final originalCount = exercises.length;
    final originalEstimateSec = _estimateExerciseListSeconds(exercises);
    final originalMinutes = (originalEstimateSec / 60).ceil();

    if (originalMinutes <= targetMinutes) {
      return ShortenDayResult(
        date: date,
        originalExerciseCount: originalCount,
        trimmedExerciseCount: originalCount,
        estimatedOriginalMinutes: originalMinutes,
        estimatedTrimmedMinutes: originalMinutes,
        droppedExerciseNames: const [],
      );
    }

    final indexed = <_PrioritisedExercise>[
      for (int i = 0; i < exercises.length; i++)
        _PrioritisedExercise(
          originalIndex: i,
          priorityRank: _exercisePriorityRank(exercises[i]),
          entry: exercises[i],
        ),
    ];

    indexed.sort((a, b) {
      final cmp = a.priorityRank.compareTo(b.priorityRank);
      if (cmp != 0) return cmp;
      return a.originalIndex.compareTo(b.originalIndex);
    });

    final droppedNames = <String>[];
    while (indexed.length > 2) {
      final estimateSec = _estimateExerciseListSeconds(
          indexed.map((e) => e.entry).toList(growable: false));
      if ((estimateSec / 60).ceil() <= targetMinutes) break;
      final dropped = indexed.removeLast();
      final name = (dropped.entry['exercise_name'] as String?) ??
          (dropped.entry['exercise_id'] as String?) ??
          'Unknown';
      droppedNames.add(name);
    }

    final keptEntries = indexed.map((e) => e.entry).toList(growable: false);
    final keptEstimateSec = _estimateExerciseListSeconds(keptEntries);
    final keptMinutes = (keptEstimateSec / 60).ceil();
    if (keptMinutes > targetMinutes) {
      throw ShortenDayException(
        'target_too_low',
        'Even the highest-priority compounds need ~${keptMinutes}min — '
            'requested $targetMinutes is too short',
      );
    }

    indexed.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    final trimmedExercises =
        indexed.map((e) => e.entry).toList(growable: false);

    scheduleMap['exercises'] = trimmedExercises;
    scheduleMap['shortened_via'] = 'ai_coach';
    scheduleMap['shortened_at'] = DateTime.now().toIso8601String();
    await WorkoutWriteService.instance.upsertScheduled(
      date: DateTime.parse(date),
      entry: scheduleMap,
      source: WriteSource.schedSwap,
    );

    return ShortenDayResult(
      date: date,
      originalExerciseCount: originalCount,
      trimmedExerciseCount: trimmedExercises.length,
      estimatedOriginalMinutes: originalMinutes,
      estimatedTrimmedMinutes: keptMinutes,
      droppedExerciseNames: droppedNames,
    );
  }

  // ── Travel mode ─────────────────────────────────────────────────

  /// Activate travel mode for a date range (max 7 days). PRO only.
  Future<String?> activateTravelMode(DateTime start, DateTime end) async {
    final days = end.difference(start).inDays + 1;
    if (days > 7) return 'Travel mode is limited to 7 days';
    if (days < 1) return 'Invalid date range';

    await MigratedKey.write(_travelStartKey, formatDateKey(start));
    await MigratedKey.write(_travelEndKey, formatDateKey(end));

    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final key = '$_schedulePrefix${formatDateKey(date)}';
      final data = _hive.workoutBox.get(key);
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        map['status'] = 'travel';
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: map,
          source: WriteSource.schedSwap,
        );
      }
    }

    return null;
  }

  /// True if a date is in travel mode.
  bool isTravelDay(DateTime date) {
    final schedule = WorkoutScheduleReadService.instance.getScheduleForDate(date);
    return schedule?['status'] == 'travel';
  }

  // ── Helpers ─────────────────────────────────────────────────────

  int _estimateExerciseListSeconds(List<Map<String, dynamic>> exercises) {
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

  int _exercisePriorityRank(Map<String, dynamic> ex) {
    final tier = ex['priority_tier'];
    if (tier is num) {
      final t = tier.toInt();
      if (t >= 1 && t <= 3) return t;
    }
    final name = (ex['exercise_name'] as String? ?? '').toLowerCase();
    const compoundKeywords = [
      'squat',
      'bench',
      'deadlift',
      'row',
      'press',
      'pull-up',
      'pullup',
      'pull up',
    ];
    for (final kw in compoundKeywords) {
      if (name.contains(kw)) return 1;
    }
    return 3;
  }
}

class _PrioritisedExercise {
  final int originalIndex;
  final int priorityRank;
  final Map<String, dynamic> entry;

  const _PrioritisedExercise({
    required this.originalIndex,
    required this.priorityRank,
    required this.entry,
  });
}
