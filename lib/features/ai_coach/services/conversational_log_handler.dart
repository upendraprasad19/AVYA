import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
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

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final id = 'sleep_${now.millisecondsSinceEpoch}';

    final healthBox = HiveService.instance.healthBox;
    final existing = healthBox.get('sleep_logs');
    final logs = existing is List ? List<Map>.from(existing) : <Map>[];

    logs.add({
      'id': id,
      'date': dateStr,
      'sleep_hours': hrs,
      'quality': quality,
      'source': 'chat',
      'created_at': now.toIso8601String(),
    });

    await healthBox.put('sleep_logs', logs);
    unawaited(SyncService.instance.pushSnapshot());
    return true;
  }

  // ── Body Measurements ─────────────────────────────────────────

  Future<bool> _logMeasurement(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final valueCm = (data['value_cm'] as num?)?.toDouble();
    if (type == null || valueCm == null || valueCm <= 0) return false;
    if (!['waist', 'chest', 'hips', 'arms'].contains(type)) return false;

    final healthBox = HiveService.instance.healthBox;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final key = 'measurement_$dateStr';

    // Read-update-write: merge single field into today's measurement record
    final existing = healthBox.get(key);
    final record = existing is Map
        ? Map<String, dynamic>.from(existing)
        : {
            'id': 'meas_${now.millisecondsSinceEpoch}',
            'date': dateStr,
            'created_at': now.toIso8601String(),
          };

    record[type] = valueCm;
    record['updated_at'] = now.toIso8601String();
    await healthBox.put(key, record);
    unawaited(SyncService.instance.pushSnapshot());
    return true;
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
/// Called by [WorkoutLogConfirmCard] on user confirmation. Writes in the
/// same format as [ActiveWorkoutNotifier.completeWorkout] so all other
/// screens (Home, Train, Reports) read the data identically.
Future<void> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref) async {
  final now = DateTime.now();
  final dateStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final workoutBox = HiveService.instance.workoutBox;

  // Save main workout log entry
  final logId = 'wlog_${now.millisecondsSinceEpoch}';
  final totalSets =
      draft.exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
  await workoutBox.put(logId, {
    'id': logId,
    'type': 'workout_log',
    'workout_name': 'Chat Workout',
    'date': dateStr,
    'completed_at': now.toIso8601String(),
    'sets_completed': totalSets,
    'source': 'chat',
  });

  // Save per-exercise logs (same format as ActiveWorkoutNotifier)
  for (final exercise in draft.exercises) {
    final exId =
        'exlog_${now.millisecondsSinceEpoch}_${exercise.name.hashCode}';
    final Map<String, dynamic> logMap = {
      'id': exId,
      'type': 'exercise_log',
      'exercise_name': exercise.name,
      'date': dateStr,
      'logging_type': exercise.loggingType,
      'sets_completed': exercise.sets.length,
      'created_at': now.toIso8601String(),
      'source': 'chat',
    };

    // Add type-specific fields from the first set (summary)
    if (exercise.sets.isNotEmpty) {
      final first = exercise.sets.first;
      if (exercise.loggingType == 'weight_reps' ||
          exercise.loggingType == 'weighted_bodyweight') {
        logMap['weight_kg'] = first.weightKg;
        logMap['reps_completed'] = first.reps;
      } else if (exercise.loggingType == 'bodyweight_reps') {
        logMap['reps_completed'] = first.reps;
      } else if (exercise.loggingType == 'timed') {
        logMap['duration_seconds'] = first.durationSecs;
      }
    }
    if (exercise.loggingType == 'cardio') {
      logMap['duration_seconds'] = (exercise.durationMins ?? 0) * 60;
      logMap['distance_km'] = exercise.distanceKm;
    }

    await workoutBox.put(exId, logMap);
  }

  // Mark today's scheduled workout as completed (if one exists)
  for (final raw in workoutBox.values) {
    if (raw is! Map) continue;
    final entry = Map<String, dynamic>.from(raw);
    if (entry['type'] == 'workout' &&
        entry['date'] == dateStr &&
        entry['status'] != 'completed') {
      entry['status'] = 'completed';
      entry['completed_at'] = now.toIso8601String();
      await workoutBox.put(entry['id'], entry);
      break;
    }
  }

  // Cross-screen invalidation
  ref.invalidate(calendarWeekProvider);
  ref.invalidate(streakProvider);
  ref.invalidate(todayWorkoutProvider);

  // Fire-and-forget cloud sync so AI coach gets fresh workout context.
  unawaited(SyncService.instance.syncWorkoutData());
  unawaited(SyncService.instance.pushSnapshot());

  // Clear the draft
  ref.read(workoutDraftProvider.notifier).clearDraft();
}
