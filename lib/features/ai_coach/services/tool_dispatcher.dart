import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/hive_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/workout_schedule_service.dart';
import '../../home/providers/home_provider.dart'
    show
        calendarWeekProvider,
        streakProvider,
        todayWorkoutProvider,
        allExercisePRsProvider,
        nutritionSummaryProvider,
        recentFoodLogsProvider;
import '../../nutrition/providers/nutrition_provider.dart'
    show dailyNutritionProvider, macroTargetsProvider, weeklyNutritionProvider;
import '../../nutrition/repositories/nutrition_repository.dart';
import '../../train/providers/train_provider.dart'
    show currentPlanProvider, workoutStatsProvider;
import '../../train/repositories/workout_repository.dart';
import '../models/tool_intent.dart';
import 'hotel_workout_planner.dart';
import 'injury_swap_planner.dart';
import 'reschedule_week_planner.dart';

/// Result of executing a tool intent.
class ToolExecutionResult {
  final bool success;
  final String? errorMessage;

  /// Optional follow-up data the UI can use (e.g. SwapExerciseResult for snackbar text).
  final Object? data;

  const ToolExecutionResult.success({this.data})
      : success = true,
        errorMessage = null;

  const ToolExecutionResult.failure(this.errorMessage, {this.data})
      : success = false;
}

/// Exception when current Hive state has materially diverged from the state
/// the intent was built against (e.g., user manually edited the workout in
/// Train screen between AI suggestion and confirmation).
class ConcurrentEditException implements Exception {
  final String reason;
  const ConcurrentEditException(this.reason);
  @override
  String toString() => 'ConcurrentEditException: $reason';
}

/// Central dispatcher for AI coach tool intents.
/// Single entry point: [execute].
class ToolDispatcher {
  ToolDispatcher._();
  static final ToolDispatcher instance = ToolDispatcher._();

  /// Execute a tool intent.
  ///
  /// Steps:
  ///  1. Check expiry (1h TTL)
  ///  2. Re-read current Hive state for concurrent-edit guard
  ///  3. Route by intent.type to the right repository call
  ///  4. Fire the 6-provider invalidation batch (CLAUDE.md §15)
  ///  5. Fire fire-and-forget sync (syncWorkoutData + pushSnapshot)
  ///  6. Return result
  ///
  /// On any error, returns ToolExecutionResult.failure — never throws.
  Future<ToolExecutionResult> execute(
    Ref ref,
    ToolIntent intent,
  ) async {
    // 1. Expiry check
    if (intent.isExpired) {
      return const ToolExecutionResult.failure(
        'This suggestion is over an hour old — ask the coach again to refresh.',
      );
    }

    try {
      // 2-3. Route by type
      final ToolExecutionResult result;
      switch (intent.type) {
        case 'swap_exercise':
          result = await _executeSwapExercise(intent);
          break;
        case 'log_set':
          result = await _executeLogSet(intent);
          break;
        case 'mark_workout_complete':
          result = await _executeMarkWorkoutComplete(intent);
          break;
        case 'shorten_workout':
          result = await _executeShortenWorkout(intent);
          break;
        case 'create_custom_exercise':
          result = await _executeCreateCustomExercise(intent);
          break;
        case 'modify_workout_for_injury':
          result = await _executeModifyWorkoutForInjury(intent);
          break;
        case 'reschedule_week':
          result = await _executeRescheduleWeek(intent);
          break;
        case 'generate_hotel_workout':
          result = await _executeGenerateHotelWorkout(intent);
          break;
        case 'log_meal_by_text':
          result = await _executeLogMealByText(intent);
          break;
        case 'adjust_caloric_target':
          result = await _executeAdjustCaloricTarget(intent);
          break;
        case 'prelog':
          result = await _executePrelog(intent);
          break;
        default:
          return ToolExecutionResult.failure(
            'Unknown tool intent type: ${intent.type}',
          );
      }

      if (!result.success) return result;

      // 4. Fire family-appropriate invalidation + sync.
      //    Workout intents → workout providers + syncWorkoutData.
      //    Nutrition intents → nutrition providers + syncNutritionData.
      //    pushSnapshot fires for both so the AI coach sees the change.
      if (_isNutritionIntent(intent.type)) {
        _invalidateNutritionProviders(ref);
        unawaited(SyncService.instance.syncNutritionData());
      } else {
        _invalidateWorkoutProviders(ref);
        unawaited(SyncService.instance.syncWorkoutData());
      }
      unawaited(SyncService.instance.pushSnapshot());

      return result;
    } on ConcurrentEditException catch (e) {
      return ToolExecutionResult.failure(
        'Things changed since I suggested this — re-ask the coach to refresh: ${e.reason}',
      );
    } catch (e, stack) {
      // Defensive — shouldn't happen since each handler should catch.
      debugPrint(
          '[ToolDispatcher] unexpected error executing ${intent.type}: $e\n$stack');
      return const ToolExecutionResult.failure('Could not execute that action.');
    }
  }

