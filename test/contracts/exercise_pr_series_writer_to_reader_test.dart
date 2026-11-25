// PR series: Hive write -> read (plan docs/plans/pr-strength-charts.md, 5.2).
//
// The series the Home PR charts draw must agree with the PR the tile shows:
// one point per workout day, the day's best SET (never a cumulative total),
// in the PR's own unit, and peaking at the PR on the PR's day. Rows are
// written through `WorkoutWriteService.logExercise` unless a legacy shape is
// the point of the case (then straight into the box, as a restore or an old
// build left them).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/exercise_pr_series.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

WorkoutWriteService get _w => WorkoutWriteService.instance;
WorkoutRepository get _repo => WorkoutRepository.instance;

DateTime _day(int d) => DateTime(2026, 10, d, 9);

Future<void> _seedLibrary() async {
  final exb = HiveService.instance.exerciseBox;
  await exb.clear();
  for (final (name, type) in const [
    ('Bench Press', 'weight_reps'),
    ('Weighted Pull Up', 'weighted_bodyweight'),
    ('Push Up', 'bodyweight_reps'),
    ('Push Up to Side Plank', 'bodyweight_reps'),
    ('Plank', 'timed'),
    ('Running (Treadmill)', 'cardio'),
    ('Rowing Machine', 'cardio'),
  ]) {
    await exb.put('lib_$name', {'name': name, 'logging_type': type});
  }
}

var _at = 0;
ExerciseSet _set({double w = 0, int r = 0, int? dur, double? km}) => ExerciseSet(
    weightKg: w,
    reps: r,
    durationSec: dur,
    distanceKm: km,
    loggedAtMs: DateTime(2026, 10, 1).millisecondsSinceEpoch + (_at += 1000));

Future<void> _log(String name, int day, List<ExerciseSet> sets) async {
  final r = await _w.logExercise(
    date: _day(day),
    exerciseName: name,
    sets: sets,
    source: WriteSource.activeWorkout,
  );
  expect(r.success, isTrue, reason: '$name day $day: ${r.errorMessage}');
}

/// The series of [name], as `date=value` (and `xreps` when known).
List<String> _series(String name) {
  final prs = _repo.loadAllExercisePRs();
  final s = _repo.loadAllExercisePrSeries(prs)[exercisePrNameKey(name)];
  return [
    for (final p in s?.points ?? const <PrSeriesPoint>[])
      '${p.date}=${p.value}${p.reps == null ? '' : 'x${p.reps}'}',
  ];
}

ExercisePR _pr(String name) => _repo
    .loadAllExercisePRs()
    .firstWhere((p) => exercisePrNameKey(p.exerciseName) == exercisePrNameKey(name));

