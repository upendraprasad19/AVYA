// Regression test — bug f1c8e4.
//
// WorkoutWriteService.markCompleted is the canonical LIVE completion writer
// (train_provider.completeWorkout calls it; the comment says it "Replaces
// repo.saveWorkoutLog + repo.markWorkoutCompleted"). Pre-fix it wrote its
// wlog_<date> row WITHOUT `type: 'workout_log'` and used `completed_at_ms`
// instead of `completed_at`. Every count/history reader filters
// `type == 'workout_log'`:
//   - WorkoutRepository.getWeeklyWorkoutCounts (reports "This Week" tile +
//     4-week frequency chart — apk34 c2e8b4 repointed the tile here)
//   - WorkoutRepository.getWorkoutLogs (history + getRecentWorkoutCompletionHours)
//   - BadgeService totalWorkouts
//   - AiSnapshotBuilder recent-workouts context
// so a live completion was invisible to ALL of them until a reinstall+restore
// (sync_workout._restoreWorkoutLogs DOES stamp type:'workout_log' + completed_at)
// re-tagged it — and the additive restore guard never upgrades a pre-existing
// type-less row. The now-dead saveWorkoutLog DID stamp both; the A-13 derive-only
// refactor dropped them and no test pinned `type` on the wlog row.
//
// This behavioral test fails RED before the fix (count == 0, history empty,
// row has no type/completed_at) and GREEN after markCompleted stamps both.
//
// closes-diagnose: f1c8e4
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('markCompleted wlog row is counted by the workout-log readers (f1c8e4)',
      () {
    test('getWeeklyWorkoutCounts counts a live markCompleted completion',
        () async {
      final today = DateTime.now();
      await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Push A',
        durationSec: 1800,
      );

      final counts = WorkoutRepository.instance.getWeeklyWorkoutCounts();
      expect(
        counts[0],
        1,
        reason: 'a workout completed today via the canonical live writer must '
            'appear in This Week. Pre-fix markCompleted wrote no '
            "type:'workout_log' so getWeeklyWorkoutCounts skipped it.",
      );
    });

    test('getWorkoutLogs surfaces a live markCompleted completion', () async {
      final today = DateTime.now();
      await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Pull A',
        durationSec: 1500,
      );

      final logs = WorkoutRepository.instance.getWorkoutLogs();
      expect(
        logs,
        hasLength(1),
        reason: 'workout history reads type==workout_log; the live wlog row '
            'must carry that type.',
      );
      expect(logs.first['workout_name'], 'Pull A');
    });

    test('markCompleted wlog row carries type:workout_log + completed_at (ISO)',
        () async {
      final today = DateTime.now();
      await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Legs',
        durationSec: 1200,
      );

      final box = HiveService.instance.workoutBox;
      final wlog = box.get(WorkoutWriteService.wlogKey(today)) as Map;
      expect(
        wlog['type'],
        'workout_log',
        reason: 'all count/history readers filter type==workout_log; the live '
            'writer must stamp it (the dead saveWorkoutLog + the restore path '
            'both do).',
      );
      expect(
        wlog['completed_at'],
        isA<String>(),
        reason: 'getRecentWorkoutCompletionHours reads completed_at (ISO); '
            'pre-fix markCompleted only wrote completed_at_ms.',
      );
    });
  });
}
