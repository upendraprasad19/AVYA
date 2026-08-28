// lib/core/services/swap_service.dart
//
// Tech-debt audit 2026-05-20 / A2 (final closure batch B5 D13-D17).
//
// Owns swap-related schedule mutations + counters + travel mode:
//   - swapDays (whole-day swap within a week, with counter)
//   - swapExerciseInDay (single-exercise swap with library lookup)
//   - shortenDay (trim accessory work to a target duration)
//   - activateTravelMode / isTravelDay
//
// closes-diagnose: 2026-05-22-a2-workout-schedule-4way-split-<6char>

// ignore_for_file: deprecated_member_use_from_same_package

import 'hive_service.dart';
import 'migrated_key.dart';
import 'singleton_lifecycle_registry.dart';
import 'template_service.dart' show LoggingTypeResolver;
import 'workout_schedule_read_service.dart';
import 'workout_write_service.dart';
import 'write_result.dart';
import '../utils/date_utils.dart';
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
  static const String _swapsThisWeekKey = 'swaps_this_week';
  static const String _swapWeekStartKey = 'swap_week_start';
  static const String _travelStartKey = 'travel_start';
  static const String _travelEndKey = 'travel_end';

  // ── Day swap ────────────────────────────────────────────────────

  /// Swap two days within the same week.
  Future<String?> swapDays(DateTime dateA, DateTime dateB,
      {required bool isPro}) async {
    final mondayA = _normalizeToMonday(dateA);
    final mondayB = _normalizeToMonday(dateB);
    if (mondayA != mondayB) {
      return 'Can only swap days within the same week';
    }

    final swapsUsed = _getSwapsUsedThisWeek(mondayA);
    final maxSwaps = isPro ? 3 : 1;
    if (swapsUsed >= maxSwaps) {
      return isPro
          ? 'Maximum 3 swaps per week reached'
          : 'Free users can swap once per week. Upgrade to PRO for 3 swaps.';
    }

    final keyA = '$_schedulePrefix${formatDateKey(dateA)}';
    final keyB = '$_schedulePrefix${formatDateKey(dateB)}';
    final dataA = _hive.workoutBox.get(keyA);
    final dataB = _hive.workoutBox.get(keyB);
    if (dataA == null || dataB == null) return 'Schedule not found';

    final mapA = Map<String, dynamic>.from(dataA as Map);
    final mapB = Map<String, dynamic>.from(dataB as Map);

    final simWeek = _simulateSwap(mondayA, dateA, dateB);
    if (_hasThreeConsecutiveRest(simWeek)) {
      return 'Swap would create 3+ consecutive rest days — not allowed';
    }

    final swappedA = Map<String, dynamic>.from(mapB);
    swappedA['date'] = mapA['date'];
    swappedA['day_of_week'] = mapA['day_of_week'];
    swappedA['is_swapped'] = true;
    swappedA['original_date'] = mapB['date'];

    final swappedB = Map<String, dynamic>.from(mapA);
    swappedB['date'] = mapB['date'];
    swappedB['day_of_week'] = mapB['day_of_week'];
    swappedB['is_swapped'] = true;
    swappedB['original_date'] = mapA['date'];

    await WorkoutWriteService.instance.upsertScheduled(
      date: dateA,
      entry: swappedA,
      source: WriteSource.schedSwap,
    );
    await WorkoutWriteService.instance.upsertScheduled(
      date: dateB,
      entry: swappedB,
      source: WriteSource.schedSwap,
    );

    await _incrementSwapCount(mondayA);

    return null;
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
        !EquipmentCapability.canPerform(newLib['equipment_needed'], capability)) {
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
      if (newLib['image_start_url'] != null)
        'image_start_url': newLib['image_start_url'],
      if (newLib['image_end_url'] != null)
        'image_end_url': newLib['image_end_url'],
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

  int _getSwapsUsedThisWeek(DateTime monday) {
    final weekStart = MigratedKey.read<String>(_swapWeekStartKey);
    if (weekStart == null || weekStart != formatDateKey(monday)) {
      return 0;
    }
    return MigratedKey.readWithDefault<int>(_swapsThisWeekKey, 0);
  }

  Future<void> _incrementSwapCount(DateTime monday) async {
    final currentWeekStart = MigratedKey.read<String>(_swapWeekStartKey);
    final mondayKey = formatDateKey(monday);

    if (currentWeekStart != mondayKey) {
      await MigratedKey.write(_swapWeekStartKey, mondayKey);
      await MigratedKey.write(_swapsThisWeekKey, 1);
    } else {
      final current = MigratedKey.readWithDefault<int>(_swapsThisWeekKey, 0);
      await MigratedKey.write(_swapsThisWeekKey, current + 1);
    }
  }

  List<String> _simulateSwap(DateTime monday, DateTime dateA, DateTime dateB) {
    final readSvc = WorkoutScheduleReadService.instance;
    final types = <String>[];
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final schedule = readSvc.getScheduleForDate(date);
      types.add(schedule?['type'] as String? ?? 'rest');
    }

    final indexA = dateA.difference(monday).inDays;
    final indexB = dateB.difference(monday).inDays;
    if (indexA >= 0 && indexA < 7 && indexB >= 0 && indexB < 7) {
      final temp = types[indexA];
      types[indexA] = types[indexB];
      types[indexB] = temp;
    }
    return types;
  }

  bool _hasThreeConsecutiveRest(List<String> types) {
    int consecutive = 0;
    for (final t in types) {
      if (t == 'rest') {
        consecutive++;
        if (consecutive >= 3) return true;
      } else {
        consecutive = 0;
      }
    }
    return false;
  }

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

  DateTime _normalizeToMonday(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
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
