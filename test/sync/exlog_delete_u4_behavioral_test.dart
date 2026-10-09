@Timeout(Duration(minutes: 5))
library;

// L1a-2 unit U4 (plan docs/plans/coach-history-correctness-client.md): exercise
// -log deletes reach the cloud for EVERY set count, the newest action wins, and
// a move queues its source day. Related bugs: e1c8b4 (OI-246), e8f4a3 (OI-218
// exlog half), debugging class 2.44 (a late op after an account swap).
//
//  - the drain sends ONE filtered UPDATE per entry (all counts, only versions
//    with completed_at <= the delete time) and never the old fallback upsert;
//  - a re-log after the delete is left alone, here (cancelFor) and in the cloud
//    (the time filter);
//  - moveExerciseLogs queues the source day (both branches) and cancels the
//    target day's delete; A->B->A leaves A live;
//  - owner check at each sink; queue re-read before the UPDATE;
//  - kill switch `disable_exlog_allcount_drain` = the old same-count upsert.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/pending_exlog_deletes.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _killSwitch = 'disable_exlog_allcount_drain';

String _wl(String day) => SyncService.workoutLogIdForDate(day);

List<StubRequest> _patches(SyncHarness h) => h.server.requests
    .where((r) => r.method == 'PATCH' && r.table == 'workout_log_exercises')
    .toList();

