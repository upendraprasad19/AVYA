import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';
import '../providers/ai_coach_provider.dart';

/// Routes AI-detected log actions to existing Riverpod providers.
///
/// Each action type maps to an existing write path:
/// - water → [WaterIntakeNotifier.addWater]
/// - weight → [WeightLogNotifier.logWeight]
/// - food → [FoodLogNotifier.logFood] (with fuzzy Hive search)
/// - sleep → direct Hive write to healthBox
/// - measurement → direct Hive write to healthBox
///
/// All writes are Hive-first (offline). Cross-screen invalidation happens
/// via the target providers themselves (fixed in A.0).
class ConversationalLogHandler {
  final WidgetRef ref;

  const ConversationalLogHandler(this.ref);

  /// Execute a pending log action. Returns true on success.
  Future<bool> executeAction(PendingLogAction action) async {
    try {
      switch (action.type) {
        case LogActionType.water:
          return await _logWater(action.data);
        case LogActionType.weight:
          return _logWeight(action.data);
        case LogActionType.food:
          return await _logFood(action.data);
        case LogActionType.sleep:
          return await _logSleep(action.data);
        case LogActionType.measurement:
          return await _logMeasurement(action.data);
      }
    } catch (_) {
      return false;
    }
  }

  // ── Water ───────────────────────────────────────────────────────

  Future<bool> _logWater(Map<String, dynamic> data) async {
    final ml = (data['ml'] as num?)?.toInt();
    if (ml == null || ml <= 0 || ml > 5000) return false;
    await ref.read(waterIntakeProvider.notifier).addWater(ml);
    return true;
  }

  // ── Weight ──────────────────────────────────────────────────────

  bool _logWeight(Map<String, dynamic> data) {
    final kg = (data['weight_kg'] as num?)?.toDouble();
    if (kg == null || kg < 20 || kg > 300) return false;
    ref.read(weightLogNotifierProvider.notifier).logWeight(kg);
    return true;
  }

  // ── Food ────────────────────────────────────────────────────────

  Future<bool> _logFood(Map<String, dynamic> data) async {
    final foodName = data['food_name'] as String? ?? '';
    final mealType = _validateMealType(data['meal_type'] as String?);
    final quantityG = (data['quantity_g'] as num?)?.toDouble() ?? 100.0;

    if (foodName.isEmpty) return false;

    // Fuzzy search Hive foodBox (case-insensitive substring match)
    final matches = FoodRepository.instance.search(foodName, limit: 5);

    final Map<String, dynamic> foodMap;
    if (matches.isNotEmpty) {
      foodMap = matches.first; // best substring match from 5K database
    } else {
      // No match — create a minimal food map from AI calorie estimates.
      // Scale per-serving estimates back to per-100g so
      // FoodLogNotifier.logFood() calculates correctly.
      foodMap = _buildEstimatedFood(data, quantityG);
    }

    await ref.read(foodLogProvider.notifier).logFood(
          food: foodMap,
          mealType: mealType,
          quantityG: quantityG,
        );
    return true;
  }

  // ── Sleep ───────────────────────────────────────────────────────

  Future<bool> _logSleep(Map<String, dynamic> data) async {
    final hrs = (data['duration_hrs'] as num?)?.toDouble();
    final quality = data['quality'] as String? ?? 'fair';
    if (hrs == null || hrs <= 0 || hrs > 24) return false;

    // audit-2026-05-16 reader-side / F2-R3 — dual-key hazard close-out.
    //
    // Pre-fix this handler wrote ONLY to the legacy `sleep_logs` LIST
    // key. Canonical readers (`profile_provider.dailySleepProvider`,
    // `ai_coach_repository._countSleepLogsLast7Days`, AI snapshot's
    // sleep_7d series) all key off `sleep_log_<istDate>` per-day. So a
    // user who reported sleep through the AI chat had ZERO sleep data
    // visible to the coach's own context — surfaced as "your sleep
    // data isn't logged" responses despite the chat turn appearing to
    // succeed.
    //
    // Fix: route through `HealthWriteService.logSleep` — same canonical
    // writer the manual UI uses. Writes `sleep_log_<istDate>` with
    // overwrite-per-day semantics, fires `syncSleepNow + pushSnapshot`
    // exactly as the audit-2026-05-16 E.7 health-domain pattern
    // mandates. Multiple chat mentions in one IST day collapse to the
    // last-mentioned value (matches how the user actually wants sleep
    // tracked — one value per night).
    //
    // The legacy `sleep_logs` LIST is no longer written from the chat
    // path. `syncSleepNow`'s list-path remains for back-compat with
    // pre-fix on-device data; once devices upgrade past +28, that path
    // can be retired in a follow-up cleanup.
    //
    // closes-diagnose: 2026-05-16-sleep-dual-key
    final result = await HealthWriteService.instance.logSleep(
      date: DateTime.now(),
      hours: hrs,
      quality: quality,
      source: WriteSource.aiCoach,
    );
    return result.success;
  }

  // ── Body Measurements ─────────────────────────────────────────

