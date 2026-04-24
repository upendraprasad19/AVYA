import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Stage 0: Reads exercise logs from Hive for Phase 2+ to suggest starting weights.
///
/// Called before plan generation to provide log-aware progression.
/// Upper body: +2.5 kg, Lower body: +5.0 kg, Bodyweight: no suggestion.
class ProgressionResolver {
  /// Lower-body muscle/category keywords for +5 kg progression.
  static const _lowerBodyKeywords = {
    'legs', 'leg', 'quad', 'hamstring', 'glute', 'calf', 'calves',
    'squat', 'deadlift', 'lunge', 'hip thrust', 'leg press',
    'romanian deadlift', 'leg curl', 'leg extension',
  };

  /// Logging types that use bodyweight (no weight suggestion).
  static const _bodyweightTypes = {
    'bodyweight_reps', 'timed', 'cardio', 'distance', 'reps_only',
  };

  /// Resolve suggested starting weights from last phase's exercise logs.
  ///
  /// Returns a map of exerciseName → suggested weight (kg).
  /// Only called for phase >= 2.
  static Map<String, double> resolve({
    required int phase,
    required List<String> exerciseNames,
  }) {
    if (phase <= 1) return {};

    final weights = <String, double>{};

    try {
      final workoutBox = HiveService.instance.workoutBox;
      final now = DateTime.now();
      // Look back 4 weeks (previous phase period)
      final cutoff = now.subtract(const Duration(days: 28));

      // Scan all exercise log keys from the last 4 weeks
      final bestWeights = <String, double>{};

      for (final key in workoutBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('exlog_')) continue;

        final log = workoutBox.get(key);
        if (log is! Map) continue;

        // Check date range
        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null || date.isBefore(cutoff)) continue;

        final name = log['exercise_name'] as String?;
        if (name == null) continue;

        final weightKg = _extractWeight(log);
        if (weightKg == null || weightKg <= 0) continue;

        // Track best (max) weight for each exercise
        if (!bestWeights.containsKey(name) || weightKg > bestWeights[name]!) {
          bestWeights[name] = weightKg;
        }
      }

      // Match exercise names from the new plan to logged exercises
      for (final exerciseName in exerciseNames) {
        final bestWeight = bestWeights[exerciseName];
        if (bestWeight == null) continue;

        // Apply progression increment
        final increment = _isLowerBody(exerciseName) ? 5.0 : 2.5;
        weights[exerciseName] = bestWeight + increment;
      }
    } catch (e) {
      debugPrint('[ProgressionResolver] Error reading Hive logs: $e');
    }

    return weights;
  }

  /// Extract weight from an exercise log entry.
  static double? _extractWeight(Map log) {
    final loggingType = log['logging_type'] as String?;
    if (loggingType != null && _bodyweightTypes.contains(loggingType)) {
      return null; // No weight suggestion for bodyweight exercises
    }

    final weight = log['weight_kg'];
    if (weight is double) return weight;
    if (weight is int) return weight.toDouble();
    if (weight is String) return double.tryParse(weight);
    return null;
  }

  /// Check if exercise targets lower body (for +5 kg vs +2.5 kg increment).
  static bool _isLowerBody(String exerciseName) {
    final lower = exerciseName.toLowerCase();
    return _lowerBodyKeywords.any((kw) => lower.contains(kw));
  }
}
