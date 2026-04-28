// test/ai_coach/snapshot_keys_test.dart
//
// TDD tests for APK Test #4 / Task A4+A6: snapshot keys added to
// AiCoachRepository.buildAiContext().
//
// A4 keys:
//   today_workout     — Map {type, status, exercises} or null if no schedule
//   yesterday_workout — Map {type, status} or null if no schedule
//   week_lookahead    — List of 7 {day, date, type, status}; REST for missing days
//
// A6 keys:
//   sleep_7d                  — List of {date, hours} ascending, last 7 days
//   water_7d                  — List of {date, ml} ascending, last 7 days
//   streak_freezes_available  — int, default 0
//   streak_freezes_refill_date — string ISO or null
//   subscription              — {tier, expires_at, plan, auto_renew}
//   current_rank              — {code, display, earned_at, total_workouts}
//   next_rank                 — {code, display, requirements, remaining, binding_constraint} or null
//   eta_next_promotion        — {at_current_cadence, at_plan_cadence} or null
//   cadence                   — {workouts_per_week_4w, plan_target}

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/train/services/active_workout_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a4_');
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
    await HiveService.instance.userBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.configBox.clear();
  });

  String todayIso() => DateTime.now().toIso8601String().substring(0, 10);
  String yesterdayIso() => DateTime.now()
      .subtract(const Duration(days: 1))
      .toIso8601String()
      .substring(0, 10);

  group('today_workout', () {
    test('returns null when no schedule for today', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['today_workout'], isNull);
    });

    test('reflects scheduled session with type, status, and exercises', () async {
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'type': 'PUSH A',
        'status': 'pending',
        'workout_name': 'PUSH A',
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': 4,
            'reps': '8-10',
            'weight': 60,
            'logging_type': 'weight_reps',
          },
          {
            'name': 'OHP',
            'sets': 3,
            'reps': '6-8',
            'weight': 45,
            'logging_type': 'weight_reps',
          },
        ],
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['today_workout'], isNotNull);
      final tw = ctx['today_workout'] as Map;
      expect(tw['type'], 'PUSH A');
      expect(tw['status'], 'pending');
      expect(tw['exercises'], isList);
      expect((tw['exercises'] as List).length, 2);
    });

    test('falls back to workout_name if type missing', () async {
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'workout_name': 'LEGS B',
        'status': 'completed',
        'exercises': [],
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect((ctx['today_workout'] as Map)['type'], 'LEGS B');
    });
  });

  group('yesterday_workout', () {
    test('returns null when no schedule for yesterday', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['yesterday_workout'], isNull);
    });

    test('reports type and status for yesterday', () async {
      await HiveService.instance.workoutBox.put('schedule_${yesterdayIso()}', {
        'type': 'PULL A',
        'status': 'completed',
        'workout_name': 'PULL A',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['yesterday_workout'], isNotNull);
      expect((ctx['yesterday_workout'] as Map)['type'], 'PULL A');
      expect((ctx['yesterday_workout'] as Map)['status'], 'completed');
    });
  });

  group('week_lookahead', () {
    test('returns 7 entries (today + next 6 days)', () async {
      // Seed 2 entries, leave 5 as rest
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'type': 'PUSH A',
        'status': 'pending',
        'workout_name': 'PUSH A',
      });
      final tomorrow = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      await HiveService.instance.workoutBox.put('schedule_$tomorrow', {
        'type': 'PULL A',
        'status': 'pending',
        'workout_name': 'PULL A',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['week_lookahead'], isList);
      final week = ctx['week_lookahead'] as List;
      expect(week.length, 7);

      final first = week.first as Map;
      expect(first['date'], todayIso());
      expect(first['type'], 'PUSH A');
      expect(first['status'], 'pending');

      // Days without schedule should be REST
      final third = week[2] as Map;
      expect(third['type'], 'REST');
      expect(third['status'], 'rest');
    });

    test('each entry has day, date, type, status fields', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      final week = ctx['week_lookahead'] as List;
      for (final entry in week) {
        final e = entry as Map;
        expect(e.keys, containsAll(['day', 'date', 'type', 'status']));
        expect(e['day'], isA<String>());
        expect(e['date'], isA<String>());
      }
    });
  });

  group('current_plan_summary', () {
    test('reads phase + week from progress dict, days_per_week from profile',
        () async {
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 2,
        'current_week': 3,
      });
      await HiveService.instance.userBox.put('profile', {
        'days_per_week': 5,
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['current_plan_summary'] as Map;
      expect(summary['phase'], 2);
      expect(summary['week'], 3);
      expect(summary['days_per_week'], 5);
    });

    test('uses defaults when progress/profile missing', () async {
      await HiveService.instance.userBox.delete('progress');
      await HiveService.instance.userBox.delete('profile');

      final ctx = AiCoachRepository.instance.buildAiContext();
      final summary = ctx['current_plan_summary'] as Map;
      expect(summary['phase'], 1);
      expect(summary['week'], 1);
      expect(summary['days_per_week'], 4);
    });

    test('weekly_sessions deduplicates by session name', () async {
      final today = DateTime.now();
      // Day 0: PUSH A
      await HiveService.instance.workoutBox.put(
        'schedule_${today.toIso8601String().substring(0, 10)}',
        {
          'type': 'PUSH A',
          'workout_name': 'PUSH A',
          'status': 'pending',
          'exercises': [
            {'name': 'Bench Press', 'sets': 4, 'reps': '8-10', 'weight': 60},
          ],
        },
      );
      // Day 1: PULL A
      final d1 = today.add(const Duration(days: 1));
      await HiveService.instance.workoutBox.put(
        'schedule_${d1.toIso8601String().substring(0, 10)}',
        {
          'type': 'PULL A',
          'workout_name': 'PULL A',
          'status': 'pending',
          'exercises': [
            {'name': 'Lat Pulldown', 'sets': 4, 'reps': '8', 'weight': 50},
          ],
        },
      );
      // Day 2: PUSH A again (duplicate — should NOT appear twice)
      final d2 = today.add(const Duration(days: 2));
      await HiveService.instance.workoutBox.put(
        'schedule_${d2.toIso8601String().substring(0, 10)}',
        {
          'type': 'PUSH A',
          'workout_name': 'PUSH A',
          'status': 'pending',
          'exercises': [
            {'name': 'Bench Press', 'sets': 4, 'reps': '8-10', 'weight': 60},
          ],
        },
      );

      final ctx = AiCoachRepository.instance.buildAiContext();
      final sessions =
          (ctx['current_plan_summary']['weekly_sessions'] as List);
      final names = sessions.map((s) => (s as Map)['name']).toList();
      expect(names, contains('PUSH A'));
      expect(names, contains('PULL A'));
      expect(names.where((n) => n == 'PUSH A').length, 1); // dedup
      expect(names.length, 2);
    });

    test('skips REST days', () async {
      // No schedule entries for today + 6 days = all rest
      final ctx = AiCoachRepository.instance.buildAiContext();
      final sessions =
          (ctx['current_plan_summary']['weekly_sessions'] as List);
      expect(sessions, isEmpty);
    });

    test('exercise list includes name, sets, reps, weight only', () async {
      final today = DateTime.now();
      await HiveService.instance.workoutBox.put(
        'schedule_${today.toIso8601String().substring(0, 10)}',
        {
          'type': 'PUSH A',
          'workout_name': 'PUSH A',
          'status': 'pending',
          'exercises': [
            {
              'name': 'Bench Press',
              'sets': 4,
              'reps': '8-10',
              'weight': 60,
              'logging_type': 'weight_reps', // should NOT be in summary
              'rest_seconds': 120, // should NOT be in summary
            },
          ],
        },
      );

      final ctx = AiCoachRepository.instance.buildAiContext();
      final sessions = ctx['current_plan_summary']['weekly_sessions'] as List;
      final firstExercise = (sessions.first as Map)['exercises'][0] as Map;
      expect(firstExercise.keys, containsAll(['name', 'sets', 'reps', 'weight']));
      expect(firstExercise['logging_type'], isNull);
      expect(firstExercise['rest_seconds'], isNull);
    });
  });

  // ── A6 tests ──────────────────────────────────────────────────────────────

  group('sleep_7d', () {
    test('returns list of {date, hours} for last 7 days, ascending by date',
        () async {
      for (int i = 0; i < 5; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        await HiveService.instance.healthBox.put(
          'sleep_log_$dateStr',
          {'date': dateStr, 'sleep_hours': 7.0 + i * 0.1},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['sleep_7d'], isList);
      final s = ctx['sleep_7d'] as List;
      expect(s.length, 5);
      // Ascending by date
      final dates = s.map((e) => (e as Map)['date'] as String).toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });

    test('each entry has date and hours keys', () async {
      final d = DateTime.now();
      final dateStr = d.toIso8601String().substring(0, 10);
      await HiveService.instance.healthBox.put(
        'sleep_log_$dateStr',
        {'date': dateStr, 'sleep_hours': 7.5},
      );
      final ctx = AiCoachRepository.instance.buildAiContext();
      final s = ctx['sleep_7d'] as List;
      final entry = s.first as Map;
      expect(entry['date'], dateStr);
      expect(entry['hours'], closeTo(7.5, 0.01));
    });

    test('excludes sleep logs older than 7 days', () async {
      final old = DateTime.now().subtract(const Duration(days: 30));
      final oldStr = old.toIso8601String().substring(0, 10);
      await HiveService.instance.healthBox.put(
        'sleep_log_$oldStr',
        {'date': oldStr, 'sleep_hours': 8.0},
      );
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['sleep_7d'], isEmpty);
    });

    test('returns empty list when no sleep logs exist', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['sleep_7d'], isEmpty);
    });
  });

  group('water_7d', () {
    test('returns list of {date, ml} for last 7 days, ascending by date',
        () async {
      for (int i = 0; i < 3; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        await HiveService.instance.healthBox.put('water_ml_$dateStr', 2000 + i * 100);
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['water_7d'], isList);
      final w = ctx['water_7d'] as List;
      expect(w.length, 3);
      final dates = w.map((e) => (e as Map)['date'] as String).toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });

    test('excludes water logs older than 7 days', () async {
      final old = DateTime.now().subtract(const Duration(days: 10));
      final oldStr = old.toIso8601String().substring(0, 10);
      await HiveService.instance.healthBox.put('water_ml_$oldStr', 1500);
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['water_7d'], isEmpty);
    });
  });

  group('streak_freezes', () {
    test('reads from progress dict with defaults', () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 2,
        'streak_freezes_last_refill': '2026-04-21',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['streak_freezes_available'], 2);
      expect(ctx['streak_freezes_refill_date'], '2026-04-21');
    });

    test('defaults to 0 / null when progress missing', () async {
      await HiveService.instance.userBox.delete('progress');
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['streak_freezes_available'], 0);
      expect(ctx['streak_freezes_refill_date'], isNull);
    });

    test('defaults to 0 when streak_freezes_available key absent', () async {
      await HiveService.instance.userBox.put('progress', <String, dynamic>{});
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['streak_freezes_available'], 0);
    });
  });

  group('subscription', () {
    test('reflects free tier when isPro false', () async {
      await HiveService.instance.configBox.put('isPro', false);
      final ctx = AiCoachRepository.instance.buildAiContext();
      final sub = ctx['subscription'] as Map;
      expect(sub['tier'], 'free');
    });

    test('reflects pro tier when isPro true with expiresAt', () async {
      final expiry = DateTime.now().add(const Duration(days: 90));
      await HiveService.instance.configBox.put('isPro', true);
      await HiveService.instance.configBox.put('expiresAt', expiry.toIso8601String());
      await HiveService.instance.configBox.put('plan', 'monthly');
      final ctx = AiCoachRepository.instance.buildAiContext();
      final sub = ctx['subscription'] as Map;
      expect(sub['tier'], 'pro');
      expect(sub['expires_at'], isNotNull);
      expect(sub['plan'], 'monthly');
    });

    test('has all required keys', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      final sub = ctx['subscription'] as Map;
      expect(sub.keys, containsAll(['tier', 'expires_at', 'plan', 'auto_renew']));
    });

    test('free tier when configBox empty', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      final sub = ctx['subscription'] as Map;
      expect(sub['tier'], 'free');
    });
  });

  group('current_rank', () {
    test('defaults to SD2 for fresh user with no profile', () async {
      await HiveService.instance.userBox.delete('profile');
      final ctx = AiCoachRepository.instance.buildAiContext();
      final r = ctx['current_rank'] as Map;
      expect(r['code'], 'SD2');
      expect(r['display'], 'Seaman 2nd Class');
    });

    test('reads stored rank code from profile', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'PO',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      final r = ctx['current_rank'] as Map;
      expect(r['code'], 'PO');
      expect(r['display'], 'Petty Officer');
    });

    test('includes total_workouts count', () async {
      for (int i = 0; i < 5; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {'date': d.toIso8601String().substring(0, 10), 'workout_name': 'PUSH A'},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      final r = ctx['current_rank'] as Map;
      expect(r['total_workouts'], 5);
    });
  });

  group('next_rank', () {
    test('returns next ladder entry with binding_constraint for SD2',
        () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'SD2',
      });
      // SD2 → SD1 gate: streakAtLeast:7, minWeeksSinceSignup:1 (no workouts gate)
      for (int i = 0; i < 2; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {'date': d.toIso8601String().substring(0, 10), 'workout_name': 'PUSH A'},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      final next = ctx['next_rank'] as Map;
      expect(next['code'], 'SD1');
      // SD1 gate has streak_days:7 requirement (canonical kRankGates)
      expect(next['requirements']['streak_days'], 7);
      expect(next['binding_constraint'], isA<String>());
    });

    test('returns null at top rank Capt', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'Capt',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['next_rank'], isNull);
    });

    test('remaining map exists and has keys for SD2 → SD1 gate', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'SD2',
      });
      // SD1 gate: streakAtLeast:7, minWeeksSinceSignup:1 (no workouts gate).
      // 10 workouts seeded just to confirm workouts don't appear in remaining.
      for (int i = 0; i < 10; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {'date': d.toIso8601String().substring(0, 10), 'workout_name': 'X'},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      final next = ctx['next_rank'] as Map;
      final remaining = next['remaining'] as Map;
      // SD1 has streak_days and weeks gates — no workouts gate
      expect(remaining.containsKey('workouts'), isFalse);
      // streak_days must be present (7 required; 0 current — conservative)
      expect(remaining['streak_days'], isA<int>());
    });
  });

  group('cadence', () {
    test('plan_target reads days_per_week from profile (default 4)', () async {
      await HiveService.instance.userBox.put('profile', {'days_per_week': 5});
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect((ctx['cadence'] as Map)['plan_target'], 5);
    });

    test('plan_target defaults to 4 when profile missing', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect((ctx['cadence'] as Map)['plan_target'], 4);
    });

    test('workouts_per_week_4w computed from last 28 days workout count / 4',
        () async {
      // Seed 8 workouts across last 28 days = 2/week
      for (int i = 0; i < 8; i++) {
        final d = DateTime.now().subtract(Duration(days: i * 3));
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {'date': d.toIso8601String().substring(0, 10), 'workout_name': 'X'},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      final cadence = ctx['cadence'] as Map;
      expect(cadence['workouts_per_week_4w'], closeTo(2.0, 0.5));
    });

    test('workouts_per_week_4w is 0.0 with no workouts', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect((ctx['cadence'] as Map)['workouts_per_week_4w'], 0.0);
    });
  });

  group('eta_next_promotion', () {
    test('returns null at top rank Capt', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'Capt',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['eta_next_promotion'], isNull);
    });

    test('computes days at plan cadence when no workouts yet', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'SD2',
        'days_per_week': 4,
      });
      // No workouts seeded — SD1 gate is streakAtLeast:7, minWeeks:1
      final ctx = AiCoachRepository.instance.buildAiContext();
      final eta = ctx['eta_next_promotion'] as Map;
      expect(eta['at_plan_cadence'], isNotNull);
      final atPlan = eta['at_plan_cadence'] as Map;
      expect(atPlan['days'], isA<int>());
    });

    test('computes days at current cadence and plan cadence', () async {
      await HiveService.instance.userBox.put('profile', {
        'current_rank_code': 'SD2',
        'days_per_week': 4,
      });
      // 4 workouts in last 28 days = 1/wk; SD1 gate: streakAtLeast:7
      for (int i = 0; i < 4; i++) {
        final d = DateTime.now().subtract(Duration(days: i * 7));
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {'date': d.toIso8601String().substring(0, 10), 'workout_name': 'X'},
        );
      }
      final ctx = AiCoachRepository.instance.buildAiContext();
      final eta = ctx['eta_next_promotion'] as Map;
      expect(eta['at_current_cadence'], isNotNull);
      expect(eta['at_plan_cadence'], isNotNull);
      expect((eta['at_current_cadence'] as Map)['days'], isA<int>());
      expect((eta['at_plan_cadence'] as Map)['days'], isA<int>());
      expect((eta['at_current_cadence'] as Map)['date'], isA<String>());
    });
  });

  // APK Test #4 / A7: active_workout snapshot key
  // Exposes mid-workout state so Captain can answer set-advice questions.
  group('active_workout', () {
    test('returns null when no active session', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['active_workout'], isNull);
    });

    test('returns active state when set logged', () async {
      await ActiveWorkoutPersistence.writeState(
        exerciseName: 'Bench Press',
        currentSet: 2,
        totalSets: 4,
        weight: 60,
        repsTarget: 8,
        repsCompleted: 8,
        rpeHistory: [7.0],
        restRemainingSecs: 90,
      );
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['active_workout'], isNotNull);
      expect((ctx['active_workout'] as Map)['exercise'], 'Bench Press');
      expect((ctx['active_workout'] as Map)['current_set'], 2);
      // Cleanup
      await ActiveWorkoutPersistence.clearState();
    });
  });

  // APK Test #4 / A8: induction commitment + 5-question muster answer keys.
  // Plan B will write these on user induction (3-message intro + I COMMIT
  // button + 5-question interview). A8 exposes them so Captain Manual §2
  // (Lt Cdr Contract recall) and §10.1 idea #1 (why-now anchor recall) have
  // data the moment Plan B ships.
  group('induction + muster keys', () {
    test('all keys are null/false/empty for un-inducted user', () async {
      await HiveService.instance.coachBox.clear();
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['committed_at'], isNull);
      expect(ctx['committed_to_lt_cdr'], false);
      expect(ctx['days_since_commitment'], isNull);
      expect(ctx['why_now'], isNull);
      expect(ctx['definition_of_winning'], isNull);
      expect(ctx['known_injuries'], isEmpty);
      expect(ctx['typical_wake_time'], isNull);
      expect(ctx['preferred_workout_time'], isNull);
      expect(ctx['body_part_priorities'], isEmpty);
    });

    test('committed_at + days_since_commitment after recordCommitment-like write',
        () async {
      final fiveDaysAgo =
          DateTime.now().subtract(const Duration(days: 5)).toIso8601String();
      await HiveService.instance.coachBox.put('committed_at', fiveDaysAgo);
      await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['committed_at'], fiveDaysAgo);
      expect(ctx['committed_to_lt_cdr'], true);
      expect(ctx['days_since_commitment'], 5);
    });

    test('muster answers round-trip', () async {
      await HiveService.instance.coachBox.put('why_now', 'wedding in October');
      await HiveService.instance.coachBox.put(
          'definition_of_winning', 'feel strong');
      await HiveService.instance.coachBox
          .put('known_injuries', ['lower back', 'right knee']);
      await HiveService.instance.coachBox.put('typical_wake_time', '06:30');
      await HiveService.instance.coachBox
          .put('preferred_workout_time', '07:00');
      await HiveService.instance.coachBox
          .put('body_part_priorities', ['back', 'shoulders']);

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['why_now'], 'wedding in October');
      expect(ctx['definition_of_winning'], 'feel strong');
      expect(ctx['known_injuries'], ['lower back', 'right knee']);
      expect(ctx['typical_wake_time'], '06:30');
      expect(ctx['preferred_workout_time'], '07:00');
      expect(ctx['body_part_priorities'], ['back', 'shoulders']);
    });

    test('days_since_commitment handles malformed committed_at gracefully',
        () async {
      await HiveService.instance.coachBox.put('committed_at', 'not-a-date');
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['days_since_commitment'], isNull);
    });
  });
}
