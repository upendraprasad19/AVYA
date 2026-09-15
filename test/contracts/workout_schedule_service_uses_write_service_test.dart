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
      // Tech-debt audit 2026-05-20 / A2 split workout_schedule_service.dart
      // (1970 LOC) into 4 services + shim. The "schedule mutations
      // route through WorkoutWriteService" invariant is now distributed
      // across all 5 files; concat them so the bounded direct-put count
      // and upsertScheduled-callsite count assertions still hold at the
      // schedule-services-as-a-whole level (which is what the contract
      // really cares about).
      const schedPaths = [
        'lib/core/services/workout_schedule_service.dart',
        'lib/core/services/workout_schedule_write_service.dart',
        'lib/core/services/workout_schedule_read_service.dart',
        'lib/core/services/swap_service.dart',
        'lib/core/services/template_service.dart',
      ];
      src = schedPaths
          .map((p) => File(p).existsSync() ? File(p).readAsStringSync() : '')
          .join('\n\n');
      expect(src.isNotEmpty, isTrue);
    });

    test('schedule services import WorkoutWriteService + SyncService', () {
      // Post-A2 split — the imports moved into the split files. The
      // shim file no longer needs them. Check that SOMEWHERE in the
      // 5-file union the imports exist.
      expect(src.contains('workout_write_service.dart'), isTrue,
          reason:
              'workout_write_service.dart must be imported by at least one '
              'schedule service (shim, write, read, swap, or template).');
      expect(src.contains('sync_service.dart'), isTrue,
          reason:
              'sync_service.dart must be imported by at least one schedule '
              'service for non-schedule fan-out (plan-key writes + '
              'template metadata).');
    });

    test('direct workoutBox.put count is bounded to known non-schedule sites', () {
      // Post-A2 split, the 4 direct puts redistributed:
      //   - read_service.dart: 2 × `_planKey` (generateInitialPlan +
      //     generateAndScheduleFromDate).
      //   - template_service.dart: 1 × displacedKey (assignTemplateToDate
      //     rollback) + 1 × templateId (last_used_at sort hint).
      // Total still 4. Any NEW direct put across the 5 files requires
      // updating this whitelist AND adding explicit
      // `unawaited(SyncService.instance...)` fan-out at the callsite.
      // audit-fixwave 2026-07-02 / F4 — broaden the direct-put detector to
      // catch ALIASED workoutBox puts. The old regex only matched
      // `workoutBox.put(` / `_hive.workoutBox.put(`, so `pauseRange`'s
      // `final box = _hive.workoutBox; ... box.put(key, map)` (an alias named
      // `box`) slipped past the ==4 bound — the schedule-bypass P1. Now we
      // also resolve every local alias assigned from `_hive.workoutBox` and
      // count `<alias>.put(` for each.
      var putCount =
          RegExp(r'\b(?:_hive\.)?workoutBox\.put\(').allMatches(src).length;
      final aliasNames = RegExp(r'final\s+(\w+)\s*=\s*_hive\.workoutBox\s*;')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .where((n) => n != 'workoutBox') // already counted by the base regex
          .toSet();
      for (final alias in aliasNames) {
        putCount +=
            RegExp('\\b${RegExp.escape(alias)}\\.put\\(').allMatches(src).length;
      }
      expect(putCount, equals(4),
          reason:
              'Schedule services must have exactly 4 direct workoutBox.put '
              'callsites across the 5-file split: 2 _planKey + 1 '
              'displacedKey + 1 templateId (all named `workoutBox`). Adding a '
              'NEW direct put — including via a `final x = _hive.workoutBox` '
              'alias — means the new site MUST route through '
              'WorkoutWriteService.upsertScheduled (preferred) OR add '
              'explicit `unawaited(SyncService.instance.syncWorkoutData())` '
              'fan-out at the callsite. Found $putCount direct puts '
              '(aliases checked: $aliasNames).');
    });

    test('all schedule mutations route through WorkoutWriteService.upsertScheduled', () {
      // Post-A2 split — upsertScheduled callsites redistributed across
      // read/write/swap/template services. The contract is on the
      // aggregate: ≥9 callsites collectively (markCompleted,
      // markSkipped, activateTravelMode × N, swapExerciseInDay,
      // shortenDay, copyWeek source+dest × 2, assignTemplateToDate,
      // unscheduleTemplateFromDate).
      final upsertCalls =
          RegExp(r'WorkoutWriteService\.instance\.upsertScheduled\(')
              .allMatches(src);
      expect(upsertCalls.length, greaterThanOrEqualTo(9),
          reason:
              'Expected ≥9 WorkoutWriteService.upsertScheduled callsites '
              'aggregated across the 5 schedule services. Found '
              '${upsertCalls.length}.');
    });

    test('non-schedule direct puts (plan + template) have explicit fan-out adjacent', () {
      // Same invariant; post-A2 split the unawaited calls live in the
      // file owning each direct put (read_service for plan, template_
      // service for template metadata). Aggregate must still have ≥3.
      final fanOutCalls = RegExp(
              r'unawaited\(\s*SyncService\.instance\.(syncWorkoutData|pushSnapshot)\(')
          .allMatches(src);
      expect(fanOutCalls.length, greaterThanOrEqualTo(3),
          reason:
              'Expected ≥3 explicit `unawaited(SyncService.instance.*)` '
              'fan-out calls aggregated across the schedule services. '
              'Found ${fanOutCalls.length}.');
    });
  });
}
