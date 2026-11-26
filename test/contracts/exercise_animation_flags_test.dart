// test/contracts/exercise_animation_flags_test.dart
//
// Batch M2a (plan Task 3): the exercise-animation kill switch. `PlateFlags.animationsEnabled` is true unless
// `configBox['disable_exercise_animations']` is set, and it also follows the plates switch (an animation replaces a plate, so
// with plates off there is nothing to replace). A missing Hive reads as ENABLED, the same guard as `platesEnabled`.
//
// ORDER MATTERS: the no-Hive case runs FIRST, before any test opens Hive (a flutter_test file is one isolate, and
// HiveService.instance stays initialised once marked); every later test opens a fresh temp-dir Hive in its own body.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_flags.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  test('no Hive at all reads as ENABLED for both switches (the same guard as platesEnabled)', () {
    expect(HiveService.instance.isInitialized, isFalse, reason: 'this test must run before any test opens Hive');
    expect(PlateFlags.platesEnabled, isTrue);
    expect(PlateFlags.animationsEnabled, isTrue);
  });

  group('with a configBox', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      await HiveService.instance.configBox.delete('disable_exercise_plates');
      await HiveService.instance.configBox.delete('disable_exercise_animations');
    });

    tearDown(() async => tearDownHiveForTests(tempDir));

    test('neither switch set -> animations enabled', () {
      expect(PlateFlags.animationsEnabled, isTrue);
    });

    test('only the plates switch set -> animations disabled', () async {
      await HiveService.instance.configBox.put('disable_exercise_plates', true);
      expect(PlateFlags.animationsEnabled, isFalse);
    });

    test('only the animations switch set -> animations disabled', () async {
      await HiveService.instance.configBox.put('disable_exercise_animations', true);
      expect(PlateFlags.animationsEnabled, isFalse);
    });

    test('both switches set -> animations disabled', () async {
      await HiveService.instance.configBox.put('disable_exercise_plates', true);
      await HiveService.instance.configBox.put('disable_exercise_animations', true);
      expect(PlateFlags.animationsEnabled, isFalse);
    });

    test('a value other than true does not disable (false is not a kill)', () async {
      await HiveService.instance.configBox.put('disable_exercise_animations', false);
      expect(PlateFlags.animationsEnabled, isTrue);
    });

    test('mirror: the animations switch does not turn the plates off', () async {
      await HiveService.instance.configBox.put('disable_exercise_animations', true);
      expect(PlateFlags.platesEnabled, isTrue);
    });
  });
}