  // ---------------- handlers ----------------

  Future<ToolExecutionResult> _executeSwapExercise(ToolIntent intent) async {
    final exerciseId = intent.payload['exerciseId'] as String?;
    final newExerciseId = intent.payload['newExerciseId'] as String?;
    if (exerciseId == null || newExerciseId == null) {
      return const ToolExecutionResult.failure('Invalid swap intent payload.');
    }

    // Determine target date. Default = today (the intent didn't specify a date
    // because the tool spec said "today's workout"). YYYY-MM-DD format.
    final today = _todayDateString();

    // Concurrent-edit guard: re-read schedule, confirm fromExercise still in it.
    final raw = HiveService.instance.workoutBox.get('schedule_$today');
    if (raw is! Map) {
      throw const ConcurrentEditException(
          "today's workout is no longer scheduled");
    }
    final schedule = Map<String, dynamic>.from(raw);
    final exercises = (schedule['exercises'] as List?) ?? const [];
    final stillThere = exercises.any((e) {
      if (e is! Map) return false;
      return e['exercise_id'] == exerciseId ||
          e['exercise_name'] == exerciseId;
    });
    if (!stillThere) {
      throw const ConcurrentEditException(
          "the exercise to swap is no longer in today's workout");
    }
    if (schedule['status'] == 'completed') {
      throw const ConcurrentEditException(
          "today's workout is already marked complete");
    }

    try {
      final result = await WorkoutScheduleService.instance.swapExerciseInDay(
        date: today,
        fromExerciseId: exerciseId,
        toExerciseId: newExerciseId,
      );
      return ToolExecutionResult.success(data: result);
    } on SwapExerciseException catch (e) {
      return ToolExecutionResult.failure(_swapExerciseErrorMessage(e));
    }
  }

  Future<ToolExecutionResult> _executeLogSet(ToolIntent intent) async {
    final exerciseId = intent.payload['exerciseId'] as String?;
    final weightKg = (intent.payload['weightKg'] as num?)?.toDouble();
    final reps = (intent.payload['reps'] as num?)?.toInt();
    final sets = (intent.payload['sets'] as num?)?.toInt();
    if (exerciseId == null ||
        weightKg == null ||
        reps == null ||
        sets == null) {
      return const ToolExecutionResult.failure('Invalid log_set intent payload.');
    }

    // Resolve exercise name from local library (Hive exerciseBox or customBox).
    final name = _resolveExerciseName(exerciseId) ?? exerciseId;

    final logId = await WorkoutRepository.instance.logSetWithPrRescan(
      exerciseId: exerciseId,
      exerciseName: name,
      weightKg: weightKg,
      reps: reps,
      sets: sets,
      // logging type and date default per the helper
    );
    return ToolExecutionResult.success(
        data: {'log_id': logId, 'exercise_name': name});
  }

  Future<ToolExecutionResult> _executeMarkWorkoutComplete(
      ToolIntent intent) async {
    final dateRaw = intent.payload['date'] as String?;
    final date = dateRaw ?? _todayDateString();

    // Concurrent-edit guard: a schedule entry must exist for the date.
    final raw = HiveService.instance.workoutBox.get('schedule_$date');
    if (raw is! Map) {
      throw ConcurrentEditException('no workout scheduled for $date');
    }
    if (raw['status'] == 'completed') {
      // Already done — idempotent success.
      return ToolExecutionResult.success(
          data: {'date': date, 'already_completed': true});
    }

    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return const ToolExecutionResult.failure(
          'Invalid mark_workout_complete intent payload.');
    }

