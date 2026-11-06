// OI-246 — Deleted exercise logs reappear after a cloud restore.
//
// SYMPTOM: `WorkoutWriteService.deleteLog` removed only the local Hive
// `exlog_` key — it never issued a cloud delete for the matching
// `workout_log_exercises` row. `SyncService._restoreExerciseLogs`'s
// additive/local-wins restore then re-inserted any cloud row whose Hive key
// was absent locally (`if (_hive.workoutBox.get(logId) == null) { put... }`,
// `sync_workout.dart` — the exact pattern `restore_local_wins_additive_test.dart`
// pins for this class), so a user-deleted log silently came back on the next
// full restore (fresh install / new device / cleared Hive).
//
// WRITER → `WorkoutWriteService.deleteLog` queues a `PendingExlogDeletes`
//          entry with the row's exact natural key (this test, behavioral).
//          `SyncService._drainPendingExlogDeletes` (wiring, source-grep)
//          UPSERTs a `deleted_at` tombstone per queued entry, drained before
//          every exercise-log push (migration 150's trigger — live-verified
//          separately in
//          test/sql/workout_log_exercises_delete_final_rename_live_verify.sql,
//          since the trigger's correctness depends on live Postgres UPDATE
//          semantics no source pin can verify).
// READER → `SyncService._restoreExerciseLogs` skips any row with
//          `deleted_at != null` (this test, wiring, source-grep).
//
// This file has four jobs:
//   1. resolveSummarySetCount — pure, mutation-tested (the natural-key
//      set-count resolver both the push and the delete queue must agree on).
//   2. PendingExlogDeletes — pure Hive queue behavior (add/dedup/remove).
//   3. WRITER — deleteLog queues the EXACT natural key a live push would
//      have used, for each of the 3 set-count shapes (behavioral, real
//      logExercise → deleteLog round trip).
//   4. WIRING — _drainPendingExlogDeletes is called before the push loop,
//      and _restoreExerciseLogs skips a deleted_at row (source-grep).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/pending_exlog_deletes.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';
import '_sync_service_source.dart';

