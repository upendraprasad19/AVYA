import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

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
}