String _prDay(String name) {
  final d = _pr(name).date;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

/// Series max == the PR's value, and the FIRST point holding it is the PR's day.
void _expectPeakIsPr(String name) {
  final prs = _repo.loadAllExercisePRs();
  final pts = _repo.loadAllExercisePrSeries(prs)[exercisePrNameKey(name)]!.points;
  final max = pts.map((p) => p.value).reduce((a, b) => a > b ? a : b);
  expect(max, _pr(name).bestValue, reason: '$name: chart peak == PR');
  expect(pts.firstWhere((p) => p.value == max).date, _prDay(name),
      reason: '$name: the first peak is on the PR day');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await wwsTestSetup();
    await _seedLibrary();
  });
  tearDown(wwsTestTeardown);

  test('B1: one point per day, oldest first, the max of a doubled day', () async {
    final box = HiveService.instance.workoutBox;
    await _log('Bench Press', 12, [_set(w: 60, r: 8)]);
    await _log('Bench Press', 14, [_set(w: 65, r: 6)]);
    // A legacy key that sorts BEFORE every dated key but belongs to day 13.
    await box.put('exlog_1700000000000_bench', {
      'exercise_name': 'Bench Press', 'date': '2026-10-13',
      'logging_type': 'weight_reps', 'weight_kg': 62.5,
      'sets': [
        {'weight_kg': 62.5, 'reps': 7},
      ],
    });
    // Two rows on day 14: the HIGHER value on the EARLIER-sorting key.
    await box.put('exlog_2026-10-14_00rogue', {
      'exercise_name': 'Bench Press', 'date': '2026-10-14',
      'logging_type': 'weight_reps', 'weight_kg': 67.5,
      'sets': [
        {'weight_kg': 67.5, 'reps': 4},
      ],
    });

    expect(_series('Bench Press'), [
      '2026-10-12=60.0x8',
      '2026-10-13=62.5x7',
      '2026-10-14=67.5x4',
    ]);
    _expectPeakIsPr('Bench Press');
  });

  test('B2: every logging type, literal series and peak == PR', () async {
    await _log('Bench Press', 12, [_set(w: 60, r: 8), _set(w: 70, r: 5)]);
    await _log('Bench Press', 15, [_set(w: 72.5, r: 3)]);
    await _log('Weighted Pull Up', 12, [_set(w: 10, r: 5)]);
    await _log('Weighted Pull Up', 15, [_set(w: 7.5, r: 8)]);
    await _log('Push Up', 12, [_set(r: 12)]);
    await _log('Push Up', 15, [_set(r: 15), _set(r: 11)]);
    await _log('Plank', 12, [_set(dur: 45)]);
    await _log('Plank', 15, [_set(dur: 50), _set(dur: 75)]);
    await _log('Running (Treadmill)', 12, [_set(dur: 1500, km: 4.0)]);
    await _log('Running (Treadmill)', 15, [_set(dur: 1800, km: 5.2)]);
    await _log('Rowing Machine', 12, [_set(dur: 600)]);
    await _log('Rowing Machine', 15, [_set(dur: 900)]);

    expect(_series('Bench Press'), ['2026-10-12=70.0x5', '2026-10-15=72.5x3']);
    expect(_series('Weighted Pull Up'), ['2026-10-12=10.0x5', '2026-10-15=7.5x8']);
    expect(_series('Push Up'), ['2026-10-12=12.0', '2026-10-15=15.0']);
    expect(_series('Plank'), ['2026-10-12=45.0', '2026-10-15=75.0']);
    expect(_series('Running (Treadmill)'), ['2026-10-12=4.0', '2026-10-15=5.2']);
    expect(_series('Rowing Machine'), ['2026-10-12=600.0', '2026-10-15=900.0']);
    expect(_pr('Running (Treadmill)').unit, 'km');
    expect(_pr('Rowing Machine').unit, 'sec');
    for (final n in const [
      'Bench Press', 'Weighted Pull Up', 'Push Up', 'Plank',
      'Running (Treadmill)', 'Rowing Machine',
    ]) {
      _expectPeakIsPr(n);
    }
  });

  test('B3: three sets of 10/9/8 chart 10, never the total 27', () async {
    await _log('Push Up', 12, [_set(r: 10), _set(r: 9), _set(r: 8)]);
    expect(_series('Push Up'), ['2026-10-12=10.0']);
  });

  test('B4: reps are those of the heaviest set; none without per-set detail', () async {
    await _log('Bench Press', 12, [_set(w: 60, r: 10), _set(w: 70, r: 4), _set(w: 70, r: 6)]);
    // Restore-shaped: no sets[]; reps_completed is a total, not a set.
    await HiveService.instance.workoutBox.put('exlog_2026-10-13_restored', {
      'exercise_name': 'Bench Press', 'date': '2026-10-13',
      'logging_type': 'weight_reps',
      'weight_kg': 72.5, 'reps_completed': 15, 'set_number': 3,
    });
    expect(_series('Bench Press'), ['2026-10-12=70.0x6', '2026-10-13=72.5']);
  });

  test('B5: a longer name never lends its history to a shorter one', () async {
    await _log('Push Up', 12, [_set(r: 10)]);
    await _log('Push Up to Side Plank', 13, [_set(r: 30)]);
    expect(_series('Push Up'), ['2026-10-12=10.0']);
    expect(_series('Push Up to Side Plank'), ['2026-10-13=30.0']);
  });

  test('B6: a row with no day is skipped; non-exlog keys are ignored', () async {
    final box = HiveService.instance.workoutBox;
    await _log('Bench Press', 12, [_set(w: 60, r: 8)]);
    await box.put('exlog_nodate', {
      'exercise_name': 'Bench Press',
      'logging_type': 'weight_reps', 'weight_kg': 90.0,
      'sets': [
        {'weight_kg': 90.0, 'reps': 1},
      ],
    });
    await box.put('exlog_baddate', {
      'exercise_name': 'Bench Press', 'date': 'not-a-day',
      'logging_type': 'weight_reps', 'weight_kg': 95.0,
    });
    await box.put('wlog_2026-10-12', {
      'exercise_name': 'Bench Press', 'date': '2026-10-12',
      'logging_type': 'weight_reps', 'weight_kg': 200.0,
    });
    expect(_pr('Bench Press').bestValue, 95.0, reason: 'the PR reader still counts it');
    expect(_series('Bench Press'), ['2026-10-12=60.0x8'],
        reason: 'the chart cannot place a row with no day, so it peaks below the PR');
  });

  test('B7: only rows in the PR unit are charted', () async {
    final box = HiveService.instance.workoutBox;
    await box.put('exlog_2026-10-12_combo', {
      'exercise_name': 'Combo', 'date': '2026-10-12',
      'logging_type': 'weight_reps', 'weight_kg': 40.0,
      'sets': [
        {'weight_kg': 40.0, 'reps': 5},
      ],
    });
    await box.put('exlog_2026-10-13_combo', {
      'exercise_name': 'Combo', 'date': '2026-10-13',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 50},
      ],
      'reps_completed': 50, 'set_number': 1,
    });
    expect(_pr('Combo').unit, 'reps');
    expect(_series('Combo'), ['2026-10-13=50.0']);
  });

  test('B8: a km-ranked cardio exercise gets no point for a duration-only day', () async {
    await _log('Running (Treadmill)', 12, [_set(dur: 1500, km: 4.0)]);
    await _log('Running (Treadmill)', 13, [_set(dur: 2400)]);
    expect(_series('Running (Treadmill)'), ['2026-10-12=4.0']);
  });

  test('B9: a tied best reports the FIRST day, whatever the key order', () async {
    final box = HiveService.instance.workoutBox;
    // The LATER day sits on the earlier-sorting key.
    await box.put('exlog_1700000000000_bench', {
      'exercise_name': 'Bench Press', 'date': '2026-10-20',
      'logging_type': 'weight_reps', 'weight_kg': 80.0,
      'sets': [
        {'weight_kg': 80.0, 'reps': 2},
      ],
    });
    await _log('Bench Press', 12, [_set(w: 80, r: 3)]);
    expect(_prDay('Bench Press'), '2026-10-12');
    _expectPeakIsPr('Bench Press');

    // An equal value of another unit on an EARLIER day takes the PR (and its
    // unit) with it: raw numbers are compared, as before.
    await box.put('exlog_2026-10-05_bench', {
      'exercise_name': 'Bench Press', 'date': '2026-10-05',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 80},
      ],
      'reps_completed': 80, 'set_number': 1,
    });
    expect(_pr('Bench Press').unit, 'reps');
    expect(_series('Bench Press'), ['2026-10-05=80.0']);

    // A dated row never loses a tie to an undated one, in either order.
    await box.clear();
    await box.put('exlog_aaa', {
      'exercise_name': 'Plank', 'logging_type': 'timed',
      'sets': [
        {'duration_sec': 60},
      ],
    });
    await _log('Plank', 12, [_set(dur: 60)]);
    expect(_prDay('Plank'), '2026-10-12');
  });

  test('B10: spellings that differ only in case are one series', () async {
    final box = HiveService.instance.workoutBox;
    await _log('Push Up', 12, [_set(r: 10)]);
    await box.put('exlog_2026-10-13_lower', {
      'exercise_name': 'push up', 'date': '2026-10-13',
      'logging_type': 'bodyweight_reps',
      'sets': [
        {'weight_kg': 0.0, 'reps': 14},
      ],
      'reps_completed': 14, 'set_number': 1,
    });
    expect(_series('PUSH UP'), ['2026-10-12=10.0', '2026-10-13=14.0']);
    expect(_repo.loadAllExercisePRs().length, 1);
  });

  test('a box of 3,000 rows: one build (time printed, not asserted)', () async {
    final box = HiveService.instance.workoutBox;
    final rows = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 3000; i++) {
      final d = DateTime(2024, 1, 1).add(Duration(days: i ~/ 10));
      final day =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      rows['exlog_${day}_e${i % 10}'] = {
        'exercise_name': 'Exercise ${i % 10}', 'date': day,
        'logging_type': 'weight_reps', 'weight_kg': 40.0 + (i % 37),
        'sets': [
          {'weight_kg': 40.0 + (i % 37), 'reps': 5},
        ],
      };
    }
    await box.putAll(rows);
    final sw = Stopwatch()..start();
    final prs = _repo.loadAllExercisePRs();
    final tPrs = sw.elapsedMilliseconds;
    final series = _repo.loadAllExercisePrSeries(prs);
    // ignore: avoid_print
    print('3000 rows: PR list ${tPrs} ms, series ${sw.elapsedMilliseconds - tPrs} ms');
    expect(series.length, 10);
    expect(series['exercise 0']!.points.length, 300);
  });
}
