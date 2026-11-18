// OI-191: the coach's goal-switch preview says what ELSE the switch writes
// (target weight, daily calories, protein), from the same `goalChange` the
// dispatcher applies.
//
// Harness note: pure widget, no Hive and no path_provider, so no font priming.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/widgets/diff_preview/goal_targets_preview.dart';
import 'package:icanbefitter/features/profile/services/goal_change_patch.dart';

Map<String, dynamic> _profile({Object? target = 71.0, bool complete = true}) => {
      'primary_goal': 'lose_fat',
      'current_weight_kg': 75.0,
      'target_weight_kg': target,
      'height_cm': 175.0,
      'gender': 'male',
      'activity_level': 'moderate',
      'days_per_week': 4,
      'pace_preference': 'balanced',
      if (complete) 'date_of_birth': '1995-06-15',
      'daily_calories': 2000,
      'protein_grams': 150,
    };

GoalChange _change(Map<String, dynamic> p, String goal) => goalChange(p,
    newGoal: goal, now: DateTime(2026, 11, 18, 10), bodyFatCalcDisabled: false);

Future<void> _pump(WidgetTester t, GoalChange c, String goal) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: GoalTargetsPreview(change: c, goal: goal))),
  ));
  await t.pump();
}

void main() {
  testWidgets('a target that breaks the new goal shows the target and calorie lines',
      (t) async {
    await _pump(t, _change(_profile(), 'build_muscle'), 'build_muscle');
    expect(find.byKey(const ValueKey('goal_targets_preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal_preview_target')), findsOneWidget);
    expect(find.textContaining('Target weight 71.0 → 78.0 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal_preview_calories')), findsOneWidget);
  });

  testWidgets('a target that already fits shows no target line',
      (t) async {
    // Maintain: 71 vs 75 is 4 kg, breaks. Use 74 (fits) to keep the seed out.
    await _pump(t, _change(_profile(target: 74.0), 'general_fitness'), 'general_fitness');
    expect(find.byKey(const ValueKey('goal_preview_target')), findsNothing);
  });

  testWidgets('an incomplete profile with a fitting target renders nothing', (t) async {
    final c = _change(_profile(target: 74.0, complete: false), 'general_fitness');
    expect(c.targetSeeded, isFalse);
    expect(c.hasTargets, isFalse);
    await _pump(t, c, 'general_fitness');
    expect(find.byKey(const ValueKey('goal_targets_preview')), findsNothing);
  });

  test('SwitchGoalDiff mounts the preview after the refused-goal return', () {
    final src = File('lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart')
        .readAsStringSync();
    final refused = src.indexOf('if (_refused) {');
    final mount = src.indexOf('GoalTargetsPreview(change: _change!');
    expect(refused, greaterThan(-1));
    expect(mount, greaterThan(refused),
        reason: 'the preview must not show for a goal the coach cannot offer');
  });
}
