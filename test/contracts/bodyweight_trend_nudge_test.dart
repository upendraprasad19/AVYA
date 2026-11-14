// Behavioral regression — W2.6: informational bodyweight-trend nudge.
//
// Wires the previously-dead TrainingHistoryAnalyzer.bodyweightTrendSignal()
// (28d-vs-prior-28d mean) into PatternDetector as a LOW-severity insight. Pins:
//   • a meaningful trend on a non-conflict goal surfaces the nudge (low);
//   • DEDUP-ON-OUTCOME: when _weightTrendAlert (14-day, goal-conflict) fires,
//     the nudge does NOT (never two weight cards);
//   • flat / insufficient data → no nudge;
//   • kill-switch disable_bodyweight_trend_nudge → no nudge;
//   • GOAL COVERAGE: every FitnessGoals token (+ empty goal) yields a non-empty
//     message — the nudge is the sole weight signal for 3 of the 5 goals.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_bw_trend');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // Seed healthBox weight rows: list of (daysAgo, kg). Feeds BOTH
  // bodyweightTrendSignal (28d windows) and getWeightHistory (14d, for dedup).
  Future<void> seedWeights(List<List<num>> rows) async {
    final hb = HiveService.instance.healthBox;
    await hb.clear();
    final now = DateTime.now();
    for (final r in rows) {
      final date = now.subtract(Duration(days: r[0].toInt()));
      final iso = date.toIso8601String();
      await hb.put('weight_$iso', {'date': iso, 'weight_kg': r[1].toDouble()});
    }
  }

  Future<void> setGoal(String goal) async {
    await HiveService.instance.userBox.put('profile', {'primary_goal': goal});
  }

  List<CoachingInsight> nudges(List<CoachingInsight> all) =>
      all.where((i) => i.patternId.startsWith('bodyweight_trend')).toList();

  test('meaningful up-trend on a neutral goal surfaces a LOW nudge', () async {
    await setGoal('general_fitness');
    await seedWeights([
      [2, 71.2], [10, 71.2], // recent 28d mean 71.2
      [35, 70.0], [45, 70.0], // prior 28d mean 70.0  → +1.2
    ]);
    final got = nudges(PatternDetector.instance.analyze());
    expect(got, hasLength(1));
    expect(got.first.patternId, 'bodyweight_trend_up');
    expect(got.first.severity, InsightSeverity.low);
    expect(got.first.userMessage.trim(), isNotEmpty);
  });

  test('DEDUP: when _weightTrendAlert fires, the nudge does NOT', () async {
    await setGoal('lose_fat');
    await seedWeights([
      [1, 72.0], [13, 70.5], // 14d delta +1.5 → weight_trend_up fires (HIGH)
      [35, 70.0], [45, 70.0], // 28d mean still up → nudge WOULD be eligible
    ]);
    final all = PatternDetector.instance.analyze();
    expect(all.any((i) => i.patternId == 'weight_trend_up'), isTrue,
        reason: 'the existing goal-conflict alert must fire');
    expect(nudges(all), isEmpty,
        reason: 'the nudge must dedup on the alert outcome (no two weight cards)');
  });

  test('flat / insufficient trend → no nudge', () async {
    await setGoal('general_fitness');
    await seedWeights([
      [2, 70.0], [10, 70.0], [35, 70.0], [45, 70.0], // signal 0.0
    ]);
    expect(nudges(PatternDetector.instance.analyze()), isEmpty);
  });

  test('kill-switch disable_bodyweight_trend_nudge → no nudge', () async {
    await setGoal('general_fitness');
    await seedWeights([
      [2, 71.2], [10, 71.2], [35, 70.0], [45, 70.0],
    ]);
    await HiveService.instance.configBox
        .put('disable_bodyweight_trend_nudge', true);
    expect(nudges(PatternDetector.instance.analyze()), isEmpty);
  });

  test('GOAL COVERAGE: every FitnessGoals token + empty goal gets a message',
      () async {
    // Recent rows all equal (14d delta 0 → _weightTrendAlert never fires, so no
    // dedup interference) but +1.0 above the prior 28d mean → nudge eligible.
    final seed = [
      [2, 71.0], [8, 71.0], [12, 71.0],
      [35, 70.0], [45, 70.0],
    ];
    final messages = <String, String>{};
    for (final goal in [...FitnessGoals.tokens, '']) {
      await setGoal(goal);
      await seedWeights(seed);
      final got = nudges(PatternDetector.instance.analyze());
      expect(got, hasLength(1), reason: 'nudge missing for goal="$goal"');
      expect(got.first.userMessage.trim(), isNotEmpty,
          reason: 'empty message for goal="$goal"');
      expect(got.first.patternId, 'bodyweight_trend_up');
      messages[goal] = got.first.userMessage;
    }
    // The copy must be GOAL-AWARE, not one-size-fits-all: on the SAME up-trend a
    // surplus goal (on-track) reads differently from a deficit goal (review).
    expect(messages['build_muscle'], isNot(messages['lose_fat']),
        reason: 'goal-aware copy must branch on goal, not just interpolate kg');
    expect(messages['strength'], messages['build_muscle'],
        reason: 'surplus goals share the confirming up-trend copy');
  });
}
