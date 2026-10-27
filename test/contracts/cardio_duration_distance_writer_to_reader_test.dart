// OI-389 Batch 1a (closes OI-380, OI-382): a cardio or distance exercise
// keeps its minutes and km from the writer to every reader. Plan
// docs/plans/cardio-duration-distance.md §4 (T-numbers below are the plan's).
//
// Writer: WorkoutWriteService.logExercise / editLog / moveExerciseLogs
// (lib/core/services/workout_write_service.dart), ExerciseSet
// (write_result.dart), exerciseSetFromInput (log_exercise_logic.dart).
// Readers: WorkoutReadService.aggregateDistanceKm, exerciseLogDetail (Train
// expanded row), cardioDistanceDetail (chips, preview, receipt), the week
// selector line, WorkoutRepository.loadAllExercisePRs + ExercisePR, the
// graduation top-3.
//
// Real Hive (wws setup). The active-workout capture and edit-sheet widget legs
// live in test/features/train/log_exercise/log_exercise_card_test.dart (T32b)
// and test/features/train/edit_sheet_cardio_test.dart, the chips in
// test/widgets/ward_set_chips_test.dart (T4b / T11 / T29: no Hive, so fonts
// load) (T8 rendered legs, T20,
// T30); the move-merge payload legs in
// test/sync/cardio_move_merge_push_behavioral_test.dart (T19).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/set_log_copy.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/logging_type_repair_migrator.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/cardio_format.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';
import 'package:icanbefitter/features/train/utils/exercise_log_detail.dart';
import 'package:icanbefitter/features/train/utils/set_count_label.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';
import 'package:icanbefitter/features/train/widgets/edit_workout_log_sheet.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

const _nb = kNbsp;
const _sep = kDetailSeparator;

final _day = DateTime(2026, 10, 20, 9);
final _t0 = _day.millisecondsSinceEpoch;

WorkoutWriteService get _w => WorkoutWriteService.instance;

Future<void> _seedLibrary() async {
  final exb = HiveService.instance.exerciseBox;
  await exb.clear();
  for (final (name, type) in const [
    ('Rowing Machine', 'cardio'),
    ('Running (Treadmill)', 'cardio'),
    ('Sled Push', 'cardio'),
    ('Farmers Carry', 'distance'),
    ('Plank', 'timed'),
    ('Bench Press', 'weight_reps'),
  ]) {
    await exb.put('lib_$name', {'name': name, 'logging_type': type});
  }
}

Future<WriteResult> _log(String name, List<ExerciseSet> sets,
        {DateTime? date, String? hint}) =>
    _w.logExercise(
      date: date ?? _day,
      exerciseName: name,
      sets: sets,
      source: WriteSource.activeWorkout,
      loggingTypeHint: hint,
    );

Map<String, dynamic> _row(String name, {DateTime? date}) =>
    Map<String, dynamic>.from(HiveService.instance.workoutBox
        .get(WorkoutWriteService.exlogKey(date ?? _day, name)) as Map);

List<Map> _sets(Map<String, dynamic> row) =>
    (row['sets'] as List).cast<Map>();

