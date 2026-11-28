// Unit 3C (OI-396, founder d77 / d78): the injury diff preview tells the user the injury will be added to their profile
// before they confirm (`Adds Knee to your injuries (change it in Edit Profile)`), in BOTH branches: no upcoming
// exercise to change (the case where confirming only records the injury) and the normal swap list. No line when the
// profile already holds it.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/widgets/diff_preview/injury_modify_diff.dart';

import '../features/train/log_exercise/card_harness.dart' show closeHive, ensureHive, renderFontsFirst;

ToolIntent _intent(String part) => ToolIntent(
      id: 'diff_$part',
      type: 'modify_workout_for_injury',
      payload: {'bodyPart': part, 'severity': 'mild', 'daysAhead': 7},
      confirmationClass: ConfirmationClass.destructive,
      previewSummary: 'x',
      createdAt: DateTime.now(),
    );

Future<void> _pump(WidgetTester tester, String part) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: InjuryModifyDiff(intent: _intent(part))))));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);
  tearDownAll(closeHive);

  Future<void> seed(WidgetTester tester, {required Object? injuries, bool withSquatToday = false}) async {
    await ensureHive(tester);
    await tester.runAsync(() async {
      await HiveService.instance.workoutBox.clear();
      await HiveService.instance.userBox.put('profile', {'primary_goal': 'lose_fat', 'injuries': injuries});
      await HiveService.instance.exerciseBox.put('Squat', {
        'id': 'Squat',
        'name': 'Squat',
        'category': 'legs',
        'primary_muscles': ['quads'],
      });
      await HiveService.instance.exerciseBox.put('Leg Curl', {
        'id': 'Leg Curl',
        'name': 'Leg Curl',
        'category': 'legs',
        'primary_muscles': ['hamstrings'],
      });
      if (withSquatToday) {
        final today = istDateStr(DateTime.now());
        await HiveService.instance.workoutBox.put('schedule_$today', {
          'date': today,
          'type': 'workout',
          'workout_name': 'Legs',
          'status': 'planned',
          'exercises': [
            {'exercise_id': 'Squat', 'exercise_name': 'Squat', 'sets': 3, 'reps': '8', 'primary_muscles': ['quads']},
          ],
        });
      }
    });
  }

  testWidgets('no exercise to change: the line shows and the text names the profile', (tester) async {
    await seed(tester, injuries: const ['none']);
    await _pump(tester, 'knee');
    expect(find.text('Adds Knee to your injuries (change it in Edit Profile)'), findsOneWidget);
    expect(find.textContaining('Confirm to save the injury to your profile.'), findsOneWidget);
  });

  testWidgets('quad is saved as knee (d78)', (tester) async {
    await seed(tester, injuries: const ['none']);
    await _pump(tester, 'quad');
    expect(find.text('Adds Knee to your injuries (change it in Edit Profile)'), findsOneWidget);
  });

  testWidgets('already in the profile: no line, the old text', (tester) async {
    await seed(tester, injuries: const ['knee']);
    await _pump(tester, 'knee');
    expect(find.byKey(const ValueKey('injury_adds_profile_line')), findsNothing);
    expect(find.textContaining('Confirm to record the injury anyway.'), findsOneWidget);
  });

  testWidgets('the swap list branch carries the line too', (tester) async {
    await seed(tester, injuries: const ['none'], withSquatToday: true);
    await _pump(tester, 'quad');
    expect(find.byKey(const ValueKey('injury_adds_profile_line')), findsOneWidget);
    expect(find.textContaining(' across '), findsOneWidget, reason: 'the swap list branch rendered');
  });
}
