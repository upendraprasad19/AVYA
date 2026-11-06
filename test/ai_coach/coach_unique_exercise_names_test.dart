// SoT concept `exercise_name_unique_in_day` (OI-358): the coach's doors through
// the REAL dispatcher and the REAL CoachSwapSheet. Writer contract:
// test/contracts/exercise_name_unique_in_day_behavioral_test.dart.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/injury_swap_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/swap_exercise_coach_sheet.dart';

import '../features/train/log_exercise/card_harness.dart' show renderFontsFirst;
import '../helpers/hive_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

ToolIntent _intent(String type, Map<String, dynamic> payload, {String? id}) =>
    ToolIntent(
      id: id ?? 'oi358_$type',
      type: type,
      payload: payload,
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: 'test',
      createdAt: DateTime.now(),
    );

Map<String, dynamic> _planned(String id, String name) => {
      'exercise_id': id,
      'exercise_name': name,
      'sets': 3,
      'reps': '8',
      'rest_seconds': 90,
      'logging_type': 'weight_reps',
      'category': 'legs',
      'primary_muscles': ['quads'],
    };

Future<void> _putToday(List<Map<String, dynamic>> exercises) =>
    HiveService.instance.workoutBox.put('schedule_${istDateStr(nowWall())}', {
      'date': istDateStr(nowWall()),
      'type': 'workout',
      'workout_name': 'D',
      'status': 'planned',
      'exercises': exercises,
    });

Future<void> _seedLibrary() async {
  final box = HiveService.instance.exerciseBox;
  for (final (id, name, muscle) in const [
    ('E1', 'Bench Press', 'chest'),
    ('E2', 'Seated Row', 'back'),
    ('E3', 'Calf Raise', 'calves'),
    ('E4', 'Hamstring Curl', 'hamstrings'),
    ('Squat', 'Squat', 'quads'),
    ('Lunge', 'Lunge', 'quads'),
  ]) {
    await box.put(id, {
      'id': id,
      'name': name,
      'category': 'legs',
      'primary_muscles': [muscle],
    });
  }
}

void main() {
  testWidgets('fonts degrade before any Hive mock', renderFontsFirst);

  group('through the dispatcher', () {
    late Directory dir;
    late ProviderContainer container;

    setUp(() async {
      dir = await setUpHiveForTests();
      SyncService.pausedForSimulation = true;
      SwapService.debugOnPlanPushForTests = () {};
      container = ProviderContainer();
      await _seedLibrary();
    });

    tearDown(() async {
      container.dispose();
      SyncService.pausedForSimulation = false;
      SwapService.debugOnPlanPushForTests = null;
      await tearDownHiveForTests(dir);
    });

    Future<ToolExecutionResult> run(ToolIntent intent) => ToolDispatcher.instance
        .execute(container.read(_refProvider), intent);

    test('swap_exercise into a name in the day fails with the coach wording',
        () async {
      await _putToday([_planned('E1', 'Bench Press'), _planned('Z', 'Row')]);
      final key = 'schedule_${istDateStr(nowWall())}';
      final before = jsonEncode(HiveService.instance.workoutBox.get(key));

      final res = await run(_intent(
          'swap_exercise', {'exerciseId': 'Z', 'newExerciseId': 'E1'}));

      expect(res.success, isFalse);
      expect(res.errorMessage,
          "That exercise is already in today's workout. Pick a different one.");
      expect(jsonEncode(HiveService.instance.workoutBox.get(key)), before);
    });

    test('modify_workout_for_injury applies every planned swap with no repeat',
        () async {
      await _putToday([_planned('Squat', 'Squat'), _planned('Lunge', 'Lunge')]);
      final swaps = await InjurySwapPlanner.instance
          .plan(bodyPart: 'quad', severity: 'mild', daysAhead: 1);
      expect(swaps.length, 2);
      final intent = _intent(
          'modify_workout_for_injury', {'bodyPart': 'quad', 'severity': 'mild'});
      InjurySwapPlanner.instance.cacheSwaps(intent.id, swaps);

      final res = await run(intent);

      expect(res.success, isTrue, reason: '${res.errorMessage}');
      expect((res.data! as Map)['partial_errors'], isNull,
          reason: 'the preview must not promise a swap the guard refuses');
      final row = HiveService.instance.workoutBox
          .get('schedule_${istDateStr(nowWall())}') as Map;
      final names =
          (row['exercises'] as List).map((e) => (e as Map)['exercise_name']).toList();
      expect(names.toSet().length, 2, reason: '$names');
    });

    test('create_custom_template with a repeat shows why and saves nothing',
        () async {
      final res = await run(_intent('create_custom_template', {
        'name': 'Split',
        'days': [
          {
            'dayName': 'Push',
            'exercises': [
              {'exerciseId': 'E1', 'exerciseName': 'Bench Press', 'sets': 3, 'reps': '8'},
              {'exerciseId': 'E1', 'exerciseName': 'Bench Press', 'sets': 3, 'reps': '8'},
            ],
          },
        ],
      }));

      expect(res.success, isFalse);
      expect(res.errorMessage, contains('Bench Press'));
      expect(res.errorMessage, contains('Push'));
      expect(
          HiveService.instance.workoutBox.values
              .whereType<Map>()
              .where((m) => m['type'] == 'template'),
          isEmpty);
    });
  });

  group('CoachSwapSheet', () {
    testWidgets('a name in today\'s workout is shown and cannot be picked',
        (tester) async {
      late Directory dir;
      late ProviderContainer container;
      await tester.runAsync(() async {
        dir = await setUpHiveForTests();
        container = ProviderContainer();
        await _seedLibrary();
        await _putToday([_planned('E1', 'Bench Press'), _planned('E2', 'Seated Row')]);
      });

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CoachSwapSheet())),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      final taken =
          find.text('Seated Row  ·${WardroomCopy.activeAlreadyInWorkoutTag}');
      expect(taken, findsOneWidget);
      await tester.tap(taken);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();
      expect(container.read(pendingToolIntentsProvider), isEmpty,
          reason: 'the taken row selected nothing');

      await tester.ensureVisible(find.text('Calf Raise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calf Raise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SWAP'));
      await tester.pumpAndSettle();
      final intents = container.read(pendingToolIntentsProvider);
      expect(intents.single.payload['newExerciseId'], 'E3');

      await tester.runAsync(() async {
        container.dispose();
        await tearDownHiveForTests(dir);
      });
    });
  });
}
