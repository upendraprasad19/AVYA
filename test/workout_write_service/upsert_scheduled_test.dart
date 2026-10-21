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

  // c3e9a4: the L2 repair migrator tells this benign refusal apart from a real
  // failure by the named message, so the message is part of the contract.
  test('a planGenerator write over a completed day is refused with '
      'completedDayRefusedMessage, and the row is untouched', () async {
    final date = DateTime(2026, 5, 1);
    final box = HiveService.instance.workoutBox;
    final completed = {
      'workout_name': 'Push Day',
      'status': 'completed',
      'type': 'workout',
    };
    await box.put(WorkoutWriteService.scheduleKey(date), completed);

    final r = await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {'workout_name': 'New', 'status': 'planned', 'type': 'workout'},
      source: WriteSource.planGenerator,
    );

    expect(r.success, isFalse);
    expect(r.errorMessage, WorkoutWriteService.completedDayRefusedMessage);
    expect(box.get(WorkoutWriteService.scheduleKey(date)), completed);
  });

  // c3e9a4: ifUnchangedFrom refuses when another writer replaced the row
  // after the caller read it, and writes when the row is the one it read.
  test('ifUnchangedFrom: a row replaced since the read is refused with '
      'rowChangedMessage; the row read is written', () async {
    final date = DateTime(2026, 5, 2);
    final key = WorkoutWriteService.scheduleKey(date);
    final box = HiveService.instance.workoutBox;
    await box.put(key, {'workout_name': 'A', 'status': 'planned'});
    final stale = box.get(key);
    await box.put(key, {'workout_name': 'B', 'status': 'planned'});

    final refused = await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {'workout_name': 'C', 'status': 'planned'},
      source: WriteSource.planGenerator,
      ifUnchangedFrom: stale,
    );

    expect(refused.success, isFalse);
    expect(refused.errorMessage, WorkoutWriteService.rowChangedMessage);
    expect((box.get(key) as Map)['workout_name'], 'B');

    final ok = await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {'workout_name': 'C', 'status': 'planned'},
      source: WriteSource.planGenerator,
      ifUnchangedFrom: box.get(key),
    );

    expect(ok.success, isTrue);
    expect((box.get(key) as Map)['workout_name'], 'C');
  });
}
