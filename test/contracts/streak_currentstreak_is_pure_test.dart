// C-14 (audit-2026-05-11) — regression test that
// `WorkoutRepository.currentStreak()` (the pure-read half of the
// CQRS split) does NOT consume streak freezes as a side effect, no
// matter how many times it's called. Pre-fix
// `calculateCurrentStreak` silently consumed freezes on every
// render — three rebuilds in 10s could burn three freezes for the
// same missed day.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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

  String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

  group('C-14 currentStreak() is pure (no side effects)', () {
    test(
      'three currentStreak() reads do not consume a freeze for a missed day',
      () async {
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        final dayBefore = today.subtract(const Duration(days: 2));

        // Anchor user well before all schedule rows so the walk-back
        // doesn't short-circuit on the onboarding anchor.
        await HiveService.instance.userBox.put('profile', {
          'id': 'A',
          'onboarding_completed_at':
              today.subtract(const Duration(days: 10)).toIso8601String(),
        });

        // Schedule: day-before completed, yesterday missed (pending),
        // today still pending. Walk-back from today: today (pending,
        // i=0 → skip), yesterday (pending, would consume a freeze if
        // the consume path runs).
        await HiveService.instance.workoutBox.put(
            'schedule_${isoDate(dayBefore)}',
            {'type': 'PUSH A', 'status': 'completed'});
        await HiveService.instance.workoutBox.put(
            'schedule_${isoDate(yesterday)}',
            {'type': 'PUSH A', 'status': 'pending'});
        await HiveService.instance.workoutBox
            .put('schedule_${isoDate(today)}',
                {'type': 'PUSH A', 'status': 'pending'});

        await HiveService.instance.userBox.put('progress', {
          'streak_freezes_available': 1,
          'streak_freeze_used_dates': <String>[],
        });

        // Three reads — pure, no side effects.
        final s1 = WorkoutRepository.instance.currentStreak();
        final s2 = WorkoutRepository.instance.currentStreak();
        final s3 = WorkoutRepository.instance.currentStreak();

        // All three should produce the same count (1 — day-before
        // completed, yesterday consumed locally for the count but
        // not persisted).
        expect(s1, equals(s2));
        expect(s2, equals(s3));
        expect(s1, 1,
            reason: 'walk-back: today(pending,skipped) → '
                'yesterday(pending, freeze simulated) → '
                'dayBefore(completed,+1) → streak=1');

        // The freeze in the persisted state must NOT have been consumed.
        final progress = UserRepository.instance.getProgress() ?? {};
        expect(progress['streak_freezes_available'], 1,
            reason:
                'pure read must not decrement freezes_available. '
                'Pre-fix three renders here would burn three freezes.');
        expect(
          (progress['streak_freeze_used_dates'] as List).isEmpty,
          isTrue,
          reason:
              'pure read must not mutate streak_freeze_used_dates.',
        );
      },
    );

    test(
      'consumeMissedDayIfFreezeAvailable() DOES persist freeze consumption',
      () async {
        // Mirror of the above: the explicit-consume variant must
        // actually persist. C-14 — the CQRS split keeps a clear path
        // for the mutating semantics (called only from
        // `train_provider.completeWorkout`).
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        final dayBefore = today.subtract(const Duration(days: 2));

        await HiveService.instance.userBox.put('profile', {
          'id': 'A',
          'onboarding_completed_at':
              today.subtract(const Duration(days: 10)).toIso8601String(),
        });

        await HiveService.instance.workoutBox.put(
            'schedule_${isoDate(dayBefore)}',
            {'type': 'PUSH A', 'status': 'completed'});
        await HiveService.instance.workoutBox.put(
            'schedule_${isoDate(yesterday)}',
            {'type': 'PUSH A', 'status': 'pending'});
        await HiveService.instance.workoutBox
            .put('schedule_${isoDate(today)}',
                {'type': 'PUSH A', 'status': 'pending'});

        await HiveService.instance.userBox.put('progress', {
          'streak_freezes_available': 1,
          'streak_freeze_used_dates': <String>[],
        });

        final streak =
            WorkoutRepository.instance.consumeMissedDayIfFreezeAvailable();
        expect(streak, 1);

        final progress = UserRepository.instance.getProgress() ?? {};
        expect(progress['streak_freezes_available'], 0,
            reason:
                'explicit-consume variant MUST decrement freezes_available '
                'when a missed day was covered by a freeze.');
        expect(
          (progress['streak_freeze_used_dates'] as List),
          contains(isoDate(yesterday)),
          reason:
              'explicit-consume variant MUST record the freeze-covered '
              'date.',
        );
      },
    );
  });
}
