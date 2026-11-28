// OI-191: every reader that projects a goal date, or says "at this rate", asks the
// ONE rule in `target_weight_check.dart` (a Cut needs a target below, a Build above,
// a Maintain within 3 kg) instead of keeping its own `(current - target).abs()` gate.
//
// Source-grep pin: PRESENCE only. The behaviour of the rule is pinned in
// test/onboarding/target_weight_check_test.dart (every goal x direction x edge).
// Mutation record: docs/diagnoses/2026-11-18-goal-target-weight-agreement-b5d2e8.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path moved: repoint this pin');
  // Comments out: a doc comment must not satisfy or break a pin.
  return f
      .readAsLinesSync()
      .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
      .join('\n');
}

void main() {
  const gated = <String, String>{
    'lib/features/nutrition/screens/nutrition_screen.dart': 'canProjectGoalDate(',
    'lib/features/profile/screens/profile/nutrition_targets.dart': 'canProjectGoalDate(',
    'lib/features/profile/screens/profile/subscription_section.dart': 'canProjectGoalDate(',
    // OI-518: the callout moved out of the Reports screen into its own widget; the
    // screen's call site (goal: from primary_goal) is pinned in
    // maintain_weight_callout_behavioral_test.dart.
    'lib/features/profile/widgets/weight_projection_callout.dart': 'projectionCalloutKind(',
    'lib/features/profile/screens/profile/journey_timeline.dart': 'journeyEtaAllowed(',
  };

  gated.forEach((path, call) {
    test('$path asks the shared rule ($call)', () {
      expect(_src(path), contains(call));
    });
  });

  test('no reader keeps its own inline gap gate between the weights', () {
    final inline = RegExp(
        r'\(\s*(currentKg|current|firstW|lastW|last\.value)\s*-\s*(targetKg|target|targetWeight)\s*\)\s*\.abs\(\)');
    for (final path in gated.keys) {
      expect(inline.hasMatch(_src(path)), isFalse,
          reason: '$path re-derived the gap gate; use the shared rule');
    }
  });

  test('the shared rule is the only home of the direction check', () {
    final rule = _src('lib/features/onboarding/target_weight_check.dart');
    for (final fn in [
      'bool canProjectGoalDate(',
      'ProjectionCalloutKind projectionCalloutKind(',
      'bool journeyEtaAllowed(',
      'bool goalTargetAgree(',
    ]) {
      expect(rule, contains(fn));
    }
  });
}
