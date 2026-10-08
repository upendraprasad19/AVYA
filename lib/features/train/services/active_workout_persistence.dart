import 'package:icanbefitter/core/services/hive_service.dart';

/// Persists in-progress workout state to Hive so the AI coach snapshot
/// can expose mid-set context. Cleared on workout completion or 2h
/// staleness. Closes audit A4.
class ActiveWorkoutPersistence {
  static const String _key = 'active_session';
  static const Duration _staleness = Duration(hours: 2);

  /// Writes current active state. Call on every set log.
  static Future<void> writeState({
    required String exerciseName,
    required int currentSet,
    required int totalSets,
    required double? weight,
    required int repsTarget,
    required int repsCompleted,
    required List<double> rpeHistory,
    required int? restRemainingSecs,
  }) async {
    await HiveService.instance.workoutBox.put(_key, {
      'exercise': exerciseName,
      'current_set': currentSet,
      'total_sets': totalSets,
      'weight': weight,
      'reps_target': repsTarget,
      'reps_completed': repsCompleted,
      'rpe_history': rpeHistory,
      'rest_remaining_secs': restRemainingSecs,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Clears active state. Call on workout completion or abandonment.
  static Future<void> clearState() async {
    await HiveService.instance.workoutBox.delete(_key);
  }

  /// Reads active state. Returns null if no state OR if state is older than
  /// 2 hours (auto-clears stale entries).
  static Map<String, dynamic>? readState() {
    final raw = HiveService.instance.workoutBox.get(_key);
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final updatedAtStr = map['updated_at'] as String?;
    if (updatedAtStr == null) return map;
    final updatedAt = DateTime.tryParse(updatedAtStr);
    if (updatedAt != null && DateTime.now().difference(updatedAt) > _staleness) {
      // Fire-and-forget cleanup of stale state on read
      HiveService.instance.workoutBox.delete(_key);
      return null;
    }
    return map;
  }
}
