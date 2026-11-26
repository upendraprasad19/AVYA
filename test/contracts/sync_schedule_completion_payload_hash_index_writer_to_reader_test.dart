import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  group('completion behavioral skip contract (day-swapper + sync-load Task 14)', () {
    final h = SyncHarness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    Future<void> seed() async {
      await HiveService.instance.workoutBox.put('schedule_2026-09-20', {
        'date': '2026-09-20',
        'day_of_week': 6,
        'workout_name': 'Pull + Core',
        'status': 'completed',
        'completed_at_ms': DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
      });
      await HiveService.instance.workoutBox.put('wlog_2026-09-20', {
        'type': 'workout_log',
        'duration_seconds': 2400,
        'completed_at': DateTime.utc(2026, 9, 20, 12).toIso8601String(),
      });
    }

    test('the full skip contract', () async {
      await expectSkipContract(
        h: h,
        domain: SyncSkipDomain.completion,
        table: 'workout_schedule_completions',
        seed: seed,
        runPass: () => SyncService.instance.pushScheduleCompletionsForSyncDomain(),
        editOne: (generation) => HiveService.instance.workoutBox.put('schedule_2026-09-20', {
          'date': '2026-09-20',
          'day_of_week': 6,
          'workout_name': 'Pull + Core v$generation',
          'status': 'completed',
          'completed_at_ms': DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
        }),
      );
    });

    test('the pushed completed_at is the REAL completion time, never now() -- the 5a36ad '
        'recurrence this task fixes', () async {
      // The stub server is created ONCE per group and its `requests` list is
      // not cleared between tests (Task 13 lesson) -- clear before this
      // test's own push so `.single` below sees only its own write.
      h.server.clear();
      await seed();
      final before = DateTime.now().toUtc();
      await SyncService.instance.pushScheduleCompletionsForSyncDomain();
      final write = h.server.writesTo('workout_schedule_completions').single;
      final sentIso = write.rows.single['completed_at'] as String;
      final sent = DateTime.parse(sentIso);
      expect(sent, DateTime.utc(2026, 9, 20, 12),
          reason: 'must be the recorded completion time, not "now" '
              '(sanity: "now" is ${before.toIso8601String()}, a totally different date)');
    });

    test('no completion-time field at all on either row -> completed_at is OMITTED, '
        'never sent as now()', () async {
      h.server.clear();
      await HiveService.instance.workoutBox.put('schedule_2026-09-20', {
        'date': '2026-09-20',
        'day_of_week': 6,
        'workout_name': 'Pull + Core',
        'status': 'completed',
        // no completed_at, no completed_at_ms
      });
      await SyncService.instance.pushScheduleCompletionsForSyncDomain();
      final write = h.server.writesTo('workout_schedule_completions').single;
      expect(write.rows.single.containsKey('completed_at'), isFalse);
    });
  });

  group('restore carve-out uses the same resolver (plan D3) -- a locally completed day '
      'must survive a restore against a stale cloud "planned" row', () {
    final h = SyncHarness();
    setUp(h.setUp);
    tearDown(h.tearDown);

    const date = '2026-09-20';

    test('local schedule row is completed with ONLY completed_at_ms (the exact shape '
        'markCompleted writes, workout_write_service.dart:502) -- the cloud has a stale '
        '"planned" row for the same date -- the local completed row must survive', () async {
      await HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'day_of_week': 6,
        'workout_name': 'Pull + Core',
        'status': 'completed',
        'completed_at_ms': DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
        // Deliberately NO ISO completed_at -- markCompleted never writes one on
        // the schedule row (only on the separate wlog_<date> row). Before Task
        // 14 this made the "local completed + cloud planned -> keep local"
        // branch (sync_workout.dart ~:1981-1988) permanently unreachable.
      });
      h.server.getResponders['scheduled_workouts'] = (_) => [
            {
              'scheduled_date': date,
              'status': 'planned', // stale: the push that would have marked
                                    // this completed in cloud either failed or
                                    // has not run yet this pass
              'week_number': 3,
              'day_of_week': 6,
              'template_id': null,
            }
          ];

      await SyncService.instance.restoreScheduledWorkoutsForSyncDomain();

      final merged =
          Map<String, dynamic>.from(HiveService.instance.workoutBox.get('schedule_$date') as Map);
      expect(merged['status'], 'completed',
          reason: 'a stale cloud "planned" row must never demote a local completed '
              'day whose only completion evidence is completed_at_ms -- this is the '
              'exact bug plan D3 fixes (sync_workout.dart ~:1976)');
    });
  });
}
