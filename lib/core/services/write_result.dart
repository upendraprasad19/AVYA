/// Shared write-result types for WorkoutWriteService and (Plan B)
/// NutritionWriteService.
///
/// `WriteResult` is the canonical return shape for every atomic write
/// method. Callers should treat `success == true` as authoritative —
/// the Hive write succeeded and providers were invalidated. Cloud
/// sync is fire-and-forget per CLAUDE.md §15; failure to sync does
/// NOT flip `success` to false.
library;

class WriteResult {
  final bool success;
  final String? logKey;
  final String? errorMessage;

  const WriteResult({
    required this.success,
    this.logKey,
    this.errorMessage,
  });

  factory WriteResult.ok(String logKey) =>
      WriteResult(success: true, logKey: logKey);

  factory WriteResult.fail(String message) =>
      WriteResult(success: false, errorMessage: message);

  /// Sentinel result used when [saveMeal] is called after state was already
  /// cleared (e.g. double-tap on the SAVE MEAL button). The UI should show
  /// "Already saved." rather than a generic error.
  factory WriteResult.noState() => WriteResult.fail('no_state');

  /// True when this result represents a no-state / already-saved condition.
  /// Use instead of comparing `errorMessage == 'no_state'` directly.
  bool get isNoState => !success && errorMessage == 'no_state';

  @override
  String toString() =>
      'WriteResult(success=$success, logKey=$logKey, error=$errorMessage)';
}

/// Source identifier for telemetry + future per-source policy.
/// Logged into Hive entry's `source` field on every write.
enum WriteSource {
  activeWorkout,
  aiCoach,
  editSheet,
  planGenerator,
  schedSwap,
  restore,
}

extension WriteSourceCode on WriteSource {
  /// Stable string code persisted to Hive + cloud. Never rename
  /// these without a migration.
  String get code {
    switch (this) {
      case WriteSource.activeWorkout:
        return 'active_workout';
      case WriteSource.aiCoach:
        return 'ai_coach';
      case WriteSource.editSheet:
        return 'edit_sheet';
      case WriteSource.planGenerator:
        return 'plan_generator';
      case WriteSource.schedSwap:
        return 'sched_swap';
      case WriteSource.restore:
        return 'restore';
    }
  }
}

/// Single set in an exercise log. Always belongs to a parent
/// `exlog_*` Hive entry's `sets[]` array.
class ExerciseSet {
  final double weightKg;       // 0 for bodyweight
  final int reps;              // 0 for timed exercises
  final int? durationSec;      // null for non-timed; populated for plank/cardio
  final int? loggedAtMs;       // millisecondsSinceEpoch — used for 60s dedup window

  const ExerciseSet({
    required this.weightKg,
    required this.reps,
    this.durationSec,
    this.loggedAtMs,
  });

  Map<String, dynamic> toMap() => {
        'weight_kg': weightKg,
        'reps': reps,
        if (durationSec != null) 'duration_sec': durationSec,
        'logged_at_ms': loggedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      };

  factory ExerciseSet.fromMap(Map<dynamic, dynamic> m) => ExerciseSet(
        weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0.0,
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        durationSec: (m['duration_sec'] as num?)?.toInt(),
        loggedAtMs: (m['logged_at_ms'] as num?)?.toInt(),
      );

  /// True if this set is a (weightKg, reps) duplicate of [other]
  /// logged within the dedup window (default 60s).
  bool isDuplicateWithin(ExerciseSet other, {int windowMs = 60000}) {
    if (weightKg != other.weightKg) return false;
    if (reps != other.reps) return false;
    if (durationSec != other.durationSec) return false;
    final a = loggedAtMs ?? 0;
    final b = other.loggedAtMs ?? 0;
    return (a - b).abs() <= windowMs;
  }
}
