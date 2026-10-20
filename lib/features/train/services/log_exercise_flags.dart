import 'package:icanbefitter/core/services/hive_service.dart';

/// Kill-switch for the one-LOG-per-exercise Active Workout flow (§4.6;
/// plan `docs/plans/active-workout-log-exercise.md`).
///
/// **Default OFF (ship dark).** `configBox['enable_log_exercise_button'] = true`
/// turns it on; only the debug-build dev panel writes the key. Flip
/// preconditions are recorded in `docs/ship_dark_pending_review.yaml`.
class LogExerciseFlags {
  LogExerciseFlags._();

  static const String key = 'enable_log_exercise_button';

  static bool get logExerciseButtonEnabled {
    try {
      return HiveService.instance.configBox.get(key) == true;
    } catch (_) {
      return false; // no Hive (pure unit test) → default: OFF
    }
  }
}
