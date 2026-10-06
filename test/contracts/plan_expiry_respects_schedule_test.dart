// Behavioral contract for APK +34 / obs 1+5.1+6 (diagnose a1d4f9): the plan is
// "expired" only if the stored plan_end_date says so AND no real workout day is
// scheduled today or later. A regeneration can advance scheduled_workouts past
// a stale plan_json plan_end_date (a source-of-truth split); trusting the stale
// constant falsely reported "expired / wrong week / not scheduled".
//
// Pure decision test (no Hive, no clock) — same pattern as
// completedWeekNumbersFrom (week_completion_check_test.dart). The Hive scan that
// feeds the real isPhaseExpired() is the thin wrapper; this pins the semantic.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

void main() {
  final today = DateTime(2026, 6, 9); // matches the founder's repro date

  group('isPhaseExpiredFrom — materialized schedule overrides a stale plan_end', () {
    test('stale plan_end (05-24) but a future scheduled workout (07-01) → NOT expired', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(
            today, DateTime(2026, 5, 24), [DateTime(2026, 7, 1)]),
        isFalse,
        reason: 'scheduled_workouts extends past the stale plan_json window',
      );
    });

    test('past plan_end and only PAST workout days → expired', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(
            today, DateTime(2026, 5, 24), [DateTime(2026, 5, 20)]),
        isTrue,
      );
    });

    test('a workout scheduled TODAY → not expired', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(
            today, DateTime(2026, 5, 24), [today]),
        isFalse,
      );
    });

    test('inside the stored window → not expired regardless of schedule', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(
            today, DateTime(2026, 7, 5), const []),
        isFalse,
      );
    });

    test('null stored end → not expired', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(today, null, const []),
        isFalse,
      );
    });

    test('past plan_end + empty schedule → genuinely expired', () {
      expect(
        WorkoutScheduleReadService.isPhaseExpiredFrom(
            today, DateTime(2026, 5, 24), const []),
        isTrue,
      );
    });
  });
}
