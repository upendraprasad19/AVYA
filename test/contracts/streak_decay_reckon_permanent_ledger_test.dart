// f9d2e7 — Phase 2 D1 (permanent freeze ledger) + D2 (single gated reckon site).
//
// D1: commitRefill no longer CLEARS streak_freeze_used_dates each week — it
//     PRUNES entries older than the 365-day walk horizon. A day protected by a
//     spent freeze stays protected forever (the 5e8a1c walk-back relies on
//     usedDates.contains(day); pre-D1 the weekly clear dropped it → after a
//     Monday refill the walk re-consumed that day or broke the streak — the
//     founder's "streak 1 / freeze 1 after idle days" symptom).
// D2: reckonStreakDecayAndPersist is the SINGLE consume site (rollover +
//     completeWorkout). It PERSISTS missed-day freeze consumption ONLY when
//     restoreCompletedTick > 0 AND a schedule exists — so a cold-start-empty /
//     pre-restore device never spuriously decays. It always returns an accurate
//     count (read-only when gated off).
//
// closes-diagnose: f9d2e7
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  // Single clock read for the whole run so all schedule keys + used-dates align.
  final today = nowWall();
  DateTime daysAgo(int n) => today.subtract(Duration(days: n));
  // Key suffix MUST match what _calculateStreak computes (formatDateKey ==
  // istDateStr); use the same helper for schedule keys AND used-dates.
  String key(DateTime d) => istDateStr(d);

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // D2 reckon gates on this; default each test to "restore not yet done".
    SyncService.instance.restoreCompletedTick.value = 0;
  });

  tearDown(() async {
    SyncService.instance.restoreCompletedTick.value = 0;
    await tearDownHiveForTests(tempDir);
  });

  group('D1 — commitRefill keeps a PERMANENT used-dates ledger (f9d2e7)', () {
    test('commitRefill does NOT clear used_dates (recent dates survive)',
        () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[key(daysAgo(3))],
        'streak_freezes_last_refill': key(daysAgo(10)),
      });
      StreakProgressService.instance
          .commitRefill(maxFreezes: 3, thisMondayStr: key(daysAgo(0)));
      final p = UserRepository.instance.getProgress()!;
      expect(p['streak_freeze_used_dates'], contains(key(daysAgo(3))),
          reason: 'D1: refill must NOT clear the recent ledger (pre-fix → [])');
      expect(p['streak_freezes_available'], 1, reason: '0 + 1 refill');
    });

    test('commitRefill prunes used_dates older than the 365d walk horizon',
        () async {
      final old = key(daysAgo(400));
      final recent = key(daysAgo(5));
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[old, recent],
        'streak_freezes_last_refill': key(daysAgo(10)),
      });
      StreakProgressService.instance
          .commitRefill(maxFreezes: 3, thisMondayStr: key(daysAgo(0)));
      final used = (UserRepository.instance.getProgress()!
          ['streak_freeze_used_dates'] as List);
      expect(used, contains(recent));
      expect(used, isNot(contains(old)), reason: 'D1: prune >365d');
    });

    test('prunePastHorizon drops >365d, keeps <=365d, sorts (pure)', () {
      final res = StreakProgressService.prunePastHorizon(
          [key(daysAgo(400)), key(daysAgo(100)), key(daysAgo(1))]);
      expect(res, [key(daysAgo(100)), key(daysAgo(1))],
          reason: '400d dropped; 100d + 1d kept, ascending');
    });

    test('a frozen day stays protected ACROSS a weekly refill (the D1 bug)',
        () async {
      // today completed, day-1 completed, day-2 MISSED (frozen on a prior
      // walk), day-3 completed, day-4 completed. Freeze for day-2 already
      // spent (available 0, day-2 in used_dates). A weekly refill happens.
      // Pre-D1 the refill CLEARED used_dates → day-2 protection lost → the walk
      // re-consumes (avail now 1) or breaks. Post-D1 the ledger survives → the
      // walk still spans day-2 → streak 4.
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': daysAgo(20).toIso8601String(),
      });
      const sched = [
        [0, 'completed'],
        [1, 'completed'],
        [2, 'pending'],
        [3, 'completed'],
        [4, 'completed'],
      ];
      for (final row in sched) {
        await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(row[0] as int))}',
          {'type': 'PUSH', 'status': row[1]},
        );
      }
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[key(daysAgo(2))],
        'streak_freezes_last_refill': key(daysAgo(10)),
      });
      // Weekly refill: tops available to 1, KEEPS used_dates per D1.
      StreakProgressService.instance
          .commitRefill(maxFreezes: 3, thisMondayStr: key(daysAgo(0)));
      final streak = WorkoutRepository.instance.currentStreak();
      expect(streak, 4,
          reason: 'day-2 protection survives the refill (D1); '
              'walk spans it → today,day-1,day-3,day-4 = 4');
    });
  });

  group('D2 — reckonStreakDecayAndPersist gating (f9d2e7)', () {
    Future<void> seedMissedDay() async {
      // today pending (i==0 → never penalised), day-1 MISSED, day-2 completed,
      // 1 freeze available → a CONSUMING walk spends the freeze on day-1.
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': daysAgo(20).toIso8601String(),
      });
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(0))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox.put('schedule_${key(daysAgo(2))}',
          {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });
    }

    test('restoreCompletedTick==0 → gated OFF: no persist (available unchanged)',
        () async {
      await seedMissedDay();
      SyncService.instance.restoreCompletedTick.value = 0;
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      final p = UserRepository.instance.getProgress()!;
      expect(p['streak_freezes_available'], 1,
          reason: 'pre-restore must NOT consume — un-restored completions could '
              'read as missed → spurious freeze spend / streak break');
      expect((p['streak_freeze_used_dates'] as List), isEmpty);
    });

    test('no schedule rows → gated OFF: no persist (cold-start-empty)',
        () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });
      SyncService.instance.restoreCompletedTick.value = 1; // restore done...
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      final p = UserRepository.instance.getProgress()!;
      expect(p['streak_freezes_available'], 1,
          reason: '...but empty schedule → nothing to decay → no persist');
    });

    test('restoreCompletedTick>0 + schedule + missed day → PERSISTS the consume',
        () async {
      await seedMissedDay();
      SyncService.instance.restoreCompletedTick.value = 1;
      final streak = WorkoutRepository.instance.reckonStreakDecayAndPersist();
      final p = UserRepository.instance.getProgress()!;
      expect(p['streak_freezes_available'], 0,
          reason: 'day-1 missed → freeze consumed + PERSISTED');
      expect((p['streak_freeze_used_dates'] as List), contains(key(daysAgo(1))),
          reason: 'the consumed day is recorded in the permanent ledger');
      expect(streak, 1, reason: 'only day-2 completed counts (day-1 frozen)');
    });

    // OBS-8b (2026-06-25) — the reckon must ALSO persist the freshly-computed
    // current_streak_days. Pre-fix it stamped only the freeze fields, so a streak
    // that DECAYED via the day-rollover reckon (no workout logged) left cloud
    // `user_progress.current_streak_days` stale — the AI snapshot + predictions
    // (the cloud-value readers) then saw the old count (the founder's "streak 1
    // after idle days" cloud symptom). Home reads a LIVE count so was unaffected.
    test('OBS-8b: decay with NO freeze persists current_streak_days 1 -> 0',
        () async {
      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': daysAgo(20).toIso8601String(),
      });
      // day-0 pending (never penalised), day-1 MISSED, day-2 completed; 0 freezes
      // → the walk breaks at day-1 → streak 0.
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(0))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox.put('schedule_${key(daysAgo(2))}',
          {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
        'current_streak_days': 1, // STALE — the founder's symptom
      });
      SyncService.instance.restoreCompletedTick.value = 1;
      final streak = WorkoutRepository.instance.reckonStreakDecayAndPersist();
      final p = UserRepository.instance.getProgress()!;
      expect(streak, 0, reason: 'day-1 missed, no freeze -> streak breaks to 0');
      expect(p['current_streak_days'], 0,
          reason: 'OBS-8b: the reckon must persist the decayed count '
              '(pre-fix left current_streak_days stale at 1)');
    });

    test('OBS-8b: freeze-consume path persists current_streak_days (stale 7 -> 1)',
        () async {
      await seedMissedDay(); // 1 freeze, day-1 missed -> consumed -> streak 1
      await UserRepository.instance
          .updateProgress({'current_streak_days': 7}); // stale, merged in
      SyncService.instance.restoreCompletedTick.value = 1;
      final streak = WorkoutRepository.instance.reckonStreakDecayAndPersist();
      final p = UserRepository.instance.getProgress()!;
      expect(streak, 1);
      expect(p['current_streak_days'], 1,
          reason: 'OBS-8b: reckon persists the count even when a freeze saved it');
    });

    test('OBS-8b: gated-off (restore not settled) does NOT persist the count',
        () async {
      await seedMissedDay();
      await UserRepository.instance.updateProgress({'current_streak_days': 9});
      SyncService.instance.restoreCompletedTick.value = 0; // gated off
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(UserRepository.instance.getProgress()!['current_streak_days'], 9,
          reason: 'pre-restore read-only path must not persist a spurious decay '
              'before completions are restored');
    });
  });

  group('progress-map writer — no lost update (Hermes L27 verification, f9d2e7)',
      () {
    test('completeWorkout sequence: consume (fire-and-forget) + a later '
        'updateProgress lose NEITHER the freeze consume NOR the count', () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
        'total_workouts_done': 5,
      });
      // Mimic reckon's consume: commitConsume is sync, its updateProgress is
      // fire-and-forget (NOT awaited) — exactly as _calculateStreak invokes it.
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-06-17'],
      );
      // Mimic completeWorkout's subsequent whole-map progress write (~line 1450).
      await UserRepository.instance.updateProgress({'total_workouts_done': 6});
      // Let any pending fire-and-forget put settle.
      await Future<void>.delayed(Duration.zero);

      final p = UserRepository.instance.getProgress()!;
      expect(p['streak_freezes_available'], 0,
          reason: 'the consume must NOT be reverted by the later updateProgress '
              '(Hermes L27 lost-update hypothesis — pinned safe)');
      expect((p['streak_freeze_used_dates'] as List), contains('2026-06-17'),
          reason: 'consumed date survives the second progress write');
      expect(p['total_workouts_done'], 6,
          reason: 'the workout-count increment also survives');
    });
  });
}
