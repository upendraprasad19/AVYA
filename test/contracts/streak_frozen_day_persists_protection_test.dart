// 5e8a1c (2026-05-31) — a missed day that was ALREADY covered by a
// previously-consumed (and persisted) streak freeze must stay protected on
// every subsequent recompute. It must NOT break the streak walk-back.
//
// Surfaced by the year-simulation harness: after the sim consumed a freeze
// for an ~85%-adherence miss, the read-only `currentStreak()` recompute
// BROKE at that historically-frozen day. Root cause: the only branch that
// referenced `usedDates` was the consume guard
//   `freezesAvailable > 0 && !usedDates.contains(dateStr)`
// so an already-used day failed that guard (freezes now 0, day already in
// usedDates) and fell through to `else → break`. The freeze protected the
// day exactly once (during the consuming walk) then permanently collapsed
// the streak on every future read. That silently capped streaks ("streak
// only 3" despite full adherence) and starved the sailor-track rank gates
// (SD1 streak>=7 / LS streak>=14 never qualified → rank stuck at SD2 after
// completing Phase 1).
//
// Fix: an explicit `usedDates.contains(dateStr)` branch BEFORE the consume
// branch treats an already-frozen day as covered (continue), never breaks,
// never double-consumes.
//
// closes-diagnose: 2026-05-31-streak-frozen-day-recompute-break-5e8a1c
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('5e8a1c — a previously-frozen day stays protected on recompute', () {
    test(
      'streak walks ACROSS a day whose freeze was already spent & persisted',
      () async {
        final today = nowWall();
        DateTime daysAgo(int n) => today.subtract(Duration(days: n));
        // Key suffix MUST match what _calculateStreak computes (formatDateKey
        // == istDateStr); use the same helper for schedule keys AND the
        // persisted used-date so the walk's lookups line up exactly.
        String key(DateTime d) => istDateStr(d);

        // Anchor the user well before the oldest schedule row so the walk
        // doesn't short-circuit on the onboarding anchor.
        await HiveService.instance.userBox.put('profile', {
          'id': 'A',
          'onboarding_completed_at': daysAgo(20).toIso8601String(),
        });

        // 5-day window walking back from today:
        //   today   (i=0) completed   → +1
        //   day-1         completed   → +1
        //   day-2         MISSED, but its freeze was already spent (in
        //                 usedDates) → must be SKIPPED, not break
        //   day-3         completed   → +1
        //   day-4         completed   → +1
        // Expected post-fix streak = 4. Pre-fix the walk broke at day-2 → 2.
        await HiveService.instance.workoutBox
            .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'completed'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'pending'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(3))}', {'type': 'PUSH', 'status': 'completed'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(4))}', {'type': 'PUSH', 'status': 'completed'});

        // The freeze for day-2 was consumed on a PRIOR walk: 0 left now, and
        // day-2 recorded in used-dates.
        await HiveService.instance.userBox.put('progress', {
          'streak_freezes_available': 0,
          'streak_freeze_used_dates': <String>[key(daysAgo(2))],
        });

        final streak = WorkoutRepository.instance.currentStreak();
        expect(
          streak,
          4,
          reason:
              'walk must span the already-frozen day-2: '
              'today(+1) day-1(+1) day-2(protected,skip) day-3(+1) day-4(+1) '
              '= 4. Pre-fix it broke at day-2 → 2. closes-diagnose: 5e8a1c',
        );

        // And it must remain a PURE read — no freeze mutation on recompute.
        final progress = UserRepository.instance.getProgress() ?? {};
        expect(progress['streak_freezes_available'], 0,
            reason: 'recompute must not touch freeze balance');
        expect(
          (progress['streak_freeze_used_dates'] as List),
          equals([key(daysAgo(2))]),
          reason: 'recompute must not add/remove used-dates',
        );
      },
    );

    test(
      'a fresh missed day with NO freeze still breaks the streak',
      () async {
        // Guard the fix did not over-protect: a missed day that was never
        // frozen (not in usedDates) and has no freeze available must still
        // break, exactly as before.
        final today = nowWall();
        DateTime daysAgo(int n) => today.subtract(Duration(days: n));
        String key(DateTime d) => istDateStr(d);

        await HiveService.instance.userBox.put('profile', {
          'id': 'A',
          'onboarding_completed_at': daysAgo(20).toIso8601String(),
        });

        await HiveService.instance.workoutBox
            .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'pending'});
        await HiveService.instance.workoutBox
            .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});

        await HiveService.instance.userBox.put('progress', {
          'streak_freezes_available': 0,
          'streak_freeze_used_dates': <String>[],
        });

        final streak = WorkoutRepository.instance.currentStreak();
        expect(streak, 1,
            reason:
                'today(+1) then day-1 missed with no freeze & not previously '
                'frozen → break → streak=1. The fix must NOT protect days '
                'that were never paid for.');
      },
    );
  });
}
