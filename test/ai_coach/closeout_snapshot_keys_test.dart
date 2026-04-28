// test/ai_coach/closeout_snapshot_keys_test.dart
//
// Tests for APK Test #4 closeout snapshot keys — 6 keys that were listed
// in the audit but missed during Plan A execution:
//
//   pr_timeline_summary  (P1 G-10) — top 5 PRs with set_date
//   goal_changed_at      (P1)      — null-safe profile read
//   body_measurements    (P2)      — latest per type from healthBox
//   onboarding_completed_at (P2)  — profile field from onboarding
//   phase_transitions    (P2)      — last 3 from progress.phase_history
//   recent_meal_deletes  (P1)      — last 5 from nutritionBox['recent_deletes']

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_closeout_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.userBox.clear();
  });

  // ── pr_timeline_summary ──────────────────────────────────────────────────

  group('pr_timeline_summary', () {
    test('returns zero total and empty list when no PR logs', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['pr_timeline_summary'] as Map;
      expect(summary['total_prs'], 0);
      expect((summary['recent_prs'] as List), isEmpty);
    });

    test('counts only is_pr=true entries in total_prs', () async {
      await HiveService.instance.workoutBox.put('exlog_100', {
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 60.0,
        'reps_completed': 8,
        'date': '2026-04-15',
      });
      await HiveService.instance.workoutBox.put('exlog_200', {
        'exercise_name': 'Squat',
        'is_pr': false,  // NOT a PR — should not count
        'weight_kg': 80.0,
        'reps_completed': 6,
        'date': '2026-04-20',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['pr_timeline_summary'] as Map;
      expect(summary['total_prs'], 1);
      expect((summary['recent_prs'] as List).length, 1);
    });

    test('returns top 5 by recency with set_date and most-recent first', () async {
      await HiveService.instance.workoutBox.put('exlog_1', {
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 60.0,
        'reps_completed': 8,
        'date': '2026-04-15',
      });
      await HiveService.instance.workoutBox.put('exlog_2', {
        'exercise_name': 'Squat',
        'is_pr': true,
        'weight_kg': 80.0,
        'reps_completed': 6,
        'date': '2026-04-20',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['pr_timeline_summary'] as Map;
      expect(summary['total_prs'], 2);
      final recent = summary['recent_prs'] as List;
      expect(recent.length, 2);
      // Most recent first
      expect((recent.first as Map)['exercise'], 'Squat');
      expect((recent.first as Map)['set_date'], '2026-04-20');
      expect((recent.last as Map)['exercise'], 'Bench Press');
      expect((recent.last as Map)['set_date'], '2026-04-15');
    });

    test('deduplicates by exercise name keeping most-recent date', () async {
      // Two PR entries for Bench Press — newer should win
      await HiveService.instance.workoutBox.put('exlog_a1', {
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 55.0,
        'reps_completed': 8,
        'date': '2026-04-01',
      });
      await HiveService.instance.workoutBox.put('exlog_a2', {
        'exercise_name': 'Bench Press',
        'is_pr': true,
        'weight_kg': 62.5,
        'reps_completed': 6,
        'date': '2026-04-20',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['pr_timeline_summary'] as Map;
      // total_prs counts both raw PR events (2), but deduped list has 1 exercise
      expect(summary['total_prs'], 2);
      final recent = summary['recent_prs'] as List;
      expect(recent.length, 1);
      expect((recent.first as Map)['set_date'], '2026-04-20');
      expect((recent.first as Map)['weight'], 62.5);
    });

    test('caps recent_prs at 5 entries', () async {
      for (var i = 1; i <= 7; i++) {
        await HiveService.instance.workoutBox.put('exlog_cap$i', {
          'exercise_name': 'Exercise $i',
          'is_pr': true,
          'weight_kg': i * 10.0,
          'reps_completed': 8,
          'date': '2026-04-${i.toString().padLeft(2, '0')}',
        });
      }

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['pr_timeline_summary'] as Map;
      expect((summary['recent_prs'] as List).length, 5);
    });
  });

  // ── goal_changed_at ──────────────────────────────────────────────────────

  group('goal_changed_at', () {
    test('returns null when no profile or field not present', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['goal_changed_at'], isNull);
    });

    test('returns value from goal_changed_at field in profile', () async {
      await HiveService.instance.userBox.put('profile', {
        'primary_goal': 'lose_fat',
        'goal_changed_at': '2026-04-22T10:30:00.000Z',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['goal_changed_at'], '2026-04-22T10:30:00.000Z');
    });

    test('falls back to primary_goal_updated_at when goal_changed_at absent',
        () async {
      await HiveService.instance.userBox.put('profile', {
        'primary_goal': 'build_muscle',
        'primary_goal_updated_at': '2026-04-10T08:00:00.000Z',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['goal_changed_at'], '2026-04-10T08:00:00.000Z');
    });
  });

  // ── body_measurements ────────────────────────────────────────────────────

  group('body_measurements', () {
    test('returns empty map when no measurements recorded', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['body_measurements'], isEmpty);
    });

    test('returns latest chest and waist from single measurement day', () async {
      await HiveService.instance.healthBox.put('measurement_2026-04-10', {
        'date': '2026-04-10',
        'chest': 90.0,
        'waist': 85.0,
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final m = ctx['body_measurements'] as Map;
      expect(m['chest'], 90.0);
      expect(m['waist'], 85.0);
      expect(m.containsKey('hips'), isFalse);
      expect(m.containsKey('arms'), isFalse);
    });

    test('picks newer value when same type exists on multiple dates', () async {
      await HiveService.instance.healthBox.put('measurement_2026-04-10', {
        'date': '2026-04-10',
        'chest': 90.0,
        'waist': 85.0,
      });
      await HiveService.instance.healthBox.put('measurement_2026-04-20', {
        'date': '2026-04-20',
        'waist': 82.0, // newer waist measurement
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final m = ctx['body_measurements'] as Map;
      expect(m['chest'], 90.0);   // only one chest entry
      expect(m['waist'], 82.0);   // newer waist wins
    });

    test('collects all 4 measurement types', () async {
      await HiveService.instance.healthBox.put('measurement_2026-04-25', {
        'date': '2026-04-25',
        'chest': 92.0,
        'waist': 80.0,
        'hips': 95.0,
        'arms': 35.0,
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final m = ctx['body_measurements'] as Map;
      expect(m['chest'], 92.0);
      expect(m['waist'], 80.0);
      expect(m['hips'], 95.0);
      expect(m['arms'], 35.0);
    });
  });

  // ── onboarding_completed_at ──────────────────────────────────────────────

  group('onboarding_completed_at', () {
    test('returns null when no profile stored', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['onboarding_completed_at'], isNull);
    });

    test('returns null when profile lacks onboarding_completed_at field',
        () async {
      await HiveService.instance.userBox.put('profile', {
        'primary_goal': 'lose_fat',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['onboarding_completed_at'], isNull);
    });

    test('reads onboarding_completed_at from profile', () async {
      await HiveService.instance.userBox.put('profile', {
        'onboarding_completed_at': '2026-04-19T10:00:00Z',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['onboarding_completed_at'], '2026-04-19T10:00:00Z');
    });
  });

  // ── phase_transitions ────────────────────────────────────────────────────

  group('phase_transitions', () {
    test('returns empty list when no progress stored', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['phase_transitions'], isEmpty);
    });

    test('returns empty list when progress has no phase_history', () async {
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 1,
        'total_workouts_done': 20,
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['phase_transitions'], isEmpty);
    });

    test('returns up to 3 transitions from phase_history', () async {
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 3,
        'phase_history': [
          {'from_phase': 1, 'to_phase': 2, 'transitioned_at': '2026-03-01'},
          {'from_phase': 2, 'to_phase': 3, 'transitioned_at': '2026-04-01'},
        ],
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final transitions = ctx['phase_transitions'] as List;
      expect(transitions.length, 2);
      expect((transitions.first as Map)['from_phase'], 1);
      expect((transitions.first as Map)['to_phase'], 2);
      expect((transitions.first as Map)['transitioned_at'], '2026-03-01');
    });

    test('caps at 3 entries when history has more', () async {
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 5,
        'phase_history': [
          {'from_phase': 1, 'to_phase': 2, 'transitioned_at': '2026-01-01'},
          {'from_phase': 2, 'to_phase': 3, 'transitioned_at': '2026-02-01'},
          {'from_phase': 3, 'to_phase': 4, 'transitioned_at': '2026-03-01'},
          {'from_phase': 4, 'to_phase': 5, 'transitioned_at': '2026-04-01'},
        ],
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final transitions = ctx['phase_transitions'] as List;
      expect(transitions.length, 3);
    });
  });

  // ── recent_meal_deletes ──────────────────────────────────────────────────

  group('recent_meal_deletes', () {
    test('returns empty list when nothing deleted', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['recent_meal_deletes'], isEmpty);
    });

    test('returns empty list when recent_deletes key is not a list', () async {
      await HiveService.instance.nutritionBox.put('recent_deletes', 'broken');

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['recent_meal_deletes'], isEmpty);
    });

    test('round-trips after deletion audit entry is written', () async {
      await HiveService.instance.nutritionBox.put('recent_deletes', [
        {
          'food_name': 'Biryani',
          'deleted_at': '2026-04-25T13:00:00Z',
          'calories': 650,
          'meal_type': 'lunch',
          'logged_date': '2026-04-25',
        },
      ]);

      final ctx = AiCoachRepository.instance.buildAiContext();
      final deletes = ctx['recent_meal_deletes'] as List;
      expect(deletes.length, 1);
      expect((deletes.first as Map)['food_name'], 'Biryani');
      expect((deletes.first as Map)['calories'], 650);
    });

    test('caps at 5 entries from the read side', () async {
      final entries = List.generate(
        8,
        (i) => {
          'food_name': 'Food $i',
          'deleted_at': '2026-04-25T1$i:00:00Z',
          'calories': 100 + i,
          'meal_type': 'lunch',
          'logged_date': '2026-04-25',
        },
      );
      await HiveService.instance.nutritionBox.put('recent_deletes', entries);

      final ctx = AiCoachRepository.instance.buildAiContext();
      final deletes = ctx['recent_meal_deletes'] as List;
      expect(deletes.length, 5);
    });
  });
}