/// Strips `//` line comments and `/* */` block comments so a source-seam
/// presence check can't be satisfied by a comment mentioning the token
/// (feedback_source_grep_strip_comments_first).
String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveSummarySetCount — pure, mutation-tested', () {
    test('counts sets[] when present', () {
      expect(
          WorkoutWriteService.resolveSummarySetCount({
            'sets': [
              {'weight_kg': 80, 'reps': 5},
              {'weight_kg': 80, 'reps': 5},
              {'weight_kg': 80, 'reps': 4},
            ],
          }),
          3);
    });

    test('counts sets_detail[] when present, preferred over sets[]', () {
      expect(
          WorkoutWriteService.resolveSummarySetCount({
            'sets_detail': [
              {'reps': 5},
              {'reps': 5},
            ],
            'sets': [
              {'reps': 5}
            ],
          }),
          2);
    });

    test('falls back to sets_completed when no per-set list', () {
      expect(
          WorkoutWriteService.resolveSummarySetCount({'sets_completed': 4}),
          4);
    });

    test('falls back to set_number when sets_completed absent', () {
      expect(WorkoutWriteService.resolveSummarySetCount({'set_number': 2}),
          2);
    });

    test('falls back to 1 when nothing present', () {
      expect(WorkoutWriteService.resolveSummarySetCount({}), 1);
    });

    test('empty sets[] falls through to the fallback chain, not 0', () {
      expect(
          WorkoutWriteService.resolveSummarySetCount(
              {'sets': [], 'set_number': 3}),
          3,
          reason: 'an empty per-set list must not be read as a real '
              '0-set count — mirrors the push side\'s resolvedSets.isNotEmpty '
              'check, which also falls through on empty');
    });
  });

  group('PendingExlogDeletes — pure Hive queue', () {
    setUp(wwsTestSetup);
    tearDown(wwsTestTeardown);

    test('add then read returns the queued entry', () async {
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 3);
      final all = PendingExlogDeletes.read();
      expect(all, hasLength(1));
      expect(all.single['workout_log_id'], 'wlog_a');
      expect(all.single['exercise_id'], 'Bench Press');
      expect(all.single['set_number'], 3);
      // L1a-2 U4: every entry records WHEN the user deleted it.
      expect(all.single['deleted_at_ms'], isA<int>());
    });

    test('adding the same natural key twice does not duplicate', () async {
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 3);
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 3);
      expect(PendingExlogDeletes.read().length, 1);
    });

    test('a different set_number is a DIFFERENT queued entry', () async {
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 3);
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 4);
      expect(PendingExlogDeletes.read().length, 2);
    });

    test('remove drops only the matching entry', () async {
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_a', exerciseId: 'Bench Press', setNumber: 3);
      await PendingExlogDeletes.add(
          workoutLogId: 'wlog_b', exerciseId: 'Squat', setNumber: 5);
      final queued = PendingExlogDeletes.read()
          .firstWhere((e) => e['exercise_id'] == 'Bench Press');
      await PendingExlogDeletes.remove(
          workoutLogId: 'wlog_a',
          exerciseId: 'Bench Press',
          setNumber: 3,
          deletedAtMs: queued['deleted_at_ms'] as int?);
      final all = PendingExlogDeletes.read();
      expect(all.length, 1);
      expect(all.first['exercise_id'], 'Squat');
    });
  });

  group('WRITER — deleteLog queues the exact natural key a push would use',
      () {
    setUp(wwsTestSetup);
    tearDown(wwsTestTeardown);

    test('deletes a log with 3 sets → queues (workoutLogId, name, 3)',
        () async {
      final date = DateTime(2026, 5, 1);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(weightKg: 80, reps: 5, loggedAtMs: 1),
          ExerciseSet(weightKg: 80, reps: 5, loggedAtMs: 2),
          ExerciseSet(weightKg: 80, reps: 4, loggedAtMs: 3),
        ],
        source: WriteSource.activeWorkout,
      );
      final key = WorkoutWriteService.exlogKey(date, 'Bench Press');
      final dateStr = WorkoutWriteService.istDateStr(date);

      await WorkoutWriteService.instance
          .deleteLog(logKey: key, source: WriteSource.editSheet);

      final queued = PendingExlogDeletes.read();
      expect(queued.length, 1);
      expect(queued.first['workout_log_id'],
          SyncService.workoutLogIdForDate(dateStr));
      expect(queued.first['exercise_id'], 'Bench Press');
      expect(queued.first['set_number'], 3);
    });

    test('the queued workout_log_id is DATE-deterministic, not row-specific '
        '(two different exercises the same day share it)', () async {
      final date = DateTime(2026, 5, 1);
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Bench Press',
        sets: [ExerciseSet(weightKg: 80, reps: 5, loggedAtMs: 1)],
        source: WriteSource.activeWorkout,
      );
      await WorkoutWriteService.instance.logExercise(
        date: date,
        exerciseName: 'Squat',
        sets: [ExerciseSet(weightKg: 100, reps: 5, loggedAtMs: 2)],
        source: WriteSource.activeWorkout,
      );
      await WorkoutWriteService.instance.deleteLog(
          logKey: WorkoutWriteService.exlogKey(date, 'Bench Press'),
          source: WriteSource.editSheet);
      await WorkoutWriteService.instance.deleteLog(
          logKey: WorkoutWriteService.exlogKey(date, 'Squat'),
          source: WriteSource.editSheet);

      final queued = PendingExlogDeletes.read();
      expect(queued.length, 2);
      expect(queued[0]['workout_log_id'], queued[1]['workout_log_id'],
          reason: 'workout_log_id is deterministic from the DATE alone '
              '(SyncService.workoutLogIdForDate) — every exercise logged '
              'that day shares it, matching the live push\'s natural key');
    });

    test('deleting a log with no explicit sets[] falls back to '
        'set_number/sets_completed for the queued count', () async {
      final box = HiveService.instance.workoutBox;
      const key = 'exlog_2026-05-01_legacy';
      await box.put(key, {
        'id': key,
        'type': 'exercise_log',
        'exercise_name': 'Deadlift',
        'date': '2026-05-01',
        'sets_completed': 5,
      });

      await WorkoutWriteService.instance
          .deleteLog(logKey: key, source: WriteSource.editSheet);

      final queued = PendingExlogDeletes.read();
      expect(queued.length, 1);
      expect(queued.first['exercise_id'], 'Deadlift');
      expect(queued.first['set_number'], 5);
    });
  });

  group('WIRING — drain + restore-skip (source-grep)', () {
    late String src;

    setUpAll(() {
      src = _stripComments(loadSyncServiceSource().readAsStringSync());
    });

    test('_syncExerciseLogs drains PendingExlogDeletes before the push loop',
        () {
      final start = src.indexOf('Future<void> _syncExerciseLogs(');
      expect(start, greaterThan(0),
          reason: '_syncExerciseLogs must exist');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next > start ? next : src.length);
      expect(body.contains('_drainPendingExlogDeletes(userId)'), isTrue,
          reason: 'a log deleted this session must be tombstoned before '
              'its own stale in-memory copy could re-create it in the same '
              'sync pass');
    });

    test('_drainPendingExlogDeletes tombstones with a filtered UPDATE on the '
        'queued key (kill switch: the same-count upsert)', () {
      final start = src.indexOf('Future<void> _drainPendingExlogDeletes(');
      expect(start, greaterThan(0));
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next > start ? next : src.length);
      expect(body.contains("'deleted_at':"), isTrue);
      expect(body.contains(".lte('completed_at', cutoff)"), isTrue,
          reason: 'only versions written at or before the delete (L1a-2 U4)');
      expect(body.contains(".eq('exercise_id', exerciseId)"), isTrue);
      expect(
          body.contains(
              "onConflict: 'user_id,workout_log_id,exercise_id,set_number'"),
          isTrue,
          reason: 'the kill-switch path keeps the exact natural key '
              'uniq_wle_user_wlog_ex_set covers');
    });

    test('_restoreExerciseLogs skips a tombstoned (deleted_at != null) row',
        () {
      final start = src.indexOf('Future<void> _restoreExerciseLogs(');
      expect(start, greaterThan(0));
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next > start ? next : src.length);
      expect(body.contains("if (map['deleted_at'] != null) continue;"),
          isTrue,
          reason: 'a tombstoned row must never be re-inserted into Hive, or '
              'this fix is a no-op — the exact resurrection OI-246 reports');
    });
  });
}
