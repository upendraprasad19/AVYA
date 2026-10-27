// test/sync/restore_merge_invariants_test.dart
//
// Day-swapper + sync-load Task 22 -- spec 2026-09-26-day-swapper-design.md
// sec 5.7 "Invariants" table (I1-I8) + the two "Accepted residuals", verbatim:
//
//   I1 Workout<->rest swap, cold restart with a stale backup -> the swap
//      survives, and no workout appears on two days.
//   I2 Reinstall after a pushed swap -> the swap appears.
//   I3 Swap on device A (pushed) -> device B's next launch shows it, for
//      workout<->workout too.
//   I4 Swap, then swap back -> both days back as they were, MOVED cleared,
//      and a stale backup does not re-apply the first swap.
//   I5 Swap (pushed), then a regeneration of those dates whose push failed,
//      then restart -> the regeneration survives.
//   I6 Completed local rows are never changed by the merge.
//   I7 The a7d3f1 repair still refills a planned workout row that lost its
//      exercises.
//   I8 No merge path produces a type:workout + status:rest row.
//
//   Accepted residuals (documented, tested as known behaviour, logged as
//   swap_merge_conflict):
//   R1 If two devices swap in the same week while offline, the later swap
//      wins that whole week. The earlier one is discarded, and its
//      allowance unit stays spent.
//   R2 A completed day is always kept, so a newer arrangement from another
//      device can leave that day's workout also scheduled elsewhere in the
//      week.
//
// Every test drives the REAL restore entry points (SyncService's
// restoreWorkoutPlanForTest / restoreScheduledWorkoutsForTest test seams)
// against real Hive with a fake downloaded bundle -- no source-grep pins
// (feedback_source_grep_false_confidence.md).
// closes-diagnose: d5a1e7
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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
          {'plan_json': {'schedules': schedules}}
        ],
      );

  Map<String, dynamic> cloudScheduledRow(String date, String status) => {
        'scheduled_date': date,
        'status': status,
        'completed_at': null,
        'week_number': null,
        'day_of_week': null,
        'template_id': null,
      };

  Future<void> restoreScheduledOverlay(List<Map<String, dynamic>> rows) =>
      SyncService.instance
          .restoreScheduledWorkoutsForTest(kTestUserId, preFetched: rows);

  test('I1: workout<->rest swap survives a cold restart against a stale '
      'backup, and no workout appears on two days', () async {
    const fri = '2026-09-25';
    const sat = '2026-09-26';
    await put(fri, {
      'type': 'rest',
      'status': 'rest',
      'arranged_at_ms': 5000,
      'exercises': <dynamic>[],
    });
    await put(sat, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Pull + Core',
      'arranged_at_ms': 5000,
      'exercises': [
        {'name': 'Pull Up'}
      ],
    });
    // Stale backup: the pre-swap arrangement, never learned about the swap.
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'exercises': [
          {'name': 'Pull Up'}
        ],
      },
      'schedule_$sat': {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]},
    });
    expect(row(fri)!['type'], 'rest');
    expect(row(sat)!['workout_name'], 'Pull + Core');
    expect(row(fri)!['workout_name'], isNull,
        reason: 'the workout must not ALSO appear on fri');
  });

  group('I2: reinstall after a pushed swap -> the swap appears', () {
    // Both starting states drive the ACTUAL step-A-then-step-B order
    // _attemptSingleCallRestore uses (sync_service.dart:1935 then :1980,
    // verified live this session).
    const fri = '2026-09-25';
    const sat = '2026-09-26';
    final swappedSchedules = {
      'schedule_$fri': {
        'type': 'rest',
        'status': 'rest',
        'arranged_at_ms': 9000,
        'exercises': <dynamic>[],
      },
      'schedule_$sat': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 9000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      },
    };

    test('from an EMPTY Hive (no local row on either date)', () async {
      await restorePlan(swappedSchedules); // step A
      await restoreScheduledOverlay([
        cloudScheduledRow(fri, 'rest'),
        cloudScheduledRow(sat, 'planned'),
      ]); // step B
      expect(row(fri)!['type'], 'rest');
      expect(row(sat)!['type'], 'workout');
    });

    test(
        'from FRESHLY GENERATED local rows (onboarding\'s plan generator ran '
        'before the restore, so both dates already have full exercises and '
        'NO arranged_at_ms)', () async {
      await put(fri, {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'exercises': [
          {'name': 'Pull Up'}
        ],
      });
      await put(sat, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});

      await restorePlan(swappedSchedules); // step A
      await restoreScheduledOverlay([
        cloudScheduledRow(fri, 'rest'),
        cloudScheduledRow(sat, 'planned'),
      ]); // step B

      expect(row(fri)!['type'], 'rest',
          reason: 'the freshly-generated (unswapped) local content must be '
              'DISCARDED here: fri carries a snapshot arranged_at_ms (9000) '
              'and no local stamp (missing = 0), so L3 forces the snapshot '
              'wholesale for this stamped date, overriding the pre-existing '
              '"local already has exercises" anti-a7d3f1 guard that would '
              'otherwise have kept the freshly-generated workout in place');
      expect(row(sat)!['type'], 'workout');
      expect(row(sat)!['workout_name'], 'Pull + Core');
    });
  });

  test('I3: a workout<->workout swap on device A reaches device B\'s next '
      'launch (the a7d3f1 anti-refill guard alone would otherwise HIDE '
      'this, since both local rows already have exercises)', () async {
    const fri = '2026-09-25';
    const sat = '2026-09-26';
    // Device B's own local state: the OLD, unswapped arrangement, never
    // stamped (device B has never swapped anything itself).
    await put(fri, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Pull + Core',
      'exercises': [
        {'name': 'Pull Up'}
      ],
    });
    await put(sat, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Legs + Core',
      'exercises': [
        {'name': 'Squat'}
      ],
    });
    // Device A's pushed swap, downloaded on device B's next launch.
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'arranged_at_ms': 7000,
        'exercises': [
          {'name': 'Squat'}
        ],
      },
      'schedule_$sat': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'arranged_at_ms': 7000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      },
    });
    expect(row(fri)!['workout_name'], 'Legs + Core');
    expect(row(sat)!['workout_name'], 'Pull + Core');
  });

  test('I4: swap then swap back -> both days as they were, MOVED cleared, '
      'and a stale backup of the FIRST swap does not re-apply', () async {
    const fri = '2026-09-25';
    const sat = '2026-09-26';
    // Local state AFTER swap-back (spec/day_swap_rules.dart landed(): content
    // landing back on its own origin clears is_swapped/original_date, and
    // arranged_at_ms is re-stamped to the swap-back's own (later) time).
    await put(fri, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Pull + Core',
      'arranged_at_ms': 8000, // swap-back time
      'exercises': [
        {'name': 'Pull Up'}
      ],
    });
    await put(sat, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Legs + Core',
      'arranged_at_ms': 8000,
      'exercises': [
        {'name': 'Squat'}
      ],
    });
    // A stale downloaded backup reflecting the FIRST swap (older stamp).
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'is_swapped': true,
        'original_date': sat,
        'arranged_at_ms': 3000, // the first swap -- OLDER than 8000
        'exercises': [
          {'name': 'Squat'}
        ],
      },
      'schedule_$sat': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Pull + Core',
        'is_swapped': true,
        'original_date': fri,
        'arranged_at_ms': 3000,
        'exercises': [
          {'name': 'Pull Up'}
        ],
      },
    });
    expect(row(fri)!['workout_name'], 'Pull + Core',
        reason: 'the stale backup\'s re-application of the FIRST swap must '
            'be rejected -- local\'s swap-back stamp (8000) is newer');
    expect(row(sat)!['workout_name'], 'Legs + Core');
    expect(row(fri)!.containsKey('is_swapped'), isFalse,
        reason: 'MOVED stays cleared');
    expect(row(sat)!.containsKey('is_swapped'), isFalse);
  });

  test('I5: a swap (pushed), then a regeneration of those dates whose push '
      'failed, then restart -> the regeneration survives', () async {
    const fri = '2026-09-25';
    // Local: a REGENERATED row (a later template change / reschedule) whose
    // arranged_at_ms was carried forward by upsertScheduled's carry-forward
    // rule (Task 6, plan sec 5.7 "Carry-forward") to a time AFTER the swap.
    await put(fri, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Regenerated Push Day',
      'arranged_at_ms': 6000, // the regeneration's carried-forward stamp
      'exercises': [
        {'name': 'Bench Press'}
      ],
    });
    // Stale backup: the swap's own bundle, whose push never landed, so the
    // cloud still only knows the SWAP's (older) arrangement.
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'arranged_at_ms': 4000, // the swap -- OLDER than the regeneration
        'exercises': [
          {'name': 'Squat'}
        ],
      },
    });
    expect(row(fri)!['workout_name'], 'Regenerated Push Day',
        reason: 'the regeneration (4000 < 6000 in the snapshot vs local '
            'stamp comparison) must survive the stale swap backup');
  });

  test('I6: a completed local row is never changed by the merge, even when '
      'its week\'s snapshot arrangement is newer', () async {
    const fri = '2026-09-25';
    await put(fri, {
      'type': 'workout',
      'status': 'completed',
      'workout_name': 'Pull + Core',
      'arranged_at_ms': 1000,
      'exercises': [
        {'name': 'Pull Up', 'sets': 3}
      ],
    });
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'arranged_at_ms': 9999,
        'exercises': [
          {'name': 'Squat'}
        ],
      },
    });
    expect(row(fri)!['status'], 'completed');
    expect(row(fri)!['workout_name'], 'Pull + Core');
    expect(row(fri)!['exercises'], [
      {'name': 'Pull Up', 'sets': 3}
    ]);
    expect(events.where((e) => e.startsWith('swap_merge_conflict ')), isEmpty,
        reason: 'the completed row was protected, so nothing was discarded to report');
  });

  test('I7: the a7d3f1 repair still refills a planned workout row that lost '
      'its exercises', () async {
    const fri = '2026-09-25';
    await put(fri, {
      'type': 'workout',
      'status': 'planned',
      'exercises': <dynamic>[], // the a7d3f1 symptom: exercises dropped
    });
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs',
        'exercises': [
          {'name': 'Squat'},
          {'name': 'Leg Press'},
        ],
      },
    });
    expect(row(fri)!['exercises'], hasLength(2),
        reason: 'a planned workout row that lost its exercises (not a rest '
            'row, so L1 does not apply) must still refill from the snapshot');
    expect(row(fri)!['status'], 'planned');
  });

  group('I8: no merge path produces a type:workout + status:rest row', () {
    test('existing == null, snapshot is a hybrid (wholesale-take branch)',
        () async {
      const fri = '2026-09-25';
      await restorePlan({
        'schedule_$fri': {'type': 'workout', 'status': 'rest', 'exercises': <dynamic>[]},
      });
      final r = row(fri)!;
      expect(r['status'] == 'rest' && r['type'] == 'workout', isFalse);
      expect(r['type'], 'rest');
    });

    test('existing is a hybrid, status rest (L1 guard branch)', () async {
      const fri = '2026-09-25';
      await put(fri, {'type': 'workout', 'status': 'rest', 'exercises': <dynamic>[]});
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'planned',
          'exercises': [
            {'name': 'Squat'}
          ],
        },
      });
      final r = row(fri)!;
      expect(r['status'] == 'rest' && r['type'] == 'workout', isFalse);
      expect(r['type'], 'rest');
    });

    test('a hybrid snapshot wins via L3 (forceSnapshotArrangement branch)',
        () async {
      const fri = '2026-09-25';
      await put(fri, {
        'type': 'workout',
        'status': 'planned',
        'arranged_at_ms': 1,
        'exercises': [
          {'name': 'Squat'}
        ],
      });
      await restorePlan({
        'schedule_$fri': {
          'type': 'workout',
          'status': 'rest',
          'arranged_at_ms': 2,
          'exercises': <dynamic>[],
        },
      });
      final r = row(fri)!;
      expect(r['status'] == 'rest' && r['type'] == 'workout', isFalse);
      expect(r['type'], 'rest');
    });
  });

  test('R1 (accepted residual): two devices swap in the SAME week while '
      'offline -- the later swap wins the WHOLE week, discarding the '
      'earlier one even on dates the later swap never touched', () async {
    const mon = '2026-09-21';
    const tue = '2026-09-22';
    const wed = '2026-09-23';
    const thu = '2026-09-24';
    // Local: device A's own earlier swap (mon<->tue), stamped 1000.
    await put(mon, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Tuesday\'s workout',
      'arranged_at_ms': 1000,
      'exercises': [
        {'name': 'B'}
      ],
    });
    await put(tue, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Monday\'s workout',
      'arranged_at_ms': 1000,
      'exercises': [
        {'name': 'A'}
      ],
    });
    await put(wed, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Wed',
      'exercises': [
        {'name': 'C'}
      ],
    });
    await put(thu, {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'Thu',
      'exercises': [
        {'name': 'D'}
      ],
    });
    // Downloaded: device B's later swap (wed<->thu, stamped 2000), whose
    // push carries mon/tue as device B last knew them -- UNSWAPPED and
    // unstamped, since device B never touched those two dates itself.
    await restorePlan({
      'schedule_$mon': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Monday\'s workout',
        'exercises': [
          {'name': 'A'}
        ],
      },
      'schedule_$tue': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Tuesday\'s workout',
        'exercises': [
          {'name': 'B'}
        ],
      },
      'schedule_$wed': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Thu\'s workout',
        'arranged_at_ms': 2000,
        'exercises': [
          {'name': 'D'}
        ],
      },
      'schedule_$thu': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Wed\'s workout',
        'arranged_at_ms': 2000,
        'exercises': [
          {'name': 'C'}
        ],
      },
    });
    expect(row(mon)!['workout_name'], 'Monday\'s workout',
        reason: 'device A\'s earlier swap is discarded -- the WHOLE week '
            'took the snapshot, per week-max comparison (2000 > 1000), even '
            'on mon/tue which the later swap itself never touched');
    expect(row(tue)!['workout_name'], 'Tuesday\'s workout');
    expect(row(wed)!['workout_name'], 'Thu\'s workout');
    expect(row(thu)!['workout_name'], 'Wed\'s workout');
    expect(events.where((e) => e.startsWith('swap_merge_conflict ')),
        hasLength(1));
  });

  test('R2 (accepted residual): a completed day is kept, so its workout can '
      'end up also scheduled elsewhere in the week after a newer '
      'arrangement lands', () async {
    const fri = '2026-09-25';
    const sat = '2026-09-26';
    await put(fri, {
      'type': 'workout',
      'status': 'completed',
      'workout_name': 'Legs + Core',
      'arranged_at_ms': 1000,
      'exercises': [
        {'name': 'Squat'}
      ],
    });
    await put(sat, {'type': 'rest', 'status': 'rest', 'exercises': <dynamic>[]});
    await restorePlan({
      'schedule_$fri': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'arranged_at_ms': 9000,
        'exercises': [
          {'name': 'Squat'}
        ],
      },
      'schedule_$sat': {
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Legs + Core',
        'arranged_at_ms': 9000,
        'exercises': [
          {'name': 'Squat'}
        ],
      },
    });
    expect(row(fri)!['status'], 'completed',
        reason: 'the completed day is never changed by the merge (I6)');
    expect(row(sat)!['workout_name'], 'Legs + Core',
        reason: 'sat is NOT completed, so L3 still applies to it -- "Legs + '
            'Core" is now accepted-residual duplicated across fri and sat');
  });
}
