// Regression test for audit-2026-05-16 reader-side / R2 —
// `WorkoutRepository.loadAllExercisePRs` must read PER-SET MAX from
// `sets[]` for `bodyweight_reps` and `timed`, NOT cumulative top-level
// `reps_completed` / `duration_seconds`.
//
// Pre-fix had THREE compounded defects in
// `lib/features/train/repositories/workout_repository.dart`:
//
//   1. Filter `raw['type'] != 'exercise_log'` skipped every modern
//      `WorkoutWriteService.logExercise` output (writer never stamps
//      `type` — only `exlog_*` key prefix).
//   2. Read non-existent fields `best_single_set_reps` and
//      `best_single_set_duration` (writer never produces them).
//   3. Fallback `reps_completed / sets_completed.clamp(1, 999)` returned
//      SUM as "best per-set" because `reps_completed` is SUM (Test #6
//      writer contract) and `sets_completed` is NULL on modern rows
//      (writer writes `set_number` instead). `?? 1` → divisor 1 →
//      returned SUM unchanged.
//
// Live symptom 2026-05-16: Push Up 100 reps, Hanging Leg Raise 85 reps,
// Jump Rope 5m 30s — all cumulative across sets.
//
// closes-diagnose: 2026-05-16-pr-cumulative-bug

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late WorkoutRepository repo;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
    repo = WorkoutRepository.instance;
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  tearDown(() async {
    await HiveService.instance.workoutBox.clear();
  });

  group('loadAllExercisePRs — per-set semantic contract', () {
    test('bodyweight_reps: returns MAX reps across sets, not SUM', () async {
      // 5 sets of Push Up: 30, 25, 20, 15, 10 reps. SUM=100. MAX=30.
      await HiveService.instance.workoutBox.put('exlog_2026-05-15_pushup', {
        'exercise_name': 'Push Up',
        'date': '2026-05-15',
        'workout_log_id': 'wlog_2026-05-15',
        'logging_type': 'bodyweight_reps',
        'sets': [
          {'weight_kg': 0.0, 'reps': 30, 'logged_at_ms': 1},
          {'weight_kg': 0.0, 'reps': 25, 'logged_at_ms': 2},
          {'weight_kg': 0.0, 'reps': 20, 'logged_at_ms': 3},
          {'weight_kg': 0.0, 'reps': 15, 'logged_at_ms': 4},
          {'weight_kg': 0.0, 'reps': 10, 'logged_at_ms': 5},
        ],
        'set_number': 5,
        'reps_completed': 100,
        'weight_kg': 0.0,
        'volume_kg': 0.0,
      });

      final prs = repo.loadAllExercisePRs();
      final pushUp = prs.firstWhere((p) => p.exerciseName == 'Push Up');
      expect(pushUp.bestValue, 30.0,
          reason: 'MAX per-set reps (30), not cumulative SUM (100)');
      expect(pushUp.loggingType, 'bodyweight_reps');
    });

    test('timed: returns MAX duration across sets, not SUM', () async {
      // 6 sets of Jump Rope: 60, 55, 50, 45, 40, 80s. SUM=330 (5m 30s). MAX=80.
      await HiveService.instance.workoutBox.put('exlog_2026-05-15_jumprope', {
        'exercise_name': 'Jump Rope',
        'date': '2026-05-15',
        'workout_log_id': 'wlog_2026-05-15',
        'logging_type': 'timed',
        'sets': [
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 60, 'logged_at_ms': 1},
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 55, 'logged_at_ms': 2},
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 50, 'logged_at_ms': 3},
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 45, 'logged_at_ms': 4},
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 40, 'logged_at_ms': 5},
          {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 80, 'logged_at_ms': 6},
        ],
        'set_number': 6,
        'reps_completed': 0,
        'duration_seconds': 330,
        'weight_kg': 0.0,
      });

      final prs = repo.loadAllExercisePRs();
      final jumpRope = prs.firstWhere((p) => p.exerciseName == 'Jump Rope');
      expect(jumpRope.bestValue, 80.0,
          reason: 'MAX per-set duration (80s), not cumulative (330s)');
      expect(jumpRope.loggingType, 'timed');
    });

    test('weight_reps: returns MAX weight from sets[] (top-level also MAX)',
        () async {
      await HiveService.instance.workoutBox.put('exlog_2026-05-15_bench', {
        'exercise_name': 'Bench Press',
        'date': '2026-05-15',
        'workout_log_id': 'wlog_2026-05-15',
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 60.0, 'reps': 10, 'logged_at_ms': 1},
          {'weight_kg': 70.0, 'reps': 8, 'logged_at_ms': 2},
          {'weight_kg': 80.0, 'reps': 5, 'logged_at_ms': 3},
        ],
        'set_number': 3,
        'reps_completed': 23,
        'weight_kg': 80.0,
      });

      final prs = repo.loadAllExercisePRs();
      final bench = prs.firstWhere((p) => p.exerciseName == 'Bench Press');
      expect(bench.bestValue, 80.0);
    });

    test('modern WriteService output (no `type` field) is INCLUDED', () async {
      // Pre-fix filter `raw['type'] != 'exercise_log'` skipped this.
      // Post-fix key-prefix filter `keyStr.startsWith('exlog_')` includes it.
      await HiveService.instance.workoutBox.put('exlog_2026-05-15_curl', {
        'exercise_name': 'Concentration Curl',
        'date': '2026-05-15',
        'workout_log_id': 'wlog_2026-05-15',
        'logging_type': 'weight_reps',
        // NOTE: no 'type' field — modern writer doesn't stamp it.
        'sets': [
          {'weight_kg': 15.0, 'reps': 10, 'logged_at_ms': 1},
        ],
        'set_number': 1,
        'reps_completed': 10,
        'weight_kg': 15.0,
      });

      final prs = repo.loadAllExercisePRs();
      expect(prs.any((p) => p.exerciseName == 'Concentration Curl'), isTrue,
          reason: 'Modern WriteService output (no type field) must be visible');
    });

    test('legacy single-set bodyweight_reps without sets[] is recoverable',
        () async {
      // Single-set legacy row (set_number=1, no sets[]) — top-level
      // reps_completed IS the per-set value.
      await HiveService.instance.workoutBox.put('exlog_2024-01-01_pushup', {
        'exercise_name': 'Push Up',
        'date': '2024-01-01',
        'logging_type': 'bodyweight_reps',
        'set_number': 1,
        'reps_completed': 25,
        'weight_kg': 0.0,
      });

      final prs = repo.loadAllExercisePRs();
      final pushUp = prs.firstWhere((p) => p.exerciseName == 'Push Up');
      expect(pushUp.bestValue, 25.0,
          reason: 'Legacy single-set: top-level reps_completed IS per-set');
    });

    test('legacy multi-set bodyweight_reps without sets[] is SKIPPED', () async {
      // Multi-set legacy row without sets[] — unrecoverable. Skip rather
      // than surface cumulative as PR.
      await HiveService.instance.workoutBox.put('exlog_2024-01-01_pullup', {
        'exercise_name': 'Pull Up',
        'date': '2024-01-01',
        'logging_type': 'bodyweight_reps',
        'set_number': 5,
        'reps_completed': 100, // cumulative — DO NOT surface
        'weight_kg': 0.0,
      });

      final prs = repo.loadAllExercisePRs();
      expect(prs.any((p) => p.exerciseName == 'Pull Up'), isFalse,
          reason:
              'Legacy multi-set row without sets[] must be skipped, not '
              'surfaced with cumulative reps as best-per-set');
    });

    test('cardio: stays cumulative (distance is meaningful as total)',
        () async {
      await HiveService.instance.workoutBox.put('exlog_2026-05-15_run', {
        'exercise_name': 'Run',
        'date': '2026-05-15',
        'logging_type': 'cardio',
        'distance_km': 5.0,
        'duration_seconds': 1800,
      });

      final prs = repo.loadAllExercisePRs();
      final run = prs.firstWhere((p) => p.exerciseName == 'Run');
      expect(run.bestValue, 5.0,
          reason: 'Cardio: total distance IS the PR metric (by design)');
    });
  });

  group('loadAllExercisePRs — forbidden source patterns', () {
    test('reader does not read fictional `best_single_set_*` fields and does '
        'not filter by stripped `type` field', () {
      final src = File(
              'lib/features/train/repositories/workout_repository.dart')
          .readAsStringSync();

      // Anti-regression: check actual code reads, not docstrings. The
      // broken pattern was `log['best_single_set_reps']` / `log['best_single_set_duration']`.
      expect(src.contains("log['best_single_set_reps']"), isFalse,
          reason:
              'Reader must not read fictional `best_single_set_reps` field — '
              'writer never produces it.');
      expect(src.contains("log['best_single_set_duration']"), isFalse,
          reason:
              'Reader must not read fictional `best_single_set_duration` '
              'field — writer never produces it.');
      // Type-filter regression covered by the positive
      // "modern WriteService output (no `type` field) is INCLUDED" test
      // above. The forbidden-pattern check here is only on field reads.
    });
  });
}
