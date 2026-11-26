// OI-532 (diagnose f5a2c8): a schedule restore that runs before a local day
// swap has been pushed must not put the old arrangement back. Plan
// docs/plans/oi532-sched-restore-unpushed-swap.md, tests section 6.
//
// BEHAVIOURAL: real Hive, the real SwapService.swapDays, the real schedule push
// (_syncScheduledWorkouts) against the local stub server, and the real
// restore merge through restoreScheduledWorkoutsForTest (injected cloud rows).
// closes-diagnose: f5a2c8
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync/sched_unpushed_swaps.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';
import 'sync_domain_skip_harness.dart';

// Week of Mon 21 – Sun 27 Sep 2026; "today" is Thu 24.
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const nextMon = '2026-09-28';
const cloudTmplId = 'cccccccc-1111-4222-8333-444444444444';

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

String get tmplKey => templateKeyFor(cloudTmplId);

Map<String, dynamic> friTemplateWorkout() => {
      'date': fri,
      'day_of_week': 4,
      'week': 2,
      'type': 'custom_template',
      'template_id': tmplKey,
      'workout_name': 'Push A',
      'workout_focus': 'Push',
      'exercises': [
        {'exercise_name': 'Bench Press', 'name': 'Bench Press', 'sets': 3}
      ],
      'status': 'planned',
    };

Map<String, dynamic> satRest() => {
      'date': sat,
      'day_of_week': 5,
      'week': 2,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'exercises': <Map<String, dynamic>>[],
      'status': 'rest',
    };

/// The cloud rows as they were BEFORE the swap (what a stale restore reads).
List<Map<String, dynamic>> preSwapCloudRows() => [
      {
        'scheduled_date': fri,
        'status': 'planned',
        'completed_at': null,
        'week_number': 2,
        'day_of_week': 4,
        'template_id': cloudTmplId,
        'template': {
          'id': cloudTmplId,
          'name': 'Push A',
          'workout_type': 'Push',
          'deleted_at': null,
          'template_exercises': [
            {
              'exercise_name': 'Bench Press',
              'exercise_id': 'bench',
              'order_index': 0,
              'prescribed_sets': 3,
              'prescribed_reps': '8',
            }
          ],
        },
      },
      {
        'scheduled_date': sat,
        'status': 'rest',
        'completed_at': null,
        'week_number': 2,
        'day_of_week': 5,
        'template_id': null,
      },
    ];

Map<String, dynamic> row(String date) => Map<String, dynamic>.from(
    HiveService.instance.workoutBox.get('schedule_$date') as Map);

Map<String, int> marks() =>
    SchedUnpushedSwaps.read(HiveService.instance.workoutBox);