    await WorkoutRepository.instance.markWorkoutCompleted(parsed);
    return ToolExecutionResult.success(data: {'date': date});
  }

  Future<ToolExecutionResult> _executeCreateCustomExercise(
      ToolIntent intent) async {
    final p = intent.payload;
    final name = p['name'] as String?;
    if (name == null || name.trim().isEmpty) {
      return const ToolExecutionResult.failure('Custom exercise needs a name.');
    }
    final category = p['category'] as String?;
    final equipment = p['equipment'] as String?;
    final loggingType = p['loggingType'] as String?;
    if (category == null || equipment == null || loggingType == null) {
      return const ToolExecutionResult.failure(
          'Invalid create_custom_exercise intent payload.');
    }

    try {
      final id = await WorkoutRepository.instance.createCustomExercise(
        name: name,
        category: category,
        equipment: equipment,
        loggingType: loggingType,
        primaryMuscles: (p['primaryMuscles'] as List?)?.cast<String>(),
        defaultSets: (p['defaultSets'] as num?)?.toInt() ?? 3,
        defaultReps: (p['defaultReps'] as num?)?.toInt(),
        defaultDurationSeconds: (p['defaultDurationSeconds'] as num?)?.toInt(),
      );
      return ToolExecutionResult.success(data: {
        'exerciseId': id,
        'name': name,
      });
    } on CreateCustomExerciseException catch (e) {
      return ToolExecutionResult.failure(
        e.code == 'duplicate_name'
            ? 'You already have an exercise called "$name".'
            : e.message,
      );
    }
  }

  Future<ToolExecutionResult> _executeShortenWorkout(ToolIntent intent) async {
    final minutes = (intent.payload['minutes'] as num?)?.toInt();
    final dateRaw = intent.payload['date'] as String?;
    if (minutes == null) {
      return const ToolExecutionResult.failure(
          'Invalid shorten_workout intent payload.');
    }
    final date = dateRaw ?? _todayDateString();

    try {
      final result = await WorkoutScheduleService.instance.shortenDay(
        date: date,
        targetMinutes: minutes,
      );
      return ToolExecutionResult.success(data: result);
    } on ShortenDayException catch (e) {
      return ToolExecutionResult.failure(_shortenWorkoutErrorMessage(e));
    }
  }

  Future<ToolExecutionResult> _executeModifyWorkoutForInjury(
      ToolIntent intent) async {
    final swaps = InjurySwapPlanner.instance.getCachedSwaps(intent.id);
    if (swaps == null) {
      return const ToolExecutionResult.failure(
        'Open the diff preview first to compute the changes.',
      );
    }

    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final swap in swaps) {
      try {
        await WorkoutScheduleService.instance.swapExerciseInDay(
          date: swap.date,
          fromExerciseId: swap.fromId,
          toExerciseId: swap.toId,
        );
        results.add({
          'date': swap.date,
          'from': swap.fromName,
          'to': swap.toName,
        });
      } on SwapExerciseException catch (e) {
        errors.add('${swap.date}: ${e.message}');
      } catch (e) {
        errors.add('${swap.date}: $e');
      }
    }

    // Update coach_memory.injuries (best-effort; never fails the op).
    try {
      await _appendInjuryToCoachMemory(
        intent.payload['bodyPart'] as String,
        intent.payload['severity'] as String,
      );
    } catch (e) {
      debugPrint('[ToolDispatcher] coach_memory injury update failed: $e');
    }

    InjurySwapPlanner.instance.clearCache(intent.id);

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {'swaps': results});
    } else if (results.isEmpty) {
      return ToolExecutionResult.failure(
        'Could not modify any workouts: ${errors.join("; ")}',
      );
    } else {
      return ToolExecutionResult.success(data: {
        'swaps': results,
        'partial_errors': errors,
      });
    }
  }

  Future<ToolExecutionResult> _executeRescheduleWeek(ToolIntent intent) async {
    final moves = RescheduleWeekPlanner.instance.getCached(intent.id);
    if (moves == null) {
      return const ToolExecutionResult.failure(
        'Open the diff preview first to compute the reshuffle plan.',
      );
    }

    final box = HiveService.instance.workoutBox;
    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    // Two-phase apply:
    //   Phase 1 — snapshot all source entries up front so a same-week
    //     A→B + B→A pair doesn't clobber each other when applied in order.
    //   Phase 2 — write each destination + delete each source from the
    //     snapshot.
    final sourceSnapshots = <String, Map<String, dynamic>>{};
    for (final move in moves) {
      if (move.action != RescheduleAction.move &&
          move.action != RescheduleAction.drop) {
        continue;
      }
      final raw = box.get('schedule_${move.fromDate}');
      if (raw is Map) {
        sourceSnapshots[move.fromDate] = Map<String, dynamic>.from(raw);
      }
    }

    for (final move in moves) {
      try {
        switch (move.action) {
          case RescheduleAction.keep:
            // No-op — entry already lives on the right date.
            break;
          case RescheduleAction.move:
            final from = sourceSnapshots[move.fromDate];
            if (from == null) {
              errors.add('${move.fromDate}: source schedule missing');
              continue;
            }
            // Defensive: refuse to clobber a completed/paused destination.
            // The planner already protects these, but a concurrent edit
            // between sheet-open and confirm could land here.
            final destExisting = box.get('schedule_${move.toDate}');
            if (destExisting is Map) {
              final destStatus = destExisting['status']?.toString();
              if (destStatus == 'completed' || destStatus == 'paused') {
                errors.add(
                    '${move.toDate}: destination not empty ($destStatus)');
                continue;
              }
            }
            // Re-stamp date + day_of_week on the moved entry.
            final updated = Map<String, dynamic>.from(from);
            updated['date'] = move.toDate;
            final destDate = DateTime.parse(move.toDate!);
            updated['day_of_week'] = destDate.weekday - 1; // 0=Mon..6=Sun
            updated['rescheduled_via'] = 'ai_coach';
            updated['rescheduled_at'] = DateTime.now().toIso8601String();
            await box.put('schedule_${move.toDate}', updated);
            // Only delete the old key if it isn't the same as the new one
            // (defensive — shouldn't happen but a no-op move would dupe).
            if (move.fromDate != move.toDate) {
              await box.delete('schedule_${move.fromDate}');
            }
            results.add({
              'from': move.fromDate,
              'to': move.toDate,
              'workout': move.workoutName,
            });
            break;
          case RescheduleAction.drop:
            await box.delete('schedule_${move.fromDate}');
            results.add({
              'from': move.fromDate,
              'dropped': move.workoutName,
            });
            break;
        }
      } catch (e) {
        errors.add('${move.fromDate}: $e');
      }
    }

    RescheduleWeekPlanner.instance.clearCache(intent.id);

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {'moves': results});
    } else if (results.isEmpty) {
      return ToolExecutionResult.failure(
        'Could not move any workouts: ${errors.join("; ")}',
      );
    } else {
      return ToolExecutionResult.success(data: {
        'moves': results,
        'partial_errors': errors,
      });
    }
  }

  Future<ToolExecutionResult> _executeGenerateHotelWorkout(
      ToolIntent intent) async {
    final rawSchedules =
        HotelWorkoutPlanner.instance.getCachedRawSchedules(intent.id);
    if (rawSchedules == null) {
      return const ToolExecutionResult.failure(
        'Open the diff preview first to compute the plan.',
      );
    }

    final box = HiveService.instance.workoutBox;
    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final schedule in rawSchedules) {
      final date = schedule['date'] as String;
      try {
        // Defensive: re-check completed status (concurrent-edit guard).
        // The planner already filters completed days out of the raw
        // schedule list, but a workout completed between sheet-open and
        // confirm could land here.
        final existing = box.get('schedule_$date');
        if (existing is Map && existing['status'] == 'completed') {
          continue;
        }
        await box.put('schedule_$date', schedule);
        results.add({
          'date': date,
          'workout': schedule['workout_name'],
        });
      } catch (e) {
        errors.add('$date: $e');
      }
    }

    HotelWorkoutPlanner.instance.clearCache(intent.id);

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {'schedules': results});
    } else if (results.isEmpty) {
      return ToolExecutionResult.failure(
        'Could not generate any workouts: ${errors.join("; ")}',
      );
    } else {
      return ToolExecutionResult.success(data: {
        'schedules': results,
        'partial_errors': errors,
      });
    }
  }

  Future<ToolExecutionResult> _executeLogMealByText(ToolIntent intent) async {
    final p = intent.payload;
    final description = p['original_description'] as String?;
    final foodName = p['food_name'] as String?;
    if (description == null || foodName == null || foodName.trim().isEmpty) {
      return const ToolExecutionResult.failure(
          'Invalid log_meal_by_text intent payload.');
    }

    // Resolve date — default to today if the intent didn't specify one.
    final dateRaw = p['date'] as String?;
    final date = (dateRaw == null || dateRaw.isEmpty)
        ? _todayDateString()
        : dateRaw;

    final mealType = _validateMealType(p['meal_type'] as String?);
    final totalCal = (p['total_calories'] as num?)?.toInt() ?? 0;
    final protein = (p['total_protein_g'] as num?)?.toInt() ?? 0;
    final carbs = (p['total_carbs_g'] as num?)?.toInt() ?? 0;
    final fat = (p['total_fat_g'] as num?)?.toInt() ?? 0;
    final servingDesc =
        (p['serving_description'] as String?)?.trim().isNotEmpty == true
            ? p['serving_description'] as String
            : '1 serving';

    try {
      final logId = await _writeFoodLogFromIntent(
        date: date,
        foodName: foodName.trim(),
        mealType: mealType,
        totalCalories: totalCal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        servingDescription: servingDesc,
      );
      return ToolExecutionResult.success(data: {
        'log_id': logId,
        'food_name': foodName,
        'total_calories': totalCal,
      });
    } catch (e, stack) {
      debugPrint('[ToolDispatcher] log_meal_by_text failed: $e\n$stack');
      return const ToolExecutionResult.failure('Could not log that meal.');
    }
  }

  /// C.4 prelog — batch-writes many meals across one or more days.
  ///
  /// The intent payload already carries fully pre-parsed meals (the tool's
  /// server-side intentBuilder ran `parseFoodText` over each meal in
  /// parallel). All the dispatcher has to do is iterate and reuse the same
  /// `_writeFoodLogFromIntent` helper the single-meal C.1 tool uses so both
  /// paths write identical shapes to the nutrition Hive box.
  ///
  /// Partial failure is tolerated: per-meal errors are collected, but as
  /// long as one meal writes we return success(partial_errors). All-empty
  /// or all-failed returns failure.
  Future<ToolExecutionResult> _executePrelog(ToolIntent intent) async {
    final parsedMeals = (intent.payload['parsed_meals'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        <Map<String, dynamic>>[];

    if (parsedMeals.isEmpty) {
      return const ToolExecutionResult.failure('No meals to pre-log.');
    }

    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (int i = 0; i < parsedMeals.length; i++) {
      final meal = parsedMeals[i];
      final date = meal['date'] as String?;
      final foodName = (meal['food_name'] as String?)?.trim();
      if (date == null || foodName == null || foodName.isEmpty) {
        errors.add('skipped meal with missing date or name');
        continue;
      }
      try {
        final logId = await _writeFoodLogFromIntent(
          date: date,
          foodName: foodName,
          mealType: _validateMealType(meal['meal_type'] as String?),
          totalCalories: (meal['total_calories'] as num?)?.toInt() ?? 0,
          protein: (meal['total_protein_g'] as num?)?.toInt() ?? 0,
          carbs: (meal['total_carbs_g'] as num?)?.toInt() ?? 0,
          fat: (meal['total_fat_g'] as num?)?.toInt() ?? 0,
          servingDescription:
              (meal['serving_description'] as String?)?.trim().isNotEmpty ==
                      true
                  ? meal['serving_description'] as String
                  : '1 serving',
          uniqueSuffix: '$i',
        );
        results.add({
          'log_id': logId,
          'date': date,
          'food_name': foodName,
          'total_calories': meal['total_calories'] ?? 0,
        });
      } catch (e, stack) {
        debugPrint(
            '[ToolDispatcher] prelog meal failed ($foodName on $date): $e\n$stack');
        errors.add('$foodName on $date: $e');
      }
    }

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {'logged': results});
    } else if (results.isEmpty) {
      return ToolExecutionResult.failure(
          'Could not log any meals: ${errors.join("; ")}');
    } else {
      return ToolExecutionResult.success(data: {
        'logged': results,
        'partial_errors': errors,
      });
    }
  }

  Future<ToolExecutionResult> _executeAdjustCaloricTarget(
      ToolIntent intent) async {
    final p = intent.payload;
    final delta = (p['delta_kcal'] as num?)?.toInt();
    final ttl = (p['ttl_days'] as num?)?.toInt();
    if (delta == null || ttl == null) {
      return const ToolExecutionResult.failure(
          'Invalid adjust_caloric_target payload.');
    }

    final startDateStr = p['start_date'] as String?;
    final startDate = (startDateStr == null || startDateStr.isEmpty)
        ? null
        : DateTime.tryParse(startDateStr);

    try {
      final override = await NutritionRepository.instance.adjustDailyTarget(
        deltaKcal: delta,
        ttlDays: ttl,
        startDate: startDate,
        reason: p['reason'] as String?,
      );
      return ToolExecutionResult.success(data: override);
    } on AdjustDailyTargetException catch (e) {
      return ToolExecutionResult.failure(_adjustTargetErrorMessage(e));
    } catch (e, stack) {
      debugPrint(
          '[ToolDispatcher] adjust_caloric_target failed: $e\n$stack');
      return const ToolExecutionResult.failure(
          'Could not adjust your calorie target.');
    }
  }

  String _adjustTargetErrorMessage(AdjustDailyTargetException e) {
    switch (e.code) {
      case 'invalid_delta':
        return 'That adjustment is too large.';
      case 'invalid_ttl':
        return 'TTL must be between 1 and 28 days.';
      case 'past_date':
        return 'Cannot adjust target for a past date.';
      default:
        return e.message;
    }
  }

  /// Write a meal-by-text log to the nutrition Hive box.
  ///
  /// Mirrors the shape produced by `FoodLogNotifier.logFood` so the existing
  /// dashboard readers (`dailyNutritionProvider`, `recentFoodLogsProvider`,
  /// `nutritionSummaryProvider`) pick it up unchanged. Differences vs. that
  /// path:
  ///   • `source: 'ai_coach_tool'` (vs `'manual'`) for telemetry.
  ///   • `food_id` is null — there's no underlying food-DB row; the AI parsed
  ///     a free-text description.
  ///   • `quantity_g` is null — the meal is logged as totals, not per-100g
  ///     scaled, so quantity_g is meaningless. Dashboard readers treat
  ///     `total_*` as the source of truth (verified via FoodLogNotifier:
  ///     totals are pre-computed before put()).
  ///   • Adds `serving_description` so the receipt-style read paths can show
  ///     "2 katori dal + 1 katori chawal" instead of a numeric quantity.
  Future<String> _writeFoodLogFromIntent({
    required String date,
    required String foodName,
    required String mealType,
    required int totalCalories,
    required int protein,
    required int carbs,
    required int fat,
    required String servingDescription,
    String? uniqueSuffix,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;
    // Optional suffix prevents same-millisecond ID collisions in batch writers
    // (e.g. C.4 prelog iterates up to 21 meals; on a fast device two iterations
    // can land in the same ms, and box.put would silently overwrite the first).
    final id = uniqueSuffix != null ? 'nlog_${ts}_$uniqueSuffix' : 'nlog_$ts';

    final logMap = <String, dynamic>{
      'id': id,
      'date': date,
      'meal_type': mealType,
      'food_id': null,
      'food_name': foodName,
      'quantity_g': null,
      'total_calories': totalCalories,
      'total_protein': protein,
      'total_carbs': carbs,
      'total_fat': fat,
      'total_fiber': 0,
      'serving_description': servingDescription,
      'created_at': now.toIso8601String(),
      'source': 'ai_coach_tool',
    };

    await box.put(id, logMap);
    return id;
  }

  String _validateMealType(String? raw) {
    const valid = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final lower = raw?.toLowerCase() ?? '';
    return valid.contains(lower) ? lower : 'snacks';
  }

  bool _isNutritionIntent(String type) {
    // Keep this list in sync with the nutrition family handlers above.
    // C.1 log_meal_by_text, C.2 adjust_caloric_target, C.4 prelog.
    // (suggestMeal is read-only — no dispatcher entry, so not listed here.)
    return type == 'log_meal_by_text' ||
        type == 'adjust_caloric_target' ||
        type == 'prelog';
  }

  Future<void> _appendInjuryToCoachMemory(
      String bodyPart, String severity) async {
    final box = HiveService.instance.coachBox;
    final raw = box.get('coach_memory');
    final mem = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};

    final existing = mem['injuries'];
    final injuries = existing is List
        ? existing
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    injuries.add({
      'part': bodyPart,
      'severity': severity,
      'since': DateTime.now().toIso8601String().split('T').first,
    });

    mem['injuries'] = injuries;
    await box.put('coach_memory', mem);
    // pushSnapshot fires after this in the dispatcher's outer flow; the
    // snapshot path can opt to forward the injury delta to server-side
    // coach_memory in a future change.
  }

  // ---------------- helpers ----------------

  void _invalidateNutritionProviders(Ref ref) {
    // Mirrors FoodLogNotifier.logFood's invalidation set so nutrition writes
    // from the AI coach refresh the same screens (Home nutrition snapshot +
    // Nutrition tab daily/weekly grids) as a manual food log.
    try {
      ref.invalidate(dailyNutritionProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(weeklyNutritionProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(nutritionSummaryProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(recentFoodLogsProvider);
    } catch (_) {/* ignore */}
    // adjust_caloric_target writes a target_override_<date> key; the
    // macro-target readers (profile MY TARGETS card, diet plan screen) need
    // to re-read the override-aware target.
    try {
      ref.invalidate(macroTargetsProvider);
    } catch (_) {/* ignore */}
  }

  void _invalidateWorkoutProviders(Ref ref) {
    // CLAUDE.md §15 mandatory batch.
    // Each invalidation is independently try/caught — a missing provider
    // shouldn't prevent the rest from refreshing. Unrolled (vs. iterating
    // a list) because providers are a sealed family and don't share a
    // common upper bound that ref.invalidate accepts.
    try {
      ref.invalidate(currentPlanProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(workoutStatsProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(calendarWeekProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(streakProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(todayWorkoutProvider);
    } catch (_) {/* ignore */}
    try {
      ref.invalidate(allExercisePRsProvider);
    } catch (_) {/* ignore */}
  }

  String _todayDateString() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  String? _resolveExerciseName(String exerciseId) {
    final libBox = HiveService.instance.exerciseBox;
    final customBox = HiveService.instance.customBox;

    final lib = libBox.get(exerciseId);
    if (lib is Map) {
      final n = lib['name'];
      if (n is String && n.isNotEmpty) return n;
    }

    final custom = customBox.get(exerciseId);
    if (custom is Map) {
      final n = custom['name'];
      if (n is String && n.isNotEmpty) return n;
    }

    // Fallback: scan customBox for exercises whose nested 'id' matches
    // (custom items are stored under different keys like
    // 'custom_exercise_<ts>').
    for (final key in customBox.keys) {
      final v = customBox.get(key);
      if (v is Map && v['id'] == exerciseId) {
        final n = v['name'];
        if (n is String && n.isNotEmpty) return n;
      }
    }
    return null;
  }

  String _swapExerciseErrorMessage(SwapExerciseException e) {
    switch (e.code) {
      case 'no_schedule':
        return 'No workout scheduled for today.';
      case 'exercise_not_in_workout':
        return "That exercise isn't in today's workout.";
      case 'exercise_not_found':
        return "I couldn't find the replacement exercise in your library.";
      case 'workout_completed':
        return "Today's workout is already done — edit it from the Train screen instead.";
      default:
        return e.message;
    }
  }

  String _shortenWorkoutErrorMessage(ShortenDayException e) {
    switch (e.code) {
      case 'no_schedule':
        return 'No workout scheduled for that day.';
      case 'workout_completed':
        return "Workout already done — can't shorten.";
      case 'target_too_low':
        return 'Target time is too short — even basic compound work needs more time.';
      default:
        return e.message;
    }
  }
}
