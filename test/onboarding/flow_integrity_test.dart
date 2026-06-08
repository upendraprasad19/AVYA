// Regex-based file-content tests for PR-FIX-4 onboarding polish.
// These are pure-Dart string checks — no Flutter framework required,
// no device, no Hive.  They guard against accidental regressions when
// other PRs touch the three onboarding screens.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) {
  final file = File('lib/features/onboarding/screens/$relativePath');
  if (!file.existsSync()) {
    fail('Expected file not found: ${file.path}');
  }
  return file.readAsStringSync();
}

void main() {
  group('Onboarding flow integrity (PR-FIX-4)', () {
    // OB-1: ADJUST PLAN must route to /onboarding/details, not /stats.
    test('OB-1: plan_screen ADJUST PLAN goes to /onboarding/details', () {
      final src = _read('plan_screen.dart');
      // Find the ADJUST PLAN label and verify the context.go within the
      // same GestureDetector (within 300 chars before the label) points
      // to /onboarding/details.
      final adjustPlanIdx = src.indexOf("'ADJUST PLAN'");
      expect(
        adjustPlanIdx,
        greaterThan(0),
        reason: 'ADJUST PLAN label must still exist in plan_screen.dart',
      );
      final vicinity = src.substring(
        (adjustPlanIdx - 300).clamp(0, src.length),
        adjustPlanIdx,
      );
      expect(
        vicinity.contains("'/onboarding/details'"),
        isTrue,
        reason: 'ADJUST PLAN tap handler must navigate to /onboarding/details',
      );
      // Also confirm /stats is NOT in the same vicinity.
      expect(
        vicinity.contains("'/onboarding/stats'"),
        isFalse,
        reason: 'ADJUST PLAN must NOT route to /onboarding/stats anymore',
      );
    });

    // OB-2: Stats BACK must spread current controller values into the
    // route extra map, not just forward widget.initial.
    test('OB-2: stats_screen BACK carries current controller values', () {
      final src = _read('stats_screen.dart');
      // F20 (audit 2026-06-07): BACK forwards 'weight_kg' — the key the onboarding
      // flow actually READS (StatsScreen.initState / _onCalibrate / plan_screen).
      // The old 'current_weight_kg' key was silently dropped on return (reset to 75).
      expect(
        src.contains("'weight_kg': double.tryParse(_weight.text)"),
        isTrue,
        reason:
            'Stats BACK must forward weight_kg (the flow-read key) from the controller',
      );
      expect(
        src.contains("_weight.text.isNotEmpty"),
        isTrue,
        reason:
            'Stats BACK must guard weight controller text with isNotEmpty',
      );
    });

    // OB-5: Plan targets card must read days_per_week from route extras.
    test('OB-5: plan_screen _computeTargets reads days_per_week from widget.data',
        () {
      final src = _read('plan_screen.dart');
      expect(
        src.contains("(widget.data['days_per_week'] as int?) ??"),
        isTrue,
        reason:
            "_computeTargets must read widget.data['days_per_week'] with int? cast and fallback",
      );
    });

    // L4: Stats CONTINUE must show a non-blocking snackbar when body fat is empty.
    //
    // Copy was updated in APK Test #1 batch (2026-04-24) — the old
    // "We'll estimate body fat at 18% — you can refine later in Profile."
    // string was misleading (Mifflin-St Jeor doesn't use body fat at all).
    // New copy clarifies what actually happens: weight + height are used,
    // and body fat can be added later via Profile.
    test('L4: stats_screen shows body-fat default snackbar when field is blank',
        () {
      final src = _read('stats_screen.dart');
      expect(
        src.contains(
            "Skipping body fat \\u2014 using weight + height. Scan later from Profile to refine."),
        isTrue,
        reason:
            'Stats _onCalibrate must show the updated snackbar copy when '
            'body-fat field is blank (post APK Test #1).',
      );
      expect(
        src.contains('_bodyFat.text.trim().isEmpty'),
        isTrue,
        reason: 'Snackbar guard must check _bodyFat.text.trim().isEmpty',
      );
    });

    // L5: Goal screen must assert identity map is present and log a
    // debugPrint when it is null.
    test('L5: goal_screen asserts identity map and logs debugPrint on null',
        () {
      final src = _read('goal_screen.dart');
      expect(
        src.contains(
            "assert(widget.identity != null,"),
        isTrue,
        reason:
            'GoalScreen BACK must assert widget.identity is not null',
      );
      expect(
        src.contains(
            '[GoalScreen] BACK navigation missing identity map'),
        isTrue,
        reason:
            'GoalScreen must debugPrint a warning when identity is null',
      );
    });
  });
}
