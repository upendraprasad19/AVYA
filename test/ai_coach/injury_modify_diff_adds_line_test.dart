// Unit 3C (OI-396, founder d77 / d78): the injury diff preview tells the user the injury will be added to their profile
// before they confirm (`Adds Knee to your injuries (change it in Edit Profile)`), in BOTH branches: no upcoming
// exercise to change (the case where confirming only records the injury) and the normal swap list. No line when the
// profile already holds it. The preview also names every affected exercise it found no substitute for (founder
// 2026-11-28 batch): "no exercise hits this body part" is said only when none does.
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

  Future<void> seed(WidgetTester tester,
      {required Object? injuries,
      bool withSquatToday = false,
      bool curlNeedsBarbell = false,
      bool withNordicToday = false}) async {
    await ensureHive(tester);
    await tester.runAsync(() async {
      await HiveService.instance.workoutBox.clear();
      await HiveService.instance.exerciseBox.clear();
      await HiveService.instance.userBox.put('profile', {'primary_goal': 'lose_fat', 'injuries': injuries});
      await HiveService.instance.exerciseBox.put('Squat', {
        'id': 'Squat',
        'name': 'Squat',
        'category': 'legs',
        'primary_muscles': ['quads'],
        'equipment_needed': ['bodyweight'],
      });
      await HiveService.instance.exerciseBox.put('Leg Curl', {
        'id': 'Leg Curl',
        'name': 'Leg Curl',
        'category': 'legs',
        'primary_muscles': ['hamstrings'],
        'equipment_needed': [curlNeedsBarbell ? 'barbell' : 'bodyweight'],
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
            if (withNordicToday)
              {'exercise_id': 'Pistol', 'exercise_name': 'Pistol', 'sets': 3, 'reps': '8', 'primary_muscles': ['quads']},
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

  const unplaced = ValueKey('injury_unplaced_block');
  const heading = 'No substitute found for these. They stay in your plan:';

  testWidgets('nothing could be replaced: the exercises are named, never "no exercise hits"',
      (tester) async {
    await seed(tester, injuries: const ['none'], withSquatToday: true, curlNeedsBarbell: true);
    await _pump(tester, 'quad');
    expect(find.byKey(unplaced), findsOneWidget);
    expect(find.text(heading), findsOneWidget);
    expect(find.text('${istDateStr(DateTime.now())} · Squat'), findsOneWidget);
    expect(find.textContaining('hit this body part'), findsNothing);
    expect(find.text('Confirm to save the injury to your profile.'), findsOneWidget);
  });

  testWidgets('some replaced, some not: both the block and the change list', (tester) async {
    // One substitute, two affected exercises.
    await seed(tester, injuries: const ['knee'], withSquatToday: true, withNordicToday: true);
    await _pump(tester, 'quad');
    expect(find.byKey(unplaced), findsOneWidget);
    expect(find.text('${istDateStr(DateTime.now())} · Pistol'), findsOneWidget);
    expect(find.textContaining('1 change across 1 day'), findsOneWidget);
    expect(find.textContaining('Confirm to'), findsNothing);
    expect(tester.getTopLeft(find.byKey(unplaced)).dy,
        lessThan(tester.getTopLeft(find.textContaining(' across ')).dy));
  });

  testWidgets('mirror: truly unaffected days show no block', (tester) async {
    await seed(tester, injuries: const ['knee']);
    await _pump(tester, 'quad');
    expect(find.byKey(unplaced), findsNothing);
    expect(find.textContaining('hit this body part'), findsOneWidget);
  });

  testWidgets('the swap list branch carries the line too', (tester) async {
    await seed(tester, injuries: const ['none'], withSquatToday: true);
    await _pump(tester, 'quad');
    expect(find.byKey(const ValueKey('injury_adds_profile_line')), findsOneWidget);
    expect(find.textContaining(' across '), findsOneWidget, reason: 'the swap list branch rendered');
  });
}
