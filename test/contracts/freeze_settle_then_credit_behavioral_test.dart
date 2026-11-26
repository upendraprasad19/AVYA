// freeze-order-d1 (diagnose a7d2e6): "settle, THEN credit". The founder's rule:
// a freeze is a KEPT stock; days up to Saturday are settled first (a missed
// scheduled day spends a freeze, a Sunday rest is free); on Monday's app-open
// +1 is credited regardless of last week's misses; a broken chain stays broken;
// next Monday's +1 covers a missed Monday.
//
// Behavioral: real Hive + StreakProgressService + WorkoutRepository, a pinned
// clock (the cases are weekday-dependent by nature). Every case asserts stock,
// the used-dates ledger, the stamp and the streak count.
//
// Calendar used (IST): Mon 2026-10-26 ... Fri 10-30 (workdays), Sat 10-31,
// Sun 11-01 (rest), Mon 11-02, Tue 11-03, Wed 11-04, Mon 11-09.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.instance.restoreCompletedTick.value = 0;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    HiveUserSession.debugCurrentUidResolverForTests = null;
    SyncService.pausedForSimulation = false;
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at': '2026-10-13T10:00:00',
    });
  });

  tearDown(() async {
    resetTestClock();
    SyncService.pausedForSimulation = false;
    SyncService.instance.restoreCompletedTick.value = 0;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(null);
    HiveUserSession.debugCurrentUidResolverForTests = null;
    await tearDownHiveForTests(tempDir);
  });

  void openRestoreGate() {
    HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
    SyncService.instance.debugSetRestoreSettledUserIdForTest(kTestUserId);
  }

  void clockAt(int y, int m, int d, [int h = 10]) =>
      setTestClockTo(DateTime(y, m, d, h));

  Future<void> sched(String date, String status, {String type = 'PUSH'}) =>
      HiveService.instance.workoutBox
          .put('schedule_$date', {'type': type, 'status': status});

  /// Workdays Mon 10-26..Fri 10-30 completed; Sat missed (pending); Sun rest.
  Future<void> baseWeek() async {
    for (final d in ['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30']) {
      await sched(d, 'completed');
    }
    await sched('2026-10-31', 'pending');
    await sched('2026-11-01', 'rest', type: 'rest');
  }

  Future<void> progress({
    required int stock,
    String? stamp,
    List<String> used = const [],
  }) =>
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': stock,
        'streak_freeze_used_dates': used,
        if (stamp != null) 'streak_freezes_last_refill': stamp,
      });

  Map<String, dynamic> prog() => UserRepository.instance.getProgress()!;
  int stockNow() => prog()['streak_freezes_available'] as int;
  List<String> usedNow() =>
      (prog()['streak_freeze_used_dates'] as List).map((e) => '$e').toList();
  String? stampNow() => prog()['streak_freezes_last_refill'] as String?;
  int streakNow() => WorkoutRepository.instance.currentStreak();

  group('Monday open (the founder rule)', () {
    test('stock 0, Saturday missed: the streak BREAKS, then +1 arrives as 1', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(stockNow(), 1);
      expect(stampNow(), '2026-11-02');
      expect(usedNow(), isEmpty, reason: 'nothing to spend on Saturday');
      expect(streakNow(), 0, reason: 'Saturday was unpaid: the chain is broken');
      // durable: a SECOND reckon (resume / midnight / completeWorkout) must not
      // re-spend the fresh credit on Saturday
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(stockNow(), 1);
      expect(usedNow(), isEmpty);
      expect(streakNow(), 0);
    });

    test('stock 1, Saturday missed: Saturday is paid by the OLD stock, +1 arrives, chain intact', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-31']);
      expect(stockNow(), 1, reason: '1 spent on Saturday, then +1');
      expect(stampNow(), '2026-11-02');
      expect(streakNow(), 5);
    });

    test('a second refill call the same Monday is a no-op', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      final before = [stockNow(), ...usedNow(), stampNow()];
      expect(StreakProgressService.instance.refillIfNewWeek(), isNull);
      expect([stockNow(), ...usedNow(), stampNow()], before);
    });
  });

  group('PRO cap on the settle-first credit', () {
    Future<void> makePro() async {
      await HiveService.instance.userBox.put('isPro', true);
      await HiveService.instance.userBox.put(
          'expiresAt', DateTime.now().add(const Duration(days: 90)).toIso8601String());
    }

    test('PRO, stock 2, Saturday missed: spend 1, +1 lands at 2 (the free cap 1 would clamp it to 1)', () async {
      clockAt(2026, 11, 2);
      await makePro();
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 2, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-31']);
      expect(stockNow(), 2);
      expect(streakNow(), 5);
    });

    test('PRO, stock 3, nothing missed: the credit clamps at the PRO cap 3', () async {
      clockAt(2026, 11, 2);
      await makePro();
      await baseWeek();
      await sched('2026-10-31', 'completed');
      await sched('2026-11-02', 'pending');
      await progress(stock: 3, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(stockNow(), 3);
      expect(stampNow(), '2026-11-02');
    });

    test('PRO, stock 2, Saturday completed: +1 reaches 3 (a cap of 2 would clamp it)', () async {
      clockAt(2026, 11, 2);
      await makePro();
      await baseWeek();
      await sched('2026-10-31', 'completed');
      await sched('2026-11-02', 'pending');
      await progress(stock: 2, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(stockNow(), 3);
    });
  });

  group('pure reads never persist, even across the cutoff', () {
    test('currentStreak() with the credit due leaves the whole progress map untouched', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      final before = Map<String, dynamic>.from(prog());
      streakNow();
      streakNow();
      expect(Map<String, dynamic>.from(prog()), before);
    });
  });

  group('first open of the week on Tuesday / Wednesday', () {
    test('Tue, stock 1, Sat + Mon missed: Saturday takes the old stock, Monday takes the credit', () async {
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-31', '2026-11-02']);
      expect(stockNow(), 0);
      expect(streakNow(), 5);
      expect(prog()['streak_freeze_just_used_count'], 2,
          reason: 'the notice count equals the number of spends');
      expect(WorkoutRepository.instance.reckonStreakDecayAndPersist(), 5,
          reason: 'the read-only display equals the persisted walk');
    });

    test('Tue, stock 0, Sat + Mon missed: Saturday breaks, the credit pays Monday', () async {
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-11-02']);
      expect(stockNow(), 0);
      expect(streakNow(), 0);
    });

    test('Wed, stock 1, Sat + Mon + Tue missed: Saturday old stock; the credit pays the NEWEST (Tue); Monday breaks', () async {
      clockAt(2026, 11, 4);
      await baseWeek();
      for (final d in ['2026-11-02', '2026-11-03', '2026-11-04']) {
        await sched(d, 'pending');
      }
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-31', '2026-11-03']);
      expect(stockNow(), 0);
      expect(streakNow(), 0, reason: 'Monday is unpaid and sits after Saturday');
    });

    test('a BARE reckon (no refill call) with the credit due settles only days before Monday', () async {
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      openRestoreGate();
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(usedNow(), ['2026-10-31'], reason: 'Monday waits for the credit');
      expect(stockNow(), 0);
    });

    test('a COMPLETED Monday while the credit is due still counts (the cutoff sits after the completed arm)', () async {
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'completed');
      await sched('2026-11-03', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      expect(streakNow(), 1);
    });
  });

  group('a broken chain stays broken (the unfundable horizon)', () {
    test('PRO-style stock 3, six misses: 3 spent, the 4th breaks, and the next Monday\'s +1 does NOT resurrect it', () async {
      clockAt(2026, 11, 2);
      for (final d in ['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30', '2026-10-31']) {
        await sched(d, 'pending');
      }
      await sched('2026-11-01', 'rest', type: 'rest');
      await sched('2026-11-02', 'pending');
      await progress(stock: 3, stamp: '2026-10-26');
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-29', '2026-10-30', '2026-10-31']);
      expect(stockNow(), 1, reason: '3 spent, then +1');
      // the week after: everything done, next Monday's credit
      await sched('2026-11-02', 'completed');
      for (final d in ['2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07']) {
        await sched(d, 'completed');
      }
      await sched('2026-11-08', 'rest', type: 'rest');
      await sched('2026-11-09', 'pending');
      clockAt(2026, 11, 9);
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-10-29', '2026-10-30', '2026-10-31'],
          reason: 'Wednesday 10-28 must not be paid retroactively');
      expect(stockNow(), 1);
      expect(streakNow(), 6);
    });

    test('boundary: a miss ON the stamped Monday is fundable, the day before is not', () async {
      clockAt(2026, 11, 10);
      await sched('2026-11-02', 'completed');
      await sched('2026-11-03', 'completed');
      await sched('2026-11-04', 'completed');
      await sched('2026-11-05', 'completed');
      await sched('2026-11-06', 'completed');
      await sched('2026-11-07', 'pending'); // Sat before the stamp
      await sched('2026-11-08', 'rest', type: 'rest');
      await sched('2026-11-09', 'pending'); // ON the stamp
      await sched('2026-11-10', 'pending');
      await progress(stock: 1, stamp: '2026-11-09');
      // Monday 11-09 is fundable (stock 1) but Saturday 11-07 (before the stamp)
      // is not: newest-first, Monday spends the stock, Saturday breaks.
      expect(streakNow(), 0);
      WorkoutRepository.instance.consumeMissedDayIfFreezeAvailable();
      expect(usedNow(), ['2026-11-09']);
    });

    test('a future-dated stamp switches the horizon off', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 1, stamp: '2026-11-09');
      expect(streakNow(), 5, reason: 'Saturday is still fundable with a stamp from the future');
    });
  });

  group('a NULL stamp keeps the old order for its first credit (documented)', () {
    test('Tue, stock 1, Sat + Mon missed, no stamp: Monday spends first, Saturday breaks, the credit then stamps', () async {
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 1);
      openRestoreGate();
      StreakProgressService.instance.refillIfNewWeek();
      expect(usedNow(), ['2026-11-02']);
      expect(stockNow(), 1);
      expect(stampNow(), '2026-11-02');
      expect(streakNow(), 0);
    });
  });

  group('deferral until the restore settles', () {
    test('restore unsettled with schedule rows: no write at all', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      expect(StreakProgressService.instance.refillIfNewWeek(), isNull);
      expect(stockNow(), 0);
      expect(stampNow(), '2026-10-26');
      expect(usedNow(), isEmpty);
    });

    test('the restore marker belongs to ANOTHER account: still deferred', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      SyncService.instance.debugSetRestoreSettledUserIdForTest('some-other-uid');
      expect(StreakProgressService.instance.refillIfNewWeek(), isNull);
      expect(stampNow(), '2026-10-26');
      expect(stockNow(), 0);
    });

    test('reinstall (EMPTY workoutBox), restore unsettled: no credit before the restore', () async {
      clockAt(2026, 11, 2);
      await progress(stock: 0, stamp: '2026-10-26');
      expect(StreakProgressService.instance.refillIfNewWeek(), isNull);
      expect(stampNow(), '2026-10-26');
      openRestoreGate();
      expect(StreakProgressService.instance.refillIfNewWeek(), 1);
      expect(stampNow(), '2026-11-02');
    });

    test('a throwing settle walk does not cost the week\'s credit', () async {
      clockAt(2026, 11, 2);
      await baseWeek();
      await progress(stock: 0, stamp: '2026-10-26');
      openRestoreGate();
      await HiveService.instance.workoutBox.close(); // the walk throws
      expect(StreakProgressService.instance.refillIfNewWeek(), 1);
      expect(stampNow(), '2026-11-02');
      expect(stockNow(), 1);
    });
  });

  group('the kill switch and the other modes run the pre-batch order', () {
    test('disable_settle_before_refill: the credit lands at once with the marker unset, no settle', () async {
      await HiveService.instance.configBox.put('disable_settle_before_refill', true);
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      StreakProgressService.instance.refillIfNewWeek();
      expect(stampNow(), '2026-11-02');
      expect(usedNow(), isEmpty);
      // the walk is the OLD one: unbounded, newest-first, and no horizon
      WorkoutRepository.instance.consumeMissedDayIfFreezeAvailable();
      expect(usedNow(), ['2026-11-02'], reason: 'Monday spends first (old order)');
    });

    test('legacy gate switch ON with the tick already > 0: refill alone spends nothing (no reckon #1)', () async {
      await HiveService.instance.configBox.put('disable_streak_reckon_user_gate', true);
      SyncService.instance.restoreCompletedTick.value = 1;
      clockAt(2026, 11, 3);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await sched('2026-11-03', 'pending');
      await progress(stock: 1, stamp: '2026-10-26');
      StreakProgressService.instance.refillIfNewWeek();
      expect(stampNow(), '2026-11-02');
      expect(usedNow(), isEmpty, reason: 'the old refill did not walk');
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(usedNow(), ['2026-11-02'], reason: 'old unbounded walk, no horizon, no cutoff');
    });

    test('legacy gate switch ON, tick 0 at credit time, then bumped: a pre-stamp miss is still funded (no horizon)', () async {
      await HiveService.instance.configBox.put('disable_streak_reckon_user_gate', true);
      clockAt(2026, 11, 2);
      await baseWeek();
      await sched('2026-11-02', 'pending');
      await progress(stock: 0, stamp: '2026-10-26');
      StreakProgressService.instance.refillIfNewWeek();
      expect(stockNow(), 1);
      SyncService.instance.restoreCompletedTick.value = 1;
      WorkoutRepository.instance.reckonStreakDecayAndPersist();
      expect(usedNow(), ['2026-10-31']);
      expect(stockNow(), 0);
    });

    test('simulation: the credit lands with the marker unset and the walk is the old walk', () async {
      SyncService.pausedForSimulation = true;
      clockAt(2026, 11, 9);
      for (final d in ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06']) {
        await sched(d, 'completed');
      }
      await sched('2026-11-07', 'pending');
      await sched('2026-11-08', 'rest', type: 'rest');
      await sched('2026-11-09', 'pending');
      await progress(stock: 1, stamp: '2026-11-02');
      StreakProgressService.instance.refillIfNewWeek();
      expect(stampNow(), '2026-11-09', reason: 'deferral bypassed');
      expect(streakNow(), 5, reason: 'no horizon: the pre-stamp Saturday is fundable');
    });
  });

  group('the Monday key', () {
    test('istMondayKey is the IST Monday around the Sunday/Monday midnight', () {
      expect(istMondayKey(DateTime.utc(2026, 11, 1, 18, 29, 59)), '2026-10-26');
      expect(istMondayKey(DateTime.utc(2026, 11, 1, 18, 30)), '2026-11-02');
      expect(istMondayKey(DateTime(2026, 11, 4, 10)), '2026-11-02');
    });

    test('the helper never feeds mondayOfIst into formatDateKey / istDateStr (a second instant conversion)', () {
      final src = File('lib/core/utils/ist_date.dart').readAsStringSync();
      final start = src.indexOf('String istMondayKey(');
      final end = src.indexOf('\n}\n', start);
      final body = src.substring(start, end);
      expect(body.contains('formatDateKey'), isFalse);
      expect(body.contains('istDateStr'), isFalse);
    });
  });
}
