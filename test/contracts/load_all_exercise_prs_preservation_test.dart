// Preservation pin for `WorkoutRepository.loadAllExercisePRs` (plan
// docs/plans/pr-strength-charts.md, section 5.1).
//
// Written and run GREEN on the code BEFORE the per-row value switch moved to
// `lib/features/train/services/exercise_pr_series.dart`, and green after it:
// one seeded box holding every branch of the reader, with a LITERAL expected
// list. No fixture row creates an equal-value tie across days, so the tie
// rule added in the same batch cannot affect this file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  tearDown(() async {
    await HiveService.instance.workoutBox.clear();
  });

  test('every branch of loadAllExercisePRs, literal expected list', () async {
    final box = HiveService.instance.workoutBox;
    Future<void> put(String key, Map<String, dynamic> row) => box.put(key, row);

    // weight_reps: heaviest set per row, strictly greater row wins.
    await put('exlog_2026-01-05_bench', {
      'exercise_name': 'Bench Press', 'date': '2026-01-05',
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 60.0, 'reps': 8},
        {'weight_kg': 70.0, 'reps': 5},
      ],
      'weight_kg': 70.0, 'reps_completed': 13, 'set_number': 2,
    });
    await put('exlog_2026-01-08_bench', {
      'exercise_name': 'Bench Press', 'date': '2026-01-08',
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 75.0, 'reps': 3},
      ],
      'weight_kg': 75.0, 'reps_completed': 3, 'set_number': 1,
    });
    // weighted_bodyweight.
    await put('exlog_2026-01-05_wpu', {
      'exercise_name': 'Weighted Pull Up', 'date': '2026-01-05',
      'logging_type': 'weighted_bodyweight',
      'sets': [
        {'weight_kg': 10.0, 'reps': 5},
      ],
      'weight_kg': 10.0, 'reps_completed': 5, 'set_number': 1,
    });
    // bodyweight_reps: MAX per set (10), never the SUM (27).
    await put('exlog_2026-01-06_pushup', {
      'exercise_name': 'Push Up', 'date': '2026-01-06',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 10},
        {'weight_kg': 0.0, 'reps': 9},
        {'weight_kg': 0.0, 'reps': 8},
      ],
      'weight_kg': 0.0, 'reps_completed': 27, 'set_number': 3,
    });
    // timed.
    await put('exlog_2026-01-06_plank', {
      'exercise_name': 'Plank', 'date': '2026-01-06',
      'logging_type': 'timed',
      'sets': [
        {'duration_sec': 45},
        {'duration_sec': 60},
      ],
      'set_number': 2,
    });
    // cardio with km on one day and none on another: ranked in km.
    await put('exlog_2026-01-05_run', {
      'exercise_name': 'Run', 'date': '2026-01-05',
      'logging_type': 'cardio',
      'sets': [
        {'duration_sec': 1800, 'distance_km': 5.0},
      ],
      'set_number': 1,
    });
    await put('exlog_2026-01-07_run', {
      'exercise_name': 'Run', 'date': '2026-01-07',
      'logging_type': 'cardio',
      'sets': [
        {'duration_sec': 2400},
      ],
      'set_number': 1,
    });
    // cardio never with km: ranked by the best set's seconds.
    await put('exlog_2026-01-05_row', {
      'exercise_name': 'Rowing', 'date': '2026-01-05',
      'logging_type': 'cardio',
      'sets': [
        {'duration_sec': 600},
      ],
      'set_number': 1,
    });
    await put('exlog_2026-01-07_row', {
      'exercise_name': 'Rowing', 'date': '2026-01-07',
      'logging_type': 'cardio',
      'sets': [
        {'duration_sec': 900},
      ],
      'set_number': 1,
    });
    // distance.
    await put('exlog_2026-01-05_farmer', {
      'exercise_name': 'Farmer Walk', 'date': '2026-01-05',
      'logging_type': 'distance',
      'sets': [
        {'distance_km': 0.04, 'weight_kg': 20.0},
      ],
      'set_number': 1,
    });
    // null logging_type: treated as weight_reps.
    await put('exlog_2026-01-05_mystery', {
      'exercise_name': 'Mystery Lift', 'date': '2026-01-05',
      'sets': [
        {'weight_kg': 50.0, 'reps': 5},
      ],
      'weight_kg': 50.0,
    });
    // unknown logging_type: the default branch reads top-level weight_kg.
    await put('exlog_2026-01-05_odd', {
      'exercise_name': 'Odd Thing', 'date': '2026-01-05',
      'logging_type': 'foo',
      'weight_kg': 33.0,
    });
    // restore-shaped: no sets[], top-level weight.
    await put('exlog_2026-01-05_squat', {
      'exercise_name': 'Squat', 'date': '2026-01-05',
      'logging_type': 'weight_reps',
      'weight_kg': 100.0, 'reps_completed': 15, 'set_number': 3,
    });
    // no resolvable day: filed under 2020.
    await put('exlog_ghost', {
      'exercise_name': 'Ghost Curl',
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 20.0, 'reps': 10},
      ],
      'weight_kg': 20.0,
    });
    // not an exlog key: ignored.
    await put('wlog_2026-01-05', {
      'exercise_name': 'Fake', 'date': '2026-01-05',
      'logging_type': 'weight_reps', 'weight_kg': 999.0,
    });
    // mixed units under one name: raw numbers are compared, the winner's
    // type and unit become the PR's.
    await put('exlog_2026-01-05_combo', {
      'exercise_name': 'Combo', 'date': '2026-01-05',
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 40.0, 'reps': 5},
      ],
      'weight_kg': 40.0,
    });
    await put('exlog_2026-01-06_combo', {
      'exercise_name': 'Combo', 'date': '2026-01-06',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 50},
      ],
      'reps_completed': 50, 'set_number': 1,
    });
    // two names differing only in case: one PR, the winning row's spelling.
    await put('exlog_2026-01-05_dip', {
      'exercise_name': 'Dip', 'date': '2026-01-05',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 12},
      ],
      'reps_completed': 12, 'set_number': 1,
    });
    await put('exlog_2026-01-06_dip', {
      'exercise_name': 'dip', 'date': '2026-01-06',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 15},
      ],
      'reps_completed': 15, 'set_number': 1,
    });

    final got = [
      for (final p in WorkoutRepository.instance.loadAllExercisePRs())
        '${p.exerciseName}|${p.loggingType}|${p.unit}|${p.bestValue}|${_d(p.date)}',
    ];

    expect(got, [
      'Bench Press|weight_reps|kg|75.0|2026-01-08',
      'Rowing|cardio|sec|900.0|2026-01-07',
      'Combo|bodyweight_reps|reps|50.0|2026-01-06',
      'dip|bodyweight_reps|reps|15.0|2026-01-06',
      'Plank|timed|sec|60.0|2026-01-06',
      'Push Up|bodyweight_reps|reps|10.0|2026-01-06',
      'Farmer Walk|distance|km|0.04|2026-01-05',
      'Mystery Lift|weight_reps|kg|50.0|2026-01-05',
      'Odd Thing|foo|kg|33.0|2026-01-05',
      'Run|cardio|km|5.0|2026-01-05',
      'Squat|weight_reps|kg|100.0|2026-01-05',
      'Weighted Pull Up|weighted_bodyweight|kg|10.0|2026-01-05',
      'Ghost Curl|weight_reps|kg|20.0|2020-01-01',
    ]);
  });
}
