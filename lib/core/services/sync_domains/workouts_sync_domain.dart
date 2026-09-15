// lib/core/services/sync_domains/workouts_sync_domain.dart
//
// [SyncDomain] wrapper for the workout part-file surfaces (audit
// 2026-05-20 / finding A6 — full migration step, B5 D7-D8 batch).
//
// Wraps the existing private helpers in `lib/core/services/sync/sync_workout.dart`
// via the public forwarders on the `SyncServiceWorkout` extension. The
// scaffold proof-of-pattern (`StreaksSyncDomain`) ships separately
// because streaks is the smallest pair and was migrated first.
//
// Sub-surfaces covered here (six pairs, excluding streaks):
//   - workout_logs           : _syncWorkoutLogs           ↔ _restoreWorkoutLogs
//   - exercise_logs          : _syncExerciseLogs          ↔ _restoreExerciseLogs
//   - schedule_completions   : _syncScheduleCompletions   ↔ _restoreScheduleCompletions
//   - workout_plan           : _syncWorkoutPlan           ↔ _restoreWorkoutPlan
//   - workout_templates      : _syncWorkoutTemplates      ↔ _restoreWorkoutTemplates
//   - scheduled_workouts     : _syncScheduledWorkouts     ↔ _restoreScheduledWorkouts
//
// The matched-pair invariant for this domain is enforced by
// `test/contracts/sync_domain_interface_test.dart` (exhaustiveness
// source-grep) and `test/contracts/restore_completeness_writes_test.dart`.
//
// IMPORTANT ordering note — templates must complete BEFORE schedules
// on both push and restore (APK Test #14 / Bug B.1, FK violation
// 23503). This wrapper preserves that ordering by awaiting templates
// before launching the rest in parallel, matching `syncWorkoutData()`
// and `restoreFromCloudForUser` step-A/B precedent.
//
// Behavioural note: this class is NOT YET WIRED into the SyncService
// fan-out. The legacy fan-out keeps calling private helpers directly.
// The `SyncFlags.useDomainFor('workouts')` gate (default FALSE) flips
// in a follow-up batch after 24h smoke of the wrapper landing.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class WorkoutsSyncDomain extends SyncDomainBase {
  WorkoutsSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'workouts';

  @override
  Future<void> push() async {
    // Templates first (APK Test #14 / Bug B.1) — schedules FK to
    // workout_templates.id.
    await _syncService.pushWorkoutTemplatesForSyncDomain();
    await Future.wait([
      _syncService.pushWorkoutLogsForSyncDomain(),
      _syncService.pushExerciseLogsForSyncDomain(),
      _syncService.pushScheduleCompletionsForSyncDomain(),
      _syncService.pushWorkoutPlanForSyncDomain(),
      _syncService.pushScheduledWorkoutsForSyncDomain(),
    ], eagerError: false);
  }

  @override
  Future<void> restore() async {
    // Workout plan first (APK Test #12.9) so cloud-authoritative
    // status='completed' from scheduled_workouts overlays cleanly.
    await _syncService.restoreWorkoutPlanForSyncDomain();
    await _syncService.restoreWorkoutTemplatesForSyncDomain();
    await Future.wait([
      _syncService.restoreWorkoutLogsForSyncDomain(),
      _syncService.restoreExerciseLogsForSyncDomain(),
      _syncService.restoreScheduleCompletionsForSyncDomain(),
      _syncService.restoreScheduledWorkoutsForSyncDomain(),
    ], eagerError: false);
  }
}
