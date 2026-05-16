// Regression test for audit 2026-05-16 / F11-C11-2 + F12-C12-3
// (WorkoutScheduleService schedule mutations route through WorkoutWriteService).
//
// Bug: `WorkoutScheduleService` had 13 direct `workoutBox.put` callsites that
// silently bypassed the canonical WriteService. Every schedule mutation
// (assign template, copy week, reschedule, swap exercise, shorten day, mark
// completed/skipped/travel, restore displaced) wrote Hive directly with:
//   - no per-date mutex (race window for two near-simultaneous edits)
//   - no `unawaited(SyncService.instance.syncWorkoutData())` (cloud stale)
//   - no `pushSnapshot()` (AI coach sees stale schedule)
//   - no provider invalidation (UI shows stale calendar / today card)
//
// Fix: per founder-approved NEEDS_DECISION 3 Option A:
//   - 9 schedule writes route through `WorkoutWriteService.upsertScheduled`
//     (which internally handles mutex + sync + invalidation).
//   - 3 non-schedule writes (`_planKey` ×2, template metadata) get explicit
//     `unawaited(SyncService.instance.syncWorkoutData())` fan-out at the
//     callsite.
//   - 1 displacedKey backup stays direct (internal rollback state, no cloud
//     sync needed — restore path at the same sibling method handles the
//     reverse fan-out).
//
// This is a source-grep contract test that bounds the direct-put count.
// If a future edit adds a NEW direct put without explicit fan-out, the test
// fails before APK ship.
//
// closes-diagnose: 2026-05-16-workout-schedule-service-bypass

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkoutScheduleService schedule mutations route through WriteService',
      () {
    late String src;

    setUpAll(() {
      final file = File('lib/core/services/workout_schedule_service.dart');
      expect(file.existsSync(), isTrue);
      src = file.readAsStringSync();
    });

    test('file imports WorkoutWriteService + SyncService', () {
      expect(src.contains("'../services/workout_write_service.dart'"), isTrue,
          reason: 'workout_write_service.dart must be imported');
      expect(src.contains("'../services/sync_service.dart'"), isTrue,
          reason:
              'sync_service.dart must be imported for non-schedule fan-out '
              '(plan-key writes + template metadata).');
    });

    test('direct workoutBox.put count is bounded to known non-schedule sites', () {
      // Whitelist: 2 plan-key writes (generateInitialPlan + generateAndScheduleFromDate),
      // 1 displaced-backup write (assignTemplateToDate internal rollback),
      // 1 template-metadata write (last_used_at sort hint).
      // Total: 4 direct puts. Any new direct put requires updating the
      // whitelist AND adding explicit `unawaited(SyncService.instance...)`
      // fan-out at the callsite.
      final puts = RegExp(r'\b(?:_hive\.)?workoutBox\.put\(').allMatches(src);
      expect(puts.length, equals(4),
          reason:
              'WorkoutScheduleService must have exactly 4 direct workoutBox.put '
              "callsites: 2 _planKey + 1 displacedKey + 1 templateId. Adding a "
              'NEW direct put means the new site MUST route through '
              'WorkoutWriteService.upsertScheduled (preferred) OR add '
              'explicit `unawaited(SyncService.instance.syncWorkoutData())` '
              'fan-out at the callsite. Found ${puts.length} direct puts.');
    });

    test('all schedule mutations route through WorkoutWriteService.upsertScheduled', () {
      // Schedule-mutating methods (markCompleted, markSkipped, swap, shorten,
      // travel, copy week, assign template, restore displaced) must call
      // WorkoutWriteService.instance.upsertScheduled. Expect 9 callsites.
      final upsertCalls =
          RegExp(r'WorkoutWriteService\.instance\.upsertScheduled\(')
              .allMatches(src);
      expect(upsertCalls.length, greaterThanOrEqualTo(9),
          reason:
              'Expected ≥9 WorkoutWriteService.upsertScheduled callsites '
              '(markCompleted, markSkipped, activateTravelMode × N days, '
              'swapExerciseInDay, shortenDay, copyWeek source + dest × 2, '
              'assignTemplateToDate, unscheduleTemplateFromDate). Found '
              '${upsertCalls.length}.');
    });

    test('non-schedule direct puts (plan + template) have explicit fan-out adjacent', () {
      // Anti-regression: the 3 non-schedule direct puts MUST be followed
      // within ~5 lines by an explicit `unawaited(SyncService.instance...)`.
      // We approximate "adjacent" by checking that the file contains at
      // least 3 fan-out invocations.
      final fanOutCalls = RegExp(
              r'unawaited\(\s*SyncService\.instance\.(syncWorkoutData|pushSnapshot)\(')
          .allMatches(src);
      expect(fanOutCalls.length, greaterThanOrEqualTo(3),
          reason:
              'Expected ≥3 explicit `unawaited(SyncService.instance.*)` '
              'fan-out calls for the 3 non-schedule direct puts. Found '
              '${fanOutCalls.length}.');
    });
  });
}
