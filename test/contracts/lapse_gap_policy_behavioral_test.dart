// Piece B (lapse gap policy) — behavioral. Plan:
// docs/plans/2026-10-18-pro-gap-policy-and-streak.md
//
// Pins, against real Hive boxes and the real repositories:
//   1. streak walk: a blank gap ends the chain (no old completed days counted,
//      no freeze spent); today with no row is tolerated; planned-but-missed
//      rows still drain freezes then break.
//   2. completion rate: blank days count as missed, days before the first row
//      do not.
//   3. resetFreezesAfterGap zeroes only the available count.
//   4. the PRO advance after a gap: start date, freeze zero, phase rows.
//   5. plan_status in the coach snapshot: omitted for a normal user.
//   6. the kill switch `disable_lapse_gap_policy` restores the old outputs.
//
// Clock pinned to Thu 2026-11-12 10:00 IST so the fixtures are date-literal.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/gap_policy.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    setTestClockTo(DateTime.utc(2026, 11, 12, 4, 30)); // Thu 12 Nov, 10:00 IST
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at': '2026-08-01T10:00:00.000',
      'days_per_week': 4,
      'primary_goal': 'build_muscle',
      'fitness_experience': 'intermediate',
      'equipment_access': 'full_gym',
    });
  });

  tearDown(() async {
    resetTestClock();
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  Future<void> row(String date, String status, {String type = 'workout'}) =>
      HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'type': type,
        'status': status,
        'workout_name': 'Push',
      });

  Future<void> rows(DateTime from, DateTime to, String status) async {
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      await row(istDateStr(d), status);
    }
  }

  Future<void> setProgress({int freezes = 3}) =>
      HiveService.instance.userBox.put('progress', {
        'current_phase': 2,
        'streak_freezes_available': freezes,
        'streak_freeze_used_dates': <String>[],
        'streak_freezes_last_refill': '2026-11-09',
      });

  Map progress() => UserRepository.instance.getProgress()!;
  Future<void> killSwitch(bool on) async =>
      HiveService.instance.configBox.put(kDisableLapseGapPolicyKey, on);

  group('streak walk — blank gap', () {
    // Old phase fully completed 21..27 Sep; nothing until today (Thu 12 Nov,
    // whose own row is planned).
    Future<void> seedBlankGap() async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await row('2026-11-12', 'planned');
      await setProgress();
    }

    test('does not cross the blank gap into old completed days', () async {
      await seedBlankGap();
      expect(WorkoutRepository.instance.currentStreak(), 0);
    });

    test('spends no freeze on a blank gap (consume path)', () async {
      await seedBlankGap();
      WorkoutRepository.instance.consumeMissedDayIfFreezeAvailable();
      expect(progress()['streak_freezes_available'], 3);
      expect(progress()['streak_freeze_used_dates'], isEmpty);
    });

    test('KILL SWITCH restores the old walk (old days counted again)',
        () async {
      await seedBlankGap();
      await killSwitch(true);
      expect(WorkoutRepository.instance.currentStreak(), 7);
    });

    test('today without a row yet is tolerated', () async {
      await rows(DateTime(2026, 11, 10), DateTime(2026, 11, 11), 'completed');
      await setProgress();
      expect(WorkoutRepository.instance.currentStreak(), 2);
    });

    test('yesterday without a row breaks the chain when a later row exists',
        () async {
      await row('2026-11-10', 'completed');
      await row('2026-11-12', 'planned');
      await setProgress();
      expect(WorkoutRepository.instance.currentStreak(), 0);
    });

    test('a TRAILING gap (nothing scheduled after it) keeps the old streak '
        '(expired free plan / advance not run yet)', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await setProgress();
      expect(WorkoutRepository.instance.currentStreak(), 7);
    });

    test('a mid gap with a FUTURE row after it still breaks', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await row('2026-11-16', 'planned'); // next Monday, no row for today
      await setProgress();
      expect(WorkoutRepository.instance.currentStreak(), 0);
    });
  });

  group('streak walk — planned (missed) gap rows', () {
    test('missed rows drain the freezes, then break the streak', () async {
      await rows(DateTime(2026, 11, 2), DateTime(2026, 11, 4), 'completed');
      await rows(DateTime(2026, 11, 5), DateTime(2026, 11, 11), 'planned');
      await row('2026-11-12', 'planned');
      await setProgress(freezes: 2);
      final streak =
          WorkoutRepository.instance.consumeMissedDayIfFreezeAvailable();
      expect(streak, 0);
      expect(progress()['streak_freezes_available'], 0);
      expect((progress()['streak_freeze_used_dates'] as List).length, 2);
    });
  });

  group('completion rate — blank days count as missed', () {
    test('a 73-day blank gap costs the 12-week rate', () async {
      await rows(DateTime(2026, 8, 17), DateTime(2026, 8, 30), 'completed');
      await row('2026-11-20', 'planned'); // the new phase, after the gap
      await setProgress();
      // Window 2026-08-20 .. today: 11 completed days + 73 blank days.
      expect(WorkoutRepository.instance.completionRateOverWindow(12),
          closeTo(11 / 84, 1e-9));
    });

    test('a non-date schedule_ key cannot disable the blank-day count',
        () async {
      await rows(DateTime(2026, 8, 17), DateTime(2026, 8, 30), 'completed');
      await row('2026-11-20', 'planned');
      await HiveService.instance.workoutBox
          .put('schedule_template_junk', {'type': 'workout'});
      await setProgress();
      expect(WorkoutRepository.instance.completionRateOverWindow(12),
          closeTo(11 / 84, 1e-9));
    });

    test('a TRAILING gap (no row after it) is not a miss', () async {
      await rows(DateTime(2026, 8, 17), DateTime(2026, 8, 30), 'completed');
      await setProgress();
      expect(WorkoutRepository.instance.completionRateOverWindow(12), 1.0);
    });

    test('KILL SWITCH restores the old rate (blank days ignored)', () async {
      await rows(DateTime(2026, 8, 17), DateTime(2026, 8, 30), 'completed');
      await row('2026-11-20', 'planned');
      await setProgress();
      await killSwitch(true);
      expect(WorkoutRepository.instance.completionRateOverWindow(12), 1.0);
    });

    test('days before the first schedule row are never penalised', () async {
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'completed');
      await setProgress();
      expect(WorkoutRepository.instance.completionRateOverWindow(26), 1.0);
    });

    test('today without a row is not counted', () async {
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'completed');
      await setProgress();
      // 3 completed, today (no row) excluded -> still 1.0, not 3/4.
      expect(WorkoutRepository.instance.completionRateOverWindow(1), 1.0);
    });
  });

  group('resetFreezesAfterGap', () {
    test('zeroes only the available count', () async {
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 3,
        'streak_freezes_available': 3,
        'streak_freeze_used_dates': <String>['2026-09-01'],
        'streak_freezes_last_refill': '2026-11-09',
        'streak_freeze_pro_granted': true,
      });
      StreakProgressService.instance.resetFreezesAfterGap(gapDays: 40);
      expect(progress()['streak_freezes_available'], 0);
      expect(progress()['streak_freeze_used_dates'], ['2026-09-01']);
      expect(progress()['streak_freeze_pro_granted'], true);
      expect(progress()['current_phase'], 3);
    });
  });

  group('coach plan_status', () {
    Future<void> wlog(String date) =>
        HiveService.instance.workoutBox.put('wlog_$date', {
          'type': 'workout_log',
          'date': date,
          'workout_name': 'Push',
        });

    test('omitted for a user who trained recently with back-to-back phases',
        () async {
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'completed');
      await wlog('2026-11-11');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx.containsKey('plan_status'), isFalse);
    });

    test('present after a blank gap, with the gap and missed days', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await wlog('2026-09-27');
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'planned');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      final ctx = AiCoachRepository.instance.buildAiContext();
      final ps = ctx['plan_status'] as Map;
      expect(ps['lapsed'], true);
      expect(ps['blank_gap_days_before_phase'], 42);
      expect(ps['missed_days_in_phase'], 3);
      expect(ps['phase_started_on'], '2026-11-09');
      expect(ps['days_since_last_workout'], 46);
    });

    test('present at 14 days idle without a blank gap, absent at 13',
        () async {
      await rows(DateTime(2026, 10, 20), DateTime(2026, 11, 11), 'planned');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 10, 12).toIso8601String());
      await wlog('2026-10-29'); // 14 days before Thu 12 Nov
      expect(
          AiCoachRepository.instance.buildAiContext()['plan_status'], isNotNull);
      await HiveService.instance.workoutBox.delete('wlog_2026-10-29');
      await wlog('2026-10-30'); // 13 days
      expect(AiCoachRepository.instance.buildAiContext()
          .containsKey('plan_status'), isFalse);
    });

    test('absent once the user has trained inside the new phase', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await wlog('2026-09-27');
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'planned');
      await row('2026-11-10', 'completed');
      await wlog('2026-11-10');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      expect(AiCoachRepository.instance.buildAiContext()
          .containsKey('plan_status'), isFalse);
    });

    test('a 3-day blank gap (below the 7-day floor) is not a lapse',
        () async {
      await rows(DateTime(2026, 11, 2), DateTime(2026, 11, 5), 'completed');
      await wlog('2026-11-05');
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'planned');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      expect(AiCoachRepository.instance.buildAiContext()
          .containsKey('plan_status'), isFalse);
    });

    test('reads the cheap progress.last_workout_date when present', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'planned');
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 2,
        'last_workout_date': '2026-09-27',
        'streak_freezes_available': 0,
      });
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      final ps = AiCoachRepository.instance.buildAiContext()['plan_status']
          as Map;
      expect(ps['days_since_last_workout'], 46);
    });

    test('KILL SWITCH removes the key', () async {
      await rows(DateTime(2026, 9, 21), DateTime(2026, 9, 27), 'completed');
      await wlog('2026-09-27');
      await rows(DateTime(2026, 11, 9), DateTime(2026, 11, 11), 'planned');
      await setProgress();
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      await killSwitch(true);
      expect(AiCoachRepository.instance.buildAiContext()
          .containsKey('plan_status'), isFalse);
    });
  });

  group('PRO advance after a gap (real plan generation)', () {
    final svc = WorkoutScheduleReadService.instance;

    Future<void> seedLibrary() async {
      final rows = jsonDecode(
              File('assets/data/exercise_library.json').readAsStringSync())
          as List;
      final box = HiveService.instance.exerciseBox;
      for (final r in rows.whereType<Map>()) {
        await box.put((r['id'] ?? r['name']).toString(),
            Map<String, dynamic>.from(r));
      }
    }

    Future<void> oldWindow(DateTime start, DateTime end) async {
      await MigratedKey.write('plan_start_date', start.toIso8601String());
      await MigratedKey.write('plan_end_date', end.toIso8601String());
    }

    Future<void> advance({int phase = 2}) => svc.autoGenerateNextPhaseIfNeeded(
          goal: 'build_muscle',
          equipment: 'full_gym',
          daysPerWeek: 4,
          experienceLevel: 'intermediate',
          currentPhase: phase,
        );

    test('3 weeks late: starts the day after the old phase, no freeze zero',
        () async {
      await seedLibrary();
      // Old phase 2026-09-28 .. 2026-10-25 (Sun); today Thu 12 Nov is NOT
      // inside the next phase 10-26..11-22? It is (11-12 <= 11-22): gap start.
      await oldWindow(DateTime(2026, 9, 28), DateTime(2026, 10, 25));
      await setProgress();
      await advance();
      expect(svc.getPlanStartDate(), DateTime(2026, 10, 26));
      expect(progress()['streak_freezes_available'], 3,
          reason: 'no blank gap: the missed rows drain freezes, nothing zeroed');
    });

    test('gap days of the new phase are real planned rows (missed)', () async {
      await seedLibrary();
      await oldWindow(DateTime(2026, 9, 28), DateTime(2026, 10, 25));
      await setProgress();
      await advance();
      final raw =
          HiveService.instance.workoutBox.get('schedule_2026-10-27') as Map?;
      expect(raw, isNotNull, reason: 'a past day of the new phase has a row');
      expect(raw!['status'], isNot('completed'));
    });

    test('10 weeks late: one phase from this Monday, blank gap stays blank',
        () async {
      await seedLibrary();
      await oldWindow(DateTime(2026, 8, 31), DateTime(2026, 9, 27));
      await setProgress();
      await advance();
      expect(svc.getPlanStartDate(), DateTime(2026, 11, 9));
      expect(HiveService.instance.workoutBox.get('schedule_2026-10-05'),
          isNull,
          reason: 'the blank weeks stay blank (no catch-up phases)');
    });

    test('free user leaving Phase 1 3 weeks late: fresh start this Monday',
        () async {
      await seedLibrary();
      // Same window as the 3-weeks-late PRO case (which starts 10-26), but the
      // old phase is Phase 1 (the free phase): Phase 2 starts THIS Monday and
      // no past day gets a row (founder 2026-10-18).
      await oldWindow(DateTime(2026, 9, 28), DateTime(2026, 10, 25));
      await setProgress();
      await advance(phase: 1);
      expect(svc.getPlanStartDate(), DateTime(2026, 11, 9));
      expect(HiveService.instance.workoutBox.get('schedule_2026-10-27'), isNull,
          reason: 'days before the purchase week are not shown as missed');
    });

    test('KILL SWITCH: 10 weeks late behaves as before (freezes kept)',
        () async {
      await seedLibrary();
      await killSwitch(true);
      await oldWindow(DateTime(2026, 8, 31), DateTime(2026, 9, 27));
      await setProgress();
      await advance();
      expect(svc.getPlanStartDate(), DateTime(2026, 11, 9));
      expect(progress()['streak_freezes_available'], 3);
    });

    test('KILL SWITCH: 3 weeks late restarts at this Monday (old rule)',
        () async {
      await seedLibrary();
      await killSwitch(true);
      await oldWindow(DateTime(2026, 9, 28), DateTime(2026, 10, 25));
      await setProgress();
      await advance();
      expect(svc.getPlanStartDate(), DateTime(2026, 11, 9));
    });
  });

  group('graduation unlock stays a fresh start (presence only)', () {
    // runGraduationPhaseAdvance needs a WidgetRef + the choice sheet, so the
    // behavior is covered by the pure `gapStart: false` table in
    // test/core/gap_policy_test.dart; this pins that the call site passes it.
    test('graduation passes gapStart: false', () {
      final src = File('lib/shared/services/pro_phase_advance.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(src.contains('nextPhaseStartDate(gapStart: false)'), isTrue);
    });
  });
}
