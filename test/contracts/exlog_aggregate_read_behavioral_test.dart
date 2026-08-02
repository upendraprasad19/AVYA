// Behavioral contract test — Unit 7 / OI-50
//
// THE SHAPE UNDER TEST is the one the CLOUD-RESTORE writer produces, which
// no client-side writer can reproduce:
//   lib/core/services/sync/sync_workout.dart:733-767
//     - stamps `set_number`               (:762-763) and NEVER `sets_completed`
//     - stamps top-level `duration_seconds` (:765-766)
//     - stamps `sets[]` ONLY when the `workout_log_sets` join came back
//       non-empty (:777) — an empty join (fetch failure at ~:704, a
//       `workoutLogId|exerciseId` group-key miss at :773-776, or old cloud
//       data with summary rows but no per-set rows) leaves it absent.
//
// Readers under test:
//   - WorkoutReadService.aggregateSetCount / aggregateDurationSeconds
//       (the ONE shared helper both surfaces now delegate to)
//   - WorkoutReceiptData.fromExerciseLogs   (workout_receipt_card.dart)
//   - EditLogExerciseRow.fromLog            (edit_workout_log_sheet.dart)
//
// NEGATIVE CONTROLS — each behavioral test below was run against the
// pre-fix readers and observed to FAIL (recorded in the diagnose-doc):
//   * receipt duration     → 0    (`const int duration = 0` discarded the
//                                  top-level aggregate)
//   * edit-sheet sets box  → ''   (read only the legacy `sets_completed`)
//   * edit-sheet duration  → ''   (`bestPerSetDuration` gates its top-level
//                                  fallback on setCount <= 1)

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/features/train/widgets/edit_workout_log_sheet.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

