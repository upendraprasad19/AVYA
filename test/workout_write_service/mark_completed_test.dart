import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('markCompleted: schedule status=completed + wlog_<date> written',
      () async {
    final date = DateTime(2026, 5, 1);
    final box = HiveService.instance.workoutBox;
    final scheduleKey = WorkoutWriteService.scheduleKey(date);
    final wlogKey = WorkoutWriteService.wlogKey(date);

    // Seed a scheduled workout
    await box.put(scheduleKey, {
      'workout_name': 'Push Day',
      'status': 'pending',
      'type': 'plan',
    });

    final r = await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3600,
      rpe: 7,
    );
    expect(r.success, isTrue);

    final scheduleAfter =
        (box.get(scheduleKey) as Map).cast<String, dynamic>();
    expect(scheduleAfter['status'], 'completed');

    final wlog = (box.get(wlogKey) as Map?)!.cast<String, dynamic>();
    expect(wlog['workout_name'], 'Push Day');
    expect(wlog['duration_seconds'], 3600);
    expect(wlog['rpe'], 7);
  });

  test('markCompleted is idempotent (second call doesn\'t duplicate wlog)',
      () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3600,
    );
    await WorkoutWriteService.instance.markCompleted(
      date: date,
      workoutName: 'Push Day',
      durationSec: 3700, // updated duration
    );

    final box = HiveService.instance.workoutBox;
    final wlogKeys =
        box.keys.where((k) => k.toString().startsWith('wlog_')).toList();
    expect(wlogKeys.length, 1);
    final wlog = (box.get(wlogKeys.first) as Map).cast<String, dynamic>();
    expect(wlog['duration_seconds'], 3700, reason: 'second call updates');
  });

  // Coach workout parity 1a (OI-379): markCompleted reports the day's FIRST
  // completion (`newlyCompleted`), decided under the per-date lock before any
  // write. Only a `completed` row or a surviving wlog_<date> makes it false.
  group('newlyCompleted', () {
    final date = DateTime(2026, 5, 4);

    Future<WriteResult> mark() => WorkoutWriteService.instance.markCompleted(
          date: date,
          workoutName: 'Push Day',
          durationSec: 1800,
        );

    Future<void> seed(Map<String, dynamic> row) => HiveService.instance
        .workoutBox
        .put(WorkoutWriteService.scheduleKey(date), row);

    test('no schedule row: true', () async {
      final r = await mark();
      expect(r.success, isTrue);
      expect(r.newlyCompleted, isTrue);
    });

    for (final status in const [
      'planned',
      'pending',
      'paused',
      'skipped',
      'travel',
      'moved',
      'dropped',
    ]) {
      test('a "$status" row: true', () async {
        await seed({'workout_name': 'Push Day', 'status': status, 'type': 'plan'});
        final r = await mark();
        expect(r.success, isTrue);
        expect(r.newlyCompleted, isTrue, reason: status);
      });
    }

    test('a rest-type row: true', () async {
      await seed({'workout_name': 'Rest', 'status': 'planned', 'type': 'rest'});
      expect((await mark()).newlyCompleted, isTrue);
    });

    test('a completed row: false', () async {
      await seed(
          {'workout_name': 'Push Day', 'status': 'completed', 'type': 'plan'});
      final r = await mark();
      expect(r.success, isTrue);
      expect(r.newlyCompleted, isFalse);
    });

    test('a planned row whose wlog_ survived: false', () async {
      await seed({'workout_name': 'Push Day', 'status': 'planned', 'type': 'plan'});
      await HiveService.instance.workoutBox.put(
          WorkoutWriteService.wlogKey(date),
          {'type': 'workout_log', 'date': '2026-05-04', 'workout_name': 'Push Day'});
      expect((await mark()).newlyCompleted, isFalse);
    });

    test('the second call on one day: false', () async {
      expect((await mark()).newlyCompleted, isTrue);
      expect((await mark()).newlyCompleted, isFalse);
    });

    test('a failed write: false', () async {
      final r = await WorkoutWriteService.instance.markCompleted(
        date: date,
        workoutName: '  ',
        durationSec: 1800,
      );
      expect(r.success, isFalse);
      expect(r.newlyCompleted, isFalse);
    });

    test('two concurrent calls on one date: exactly one true', () async {
      await seed({'workout_name': 'Push Day', 'status': 'planned', 'type': 'plan'});
      final rs = await Future.wait([mark(), mark()]);
      expect(rs.every((r) => r.success), isTrue);
      expect(rs.where((r) => r.newlyCompleted).length, 1);
    });
  });
}
