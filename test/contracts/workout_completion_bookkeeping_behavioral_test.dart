// Coach workout parity 1a (OI-379) — BEHAVIORAL contract for the ONE shared
// after-completion step, `WorkoutCompletionBookkeeping.afterCompletion`
// (plan `docs/plans/coach-workout-parity-1a.md` rev 4, §3 T1).
//
// Before this step existed only Active Workout raised `total_workouts_done`,
// the daily and weekly streaks, the per-week streak row, badges and rank; the
// three coach doors called `markCompleted` alone (ADR-0012 assumed it "feeds
// streak / rank"; it never did). Every value raised here is monotonic (restore
// merges max-wins, the push RPC takes GREATEST), so an over-count is permanent:
// these cases pin the +1 rule, the heal to completed DAYS, every guard and the
// independence of the steps, on real Hive with a frozen clock.
//
// World: plan_start Monday 2026-06-01. Week 1 = Mon..Fri workouts, Sat/Sun
// rest (5 planned, threshold ceil(4.0) = 4). Clock Thursday 2026-06-04 10:00
// unless a case moves it. The door is simulated as production does it:
// `markCompleted` first, then `afterCompletion` with its `newlyCompleted`.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/workout_completion_bookkeeping_behavioral_test.dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show calendarWeekKey;
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/train/services/workout_completion_bookkeeping.dart';

import '../helpers/hive_test_setup.dart';

final _mon = DateTime(2026, 6, 1);
DateTime _d(int offset) => _mon.add(Duration(days: offset));

