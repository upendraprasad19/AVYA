/// Anti-fabrication regression tests for APK Test #4.
///
/// Replays the data shape of the original OBS-3 and OBS-4 fabrications.
/// These tests verify the SNAPSHOT contains the grounding keys + counts
/// the Captain Manual §8 rules need to refuse fabrication.
///
/// OBS-3: user asked "can I do leg day today?" — coach replied
///   "you skip Mondays 100% of the time" against an account with only
///   8 days of data. Impossible to derive a "100% Monday skip rate" from
///   that corpus.
///
/// OBS-4: same session, coach said "your protein intake has been 0g for
///   the last 90 days" — account had only ~14 nutrition logs total.
///   "90 days" is fabrication; the account was 8 days old.
///
/// Live model behavior is verified separately at on-device verification
/// time (post-APK-build). CI tests do not call ai-proxy.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  /// Seeds the Hive state that matched the OBS-3 / OBS-4 user:
  /// - 8-day-old account
  /// - 2 workout logs
  /// - Today has PUSH A scheduled
  /// - 7 nutrition logs in last 7 days (~138g protein/day)
  ///
  /// Returns the snapshot built from that state.
  Map<String, dynamic> _seedObs3StateAndBuild() {
    final base = DateTime.now().subtract(const Duration(days: 8));
    // 2 workout logs (days 8 and 7 ago)
    for (int i = 0; i < 2; i++) {
      final d = base.add(Duration(days: i));
      HiveService.instance.workoutBox.put(
        'wlog_${d.millisecondsSinceEpoch}',
        {
          'date': d.toIso8601String().substring(0, 10),
          'workout_name': 'PUSH A',
          'duration_seconds': 1800,
        },
      );
    }
    // Today's schedule
    final today = DateTime.now().toIso8601String().substring(0, 10);
    HiveService.instance.workoutBox.put('schedule_$today', {
      'type': 'PUSH A',
      'workout_name': 'PUSH A',
      'status': 'pending',
      'exercises': [
        {'name': 'Bench Press', 'sets': 4, 'reps': '8-10', 'weight': 60},
      ],
    });
    // 7 nutrition logs (one per day, last 7 days)
    for (int i = 0; i < 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      HiveService.instance.nutritionBox.put(
        'nlog_${d.millisecondsSinceEpoch}',
        {
          'date': d.toIso8601String().substring(0, 10),
          'total_calories': 2200,
          'total_protein': 138,
        },
      );
    }
    return AiCoachRepository.instance.buildAiContext();
  }

  // ---------------------------------------------------------------------------
  // OBS-3 regression — "you skip Mondays 100% of the time"
  // ---------------------------------------------------------------------------

  group('OBS-3 regression — small data window', () {
    test('data_window_days reflects actual account age (8 days), not invented history',
        () {
      final ctx = _seedObs3StateAndBuild();
      // §8 rule: never claim history beyond data_window_days.
      // An 8-day account cannot produce "100% Monday skip rate."
      expect(ctx['data_window_days'], greaterThanOrEqualTo(7));
      expect(ctx['data_window_days'], lessThanOrEqualTo(9));
    });

    test('workout_logs_count is the actual count (2), enabling honest framing',
        () {
      final ctx = _seedObs3StateAndBuild();
      // Coach must reference "2 of your 2 workouts" — not "100% of Mondays".
      // Having the raw count prevents percentage fabrication.
      expect(ctx['workout_logs_count'], 2);
    });

    test('today_workout exposes PUSH A — coach should not ask user "what is today"',
        () {
      final ctx = _seedObs3StateAndBuild();
      expect(ctx['today_workout'], isNotNull);
      final tw = ctx['today_workout'] as Map;
      expect(tw['type'], 'PUSH A');
      expect(tw['status'], 'pending');
    });

    test('today_workout includes the exercise list', () {
      final ctx = _seedObs3StateAndBuild();
      final tw = ctx['today_workout'] as Map;
      final exercises = tw['exercises'] as List;
      expect(exercises, isNotEmpty);
      expect((exercises.first as Map)['name'], 'Bench Press');
    });

    test('current_plan_summary exposes PUSH A exercises — coach should not ask "what is in leg day"',
        () {
      final ctx = _seedObs3StateAndBuild();
      final summary = ctx['current_plan_summary'] as Map;
      final sessions = summary['weekly_sessions'] as List;
      expect(sessions, isNotEmpty);
      final firstSession = sessions.first as Map;
      expect(firstSession['name'], 'PUSH A');
      expect((firstSession['exercises'] as List), isNotEmpty);
    });

    test('snapshot does NOT include skip-rate or fabricated adherence percentage keys',
        () {
      final ctx = _seedObs3StateAndBuild();
      // None of these aggregate keys should exist. Their presence would invite
      // the model to fabricate by treating them as truth without showing the
      // underlying counts (the original OBS-3 failure mode).
      expect(ctx.containsKey('monday_skip_rate'), false,
          reason: 'monday_skip_rate must not exist — would invite fabricated percentages');
      expect(ctx.containsKey('skip_rate'), false,
          reason: 'skip_rate must not exist — misleading without count context');
      expect(ctx.containsKey('adherence_percentage'), false,
          reason: 'adherence_percentage must not exist — model fabricated 100% from 2 logs');
    });
  });

  // ---------------------------------------------------------------------------
  // OBS-4 regression — "your protein has been 0g for the last 90 days"
  // ---------------------------------------------------------------------------

  group('OBS-4 regression — short nutrition history', () {
    test('nutrition_logs_count_7d is 7 — refutes "90 days" claim from 7 logs',
        () {
      final ctx = _seedObs3StateAndBuild();
      // 90 days of protein data is impossible on an 8-day account.
      // The count forces an honest boundary ("based on your 7 logs this week").
      expect(ctx['nutrition_logs_count_7d'], 7);
    });

    test('data_window_days is <15 — account too young for 90-day claims', () {
      final ctx = _seedObs3StateAndBuild();
      expect(ctx['data_window_days'], lessThan(15));
    });

    test('first_workout_date is set — coach knows when the clock started', () {
      final ctx = _seedObs3StateAndBuild();
      expect(ctx['first_workout_date'], isNotNull);
      expect(ctx['first_workout_date'], isA<String>());
      // Must be an ISO date string (yyyy-MM-dd)
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(ctx['first_workout_date'] as String),
          true, reason: 'first_workout_date must be yyyy-MM-dd');
    });

    test('nutrition keys have window-scoped names (no raw unqualified "trend" in base snapshot)',
        () {
      final ctx = _seedObs3StateAndBuild();
      // Every nutrition-related key in the BASE snapshot must carry its window
      // scope in the name, or be an explicitly whitelisted bare key.
      // Raw 'nutrition_trend' (no window) only exists in enrichContextForQuery
      // (historical queries), not in the base snapshot — so we check it's absent.
      //
      // Accepted base keys:
      //   today_nutrition       — today's macro snapshot (no window needed: "today" is the scope)
      //   nutrition_trend_7d    — 7-day trend (window in name)
      //   nutrition_logs_count_7d — 7-day count (window in name)
      //   meals_today           — today's food list (no window needed)
      // 'nutrition_trend' (no suffix) is NOT expected in the base snapshot.
      final nutritionKeys = ctx.keys.where((k) => k.contains('nutrition')).toList();
      for (final k in nutritionKeys) {
        final isWindowScoped = RegExp(r'\d+[dwm]').hasMatch(k);
        final isWhitelisted = k == 'nutrition_logs_count_7d' ||
            k == 'nutrition_trend_7d' ||
            k == 'today_nutrition'; // today-scoped: no window suffix needed
        expect(isWindowScoped || isWhitelisted, true,
            reason: 'Nutrition key "$k" lacks a window indicator or known whitelist entry — '
                'could mislead the model about history depth');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Fresh user (zero data) — truthful zero-state for all grounding keys
  // ---------------------------------------------------------------------------

  group('Fresh user — truthful zero-state', () {
    test('workout_logs_count is 0, data_window_days is 0, first_workout_date is null',
        () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['workout_logs_count'], 0);
      expect(ctx['data_window_days'], 0);
      expect(ctx['first_workout_date'], isNull);
    });

    test('nutrition_logs_count_7d is 0', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['nutrition_logs_count_7d'], 0);
    });

    test('sleep_logs_count_7d is 0', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['sleep_logs_count_7d'], 0);
    });

    test('today_workout is null when no schedule seeded', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['today_workout'], isNull);
    });

    test('no fabrication-inviting aggregate keys exist on fresh account', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx.containsKey('monday_skip_rate'), false);
      expect(ctx.containsKey('skip_rate'), false);
      expect(ctx.containsKey('adherence_percentage'), false);
    });
  });

  // ---------------------------------------------------------------------------
  // Boundary: exactly 1 workout → still never shows percentages
  // ---------------------------------------------------------------------------

  group('Single-workout account — no percentage keys', () {
    test('1 workout produces a non-zero window and count without fabricated aggregates',
        () {
      final d = DateTime.now().subtract(const Duration(days: 3));
      HiveService.instance.workoutBox.put(
        'wlog_${d.millisecondsSinceEpoch}',
        {
          'date': d.toIso8601String().substring(0, 10),
          'workout_name': 'LEGS A',
          'duration_seconds': 2400,
        },
      );
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['workout_logs_count'], 1);
      expect(ctx['data_window_days'], greaterThan(0));
      expect(ctx.containsKey('monday_skip_rate'), false);
      expect(ctx.containsKey('skip_rate'), false);
      expect(ctx.containsKey('adherence_percentage'), false);
    });
  });
}