  Future<bool> _logMeasurement(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final valueCm = (data['value_cm'] as num?)?.toDouble();
    if (type == null || valueCm == null || valueCm <= 0) return false;
    if (!['waist', 'chest', 'hips', 'arms'].contains(type)) return false;

    // audit-2026-05-16 task E.7 — route through HealthWriteService so the
    // measurement key uses `istDateStr` and the sync fan-out + telemetry
    // pattern is identical to every other health-domain mutation.
    final result = await HealthWriteService.instance.logMeasurement(
      date: DateTime.now(),
      partName: type,
      valueCm: valueCm,
      source: WriteSource.aiCoach,
    );
    return result.success;
  }

  // ── Helpers ────────────────────────────────────────────────────

  String _validateMealType(String? raw) {
    const valid = ['breakfast', 'lunch', 'dinner', 'snacks'];
    final lower = raw?.toLowerCase() ?? '';
    return valid.contains(lower) ? lower : 'snacks';
  }

  /// Build a minimal food map from AI calorie estimates, scaled to per-100g.
  ///
  /// FoodLogNotifier.logFood() multiplies per-100g values by (quantityG / 100),
  /// so we must scale the AI's per-serving estimates back to per-100g first.
  Map<String, dynamic> _buildEstimatedFood(
      Map<String, dynamic> data, double quantityG) {
    final factor = quantityG > 0 ? 100.0 / quantityG : 1.0;
    return {
      'id': 'chat_food_${DateTime.now().millisecondsSinceEpoch}',
      'name': data['food_name'] ?? 'Unknown Food',
      'calories_per_100g':
          ((data['calories_estimate'] as num?)?.toDouble() ?? 200) * factor,
      'protein_per_100g':
          ((data['protein_estimate'] as num?)?.toDouble() ?? 10) * factor,
      'carbs_per_100g':
          ((data['carbs_estimate'] as num?)?.toDouble() ?? 25) * factor,
      'fat_per_100g':
          ((data['fat_estimate'] as num?)?.toDouble() ?? 5) * factor,
      'fiber_per_100g': 0.0,
      'source': 'chat_estimate',
    };
  }
}

/// Submit a confirmed workout draft to Hive workoutBox.
///
/// Called by [WorkoutLogConfirmCard] on user confirmation.
///
/// C-8 (audit-2026-05-11) — routed through [WorkoutWriteService] so
/// chat-confirmed workouts match the canonical field shape used by
/// [ActiveWorkoutNotifier.completeWorkout]: `sets[]` per-set array,
/// `set_number`, IST date stamping, deterministic key, per-exercise
/// PR rescan, and 3-tier cloud sync (workout_logs +
/// workout_log_exercises + workout_log_sets). Pre-fix this function
/// wrote `exlog_<ts>_<hash>` rows with the *legacy* shape
/// (`sets_completed`, no `sets[]`, no `set_number`) — invisible to the
/// receipt, AI snapshot `_getThisWeekWorkouts`/`_getPersonalRecords`
/// readers, and the per-set cloud sync. AI coach silently dropped every
/// "I did 3x10 squats" message.
Future<void> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref) async {
  final now = DateTime.now();
  final totalDurationSec = draft.exercises.fold<int>(0, (sum, e) {
    if (e.loggingType == 'cardio') {
      return sum + ((e.durationMins ?? 0) * 60);
    }
    if (e.loggingType == 'timed') {
      return sum +
          e.sets.fold<int>(0, (s, set) => s + (set.durationSecs ?? 0));
    }
    return sum;
  });

  for (final exercise in draft.exercises) {
    final sets = <ExerciseSet>[];
    if (exercise.loggingType == 'cardio') {
      // Cardio: single synthetic set carrying total duration + distance.
      sets.add(ExerciseSet(
        weightKg: 0,
        reps: 0,
        durationSec: (exercise.durationMins ?? 0) * 60,
      ));
    } else {
      for (final s in exercise.sets) {
        sets.add(ExerciseSet(
          weightKg: s.weightKg ?? 0,
          reps: s.reps ?? 0,
          durationSec: s.durationSecs,
        ));
      }
    }
    if (sets.isEmpty) continue;

    await WorkoutWriteService.instance.logExercise(
      date: now,
      exerciseName: exercise.name,
      sets: sets,
      source: WriteSource.aiCoach,
      ref: ref,
    );
  }

  // Mark the day's workout as completed — synthesizes a wlog_<date>
  // and flips today's schedule status if present.
  await WorkoutWriteService.instance.markCompleted(
    date: now,
    workoutName: 'Chat Workout',
    durationSec: totalDurationSec,
    ref: ref,
  );

  // Cross-screen invalidation. WorkoutWriteService.onInvalidate handles
  // the full batch when wired (currentPlan / workoutStats / calendar /
  // streak / today / PRs); we still invalidate the immediate Home
  // surface here so the chat → confirmation → home transition shows
  // fresh state even when the optional `onInvalidate` hook isn't set.
  ref.invalidate(calendarWeekProvider);
  ref.invalidate(streakProvider);
  ref.invalidate(todayWorkoutProvider);

  // Defensive: pushSnapshot may have been triggered already by
  // WorkoutWriteService; calling it again is cheap (snapshot compile is
  // idempotent + rate-limited inside SyncService).
  unawaited(SyncService.instance.pushSnapshot());

  // Clear the draft
  ref.read(workoutDraftProvider.notifier).clearDraft();
}
