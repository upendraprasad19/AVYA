import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/fitness_goals.dart';
import '../../../core/services/error_telemetry.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/utils/ist_date.dart';
import '../../../core/services/nutrition_write_service.dart';
import '../../../core/services/nutrition_write_source.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/usage_counter_service.dart';
import '../../../core/services/workout_schedule_service.dart';
import '../../../core/services/workout_write_service.dart';
import '../../../core/services/write_result.dart';
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
import '../../profile/services/profile_write_service.dart';
import '../../profile/providers/profile_provider.dart'
    show userProfileProvider, userStatsProvider;
import '../../train/providers/train_provider.dart'
    show currentPlanProvider, templatesProvider, workoutStatsProvider;
import '../../train/repositories/workout_repository.dart';
import '../models/tool_intent.dart';
import 'hotel_workout_planner.dart';
import 'injury_swap_planner.dart';
import 'pause_plan_planner.dart';
import 'regenerate_plan_planner.dart';
import 'reschedule_week_planner.dart';
import 'schedule_template_planner.dart';

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

    // 1a. Idempotency guard (B-4): refuse double-dispatch.
    // The Hive marker is written AFTER successful execution below; if it's
    // already there, this intent has been applied. Returning success keeps
    // the UI calm — no error toast, no second handler run.
    final markerKey = 'intent_${intent.id}_dispatched_at';
    try {
      final existing = HiveService.instance.coachBox.get(markerKey);
      if (existing != null) {
        debugPrint(
            '[tool_dispatcher] intent ${intent.id} already dispatched — skip');
        return const ToolExecutionResult.success();
      }
    } catch (_) {/* never block on telemetry */}

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
        case 'regenerate_plan_block':
          result = await _executeRegeneratePlanBlock(intent);
          break;
        case 'pause_plan':
          result = await _executePausePlan(intent);
          break;
        case 'switch_goal':
          result = await _executeSwitchGoal(intent);
          break;
        case 'create_custom_template':
          result = await _executeCreateCustomTemplate(intent);
          break;
        case 'schedule_template':
          result = await _executeScheduleTemplate(intent);
          break;
        case 'log_meal_by_text':
          result = await _executeLogMealByText(intent);
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
      // switch_goal also mutates the profile (primary_goal) — refresh the
      // profile readers so MY TARGETS card, header, and any goal-derived
      // UI re-read the new value.
      if (intent.type == 'switch_goal') {
        _invalidateProfileProviders(ref);
      }
      // create_custom_template adds rows to the user's template library —
      // refresh the Train screen's templates list so the new entries
      // appear immediately without a tab switch.
      if (intent.type == 'create_custom_template') {
        try {
          ref.invalidate(templatesProvider);
        } catch (e, st) {
          debugPrint('[tool_dispatcher] invalidate templatesProvider failed: $e\n$st');
        }
      }
      unawaited(SyncService.instance.pushSnapshot());

      // C-4 / C-6: stamp a Hive marker so the chat thread can filter out
      // already-dispatched intents even if the in-memory provider state is
      // lost (hot restart, low-memory background kill). The marker is a
      // belt-and-braces complement to ToolIntent.status — primary state
      // remains in PendingToolIntentsNotifier; this just survives process
      // death.
      try {
        await HiveService.instance.coachBox.put(
          'intent_${intent.id}_dispatched_at',
          DateTime.now().toIso8601String(),
        );
      } catch (_) {/* never block on telemetry */}

      return result;
    } on ConcurrentEditException catch (e) {
      return ToolExecutionResult.failure(
        'Things changed since I suggested this — re-ask the coach to refresh: ${e.reason}',
      );
    } catch (e, stack) {
      // Defensive — shouldn't happen since each handler should catch.
      debugPrint(
          '[ToolDispatcher] unexpected error executing ${intent.type}: $e\n$stack');
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_${intent.type}_unexpected_failure',
          message: clipped));
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

    // Plan A A-11: route through WorkoutWriteService.logExercise — ONE call
    // with sets[length=N] yields ONE deterministic exlog row, replacing the
    // old per-set logSetWithPrRescan loop that produced N duplicate rows
    // (observation #16 root cause).
    final dateRaw = intent.payload['date'] as String?;
    final date = (dateRaw == null || dateRaw.isEmpty)
        ? DateTime.now()
        : (DateTime.tryParse(dateRaw) ?? DateTime.now());
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final exerciseSets = List<ExerciseSet>.generate(
      sets,
      (i) => ExerciseSet(
        weightKg: weightKg,
        reps: reps,
        loggedAtMs: nowMs + i, // tiny offset prevents 60s-window self-dedup
      ),
    );

    final result = await WorkoutWriteService.instance.logExercise(
      date: date,
      exerciseName: name,
      sets: exerciseSets,
      source: WriteSource.aiCoach,
      // ref: null — dispatcher's outer flow handles invalidation + sync.
    );
    if (!result.success) {
      return ToolExecutionResult.failure(
          result.errorMessage ?? 'Could not log set.');
    }

    // Derived completion (replaces the removed `markWorkoutComplete` tool —
    // completion is no longer AI-assertable; it is DERIVED from raw logging).
    // If this date has a scheduled workout that isn't already complete, mark it
    // done via the canonical writer (same one the UI finish button uses).
    final schedDateStr =
        (dateRaw == null || dateRaw.isEmpty) ? _todayDateString() : dateRaw;
    await _maybeCompleteScheduledDay(date, schedDateStr);

    return ToolExecutionResult.success(
        data: {'log_id': result.logKey, 'exercise_name': name});
  }

  /// Derived workout completion — see `_executeLogSet`. Idempotent: no-op when
  /// the date has no schedule or is already `completed`. Reuses the canonical
  /// `WorkoutWriteService.markCompleted` so streak / deployment / rank advance
  /// exactly as the UI finish button does. Never throws into the dispatch flow.
  Future<void> _maybeCompleteScheduledDay(DateTime date, String dateStr) async {
    try {
      final raw = HiveService.instance.workoutBox.get('schedule_$dateStr');
      if (raw is! Map || raw['status'] == 'completed') return;
      // Don't auto-complete a REST day — there's no planned workout to finish,
      // so an ad-hoc coach-logged set shouldn't flip the rest day into a
      // "completed workout" (which would feed streak / deployment wrongly).
      if (raw['type'] == 'rest') return;
      final workoutName = (raw['workout_name'] as String?) ?? 'Workout';
      await WorkoutWriteService.instance.markCompleted(
        date: date,
        workoutName: workoutName,
        durationSec: 0,
      );
    } catch (e) {
      // Swallow — derived completion is best-effort; the log itself succeeded.
      debugPrint('[ToolDispatcher] derived completion failed: $e');
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_derived_completion_failed',
          message: e.toString()));
    }
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
      final aggregated = errors.join('; ');
      final clipped = aggregated.length > 500
          ? aggregated.substring(0, 500)
          : aggregated;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_modify_workout_for_injury_failed',
          message: clipped));
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
            // Plan A A-12: route through WorkoutWriteService for source +
            // updated_at_ms stamping. The service uses scheduleKey(date)
            // which matches the legacy 'schedule_<YYYY-MM-DD>' format.
            await WorkoutWriteService.instance.upsertScheduled(
              date: destDate,
              entry: updated,
              source: WriteSource.aiCoach,
            );
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
      final aggregated = errors.join('; ');
      final clipped = aggregated.length > 500
          ? aggregated.substring(0, 500)
          : aggregated;
      unawaited(ErrorTelemetry.logEvent('tool_dispatch_reschedule_week_failed',
          message: clipped));
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
        // Plan A A-12: route through WorkoutWriteService.
        final parsed = DateTime.tryParse(date);
        if (parsed == null) {
          errors.add('$date: invalid date');
          continue;
        }
        await WorkoutWriteService.instance.upsertScheduled(
          date: parsed,
          entry: Map<String, dynamic>.from(schedule),
          source: WriteSource.aiCoach,
        );
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
      final aggregated = errors.join('; ');
      final clipped = aggregated.length > 500
          ? aggregated.substring(0, 500)
          : aggregated;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_generate_hotel_workout_failed',
          message: clipped));
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

  /// D.3 regeneratePlanBlock — writes a fresh N-week schedule block.
  ///
  /// The planner has already computed the raw schedule list (one entry per
  /// non-completed day in the window, including rest days). Dispatcher
  /// writes them in order, preserving completed days defensively as a
  /// concurrent-edit guard (planner already filters them out, but a
  /// completion that lands between sheet-open and confirm would get caught
  /// here).
  Future<ToolExecutionResult> _executeRegeneratePlanBlock(
      ToolIntent intent) async {
    final rawSchedules =
        RegeneratePlanPlanner.instance.getCachedRawSchedules(intent.id);
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
        final existing = box.get('schedule_$date');
        if (existing is Map && existing['status'] == 'completed') {
          // Concurrent-edit safety net.
          continue;
        }
        // Plan A A-12: route through WorkoutWriteService.
        final parsed = DateTime.tryParse(date);
        if (parsed == null) {
          errors.add('$date: invalid date');
          continue;
        }
        await WorkoutWriteService.instance.upsertScheduled(
          date: parsed,
          entry: Map<String, dynamic>.from(schedule),
          source: WriteSource.aiCoach,
        );
        results.add({
          'date': date,
          'workout': schedule['workout_name'],
          'type': schedule['type'],
        });
      } catch (e) {
        errors.add('$date: $e');
      }
    }

    RegeneratePlanPlanner.instance.clearCache(intent.id);

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {
        'schedules': results,
        'count': results.length,
      });
    } else if (results.isEmpty) {
      final aggregated = errors.join('; ');
      final clipped = aggregated.length > 500
          ? aggregated.substring(0, 500)
          : aggregated;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_regenerate_plan_block_failed',
          message: clipped));
      return ToolExecutionResult.failure(
        'Could not regenerate plan: ${errors.join("; ")}',
      );
    } else {
      return ToolExecutionResult.success(data: {
        'schedules': results,
        'count': results.length,
        'partial_errors': errors,
      });
    }
  }

  /// D.4 pausePlan — pauses scheduled workouts for a date range.
  ///
  /// Reads the original payload (start_date + days + reason) and delegates
  /// to [WorkoutScheduleService.pauseRange]. The planner cache is
  /// informational only — the dispatcher doesn't need it to perform the
  /// write (the service walks the date range itself and skips completed
  /// entries).
  Future<ToolExecutionResult> _executePausePlan(ToolIntent intent) async {
    final p = intent.payload;
    final startDateRaw = p['start_date'] as String?;
    final days = (p['days'] as num?)?.toInt();
    final reason = p['reason'] as String?;

    if (startDateRaw == null || days == null) {
      return const ToolExecutionResult.failure(
          'Invalid pause_plan payload.');
    }

    final startDate = DateTime.tryParse(startDateRaw);
    if (startDate == null) {
      return const ToolExecutionResult.failure(
          'Invalid start_date format.');
    }

    try {
      final pausedDates =
          await WorkoutScheduleService.instance.pauseRange(
        startDate: startDate,
        days: days,
        reason: reason,
      );
      PausePlanPlanner.instance.clearCache(intent.id);
      return ToolExecutionResult.success(data: {
        'paused_dates': pausedDates,
        'paused_count': pausedDates.length,
      });
    } on PausePlanException catch (e) {
      return ToolExecutionResult.failure(_pausePlanErrorMessage(e));
    }
  }

  /// D.5 switchGoal — destructive two-part operation:
  ///   1. Update `userBox['profile']['primary_goal']` to the new goal,
  ///      stamping `goal_changed_at` / `goal_changed_via` / `previous_goal`
  ///      audit fields.
  ///   2. Apply the regenerated schedules cached by [SwitchGoalDiff] (which
  ///      called [RegeneratePlanPlanner.plan] with `goal: newGoal`). Same
  ///      shape as [_executeRegeneratePlanBlock] — we cannot reuse that
  ///      method directly because the dispatcher needs the success result
  ///      to carry the goal-change metadata too.
  Future<ToolExecutionResult> _executeSwitchGoal(ToolIntent intent) async {
    final p = intent.payload;
    final newGoal = p['new_goal'] as String?;
    if (newGoal == null || newGoal.isEmpty) {
      return const ToolExecutionResult.failure(
          'Invalid switch_goal payload.');
    }
    // Hermes E-pass L28 defense-in-depth: primary_goal feeds the BmrCalculator /
    // PlanGenerator goal SoT. Reject any token FitnessGoals doesn't know BEFORE
    // the write, so a non-onboarding entry point (a future tool, a replayed
    // intent, a server-enum regression) can't persist an unknown goal that
    // silently falls back to maintenance calories (the F19 class).
    if (!FitnessGoals.isKnown(newGoal)) {
      return ToolExecutionResult.failure('Unsupported goal: $newGoal.');
    }

    // The diff widget caches the regenerated raw schedules under intent.id
    // — the dispatcher refuses to write the profile change without the
    // matching plan, so the user can never end up with mismatched
    // profile/schedule state.
    final rawSchedules =
        RegeneratePlanPlanner.instance.getCachedRawSchedules(intent.id);
    if (rawSchedules == null) {
      return const ToolExecutionResult.failure(
        'Open the diff preview first to compute the plan.',
      );
    }

    // 1. Profile write — routed through canonical service
    //    (audit 2026-05-20 A4). patchProfile merges under the
    //    service's mutex so a concurrent home-screen weight write
    //    can't race-clobber the goal change.
    final userBox = HiveService.instance.userBox;
    final rawProfile = userBox.get('profile');
    if (rawProfile is! Map) {
      return const ToolExecutionResult.failure('Profile not found.');
    }
    final oldGoal = (rawProfile['primary_goal'])?.toString();
    await ProfileWriteService.instance.patchProfile({
      'primary_goal': newGoal,
      'goal_changed_at': DateTime.now().toIso8601String(),
      'goal_changed_via': 'ai_coach',
      'previous_goal': oldGoal,
    });

    // 2. Schedule writes (same shape as regenerate_plan_block).
    final wbox = HiveService.instance.workoutBox;
    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final schedule in rawSchedules) {
      final date = schedule['date'] as String;
      try {
        final existing = wbox.get('schedule_$date');
        if (existing is Map && existing['status'] == 'completed') {
          // Concurrent-edit safety net — completed days stay sacred.
          continue;
        }
        // Plan A A-12: route through WorkoutWriteService.
        final parsed = DateTime.tryParse(date);
        if (parsed == null) {
          errors.add('$date: invalid date');
          continue;
        }
        await WorkoutWriteService.instance.upsertScheduled(
          date: parsed,
          entry: Map<String, dynamic>.from(schedule),
          source: WriteSource.aiCoach,
        );
        results.add({
          'date': date,
          'workout': schedule['workout_name'],
          'type': schedule['type'],
        });
      } catch (e) {
        errors.add('$date: $e');
      }
    }

    RegeneratePlanPlanner.instance.clearCache(intent.id);

    if (errors.isEmpty) {
      return ToolExecutionResult.success(data: {
        'old_goal': oldGoal,
        'new_goal': newGoal,
        'schedules': results,
        'count': results.length,
      });
    } else if (results.isEmpty) {
      // Profile already changed but plan regen totally failed — surface the
      // partial state so the user knows. Profile rollback would require a
      // second write that could itself fail.
      return ToolExecutionResult.failure(
        'Goal updated but plan regenerate failed: ${errors.join("; ")}',
      );
    } else {
      return ToolExecutionResult.success(data: {
        'old_goal': oldGoal,
        'new_goal': newGoal,
        'schedules': results,
        'count': results.length,
        'partial_errors': errors,
      });
    }
  }

  String _pausePlanErrorMessage(PausePlanException e) {
    switch (e.code) {
      case 'past_date':
        return 'Cannot pause dates that are too far in the past.';
      case 'no_schedules_in_range':
        return 'No scheduled workouts in that date range to pause.';
      default:
        return e.message;
    }
  }

  /// D.6 createCustomTemplate — saves a multi-day custom template to the
  /// user's library by writing one Hive `tmpl_*` row per day (matching the
  /// existing single-day Template Builder shape so `templatesProvider`,
  /// `_syncWorkoutTemplates`, and `WorkoutScheduleService` all keep working
  /// unchanged).
  ///
  /// Days with no valid exercises are silently skipped at the repository
  /// level. If every day is empty the repo throws `invalid_input` and we
  /// surface a friendly message.
  Future<ToolExecutionResult> _executeCreateCustomTemplate(
      ToolIntent intent) async {
    final p = intent.payload;
    final name = p['name'] as String?;
    final days = ((p['days'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final assignedDaysRaw = ((p['assigned_days'] as List?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();

    if (name == null || name.trim().isEmpty || days.isEmpty) {
      return const ToolExecutionResult.failure(
          'Invalid create_custom_template payload.');
    }

    try {
      final groupId = await WorkoutRepository.instance.createTemplate(
        name: name.trim(),
        description: p['description'] as String?,
        days: days,
        assignedDays:
            assignedDaysRaw.isNotEmpty ? assignedDaysRaw : null,
      );
      return ToolExecutionResult.success(data: {
        'template_group_id': groupId,
        'name': name,
        'days_count': days.length,
      });
    } on CreateTemplateException catch (e) {
      return ToolExecutionResult.failure(
        e.code == 'duplicate_name'
            ? 'A template called "$name" already exists in your library.'
            : e.message,
      );
    } catch (e, stack) {
      debugPrint(
          '[ToolDispatcher] create_custom_template failed: $e\n$stack');
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_create_custom_template_failed',
          message: clipped));
      return const ToolExecutionResult.failure(
          'Could not create that template.');
    }
  }

  /// D.7 scheduleTemplate — fans a template (single OR multi-day group)
  /// across 1-14 calendar dates.
  ///
  /// Flow:
  ///  1. Read the cached `(date, templateId)` assignments the planner
  ///     resolved during diff render (atomic with the display rows via the
  ///     planner's record-return contract).
  ///  2. For each assignment, re-check the schedule entry for `completed`
  ///     status and silently skip — concurrent-edit guard (the user could
  ///     have completed a workout between diff render and Confirm).
  ///  3. Delegate the per-date write to
  ///     [WorkoutScheduleService.assignTemplateToDate] — the canonical
  ///     single-template-to-single-date path that handles displaced
  ///     backups, warm-up/cool-down injection, completed guard, and
  ///     proper week numbering. We avoid duplicating that logic.
  ///  4. Aggregate results — partial success is allowed (some dates land,
  ///     some skipped/failed).
  Future<ToolExecutionResult> _executeScheduleTemplate(
      ToolIntent intent) async {
    final assignments =
        ScheduleTemplatePlanner.instance.getCachedAssignments(intent.id);
    if (assignments == null) {
      return const ToolExecutionResult.failure(
        'Open the diff preview first to compute the schedule.',
      );
    }
    if (assignments.isEmpty) {
      ScheduleTemplatePlanner.instance.clearCache(intent.id);
      return const ToolExecutionResult.failure(
        'All target dates were already completed — nothing to schedule.',
      );
    }

    final box = HiveService.instance.workoutBox;
    final scheduled = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final a in assignments) {
      // Concurrent-edit guard — re-read the schedule entry. The planner
      // already filtered completed days, but the user may have completed
      // a workout since then.
      final existing = box.get('schedule_${a.date}');
      if (existing is Map && existing['status'] == 'completed') {
        continue;
      }

      final date = DateTime.tryParse(a.date);
      if (date == null) {
        errors.add('${a.date}: invalid date');
        continue;
      }

      try {
        await WorkoutScheduleService.instance
            .assignTemplateToDate(a.templateId, date);
        scheduled.add({'date': a.date, 'template_id': a.templateId});
      } catch (e, stack) {
        debugPrint(
            '[ToolDispatcher] schedule_template ${a.date} failed: $e\n$stack');
        errors.add('${a.date}: $e');
      }
    }

    ScheduleTemplatePlanner.instance.clearCache(intent.id);

    if (scheduled.isEmpty) {
      final aggregated = errors.join('; ');
      final clipped = aggregated.length > 500
          ? aggregated.substring(0, 500)
          : aggregated;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_schedule_template_failed',
          message: clipped));
      return ToolExecutionResult.failure(
        errors.isEmpty
            ? 'No dates were scheduled.'
            : 'Could not schedule any dates: ${errors.join("; ")}',
      );
    }
    return ToolExecutionResult.success(data: {
      'scheduled': scheduled,
      'count': scheduled.length,
      if (errors.isNotEmpty) 'partial_errors': errors,
    });
  }

  /// B-10 (APK Test #6 spec §5.5): chat-mode food log MUST decrement the
  /// same visible counter as the LogFood sheet AI tab. The increment is
  /// wired centrally by NutritionWriteService.logMeal — passing
  /// `source: NutritionWriteSource.aiCoachTool` below maps to
  /// `featureAiTextLogPro`. Server-side cap enforcement still lives in
  /// migration 024 (food_text_daily_limit_reached trigger). Do NOT
  /// duplicate the increment here — single source of truth is the writer.
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
        source: NutritionWriteSource.aiCoachTool,
      );
      // Test #11 M1: increment AI text counter at the API-call site.
      // The Gemini function-calling turn already fired (server counted it
      // in ai_coach_interactions). Increment client counter so the
      // food_logger_section "X remaining" display stays in sync.
      unawaited(UsageCounterService.instance.increment(
        AppConstants.featureAiTextLogPro,
        SubscriptionService.instance.isPro(),
      ));
      return ToolExecutionResult.success(data: {
        'log_id': logId,
        'food_name': foodName,
        'total_calories': totalCal,
      });
    } catch (e, stack) {
      debugPrint('[ToolDispatcher] log_meal_by_text failed: $e\n$stack');
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'tool_dispatch_log_meal_by_text_failed',
          message: clipped));
      return const ToolExecutionResult.failure('Could not log that meal.');
    }
  }

  /// Write a meal-by-text log via NutritionWriteService.
  ///
  /// Plan C-13 — routes through the service so:
  ///   • Hive write + cloud projection (BOTH nutrition_logs AND
  ///     nutrition_log_items rows) happen via the canonical writer.
  ///   • Counter increments per source (aiCoachTool → featureAiTextLogPro;
  ///     prelog → no counter, since speculative pre-logs shouldn't burn
  ///     the daily AI text quota until the user confirms).
  ///   • Provider invalidation + fire-and-forget sync runs uniformly.
  ///
  /// `uniqueSuffix` is preserved as a no-op for callers (prelog still
  /// passes it). The service's content-addressed key (format:
  /// `nlog_[date]_[mealType]_[itemsHash]`) is naturally collision-resistant
  /// when the items list differs, which is true across all 21 prelog meals.
  Future<String> _writeFoodLogFromIntent({
    required String date,
    required String foodName,
    required String mealType,
    required int totalCalories,
    required int protein,
    required int carbs,
    required int fat,
    required String servingDescription,
    required NutritionWriteSource source,
    String? uniqueSuffix,
  }) async {
    final parsed = DateTime.tryParse(date) ?? DateTime.now();
    final result = await NutritionWriteService.instance.logMeal(
      date: parsed,
      mealType: mealType,
      items: [
        FoodItem(
          name: foodName,
          // Test #11 M4: the AI coach tool parses free-text and returns
          // pre-computed total macros — no per-item gram value is in the
          // intent payload. Use 100.0 (canonical "per 100g" sentinel) so
          // cloud nutrition_log_items.quantity_g is non-zero and useful
          // for future server-side analytics joins.
          quantityG: 100.0,
          calories: totalCalories.toDouble(),
          protein: protein.toDouble(),
          carbs: carbs.toDouble(),
          fat: fat.toDouble(),
          fiber: 0,
        ),
      ],
      overrideTotalCals: totalCalories,
      overrideTotalProtein: protein,
      source: source,
    );

    if (!result.success) {
      throw StateError(result.errorMessage ?? 'logMeal failed');
    }
    return result.logKey ?? 'nlog_unknown_$uniqueSuffix';
  }

  String _validateMealType(String? raw) {
    const valid = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final lower = raw?.toLowerCase() ?? '';
    return valid.contains(lower) ? lower : 'snacks';
  }

  bool _isNutritionIntent(String type) {
    // Keep this list in sync with the nutrition family handlers above.
    // Only log_meal_by_text remains a write tool (adjust_caloric_target +
    // prelog removed 2026-05-31 — derive-only tool surface; suggestMeal is
    // read-only with no dispatcher entry).
    return type == 'log_meal_by_text';
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
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate dailyNutritionProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(weeklyNutritionProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate weeklyNutritionProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(nutritionSummaryProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate nutritionSummaryProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(recentFoodLogsProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate recentFoodLogsProvider failed: $e\n$st');
    }
    // adjust_caloric_target writes a target_override_<date> key; the
    // macro-target readers (profile MY TARGETS card, diet plan screen) need
    // to re-read the override-aware target.
    try {
      ref.invalidate(macroTargetsProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate macroTargetsProvider failed: $e\n$st');
    }
  }

  void _invalidateProfileProviders(Ref ref) {
    // switch_goal mutates userBox['profile']['primary_goal']. Refresh the
    // profile readers so MY TARGETS card, header chip, and any goal-derived
    // UI re-read the new value immediately. Each call is independently
    // try/caught so one missing provider doesn't block the rest.
    try {
      ref.invalidate(userProfileProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate userProfileProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(userStatsProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate userStatsProvider failed: $e\n$st');
    }
  }

  void _invalidateWorkoutProviders(Ref ref) {
    // CLAUDE.md §15 mandatory batch.
    // Each invalidation is independently try/caught — a missing provider
    // shouldn't prevent the rest from refreshing. Unrolled (vs. iterating
    // a list) because providers are a sealed family and don't share a
    // common upper bound that ref.invalidate accepts.
    try {
      ref.invalidate(currentPlanProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate currentPlanProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(workoutStatsProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate workoutStatsProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(calendarWeekProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate calendarWeekProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(streakProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate streakProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(todayWorkoutProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate todayWorkoutProvider failed: $e\n$st');
    }
    try {
      ref.invalidate(allExercisePRsProvider);
    } catch (e, st) {
      debugPrint('[tool_dispatcher] invalidate allExercisePRsProvider failed: $e\n$st');
    }
  }

  String _todayDateString() => istTodayStr();

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