ExerciseSet _set({
  double w = 0,
  int r = 0,
  int? dur,
  double? km,
  int at = 0,
}) =>
    ExerciseSet(
        weightKg: w,
        reps: r,
        durationSec: dur,
        distanceKm: km,
        loggedAtMs: _t0 + at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await wwsTestSetup();
    await _seedLibrary();
  });
  tearDown(wwsTestTeardown);

  group('logExercise keeps cardio minutes and km', () {
    test('T1: Rowing Machine 1200 s + 5.0 km', () async {
      final r = await _log('Rowing Machine', [_set(dur: 1200, km: 5.0)]);
      expect(r.success, isTrue, reason: r.errorMessage);
      final row = _row('Rowing Machine');
      expect(row['logging_type'], 'cardio');
      expect(_sets(row).single['duration_sec'], 1200);
      expect(_sets(row).single['distance_km'], 5.0);
      expect(row['distance_km'], 5.0);
      expect(exerciseLogDetail(row), '20${_nb}min${_sep}5.0${_nb}km',
          reason: 'cardio carries no set count');
    });

    test('T2: km is totalled over the STORED sets; a retry adds nothing',
        () async {
      await _log('Rowing Machine', [_set(dur: 1200, km: 5.0)]);
      await _log('Rowing Machine', [_set(dur: 600, km: 3.0, at: 120000)]);
      expect(_row('Rowing Machine')['distance_km'], 8.0);

      final retry =
          await _log('Rowing Machine', [_set(dur: 600, km: 3.0, at: 150000)]);
      expect(retry.success, isTrue);
      final afterRetry = _row('Rowing Machine');
      expect(afterRetry['distance_km'], 8.0);
      expect(afterRetry['set_number'], 2);

      await _log('Rowing Machine', [_set(dur: 600, km: 4.0, at: 160000)]);
      final row = _row('Rowing Machine');
      expect(row['distance_km'], 12.0,
          reason: 'a set with a different km is not a duplicate');
      expect(_sets(row).map((s) => s['distance_km']), [5.0, 3.0, 4.0]);
    });

    test('T3: phantom duration / km cleared on weight and timed rows',
        () async {
      await _log('Bench Press', [_set(w: 60, r: 8, dur: 30, km: 2)]);
      final bench = _row('Bench Press');
      expect(_sets(bench).single['duration_sec'], isNull);
      expect(_sets(bench).single.containsKey('distance_km'), isFalse);
      expect(bench.containsKey('distance_km'), isFalse);
      expect(_sets(bench).single['reps'], 8);

      await _log('Plank', [_set(w: 20, r: 3, dur: 45, km: 1)]);
      final plank = _row('Plank');
      final s = _sets(plank).single;
      expect(s['duration_sec'], 45);
      expect(s['weight_kg'], 0);
      expect(s['reps'], 0);
      expect(s.containsKey('distance_km'), isFalse);
    });

    test('T4: Farmers Carry (distance) reads metres under 1 km (OI-380)',
        () async {
      await _log('Farmers Carry', [_set(w: 40, km: 0.04)]);
      expect(exerciseLogDetail(_row('Farmers Carry')),
          '1${_nb}set${_sep}40${_nb}m${_sep}40.0${_nb}kg');

      final d2 = _day.add(const Duration(days: 1));
      await _log('Farmers Carry', [_set(w: 40, km: 1.2)], date: d2);
      expect(exerciseLogDetail(_row('Farmers Carry', date: d2)),
          '1${_nb}set${_sep}1.2${_nb}km${_sep}40.0${_nb}kg');
    });

    test('T4b: cardio with no km reads "30 min" everywhere, no km key',
        () async {
      await _log('Running (Treadmill)', [_set(dur: 1800)]);
      final row = _row('Running (Treadmill)');
      expect(row.containsKey('distance_km'), isFalse,
          reason: 'no km → the cloud keeps NULL, never 0');
      expect(exerciseLogDetail(row), '30${_nb}min');
      // The preview fallback and the chips share the one rule (plain space).
      expect(
          cardioDistanceDetail(
              loggingType: 'cardio',
              sets: 1,
              durationSec: 1800,
              km: 0,
              reps: 0,
              weightKg: 0),
          '30 min');

      // Restore-shaped (top-level only) through the receipt builder.
      final restored = DateTime(2026, 10, 10);
      await HiveService.instance.workoutBox.put('exlog_2026-10-10_aaaa0001', {
        'exercise_name': 'Running (Treadmill)',
        'date': '2026-10-10',
        'logging_type': 'cardio',
        'set_number': 1,
        'duration_seconds': 1800,
      });
      final receipt = WorkoutReceiptData.fromExerciseLogs(restored)!;
      final ex = receipt.exercises.single;
      expect(WorkoutReceiptCard.exerciseDetail(ex), '30 min',
          reason: 'the receipt fallback never prints "0.0 km"');
    });

    test('T23: the reps rule keeps the figures a coach route gave', () async {
      await _log('Farmers Carry',
          [for (var i = 0; i < 4; i++) _set(w: 40, r: 40, at: i)]);
      final carry = _row('Farmers Carry');
      expect(_sets(carry).every((s) => s['reps'] == 40 && s['weight_kg'] == 40),
          isTrue);
      expect(exerciseLogDetail(carry),
          '4${_nb}sets${_sep}40${_nb}reps${_sep}40.0${_nb}kg');

      await _log('Sled Push', [for (var i = 0; i < 3; i++) _set(w: 100, r: 20, at: i)]);
      expect(exerciseLogDetail(_row('Sled Push')),
          '3${_nb}sets${_sep}20${_nb}reps${_sep}100.0${_nb}kg',
          reason: 'a reps-rule cardio row leads with its set count');

      final d2 = _day.add(const Duration(days: 1));
      await _log('Sled Push', [_set(w: 100, r: 3, dur: 30)], date: d2);
      final timedish = _sets(_row('Sled Push', date: d2)).single;
      expect(timedish['weight_kg'], 100);
      expect(timedish['duration_sec'], 30);
      expect(timedish['reps'], 0);

      final d3 = _day.add(const Duration(days: 2));
      await _log('Farmers Carry', [_set(r: 10, dur: 120)], date: d3);
      expect(_sets(_row('Farmers Carry', date: d3)).single['reps'], 10);
      expect(_sets(_row('Farmers Carry', date: d3)).single['duration_sec'], 120);
      await _log('Farmers Carry', [_set(r: 10, km: 0.5, at: 200000)], date: d3);
      final both = _sets(_row('Farmers Carry', date: d3));
      expect(both[0]['reps'], 10, reason: 'the km-less set keeps its reps');
      expect(both[1]['reps'], 0, reason: 'the km set clears its reps');
    });

    test('T24: dedup sees both sides normalised (phantom on the stored set)',
        () async {
      // A stored weight set carrying a phantom duration, written straight
      // into Hive (no writer would produce it today).
      await HiveService.instance.workoutBox
          .put(WorkoutWriteService.exlogKey(_day, 'Bench Press'), {
        'exercise_name': 'Bench Press',
        'date': '2026-10-20',
        'logging_type': 'weight_reps',
        'set_number': 1,
        'sets': [
          {'weight_kg': 60.0, 'reps': 8, 'duration_sec': 30, 'logged_at_ms': _t0},
        ],
      });
      await _log('Bench Press', [_set(w: 60, r: 8, at: 20000)]);
      expect(_row('Bench Press')['set_number'], 1,
          reason: 'the re-send is the same set once the phantom is gone');
    });

    test('T28b / T28c: hint and stored type keep a custom row cardio; the '
        'library wins over both', () async {
      await _log('Cardio', [_set(dur: 1800, km: 3, w: 20, r: 30)],
          hint: 'cardio');
      var row = _row('Cardio');
      expect(row['logging_type'], 'cardio');
      expect(_sets(row).single['duration_sec'], 1800);
      expect(row['distance_km'], 3.0);

      // Same-day chat-card log with no hint: the stored type holds.
      await _log('Cardio', [_set(dur: 600, at: 300000)]);
      row = _row('Cardio');
      expect(row['logging_type'], 'cardio');
      expect(row['distance_km'], 3.0);
      expect(WorkoutReadService.aggregateDurationSeconds(row), 2400);

      // A coach logSet weight × reps for the same name.
      await _log('Cardio', [_set(w: 50, r: 10, at: 400000)]);
      row = _row('Cardio');
      expect(row['logging_type'], 'cardio');
      expect(row['distance_km'], 3.0);
      expect(WorkoutReadService.aggregateDurationSeconds(row), 2400);

      await _log('Plank', [_set(dur: 60)], hint: 'cardio');
      expect(_row('Plank')['logging_type'], 'timed');
    });
  });

  group('bounds (OI-382)', () {
    test('T18: logExercise refuses out-of-range duration and km', () async {
      Future<String?> code(ExerciseSet s) async =>
          (await _log('Rowing Machine', [s])).code;
      expect(await code(_set(dur: -1)), 'duration_out_of_range');
      expect(await code(_set(dur: 21601)), 'duration_out_of_range');
      expect(await code(_set(dur: 600, km: -0.1)), 'distance_out_of_range');
      expect(await code(_set(dur: 600, km: 301)), 'distance_out_of_range');
      expect(
          HiveService.instance.workoutBox
              .get(WorkoutWriteService.exlogKey(_day, 'Rowing Machine')),
          isNull);
    });

    test('T18: editLog bounds per set; totals beside them are not bounded',
        () async {
      await _log('Rowing Machine', [_set(dur: 600, km: 2, at: 0), _set(dur: 600, km: 2, at: 1)]);
      final key = WorkoutWriteService.exlogKey(_day, 'Rowing Machine');

      final over = await _w.editLog(logKey: key, updates: {
        'sets': [
          {'weight_kg': 0, 'reps': 0, 'duration_sec': 600, 'distance_km': 301},
        ],
      }, source: WriteSource.editSheet);
      expect(over.code, 'distance_out_of_range');

      final twoLong = await _w.editLog(logKey: key, updates: {
        'duration_seconds': 25200,
        'sets_detail': [
          {'set_number': 1, 'duration_seconds': 12600},
          {'set_number': 2, 'duration_seconds': 12600},
        ],
      }, source: WriteSource.editSheet);
      expect(twoLong.success, isTrue, reason: '2 × 210 min saves');

      final twoFar = await _w.editLog(logKey: key, updates: {
        'distance_km': 400,
        'sets_detail': [
          {'set_number': 1, 'distance_km': 200},
          {'set_number': 2, 'distance_km': 200},
        ],
      }, source: WriteSource.editSheet);
      expect(twoFar.success, isTrue);
      expect(_row('Rowing Machine')['distance_km'], 400.0);
    });

    test('T18 / T8: a value arriving through sets_detail is bounded', () async {
      await _log('Rowing Machine', [_set(dur: 600, km: 2)]);
      final r = await _w.editLog(
          logKey: WorkoutWriteService.exlogKey(_day, 'Rowing Machine'),
          updates: {
            'sets_detail': [
              {'set_number': 1, 'duration_seconds': 600, 'distance_km': 301},
            ],
          },
          source: WriteSource.editSheet);
      expect(r.code, 'distance_out_of_range');
      expect(_sets(_row('Rowing Machine')).single['distance_km'], 2.0);
    });

    test('T18: the legacy top-level path is bounded × the set count',
        () async {
      Future<WriteResult> legacy(int setNumber, double km) async {
        final key = 'exlog_2026-10-11_legacy$setNumber';
        await HiveService.instance.workoutBox.put(key, {
          'exercise_name': 'Rowing Machine',
          'date': '2026-10-11',
          'logging_type': 'cardio',
          'set_number': setNumber,
          'duration_seconds': 600,
        });
        return _w.editLog(
            logKey: key,
            updates: {'distance_km': km},
            source: WriteSource.editSheet);
      }

      expect((await legacy(1, 301)).code, 'distance_out_of_range');
      expect((await legacy(3, 500)).success, isTrue);
    });

    test('T18 UI leg: validateSetInputs blocks LOG past each max', () {
      SetValidation v(String type, {String d = '', String km = ''}) =>
          validateSetInputs(
              loggingType: type, durationText: d, distanceText: km);
      final min = v('cardio', d: '361');
      expect(min.kind, SetFailureKind.outOfRange);
      expect(min.message, kSetMinutesMaxMessage);
      final sec = v('timed', d: '21601');
      expect(sec.kind, SetFailureKind.outOfRange);
      expect(sec.message, kSetSecondsMaxMessage);
      final km = v('cardio', d: '30', km: '301');
      expect(km.field, SetField.distance);
      expect(km.message, kSetKmMaxMessage);
      expect(v('distance', km: '301').message, kSetKmMaxMessage);
      expect(blockedLogLabel(min), WardroomCopy.activeBlockedFixTime);
    });
  });

  group('D2: decimal minutes at capture', () {
    test('T32: validator and conversion', () {
      SetValidation v(String d) =>
          validateSetInputs(loggingType: 'cardio', durationText: d);
      expect(v('12.5').isOk, isTrue);
      expect(cardioMinutesToSeconds('12.5'), 750);
      expect(v('1.2.3').kind, SetFailureKind.outOfRange);
      final tiny = v('0.001');
      expect(tiny.kind, SetFailureKind.outOfRange);
      expect(tiny.message, kSetMinimumSecondMessage);
      expect(v('12.').isOk, isTrue);
      expect(cardioMinutesToSeconds('12.'), 720);
      expect(cardioMinutesToSeconds('1.01'), 61,
          reason: 'rounded, not truncated (60.6 s → 61)');
      expect(v('0.0').kind, SetFailureKind.empty);
      expect(v('0').kind, SetFailureKind.empty);
      for (final secs in [750, 735, 30, 45, 1800, 61, 737]) {
        expect(cardioMinutesToSeconds(secondsToMinutesInput(secs)), secs,
            reason: 'the 2-decimal prefill round-trips $secs s exactly');
      }
      expect(secondsToMinutesInput(750), '12.5');
      expect(secondsToMinutesInput(735), '12.25');
      expect(secondsToMinutesInput(30), '0.5');
      expect(secondsToMinutesInput(1800), '30');
    });

    test('T32: a 750 s PR reads 12.5 min (one token before the unit)', () {
      final pr = ExercisePR(
          exerciseName: 'Rowing Machine',
          loggingType: 'cardio',
          bestValue: 750,
          date: _day,
          unit: 'sec');
      expect(pr.formattedValue, '12.5 min');
      expect(pr.formattedValue.split(' '), ['12.5', 'min']);
    });
  });

  group('exerciseSetFromInput + liveVolumeKg (U5)', () {
    test('T29: a cardio set with a hidden reps prefill carries no volume; a '
        'distance set keeps its duration; 0 km is absent', () {
      const v = SetInputValues(weight: 20, reps: 30, durationSeconds: 1800);
      final s = exerciseSetFromInput(v, 'cardio', 0);
      expect(s.reps, 0);
      expect(s.durationSec, 1800);
      final data = ActiveWorkoutData(
        exercises: const [
          ExerciseData(name: 'Rowing Machine', sets: '1', loggingType: 'cardio'),
        ],
        checkedSets: const {'0-0': true},
        setInputValues: const {'0-0': v},
      );
      expect(data.liveVolumeKg, 0);

      final carry = exerciseSetFromInput(
          const SetInputValues(weight: 40, durationSeconds: 120, distanceKm: 0.5),
          'distance',
          0);
      expect(carry.durationSec, 120);
      expect(carry.distanceKm, 0.5);

      final zero = exerciseSetFromInput(
          const SetInputValues(durationSeconds: 600, distanceKm: 0),
          'cardio',
          0);
      expect(zero.distanceKm, isNull);
      expect(zero.toMap().containsKey('distance_km'), isFalse);
    });

    test('T6: the receipt from the active workout reads minutes and km, and '
        'its volume equals the stored row', () async {
      const v = SetInputValues(durationSeconds: 1800, distanceKm: 4);
      final data = ActiveWorkoutData(
        exercises: const [
          ExerciseData(
              name: 'Running (Treadmill)', sets: '1', loggingType: 'cardio'),
        ],
        checkedSets: const {'0-0': true},
        setInputValues: const {'0-0': v},
      );
      final receipt = WorkoutReceiptData.fromActiveWorkout(data);
      final ex = receipt.exercises.single;
      expect(ex.perSetBreakdown.single.distanceKm, 4.0);
      expect(WorkoutReceiptCard.exerciseDetail(ex), '30 min · 4.0 km');

      await _log('Running (Treadmill)', [exerciseSetFromInput(v, 'cardio', _t0)]);
      expect(receipt.totalVolumeKg,
          (_row('Running (Treadmill)')['volume_kg'] as num).toDouble());
      final fromLogs = WorkoutReceiptData.fromExerciseLogs(_day)!;
      expect(WorkoutReceiptCard.exerciseDetail(fromLogs.exercises.single),
          '30 min · 4.0 km');
    });
  });

  group('readers', () {
    test('T9: aggregateDistanceKm — per-set first, then the top level',
        () {
      final restored = <String, dynamic>{
        'logging_type': 'cardio',
        'set_number': 1,
        'duration_seconds': 600,
        'distance_km': 5.0,
      };
      expect(WorkoutReadService.perSetList(restored), isEmpty,
          reason: 'precondition: no per-set list');
      expect(WorkoutReadService.aggregateDistanceKm(restored), 5.0);

      expect(
          WorkoutReadService.aggregateDistanceKm({
            'sets': <Map>[],
            'sets_detail': [
              {'distance_km': 1.5},
              {'distance_km': 2.0},
            ],
          }),
          3.5);
      expect(
          WorkoutReadService.aggregateDistanceKm({
            'distance_km': 5.0,
            'sets': [
              {'duration_sec': 600},
            ],
          }),
          5.0,
          reason: 'F5 shape: sets without km beside a top-level total');
      expect(
          WorkoutReadService.aggregateDistanceKm({
            'sets': [
              {'distance_km': 0.1},
              {'distance_km': 0.2},
            ],
          }),
          0.3);
    });

    test('T25: formatters', () {
      expect(formatDistance(0.9994), '999 m');
      expect(formatDistance(0.9996), '1.0 km');
      expect(formatSetDuration(1800), '30 min');
      expect(formatSetDuration(1830), '30.5 min');
      expect(formatSetDuration(750), '12.5 min');
      expect(formatSetDuration(735), '12.3 min');
      expect(formatSetDuration(3597), '60 min');
      expect(formatSetDuration(45), '45s');
      expect(formatSetDuration(1800, space: _nb), '30${_nb}min');
      expect(formatDistance(0.04, space: _nb), '40${_nb}m');
      String d(String type) => cardioDistanceDetail(
          loggingType: type,
          sets: 1,
          durationSec: 0,
          km: 0,
          reps: 0,
          weightKg: 0);
      expect(d('cardio'), '—');
      // B-pass F5: a km that rounds to 0 m is omitted.
      expect(
          cardioDistanceDetail(
              loggingType: 'cardio',
              sets: 1,
              durationSec: 600,
              km: 0.0004,
              reps: 0,
              weightKg: 0),
          '10 min');
      expect(d('distance'), '1 set');
    });

    test('T26: the week selector line for a cardio row with per-set km only',
        () {
      expect(
          weekExerciseLineDetail({
            'logging_type': 'cardio',
            'set_number': 1,
            'sets': [
              {'duration_sec': 1830, 'distance_km': 0.04},
            ],
          }),
          '1 set · 30.5 min · 40 m');
      expect(
          weekExerciseLineDetail({
            'logging_type': 'timed',
            'set_number': 1,
            'sets': [
              {'duration_sec': 45},
            ],
          }),
          '1 set · 1 min',
          reason: 'timed keeps its old minute expression');
    });

    test('T16a: a 5 km log then a duration-only 1800 s log → PR 5.0 km',
        () async {
      await _log('Rowing Machine', [_set(dur: 1200, km: 5.0)]);
      await _log('Rowing Machine', [_set(dur: 1800)],
          date: _day.add(const Duration(days: 1)));
      final pr = WorkoutRepository.instance
          .loadAllExercisePRs()
          .singleWhere((p) => p.exerciseName == 'Rowing Machine');
      expect(pr.unit, 'km');
      expect(pr.formattedValue, '5.0 km');
    });

    test('T16a / T16b: a duration-only cardio PR is in seconds, never km',
        () async {
      await _log('Running (Treadmill)', [_set(dur: 1800)]);
      final pr = WorkoutRepository.instance
          .loadAllExercisePRs()
          .singleWhere((p) => p.exerciseName == 'Running (Treadmill)');
      expect(pr.unit, 'sec');
      expect(pr.formattedValue, '30 min');
    });

    test('T29: a 0.04 km distance PR reads 40 m', () async {
      await _log('Farmers Carry', [_set(w: 40, km: 0.04)]);
      final pr = WorkoutRepository.instance
          .loadAllExercisePRs()
          .singleWhere((p) => p.exerciseName == 'Farmers Carry');
      expect(pr.formattedValue, '40 m');
    });

    test('T16c: graduation top-3 puts 100 kg before an 1800 s cardio PR', () {
      final top = graduationTopPrs([
        ExercisePR(
            exerciseName: 'Running (Treadmill)',
            loggingType: 'cardio',
            bestValue: 1800,
            date: _day,
            unit: 'sec'),
        ExercisePR(
            exerciseName: 'Bench Press',
            loggingType: 'weight_reps',
            bestValue: 100,
            date: _day.subtract(const Duration(days: 9))),
      ]);
      expect(top.first.exerciseName, 'Bench Press');
      expect(top.first.value, '100 kg');
      expect(top[1].value, '30 min');
    });
  });

  group('heal and repair keep cardio (U8, W16)', () {
    test('T10: healedExlog keeps cardio duration + km and every untouched key',
        () {
      final log = <String, dynamic>{
        'logging_type': 'timed',
        'sets': <Map<String, dynamic>>[
          {'set_number': 1, 'duration_seconds': 1200, 'distance_km': 5.0},
        ],
      };
      AuthSessionBootstrapper.healedExlog(log, 'cardio');
      final s = (log['sets'] as List).single as Map;
      expect(log['logging_type'], 'cardio');
      expect(s['duration_seconds'], 1200);
      expect(s['distance_km'], 5.0);
      expect(s['set_number'], 1);
      expect(s.containsKey('duration_sec'), isFalse);
      expect(s.containsKey('logged_at_ms'), isFalse,
          reason: 'never rebuilt through ExerciseSet.toMap');

      final weight = <String, dynamic>{
        'logging_type': 'timed',
        'sets': <Map<String, dynamic>>[
          {'weight_kg': 60.0, 'reps': 8, 'duration_seconds': 45},
        ],
      };
      AuthSessionBootstrapper.healedExlog(weight, 'weight_reps');
      final w = (weight['sets'] as List).single as Map;
      expect(w['duration_sec'], 0);
      expect(w['duration_seconds'], 45);
      expect(w['reps'], 8);
    });

    test('T10b: a disk-shaped (Map<dynamic, dynamic>) row is byte-unchanged '
        '(today\'s footprint; OI-394 owns making the heal live)', () async {
      const key = 'exlog_2026-10-12_heal0001';
      final disk = <dynamic, dynamic>{
        'exercise_name': 'Rowing Machine',
        'date': '2026-10-12',
        'logging_type': 'timed',
        'sets': <dynamic>[
          <dynamic, dynamic>{'duration_sec': 1200, 'distance_km': 5.0},
        ],
      };
      await HiveService.instance.workoutBox.put(key, disk);
      final before = HiveService.instance.workoutBox.get(key).toString();
      await AuthSessionBootstrapper.instance.healMismatchedExerciseLogsForTest();
      expect(HiveService.instance.workoutBox.get(key).toString(), before);
    });

    test('T31: the v3 repair leaves a stored custom cardio row alone',
        () async {
      await _log('Cardio', [_set(dur: 1800)], hint: 'cardio');
      final before = _row('Cardio').toString();
      await LoggingTypeRepairMigrator.runIfNeeded();
      expect(LoggingTypeRepairMigrator.hasRun(), isTrue);
      final row = _row('Cardio');
      expect(row['logging_type'], 'cardio');
      expect(row.toString(), before);
    });
  });

  group('editLog keeps km (U3)', () {
    test('T8: a per-set km edit survives; an F5 total survives an unrelated '
        'edit; clearing every km clears the total', () async {
      await _log('Rowing Machine', [_set(dur: 1200, km: 5.0)]);
      final key = WorkoutWriteService.exlogKey(_day, 'Rowing Machine');
      await _w.editLog(logKey: key, updates: {
        'sets_detail': [
          {'set_number': 1, 'duration_seconds': 1200, 'distance_km': 6.0},
        ],
        'distance_km': 6.0,
      }, source: WriteSource.editSheet);
      expect(_sets(_row('Rowing Machine')).single['distance_km'], 6.0);
      expect(_row('Rowing Machine')['distance_km'], 6.0);

      // F5: sets lack km beside a top-level 4 km.
      const f5 = 'exlog_2026-10-13_f5000001';
      await HiveService.instance.workoutBox.put(f5, {
        'exercise_name': 'Rowing Machine',
        'date': '2026-10-13',
        'logging_type': 'cardio',
        'distance_km': 4.0,
        'sets': [
          {'weight_kg': 0, 'reps': 0, 'duration_sec': 600},
        ],
      });
      await _w.editLog(logKey: f5, updates: {
        'sets_detail': [
          {'set_number': 1, 'duration_seconds': 660},
        ],
      }, source: WriteSource.editSheet);
      final f5Row = Map<String, dynamic>.from(
          HiveService.instance.workoutBox.get(f5) as Map);
      expect(f5Row['distance_km'], 4.0);

      await _w.editLog(logKey: key, updates: {
        'sets_detail': [
          {'set_number': 1, 'duration_seconds': 1200},
        ],
        'distance_km': null,
      }, source: WriteSource.editSheet);
      expect(_row('Rowing Machine')['distance_km'], isNull);
      expect(WorkoutReadService.aggregateDistanceKm(_row('Rowing Machine')), 0);
    });
  });

  group('move merge (W15)', () {
    final from = DateTime(2026, 10, 14);
    final to = DateTime(2026, 10, 15);

    Future<Map<String, dynamic>> merge(
        Map<String, dynamic> dest, Map<String, dynamic> moved) async {
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.exlogKey(to, 'Rowing Machine'),
          {'exercise_name': 'Rowing Machine', 'date': '2026-10-15', ...dest});
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.exlogKey(from, 'Rowing Machine'),
          {'exercise_name': 'Rowing Machine', 'date': '2026-10-14', ...moved});
      await _w.moveExerciseLogs(fromDate: '2026-10-14', toDate: '2026-10-15');
      return _row('Rowing Machine', date: to);
    }

    const restored5 = {
      'logging_type': 'cardio',
      'set_number': 1,
      'duration_seconds': 600,
      'distance_km': 5.0,
    };
    Map<String, dynamic> perSet(double? km) => {
          'logging_type': 'cardio',
          'set_number': 1,
          if (km != null) 'distance_km': km,
          'sets': [
            {'duration_sec': 600, 'distance_km': ?km},
          ],
        };

    test('T19 (a) both restore-shaped: 8.0', () async {
      final m = await merge(restored5, {...restored5, 'distance_km': 3.0});
      expect(WorkoutReadService.aggregateDistanceKm(m), 8.0);
      expect(m['distance_km'], 8.0);
    });
    test('T19 (b) both per-set: 5.0', () async {
      final m = await merge(perSet(2), perSet(3));
      expect(WorkoutReadService.aggregateDistanceKm(m), 5.0);
      expect(m['distance_km'], 5.0);
    });
    test('T19 (c) neither side has km: no key', () async {
      final m = await merge(perSet(null), perSet(null));
      expect(m.containsKey('distance_km'), isFalse);
    });
    test('T19 (d) mixed (OI-393 limit, pinned): 3.0 on both', () async {
      final m = await merge(restored5, perSet(3));
      expect(WorkoutReadService.aggregateDistanceKm(m), 3.0);
      expect(m['distance_km'], 3.0);
    });
    test('T19 (e) restore-shaped 5 km + a per-set side with no km: 5.0',
        () async {
      final m = await merge(restored5, perSet(null));
      expect(WorkoutReadService.aggregateDistanceKm(m), 5.0);
      expect(m['distance_km'], 5.0);
    });
    test('T19 (f) a sheet-edited destination loses its stale sets_detail',
        () async {
      final m = await merge({
        ...perSet(2),
        'sets_detail': [
          {'set_number': 1, 'duration_seconds': 600, 'distance_km': 2.0},
        ],
      }, perSet(1));
      expect(m.containsKey('sets_detail'), isFalse);
      expect((m['sets'] as List).length, 2);
      expect(WorkoutReadService.aggregateDistanceKm(m), 3.0);
    });
    test('T19 (g) a sets_detail-only destination is merged, not dropped',
        () async {
      final m = await merge({
        'logging_type': 'cardio',
        'set_number': 3,
        'sets_detail': [
          for (var i = 0; i < 3; i++)
            {'set_number': i + 1, 'duration_seconds': 300, 'distance_km': 2 / 3},
        ],
      }, perSet(1));
      expect((m['sets'] as List).length, 4);
      expect(WorkoutReadService.aggregateDistanceKm(m), 3.0);
      expect(m['distance_km'], 3.0);
    });
  });

  group('copy (U7)', () {
    test('T20: release failure copy never shows the raw code', () {
      expect(toFailureCopy('db_down', raw: 'PGRST002', debug: false),
          kNotSavedGeneric);
      expect(toFailureCopy('distance_out_of_range', debug: false),
          kNotSavedDistance);
      expect(toFailureCopy('duration_out_of_range', loggingType: 'timed'),
          kNotSavedDurationTimed);
      expect(toFailureCopy(kMinutesFormatCode), kNotSavedMinutesFormat);
    });

    test('T30: the partial line names only the failed exercises', () {
      expect(
          partialSaveCopy(['Rowing Machine'],
              firstCode: 'duration_out_of_range'),
          'Partly saved. Not saved: Rowing Machine. A set can be up to 360 min.');
    });
  });

  group('edit sheet update map (T8, editSheetUpdatesFor)', () {
    Map<String, dynamic> cardioRow(List<Map<String, dynamic>> sets,
            {String type = 'cardio', double? topKm}) =>
        {
          'exercise_name': 'Rowing Machine',
          'date': '2026-10-20',
          'logging_type': type,
          'set_number': sets.length,
          'distance_km': ?topKm,
          'sets': sets,
        };
    EditLogExerciseRow rowOf(Map<String, dynamic> log) =>
        EditLogExerciseRow.fromLog('k', log);
    List<Map> detail(EditLogExerciseRow r) =>
        (editSheetUpdatesFor(r).updates['sets_detail'] as List).cast<Map>();

    test('prefill is decimal minutes and an unchanged save keeps the seconds',
        () {
      for (final (secs, text) in [
        (1800, '30'),
        (750, '12.5'),
        (735, '12.25'),
        (45, '0.75'),
        (30, '0.5'),
      ]) {
        final r = rowOf(cardioRow([
          {'duration_sec': secs},
        ]));
        expect(r.setRows.single.durationCtrl.text, text);
        expect(detail(r).single['duration_seconds'], secs,
            reason: '$secs s round-trips through "$text"');
      }
    });

    test('"13.5" typed into a 750 s row saves 810 s; "12.5." is refused', () {
      final r = rowOf(cardioRow([
        {'duration_sec': 750},
      ]));
      r.setRows.single.durationCtrl.text = '13.5';
      expect(detail(r).single['duration_seconds'], 810);
      r.setRows.single.durationCtrl.text = '12.5.';
      expect(editSheetUpdatesFor(r).errorCode, kMinutesFormatCode);
    });

    test('a distance set keeps its 120 s (hidden box in seconds); a cardio '
        'set with no duration writes no duration key', () {
      final carry = rowOf(cardioRow([
        {'duration_sec': 120, 'distance_km': 0.5, 'weight_kg': 40.0},
      ], type: 'distance'));
      expect(carry.setRows.single.durationCtrl.text, '120');
      final noDur = rowOf(cardioRow([
        {'distance_km': 2.0},
      ]));
      expect(noDur.setRows.single.durationCtrl.text, '');
      expect(detail(noDur).single.containsKey('duration_seconds'), isFalse);
    });

    test('legacy path: MIN in and out (×60), km kept', () {
      final r = rowOf({
        'exercise_name': 'Rowing Machine',
        'date': '2026-10-10',
        'logging_type': 'cardio',
        'set_number': 1,
        'duration_seconds': 600,
        'distance_km': 5.0,
      });
      expect(r.hasPerSetData, isFalse);
      expect(r.durationCtrl.text, '10');
      expect(r.distanceCtrl.text, '5');
      final u = editSheetUpdatesFor(r).updates;
      expect(u['duration_seconds'], 600);
      expect(u['distance_km'], 5.0);

      r.distanceCtrl.text = '';
      final cleared = editSheetUpdatesFor(r).updates;
      expect(cleared.containsKey('distance_km'), isTrue);
      expect(cleared['distance_km'], isNull,
          reason: 'a prefilled km box emptied clears the total');

      final none = rowOf({
        'exercise_name': 'Rowing Machine',
        'date': '2026-10-10',
        'logging_type': 'cardio',
        'set_number': 1,
        'duration_seconds': 600,
      });
      expect(editSheetUpdatesFor(none).updates.containsKey('distance_km'),
          isFalse,
          reason: 'blank on a row that never had km: left out');
    });

    test('F5: a reps edit on sets without km beside a top-level 4 km keeps '
        'the 4 km through editLog; clearing every per-set km sends null',
        () async {
      const key = 'exlog_2026-10-13_f5000002';
      final log = cardioRow([
        {'duration_sec': 600, 'reps': 3},
      ], topKm: 4.0);
      await HiveService.instance.workoutBox.put(key, log);
      final r = rowOf(log);
      r.setRows.single.repsCtrl.text = '4';
      final u = editSheetUpdatesFor(r).updates;
      expect(u.containsKey('distance_km'), isFalse);
      await _w.editLog(logKey: key, updates: u, source: WriteSource.editSheet);
      expect(
          (HiveService.instance.workoutBox.get(key) as Map)['distance_km'], 4.0);

      final withKm = rowOf(cardioRow([
        {'duration_sec': 600, 'distance_km': 2.0},
      ]));
      withKm.setRows.single.distanceCtrl.text = '';
      final cu = editSheetUpdatesFor(withKm).updates;
      expect(cu.containsKey('distance_km'), isTrue);
      expect(cu['distance_km'], isNull);
    });
  });
}
