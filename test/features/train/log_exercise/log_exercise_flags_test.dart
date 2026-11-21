// The flip (docs/plans/log-exercise-flip.md §4, §6 "Flag"): the kill switch
// `enable_log_exercise_button` reads default ON. A stored `false` is the only
// way to the old per-set path; no Hive (a pure unit test) is the old path too.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/services/log_exercise_flags.dart';

import '../../../helpers/hive_test_setup.dart';

void main() {
  // F0 runs FIRST, before any Hive box is open.
  test('F0: no Hive (box not open) reads OFF', () {
    expect(LogExerciseFlags.logExerciseButtonEnabled, isFalse);
  });

  group('with Hive', () {
    late Directory dir;
    setUp(() async => dir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(dir));

    Future<void> store(Object? value) =>
        HiveService.instance.configBox.put(LogExerciseFlags.key, value);

    test('F1: key absent reads ON', () {
      expect(HiveService.instance.configBox.containsKey(LogExerciseFlags.key),
          isFalse);
      expect(LogExerciseFlags.logExerciseButtonEnabled, isTrue);
    });

    test('F2: stored false is the kill switch; stored true is ON', () async {
      await store(false);
      expect(LogExerciseFlags.logExerciseButtonEnabled, isFalse);
      await store(true);
      expect(LogExerciseFlags.logExerciseButtonEnabled, isTrue);
    });

    test('F3: a non-bool value reads ON', () async {
      for (final v in <Object>['false', 0, 'off']) {
        await store(v);
        expect(LogExerciseFlags.logExerciseButtonEnabled, isTrue,
            reason: 'stored ${v.runtimeType} $v');
      }
    });

    test('F3b: deleting a stored false turns it ON again', () async {
      await store(false);
      await HiveService.instance.configBox.delete(LogExerciseFlags.key);
      expect(LogExerciseFlags.logExerciseButtonEnabled, isTrue);
    });
  });
}
