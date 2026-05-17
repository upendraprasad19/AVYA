// Regression test for audit-2026-05-17 OI-07-FOLLOWUP — top-level
// aliases for cron Edge Function readers.
//
// OI-07's snapshot_contract.yaml enumerated 11 orphan readers — cron
// functions (morning-alert, streak-guardian, protein-gap-alert) reading
// fields by name from `user_daily_snapshots.snapshot_json` that the
// writer (`AiCoachRepository.buildAiContext`) did NOT emit at the
// expected path. Silent personalisation degradation since the cron
// functions null-check + fall through to default templates.
//
// Fix: writer emits top-level aliases for the 11 expected fields.
// This test pins the alias contract via source-grep so a future
// refactor can't silently strip them and re-create the orphan-reader
// drift.
//
// closes-diagnose: 2026-05-17-orphan-reader-aliases-7faa3b
// closes-oi: OI-07-FOLLOWUP

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/repositories/ai_coach_repository.dart')
        .readAsStringSync();
  });

  group('OI-07-FOLLOWUP — top-level alias emission in buildAiContext', () {
    test('writer emits current_streak_weeks at top level', () {
      expect(
        RegExp(r"'current_streak_weeks':\s*progress\['current_streak_weeks'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_streak_weeks '
            '(top-level). Writer must emit the top-level alias alongside the '
            'nested progress.current_streak_weeks for backward compat.',
      );
    });

    test('writer emits current_streak_days at top level', () {
      expect(
        src.contains("'current_streak_days':"),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_streak_days. '
            'Computed as streak_weeks * 7 (no canonical Hive field exists).',
      );
    });

    test('writer emits total_workouts_done at top level', () {
      expect(
        RegExp(r"'total_workouts_done':\s*progress\['total_workouts_done'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert reads snap.total_workouts_done at top level.',
      );
    });

    test('writer emits current_weight_kg + target_weight_kg at top level', () {
      expect(
        RegExp(r"'current_weight_kg':\s*profile\['current_weight_kg'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_weight_kg.',
      );
      expect(
        RegExp(r"'target_weight_kg':\s*profile\['target_weight_kg'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.target_weight_kg.',
      );
    });

    test('writer emits today_workout_name + recent_pr_* at top level', () {
      expect(src.contains("'today_workout_name': _topLevelTodayWorkoutName()"),
          isTrue,
          reason: 'morning-alert reads snap.today_workout_name.');
      expect(
        src.contains("'recent_pr_exercise': _topLevelRecentPrField"),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.recent_pr_exercise.',
      );
      expect(
        src.contains("'recent_pr_weight': _topLevelRecentPrField"),
        isTrue,
        reason: 'morning-alert reads snap.recent_pr_weight.',
      );
    });

    test('writer emits yesterday_calories + daily_calorie_target + daily_targets',
        () {
      expect(src.contains("'yesterday_calories': _topLevelYesterdayCalories()"),
          isTrue,
          reason: 'morning-alert reads snap.yesterday_calories.');
      expect(src.contains("'daily_calorie_target':"), isTrue,
          reason: 'morning-alert reads snap.daily_calorie_target.');
      expect(
        src.contains("'daily_targets':") &&
            src.contains("'protein':"),
        isTrue,
        reason: 'protein-gap-alert reads snap.daily_targets.protein.',
      );
    });

    test('writer helpers are present + private', () {
      // All three helpers must exist and be private (underscore prefix)
      // — they're implementation details of buildAiContext.
      expect(src.contains('String? _topLevelTodayWorkoutName()'), isTrue);
      expect(
        src.contains('dynamic _topLevelRecentPrField(String field)'),
        isTrue,
      );
      expect(src.contains('int _topLevelYesterdayCalories()'), isTrue);
    });
  });
}
