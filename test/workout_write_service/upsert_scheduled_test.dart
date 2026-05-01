import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('upsertScheduled writes schedule_<date> and queues sync', () async {
    final date = DateTime(2026, 5, 1);

    final r = await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'workout_name': 'Push Day',
        'status': 'pending',
        'type': 'plan',
        'week': 1,
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': '5-8'},
        ],
      },
      source: WriteSource.planGenerator,
    );
    expect(r.success, isTrue);

    final box = HiveService.instance.workoutBox;
    final stored =
        (box.get(WorkoutWriteService.scheduleKey(date)) as Map)
            .cast<String, dynamic>();
    expect(stored['workout_name'], 'Push Day');
    expect(stored['status'], 'pending');
    expect(stored['exercises'], isA<List>());
    expect(stored['source'], 'plan_generator');
  });

  test('upsertScheduled with status=rest preserves reason field', () async {
    final date = DateTime(2026, 5, 1);

    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'workout_name': 'Rest',
        'status': 'rest',
        'type': 'plan',
        'reason': 'pre_onboarding',
      },
      source: WriteSource.planGenerator,
    );

    final box = HiveService.instance.workoutBox;
    final stored =
        (box.get(WorkoutWriteService.scheduleKey(date)) as Map)
            .cast<String, dynamic>();
    expect(stored['status'], 'rest');
    expect(stored['reason'], 'pre_onboarding');
  });
}
