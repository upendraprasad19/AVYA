import 'package:icanbefitter/core/services/hive_service.dart';

/// Kill-switch for the one-LOG-per-exercise Active Workout flow (§4.6;
/// plans `docs/plans/active-workout-log-exercise.md`,
/// `docs/plans/log-exercise-flip.md`).
///
/// **Default ON (LIVE since the flip batch).** A stored `false` is the kill
/// switch (only the debug-build dev panel writes the key); an absent or
/// non-bool value is ON. The old per-set path stays reachable behind `false`
/// until its removal OI closes (`docs/ship_dark_pending_review.yaml`).
class LogExerciseFlags {
  LogExerciseFlags._();

  static const String key = 'enable_log_exercise_button';

  static bool get logExerciseButtonEnabled {
    try {
      final stored = HiveService.instance.configBox.get(key);
      return stored is bool ? stored : true;
    } catch (_) {
      return false; // no Hive (pure unit test) → the old per-set path
    }
  }
}
