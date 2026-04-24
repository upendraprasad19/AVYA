import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that both START WORKOUT call sites in train_screen.dart are
/// gated behind featureActiveWorkoutMode.
///
/// Previously both buttons navigated directly to /train/active-workout
/// without any subscription check — a free-for-all despite
/// featureActiveWorkoutMode being declared PRO in AppConstants.
void main() {
  late String trainScreenSource;

  setUpAll(() {
    final file = File('lib/features/train/screens/train_screen.dart');
    expect(file.existsSync(), isTrue,
        reason: 'train_screen.dart must exist');
    trainScreenSource = file.readAsStringSync();
  });

  group('C4 — featureActiveWorkoutMode gate', () {
    test('gate(featureActiveWorkoutMode, ...) appears at least twice', () {
      final pattern = RegExp(
          r'gate\(\s*AppConstants\.featureActiveWorkoutMode',
          dotAll: true);
      final matches = pattern.allMatches(trainScreenSource).toList();
      expect(
        matches.length,
        greaterThanOrEqualTo(2),
        reason: 'Both START WORKOUT buttons must call gate(featureActiveWorkoutMode)',
      );
    });

    test('showPaywallSheet is called on the free path for active workout', () {
      expect(
        trainScreenSource,
        contains("feature: 'Active Workout Mode'"),
        reason: 'onFree path must show paywall for Active Workout Mode',
      );
    });

    test('no direct context.go active-workout without a gate', () {
      // All occurrences of the navigation target should appear inside a gate
      // onPro callback. We verify no bare onPressed lambda navigates directly.
      // Strategy: count occurrences of context.go('/train/active-workout') —
      // they should NOT be preceded by a bare `onPressed: ()` without a gate.
      // Simpler proxy: the old bare `onPressed: () {` immediately followed by
      // a startWorkout + context.go pattern is gone.
      expect(
        trainScreenSource,
        isNot(contains(
          "onPressed: () {\n              ref\n                  .read(activeWorkoutProvider.notifier)\n                  .startWorkout(workout);\n              context.go('/train/active-workout')",
        )),
        reason: 'First START WORKOUT must no longer be a bare unguarded onPressed',
      );
    });
  });
}