/// An `exlog_*` row exactly as `sync_workout.dart` writes it when the
/// per-set join came back empty: `set_number` + top-level
/// `duration_seconds`, and NO `sets` / `sets_detail`.
Map<String, dynamic> restoredExlogRow({
  required String dateKey,
  String name = 'Plank',
  int setNumber = 3,
  int durationSeconds = 300,
  String loggingType = 'timed',
}) =>
    <String, dynamic>{
      'id': 'exlog_restored',
      'type': 'exercise_log',
      'exercise_name': name,
      'date': dateKey,
      'logging_type': loggingType,
      'is_pr': false,
      'set_number': setNumber,
      'duration_seconds': durationSeconds,
      // deliberately NO 'sets' and NO 'sets_detail' — that is the bug shape
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────
  //  A · Pure helper semantics (no Hive)
  // ───────────────────────────────────────────────────────────
  group('A · WorkoutReadService aggregate helpers', () {
    test('aggregateSetCount reads the canonical `set_number`', () {
      expect(
        WorkoutReadService.aggregateSetCount({'set_number': 4}),
        4,
      );
    });

    test('aggregateSetCount reads the legacy `sets_completed`', () {
      expect(
        WorkoutReadService.aggregateSetCount({'sets_completed': 5}),
        5,
      );
    });

    test(
      'aggregateSetCount takes the MAX — APK Test #12.2: both count keys 0 '
      'while the per-set array is populated',
      () {
        final log = <String, dynamic>{
          'set_number': 0,
          'sets_completed': 0,
          'sets': [
            {'reps': 8},
            {'reps': 8},
            {'reps': 8},
            {'reps': 8},
          ],
        };
        expect(WorkoutReadService.aggregateSetCount(log), 4,
            reason: 'array length must win over two zeroed count keys');
      },
    );

    test('aggregateSetCount counts the legacy `sets_detail` array too', () {
      expect(
        WorkoutReadService.aggregateSetCount({
          'sets_detail': [
            {'reps': 1},
            {'reps': 1},
          ],
        }),
        2,
      );
    });

    test('hasAggregateSetCount distinguishes explicit 0 from absent', () {
      expect(WorkoutReadService.hasAggregateSetCount({'set_number': 0}), isTrue,
          reason: 'a logged zero IS a signal');
      expect(
          WorkoutReadService.hasAggregateSetCount({'sets_completed': 0}), isTrue);
      expect(
        WorkoutReadService.hasAggregateSetCount(
            {'exercise_name': 'Squat', 'reps_completed': 10}),
        isFalse,
        reason: 'no count key and no per-set array → no signal at all',
      );
    });

    test('aggregateDurationSeconds prefers the per-set SUM', () {
      final log = <String, dynamic>{
        'duration_seconds': 999, // must NOT win
        'sets': [
          {'duration_sec': 30},
          {'duration_sec': 45},
        ],
      };
      expect(WorkoutReadService.aggregateDurationSeconds(log), 75);
    });

    test('aggregateDurationSeconds reads the restore per-set alias', () {
      final log = <String, dynamic>{
        'sets': [
          {'duration_seconds': 20},
          {'duration_seconds': 25},
        ],
      };
      expect(WorkoutReadService.aggregateDurationSeconds(log), 45);
    });

    test(
      'aggregateDurationSeconds falls back to the top-level aggregate when '
      'there is no per-set array — THE OI-50 CASE',
      () {
        expect(
          WorkoutReadService.aggregateDurationSeconds(
              {'set_number': 3, 'duration_seconds': 300}),
          300,
        );
      },
    );

    test(
      'aggregateDurationSeconds falls back when per-set rows carry no '
      'duration but the summary row does',
      () {
        final log = <String, dynamic>{
          'duration_seconds': 300,
          'sets': [
            {'reps': 0},
            {'reps': 0},
          ],
        };
        expect(WorkoutReadService.aggregateDurationSeconds(log), 300,
            reason: 'a per-set sum of 0 is not a real duration signal');
      },
    );

    test(
      'an EMPTY canonical `sets` does not mask a populated legacy '
      '`sets_detail` — round-1 F3',
      () {
        // `log['sets'] ?? log['sets_detail']` is null-coalescing, so a row
        // carrying BOTH (canonical empty, legacy populated) would resolve to
        // the empty list and silently lose the legacy array. The receipt's
        // pre-Unit-7 code measured both lengths and MAXed them.
        final log = <String, dynamic>{
          'sets': <Map<String, dynamic>>[],
          'sets_detail': [
            {'reps': 5, 'duration_seconds': 20},
            {'reps': 5, 'duration_seconds': 25},
            {'reps': 5, 'duration_seconds': 15},
          ],
        };
        expect(WorkoutReadService.aggregateSetCount(log), 3,
            reason: 'must not collapse to the empty canonical array');
        expect(WorkoutReadService.aggregateDurationSeconds(log), 60,
            reason: 'the legacy array must still be summed');
        expect(WorkoutReadService.hasAggregateSetCount(log), isTrue);
      },
    );

    test('aggregateDurationSeconds returns null when there is no signal', () {
      expect(
        WorkoutReadService.aggregateDurationSeconds(
            {'set_number': 3, 'reps_completed': 30}),
        isNull,
        reason: 'null lets the caller render nothing instead of a fake 0',
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  //  B · Receipt reads a restored row (Hive)
  // ───────────────────────────────────────────────────────────
  group('B · WorkoutReceiptData.fromExerciseLogs — restored row', () {
    setUp(() async {
      await wwsTestSetup();
    });
    tearDown(() async {
      await wwsTestTeardown();
    });

    test(
      'renders the TRUE total duration for a restored timed row whose '
      'per-set join came back empty (pre-fix: 0)',
      () async {
        final date = DateTime(2026, 7, 4);
        final dateKey = formatDateKey(date);
        await HiveService.instance.workoutBox.put(
          'exlog_restored',
          restoredExlogRow(dateKey: dateKey),
        );

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);

        expect(receipt, isNotNull, reason: 'the row must be discoverable');
        final ex = receipt!.exercises.single;
        expect(ex.totalDurationSeconds, 300,
            reason: 'THE REGRESSION: `const duration = 0` rendered this as 0 '
                'while the row carried the real aggregate');
        expect(ex.sets, 3,
            reason: 'set_number must survive — the receipt already MAXed both '
                'count keys, and that behaviour must not regress');
      },
    );

    test(
      'per-set rows still win over the top-level aggregate (no regression '
      'of the 2026-05-24/T6 drift-fix intent)',
      () async {
        final date = DateTime(2026, 7, 5);
        final dateKey = formatDateKey(date);
        await HiveService.instance.workoutBox.put('exlog_persets', {
          'id': 'exlog_persets',
          'type': 'exercise_log',
          'exercise_name': 'Plank',
          'date': dateKey,
          'logging_type': 'timed',
          'set_number': 2,
          // A stale/wrong top-level aggregate that must NOT be preferred.
          'duration_seconds': 9999,
          'sets': [
            {'set_number': 1, 'duration_sec': 60},
            {'set_number': 2, 'duration_sec': 90},
          ],
        });

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);

        expect(receipt!.exercises.single.totalDurationSeconds, 150,
            reason: 'per-set SUM stays canonical');
      },
    );
  });

  // ───────────────────────────────────────────────────────────
  //  C · Edit sheet reads a restored row
  // ───────────────────────────────────────────────────────────
  group('C · EditLogExerciseRow.fromLog — restored row', () {
    test(
      'populates the SETS box from `set_number` (pre-fix: blank, because it '
      'read only the legacy `sets_completed`)',
      () {
        final row = EditLogExerciseRow.fromLog(
          'exlog_restored',
          restoredExlogRow(dateKey: '2026-07-04'),
        );

        expect(row.hasPerSetData, isFalse, reason: 'no per-set array');
        expect(row.setsCtrl.text, '3',
            reason: 'THE REGRESSION: every cloud-restored aggregate row '
                'rendered a blank sets box');
      },
    );

    test(
      'populates the DURATION box with the TOTAL (pre-fix: blank — '
      'bestPerSetDuration gates its fallback on setCount <= 1, so saving '
      'wiped the real total to 0)',
      () {
        final row = EditLogExerciseRow.fromLog(
          'exlog_restored',
          restoredExlogRow(dateKey: '2026-07-04'),
        );

        expect(row.durationCtrl.text, '300');
      },
    );

    test('hasAggregateData is true for a restored row', () {
      final row = EditLogExerciseRow.fromLog(
        'exlog_restored',
        restoredExlogRow(dateKey: '2026-07-04'),
      );
      expect(row.hasAggregateData, isTrue);
    });

    test(
      'hasAggregateData is false when the row carries NO count signal, so '
      'save can tell "unknown" from "zero"',
      () {
        final row = EditLogExerciseRow.fromLog('exlog_bare', {
          'id': 'exlog_bare',
          'exercise_name': 'Squat',
          'date': '2026-07-04',
          'logging_type': 'weight_reps',
          'reps_completed': 30,
          'weight_kg': 60.0,
        });

        expect(row.hasAggregateData, isFalse);
        expect(row.setsCtrl.text, '',
            reason: 'nothing known → empty box, not a fabricated 0');
      },
    );

    test('an explicitly-logged zero still counts as a signal', () {
      final row = EditLogExerciseRow.fromLog('exlog_zero', {
        'id': 'exlog_zero',
        'exercise_name': 'Squat',
        'date': '2026-07-04',
        'logging_type': 'weight_reps',
        'sets_completed': 0,
      });

      expect(row.hasAggregateData, isTrue,
          reason: 'a logged 0 must be preserved on save, not treated as a gap');
    });

    test(
      'hasAggregateDuration is true for a restored row and false when no '
      'duration exists anywhere — round-1 F5',
      () {
        final restored = EditLogExerciseRow.fromLog(
          'exlog_restored',
          restoredExlogRow(dateKey: '2026-07-04'),
        );
        expect(restored.hasAggregateDuration, isTrue,
            reason: 'top-level duration_seconds is the only surviving copy — '
                'save must not overwrite it with a computed 0');

        final noDuration = EditLogExerciseRow.fromLog('exlog_wr', {
          'id': 'exlog_wr',
          'exercise_name': 'Squat',
          'date': '2026-07-04',
          'logging_type': 'weight_reps',
          'set_number': 3,
          'reps_completed': 30,
        });
        expect(noDuration.hasAggregateDuration, isFalse);
      },
    );

    test(
      'a row with sets[] but NO per-set durations still reports a duration '
      'signal from the top-level aggregate — round-1 F5',
      () {
        final row = EditLogExerciseRow.fromLog('exlog_mixed', {
          'id': 'exlog_mixed',
          'exercise_name': 'Plank',
          'date': '2026-07-04',
          'logging_type': 'timed',
          'set_number': 2,
          'duration_seconds': 240,
          'sets': [
            {'set_number': 1, 'reps': 0},
            {'set_number': 2, 'reps': 0},
          ],
        });

        expect(row.hasPerSetData, isTrue, reason: 'sets[] is present');
        expect(row.hasAggregateDuration, isTrue,
            reason: 'the per-set rows carry no duration, so the top-level 240 '
                'is the only copy — the save guard keys off exactly this');
      },
    );

    test(
      'hadPerSetDuration separates "clearable" from "top-level is the only '
      'copy" — round-2, the un-clearable-duration fix',
      () {
        // BOTH per-set durations AND a top-level total (a restored row whose
        // workout_log_sets join WAS non-empty carries both). The user must be
        // able to clear the per-set boxes to zero; the save guard must stand
        // down, or `editLog`'s merge resurrects the stale total forever.
        final clearable = EditLogExerciseRow.fromLog('exlog_both', {
          'id': 'exlog_both',
          'exercise_name': 'Plank',
          'date': '2026-07-04',
          'logging_type': 'timed',
          'set_number': 2,
          'duration_seconds': 150,
          'sets': [
            {'set_number': 1, 'duration_seconds': 60},
            {'set_number': 2, 'duration_seconds': 90},
          ],
        });
        expect(clearable.hadPerSetDuration, isTrue,
            reason: 'per-set durations exist → a clear-to-zero is a real edit, '
                'so the guard must NOT fire');
        expect(clearable.hasAggregateDuration, isTrue);

        // sets[] present but carrying NO durations — here the top-level total
        // is the only surviving copy and the guard SHOULD fire.
        final protected = EditLogExerciseRow.fromLog('exlog_mixed2', {
          'id': 'exlog_mixed2',
          'exercise_name': 'Plank',
          'date': '2026-07-04',
          'logging_type': 'timed',
          'set_number': 2,
          'duration_seconds': 240,
          'sets': [
            {'set_number': 1, 'reps': 0},
            {'set_number': 2, 'reps': 0},
          ],
        });
        expect(protected.hadPerSetDuration, isFalse);
        expect(protected.hasAggregateDuration, isTrue);
      },
    );

    test('legacy `sets_completed`-only rows are unaffected', () {
      final row = EditLogExerciseRow.fromLog('exlog_ancient', {
        'id': 'exlog_ancient',
        'exercise_name': 'Squat',
        'date': '2024-08-01',
        'logging_type': 'weight_reps',
        'sets_completed': 4,
        'reps_completed': 32,
        'weight_kg': 110.0,
      });

      expect(row.setsCtrl.text, '4');
      expect(row.repsCtrl.text, '32');
      expect(row.weightCtrl.text, '110');
    });
  });

  // ───────────────────────────────────────────────────────────
  //  D · The two surfaces agree on the same row
  // ───────────────────────────────────────────────────────────
  group('D · receipt and edit sheet agree', () {
    setUp(() async {
      await wwsTestSetup();
    });
    tearDown(() async {
      await wwsTestTeardown();
    });

    test(
      'both surfaces report the same set count and duration for a restored '
      'row — the drift OI-50 actually was',
      () async {
        final date = DateTime(2026, 7, 6);
        final dateKey = formatDateKey(date);
        final raw = restoredExlogRow(dateKey: dateKey, setNumber: 4,
            durationSeconds: 480);
        await HiveService.instance.workoutBox.put('exlog_restored', raw);

        final receipt = WorkoutReceiptData.fromExerciseLogs(date);
        final row = EditLogExerciseRow.fromLog('exlog_restored', raw);

        final ex = receipt!.exercises.single;
        expect(ex.sets.toString(), row.setsCtrl.text,
            reason: 'set count must not differ between the two surfaces');
        expect(ex.totalDurationSeconds.toString(), row.durationCtrl.text,
            reason: 'duration must not differ between the two surfaces');
      },
    );
  });
}
