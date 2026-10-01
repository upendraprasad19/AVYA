// c4d8a2 / B-pass Finding 1 (docs/reviews/5a1ac3e1cb4d-review.md) — the streak
// walk-back anchor must be the onboarding IST *calendar-date midnight*, not the
// raw onboarding_completed_at instant.
//
// Diagnose c4d8a2 made onboarding_completed_at a durable Hive value (the
// completeOnboarding stamp + _syncUserProfile carrier). That ACTIVATED
// `_earliestUserAnchor`'s long-dormant `consider(profile['onboarding_completed_at'])`
// read (the Hive profile previously never carried the column, so the anchor
// silently fell back to the first-workout date). The walk's per-day cursor
// (`today.subtract(days)`) carries the wall-clock time-of-day, and the stop is
// `date.isBefore(anchor)` — so a RAW mid-day onboarding instant excluded the
// onboarding-day workout whenever onboarding's time-of-day exceeded the walk's.
// Fix: anchor on istMidnight(dt). istMidnight only ever moves the anchor EARLIER,
// so it can INCLUDE the onboarding day but never drop a completed day.
//
// This is a behavioral test (real Hive + the real _calculateStreak walk) per
// feedback_source_grep_false_confidence.md — the source-grep contract
// (onboarding_completed_at_durable_writer_test.dart) pins the field presence;
// this pins the runtime streak outcome.
//
// closes-diagnose: c4d8a2
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    resetTestClock();
    await tearDownHiveForTests(tempDir);
  });

  group('onboarding streak anchor — IST-date midnight (c4d8a2 / B-pass F1)', () {
    test('a completed workout ON the onboarding day is counted '
        '(late-in-IST-day onboarding instant does not exclude it)', () async {
      // Walk "now" frozen at 09:00 so the per-day cursor carries a 09:00
      // time-of-day. Onboarding at 22:00 IST on Jun 28 (= 16:30 UTC) → the IST
      // onboarding date is Jun 28. Pre-fix anchor = the raw 16:30 UTC instant;
      // the Jun-28 cursor (09:00) is BEFORE it → the walk breaks before counting
      // Jun 28 (streak 1). Post-fix anchor = istMidnight = Jun 28 00:00 → Jun 28
      // is included (streak 2).
      setTestClockTo(DateTime(2026, 6, 30, 9));
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': '2026-06-28T16:30:00.000Z', // 22:00 IST Jun 28
      });
      // istDateStr of each cursor day resolves to these keys on BOTH IST and
      // UTC test runners (a 09:00 local cursor never crosses the IST boundary).
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-28', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-29', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-30', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.currentStreak();

      expect(streak, 2,
          reason: 'Jun 30 today/pending (not penalised), Jun 29 + Jun 28 both '
              'completed and on/after the onboarding IST date → streak 2. '
              'Pre-fix the raw mid-day instant anchor excluded Jun 28 → 1.');
    });

    test('anchor still stops the walk BEFORE the onboarding date '
        '(pre-account schedule rows never count)', () async {
      // A plan-generator artefact dated the IST day BEFORE onboarding must not
      // count, even though it is marked completed — the anchor is the floor.
      setTestClockTo(DateTime(2026, 6, 30, 9));
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': '2026-06-29T02:00:00.000Z', // 07:30 IST Jun 29
      });
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-30', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-29', {'type': 'PUSH', 'status': 'completed'});
      // Pre-onboarding artefact — must be excluded by the anchor.
      await HiveService.instance.workoutBox
          .put('schedule_2026-06-28', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.currentStreak();

      expect(streak, 2,
          reason: 'Jun 30 + Jun 29 count; Jun 28 is BEFORE the onboarding IST '
              'date (Jun 29) → excluded by the anchor floor → streak 2, not 3.');
    });
  });
}
