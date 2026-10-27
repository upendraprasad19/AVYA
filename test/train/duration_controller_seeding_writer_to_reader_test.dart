// Source-grep contract for bug e8f95e (2026-09-28) — presence only, per
// CLAUDE.md rule 21. The behavioral proof of the downstream consequence
// lives in test/workout_write_service/aggregate_reflects_cleaned_sets_test.dart
// (the SoT registry's behavioral_test_path for concept
// duration_controller_seeding_leak); this file pins the actual UI-layer
// fix so a future edit to _initControllers can't silently reintroduce the
// copy-paste that caused the bug in the first place.
//
// Writer: exercise_card.dart _initControllers — was seeding
// _durationControllers with `repsValue` (copy-paste of the reps
// controller's seed line immediately above it). LastPerformanceData has
// no duration field, so there is no legitimate prefill source for
// duration; _captureSetValues parses BOTH controllers unconditionally
// regardless of which one the active loggingType actually renders, so a
// non-empty seed here silently leaked into SetInputValues.durationSeconds
// even for a pure reps-based exercise the user never saw a duration field
// for.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final f = File(
        'lib/features/train/screens/active_workout/exercise_card.dart');
    expect(f.existsSync(), isTrue);
    src = f.readAsStringSync();
  });

  group('duration_controller_seeding_leak writer contract', () {
    test('_durationControllers is NOT seeded with repsValue', () {
      expect(
          src.contains(
              '_durationControllers = List.generate(n, (_) => TextEditingController(text: repsValue));'),
          isFalse,
          reason: 'bug e8f95e — this exact copy-paste leaked the reps '
              'prefill into the duration controller for every exercise, '
              'regardless of loggingType');
    });

    test('_durationControllers is seeded empty (no legitimate prefill '
        'source exists in LastPerformanceData)', () {
      expect(
          src.contains(
              '_durationControllers = List.generate(n, (_) => TextEditingController());'),
          isTrue,
          reason: 'the fix: leave it empty, matching _distanceControllers '
              'immediately below, which has the same "no prefill data" '
              'shape');
    });
  });
}
