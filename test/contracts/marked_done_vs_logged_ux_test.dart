// Regression test for audit-2026-05-17 OI-05 — differentiate
// "marked done outside the app" from "logged exercises" in completed-
// day UX surfaces (day_detail_sheet + train_screen).
//
// Root cause (verified via live cloud query 2026-05-17):
// `WorkoutScheduleService.markCompleted` allows schedule.status flip
// without requiring any exlog rows — this is by design for the
// "I trained outside the app" use case. But the day-card UX surfaces
// (DONE chip + VIEW WORKOUT CARD button) implied detailed exercise
// data existed.
//
// On +27 install, founder's cloud had 2/11 schedule_completions of
// this shape (May 14 + 15 Hybrid A) — both produced misleading
// "View Card does nothing" + "No exercise data logged" observations.
//
// closes-diagnose: 2026-05-17-marked-done-without-logging-7c4e5d
//
// Source-grep contract — pins the differentiated UX so a refactor
// can't silently revert to the misleading single-state copy.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  group('OI-05 — marked-done-without-logging UX', () {
    test('day_detail_sheet renders MARKED DONE chip when no exlog rows',
        () {
      final src = File('lib/features/home/widgets/day_detail_sheet.dart')
          .readAsStringSync();
      expect(
        src.contains("hasLoggedExercises ? 'COMPLETED' : 'MARKED DONE'"),
        isTrue,
        reason: 'Day detail completed footer must differentiate the chip '
            'label based on whether exlog rows exist for the IST date. '
            'Pre-fix every completed day rendered "COMPLETED" regardless.',
      );
    });

    test('day_detail_sheet hides VIEW WORKOUT CARD when no exlog rows',
        () {
      final src = File('lib/features/home/widgets/day_detail_sheet.dart')
          .readAsStringSync();
      // The View Card button is now inside `if (hasLoggedExercises)`.
      expect(
        src.contains('if (hasLoggedExercises)'),
        isTrue,
        reason: 'View Workout Card button must be gated on '
            'hasLoggedExercises; rendering it for marked-done-without-'
            'logging days is misleading (tap was the silent no-op bug).',
      );
      // The empty-state replacement copy.
      expect(
        src.contains(
            'Marked done outside the app — no exercises were logged.'),
        isTrue,
        reason: 'Empty-state replacement copy must explain WHY there is '
            'no View Card affordance, not just hide it silently.',
      );
    });

    test('day_detail_sheet has _hasExerciseLogsForDate probe helper', () {
      final src = File('lib/features/home/widgets/day_detail_sheet.dart')
          .readAsStringSync();
      expect(
        src.contains('bool _hasExerciseLogsForDate()'),
        isTrue,
        reason: 'Cheap probe helper required so the build method can '
            'pre-check exlog availability without instantiating a full '
            'WorkoutReceiptData.',
      );
      // Probe must read both the canonical index AND fallback grep.
      expect(
        src.contains("'exercise_log_index_") &&
            src.contains("ks.startsWith('exlog_')"),
        isTrue,
        reason: 'Probe must mirror WorkoutReceiptData.fromExerciseLogs '
            'fallback logic — canonical index FIRST, exlog grep '
            'SECOND. Otherwise the probe diverges from the receipt '
            'builder and we recreate the silent-mismatch bug.',
      );
    });

    test('train_screen expanded view differentiates copy for completed days',
        () {
      final src = readScreenSource('train');
      expect(
        src.contains(
            'Marked done outside the app — no exercises were logged.'),
        isTrue,
        reason: 'Train screen expanded view must show the same '
            '"marked done outside app" copy as day_detail_sheet for '
            'completed days with no exlog rows. Pre-fix copy was '
            '"No exercise data logged" — misleading on completed days.',
      );
      expect(
        src.contains('day.isDone'),
        isTrue,
        reason: 'Differentiation gates on day.isDone so non-completed '
            'days still show the generic "No exercise data logged" '
            'copy (those should remain unchanged).',
      );
    });
  });
}
