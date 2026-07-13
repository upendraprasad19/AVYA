// Behavioral regression — ④ (Batch 3a): goal-aware cardio finisher default.
//
// Pre-④, CardioFinisher defaulted EVERY cardio-goal user to the blanket mildest
// mini-HIIT (`hate_cardio`) because there is no cardioPreference UI/field. ④
// keys the default finisher SHAPE to the goal. Pins:
//   • lose_fat → HIIT (fullest), general_fitness → cycling, recompose → jump_rope;
//   • build_muscle/strength (cardio==false) → no finisher, unchanged;
//   • kill-switch disable_cardio_goal_default → verbatim pre-④ (mini-HIIT for all).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Minimal 2-day week (finisher attaches to 2 days, so day 0 always gets one).
  List<WeekPlan> week() => [
        WeekPlan(
          weekNumber: 1,
          weekInPhase: 1,
          overloadNotes: '',
          workoutDays: [
            for (var d = 0; d < 2; d++)
              WorkoutDay(
                dayNumber: d + 1,
                name: 'Day ${d + 1}',
                focus: 'full_body',
                exercises: const [],
              ),
          ],
        ),
      ];

  // The finisher attached to day 0 for [goal] with no stored preference.
  List<PlannedExercise> finisherFor(String goal, {List<String>? equip}) {
    final out = CardioFinisher.attach(
      weeks: week(),
      goal: goal,
      cardioPreference: null,
      equipmentList: equip ?? const ['full_gym'],
    );
    return out.first.workoutDays.first.finisher;
  }

  group('goal-aware default (no Hive → kill-switch safe-defaults ON)', () {
    test('lose_fat → HIIT (has the HIIT-only Jump Squats)', () {
      final f = finisherFor('lose_fat');
      expect(f.map((e) => e.exerciseName), contains('Jump Squats'));
    });

    test('general_fitness → cycling', () {
      final f = finisherFor('general_fitness', equip: const ['full_gym']);
      expect(f, hasLength(1));
      expect(f.first.exerciseName, 'Stationary Bike Sprints');
    });

    test('recompose → jump_rope', () {
      final f = finisherFor('recompose');
      expect(f.map((e) => e.exerciseName), ['Jump Rope Intervals']);
    });

    test('build_muscle / strength → no finisher (cardio==false, unchanged)', () {
      expect(finisherFor('build_muscle'), isEmpty);
      expect(finisherFor('strength'), isEmpty);
    });

    test('non-vacuity: lose_fat is NOT the old mini-HIIT default', () {
      // Pre-④, lose_fat got mini-HIIT (first = "High Knees", no Jump Squats).
      final f = finisherFor('lose_fat');
      expect(f.first.exerciseName, isNot('High Knees'));
    });
  });

  group('kill-switch (Hive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('test_cardio_killswitch');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      await Hive.openBox(HiveService.configBoxName);
      HiveService.instance.markInitializedForTests();
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('disable_cardio_goal_default=true → lose_fat reverts to mini-HIIT', () async {
      await HiveService.instance.configBox
          .put('disable_cardio_goal_default', true);
      final f = finisherFor('lose_fat');
      // Mini-HIIT: [High Knees, Burpees, Mountain Climbers] — no Jump Squats.
      expect(f.first.exerciseName, 'High Knees');
      expect(f.map((e) => e.exerciseName), isNot(contains('Jump Squats')));
    });

    test('flag unset → goal-aware ON (lose_fat = HIIT)', () {
      final f = finisherFor('lose_fat');
      expect(f.map((e) => e.exerciseName), contains('Jump Squats'));
    });
  });
}
