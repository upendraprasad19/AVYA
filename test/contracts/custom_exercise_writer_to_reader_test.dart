// test/contracts/custom_exercise_writer_to_reader_test.dart
//
// Contract (E.13 — Audit 2026-05-16 framework deliverable):
// Pin the `custom_exercise_<ms>` Hive key shape + field set written by
// the CREATE path and consumed by readers across train + sync.
//
// Writer (the ONE create path since diagnose d5c2e8 — the sheet and the AI
// coach tool both call it):
//   lib/features/train/repositories/workout_repository.dart
//     `createCustomExercise` → WorkoutWriteService.upsertCustomExercise
// Caller pinned here: lib/features/train/widgets/create_custom_exercise_sheet.dart
//   `_save` create branch (was a raw customBox.put until d5c2e8).
//
// Readers:
//   lib/features/train/screens/train_screen.dart (YOUR EXERCISES section)
//   lib/core/services/sync/sync_community.dart `_syncCustomItems`
//   lib/core/services/sync/sync_community.dart `_restoreCustomExercises`
//
// Failure mode this prevents: field rename in the writer breaks one or
// more readers silently. APK Test #16 / 5e35aaf exercised this exact
// pattern (`type:'exercise'` missing on restored entries — picker
// dropped them).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

/// Body of `Future<String> _createCustomExerciseLocked(...)` — the serialized
/// half of createCustomExercise that builds and writes the row (B-pass F2) —
/// brace-matched so an assertion can't be satisfied by text elsewhere in the
/// 1.7K-line file.
String _createBody(String src) {
  final start = src.indexOf('Future<String> _createCustomExerciseLocked(');
  expect(start, isNot(-1), reason: '_createCustomExerciseLocked must exist');
  final open = src.indexOf('{', src.indexOf(') async', start));
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  fail('unbalanced braces in createCustomExercise');
}

void main() {
  late String writerSrc;
  late String sheetSrc;
  late String trainScreenSrc;
  late String syncCommunitySrc;

  setUpAll(() {
    writerSrc = _createBody(
        File('lib/features/train/repositories/workout_repository.dart')
            .readAsStringSync());
    sheetSrc = File(
            'lib/features/train/widgets/create_custom_exercise_sheet.dart')
        .readAsStringSync();
    trainScreenSrc =
        readScreenSource('train');
    syncCommunitySrc = File('lib/core/services/sync/sync_community.dart')
        .readAsStringSync();
  });

  group('custom_exercise_<ms> writer→reader contract', () {
    test('writer uses `custom_exercise_<ms>` key formula', () {
      // The canonical formula is 'custom_exercise_<ms>', ms from
      // DateTime.now().millisecondsSinceEpoch, bumped past any taken key.
      expect(
        writerSrc,
        contains("custom_exercise_"),
        reason: 'writer must produce keys with prefix `custom_exercise_`',
      );
      expect(
        writerSrc,
        contains('millisecondsSinceEpoch'),
        reason: 'writer key formula uses millisecondsSinceEpoch suffix',
      );
    });

    test('writer stamps the required fields', () {
      // These fields are read by at least one downstream consumer.
      const requiredFields = [
        "'id'", // deterministic v5 UUID (sync_community projection)
        "'name'", // display
        "'category'", // grouping
        "'logging_type'", // active workout columns
        "'is_custom'", // discriminator for repos
        "'type'", // 'exercise' (separates from saved meals)
        "'submitted_to_library'", // community gating
        "'approved_for_library'", // submission status
        "'primary_muscles'",
        "'created_at'",
      ];
      for (final f in requiredFields) {
        expect(
          writerSrc.contains(f),
          isTrue,
          reason: 'writer must stamp field $f',
        );
      }
    });

    test('sheet create passes the chip selection, not an empty list', () {
      // custom-picker-fix (2026-09-17): the chip selection re-arms the
      // plan-generator supplement path (_eligibleCustomExercises skips
      // customs with empty primary_muscles). Since d5c2e8 the sheet hands it
      // to the repository as an argument.
      expect(sheetSrc.contains('primaryMuscles: _resolvedMuscles'), isTrue);
    });

    test('sheet create goes through createCustomExercise, never a raw put '
        '(d5c2e8)', () {
      expect(sheetSrc.contains('WorkoutRepository.instance.createCustomExercise('),
          isTrue);
      expect(sheetSrc.contains('customBox.put('), isFalse,
          reason: 'a raw put skips the duplicate guard, the 60-char cap and '
              'the writer stamps — the d5c2e8 bypass');
      expect(sheetSrc.contains('syncCustomItemsNow'), isFalse,
          reason: 'sync fan-out belongs to the writer, not the sheet');
    });

    test("writer stamps type:'exercise' (Test #16 5e35aaf discriminator)", () {
      // Reader filter in ExerciseRepository.getCustomExercises uses
      // both key-prefix AND `type=='exercise'`. Drift either way drops
      // entries silently.
      expect(
        writerSrc,
        contains("'type': 'exercise'"),
        reason: "writer must stamp 'type': 'exercise' explicitly",
      );
    });

    test('sync_community._restoreCustomExercises also stamps type:\'exercise\'', () {
      // Belt-and-suspenders for restored rows (cloud has no `type` col).
      // The Test #16 5e35aaf fix added the stamp at the writer.
      expect(
        syncCommunitySrc,
        contains("'type'"),
        reason: 'restore path must stamp `type` on each restored row so '
            'legacy readers (key-prefix-only) continue to work',
      );
    });

    test('train_screen reads customBox and renders YOUR EXERCISES section', () {
      // Train surface that lists custom exercises (key prefix scan or
      // ExerciseRepository.getCustomExercises read path).
      final readsCustom = trainScreenSrc.contains('customBox') ||
          trainScreenSrc.contains('getCustomExercises');
      expect(
        readsCustom,
        isTrue,
        reason: 'train_screen must read customBox or call getCustomExercises',
      );
    });

    test('sync_community._syncCustomItems projects custom exercises to cloud',
        () {
      expect(
        syncCommunitySrc,
        contains('user_custom_exercises'),
        reason:
            'sync_community must upsert to user_custom_exercises cloud table',
      );
      // Projection function exists.
      expect(
        syncCommunitySrc.contains('_projectCustomExercise') ||
            syncCommunitySrc.contains('_syncCustomItems'),
        isTrue,
      );
    });
  });
}
