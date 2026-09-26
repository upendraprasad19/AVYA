// test/contracts/edit_workout_log_sets_field_contract_test.dart
//
// Contract: exercise_log_per_set — EditWorkoutLogSheet reader path.
//
// Bug e1f8a2 (APK Test #15.3, sibling to 6e1b45):
//   `_ExerciseEditRow.fromLog` (renamed `EditLogExerciseRow.fromLog` in
//   the fix) read ONLY `log['sets_detail']` — the pre-Test-#6 legacy
//   field name. Modern `WorkoutWriteService.logExercise` writes canonical
//   `log['sets']` and does NOT populate `sets_detail`. So the edit sheet
//   fell through to the aggregate fallback for modern rows, presenting
//   the user with empty duration inputs even though Hive carried the
//   correct per-set values.
//
//   Symmetric per-set bug: `_SetEditRow.fromSetDetail` (renamed
//   `EditLogSetRow.fromSetDetail`) read ONLY `set['duration_seconds']`.
//   `ExerciseSet.toMap` writes canonical `'duration_sec'`, so the
//   per-set duration was lost even when the outer list was readable.
//
// This contract pins:
//   1. fromLog accepts canonical `'sets'` (modern WriteService shape).
//   2. fromLog still accepts legacy `'sets_detail'` (pre-Test-#6).
//   3. fromSetDetail accepts canonical `'duration_sec'`.
//   4. fromSetDetail still accepts legacy `'duration_seconds'` (the
//      restore-shape written by `SyncService._restoreExerciseLogs`).
//
// Pre-fix: tests 1 + 3 FAIL.
// Post-fix: all four pass.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/widgets/edit_workout_log_sheet.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('EditLogExerciseRow.fromLog — per-set field-name contract', () {
    test(
      'modern WriteService shape: log[sets] populates per-set rows '
      'with duration_sec → durationCtrl',
      () {
        // Modern WorkoutWriteService.logExercise output shape:
        //   - canonical 'sets' (List<Map>) per-set array
        //   - per-set entries use canonical 'duration_sec'
        //   - 'sets_detail' is absent (NOT written by modern path)
        final modernLog = <String, dynamic>{
          'id': 'exlog_2026-05-11_-1234',
          'exercise_name': 'Handstand Hold',
          'date': '2026-05-11',
          'workout_log_id': 'wlog_2026-05-11',
          'logging_type': 'timed',
          'set_number': 3,
          'reps_completed': 0,
          'weight_kg': 0.0,
          'volume_kg': 0.0,
          'updated_at_ms': 1736582400000,
          'sets': <Map<String, dynamic>>[
            {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 30,
              'logged_at_ms': 1736582400000},
            {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 30,
              'logged_at_ms': 1736582460000},
            {'weight_kg': 0.0, 'reps': 0, 'duration_sec': 30,
              'logged_at_ms': 1736582520000},
          ],
          // NOTE: no 'sets_detail' key — modern writer doesn't emit it.
        };

        final row = EditLogExerciseRow.fromLog('exlog_x', modernLog);

        // FAIL pre-fix: fromLog reads only 'sets_detail' (null here) →
        // falls through to aggregate view → hasPerSetData = false.
        expect(row.hasPerSetData, isTrue,
            reason: 'modern log[sets] must produce per-set rows');
        expect(row.setRows.length, 3,
            reason: 'three sets logged, three set rows expected');
        expect(row.loggingType, 'timed');
        expect(row.exerciseName, 'Handstand Hold');

        // Per-set duration must round-trip from canonical 'duration_sec'.
        for (var i = 0; i < 3; i++) {
          expect(row.setRows[i].durationCtrl.text, '30',
              reason: 'set ${i + 1} duration_sec=30 must populate controller');
        }
      },
    );

    test(
      'legacy pre-Test-#6 shape: log[sets_detail] still populates '
      'per-set rows with duration_seconds → durationCtrl',
      () {
        // Pre-Test-#6 EditWorkoutLogSheet shape:
        //   - legacy 'sets_detail' (List<Map>) per-set array
        //   - per-set entries use legacy 'duration_seconds'
        //   - 'sets' is absent
        final legacyLog = <String, dynamic>{
          'id': 'exlog_2025-12-01_-5678',
          'exercise_name': 'Plank',
          'date': '2025-12-01',
          'logging_type': 'timed',
          'sets_completed': 3,
          'reps_completed': 0,
          'weight_kg': 0.0,
          'duration_seconds': 0,
          'sets_detail': <Map<String, dynamic>>[
            {'set_number': 1, 'reps': 0, 'weight_kg': 0.0,
              'duration_seconds': 60},
            {'set_number': 2, 'reps': 0, 'weight_kg': 0.0,
              'duration_seconds': 75},
            {'set_number': 3, 'reps': 0, 'weight_kg': 0.0,
              'duration_seconds': 90},
          ],
          // NOTE: no 'sets' key — pre-Test-#6 writer didn't emit it.
        };

        final row = EditLogExerciseRow.fromLog('exlog_x', legacyLog);

        expect(row.hasPerSetData, isTrue,
            reason: 'legacy log[sets_detail] must still produce per-set rows');
        expect(row.setRows.length, 3);
        expect(row.setRows[0].durationCtrl.text, '60');
        expect(row.setRows[1].durationCtrl.text, '75');
        expect(row.setRows[2].durationCtrl.text, '90');
      },
    );

    test(
      'restore-shape hybrid: log[sets] (canonical key) carries legacy '
      'per-set duration_seconds (as written by _restoreExerciseLogs)',
      () {
        // SyncService._restoreExerciseLogs:2882-2893 writes:
        //   - canonical key 'sets' (NOT 'sets_detail')
        //   - legacy per-set field name 'duration_seconds'
        // This is the hybrid the founder hits after a restore.
        final restoredLog = <String, dynamic>{
          'id': 'exlog_2026-05-11_-9999',
          'exercise_name': 'Jump Rope',
          'date': '2026-05-11',
          'logging_type': 'timed',
          'set_number': 2,
          'sets': <Map<String, dynamic>>[
            {'set_number': 1, 'reps': 0, 'weight_kg': 0.0,
              'duration_seconds': 30},
            {'set_number': 2, 'reps': 0, 'weight_kg': 0.0,
              'duration_seconds': 30},
          ],
        };

        final row = EditLogExerciseRow.fromLog('exlog_x', restoredLog);

        expect(row.hasPerSetData, isTrue,
            reason: 'restored log[sets] must produce per-set rows');
        expect(row.setRows.length, 2);
        // duration_seconds (legacy) must populate even when carried inside
        // canonical 'sets' wrapper.
        expect(row.setRows[0].durationCtrl.text, '30');
        expect(row.setRows[1].durationCtrl.text, '30');
      },
    );

    test(
      'weight_reps modern shape: per-set weight + reps preserved through '
      'canonical sets[] reader',
      () {
        // Non-timed exercise to confirm reps/weight read paths unaffected
        // by the duration fallback work.
        final modernLog = <String, dynamic>{
          'id': 'exlog_2026-05-11_-0001',
          'exercise_name': 'Bench Press',
          'date': '2026-05-11',
          'logging_type': 'weight_reps',
          'set_number': 3,
          'reps_completed': 24,  // sum
          'weight_kg': 100.0,    // max
          'sets': <Map<String, dynamic>>[
            {'weight_kg': 80.0, 'reps': 10, 'logged_at_ms': 1},
            {'weight_kg': 90.0, 'reps': 8, 'logged_at_ms': 2},
            {'weight_kg': 100.0, 'reps': 6, 'logged_at_ms': 3},
          ],
        };

        final row = EditLogExerciseRow.fromLog('exlog_x', modernLog);

        expect(row.hasPerSetData, isTrue);
        expect(row.setRows.length, 3);
        // Per-set granularity preserved — not aggregate sum/max.
        expect(row.setRows[0].weightCtrl.text, '80');
        expect(row.setRows[0].repsCtrl.text, '10');
        expect(row.setRows[1].weightCtrl.text, '90');
        expect(row.setRows[1].repsCtrl.text, '8');
        expect(row.setRows[2].weightCtrl.text, '100');
        expect(row.setRows[2].repsCtrl.text, '6');
      },
    );

    test(
      'aggregate fallback still works when neither sets nor sets_detail '
      'is present (very old one-shot complete-workout writes)',
      () {
        final ancientLog = <String, dynamic>{
          'id': 'exlog_2024-08-01_-1111',
          'exercise_name': 'Squat',
          'date': '2024-08-01',
          'logging_type': 'weight_reps',
          'sets_completed': 4,
          'reps_completed': 32,
          'weight_kg': 110.0,
        };

        final row = EditLogExerciseRow.fromLog('exlog_x', ancientLog);

        expect(row.hasPerSetData, isFalse,
            reason: 'no per-set array → aggregate view');
        expect(row.setRows, isEmpty);
        expect(row.setsCtrl.text, '4');
        expect(row.repsCtrl.text, '32');
        expect(row.weightCtrl.text, '110');
      },
    );
  });

  group('EditLogSetRow.fromSetDetail — duration_sec dual-name', () {
    test('canonical duration_sec is read', () {
      final setMap = <String, dynamic>{
        'weight_kg': 0.0,
        'reps': 0,
        'duration_sec': 45,
        'logged_at_ms': 1736582400000,
      };
      final row = EditLogSetRow.fromSetDetail(setMap);
      expect(row.durationCtrl.text, '45');
      row.dispose();
    });

    test('legacy duration_seconds still read', () {
      final setMap = <String, dynamic>{
        'weight_kg': 0.0,
        'reps': 0,
        'duration_seconds': 60,
      };
      final row = EditLogSetRow.fromSetDetail(setMap);
      expect(row.durationCtrl.text, '60');
      row.dispose();
    });

    test('canonical wins when both present', () {
      // Belt and suspenders — if both names happen to be on the map,
      // canonical wins (per the `??` short-circuit order).
      final setMap = <String, dynamic>{
        'weight_kg': 0.0,
        'reps': 0,
        'duration_sec': 30,
        'duration_seconds': 999, // would lose
      };
      final row = EditLogSetRow.fromSetDetail(setMap);
      expect(row.durationCtrl.text, '30');
      row.dispose();
    });
  });
}
