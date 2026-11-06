@Timeout(Duration(minutes: 5))
library;

// L1a-3 / M2 (D2e): a log the exercise-log RESTORE wrote equals the cloud's
// rows, so the next push pass must skip it. The restore records the push
// fingerprint (built by the SAME `_buildExlogPushBundle` the push uses) only
// when its put actually ran, never when a local row won, and never under the
// hash-skip kill switch. Related bugs: e6a2d4.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/exlog_restore_rules.dart';
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

  String key0() => WorkoutWriteService.exlogKey(
      DateTime.utc(2026, 9, 1).subtract(const Duration(hours: 5, minutes: 30)),
      'Bench Press');

  test('a local edit after the restore still pushes (no false skip)',
      () async {
    await restore();
    final box = HiveService.instance.workoutBox;
    final row = Map<String, dynamic>.from(box.get(key0()) as Map);
    row['weight_kg'] = 80.0;
    row['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
    await box.put(key0(), row);
    h.server.clear();
    await push();
    expect(exlogUpserts(), 1);
  });

  test('gapped cloud set numbers are NOT fingerprinted (the push renumbers)',
      () async {
    h.server.pagedTables['workout_log_exercises'] = [
      {..._summary(), 'set_number': 3}
    ];
    h.server.pagedTables['workout_log_sets'] = [_set(1), _set(2), _set(4)];
    await restore();
    expect(
        SyncSkipIndex.readIndex(
            HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey),
        isNot(contains(key0())));
  });

  test('sets above the summary count are trimmed and the row is still skipped',
      () async {
    h.server.pagedTables['workout_log_sets'] = [_set(1), _set(2), _set(3)];
    await restore();
    h.server.clear();
    await push();
    expect(exlogUpserts(), 0);
  });

  group('restoredBundleEqualsCloud (pure)', () {
    Map<String, dynamic> sum() => {
          'workout_log_id': 'w',
          'exercise_id': 'Bench',
          'set_number': 2,
          'duration_seconds': 0,
          'completed_at': 't',
        };
    Map<String, dynamic> cloud() => {
          'workout_log_id': 'w',
          'exercise_id': 'Bench',
          'logging_type': 'weight_reps',
          'set_number': 2,
          'duration_seconds': null,
          'completed_at': 't',
        };
    final sets = [
      {'set_number': 1},
      {'set_number': 2}
    ];
    bool eq({Map<String, dynamic>? s, Map<String, dynamic>? c, List? r}) =>
        restoredBundleEqualsCloud(
            summary: s ?? sum(),
            sets: sets,
            cloudSummary: c ?? cloud(),
            restoredSets: r ?? sets);
    test('matching content is true', () => expect(eq(), isTrue));
    test('each divergence is false', () {
      expect(eq(c: {...cloud(), 'logging_type': null}), isFalse);
      expect(eq(c: {...cloud(), 'set_number': 5}), isFalse);
      expect(eq(c: {...cloud(), 'duration_seconds': 30}), isFalse);
      expect(eq(c: {...cloud(), 'exercise_id': 'Other'}), isFalse);
      expect(eq(c: {...cloud(), 'workout_log_id': 'x'}), isFalse);
      expect(eq(c: {...cloud(), 'completed_at': 'u'}), isFalse);
      expect(
          eq(r: [
            {'set_number': 1},
            {'set_number': 4}
          ]),
          isFalse);
      expect(eq(r: [{'set_number': 1}]), isFalse);
    });
  });
}