List<StubRequest> _posts(SyncHarness h) => h.server.requests
    .where((r) => r.method == 'POST' && r.table == 'workout_log_exercises')
    .toList();

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    // The stub instance is shared by every test in this file: reset all of its
    // per-test state so nothing leaks from one test into the next.
    h.server.clear();
    h.server.failWritesTo.clear();
    h.server.writeResponders.clear();
  });
  tearDown(h.tearDown);

  Future<void> drain() => SyncService.instance
      .pushExerciseLogsForSyncDomain()
      .timeout(const Duration(minutes: 2));

  Future<void> queue(String day, String name,
      {int sets = 3, int? at}) async {
    await PendingExlogDeletes.add(
      workoutLogId: _wl(day),
      exerciseId: name,
      setNumber: sets,
      deletedAtMs: at,
    );
  }

  group('the drain is one filtered UPDATE, all counts', () {
    test('sends the delete as a time-filtered UPDATE on the queued key, no upsert',
        () async {
      final deletedAt = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
      await queue('2026-09-01', 'Bench Press', at: deletedAt);
      await drain();

      final p = _patches(h);
      expect(p, hasLength(1));
      final q = p.single.query;
      expect(q['workout_log_id'], 'eq.${_wl('2026-09-01')}');
      expect(q['exercise_id'], 'eq.Bench Press');
      expect(q['user_id'], 'eq.$kTestUserId');
      expect(q['deleted_at'], 'is.null');
      expect(q['completed_at'], 'lte.2026-10-01T12:00:00.000Z',
          reason: 'only versions written at or before the delete');
      expect(q.containsKey('set_number'), isFalse,
          reason: 'ALL set counts: no set_number filter');
      expect((p.single.body as Map)['deleted_at'], isA<String>());
      expect(_posts(h), isEmpty, reason: 'the old fallback upsert is gone');
      expect(PendingExlogDeletes.read(), isEmpty,
          reason: 'a 0-row answer still completes the entry');
    });

    test('an entry queued before this landing (no time) cuts off at drain time',
        () async {
      // A legacy entry as it sits in an installed app's userBox.
      await HiveService.instance.userBox.put('pending_exlog_deletes', [
        {
          'workout_log_id': _wl('2026-09-01'),
          'exercise_id': 'Bench Press',
          'set_number': 3,
        }
      ]);
      final before = DateTime.now().toUtc();
      await drain();
      final cutoff = DateTime.parse(
          _patches(h).single.query['completed_at']!.substring(4));
      expect(cutoff.isBefore(before.subtract(const Duration(seconds: 5))),
          isFalse);
      expect(cutoff.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 5))),
          isFalse);
      expect(PendingExlogDeletes.read(), isEmpty);
    });

    test(
        'cross-device: an older row is tombstoned at ANY count, a re-log written '
        'after the delete is left alone', () async {
      final deletedAt = DateTime.utc(2026, 10, 1, 12);
      final cloud = <Map<String, dynamic>>[
        {'id': 'old3', 'set_number': 3, 'completed_at': '2026-10-01T09:00:00.000Z', 'deleted_at': null},
        {'id': 'old5', 'set_number': 5, 'completed_at': '2026-10-01T11:59:59.000Z', 'deleted_at': null},
        {'id': 'newer', 'set_number': 4, 'completed_at': '2026-10-01T12:00:01.000Z', 'deleted_at': null},
      ];
      h.server.writeResponders['workout_log_exercises'] = (r) {
        final cutoff = DateTime.parse(r.query['completed_at']!.substring(4));
        final touched = <Map<String, dynamic>>[];
        for (final row in cloud) {
          if (row['deleted_at'] == null &&
              !DateTime.parse(row['completed_at'] as String).isAfter(cutoff)) {
            row['deleted_at'] = (r.body as Map)['deleted_at'];
            touched.add(row);
          }
        }
        return touched;
      };
      await queue('2026-09-01', 'Bench Press',
          sets: 3, at: deletedAt.millisecondsSinceEpoch);
      await drain();
      expect(cloud.firstWhere((r) => r['id'] == 'old3')['deleted_at'], isNotNull);
      expect(cloud.firstWhere((r) => r['id'] == 'old5')['deleted_at'], isNotNull,
          reason: 'a stale count the same-count upsert would have missed');
      expect(cloud.firstWhere((r) => r['id'] == 'newer')['deleted_at'], isNull,
          reason: 'the newest action wins');
    });

    test('kill switch ON: the old same-count upsert, no UPDATE', () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      await queue('2026-09-01', 'Bench Press', sets: 3);
      await drain();
      expect(_patches(h), isEmpty);
      final posts = _posts(h);
      expect(posts, hasLength(1));
      expect(posts.single.query['on_conflict'],
          'user_id,workout_log_id,exercise_id,set_number');
      expect((posts.single.body as Map)['set_number'], 3);
    });

    test('a failed drain leaves the entry queued for the next pass', () async {
      h.server.failWritesTo.add('workout_log_exercises');
      await queue('2026-09-01', 'Bench Press');
      await drain();
      expect(PendingExlogDeletes.read(), hasLength(1));
    });
  });

  group('a re-log cancels the queued delete', () {
    test('delete -> failed drain -> re-log: the re-log stays live', () async {
      final day = DateTime(2026, 9, 1);
      Future<void> log() async {
        await WorkoutWriteService.instance.logExercise(
          date: day,
          exerciseName: 'Bench Press',
          sets: [
            ExerciseSet(
                weightKg: 60, reps: 8, loggedAtMs: day.millisecondsSinceEpoch),
          ],
          source: WriteSource.activeWorkout,
        );
      }

      await log();
      final key = WorkoutWriteService.exlogKey(day, 'Bench Press');
      await WorkoutWriteService.instance
          .deleteLog(logKey: key, source: WriteSource.activeWorkout);
      expect(PendingExlogDeletes.read(), hasLength(1));

      h.server.failWritesTo.add('workout_log_exercises');
      await drain();
      expect(PendingExlogDeletes.read(), hasLength(1),
          reason: 'the failed drain left it queued');

      await log(); // re-created
      expect(PendingExlogDeletes.read(), isEmpty,
          reason: 'logExercise cancels the stale delete');

      h.server.failWritesTo.clear();
      h.server.clear();
      await drain();
      expect(_patches(h), isEmpty,
          reason: 'nothing left to send: the re-log is not tombstoned');
    });
  });

  group('moveExerciseLogs queues the source day (closes OI-218 exlog half)', () {
    Map<String, dynamic> row(String day, {Map<String, dynamic> extra = const {}}) => {
          'exercise_name': 'Bench Press',
          'date': day,
          'logging_type': 'weight_reps',
          'weight_kg': 60.0,
          'reps_completed': 16,
          'set_number': 2,
          'created_at': '${day}T10:00:00.000Z',
          'sets': [
            {'weight_kg': 60.0, 'reps': 8},
            {'weight_kg': 60.0, 'reps': 8},
          ],
          ...extra,
        };

    String key(String day) => WorkoutWriteService.exlogKey(
        DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)),
            int.parse(day.substring(8, 10))),
        'Bench Press');

    test('non-collision branch queues A and the cloud A is tombstoned', () async {
      final box = HiveService.instance.workoutBox;
      await box.put(key('2026-09-01'), row('2026-09-01'));
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-01', toDate: '2026-09-02');
      final q = PendingExlogDeletes.read();
      expect(q, hasLength(1));
      expect(q.single['workout_log_id'], _wl('2026-09-01'));
      expect(q.single['exercise_id'], 'Bench Press');
      expect(q.single['set_number'], 2, reason: 'the moved row\'s local count');
      await drain();
      expect(_patches(h).single.query['workout_log_id'], 'eq.${_wl('2026-09-01')}');
    });

    test('collision branch queues the source day too', () async {
      final box = HiveService.instance.workoutBox;
      await box.put(key('2026-09-01'), row('2026-09-01'));
      await box.put(key('2026-09-02'), row('2026-09-02'));
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-01', toDate: '2026-09-02');
      expect(PendingExlogDeletes.read().single['workout_log_id'], _wl('2026-09-01'));
    });

    test('a delete queued for the TARGET day is cancelled by the move',
        () async {
      final box = HiveService.instance.workoutBox;
      await box.put(key('2026-09-01'), row('2026-09-01'));
      await queue('2026-09-02', 'Bench Press', sets: 4);
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-01', toDate: '2026-09-02');
      final ids = PendingExlogDeletes.read().map((e) => e['workout_log_id']);
      expect(ids, [_wl('2026-09-01')], reason: 'only the source remains queued');
    });

    test('A -> B -> A before a sync leaves A live (nothing queued for A)',
        () async {
      final box = HiveService.instance.workoutBox;
      await box.put(key('2026-09-01'), row('2026-09-01'));
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-01', toDate: '2026-09-02');
      await WorkoutWriteService.instance
          .moveExerciseLogs(fromDate: '2026-09-02', toDate: '2026-09-01');
      final ids = PendingExlogDeletes.read().map((e) => e['workout_log_id']).toList();
      expect(ids, [_wl('2026-09-02')],
          reason: 'B is queued, A was cancelled by the move back');
    });
  });

  group('sinks: queue re-read, owner checks', () {
    test('an entry cancelled after the drain read its copy sends nothing for it',
        () async {
      await queue('2026-09-01', 'Bench Press', at: 1000);
      await queue('2026-09-02', 'Squat', at: 2000);
      var first = true;
      h.server.writeResponders['workout_log_exercises'] = (r) {
        if (first) {
          first = false;
          // A re-log of the SECOND entry lands while the first is on the wire.
          PendingExlogDeletes.cancelFor(
              workoutLogId: _wl('2026-09-02'), exerciseName: 'Squat');
        }
        return const <Object>[];
      };
      await drain();
      final sent = _patches(h).map((r) => r.query['exercise_id']).toList();
      expect(sent, ['eq.Bench Press'],
          reason: 'the cancelled Squat delete is never sent');
      expect(_posts(h), isEmpty);
    });

    test('an account switch between two entries: the second is not sent',
        () async {
      await queue('2026-09-01', 'Bench Press', at: 1000);
      await queue('2026-09-02', 'Squat', at: 2000);
      var first = true;
      h.server.writeResponders['workout_log_exercises'] = (r) {
        if (first) {
          first = false;
          HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
        }
        return const <Object>[];
      };
      await drain();
      expect(_patches(h), hasLength(1));
    });

    test('an account switch during the UPDATE: no local remove', () async {
      await queue('2026-09-01', 'Bench Press', at: 1000);
      h.server.writeResponders['workout_log_exercises'] = (r) {
        HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
        return const <Object>[];
      };
      await drain();
      expect(_patches(h), hasLength(1));
      expect(PendingExlogDeletes.read(), hasLength(1),
          reason: 'the queue key is user-independent: a late remove would '
              'delete the next account\'s identical entry');
    });

    test('a delete re-queued while the older entry is on the wire survives '
        'that entry\'s local remove (exact triple AND time)', () async {
      await queue('2026-09-01', 'Bench Press', sets: 3, at: 1000);
      h.server.writeResponders['workout_log_exercises'] = (r) {
        // The user deletes the same exercise again while the first UPDATE is
        // in flight: a NEWER entry for the same triple replaces the older.
        PendingExlogDeletes.add(
          workoutLogId: _wl('2026-09-01'),
          exerciseId: 'Bench Press',
          setNumber: 3,
          deletedAtMs: 3000,
        );
        return const <Object>[];
      };
      await drain();
      final left = PendingExlogDeletes.read();
      expect(left, hasLength(1), reason: 'the newer delete is still queued');
      expect(left.single['deleted_at_ms'], 3000);
    });

    test('an account switch that lands right after the first entry\'s local '
        'remove stops the drain before the second UPDATE', () async {
      await queue('2026-09-01', 'Bench Press', at: 1000);
      await queue('2026-09-02', 'Squat', at: 2000);
      final sub = HiveService.instance.userBox
          .watch(key: 'pending_exlog_deletes')
          .listen((_) {
        HiveUserSession.debugCurrentUidResolverForTests = () => 'someone-else';
      });
      addTearDown(sub.cancel);
      await drain();
      expect(_patches(h).map((r) => r.query['exercise_id']), ['eq.Bench Press'],
          reason: 'the second entry is not sent under the old user id');
    });
  });

  group('ExlogKeyMigrator re-creates the row, so it cancels a queued delete', () {
    test('a rogue-keyed row migrated onto a day with a queued delete', () async {
      final box = HiveService.instance.workoutBox;
      await box.put('exlog_2026-09-01_rogue', {
        'exercise_name': 'Bench Press',
        'date': '2026-09-01',
        'sets': [
          {'weight_kg': 60.0, 'reps': 8},
        ],
        'set_number': 1,
        'updated_at_ms': 1,
      });
      await queue('2026-09-01', 'Bench Press', sets: 1);
      await queue('2026-09-02', 'Squat', sets: 2);
      await HiveService.instance.configBox.delete('exlog_key_migration_v8');
      await ExlogKeyMigrator.runIfNeeded();
      final ids = PendingExlogDeletes.read().map((e) => e['workout_log_id']).toList();
      expect(ids, [_wl('2026-09-02')],
          reason: 'only the re-created exercise\'s delete is cancelled');
    });
  });
}
