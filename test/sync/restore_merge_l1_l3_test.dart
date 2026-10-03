// test/sync/restore_merge_l1_l3_test.dart
//
// Behavioral coverage for spec 2026-09-26-day-swapper-design.md sec 5.7
// (L1 "never refill a rest row", L3 "the newer arrangement wins per week")
// and the _restoreScheduledWorkouts rest-type fix (diagnose b6e1c8).
// closes-diagnose: d5a1e7, b6e1c8

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;
  final events = <String>[];

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add('$op $message');
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  Map<String, dynamic>? row(String date) {
    final raw = HiveService.instance.workoutBox.get('schedule_$date');
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> put(String date, Map<String, dynamic> r) =>
      HiveService.instance.workoutBox.put('schedule_$date', r);

  Future<void> restorePlan(Map<String, dynamic> schedules) =>
      SyncService.instance.restoreWorkoutPlanForTest(
        kTestUserId,
        preFetched: [
          {
            'plan_json': {'schedules': schedules}
          }
        ],
      );

  group('snapshotArrangementWinsKeys (pure)', () {
    test('a strictly-newer snapshot week wins on its stamped dates', () {
      final wins = PlanIntegrityReconciler.snapshotArrangementWinsKeys(
        localRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 1000},
        },
        snapshotRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 2000},
          'schedule_2026-09-26': {'arranged_at_ms': 2000},
        },
      );
      expect(wins, {'schedule_2026-09-25', 'schedule_2026-09-26'});
    });

    test('a tie keeps local (strictly newer required)', () {
      final wins = PlanIntegrityReconciler.snapshotArrangementWinsKeys(
        localRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 1000},
        },
        snapshotRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 1000},
        },
      );
      expect(wins, isEmpty);
    });

    test('an unstamped date is never in the winning set even in a winning '
        'week, and a date absent from the snapshot side is never included',
        () {
      final wins = PlanIntegrityReconciler.snapshotArrangementWinsKeys(
        localRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 1000}, // Fri, stamped
          'schedule_2026-09-27': {}, // Sun, unstamped, same week
        },
        snapshotRows: {
          'schedule_2026-09-25': {'arranged_at_ms': 2000},
          // No schedule_2026-09-27 on the snapshot side at all.
        },
      );
      expect(wins, {'schedule_2026-09-25'});
    });

    test('missing arranged_at_ms counts as 0: an unstamped local week loses '
        'to any stamped snapshot week', () {
      final wins = PlanIntegrityReconciler.snapshotArrangementWinsKeys(
        localRows: {'schedule_2026-09-25': {}},
        snapshotRows: {'schedule_2026-09-25': {'arranged_at_ms': 1}},
      );
      expect(wins, {'schedule_2026-09-25'});
    });
  });

  group('_restoreWorkoutPlan wired through mergeScheduleBundleIntoHive '
      '(real Hive)', () {
    test('I1: a workout<->rest swap survives a cold restart against a stale '
        'plan_json backup', () async {
      const fri = '2026-09-25';
      const sat = '2026-09-26';
      await put(fri, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 1000,
        'exercises': <dynamic>[],
      });
      await put(sat, {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      });
      // The stale backup never learned about the swap.
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Pull + Core',
          'exercises': [
            {'name': 'Pull Up'}
          ],
        },
        'schedule_$sat': {
          'type': 'rest',
          'status': 'rest',
          'exercises': <dynamic>[],
        },
      });
      expect(row(fri)!['type'], 'rest',
          reason: 'the local rest row must never be refilled by the stale backup');
      expect(row(sat)!['workout_name'], 'Pull + Core');
      expect(events, isEmpty, reason: 'local wins on a TIE — no conflict to log');
    });

    test('a genuinely newer snapshot arrangement (another device) overrides '
        'the local one, per week, and logs ONE swap_merge_conflict', () async {
      const fri = '2026-09-25';
      const sat = '2026-09-26';
      await put(fri, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 1000,
        'exercises': <dynamic>[],
      });
      await put(sat, {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
        'schedule_$sat': {
          'type': 'rest',
          'status': 'rest',
          'arranged_at_ms': 2000,
          'exercises': <dynamic>[],
        },
      });
      expect(row(fri)!['workout_name'], 'Legs + Core');
      expect(row(sat)!['type'], 'rest');
      expect(events.where((e) => e.startsWith('swap_merge_conflict ')), hasLength(1),
          reason: 'ONE event per merge call, not per row');
    });

    test('two weeks in ONE bundle are decided independently: the snapshot '
        'wins the week where it is newer and loses the week where local is '
        'newer (no max leaks across the Monday boundary)', () async {
      const fri1 = '2026-09-25'; // week of Mon 2026-09-21
      const fri2 = '2026-10-02'; // week of Mon 2026-09-28
      await put(fri1, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 1000,
        'exercises': <dynamic>[],
      });
      await put(fri2, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 3000,
        'exercises': <dynamic>[],
      });
      await restorePlan({
        'schedule_$fri1': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
        'schedule_$fri2': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Pull + Core',
          'arranged_at_ms': 2500,
          'exercises': [
            {'name': 'Pull Up'}
          ],
        },
      });
      expect(row(fri1)!['workout_name'], 'Legs + Core',
          reason: 'week 1: snapshot 2000 > local 1000, so the snapshot wins — '
              'a week key that pooled both weeks would compare 2500 vs 3000 '
              'and wrongly keep the rest row');
      expect(row(fri2)!['type'], 'rest',
          reason: 'week 2: local 3000 > snapshot 2500, so local wins');
    });

    test('I6: a completed local row is never overridden even when its week '
        "'s snapshot arrangement is newer", () async {
      const fri = '2026-09-25';
      const sat = '2026-09-26';
      await put(fri, {
        'type': 'workout',
        'status': 'completed',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      });
      await put(sat, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 1000,
        'exercises': <dynamic>[],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
        'schedule_$sat': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      expect(row(fri)!['status'], 'completed');
      expect(row(fri)!['workout_name'], 'Pull + Core');
      expect(row(sat)!['workout_name'], 'Legs + Core',
          reason: 'sat is not completed — L3 still applies to it');
    });

    test('a winning week whose only arranged local row is completed logs NO '
        'swap_merge_conflict (nothing was discarded; round-1 review E F1)', () async {
      const fri = '2026-09-25';
      await put(fri, {
        'type': 'workout',
        'status': 'completed',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 1000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      expect(row(fri)!['status'], 'completed');
      expect(events.where((e) => e.startsWith('swap_merge_conflict ')), isEmpty);
    });

    test('kill switch disable_swap_arrangement_merge=true reverts to '
        'per-entry merge only (L3 off)', () async {
      await HiveService.instance.configBox
          .put('disable_swap_arrangement_merge', true);
      const fri = '2026-09-25';
      await put(fri, {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 1000,
        'exercises': <dynamic>[],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs + Core',
          'arranged_at_ms': 2000,
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      expect(row(fri)!['type'], 'rest',
          reason: 'with L3 off, a newer snapshot arrangement must NOT '
              'override — L1 still protects the rest row via the normal '
              'per-entry path');
      expect(events, isEmpty);
    });

    test('kill switch disable_rest_row_refill_guard=true skips the L1 guard: '
        'a snapshot row WITH exercises refills the rest row again (the '
        'normalizer stays on, so only this with-exercises shape reproduces)',
        () async {
      await HiveService.instance.configBox
          .put('disable_rest_row_refill_guard', true);
      const fri = '2026-09-25';
      await put(fri, {
        'type': 'rest',
        'status': 'rest',
        'exercises': <dynamic>[],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'workout_name': 'Legs',
          'exercises': [
            {'name': 'Squat'},
            {'name': 'Leg Press'},
            {'name': 'Lunge'},
          ],
        },
      });
      final r = row(fri)!;
      expect(r['type'], 'workout',
          reason: 'the kill switch reproduces the OLD bug on purpose: a '
              'rest row refilled with the stale workout content');
      expect(r['status'], 'rest');
      expect((r['exercises'] as List), hasLength(3));
    });
  });

  group('_restoreScheduledWorkouts rest-type fix (diagnose b6e1c8)', () {
    Map<String, dynamic> cloudRow(String date, String status,
            {String? templateId}) =>
        {
          'scheduled_date': date,
          'status': status,
          'completed_at': null,
          'week_number': null,
          'day_of_week': null,
          'template_id': templateId,
        };

    test('a cloud rest day with no local row and no template derives '
        'type rest, not workout', () async {
      const date = '2026-09-25';
      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [cloudRow(date, 'rest')],
      );
      expect(row(date)!['type'], 'rest');
    });

    test('a cloud PLANNED day with no local row and no template still '
        'derives type workout (unchanged, negative control)', () async {
      const date = '2026-09-26';
      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [cloudRow(date, 'planned')],
      );
      expect(row(date)!['type'], 'workout');
    });
  });
}