void main() {
  late Directory dir;
  final bk = WorkoutCompletionBookkeeping.instance;
  final events = <String>[];

  Map<String, dynamic> progress() => Map<String, dynamic>.from(
      HiveService.instance.userBox.get('progress') as Map);

  Future<void> seedProgress(Map<String, dynamic> m) =>
      HiveService.instance.userBox.put('progress', m);

  /// Seeds one plan week from [monday]: Mon..Fri `workout`, Sat/Sun `rest`.
  /// [completed] = offsets (0 = Monday) whose row is completed WITH a wlog_.
  /// [types] overrides a day's type.
  Future<void> seedWeek(
    DateTime monday, {
    required int week,
    Set<int> completed = const {},
    Map<int, String> types = const {},
  }) async {
    final wb = HiveService.instance.workoutBox;
    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final type = types[i] ?? (i < 5 ? 'workout' : 'rest');
      final done = completed.contains(i);
      await wb.put(WorkoutWriteService.scheduleKey(date), {
        'date': istDateStr(date),
        'week': week,
        'phase': 1,
        'type': type,
        'status': done ? 'completed' : 'planned',
        'workout_name': type == 'rest' ? 'Rest' : 'Upper Body',
      });
      if (done) {
        await wb.put(WorkoutWriteService.wlogKey(date), {
          'type': 'workout_log',
          'date': istDateStr(date),
          'workout_name': 'Upper Body',
        });
      }
    }
  }

  /// A door, exactly as production runs it: owner first, mark, then the step.
  Future<void> door(
    DateTime date, {
    CompletionDoor via = CompletionDoor.chatCard,
    bool mint = false,
  }) async {
    final owner = HiveUserSession.currentOwnerFullId;
    final r = await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Upper Body',
      durationSec: 1800,
    );
    expect(r.success, isTrue);
    await bk.afterCompletion(
      workoutDate: date,
      newlyCompleted: r.newlyCompleted,
      expectedOwner: owner,
      mintProgressIfMissing: mint,
      door: via,
    );
  }

  Future<void> step({
    DateTime? date,
    required bool newly,
    String? owner,
    bool ownerGiven = false,
    bool mint = false,
  }) =>
      bk.afterCompletion(
        workoutDate: date ?? _d(3),
        newlyCompleted: newly,
        expectedOwner: ownerGiven ? owner : HiveUserSession.currentOwnerFullId,
        mintProgressIfMissing: mint,
        door: CompletionDoor.coachTap,
      );

  setUp(() async {
    dir = await setUpHiveForTests();
    HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(kTestUserId);
    setTestClockTo(DateTime(2026, 6, 4, 10));
    WorkoutCompletionBookkeeping.debugReset();
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {String? message}) => events.add(op);
    await MigratedKey.write('plan_start_date', _mon.toIso8601String());
    await MigratedKey.write(
        'plan_end_date', _mon.add(const Duration(days: 27)).toIso8601String());
    await HiveService.instance.userBox.put('profile', {
      'id': kTestUserId,
      'onboarding_completed_at': DateTime(2026, 5, 20).toIso8601String(),
    });
    await HiveService.instance.configBox.delete('unlockedBadges');
  });

  tearDown(() async {
    WorkoutCompletionBookkeeping.debugReset();
    ErrorTelemetry.debugOnLogEventForTests = null;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    HiveUserSession.debugCurrentUidResolverForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  group('step 1: the count', () {
    test('heal off: newlyCompleted true adds exactly 1, false adds 0',
        () async {
      WorkoutCompletionBookkeeping.debugCompletedDayCount = () => 0;
      await seedProgress({'total_workouts_done': 5});
      await step(newly: true);
      expect(progress()['total_workouts_done'], 6);
      await step(newly: false);
      expect(progress()['total_workouts_done'], 6);
    });

    test('the heal raises the stored count to the completed DAYS on record',
        () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 0});
      await step(newly: false);
      expect(progress()['total_workouts_done'], 3);
    });

    test('the heal never lowers a higher stored count', () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 10});
      await step(newly: false);
      expect(progress()['total_workouts_done'], 10);
      await step(newly: true);
      expect(progress()['total_workouts_done'], 11);
    });

    test('a stored double (12.0) is read as 12 and counted, never thrown',
        () async {
      WorkoutCompletionBookkeeping.debugCompletedDayCount = () => 0;
      await seedProgress({'total_workouts_done': 12.0});
      await step(newly: true);
      expect(progress()['total_workouts_done'], 13);
    });

    test('distinct DATES: wlog_<date> + a legacy wlog_<ms> for the same day '
        'count once; a row with no usable date is skipped', () async {
      final wb = HiveService.instance.workoutBox;
      await wb.put('wlog_2026-06-02',
          {'type': 'workout_log', 'date': '2026-06-02'});
      await wb.put('wlog_1780380000000',
          {'type': 'workout_log', 'date': '2026-06-02T08:00:00'});
      await wb.put('wlog_legacy', {'type': 'workout_log'});
      await wb.put('wlog_2026-06-03', {'type': 'something_else'});
      expect(WorkoutReadService.instance.completedWorkoutDayCount(), 1);
      await seedProgress({'total_workouts_done': 0});
      await step(newly: false);
      expect(progress()['total_workouts_done'], 1);
    });
  });

  group('step 0: guards', () {
    test('the owner changed: nothing is written, the event fires', () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 2, 3});
      await seedProgress({'total_workouts_done': 2});
      await step(newly: true, owner: 'someone-else', ownerGiven: true);
      expect(progress(), {'total_workouts_done': 2});
      expect(HiveService.instance.healthBox.get('streaks'), isNull);
      expect(events, contains('completion_bookkeeping_owner_changed'));
    });

    test('null progress, a coach door (mint false): no write, no minted map',
        () async {
      await seedWeek(_mon, week: 1, completed: {0});
      await step(newly: true);
      expect(HiveService.instance.userBox.get('progress'), isNull);
      expect(HiveService.instance.healthBox.get('streaks'), isNull);
      expect(events, contains('completion_bookkeeping_no_progress'));
    });

    test('null progress, Active Workout (mint true): today\'s minted map',
        () async {
      await step(newly: true, mint: true);
      final p = progress();
      expect(p['total_workouts_done'], 1);
      expect(p['current_phase'], 1);
      expect(p['last_workout_date'], '2026-06-04');
    });

    test('restore NOT settled: only the count is written', () async {
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 3, 'current_streak_weeks': 0});
      await door(_d(3));
      final p = progress();
      expect(p['total_workouts_done'], 4);
      expect(p.containsKey('current_streak_days'), isFalse);
      expect(p.containsKey('last_workout_date'), isFalse);
      expect(p['current_streak_weeks'], 0);
      expect(p.containsKey('last_counted_week_key'), isFalse);
      expect(HiveService.instance.healthBox.get('streaks'), isNull);
      expect(events, contains('completion_bookkeeping_restore_unsettled'));
    });
  });

  group('step 1b follows the reckon\'s kill switch', () {
    tearDown(() async {
      SyncService.instance.restoreCompletedTick.value = 0;
      await HiveService.instance.configBox
          .delete('disable_streak_reckon_user_gate');
    });

    test('disable_streak_reckon_user_gate + a restore tick: the streak steps '
        'run without the marker (as the reckon does)', () async {
      SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
      await HiveService.instance.configBox
          .put('disable_streak_reckon_user_gate', true);
      SyncService.instance.restoreCompletedTick.value = 1;
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 3, 'current_streak_weeks': 0});
      await door(_d(3));
      final p = progress();
      expect(p['current_streak_weeks'], 1);
      expect(p['current_streak_days'], isA<int>());
      expect(events, isNot(contains('completion_bookkeeping_restore_unsettled')));
    });

    test('the switch with no tick: only the count', () async {
      SyncService.instance.debugSetRestoreSettledUserIdForTest(kTestUserId);
      await HiveService.instance.configBox
          .put('disable_streak_reckon_user_gate', true);
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 3, 'current_streak_weeks': 0});
      await door(_d(3));
      final p = progress();
      expect(p['total_workouts_done'], 4);
      expect(p['current_streak_weeks'], 0);
      expect(p.containsKey('current_streak_days'), isFalse);
    });
  });

  group('steps 2-6 on a settled restore', () {
    test('the weekly streak credits the week whose 80% this day completes, '
        'stamps the marker once, and writes the streak row', () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 3, 'current_streak_weeks': 0});
      await door(_d(3));
      var p = progress();
      expect(p['total_workouts_done'], 4);
      expect(p['current_streak_weeks'], 1);
      expect(p['last_counted_week_key'], calendarWeekKey(_d(3)));
      expect(p['last_workout_date'], '2026-06-04');
      expect(p['current_streak_days'], isA<int>());
      final rows = (HiveService.instance.healthBox.get('streaks') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single['local_id'], 'streak_2026-06-01');
      expect(rows.single['workouts_planned'], 5);
      expect(rows.single['workouts_completed'], 4);
      expect(rows.single['is_streak_maintained'], isTrue);

      // A second door on the same day: no second count, no second week.
      await door(_d(3), via: CompletionDoor.activeWorkout);
      p = progress();
      expect(p['total_workouts_done'], 4);
      expect(p['current_streak_weeks'], 1);
    });

    test('a backdated completion in the SAME week credits that week',
        () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 3});
      await seedProgress({
        'total_workouts_done': 3,
        'current_streak_weeks': 0,
        'last_workout_date': '2026-06-04',
      });
      await door(_d(2)); // Wednesday, logged on Thursday
      final p = progress();
      expect(p['current_streak_weeks'], 1);
      expect(p['last_counted_week_key'], calendarWeekKey(_d(2)));
      expect(p['last_workout_date'], '2026-06-04',
          reason: 'Thursday was completed earlier; the backdated Wednesday '
              'never pulls last_workout_date back');
    });

    test('a backdated completion in the PREVIOUS week gives no credit and '
        'leaves the marker', () async {
      setTestClockTo(DateTime(2026, 6, 9, 10)); // Tuesday of week 2
      await seedWeek(_mon, week: 1, completed: {0, 1, 2, 3});
      await seedWeek(_d(7), week: 2, completed: {0});
      await seedProgress({
        'total_workouts_done': 5,
        'current_streak_weeks': 2,
        'last_counted_week_key': 7,
      });
      await door(_d(4)); // Friday of week 1
      final p = progress();
      expect(p['total_workouts_done'], 6);
      expect(p['current_streak_weeks'], 2);
      expect(p['last_counted_week_key'], 7);
    });

    test('last_workout_date: a later stored date stays (a backdated log never '
        'pulls it back), an earlier one moves', () async {
      setTestClockTo(DateTime(2026, 6, 10, 10));
      await seedWeek(_mon, week: 1);
      await seedProgress(
          {'total_workouts_done': 0, 'last_workout_date': '2026-06-09'});
      await door(_d(3)); // Thursday 06-04, logged on 06-10
      expect(progress()['last_workout_date'], '2026-06-09');
      await seedProgress(
          {'total_workouts_done': 1, 'last_workout_date': '2026-06-01'});
      await step(newly: false);
      expect(progress()['last_workout_date'], '2026-06-04');
    });

    test('last_workout_date: a stored date after IST today + 1 is repaired '
        '(the one laterIsoDate rule the restore merge also uses)', () async {
      await seedWeek(_mon, week: 1);
      await seedProgress(
          {'total_workouts_done': 0, 'last_workout_date': '2026-06-10'});
      await door(_d(3)); // the clock says 06-04
      expect(progress()['last_workout_date'], '2026-06-04');
    });

    test('the IST day: 22:00 UTC Sunday is Monday in IST and credits the '
        'Monday\'s week', () async {
      setTestClockTo(DateTime(2026, 6, 8, 10)); // Monday of week 2, IST
      await seedWeek(_mon, week: 1, completed: {0, 1, 2, 3});
      // Week 2: one planned workout (Monday), so completing it is 1/1.
      await seedWeek(_d(7), week: 2, types: {1: 'rest', 2: 'rest', 3: 'rest', 4: 'rest'});
      await seedProgress({'total_workouts_done': 4, 'current_streak_weeks': 1});
      final utcLate = DateTime.utc(2026, 6, 7, 22); // = 2026-06-08 03:30 IST
      expect(istDateStr(utcLate), '2026-06-08');
      await door(utcLate);
      final p = progress();
      expect(p['last_workout_date'], '2026-06-08');
      expect(p['current_streak_weeks'], 2);
      expect(p['last_counted_week_key'], calendarWeekKey(DateTime(2026, 6, 8)));
    });

    test('a missed yesterday with one freeze: exactly ONE debit from a coach '
        'door, none on the next rollover reckon', () async {
      await seedWeek(_mon, week: 1, completed: {0, 1}); // Wed 06-03 missed
      await seedProgress({
        'total_workouts_done': 2,
        'current_streak_weeks': 0,
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
        'streak_freezes_last_refill': '2026-06-01',
      });
      await door(_d(3));
      var p = progress();
      expect(p['streak_freezes_available'], 0);
      expect(p['streak_freeze_used_dates'], ['2026-06-03']);
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      p = progress();
      expect(p['streak_freezes_available'], 0);
      expect(p['streak_freeze_used_dates'], ['2026-06-03']);
    });
  });

  group('each step has its own try/catch', () {
    for (final fault in const ['reckon', 'weekly']) {
      test('a throw in "$fault": the count still lands and step 6 still runs',
          () async {
        await seedWeek(_mon, week: 1, completed: {0, 1, 2});
        await seedProgress(
            {'total_workouts_done': 3, 'current_streak_weeks': 0});
        WorkoutCompletionBookkeeping.debugThrowAtStep = fault;
        await door(_d(3));
        final p = progress();
        expect(p['total_workouts_done'], 4);
        expect(p['last_workout_date'], '2026-06-04');
        expect(HiveService.instance.configBox.get('unlockedBadges'), isNotNull,
            reason: 'step 6 (badges) ran');
        if (fault == 'reckon') {
          expect(p.containsKey('current_streak_days'), isFalse);
          expect(p['current_streak_weeks'], 1);
        } else {
          expect(p['current_streak_days'], isA<int>());
          expect(p['current_streak_weeks'], 0);
          expect(HiveService.instance.healthBox.get('streaks'), isNull);
        }
      });
    }

    test('a throw in "count": the streak steps still run', () async {
      await seedWeek(_mon, week: 1, completed: {0, 1, 2});
      await seedProgress({'total_workouts_done': 3, 'current_streak_weeks': 0});
      WorkoutCompletionBookkeeping.debugThrowAtStep = 'count';
      await door(_d(3));
      final p = progress();
      expect(p['total_workouts_done'], 3);
      expect(p['current_streak_weeks'], 1);
      expect(p['current_streak_days'], isA<int>());
    });
  });
}