void main() {
  final h = SyncHarness();
  final events = <String>[];

  Future<void> pushSched() =>
      SyncService.instance.pushScheduledWorkoutsForSyncDomain();

  Future<void> restore(List<Map<String, dynamic>> rows, {int? fetchMark}) =>
      SyncService.instance.restoreScheduledWorkoutsForTest(kTestUserId,
          preFetched: rows, fetchMark: fetchMark);

  Future<DaySwapResult> swap() => engine.swapDays(
      dateA: fri, dateB: sat, origin: DaySwapOrigin.trainDrag, isPro: true);

  /// Fri (template workout) and Sat (rest), both confirmed in the cloud.
  Future<void> seedConfirmed() async {
    final wb = HiveService.instance.workoutBox;
    await wb.put(tmplKey, {
      'type': 'template',
      'id': tmplKey,
      'name': 'Push A',
      'exercises': <dynamic>[],
    });
    await wb.put('schedule_$thu', {
      'date': thu,
      'type': 'rest',
      'status': 'rest',
      'exercises': <dynamic>[],
    });
    await wb.put('schedule_$fri', friTemplateWorkout());
    await wb.put('schedule_$sat', satRest());
    await pushSched();
    expect(h.server.writesTo('scheduled_workouts'), isNotEmpty);
    expect(marks(), isEmpty);
  }

  /// The swap lands locally; its push fails (offline).
  Future<void> swapOffline() async {
    h.server.failWritesTo.add('scheduled_workouts');
    expect(await swap(), isA<DaySwapDone>());
    await pushSched();
    expect(marks().keys, containsAll(<String>[fri, sat]),
        reason: 'a failed push keeps both marks');
    h.server.failWritesTo.remove('scheduled_workouts');
  }

  void expectSwapSurvived() {
    final s = row(sat);
    expect(s['type'], isNot('rest'), reason: 'Sat now holds the workout');
    expect(s['workout_name'], 'Push A');
    expect(s['exercises'], isNotEmpty);
    expect(s['status'], 'planned');
    final f = row(fri);
    expect(f['type'], 'rest');
    expect(f['status'], 'rest');
    expect(f.containsKey('template_id'), isFalse,
        reason: 'R2-1 (OI-348 3d): the rest side never re-gains the template');
  }

  setUp(() async {
    await h.setUp();
    SyncService.pausedForSimulation = true;
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
    SchedUnpushedSwaps.resetForUser();
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add('$op $message');
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () {};
    SwapService.debugSwapWriteForTests = null;
    SwapService.debugRecordSwapForTests = null;
    WorkoutWriteService.debugAfterPreMarkForTests = null;
    h.server.clear();
    h.server.writeFailers.clear();
    h.server.beforeWrite.clear();
    h.server.failWritesTo.clear();
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    WorkoutWriteService.debugAfterPreMarkForTests = null;
    SchedUnpushedSwaps.resetForUser();
    SchedUnpushedSwaps.nowMs = () => DateTime.now().millisecondsSinceEpoch;
    resetTestClock();
    SyncService.pausedForSimulation = false;
    await h.tearDown();
  });

  test('T1: an unpushed swap survives a restore of the PRE-swap cloud rows',
      () async {
    await seedConfirmed();
    await swapOffline();

    await restore(preSwapCloudRows());

    expectSwapSurvived();
    expect(events, contains('sched_restore_kept_unpushed_swap date=$sat'));
  });

  test('T2: not permanent: after a confirmed push the marks go, and a later '
      'cloud arrangement (another device swapped back) wins', () async {
    await seedConfirmed();
    await swapOffline();

    await pushSched();
    expect(marks(), isEmpty, reason: 'the confirmed push clears both marks');

    // Another device swapped back and pushed: the cloud rows equal the
    // pre-swap shape again, fetched now.
    await restore(preSwapCloudRows());
    expect(row(sat)['type'], 'rest');
    expect(row(sat)['exercises'], isEmpty);
    expect(row(fri)['workout_name'], 'Push A');
  });

  test('T3: a cloud COMPLETED on a pending date still lands', () async {
    await seedConfirmed();
    await swapOffline();

    final rows = preSwapCloudRows();
    rows[1] = {
      ...rows[1],
      'status': 'completed',
      'completed_at': '2026-09-26T05:00:00Z',
    };
    await restore(rows);

    expect(row(sat)['status'], 'completed');
  });

  test('T4: a later local rewrite of the swapped row keeps the guard while it '
      'is unpushed (arranged_at_ms is re-stamped, the mark is not)', () async {
    await seedConfirmed();
    await swapOffline();

    final s = row(sat);
    final r = await WorkoutWriteService.instance.upsertScheduled(
        date: DateTime.parse(sat),
        entry: {...s, 'notes': 'edited'},
        source: WriteSource.editSheet);
    expect(r.success, isTrue);

    await restore(preSwapCloudRows());
    expect(row(sat)['workout_name'], 'Push A');
    expect(row(sat)['exercises'], isNotEmpty);
    expect(row(sat)['notes'], 'edited');
  });

  test('T5 MIRROR: a fresh device (rows carry arranged_at_ms, no mark) takes '
      'the cloud as before', () async {
    final wb = HiveService.instance.workoutBox;
    await wb.put('schedule_$fri', {
      ...satRest(),
      'date': fri,
      'arranged_at_ms': 1000,
    });
    await wb.put('schedule_$sat', {
      ...friTemplateWorkout(),
      'date': sat,
      'template_id': null,
      'type': 'workout',
      'arranged_at_ms': 1000,
    });

    await restore(preSwapCloudRows());

    expect(row(sat)['type'], 'rest');
    expect(row(sat)['exercises'], isEmpty);
  });

  test('T6 kill switch: disable_sched_unpushed_swap_guard restores the old '
      'merge', () async {
    await HiveService.instance.configBox
        .put('disable_sched_unpushed_swap_guard', true);
    await seedConfirmed();
    await swapOffline();

    await restore(preSwapCloudRows());

    expect(row(sat)['type'], 'rest', reason: 'the pre-OI-532 merge');
    expect(row(sat)['exercises'], isEmpty);
  });

  test('T7: a swap that lands WHILE its date is being pushed keeps its mark; '
      'the next pass pushes the new content and clears it', () async {
    await seedConfirmed();
    await swapOffline();

    var swappedBack = false;
    h.server.beforeWrite['scheduled_workouts'] = (req) async {
      if (swappedBack) return;
      if (req.rows.single['scheduled_date'] != fri) return;
      swappedBack = true;
      expect(await swap(), isA<DaySwapDone>()); // swap back, mid-flight
    };
    await pushSched();
    expect(swappedBack, isTrue);
    expect(marks().keys, contains(fri),
        reason: 'the in-flight push sent the OLD Fri; its token is stale');

    h.server.beforeWrite.clear();
    h.server.clear();
    await pushSched();
    final friWrites = h.server
        .writesTo('scheduled_workouts')
        .where((r) => r.rows.single['scheduled_date'] == fri);
    expect(friWrites, isNotEmpty, reason: 'the swapped-back Fri is pushed');
    expect(marks(), isEmpty);
  });

  test('T8: launch order — the plan bundle restore then the schedule restore, '
      'both stale, keep the swap', () async {
    await seedConfirmed();
    await swapOffline();

    await SyncService.instance.restoreWorkoutPlanForTest(kTestUserId,
        preFetched: [
          {
            'plan_json': {
              'schedules': {
                'schedule_$fri': friTemplateWorkout(),
                'schedule_$sat': satRest(),
              }
            }
          }
        ]);
    await restore(preSwapCloudRows());

    expectSwapSurvived();
  });

  test('T9: rows fetched BEFORE a swap that was then pushed and cleared are '
      'still kept off that date', () async {
    await seedConfirmed();
    final fetchMark = SchedUnpushedSwaps.fetchMark(); // the restore fetched

    expect(await swap(), isA<DaySwapDone>());
    await pushSched();
    expect(marks(), isEmpty, reason: 'pushed and cleared before the merge');

    await restore(preSwapCloudRows(), fetchMark: fetchMark);

    expectSwapSurvived();
  });

  test('T10: a marked row whose push omits its template link stays marked '
      'across passes', () async {
    await seedConfirmed();
    await swapOffline();
    // The template is not on this phone and the cloud rejects the link.
    await HiveService.instance.workoutBox.delete(tmplKey);
    h.server.writeFailers['scheduled_workouts'] = (req) =>
        req.rows.any((r) => r['template_id'] == cloudTmplId)
            ? {
                'code': '23503',
                'message': 'violates foreign key constraint '
                    '"scheduled_workouts_template_id_fkey"',
              }
            : null;

    await pushSched();
    expect(marks().keys, contains(sat));
    await pushSched();
    expect(marks().keys, contains(sat),
        reason: 'a skip-branch true must not clear it on the second pass');
    expect(marks().keys, isNot(contains(fri)),
        reason: 'Fri (no template ref) was confirmed and cleared');
  });

  test('T11: a stale mark with no local row lets the cloud row restore',
      () async {
    final wb = HiveService.instance.workoutBox;
    await SchedUnpushedSwaps.markAll(wb, [nextMon]);
    expect(wb.get('schedule_$nextMon'), isNull);

    await restore([
      {
        'scheduled_date': nextMon,
        'status': 'planned',
        'completed_at': null,
        'week_number': 3,
        'day_of_week': 0,
        'template_id': null,
      }
    ]);

    expect(wb.get('schedule_$nextMon'), isA<Map>());
  });

  test('T12: the swap marks its dates before its first row write', () async {
    await seedConfirmed();
    final wb = HiveService.instance.workoutBox;
    final mark = SchedUnpushedSwaps.fetchMark();
    bool? pendingBeforeRows;
    bool? rowsUntouched;
    WorkoutWriteService.debugAfterPreMarkForTests = () async {
      pendingBeforeRows = SchedUnpushedSwaps.isPending(wb, fri) &&
          SchedUnpushedSwaps.isPending(wb, sat) &&
          SchedUnpushedSwaps.touchedSince(fri, mark);
      rowsUntouched = row(sat)['type'] == 'rest';
    };
    expect(await swap(), isA<DaySwapDone>());
    expect(rowsUntouched, isTrue);
    expect(pendingBeforeRows, isTrue);
    expect(SchedUnpushedSwaps.inFlightForTests, isEmpty,
        reason: 'the in-flight dates are released after the swap');
  });

  test('T13: a push that read the date DURING a swap (first mark, old row) '
      'and is answered after the swap ended does not clear the mark',
      () async {
    await seedConfirmed();
    await swapOffline(); // Fri/Sat now differ from the confirmed fingerprints

    final arrived = Completer<void>();
    final release = Completer<void>();
    var gated = false;
    h.server.beforeWrite['scheduled_workouts'] = (req) async {
      if (gated || req.rows.single['scheduled_date'] != fri) return;
      gated = true;
      arrived.complete();
      await release.future;
    };
    Future<void>? push;
    WorkoutWriteService.debugAfterPreMarkForTests = () async {
      WorkoutWriteService.debugAfterPreMarkForTests = null;
      push = pushSched(); // reads Fri: first-mark token, pre-swap-back row
      await arrived.future;
    };
    expect(await swap(), isA<DaySwapDone>()); // swap back
    release.complete();
    await push;

    expect(marks().keys, contains(fri),
        reason: 'the push sent the row of BEFORE the swap-back');
  });

  // The single-call restore fetches its bundle long before step B runs the
  // schedule restore, so the fetch mark must be taken before the call and
  // handed through (behaviour: T9). Driving _attemptSingleCallRestore end to
  // end needs an authed session and the 29-table bundle; this pins the wiring
  // the way restore_readiness_prefetch_test.dart pins its prefetch.
  test('single-call restore: the fetch mark is taken BEFORE the bundle call '
      'and passed to the schedule restore', () {
    final src = File('lib/core/services/sync_service.dart').readAsStringSync();
    final start = src.indexOf('Future<RestoreResult?> _attemptSingleCallRestore(');
    expect(start, greaterThan(0));
    final body = src.substring(start);
    final mark = body.indexOf('SchedUnpushedSwaps.fetchMark()');
    final call = body.indexOf("callFunction('restore-user-snapshot')");
    final pass = body.indexOf('fetchMark: schedFetchMark');
    expect(mark, greaterThan(0));
    expect(call, greaterThan(mark));
    expect(pass, greaterThan(call));
    expect(body.substring(pass - 200, pass), contains('_restoreScheduledWorkouts('));
  });

  group('helper', () {
    test('U1: the clear refuses a newer token and an in-flight date', () async {
      final wb = HiveService.instance.workoutBox;
      await SchedUnpushedSwaps.markAll(wb, [fri]);
      final old = SchedUnpushedSwaps.tokenOf(wb, fri)!;
      await SchedUnpushedSwaps.markAll(wb, [fri]);
      await SchedUnpushedSwaps.clearIfUnchanged(wb, fri, old);
      expect(SchedUnpushedSwaps.isPending(wb, fri), isTrue);

      final current = SchedUnpushedSwaps.tokenOf(wb, fri)!;
      await SchedUnpushedSwaps.beginSwap(wb, {fri});
      final t = SchedUnpushedSwaps.tokenOf(wb, fri)!;
      expect(t, greaterThan(current));
      await SchedUnpushedSwaps.clearIfUnchanged(wb, fri, t);
      expect(SchedUnpushedSwaps.tokenOf(wb, fri), t,
          reason: 'the STORED mark is never cleared while its swap is being '
              'written (isPending alone would also read the in-flight set)');
      SchedUnpushedSwaps.endSwap({fri});
      await SchedUnpushedSwaps.clearIfUnchanged(wb, fri, t);
      expect(SchedUnpushedSwaps.isPending(wb, fri), isFalse);
    });

    test('U2: a token is never reused (same ms, after a clear, clock back)',
        () async {
      final wb = HiveService.instance.workoutBox;
      var now = 5000;
      SchedUnpushedSwaps.nowMs = () => now;
      final seen = <int>{};
      for (var i = 0; i < 3; i++) {
        await SchedUnpushedSwaps.markAll(wb, [fri, sat]);
        seen.add(SchedUnpushedSwaps.tokenOf(wb, fri)!);
        seen.add(SchedUnpushedSwaps.tokenOf(wb, sat)!);
      }
      final t = SchedUnpushedSwaps.tokenOf(wb, fri)!;
      await SchedUnpushedSwaps.clearIfUnchanged(wb, fri, t);
      now = 10; // clock stepped back
      await SchedUnpushedSwaps.markAll(wb, [fri]);
      seen.add(SchedUnpushedSwaps.tokenOf(wb, fri)!);
      expect(seen, hasLength(7));
    });

    test('U3: a malformed stored value reads as no marks (fail open)',
        () async {
      final wb = HiveService.instance.workoutBox;
      await wb.put(kSchedSwapUnpushedKey, 'garbage');
      expect(SchedUnpushedSwaps.read(wb), isEmpty);
      expect(SchedUnpushedSwaps.isPending(wb, fri), isFalse);
    });

    test('U4: the reserved sequence entry is never a date', () async {
      final wb = HiveService.instance.workoutBox;
      await SchedUnpushedSwaps.markAll(wb, [fri]);
      expect(SchedUnpushedSwaps.read(wb).keys, [fri]);
      await SchedUnpushedSwaps.prune(wb); // no schedule_ row for fri
      expect(SchedUnpushedSwaps.read(wb), isEmpty);
      expect(SchedUnpushedSwaps.isPending(wb, '_seq'), isFalse);
    });
  });
}
