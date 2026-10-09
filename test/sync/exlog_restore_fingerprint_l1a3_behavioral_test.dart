@Timeout(Duration(minutes: 5))
library;

// L1a-3 / M2 (D2e): a log the exercise-log RESTORE wrote equals the cloud's
// rows, so the next push pass must skip it. The restore records the push
// fingerprint (built by the SAME `_buildExlogPushBundle` the push uses) only
// when its put actually ran, never when a local row won, and never under the
// hash-skip kill switch. Related bugs: e6a2d4.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import '../helpers/hive_test_setup.dart';
import 'sync_domain_skip_harness.dart';

const _day = '2026-09-01';

Map<String, dynamic> _summary() => {
      'id': '00000000-0000-4000-8000-000000000001',
      'user_id': kTestUserId,
      'workout_log_id': SyncService.workoutLogIdForDate(_day),
      'exercise_id': 'Bench Press',
      'exercise_name': 'Bench Press',
      'set_number': 2,
      'weight_kg': 60.0,
      'reps': 16,
      'logging_type': 'weight_reps',
      'is_pr': false,
      'completed_at': '${_day}T10:00:00+00:00',
      'created_at': '${_day}T10:00:00+00:00',
      'deleted_at': null,
    };

Map<String, dynamic> _set(int n) => {
      'id': '00000000-0000-4000-8000-00000000100$n',
      'user_id': kTestUserId,
      'workout_log_id': SyncService.workoutLogIdForDate(_day),
      'exercise_id': 'Bench Press',
      'set_number': n,
      'weight_kg': 60.0,
      'reps': 8,
      'completed_at': '${_day}T10:00:00+00:00',
      'created_at': '${_day}T10:00:00+00:00',
    };

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.pagedTables['workout_log_exercises'] = [_summary()];
    h.server.pagedTables['workout_log_sets'] = [_set(1), _set(2)];
    h.server.clear();
  });
  tearDown(h.tearDown);

  Future<void> restore() => SyncService.instance
      .restoreExerciseLogsForSyncDomain(since: '2020-01-01T00:00:00Z')
      .timeout(const Duration(minutes: 2));
  Future<void> push() => SyncService.instance
      .pushExerciseLogsForSyncDomain()
      .timeout(const Duration(minutes: 2));
  int exlogUpserts() => h.server.writesTo('workout_log_exercises').length;

  test('a restored log is not pushed straight back', () async {
    await restore();
    final key = WorkoutWriteService.exlogKey(
        DateTime.utc(2026, 9, 1).subtract(const Duration(hours: 5, minutes: 30)),
        'Bench Press');
    expect(HiveService.instance.workoutBox.get(key), isNotNull);
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey),
        contains(key));
    h.server.clear();
    await push();
    expect(exlogUpserts(), 0);
  });

  test('a local row that won the restore is NOT fingerprinted', () async {
    final key = WorkoutWriteService.exlogKey(
        DateTime.utc(2026, 9, 1).subtract(const Duration(hours: 5, minutes: 30)),
        'Bench Press');
    await HiveService.instance.workoutBox.put(key, {
      'id': key,
      'type': 'exercise_log',
      'exercise_name': 'Bench Press',
      'date': _day,
      'logging_type': 'weight_reps',
      'weight_kg': 100.0,
      'reps_completed': 3,
      'set_number': 1,
      'created_at': '${_day}T11:00:00+00:00',
      'workout_log_id': 'wlog_$_day',
    });
    await restore();
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey),
        isNot(contains(key)));
    h.server.clear();
    await push();
    expect(exlogUpserts(), 1, reason: 'the local edit still reaches the cloud');
  });

  test('kill switch: nothing is recorded and the restored log pushes once',
      () async {
    await HiveService.instance.configBox.put(
        SyncSkipDomain.exlog.killSwitchKey, true);
    await restore();
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey),
        isEmpty);
    h.server.clear();
    await push();
    expect(exlogUpserts(), 1);
  });

  test('restore-dedupe kill switch: old behaviour, nothing recorded', () async {
    await HiveService.instance.configBox
        .put('disable_exlog_restore_dedupe', true);
    await restore();
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey),
        isEmpty);
  });
}
