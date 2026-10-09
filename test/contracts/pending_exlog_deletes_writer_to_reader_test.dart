// L1a-2 U4 - SoT concept `pending_exlog_deletes` writer -> reader contract
// (Gate 9 names this file after the concept). The full drain behaviour (the
// time-filtered UPDATE, owner checks, queue re-read, kill switch) is in
// test/sync/exlog_delete_u4_behavioral_test.dart; this file pins the queue's
// own writer/reader field contract with the real WriteService:
//   writers  deleteLog / moveExerciseLogs -> add (workout_log_id, exercise_id,
//            set_number, deleted_at_ms); logExercise / move target -> cancelFor
//   readers  PendingExlogDeletes.read / isQueued (the drain and restore ask these)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/pending_exlog_deletes.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  final day = DateTime(2026, 9, 1);
  Future<void> log() => WorkoutWriteService.instance.logExercise(
        date: day,
        exerciseName: 'Bench Press',
        sets: [
          ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: day.millisecondsSinceEpoch),
          ExerciseSet(weightKg: 60, reps: 8, loggedAtMs: day.millisecondsSinceEpoch),
        ],
        source: WriteSource.activeWorkout,
      );

  test('deleteLog writes an entry the readers can find, with the delete time',
      () async {
    await log();
    final before = DateTime.now().millisecondsSinceEpoch;
    await WorkoutWriteService.instance.deleteLog(
        logKey: WorkoutWriteService.exlogKey(day, 'Bench Press'),
        source: WriteSource.activeWorkout);
    final e = PendingExlogDeletes.read().single;
    expect(e['workout_log_id'], SyncService.workoutLogIdForDate('2026-09-01'));
    expect(e['exercise_id'], 'Bench Press');
    expect(e['set_number'], 2);
    expect(e['deleted_at_ms'] as int, greaterThanOrEqualTo(before));
    expect(
        PendingExlogDeletes.isQueued(
            workoutLogId: e['workout_log_id'] as String,
            exerciseId: 'Bench Press',
            setNumber: 2,
            deletedAtMs: e['deleted_at_ms'] as int),
        isTrue);
    // A different time is a different (newer or older) action.
    expect(
        PendingExlogDeletes.isQueued(
            workoutLogId: e['workout_log_id'] as String,
            exerciseId: 'Bench Press',
            setNumber: 2,
            deletedAtMs: (e['deleted_at_ms'] as int) + 1),
        isFalse);
  });

  test('a re-log keeps a TIMED entry (the drain time filter spares the new '
      'version) and cancels a time-less one', () async {
    await log();
    await WorkoutWriteService.instance.deleteLog(
        logKey: WorkoutWriteService.exlogKey(day, 'Bench Press'),
        source: WriteSource.activeWorkout);
    expect(PendingExlogDeletes.read(), hasLength(1));
    await log();
    expect(PendingExlogDeletes.read(), hasLength(1),
        reason: 'timed: kept so the OLDER cloud versions are tombstoned');

    await HiveService.instance.userBox.put('pending_exlog_deletes', [
      {
        'workout_log_id': SyncService.workoutLogIdForDate('2026-09-01'),
        'exercise_id': 'Bench Press',
        'set_number': 2,
      }
    ]);
    await log();
    expect(PendingExlogDeletes.read(), isEmpty,
        reason: 'a pre-L1a-2 entry has no time: cancelled');
  });

  // PRESENCE-ONLY (source order): the move's Hive work cannot be made to throw
  // from a test, so the ordering is pinned by position. A queued cloud delete
  // for a source row that is still live locally would tombstone the cloud copy
  // and leave the local one (B-pass 5c19161a, reviewer B F6).
  test('moveExerciseLogs queues the source delete only AFTER its Hive work',
      () {
    final src = File('lib/core/services/workout_write_service.dart')
        .readAsStringSync();
    final start = src.indexOf('Future<void> moveExerciseLogs({');
    final body = src.substring(start, src.indexOf('Future<WriteResult> regenerateWeek', start));
    final del = body.indexOf('await box.delete(oldKey);');
    final add = body.indexOf('await PendingExlogDeletes.add(');
    expect(del, greaterThan(0));
    expect(add, greaterThan(del));
  });
}
