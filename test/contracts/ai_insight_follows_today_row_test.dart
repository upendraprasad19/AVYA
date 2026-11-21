// test/contracts/ai_insight_follows_today_row_test.dart
//
// Regression for the Home insight going stale after a day swap (founder
// observation 2026-10-01; plan docs/plans/swap-cross-device-reconcile.md v6).
//
// Writer: every caller that changes today's schedule row and then
// invalidates todayWorkoutProvider (21 sites, incl. the day-swap batch at
// lib/features/train/providers/day_swap_provider.dart:75-82).
// Reader: AiInsightNotifier (lib/features/home/providers/home_provider.dart).
//
// Recurrence of b3c9d4 / F5 (a forgotten entry in an invalidation list): the
// insight read today's row with ref.read, so it refreshed only when a caller
// ALSO remembered to invalidate aiInsightProvider. The fix derives the
// insight from todayWorkoutProvider instead of adding one more list entry.
//
// Group 1 fails on the pre-fix code; group 2 passes on both (byte-identical
// sentences) and reads real Hive rows with NO todayWorkoutProvider override,
// because the pre-fix insight ignores such an override.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_insight_today_row_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.workoutBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  String todayKey() => 'schedule_${formatDateKey(DateTime.now())}';

  Future<void> putToday(Map<String, dynamic> row) =>
      HiveService.instance.workoutBox.put(todayKey(), row);

  ProviderContainer newContainer() {
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('ai-insight-test-user'),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  List<Map<String, dynamic>> threeExercises() => [
        {'name': 'A'},
        {'name': 'B'},
        {'name': 'C'},
      ];

  group('insight follows todayWorkoutProvider (regression)', () {
    test('invalidating ONLY todayWorkoutProvider refreshes the insight', () async {
      await putToday({
        'workout_name': 'Push + Core',
        'type': 'workout',
        'status': 'planned',
        'exercises': threeExercises(),
      });
      final c = newContainer();
      expect(c.read(aiInsightProvider), contains('Push + Core'));

      // A day swap (or any writer) rewrites today's row, then refreshes the
      // Today card — and nothing else.
      await putToday({
        'workout_name': 'Pull + Core',
        'type': 'workout',
        'status': 'planned',
        'exercises': threeExercises(),
      });
      c.invalidate(todayWorkoutProvider);

      final insight = c.read(aiInsightProvider);
      expect(insight, contains('Pull + Core'),
          reason: 'the insight must follow the Today card, not a stale read');
      expect(insight, isNot(contains('Push + Core')));
    });
  });

  group('sentences unchanged (byte-identical on main and on the fix)', () {
    test('planned workout', () async {
      await putToday({
        'workout_name': 'Leg Day',
        'type': 'workout',
        'status': 'planned',
        'exercises': threeExercises(),
      });
      expect(newContainer().read(aiInsightProvider),
          'Leg Day is scheduled for today — 3 exercises. Ready when you are!');
    });

    test('completed workout', () async {
      await putToday({
        'workout_name': 'Leg Day',
        'type': 'workout',
        'status': 'completed',
        'exercises': threeExercises(),
      });
      expect(newContainer().read(aiInsightProvider),
          'Leg Day completed today — 3 exercises. Great work 💪');
    });

    test('rest day', () async {
      await putToday({'workout_name': 'Rest', 'type': 'rest', 'status': 'rest'});
      expect(newContainer().read(aiInsightProvider),
          'Rest day! You have earned it! 🎉');
    });

    test('logged row, OI-126 flag OFF', () async {
      await putToday({
        'workout_name': 'Chat Workout',
        'type': 'logged',
        'status': 'planned',
        'exercises': threeExercises(),
      });
      expect(newContainer().read(aiInsightProvider),
          'No workout scheduled for today. A good day for active recovery!');
    });

    test('logged row, OI-126 flag ON', () async {
      await HiveService.instance.configBox
          .put('enable_logged_counts_as_phase_training_day', true);
      await putToday({
        'workout_name': 'Chat Workout',
        'type': 'logged',
        'status': 'planned',
        'exercises': threeExercises(),
      });
      expect(newContainer().read(aiInsightProvider),
          'Chat Workout is scheduled for today — 3 exercises. Ready when you are!');
    });

    test('terminal moved row reads as no row', () async {
      await putToday({
        'workout_name': 'Leg Day',
        'type': 'workout',
        'status': 'moved',
        'exercises': threeExercises(),
      });
      expect(newContainer().read(aiInsightProvider),
          'No workout scheduled for today. A good day for active recovery!');
    });

    test('no row', () async {
      expect(newContainer().read(aiInsightProvider),
          'No workout scheduled for today. A good day for active recovery!');
    });
  });
}
